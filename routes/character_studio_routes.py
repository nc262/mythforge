"""Character Studio routes — a local, magical fantasy-RPG character creator + chat.

A first-class tool that chains primitives already in Odysseus into one immersive
flow: forge a character (portrait + persona + world), then roleplay with them.

Endpoints (all under /api/characters/studio):
  - generate  → POST: txt2img portrait via the ComfyUI bridge (do_generate_image)
  - describe  → POST: best-effort appearance anchor (prompt + optional vision model)
  - suggest   → POST: per-field AI co-creation (names, traits, backstory, lore, …)
  - save      → POST: promote the chosen portrait to the character's IP-Adapter base
                reference + appearance anchor (via the bridge) AND persist the persona
                template (composed system prompt + world canon + avatar).

The chat itself reuses the existing /api/chat_stream engine: the saved character
becomes an active persona (character_name → IP-Adapter folder), so in-character
replies and on-model selfies work with zero chat-backend changes.
"""

import ast as _pyast
import base64
import json
import logging
import os
import re
import threading
import uuid
from datetime import datetime
from urllib.parse import quote

import httpx
from fastapi import APIRouter, HTTPException, Request

from core.database import SessionLocal, ModelEndpoint
from src.auth_helpers import get_current_user, owner_filter, require_privilege
from src.generated_images import resolve_generated_image_path
from src.ai_interaction import do_generate_image, _resolve_model
from src.llm_core import llm_call_async
from src import party_registry
from src import campaign_memory
from src import art_styles
from routes.gallery_routes import _first_visible_image_endpoint

logger = logging.getLogger(__name__)

# Heuristic for auto-detecting a vision-capable model among configured endpoints'
# cached model lists, when no `vision_model` admin setting is set.
_VISION_RE = re.compile(
    r"llava|bakllava|moondream|minicpm-?v|qwen2\.?5?-?vl|llama-?3\.?2-?vision|-vl\b|vision",
    re.I,
)
# Image-only model ids we must never pick as the text model for suggest/describe.
_IMAGE_MODEL_RE = re.compile(r"gpt-image|dall-?e|stable-?diffusion|sdxl|flux|dreamshaper", re.I)

_MIME_BY_EXT = {
    "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
    "webp": "image/webp", "gif": "image/gif", "bmp": "image/bmp",
}

# Per-field guidance for the co-creation "suggest" sparks. Each returns a small
# list of options the builder renders as click-to-apply chips.
_SUGGEST_SPECS = {
    "name": {
        "n": 6,
        "system": "You invent evocative character names for a fantasy/roleplay app. "
                  "Return ONLY a JSON array of {n} short names (1-3 words each), no numbering, no prose.",
    },
    "personality": {
        "n": 3,
        "system": "You write vivid character personalities for a roleplay app. Return ONLY a JSON "
                  "array of {n} options, each a single rich sentence describing temperament, voice, and quirks.",
    },
    "appearance": {
        "n": 3,
        "system": "You write image-generation prompt fragments describing a character's look. Return ONLY "
                  "a JSON array of {n} options, each comma-separated visual tokens (age, build, hair, eyes, "
                  "attire, vibe). No sentences, no scene.",
    },
    "world": {
        "n": 3,
        "system": "You write short lore/backstory hooks for a roleplay character. Return ONLY a JSON array "
                  "of {n} options, each 1-2 sentences of evocative background, history, or secrets.",
    },
    "setting": {
        "n": 3,
        "system": "You suggest vivid settings/worlds a character inhabits. Return ONLY a JSON array of {n} "
                  "options, each a short phrase (e.g. 'a rain-soaked neon harbor city', 'a sunlit hill-kingdom').",
    },
    "relationship": {
        "n": 3,
        "system": "You suggest how a roleplay character relates to the player. Return ONLY a JSON array of {n} "
                  "options, each a short phrase (e.g. 'your loyal traveling companion', 'a rival you can't quite trust').",
    },
    "scene": {
        "n": 3,
        "system": "You suggest an opening scene for a roleplay. Return ONLY a JSON array of {n} options, each "
                  "one sentence setting the immediate moment (place, time, what's happening right now).",
    },
}


def _appearance_from_prompt(prompt: str) -> str:
    """Prompt-derived appearance anchor — the always-available fallback."""
    return " ".join((prompt or "").split())[:300]


def _merge_appearance(base: str, extra: str) -> str:
    """Merge two comma/space appearance strings, de-duping tokens, capped 300."""
    seen, parts = set(), []
    for chunk in (base or "", extra or ""):
        for tok in (t.strip() for t in chunk.replace("\n", ",").split(",")):
            key = tok.lower()
            if tok and key not in seen:
                seen.add(key)
                parts.append(tok)
    return ", ".join(parts)[:300]


def _compose_system_prompt(name, personality, world, setting, relationship, scene) -> str:
    """Fold the raw persona + world/roleplay fields into one system prompt.

    The chat engine drives entirely off the persona system prompt, so baking the
    world canon in here means roleplay context reaches the model with zero
    chat-backend changes. Raw fields are persisted separately for re-editing."""
    base = (personality or "").strip()
    rp_lines = []
    if (setting or "").strip():
        rp_lines.append(f"- Setting: {setting.strip()}")
    if (relationship or "").strip():
        rp_lines.append(f"- Your relationship to the person you're talking to: {relationship.strip()}")
    if (scene or "").strip():
        rp_lines.append(f"- Current scene: {scene.strip()}")
    lore = (world or "").strip()
    if not rp_lines and not lore:
        return base
    section = f"\n\n# WORLD & ROLEPLAY — canon for {name or 'this character'} (always true; stay in character)\n"
    if rp_lines:
        section += "\n".join(rp_lines) + "\n"
    if lore:
        section += "\n## Lore\n" + lore + "\n"
    return (base + section) if base else section.strip()


def _default_text_model(owner, prefer: str = "") -> str:
    """Resolve a usable text model spec for suggest/describe.

    Prefer the caller-supplied model label (the active picker model); otherwise
    scan enabled endpoints' cached models for the first non-image model."""
    if prefer and not _IMAGE_MODEL_RE.search(prefer):
        return prefer
    db = SessionLocal()
    try:
        q = db.query(ModelEndpoint).filter(ModelEndpoint.is_enabled == True)  # noqa: E712
        if owner:
            q = owner_filter(q, ModelEndpoint, owner)
        for ep in q.all():
            if getattr(ep, "model_type", "") == "image":
                continue
            try:
                ids = json.loads(ep.cached_models or "[]")
            except Exception:
                ids = []
            for mid in ids:
                if mid and not _IMAGE_MODEL_RE.search(mid):
                    return mid
    finally:
        db.close()
    return prefer or ""


_SIZE_RE = re.compile(r"(\d+(?:\.\d+)?)\s*b\b", re.I)   # "8b", "7B", "1.5b"


def _model_size(mid: str) -> float:
    """Param count (billions) parsed from a model id, or a large sentinel when
    unknown — so size-unaware ids never win the 'smallest' race."""
    m = _SIZE_RE.search(mid or "")
    return float(m.group(1)) if m else 999.0


def _extractor_model(owner, prefer: str = "") -> str:
    """Pick a model for the background structured-extraction calls (memory,
    codex, quests, snapshot). These run often and only need to emit a small
    JSON object — json_mode already guarantees the format — so routing them to
    a fast small model keeps play snappy while the heavy model is reserved for
    narration. Order: admin `studio_fast_model` pin → most capable enabled text
    model that still fits the 3–9B fast window → fall back to the normal
    default. We take the largest in-window model (e.g. an 8B over a 3B) for the
    best extraction quality that's still quick; a 14B narration model stays out
    of the window so it isn't used here."""
    try:
        from src.settings import get_setting
        pinned = (get_setting("studio_fast_model", "") or "").strip()
    except Exception:
        pinned = ""
    if pinned:
        return pinned
    best, best_sz = None, None
    db = SessionLocal()
    try:
        q = db.query(ModelEndpoint).filter(ModelEndpoint.is_enabled == True)  # noqa: E712
        if owner:
            q = owner_filter(q, ModelEndpoint, owner)
        for ep in q.all():
            if getattr(ep, "model_type", "") == "image":
                continue
            try:
                ids = json.loads(ep.cached_models or "[]")
            except Exception:
                ids = []
            for mid in ids:
                if not mid or _IMAGE_MODEL_RE.search(mid):
                    continue
                sz = _model_size(mid)
                # 3–9B: big enough to extract reliably, small enough to be fast.
                # Prefer the largest in-window model for better extraction.
                if 3.0 <= sz <= 9.0 and (best_sz is None or sz > best_sz):
                    best, best_sz = mid, sz
    finally:
        db.close()
    return best or _default_text_model(owner, prefer)


def _find_vision_model(owner) -> str:
    """Resolve a vision model spec: admin `vision_model` setting, else auto-detect."""
    try:
        from src.settings import get_setting
        explicit = (get_setting("vision_model", "") or "").strip()
    except Exception:
        explicit = ""
    if explicit:
        return explicit
    db = SessionLocal()
    try:
        q = db.query(ModelEndpoint).filter(ModelEndpoint.is_enabled == True)  # noqa: E712
        if owner:
            q = owner_filter(q, ModelEndpoint, owner)
        for ep in q.all():
            try:
                ids = json.loads(ep.cached_models or "[]")
            except Exception:
                ids = []
            for mid in ids:
                if mid and _VISION_RE.search(mid):
                    return mid
    finally:
        db.close()
    return ""


async def _vision_describe(filename: str, owner) -> str:
    """Run a vision model over the chosen portrait; return a short physique/appearance
    fragment. Raises on any failure so the caller falls back to the prompt anchor."""
    img_path = resolve_generated_image_path(filename)
    ext = filename.rsplit(".", 1)[-1].lower()
    mime = _MIME_BY_EXT.get(ext, "image/png")
    b64 = base64.b64encode(img_path.read_bytes()).decode()
    data_uri = f"data:{mime};base64,{b64}"

    model_spec = _find_vision_model(owner)
    if not model_spec:
        raise RuntimeError("no vision model configured")
    url, model_id, headers = _resolve_model(model_spec, owner=owner)
    messages = [
        {"role": "system", "content": (
            "You describe a character's fixed physical appearance for an image-generation "
            "anchor. Output ONLY comma-separated visual tokens: age range, build/physique, "
            "hair (color/length/style), eye color, skin tone, and other stable features. "
            "No scene, pose, clothing, lighting, or sentences. Max 30 words."
        )},
        {"role": "user", "content": [
            {"type": "text", "text": "Describe this character's stable appearance:"},
            {"type": "image_url", "image_url": {"url": data_uri}},
        ]},
    ]
    out = await llm_call_async(url, model_id, messages, temperature=0.2, max_tokens=120, headers=headers)
    return " ".join((out or "").replace("\n", " ").split())[:300]


def _parse_suggestion_list(raw: str, limit: int) -> list:
    """Pull a list of suggestions out of an LLM reply. Prefers a JSON array;
    falls back to splitting lines / bullets so a chatty model still works."""
    text = (raw or "").strip()
    # Try a fenced or bare JSON array first.
    m = re.search(r"\[.*\]", text, re.S)
    if m:
        try:
            arr = json.loads(m.group(0))
            out = [str(x).strip(" \t\"'-•") for x in arr if str(x).strip()]
            if out:
                return out[:limit]
        except Exception:
            pass
    # Fallback: line/bullet split.
    lines = [re.sub(r"^\s*(?:\d+[.)]|[-*•])\s*", "", ln).strip(" \t\"'") for ln in text.splitlines()]
    out = [ln for ln in lines if ln]
    return out[:limit]


def _parse_json_object(raw: str) -> dict:
    """Extract the first {...} JSON object from an LLM reply; {} on failure."""
    text = (raw or "").strip()
    m = re.search(r"\{.*\}", text, re.S)
    if m:
        try:
            obj = json.loads(m.group(0))
            return obj if isinstance(obj, dict) else {}
        except Exception:
            pass
    return {}


_WS_LOCK = threading.Lock()   # serializes read-modify-write on the world-state file


def setup_character_studio_routes(preset_manager) -> APIRouter:
    # Snapshots live beside presets.json so they share the user's data dir.
    def _snapshots_path():
        return os.path.join(os.path.dirname(preset_manager.presets_file), "studio_snapshots.json")

    def _load_snapshots():
        p = _snapshots_path()
        if not os.path.exists(p):
            return []
        try:
            with open(p, encoding="utf-8") as f:
                data = json.load(f)
            return data if isinstance(data, list) else []
        except Exception:
            return []

    def _save_snapshots(snaps):
        p = _snapshots_path()
        tmp = p + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(snaps, f, indent=2)
        os.replace(tmp, p)

    # ── Durable world state ─────────────────────────────────────────────────
    # The studio's per-story memory/codex/quests/combat/sheet/etc. used to live
    # only in the browser's localStorage. We persist it server-side too so a
    # story survives a cache wipe and follows the user across devices. Shape:
    #   { "<owner>": { "<character_id>": { "<kind>": <blob>, ... } } }
    # The client treats the server as the source of truth on load and pushes
    # each save back here. Writes are serialized (read-modify-write the whole
    # file) so concurrent kind-saves can't clobber each other.
    _WS_KINDS = {"mem", "codex", "quests", "combat", "sheet", "gm", "notes", "bmap", "inv", "clock", "world", "rel", "cworlds", "cstories", "artstyle"}

    def _world_state_path():
        return os.path.join(os.path.dirname(preset_manager.presets_file), "studio_world_state.json")

    # Pinpoint campaign memory (§4.C) lives beside the world state. Keyed per
    # adventure and shared across a party (resolve onto the host's cid), the same
    # way world state is.
    def _mem_dir():
        return os.path.join(os.path.dirname(preset_manager.presets_file), "studio_memory")

    def _mem_key(user, cid):
        owner = party_registry.resolve_shared_cid(user, cid) or user
        return f"{owner}__{cid}"

    def _load_world_state():
        p = _world_state_path()
        if not os.path.exists(p):
            return {}
        try:
            with open(p, encoding="utf-8") as f:
                data = json.load(f)
            return data if isinstance(data, dict) else {}
        except Exception:
            return {}

    def _save_world_state(state):
        p = _world_state_path()
        tmp = p + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(state, f, indent=2)
        os.replace(tmp, p)

    router = APIRouter(tags=["character-studio"])

    @router.post("/api/characters/studio/generate")
    async def studio_generate(request: Request):
        """Generate one portrait. Passing `character` conditions on an already-saved
        base so iterating after a save stays on-model."""
        user = require_privilege(request, "can_generate_images")
        data = await request.json()
        prompt = " ".join((data.get("prompt") or "").split())
        if not prompt:
            raise HTTPException(400, "prompt is required")
        size = (data.get("size") or "1024x1024").strip()
        character = (data.get("character") or "").strip() or None
        # Art style → a specific checkpoint + its sampler budget (turbo vs
        # standard SDXL). Line 2 of content is the model the bridge loads; when
        # the style isn't installed we fall through to the bridge's default.
        style = art_styles.resolve_for_generation((data.get("style") or "").strip())
        ckpt = style["ckpt"] if style else ""
        content = f"{prompt}\n{ckpt}\n{size}"
        result = await do_generate_image(
            content, session_id=None, owner=user, character=character,
            steps=(style["steps"] if style else None),
            cfg=(style["cfg"] if style else None),
        )
        if result.get("error"):
            raise HTTPException(502, result["error"])
        image_url = result.get("image_url", "")
        filename = image_url.rsplit("/", 1)[-1] if image_url else ""
        return {
            "ok": True,
            "image_url": image_url,
            "filename": filename,
            "image_prompt": result.get("image_prompt", prompt),
        }

    @router.post("/api/characters/studio/describe")
    async def studio_describe(request: Request):
        """Best-effort appearance anchor: vision-model description merged onto the
        prompt-derived fallback, or just the fallback when no vision model exists."""
        user = get_current_user(request)
        data = await request.json()
        filename = (data.get("filename") or "").strip()
        prompt = data.get("prompt") or ""
        appearance = _appearance_from_prompt(prompt)
        vision_used = False
        if filename:
            try:
                vision = await _vision_describe(filename, owner=user)
                if vision:
                    appearance = _merge_appearance(vision, appearance)
                    vision_used = True
            except Exception as e:
                logger.info("Character Studio vision describe skipped: %s", e)
        return {"ok": True, "appearance": appearance[:300], "vision_used": vision_used}

    @router.post("/api/characters/studio/suggest")
    async def studio_suggest(request: Request):
        """Per-field AI co-creation. Returns a small list of click-to-apply options."""
        user = get_current_user(request)
        data = await request.json()
        field = (data.get("field") or "").strip().lower()
        spec = _SUGGEST_SPECS.get(field)
        if not spec:
            raise HTTPException(400, f"unknown field '{field}'")
        name = (data.get("name") or "").strip()
        context = (data.get("context") or "").strip()
        model_spec = _default_text_model(user, (data.get("model") or "").strip())
        if not model_spec:
            raise HTTPException(400, "No text model available for suggestions.")
        try:
            url, model_id, headers = _resolve_model(model_spec, owner=user)
        except ValueError:
            raise HTTPException(400, f"Could not resolve a model for suggestions ('{model_spec}').")

        user_ctx = ""
        if name:
            user_ctx += f"Character name: {name}\n"
        if context:
            user_ctx += f"What we know so far:\n{context}\n"
        user_ctx += f"Give {spec['n']} fresh options."
        messages = [
            {"role": "system", "content": spec["system"].format(n=spec["n"])},
            {"role": "user", "content": user_ctx},
        ]
        try:
            raw = await llm_call_async(url, model_id, messages, temperature=1.0, max_tokens=400, headers=headers)
        except Exception as e:
            logger.warning("Studio suggest failed: %s", e)
            raise HTTPException(502, "Suggestion generation failed.")
        suggestions = _parse_suggestion_list(raw, spec["n"])
        return {"ok": True, "field": field, "suggestions": suggestions}

    @router.post("/api/characters/studio/activate")
    async def studio_activate(request: Request):
        """Make a saved character the active persona for chat (sets the `custom`
        preset). Kept out of the admin-gated /api/presets/custom path so entering a
        roleplay works for any signed-in user; the persona's character_name drives
        the in-chat photo trigger + IP-Adapter reference."""
        get_current_user(request)  # auth enforced by middleware
        data = await request.json()
        cid = (data.get("id") or "").strip()
        cname = (data.get("name") or "").strip()
        templates = preset_manager.get_user_templates() or []
        tmpl = next((t for t in templates if t.get("id") == cid), None) \
            or next((t for t in templates if (t.get("name") or "").lower() == cname.lower()), None)
        if not tmpl:
            raise HTTPException(404, "Character not found")
        ok = preset_manager.update_custom(
            float(tmpl.get("temperature", 1.0) or 1.0),
            int(tmpl.get("max_tokens", 0) or 0),
            tmpl.get("system_prompt", "") or "",
            tmpl.get("name", "") or "",
            True, "", "",
        )
        if not ok:
            raise HTTPException(500, "Failed to activate character")
        return {"ok": True, "name": tmpl.get("name", ""), "character_name": tmpl.get("name", "")}

    @router.post("/api/characters/studio/save")
    async def studio_save(request: Request):
        """Promote the chosen portrait to the character's IP-Adapter base reference +
        appearance anchor (via the bridge) and persist the persona (with world canon)."""
        user = require_privilege(request, "can_generate_images")
        data = await request.json()
        name = (data.get("name") or "").strip()
        if not name:
            raise HTTPException(400, "name is required")
        filename = (data.get("image_filename") or "").strip()
        appearance = (data.get("appearance") or "").strip()
        # Raw persona + world fields (back-compat: accept system_prompt as personality).
        personality = (data.get("personality") or data.get("system_prompt") or "").strip()
        world = (data.get("world") or "").strip()
        setting = (data.get("setting") or "").strip()
        relationship = (data.get("relationship") or "").strip()
        scene = (data.get("scene") or "").strip()
        try:
            temperature = float(data.get("temperature", 1.0))
        except (TypeError, ValueError):
            temperature = 1.0
        try:
            max_tokens = int(data.get("max_tokens", 0))
        except (TypeError, ValueError):
            max_tokens = 0

        system_prompt = _compose_system_prompt(name, personality, world, setting, relationship, scene)

        image_url = ""
        reference = None
        if filename:
            img_path = resolve_generated_image_path(filename)
            b64 = base64.b64encode(img_path.read_bytes()).decode()
            ext = filename.rsplit(".", 1)[-1].lower()
            image_url = f"/api/generated-image/{filename}"
            db = SessionLocal()
            try:
                ep = _first_visible_image_endpoint(db, user)
            finally:
                db.close()
            if not ep:
                raise HTTPException(400, "No image endpoint configured to store the character reference.")
            base_url = ep.base_url.rstrip("/")
            if not base_url.endswith("/v1"):
                base_url += "/v1"
            ref_url = f"{base_url}/characters/{quote(name, safe='')}/reference"
            try:
                async with httpx.AsyncClient(timeout=60) as client:
                    resp = await client.post(
                        ref_url, json={"b64": b64, "ext": ext, "appearance": appearance}
                    )
            except Exception as e:
                raise HTTPException(502, f"Could not reach the image bridge to save the reference: {e}")
            if resp.status_code != 200:
                raise HTTPException(502, f"Failed to save character reference ({resp.status_code})")
            rj = resp.json()
            if isinstance(rj.get("error"), dict):
                raise HTTPException(502, rj["error"].get("message", "reference save failed"))
            reference = rj

        tmpl_id = (data.get("id") or "").strip() or f"user-{uuid.uuid4().hex[:8]}"
        # Ownership: characters and adventures belong to whoever forged them.
        # Nobody overwrites someone else's by reusing an id.
        existing = next((t for t in preset_manager.get_user_templates() if t.get("id") == tmpl_id), None)
        if existing and existing.get("owner") and existing.get("owner") != user:
            raise HTTPException(403, "That character belongs to another player.")
        template = {
            "id": tmpl_id,
            "owner": (existing or {}).get("owner") or user,
            "name": name,
            "system_prompt": system_prompt,
            "temperature": max(0.0, min(2.0, temperature)),
            "max_tokens": max_tokens if 0 <= max_tokens <= 8192 else 0,
            "character_name": name,
            "avatar": image_url,
            "appearance": appearance,
            # Raw fields so the Forge can reload + re-edit a character.
            "personality": personality,
            "world": world,
            "setting": setting,
            "relationship": relationship,
            "scene": scene,
            "world_id": (data.get("world_id") or "").strip(),
        }
        if not preset_manager.save_user_template(template):
            raise HTTPException(500, "Failed to save persona template")
        return {"ok": True, "template": template, "reference": reference}

    @router.post("/api/characters/studio/snapshot")
    async def studio_snapshot(request: Request):
        """Save-point: summarize the session into a titled story-so-far + a
        world-state delta ('how the world changed'), timestamped and persisted."""
        user = get_current_user(request)
        data = await request.json()
        cid = (data.get("character_id") or "").strip()
        cname = (data.get("character_name") or "").strip() or "the character"
        world_id = (data.get("world_id") or "").strip()
        transcript = data.get("transcript") or []
        if not isinstance(transcript, list) or not transcript:
            raise HTTPException(400, "Nothing to snapshot yet.")

        lines = []
        for m in transcript[-60:]:
            content = (m.get("content") or "").strip()
            if not content:
                continue
            # Drop bracketed meta/framing lines (DM kickoff, play-as tags).
            content = re.sub(r"^\[[^\]]*\]\s*", "", content)
            who = cname if m.get("role") == "assistant" else "Player"
            lines.append(f"{who}: {content}")
        convo = "\n".join(lines)[:8000]

        title = story_so_far = world_changes = ""
        model_spec = _extractor_model(user, (data.get("model") or "").strip())
        if model_spec and convo:
            try:
                url, model_id, headers = _resolve_model(model_spec, owner=user)
                messages = [
                    {"role": "system", "content": (
                        "You turn an in-progress roleplay/story session into a save-point. "
                        "Return ONLY a JSON object with keys: "
                        "\"title\" (an evocative chapter title, <=6 words), "
                        "\"story_so_far\" (a 2-4 sentence recap of what has happened), "
                        "\"world_changes\" (a short markdown bullet list of how the world, "
                        "relationships, or situation have CHANGED, plus any open threads). "
                        "No text outside the JSON."
                    )},
                    {"role": "user", "content": f"Session with {cname}:\n\n{convo}"},
                ]
                raw = await llm_call_async(url, model_id, messages, temperature=0.4, max_tokens=600, headers=headers, json_mode=True, num_ctx=8192)
                parsed = _parse_json_object(raw)
                title = str(parsed.get("title") or "").strip()
                story_so_far = str(parsed.get("story_so_far") or "").strip()
                wc = parsed.get("world_changes")
                if isinstance(wc, list):
                    world_changes = "\n".join(f"- {str(x).strip().lstrip('- ')}" for x in wc if str(x).strip())
                else:
                    world_changes = str(wc or "").strip()
            except Exception as e:
                logger.warning("Snapshot summarize failed: %s", e)

        if not title:
            title = f"{cname} — save point"
        snap = {
            "id": uuid.uuid4().hex[:12],
            "character_id": cid, "character_name": cname, "world_id": world_id,
            "title": title, "story_so_far": story_so_far, "world_changes": world_changes,
            "message_count": len(transcript),
            "created_at": datetime.utcnow().isoformat() + "Z",
            "owner": user or "",
        }
        snaps = _load_snapshots()
        snaps.append(snap)
        _save_snapshots(snaps)
        return {"ok": True, "snapshot": snap}

    @router.post("/api/characters/studio/memory")
    async def studio_memory(request: Request):
        """Maintain a living campaign memory: merge the latest events into the
        existing memory and return a tight running summary + durable key facts.
        The client injects this back into the GM's context so long stories stay
        consistent (NPCs, places, choices, items, open threads)."""
        user = get_current_user(request)
        data = await request.json()
        cname = (data.get("character_name") or "the story").strip()
        transcript = data.get("transcript") or []
        current = (data.get("memory") or "").strip()
        if not isinstance(transcript, list) or not transcript:
            raise HTTPException(400, "nothing to remember yet")
        lines = []
        for m in transcript[-44:]:
            content = (m.get("content") or "").strip()
            if not content:
                continue
            content = re.sub(r"^\[[^\]]*\]\s*", "", content)
            who = cname if m.get("role") == "assistant" else "Player"
            lines.append(f"{who}: {content}")
        convo = "\n".join(lines)[:7000]
        model_spec = _extractor_model(user, (data.get("model") or "").strip())
        if not model_spec:
            raise HTTPException(400, "No text model available.")
        try:
            url, model_id, headers = _resolve_model(model_spec, owner=user)
        except ValueError:
            raise HTTPException(400, "Could not resolve a model.")
        messages = [
            {"role": "system", "content": (
                "You maintain a living campaign memory for an ongoing roleplay adventure. "
                "Given the EXISTING memory and the LATEST events, output ONLY a JSON object with keys: "
                "\"summary\" (a tight 3-5 sentence running recap of the whole story so far) and "
                "\"facts\" (an array of short, durable fact strings — named NPCs met with a one-line note, "
                "locations, the player's key choices and relationships, important items, and open threads/quests). "
                "Merge new information with the existing memory; keep at most ~15 facts; never drop something important; "
                "prefer specifics and names. No text outside the JSON."
            )},
            {"role": "user", "content": f"Existing memory:\n{current or '(none yet)'}\n\nLatest events:\n{convo}"},
        ]
        try:
            raw = await llm_call_async(url, model_id, messages, temperature=0.3, max_tokens=700, headers=headers, json_mode=True, num_ctx=8192)
        except Exception as e:
            logger.warning("Memory update failed: %s", e)
            raise HTTPException(502, "Memory update failed.")
        parsed = _parse_json_object(raw)
        summary = str(parsed.get("summary") or "").strip()
        facts = parsed.get("facts")
        facts = [str(x).strip() for x in facts if str(x).strip()][:20] if isinstance(facts, list) else []
        return {"ok": True, "summary": summary, "facts": facts}

    # ── Pinpoint campaign memory (§4.C) ──────────────────────────────────────
    # Store a story beat (embedded) and recall the most relevant past beats for
    # the current moment. This replaces the LLM-summary memory above for the
    # GM's automatic recall — no per-turn LLM call, so no 502 under model load.
    @router.post("/api/characters/studio/memory/beat")
    async def studio_memory_beat(request: Request):
        user = get_current_user(request)
        data = await request.json()
        cid = (data.get("cid") or "").strip()
        text = (data.get("text") or "").strip()
        if not cid or not text:
            raise HTTPException(400, "cid and text required")
        ok = campaign_memory.add_beat(
            _mem_dir(), _mem_key(user, cid), text,
            day=int(data.get("day") or 0), tags=data.get("tags") or [],
        )
        return {"ok": ok}

    @router.post("/api/characters/studio/memory/recall")
    async def studio_memory_recall(request: Request):
        user = get_current_user(request)
        data = await request.json()
        cid = (data.get("cid") or "").strip()
        query = (data.get("query") or "").strip()
        if not cid:
            raise HTTPException(400, "cid required")
        beats = campaign_memory.recall(
            _mem_dir(), _mem_key(user, cid), query, k=int(data.get("k") or 5),
        )
        return {"ok": True, "beats": beats}

    # ── Art styles (§ picker) ────────────────────────────────────────────────
    # Each style is a full SDXL checkpoint the ComfyUI bridge loads by name;
    # un-installed styles download on demand from Hugging Face. The world stores
    # its chosen style (world-state kind "artstyle"); generation threads the
    # matching checkpoint + sampler budget into do_generate_image.
    @router.get("/api/characters/studio/art-styles")
    async def studio_art_styles(request: Request):
        get_current_user(request)
        return {"ok": True, "styles": art_styles.list_styles()}

    @router.post("/api/characters/studio/art-styles/download")
    async def studio_art_style_download(request: Request):
        get_current_user(request)
        data = await request.json()
        style_id = (data.get("id") or "").strip()
        prog = art_styles.start_download(style_id)
        return {"ok": prog.get("state") != "error", "id": style_id, "progress": prog}

    @router.get("/api/characters/studio/art-styles/progress/{style_id}")
    async def studio_art_style_progress(request: Request, style_id: str):
        get_current_user(request)
        return {"ok": True, "id": style_id, "progress": art_styles.get_progress(style_id)}

    @router.post("/api/characters/studio/codex")
    async def studio_codex(request: Request):
        """Maintain a cast codex: the named NPCs the player has met, each with a
        role, a disposition toward the player (ally→hostile), a one-line memory,
        and a short appearance anchor for a portrait. The client injects this back
        into the GM's context so recurring characters stay consistent and react to
        the relationship the player has actually built with them."""
        user = get_current_user(request)
        data = await request.json()
        cname = (data.get("character_name") or "the story").strip()
        transcript = data.get("transcript") or []
        current = data.get("codex") or []
        if not isinstance(transcript, list) or not transcript:
            raise HTTPException(400, "nothing to chronicle yet")
        lines = []
        for m in transcript[-44:]:
            content = (m.get("content") or "").strip()
            if not content:
                continue
            content = re.sub(r"^\[[^\]]*\]\s*", "", content)
            who = cname if m.get("role") == "assistant" else "Player"
            lines.append(f"{who}: {content}")
        convo = "\n".join(lines)[:7000]
        existing = "; ".join(
            f"{n.get('name')} ({n.get('role', '')}, {n.get('disposition', 'neutral')}): {n.get('note', '')}"
            + (f" [wants: {n.get('goal')}]" if n.get("goal") else "")
            for n in current if isinstance(n, dict) and n.get("name")
        ) or "(none yet)"
        model_spec = _extractor_model(user, (data.get("model") or "").strip())
        if not model_spec:
            raise HTTPException(400, "No text model available.")
        try:
            url, model_id, headers = _resolve_model(model_spec, owner=user)
        except ValueError:
            raise HTTPException(400, "Could not resolve a model.")
        messages = [
            {"role": "system", "content": (
                "You maintain a cast codex of non-player characters the player has MET in an ongoing roleplay. "
                "Given the EXISTING codex and the LATEST events, output ONLY a JSON object with key \"npcs\": an array of objects, "
                "each with: \"name\" (the NPC's name), \"role\" (a 2-4 word title or role), "
                "\"disposition\" (exactly one of: ally, friendly, neutral, wary, hostile — toward the player), "
                "\"note\" (one sentence: who they are and the current state of their relationship with the player), "
                "\"goal\" (one short phrase: what this character currently wants or is trying to achieve — their own agenda, which may have nothing to do with the player), "
                "and \"appearance\" (a short comma-separated visual description suitable for a character portrait). "
                "Include ONLY named characters the player has actually encountered. Merge with the existing codex — "
                "update dispositions, notes, and goals as things shift; keep at most 12; never invent characters not in the story. "
                "No text outside the JSON."
            )},
            {"role": "user", "content": f"Existing codex:\n{existing}\n\nLatest events:\n{convo}"},
        ]
        try:
            raw = await llm_call_async(url, model_id, messages, temperature=0.3, max_tokens=900, headers=headers, json_mode=True, num_ctx=8192)
        except Exception as e:
            logger.warning("Codex update failed: %s", e)
            raise HTTPException(502, "Codex update failed.")
        parsed = _parse_json_object(raw)
        npcs = parsed.get("npcs")
        valid_disp = {"ally", "friendly", "neutral", "wary", "hostile"}
        out = []
        if isinstance(npcs, list):
            for n in npcs:
                if not isinstance(n, dict):
                    continue
                name = str(n.get("name") or "").strip()
                if not name:
                    continue
                disp = str(n.get("disposition") or "neutral").strip().lower()
                if disp not in valid_disp:
                    disp = "neutral"
                out.append({
                    "name": name[:60],
                    "role": str(n.get("role") or "").strip()[:60],
                    "disposition": disp,
                    "note": str(n.get("note") or "").strip()[:240],
                    "goal": str(n.get("goal") or "").strip()[:160],
                    "appearance": str(n.get("appearance") or "").strip()[:240],
                })
                if len(out) >= 12:
                    break
        return {"ok": True, "npcs": out}

    @router.post("/api/characters/studio/quests")
    async def studio_quests(request: Request):
        """Maintain a quest log: the goals, missions, and promises the player has
        taken on, each with a one-line objective and an active/done status. The
        client injects active quests into the GM's context so the story stays
        goal-directed and the GM can resolve threads it set up."""
        user = get_current_user(request)
        data = await request.json()
        cname = (data.get("character_name") or "the story").strip()
        transcript = data.get("transcript") or []
        current = data.get("quests") or []
        if not isinstance(transcript, list) or not transcript:
            raise HTTPException(400, "nothing to chronicle yet")
        lines = []
        for m in transcript[-44:]:
            content = (m.get("content") or "").strip()
            if not content:
                continue
            content = re.sub(r"^\[[^\]]*\]\s*", "", content)
            who = cname if m.get("role") == "assistant" else "Player"
            lines.append(f"{who}: {content}")
        convo = "\n".join(lines)[:7000]
        existing = "; ".join(
            f"{q.get('title')} [{q.get('status', 'active')}]: {q.get('desc', '')}"
            for q in current if isinstance(q, dict) and q.get("title")
        ) or "(none yet)"
        model_spec = _extractor_model(user, (data.get("model") or "").strip())
        if not model_spec:
            raise HTTPException(400, "No text model available.")
        try:
            url, model_id, headers = _resolve_model(model_spec, owner=user)
        except ValueError:
            raise HTTPException(400, "Could not resolve a model.")
        messages = [
            {"role": "system", "content": (
                "You maintain a quest log for an ongoing roleplay adventure. "
                "Given the EXISTING quests and the LATEST events, output ONLY a JSON object with key \"quests\": an array of objects, "
                "each with: \"title\" (a short quest name), \"desc\" (one sentence on the objective and its current state), "
                "and \"status\" (exactly one of: active, done). "
                "Track goals, missions, and promises the player has taken on. Mark a quest \"done\" when it is clearly resolved. "
                "Merge with the existing quests; keep at most 10; never invent quests the story does not imply. "
                "No text outside the JSON."
            )},
            {"role": "user", "content": f"Existing quests:\n{existing}\n\nLatest events:\n{convo}"},
        ]
        try:
            raw = await llm_call_async(url, model_id, messages, temperature=0.3, max_tokens=800, headers=headers, json_mode=True, num_ctx=8192)
        except Exception as e:
            logger.warning("Quest update failed: %s", e)
            raise HTTPException(502, "Quest update failed.")
        parsed = _parse_json_object(raw)
        quests = parsed.get("quests")
        out = []
        if isinstance(quests, list):
            for q in quests:
                if not isinstance(q, dict):
                    continue
                title = str(q.get("title") or "").strip()
                if not title:
                    continue
                status = str(q.get("status") or "active").strip().lower()
                if status not in ("active", "done"):
                    status = "active"
                out.append({
                    "title": title[:80],
                    "desc": str(q.get("desc") or "").strip()[:240],
                    "status": status,
                })
                if len(out) >= 10:
                    break
        return {"ok": True, "quests": out}

    @router.post("/api/characters/studio/worldsmith")
    async def studio_worldsmith(request: Request):
        """Co-create a world or a campaign with the AI. mode='world' expands a
        one-line idea into a full playable world (lore, cast, campaigns,
        locations, backdrop prompt); mode='story' crafts one campaign for an
        existing world. Constrained-JSON like the other extractors, but routed
        to the default (larger) text model — this is creative writing."""
        user = get_current_user(request)
        data = await request.json()
        idea = (data.get("idea") or "").strip()
        mode = (data.get("mode") or "world").strip()
        if not idea:
            raise HTTPException(400, "Describe the world or story you want.")
        # The fast extractor model, asked for SMALL bites: one giant schema
        # makes small models drop sections and big models crawl (CPU spill).
        # Two focused calls - the world's core, then its people & threats -
        # finish in about a minute total and come back complete.
        model_spec = _extractor_model(user, (data.get("model") or "").strip())
        if not model_spec:
            raise HTTPException(400, "No text model available.")
        try:
            url, model_id, headers = _resolve_model(model_spec, owner=user)
        except ValueError:
            raise HTTPException(400, "Could not resolve a model.")

        async def _ask(sys_prompt: str, user_prompt: str, max_tok: int, must: list):
            """One constrained-JSON call, with a single stern retry when the
            model omits required list sections. max_retries=1 keeps a slow box
            from silently multiplying the 120s budget."""
            last = {}
            for attempt in range(2):
                u = user_prompt if not attempt else (
                    user_prompt + "\n\nIMPORTANT: your previous answer omitted required sections. "
                    "Include ALL required keys with non-empty values this time."
                )
                try:
                    raw = await llm_call_async(url, model_id, [
                        {"role": "system", "content": sys_prompt},
                        {"role": "user", "content": u},
                    ], temperature=0.85, max_tokens=max_tok, headers=headers,
                        json_mode=True, num_ctx=8192, timeout=120, max_retries=1)
                except Exception as e:
                    logger.warning("Worldsmith call failed: %s", e)
                    raise HTTPException(502, "The worldsmith could not answer.")
                last = _parse_json_object(raw)
                if not must or all(isinstance(last.get(k), (list, dict)) and last.get(k) for k in must):
                    return last
            return last

        if mode == "story":
            w = data.get("world") or {}
            parsed = await _ask(
                "You craft campaign premises for a tabletop-style roleplay adventure. "
                "Given the world and the player's idea, output ONLY a JSON object with keys: "
                '"title" (a short evocative campaign name), '
                '"premise" (2-3 sentences: the situation, the stakes, the hook - written to entice), and '
                '"hook" (one vivid sentence describing the exact opening scene the GM sets, present tense). '
                "Fit the world's tone. No text outside the JSON.",
                f"World: {w.get('name', 'an original world')} - {w.get('kind', '')}. "
                f"{(w.get('lore') or '')[:600]}\n\nThe player wants a campaign about: {idea[:800]}",
                500, [])
        else:
            prior = data.get("prior") if isinstance(data.get("prior"), dict) else None
            # Guided-forge pillars (magic system, tech level, era, beasts, tone)
            # from the structured form — folded into every generation call.
            _f = data.get("fields") if isinstance(data.get("fields"), dict) else {}
            pillars = "; ".join(
                f"{k}: {str(v).strip()[:120]}" for k, v in _f.items()
                if isinstance(v, str) and v.strip()
            )[:600]
            pillar_line = f"\nWorld pillars the player chose — honor ALL of them: {pillars}" if pillars else ""
            sys_core = (
                "You design original worlds for a tabletop-style roleplay adventure game. "
                "Output ONLY a JSON object with keys: "
                '"name" (short world name), "kind" (2-4 word genre label), '
                '"tagline" (one enticing sentence), '
                '"lore" (3-4 sentences establishing the world, its feel, and what adventurers do there), '
                '"backdrop" (an image-generation prompt for an empty atmospheric establishing scene, no people), and '
                '"locations" (5-7 objects: "name", "kind" (one of: tavern, shop, landmark, wilds, home), '
                '"lore" (one sentence), optional "shop" (what it trades, only for shops/taverns)). '
                "Be specific and flavorful, never generic. No text outside the JSON."
            )
            if prior and prior.get("name"):
                core_slice = {k: prior.get(k) for k in ("name", "kind", "tagline", "lore", "backdrop", "locations")}
                usr_core = ("Current world core as JSON:\n" + json.dumps(core_slice)[:2000]
                            + f"\n\nRevise it per these instructions, keeping everything not mentioned: {idea[:800]}\n"
                            "Output the FULL revised JSON in the same schema.")
            else:
                usr_core = f"The player wants a world like this: {idea[:1000]}{pillar_line}"
            core = await _ask(sys_core, usr_core, 800, ["locations"])
            if not (isinstance(core.get("locations"), list) and core["locations"]):
                # No map, no vendors, no travel — locations are load-bearing, so
                # they get their own small call when the core drops them.
                try:
                    lc = await _ask(
                        "You invent locations for a tabletop roleplay world. "
                        'Output ONLY a JSON object with key "locations" (exactly 6 objects: '
                        '"name", "kind" (one of: tavern, shop, landmark, wilds, home), '
                        '"lore" (one sentence), optional "shop" (what it trades, only for shops/taverns)). '
                        "At least one tavern and one shop. No text outside the JSON.",
                        f"The world: {str(core.get('name') or idea[:80])} - {str(core.get('kind') or '')}. "
                        f"{str(core.get('lore') or '')[:500]}{pillar_line}\nInvent its 6 key locations.",
                        600, ["locations"])
                    if lc.get("locations"):
                        core["locations"] = lc["locations"]
                except HTTPException:
                    pass  # the atlas can still grow from play

            # Refinement revises the full prior (incl. creatures) in one call;
            # a fresh forge keeps this call SMALL (cast + stories only) — the
            # bestiary gets its own dedicated call below. Smaller asks are the
            # difference between a complete answer and dropped sections on 3B.
            refining = bool(prior and prior.get("name"))
            _life_creatures_schema = (
                ', and "creatures" (exactly 3 setting-specific threats: "name", "tier" (one of: minor, standard, dire), '
                '"desc" (1-2 sentences), "weakness" (one sentence - how a clever hero beats it), '
                '"tactics" (one sentence - how it fights), "art" (an image-generation prompt for it))'
            ) if refining else ""
            sys_life = (
                "You populate a tabletop roleplay world with people and campaigns. "
                "Output ONLY a JSON object with keys: "
                '"cast" (exactly 3 objects: "name", "role", "appearance" (an image-gen portrait prompt), '
                "\"persona\" (2-3 sentences of second-person system-prompt: 'You are ...' voice, personality, how they speak)), "
                'and "stories" (exactly 2 objects: "title", "premise" (2-3 sentences), "hook" (one vivid opening-scene sentence))'
                + _life_creatures_schema + ". "
                "Be specific and flavorful, never generic. No text outside the JSON."
            )
            core_name = str(core.get("name") or (prior or {}).get("name") or "the world")
            core_lore = str(core.get("lore") or (prior or {}).get("lore") or "")[:600]
            if prior and prior.get("name"):
                life_slice = {k: prior.get(k) for k in ("cast", "stories", "creatures")}
                usr_life = (f"The world: {core_name}. {core_lore}\n"
                            "Current people & threats as JSON:\n" + json.dumps(life_slice)[:2200]
                            + f"\n\nRevise them per these instructions, keeping everything not mentioned: {idea[:800]}\n"
                            "Output the FULL revised JSON in the same schema.")
            else:
                usr_life = (f"The world: {core_name} - {str(core.get('kind') or '')}. {core_lore}\n"
                            f"The player's original idea: {idea[:600]}{pillar_line}\n"
                            "Invent its cast, campaigns, and creatures.")
            life = await _ask(sys_life, usr_life, 1000,
                              ["cast", "stories"] + (["creatures"] if refining else []))
            parsed = {**core, **life}
            if not (isinstance(parsed.get("stories"), list) and parsed["stories"]):
                # The stories section is the one the model drops most — give it
                # its own tiny call rather than shipping a world with no campaigns.
                try:
                    st = await _ask(
                        "You craft campaign premises for a tabletop roleplay world. "
                        'Output ONLY a JSON object with key "stories" (exactly 2 objects: '
                        '"title", "premise" (2-3 sentences: situation, stakes, hook), '
                        '"hook" (one vivid sentence describing the exact opening scene)). '
                        "No text outside the JSON.",
                        f"The world: {str(core.get('name') or '')} - {str(core.get('kind') or '')}. "
                        f"{str(core.get('lore') or '')[:500]}{pillar_line}\nInvent its 2 launch campaigns.",
                        500, ["stories"])
                    if st.get("stories"):
                        parsed["stories"] = st["stories"]
                except HTTPException:
                    pass  # campaigns can still be crafted later in-world

            if refining:
                # Refinement revises the prior's creatures via life above;
                # the class reskins carry through untouched.
                if isinstance(prior.get("reskins"), dict):
                    parsed["reskins"] = prior["reskins"]
            else:
                # Fresh forge: two more focused calls give the world its OWN
                # bestiary depth and its own names for the standard classes.
                known = ", ".join(
                    str(c.get("name")) for c in (life.get("creatures") or [])
                    if isinstance(c, dict) and c.get("name")
                )[:200]
                sys_beasts = (
                    "You invent monsters for a tabletop roleplay world. "
                    'Output ONLY a JSON object with key "creatures" (exactly 6 objects: '
                    '"name", "tier" (one of: minor, standard, dire), "desc" (1-2 sentences), '
                    '"weakness" (one sentence - how a clever hero beats it), '
                    '"tactics" (one sentence - how it fights), '
                    '"art" (an image-generation prompt for it)). '
                    "Vary the tiers. Every creature must belong to THIS world specifically, never generic fantasy filler. "
                    "No text outside the JSON."
                )
                usr_beasts = (f"The world: {core_name} - {str(core.get('kind') or '')}. {core_lore}{pillar_line}\n"
                              f"Threats already known: {known or 'none yet'}.\n"
                              "Invent 6 MORE distinct creatures for its bestiary.")
                try:
                    beasts = await _ask(sys_beasts, usr_beasts, 900, ["creatures"])
                    parsed["creatures"] = (life.get("creatures") or []) + (beasts.get("creatures") or [])
                except HTTPException:
                    pass  # the 3 from the life call still stand

                sys_rsk = (
                    "You translate the standard adventurer classes into a specific world's own language. "
                    'Output ONLY a JSON object with keys: '
                    '"flavor" (1-2 sentences: how supernatural power manifests in this world - the GM will describe ALL casting this way), '
                    '"slots" (a 1-3 word world-specific term for spell slots), and '
                    '"names" (an object mapping EVERY one of these to a 1-3 word world-specific title: '
                    "Fighter, Barbarian, Rogue, Ranger, Monk, Paladin, Wizard, Sorcerer, Cleric, Druid, Bard, Warlock). "
                    "No text outside the JSON."
                )
                usr_rsk = f"The world: {core_name} - {str(core.get('kind') or '')}. {core_lore}{pillar_line}"
                try:
                    parsed["reskins"] = await _ask(sys_rsk, usr_rsk, 500, ["names"])
                except HTTPException:
                    pass  # classic class names are a fine fallback

        def _clean(v):
            """Small models sometimes emit a field as a repr'd dict/list
            ("{'prompt': '…'}") instead of a plain string — unwrap those."""
            v = str(v or "").strip()
            if v[:2] in ("{'", "['", '{"', '["'):
                try:
                    obj = _pyast.literal_eval(v)
                    if isinstance(obj, dict):
                        for x in obj.values():
                            if isinstance(x, str) and x.strip():
                                return x.strip()
                    if isinstance(obj, (list, tuple)):
                        return " ".join(str(x) for x in obj if isinstance(x, str)).strip()
                except Exception:
                    pass
            return v

        if mode == "story":
            title = _clean(parsed.get("title"))
            if not title:
                raise HTTPException(502, "The worldsmith returned nothing usable.")
            return {"ok": True, "story": {
                "title": title[:80],
                "premise": _clean(parsed.get("premise"))[:500],
                "hook": _clean(parsed.get("hook"))[:300],
            }}
        name = _clean(parsed.get("name"))
        if not name:
            raise HTTPException(502, "The worldsmith returned nothing usable.")
        def _cast(items):
            out = []
            for c in (items if isinstance(items, list) else [])[:4]:
                if isinstance(c, dict) and c.get("name"):
                    out.append({
                        "name": _clean(c["name"])[:60],
                        "role": _clean(c.get("role"))[:80],
                        "appearance": _clean(c.get("appearance"))[:300],
                        "persona": _clean(c.get("persona"))[:600],
                    })
            return out
        def _stories(items):
            out = []
            for s in (items if isinstance(items, list) else [])[:3]:
                if isinstance(s, dict) and s.get("title"):
                    out.append({
                        "title": _clean(s["title"])[:80],
                        "premise": _clean(s.get("premise"))[:500],
                        "hook": _clean(s.get("hook"))[:300],
                    })
            return out
        def _locs(items):
            out = []
            for p in (items if isinstance(items, list) else [])[:8]:
                if isinstance(p, dict) and p.get("name"):
                    kind = _clean(p.get("kind") or "landmark").lower()
                    if kind not in ("tavern", "shop", "landmark", "wilds", "home"):
                        kind = "landmark"
                    loc = {"name": _clean(p["name"])[:60], "kind": kind,
                           "lore": _clean(p.get("lore"))[:200]}
                    if p.get("shop"):
                        loc["shop"] = _clean(p["shop"])[:120]
                    elif kind == "shop":
                        loc["shop"] = "odds & ends"     # every shop trades in SOMETHING
                    elif kind == "tavern":
                        loc["shop"] = "food & drink"
                    out.append(loc)
            return out
        def _creatures(items):
            out = []
            for c in (items if isinstance(items, list) else [])[:12]:
                if isinstance(c, dict) and c.get("name"):
                    tier = _clean(c.get("tier") or "standard").lower()
                    if tier not in ("minor", "standard", "dire"):
                        tier = "standard"
                    out.append({
                        "name": _clean(c["name"])[:60], "tier": tier,
                        "desc": _clean(c.get("desc"))[:300],
                        "weakness": _clean(c.get("weakness"))[:200],
                        "tactics": _clean(c.get("tactics"))[:200],
                        "art": _clean(c.get("art"))[:300],
                    })
            return out
        def _reskins(obj):
            """World-specific class names. Requires most of the 12 classes to be
            renamed sensibly, else return None and the classic register stands."""
            if not isinstance(obj, dict) or not isinstance(obj.get("names"), dict):
                return None
            classes = ["Fighter", "Barbarian", "Rogue", "Ranger", "Monk", "Paladin",
                       "Wizard", "Sorcerer", "Cleric", "Druid", "Bard", "Warlock"]
            clean = {}
            for c in classes:
                v = obj["names"].get(c)
                if isinstance(v, str) and v.strip():
                    nm = _clean(v).strip("-—–_* ").strip()
                    if nm:
                        clean[c] = nm[:40]
            if len(clean) < 8:
                return None
            return {"flavor": _clean(obj.get("flavor"))[:400],
                    "slots": _clean(obj.get("slots"))[:40],
                    "names": clean}
        return {"ok": True, "world": {
            "name": name[:60],
            "kind": (_clean(parsed.get("kind")) or "Adventure")[:40],
            "tagline": _clean(parsed.get("tagline"))[:160],
            "lore": _clean(parsed.get("lore"))[:1200],
            "backdrop": _clean(parsed.get("backdrop"))[:400],
            "cast": _cast(parsed.get("cast")),
            "stories": _stories(parsed.get("stories")),
            "locations": _locs(parsed.get("locations")),
            "creatures": _creatures(parsed.get("creatures")),
            "reskins": _reskins(parsed.get("reskins")),
        }}

    @router.post("/api/characters/studio/worldtick")
    async def studio_worldtick(request: Request):
        """Advance the living world between days. Given the active quests, the
        NPCs' own goals, and the story so far, return a few small, concrete
        things that plausibly happened OFF-SCREEN while the player was busy —
        driven by NPC agendas and open threads, not by the player. The client
        shows these as a 'Meanwhile…' aside and folds them into memory."""
        user = get_current_user(request)
        data = await request.json()
        quests = data.get("quests") or []
        codex = data.get("codex") or []
        memory = (data.get("memory") or "").strip()
        day = data.get("day")
        active_q = "; ".join(
            q.get("title", "") for q in quests if isinstance(q, dict) and q.get("status") != "done" and q.get("title")
        ) or "(none)"
        goals = "; ".join(
            f"{n.get('name')} wants {n.get('goal')}"
            for n in codex if isinstance(n, dict) and n.get("name") and n.get("goal")
        ) or "(no known agendas)"
        if active_q == "(none)" and goals == "(no known agendas)":
            return {"ok": True, "events": []}   # nothing in motion yet — skip the call
        model_spec = _extractor_model(user, (data.get("model") or "").strip())
        if not model_spec:
            raise HTTPException(400, "No text model available.")
        try:
            url, model_id, headers = _resolve_model(model_spec, owner=user)
        except ValueError:
            raise HTTPException(400, "Could not resolve a model.")
        messages = [
            {"role": "system", "content": (
                "You simulate a living world between scenes in an ongoing roleplay. A day has passed off-screen. "
                "Given the story so far, the open quests, and what each NPC WANTS, output ONLY a JSON object with keys: "
                "\"events\" (an array of 1 to 3 short, concrete developments that plausibly happened while the player was elsewhere — "
                "each driven by an NPC pursuing their goal or by an open thread progressing; small and reactive like a rumor, a rival's move, "
                "or a quiet change in town, NOT major plot twists, and NEVER acting for the player; one sentence each) "
                "and \"newQuest\" (either null, or — only if these developments naturally create a fresh opportunity or threat the player "
                "could choose to pursue — an object {\"title\": short name, \"desc\": one-sentence hook}). "
                "No text outside the JSON."
            )},
            {"role": "user", "content": f"Story so far:\n{memory or '(just beginning)'}\n\nOpen quests: {active_q}\n\nNPC agendas: {goals}\n\nA new day (day {day or '?'}) has dawned. What happened off-screen?"},
        ]
        try:
            raw = await llm_call_async(url, model_id, messages, temperature=0.7, max_tokens=480, headers=headers, json_mode=True, num_ctx=8192)
        except Exception as e:
            logger.warning("World tick failed: %s", e)
            raise HTTPException(502, "World tick failed.")
        parsed = _parse_json_object(raw)
        events = parsed.get("events")
        out = []
        if isinstance(events, list):
            for ev in events:
                s = str(ev).strip()
                if s:
                    out.append(s[:240])
                if len(out) >= 3:
                    break
        new_quest = None
        nq = parsed.get("newQuest")
        if isinstance(nq, dict) and str(nq.get("title") or "").strip():
            new_quest = {"title": str(nq.get("title")).strip()[:80], "desc": str(nq.get("desc") or "").strip()[:240]}
        return {"ok": True, "events": out, "newQuest": new_quest}

    @router.post("/api/characters/studio/worldstate")
    async def studio_worldstate(request: Request):
        """Track the realm itself: the places the player has been and the factions
        at work, each with a short note and current state/standing. Injected into
        the GM's context so the world stays geographically and politically
        consistent, and evolved over time by the world-tick."""
        user = get_current_user(request)
        data = await request.json()
        cname = (data.get("character_name") or "the story").strip()
        transcript = data.get("transcript") or []
        current = data.get("world") or {}
        if not isinstance(transcript, list) or not transcript:
            raise HTTPException(400, "nothing to chronicle yet")
        lines = []
        for m in transcript[-44:]:
            content = (m.get("content") or "").strip()
            if not content:
                continue
            content = re.sub(r"^\[[^\]]*\]\s*", "", content)
            who = cname if m.get("role") == "assistant" else "Player"
            lines.append(f"{who}: {content}")
        convo = "\n".join(lines)[:7000]
        cur_places = "; ".join(f"{p.get('name')}: {p.get('note', '')}" for p in (current.get("places") or []) if isinstance(p, dict) and p.get("name")) or "(none yet)"
        cur_factions = "; ".join(f"{f.get('name')} ({f.get('standing', 'neutral')}): {f.get('note', '')}" for f in (current.get("factions") or []) if isinstance(f, dict) and f.get("name")) or "(none yet)"
        model_spec = _extractor_model(user, (data.get("model") or "").strip())
        if not model_spec:
            raise HTTPException(400, "No text model available.")
        try:
            url, model_id, headers = _resolve_model(model_spec, owner=user)
        except ValueError:
            raise HTTPException(400, "Could not resolve a model.")
        messages = [
            {"role": "system", "content": (
                "You maintain the world gazetteer for an ongoing roleplay. Given the EXISTING world and the LATEST events, "
                "output ONLY a JSON object with two keys: "
                "\"places\" (an array of {\"name\", \"note\" (one sentence on what it is and its current state)}) and "
                "\"factions\" (an array of {\"name\", \"standing\" (one of: allied, friendly, neutral, wary, hostile — toward the player), "
                "\"note\" (one sentence on who they are and what they're doing)}). "
                "Include ONLY places the player has visited or heard of and factions/groups that have appeared. Merge with the existing world; "
                "update notes and standings as things change; keep at most 8 places and 8 factions; never invent things the story doesn't imply. "
                "No text outside the JSON."
            )},
            {"role": "user", "content": f"Existing places: {cur_places}\nExisting factions: {cur_factions}\n\nLatest events:\n{convo}"},
        ]
        try:
            raw = await llm_call_async(url, model_id, messages, temperature=0.3, max_tokens=900, headers=headers, json_mode=True, num_ctx=8192)
        except Exception as e:
            logger.warning("World-state update failed: %s", e)
            raise HTTPException(502, "World-state update failed.")
        parsed = _parse_json_object(raw)
        valid_standing = {"allied", "friendly", "neutral", "wary", "hostile"}
        places = []
        for p in (parsed.get("places") or []):
            if isinstance(p, dict) and str(p.get("name") or "").strip():
                places.append({"name": str(p.get("name")).strip()[:60], "note": str(p.get("note") or "").strip()[:240]})
            if len(places) >= 8:
                break
        factions = []
        for f in (parsed.get("factions") or []):
            if isinstance(f, dict) and str(f.get("name") or "").strip():
                st = str(f.get("standing") or "neutral").strip().lower()
                if st not in valid_standing:
                    st = "neutral"
                factions.append({"name": str(f.get("name")).strip()[:60], "standing": st, "note": str(f.get("note") or "").strip()[:240]})
            if len(factions) >= 8:
                break
        return {"ok": True, "places": places, "factions": factions}

    @router.get("/api/characters/studio/state/{character_id}")
    async def studio_get_state(request: Request, character_id: str):
        """Return all persisted world-state kinds for one character. Party
        members resolve onto the HOST's campaign blob — one shared world."""
        user = get_current_user(request)
        owner = party_registry.resolve_shared_cid(user, character_id) or user
        state = _load_world_state()
        blob = (state.get(owner) or {}).get(character_id) or {}
        return {"ok": True, "state": blob}

    @router.put("/api/characters/studio/state/{character_id}/{kind}")
    async def studio_put_state(request: Request, character_id: str, kind: str):
        """Upsert one world-state kind for one character. Serialized so a save
        of one kind can't drop a concurrent save of another. Party members
        write to the host's blob (last write wins, same as the host's own
        multi-tab behavior)."""
        user = get_current_user(request)
        owner = party_registry.resolve_shared_cid(user, character_id) or user
        if kind not in _WS_KINDS:
            raise HTTPException(400, f"unknown state kind '{kind}'")
        data = await request.json()
        value = data.get("value")
        with _WS_LOCK:
            state = _load_world_state()
            state.setdefault(owner, {}).setdefault(character_id, {})[kind] = value
            _save_world_state(state)
        return {"ok": True}

    # ── Shared parties: play one campaign together ───────────────────────────
    @router.post("/api/characters/studio/party/create")
    async def party_create(request: Request):
        """Host opens their table: returns the join code for a campaign."""
        user = get_current_user(request)
        data = await request.json()
        cid = (data.get("cid") or "").strip()
        sid = (data.get("sid") or "").strip()
        if not cid or not sid:
            raise HTTPException(400, "cid and sid required")
        p = party_registry.create_party(user, cid, sid, (data.get("name") or "").strip()[:80],
                                        (data.get("world_id") or "").strip())
        return {"ok": True, "code": p["code"], "members": p.get("members") or {}}

    @router.post("/api/characters/studio/party/join")
    async def party_join(request: Request):
        """A friend sits down: joins by code, and their hero is written into
        the host's party (a guest hero — the GM already treats those as
        player-run, not NPCs)."""
        user = get_current_user(request)
        data = await request.json()
        code = (data.get("code") or "").strip().upper()
        hero = (data.get("hero") or "").strip()[:40] or user
        cls = (data.get("cls") or "Fighter").strip()[:20]
        p = party_registry.join_party(code, user, hero, cls)
        if not p:
            raise HTTPException(404, "No table with that code.")
        # Seat the hero in the host's sheet (companions list) if not already there.
        with _WS_LOCK:
            state = _load_world_state()
            sheet = state.setdefault(p["host"], {}).setdefault(p["cid"], {}).get("sheet") or {}
            comps = sheet.setdefault("companions", [])
            if not any((c.get("name") or "").lower() == hero.lower() for c in comps):
                level = sheet.get("level") or 1
                hit_die = {"Fighter": 10, "Barbarian": 12, "Ranger": 10, "Paladin": 10}.get(cls, 8)
                hp = hit_die + 2 * level
                comps.append({"name": hero, "role": "guest hero", "cls": cls, "level": level,
                              "ac": 14 if hit_die >= 10 else 12, "hpMax": hp, "hp": hp,
                              "guest": True, "player": user})
                state[p["host"]][p["cid"]]["sheet"] = sheet
                _save_world_state(state)
        return {"ok": True, "code": p["code"], "cid": p["cid"], "sid": p["sid"],
                "name": p.get("name") or "", "world_id": p.get("world_id") or "",
                "host": p["host"], "hero": hero}

    @router.get("/api/characters/studio/party/mine")
    async def party_mine(request: Request):
        """Tables I host or sit at — for the title screen's rejoin list."""
        user = get_current_user(request)
        out = []
        for p in party_registry.parties_for(user):
            out.append({"code": p["code"], "name": p.get("name") or "", "cid": p["cid"],
                        "sid": p["sid"], "world_id": p.get("world_id") or "",
                        "host": p["host"], "role": "host" if p["host"] == user else "guest",
                        "hero": ((p.get("members") or {}).get(user) or {}).get("hero") or "",
                        "members": [{"user": u, **m} for u, m in (p.get("members") or {}).items()]})
        return {"ok": True, "parties": out}

    @router.get("/api/characters/studio/party/state")
    async def party_state(request: Request, code: str):
        """The poll: who's at the table, and is someone talking to the GM?"""
        user = get_current_user(request)
        p = party_registry.get_party(code)
        if not p or (p["host"] != user and user not in (p.get("members") or {})):
            raise HTTPException(404, "No table with that code.")
        busy = party_registry.get_busy(p)
        return {"ok": True,
                "members": [{"user": u, **m} for u, m in (p.get("members") or {}).items()],
                "host": p["host"], "busy": busy}

    @router.post("/api/characters/studio/party/busy")
    async def party_busy(request: Request):
        """The table lock — set when you start a turn, cleared when the GM
        finishes answering you. Best-effort; stale locks expire server-side."""
        user = get_current_user(request)
        data = await request.json()
        p = party_registry.get_party((data.get("code") or ""))
        if not p or (p["host"] != user and user not in (p.get("members") or {})):
            raise HTTPException(404, "No table with that code.")
        party_registry.set_busy(p["code"], user, bool(data.get("busy")))
        return {"ok": True}

    # ── Party voice chat: WebRTC signaling relay ─────────────────────────────
    # Voice itself is peer-to-peer over the tailnet; the server only ferries
    # the tiny offer/answer/ICE envelopes. In-memory, best-effort — a lost
    # signal just means the client re-offers on its next poll.
    _voice_signals: dict = {}   # code -> {username: [ {from, data}, ... ]}

    def _party_member(p, user):
        return bool(p) and (p["host"] == user or user in (p.get("members") or {}))

    @router.post("/api/characters/studio/party/signal")
    async def party_signal(request: Request):
        user = get_current_user(request)
        data = await request.json()
        p = party_registry.get_party((data.get("code") or ""))
        if not _party_member(p, user):
            raise HTTPException(404, "No table with that code.")
        to = str(data.get("to") or "").strip()
        if not to or not _party_member(p, to):
            raise HTTPException(400, "Signal needs a recipient at this table.")
        q = _voice_signals.setdefault(p["code"], {}).setdefault(to, [])
        q.append({"from": user, "data": data.get("data")})
        del q[:-64]   # ponytail: bounded queue, oldest dropped
        return {"ok": True}

    @router.get("/api/characters/studio/party/signal")
    async def party_signal_poll(request: Request, code: str):
        user = get_current_user(request)
        p = party_registry.get_party(code)
        if not _party_member(p, user):
            raise HTTPException(404, "No table with that code.")
        msgs = _voice_signals.get(p["code"], {}).pop(user, [])
        return {"ok": True, "signals": msgs}

    @router.get("/api/characters/studio/snapshots")
    async def studio_snapshots(request: Request, character_id: str = ""):
        """List saved snapshots (optionally for one character), newest first."""
        user = get_current_user(request)
        snaps = _load_snapshots()
        out = [
            s for s in snaps
            if (not character_id or s.get("character_id") == character_id)
            and (not s.get("owner") or s.get("owner") == user)
        ]
        out.sort(key=lambda s: s.get("created_at", ""), reverse=True)
        return {"ok": True, "snapshots": out}

    return router
