#!/usr/bin/env python3
"""OpenAI-compatible image API in front of a running ComfyUI server.

ComfyUI does not natively expose ``/v1/images/generations``. Odysseus's
built-in image-generation tool (mcp_servers/image_gen_server.py) and its
provider/model discovery both speak the OpenAI image API, exactly like the
bundled scripts/diffusion_server.py. This shim bridges the two: it accepts
OpenAI-style requests and drives ComfyUI's prompt-queue API underneath, so
Odysseus needs no changes — you just register this shim as an image provider.

Endpoints:
    GET  /v1/models                -> list checkpoints in ComfyUI
    POST /v1/images/generations    -> {"data": [{"b64_json": "..."}]}
    GET  /health

Usage (run with the Odysseus venv python; it already has fastapi/httpx/uvicorn):
    python scripts/comfyui_openai_bridge.py \
        --comfy-url http://127.0.0.1:8188 \
        --ckpt DreamShaperXL_Turbo_v2_1.safetensors \
        --host 127.0.0.1 --port 8101

The defaults below are tuned for DreamShaper XL Turbo (fast, ~6 steps, low
cfg). For a non-turbo SDXL checkpoint, pass --steps 25 --cfg 7.0.
"""
import argparse
import asyncio
import base64
import json
import logging
import os
import random
import uuid


def _default_comfy_input():
    """Sibling ComfyUI install's input dir (ComfyUI-Zluda for AMD, ComfyUI for
    NVIDIA), relative to this repo — so a fresh clone works without flags."""
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    sib = os.path.dirname(root)
    for name in ("ComfyUI-Zluda", "ComfyUI"):
        cand = os.path.join(sib, name, "input")
        if os.path.isdir(cand):
            return cand
    return os.path.join(sib, "ComfyUI", "input")

import httpx
import uvicorn
from fastapi import FastAPI
from pydantic import BaseModel
from starlette.middleware.trustedhost import TrustedHostMiddleware

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("comfyui_bridge")

_args = None
app = FastAPI(title="ComfyUI OpenAI Bridge")
# Loopback-only by default: this shim is for server-to-server use from the
# Odysseus backend on the same host. Mirrors diffusion_server.py's posture.
app.add_middleware(TrustedHostMiddleware, allowed_hosts=["127.0.0.1", "localhost", "::1"])


class ImageRequest(BaseModel):
    model: str = ""
    prompt: str
    n: int = 1
    size: str = "1024x1024"
    quality: str = "medium"
    response_format: str = "b64_json"
    # Optional pass-throughs (Odysseus doesn't send these today, but harmless):
    negative_prompt: str | None = None
    seed: int | None = None
    # Per-request sampler budget so turbo (~6 steps) and standard SDXL (~30) art
    # styles can coexist behind one bridge. Fall back to launch flags when unset.
    steps: int | None = None
    cfg: float | None = None
    # Regional prompting: [{prompt, x, y, w, h}] paints each subject in its own
    # canvas zone (keeps two characters from bleeding together).
    regions: list | None = None
    # When set (e.g. "meg", "lilly"), condition generation on that character's
    # reference photos via IP-Adapter so the look stays consistent across scenes.
    character: str | None = None


class CharacterReferenceRequest(BaseModel):
    """Promote a generated image to a character's IP-Adapter reference set.

    Odysseus's Character Studio reads the chosen portrait's bytes, base64s them,
    and POSTs them here so the bytes land in ComfyUI's own input dir (this shim
    owns ``characters/``). Writing through the bridge guarantees the folder name
    matches ``_safe_char`` — the same key a later chat photo request resolves."""
    b64: str
    ext: str = "png"
    appearance: str | None = None


_IMG_EXTS = (".png", ".jpg", ".jpeg", ".webp", ".bmp")


def _safe_char(character: str) -> str:
    """Folder-safe character key: alphanumerics plus - and _, lowercased.

    The SAME sanitizer is used everywhere a character maps to its
    ``input/characters/<key>/`` folder — on read (``_pick_reference``,
    ``_character_appearance``) and on write (the reference-upload endpoint) — so
    a name written by Character Studio always resolves to the same folder a chat
    photo request later reads from."""
    return "".join(c for c in (character or "") if c.isalnum() or c in ("-", "_")).lower()


def _pick_reference(character: str):
    """Return the LoadImage-relative path of the best reference photo for a
    character (largest file = usually highest quality), or None if the folder
    has no images. Path is relative to ComfyUI's input dir, e.g.
    'characters/meg/gm6.jpg'."""
    from pathlib import Path as _P
    safe = _safe_char(character)
    if not safe:
        return None
    folder = _P(_args.comfy_input) / "characters" / safe
    if not folder.is_dir():
        return None
    imgs = [p for p in folder.iterdir() if p.suffix.lower() in _IMG_EXTS and p.is_file()]
    if not imgs:
        return None
    best = max(imgs, key=lambda p: p.stat().st_size)
    return f"characters/{safe}/{best.name}"


def _character_appearance(character: str) -> str:
    """Return a fixed physique/appearance anchor for a character, read from
    ``input/characters/<name>/appearance.txt`` (blank lines and ``#`` comments
    ignored, remaining lines joined with commas). PLUS-FACE IP-Adapter only
    encodes the face, so body shape (build, bust, proportions) otherwise drifts
    every image; appending these tokens to every prompt for the character pins
    the body while leaving pose free. Returns "" if the file is absent/empty."""
    from pathlib import Path as _P
    safe = _safe_char(character)
    if not safe:
        return ""
    f = _P(_args.comfy_input) / "characters" / safe / "appearance.txt"
    if not f.is_file():
        return ""
    try:
        lines = [ln.strip() for ln in f.read_text(encoding="utf-8").splitlines()]
    except Exception:
        return ""
    parts = [ln for ln in lines if ln and not ln.startswith("#")]
    return ", ".join(parts)[:300]


def _parse_size(size: str) -> tuple[int, int]:
    try:
        w, h = size.lower().split("x")
        w, h = int(w), int(h)
    except Exception:
        w, h = 1024, 1024
    # SDXL wants multiples of 8; clamp to a sane window.
    w = max(512, min(2048, (w // 8) * 8))
    h = max(512, min(2048, (h // 8) * 8))
    return w, h


def _steps_for_quality(quality: str) -> int:
    base = _args.steps
    return {
        "low": max(2, base - 2),
        "medium": base,
        "high": base + 4,
        "auto": base,
    }.get(quality, base)


def _build_workflow(ckpt: str, prompt: str, negative: str, w: int, h: int,
                    steps: int, seed: int, cfg: float = None) -> dict:
    """Minimal SDXL txt2img graph in ComfyUI API ('prompt') format.

    The 'cudnn' node forces torch.backends.cudnn.enabled=False before sampling.
    ZLUDA's cuDNN path is unreliable on AMD/Windows (conv2d throws
    CUDNN_STATUS_EXECUTION_FAILED); disabling it makes torch fall back to a
    working conv implementation. Routing MODEL through the node keeps it in the
    execution path so it always runs. (CFZ CUDNN Toggle ships with ComfyUI-Zluda.)
    """
    return {
        "ckpt": {
            "class_type": "CheckpointLoaderSimple",
            "inputs": {"ckpt_name": ckpt},
        },
        "cudnn": {
            "class_type": "CUDNNToggleAutoPassthrough",
            "inputs": {"model": ["ckpt", 0], "enable_cudnn": False, "cudnn_benchmark": False},
        },
        "pos": {
            "class_type": "CLIPTextEncode",
            "inputs": {"text": prompt, "clip": ["ckpt", 1]},
        },
        "neg": {
            "class_type": "CLIPTextEncode",
            "inputs": {"text": negative, "clip": ["ckpt", 1]},
        },
        "latent": {
            "class_type": "EmptyLatentImage",
            "inputs": {"width": w, "height": h, "batch_size": 1},
        },
        "sampler": {
            "class_type": "KSampler",
            "inputs": {
                "model": ["cudnn", 0],
                "positive": ["pos", 0],
                "negative": ["neg", 0],
                "latent_image": ["latent", 0],
                "seed": seed,
                "steps": steps,
                "cfg": cfg if cfg is not None else _args.cfg,
                "sampler_name": _args.sampler,
                "scheduler": _args.scheduler,
                "denoise": 1.0,
            },
        },
        "decode": {
            "class_type": "VAEDecode",
            "inputs": {"samples": ["sampler", 0], "vae": ["ckpt", 2]},
        },
        "save": {
            "class_type": "SaveImage",
            "inputs": {"filename_prefix": "odysseus", "images": ["decode", 0]},
        },
    }


def _build_regional_workflow(ckpt: str, regions: list, negative: str, w: int, h: int,
                             steps: int, seed: int, cfg: float = None, base_prompt: str = "") -> dict:
    """Multi-subject SDXL graph: each region gets its own prompt confined to a
    slice of the canvas (ConditioningSetAreaPercentage) and the slices are merged
    (ConditioningCombine). This keeps two characters' looks from bleeding into
    each other — each is painted in its own zone. regions = [{prompt, x, y, w, h}]
    with x/y/w/h as 0..1 fractions of the canvas (default: split left/right).
    base_prompt (the shared scene) is applied full-canvas so both halves share one
    environment instead of two stitched backgrounds."""
    wf = {
        "ckpt": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": ckpt}},
        "cudnn": {"class_type": "CUDNNToggleAutoPassthrough",
                  "inputs": {"model": ["ckpt", 0], "enable_cudnn": False, "cudnn_benchmark": False}},
        "neg": {"class_type": "CLIPTextEncode", "inputs": {"text": negative, "clip": ["ckpt", 1]}},
        "latent": {"class_type": "EmptyLatentImage", "inputs": {"width": w, "height": h, "batch_size": 1}},
    }
    conds = []
    if base_prompt:
        wf["base"] = {"class_type": "CLIPTextEncode", "inputs": {"text": base_prompt, "clip": ["ckpt", 1]}}
        conds.append("base")   # full-canvas: shared scene/background
    for i, r in enumerate(regions):
        enc, area = f"enc{i}", f"area{i}"
        wf[enc] = {"class_type": "CLIPTextEncode", "inputs": {"text": r.get("prompt", ""), "clip": ["ckpt", 1]}}
        wf[area] = {"class_type": "ConditioningSetAreaPercentage", "inputs": {
            "conditioning": [enc, 0],
            "width": float(r.get("w", 0.5)), "height": float(r.get("h", 1.0)),
            "x": float(r.get("x", 0.0)), "y": float(r.get("y", 0.0)), "strength": 1.0}}
        conds.append(area)
    combined = conds[0]
    for i in range(1, len(conds)):
        node = f"comb{i}"
        wf[node] = {"class_type": "ConditioningCombine",
                    "inputs": {"conditioning_1": [combined, 0], "conditioning_2": [conds[i], 0]}}
        combined = node
    wf["sampler"] = {"class_type": "KSampler", "inputs": {
        "model": ["cudnn", 0], "positive": [combined, 0], "negative": ["neg", 0],
        "latent_image": ["latent", 0], "seed": seed, "steps": steps,
        "cfg": cfg if cfg is not None else _args.cfg,
        "sampler_name": _args.sampler, "scheduler": _args.scheduler, "denoise": 1.0}}
    wf["decode"] = {"class_type": "VAEDecode", "inputs": {"samples": ["sampler", 0], "vae": ["ckpt", 2]}}
    wf["save"] = {"class_type": "SaveImage", "inputs": {"filename_prefix": "odysseus", "images": ["decode", 0]}}
    return wf


def _build_ipadapter_workflow(ckpt: str, prompt: str, negative: str, w: int, h: int,
                              steps: int, seed: int, ref_image: str) -> dict:
    """SDXL txt2img conditioned on a character reference photo via IP-Adapter,
    so the same character look is reused for any scene the prompt describes.
    Uses ComfyUI-Zluda's bundled IP-Adapter Plus nodes. cuDNN is forced off
    (same ZLUDA conv2d issue as the plain workflow)."""
    wf = {
        "ckpt": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": ckpt}},
        "cudnn": {"class_type": "CUDNNToggleAutoPassthrough",
                  "inputs": {"model": ["ckpt", 0], "enable_cudnn": False, "cudnn_benchmark": False}},
        "iploader": {"class_type": "IPAdapterUnifiedLoader",
                     "inputs": {"model": ["cudnn", 0], "preset": _args.ip_preset}},
        "refimg": {"class_type": "LoadImage", "inputs": {"image": ref_image}},
        "ipadapter": {"class_type": "IPAdapterAdvanced",
                      "inputs": {"model": ["iploader", 0], "ipadapter": ["iploader", 1],
                                 "image": ["refimg", 0], "weight": _args.ip_weight,
                                 "weight_type": _args.ip_weight_type, "combine_embeds": "average",
                                 "start_at": 0.0, "end_at": _args.ip_end_at, "embeds_scaling": "V only"}},
        "pos": {"class_type": "CLIPTextEncode", "inputs": {"text": prompt, "clip": ["ckpt", 1]}},
        "neg": {"class_type": "CLIPTextEncode", "inputs": {"text": negative, "clip": ["ckpt", 1]}},
        "latent": {"class_type": "EmptyLatentImage", "inputs": {"width": w, "height": h, "batch_size": 1}},
        "sampler": {"class_type": "KSampler",
                    "inputs": {"model": ["ipadapter", 0], "positive": ["pos", 0], "negative": ["neg", 0],
                               "latent_image": ["latent", 0], "seed": seed, "steps": steps,
                               "cfg": _args.cfg, "sampler_name": _args.sampler,
                               "scheduler": _args.scheduler, "denoise": 1.0}},
        "decode": {"class_type": "VAEDecode", "inputs": {"samples": ["sampler", 0], "vae": ["ckpt", 2]}},
    }
    # Optional FaceDetailer pass: detect the face and re-render just that region
    # at high detail using the IP-Adapter-conditioned model, so the sharper face
    # still matches the reference. FaceDetailer's sampler set doesn't include
    # dpmpp_sde, so use euler_ancestral. cuDNN is already forced off globally by
    # the "cudnn" node above, so this extra sampling pass is safe on ZLUDA.
    final = "decode"
    if _args.face_detailer:
        wf["facedet_loader"] = {"class_type": "UltralyticsDetectorProvider",
                                "inputs": {"model_name": "bbox/face_yolov8m.pt"}}
        wf["facedetail"] = {"class_type": "FaceDetailer", "inputs": {
            "image": ["decode", 0], "model": ["ipadapter", 0], "clip": ["ckpt", 1], "vae": ["ckpt", 2],
            "positive": ["pos", 0], "negative": ["neg", 0], "bbox_detector": ["facedet_loader", 0],
            "guide_size": 512.0, "guide_size_for": True, "max_size": 1024.0,
            "seed": seed + 1, "steps": _args.face_detail_steps, "cfg": _args.cfg,
            "sampler_name": "euler_ancestral", "scheduler": "karras", "denoise": _args.face_detail_denoise,
            "feather": 5, "noise_mask": True, "force_inpaint": True,
            "bbox_threshold": 0.5, "bbox_dilation": 10, "bbox_crop_factor": 3.0,
            "sam_detection_hint": "center-1", "sam_dilation": 0, "sam_threshold": 0.93,
            "sam_bbox_expansion": 0, "sam_mask_hint_threshold": 0.7, "sam_mask_hint_use_negative": "False",
            "drop_size": 10, "wildcard": "", "cycle": 1}}
        final = "facedetail"
    wf["save"] = {"class_type": "SaveImage", "inputs": {"filename_prefix": "odysseus", "images": [final, 0]}}
    return wf


async def _resolve_ckpt(client: httpx.AsyncClient, requested: str) -> str:
    """Pick the checkpoint filename ComfyUI should load. Prefer the one the
    caller asked for if ComfyUI actually has it; else fall back to --ckpt;
    else the first checkpoint ComfyUI reports."""
    available = await _list_checkpoints(client)
    if requested and requested in available:
        return requested
    # tolerate name with/without .safetensors
    for a in available:
        if requested and (a == requested or a.split(".")[0] == requested.split(".")[0]):
            return a
    if _args.ckpt and (_args.ckpt in available or not available):
        return _args.ckpt
    return available[0] if available else _args.ckpt


async def _list_checkpoints(client: httpx.AsyncClient) -> list[str]:
    try:
        r = await client.get(f"{_args.comfy_url}/object_info/CheckpointLoaderSimple", timeout=15)
        info = r.json()
        opts = info["CheckpointLoaderSimple"]["input"]["required"]["ckpt_name"][0]
        return list(opts)
    except Exception as e:
        logger.warning("Could not list checkpoints from ComfyUI: %s", e)
        return [_args.ckpt] if _args.ckpt else []


async def _generate_one(client: httpx.AsyncClient, prompt: str, negative: str,
                        w: int, h: int, steps: int, ckpt: str, ref_image: str | None = None,
                        cfg: float = None, regions: list | None = None) -> str:
    """Queue one txt2img job, wait for it, return base64 PNG. regions → multi-
    subject regional prompting; else ref_image → IP-Adapter; else plain txt2img."""
    seed = random.randint(1, 2**63 - 1)
    if regions:
        workflow = _build_regional_workflow(ckpt, regions, negative, w, h, steps, seed, cfg, prompt)
    elif ref_image:
        workflow = _build_ipadapter_workflow(ckpt, prompt, negative, w, h, steps, seed, ref_image)
    else:
        workflow = _build_workflow(ckpt, prompt, negative, w, h, steps, seed, cfg)
    client_id = uuid.uuid4().hex

    resp = await client.post(
        f"{_args.comfy_url}/prompt",
        json={"prompt": workflow, "client_id": client_id},
        timeout=30,
    )
    if resp.status_code != 200:
        raise RuntimeError(f"ComfyUI rejected the workflow ({resp.status_code}): {resp.text[:400]}")
    prompt_id = resp.json()["prompt_id"]
    logger.info("Queued prompt %s (%dx%d, %d steps, seed %d)", prompt_id, w, h, steps, seed)

    # Poll history until the job produces outputs (ZLUDA's first run compiles
    # kernels, which can take a few minutes — hence the generous deadline).
    deadline = _args.timeout
    waited = 0.0
    while waited < deadline:
        await asyncio.sleep(1.0)
        waited += 1.0
        h_resp = await client.get(f"{_args.comfy_url}/history/{prompt_id}", timeout=15)
        hist = h_resp.json()
        entry = hist.get(prompt_id)
        if not entry:
            continue
        status = entry.get("status", {})
        if status.get("status_str") == "error":
            raise RuntimeError(f"ComfyUI execution error: {json.dumps(status)[:400]}")
        outputs = entry.get("outputs", {})
        for node_out in outputs.values():
            for img in node_out.get("images", []):
                img_resp = await client.get(
                    f"{_args.comfy_url}/view",
                    params={
                        "filename": img["filename"],
                        "subfolder": img.get("subfolder", ""),
                        "type": img.get("type", "output"),
                    },
                    timeout=30,
                )
                img_resp.raise_for_status()
                return base64.b64encode(img_resp.content).decode()
    raise TimeoutError(f"ComfyUI did not return an image within {deadline:.0f}s")


@app.get("/v1/models")
async def list_models():
    async with httpx.AsyncClient() as client:
        names = await _list_checkpoints(client)
    if not names:
        names = [_args.ckpt] if _args.ckpt else []
    return {"object": "list", "data": [{"id": n, "object": "model", "owned_by": "comfyui"} for n in names]}


@app.post("/v1/images/generations")
async def generate(req: ImageRequest):
    if not req.prompt:
        return {"error": {"message": "prompt is required"}}
    w, h = _parse_size(req.size)
    # A style may pin its own sampler budget (turbo vs standard SDXL); else the
    # quality→steps curve off the launch default.
    steps = req.steps if req.steps else _steps_for_quality(req.quality)
    cfg = req.cfg  # None → _build_workflow uses _args.cfg
    negative = req.negative_prompt or _args.negative
    n = max(1, min(4, req.n))
    try:
        async with httpx.AsyncClient() as client:
            ckpt = await _resolve_ckpt(client, req.model)
            ref_image = _pick_reference(req.character) if req.character else None
            if req.character and not ref_image:
                logger.warning("character %r has no reference photos in input/characters/; plain generation", req.character)
            elif ref_image:
                logger.info("character %r -> reference %s", req.character, ref_image)
            # Pin body shape: append the character's fixed appearance anchor so
            # build/proportions stay consistent across poses (PLUS-FACE only
            # locks the face).
            prompt = req.prompt
            if req.character:
                appearance = _character_appearance(req.character)
                if appearance:
                    prompt = f"{prompt}, {appearance}"
                    logger.info("character %r -> appearance anchor (%d chars)", req.character, len(appearance))
            data = []
            for _ in range(n):
                b64 = await _generate_one(client, prompt, negative, w, h, steps, ckpt, ref_image, cfg, req.regions)
                data.append({"b64_json": b64})
        return {"created": 0, "data": data}
    except Exception as e:
        logger.exception("generation failed")
        # OpenAI-style error envelope so callers surface a clean message.
        return {"error": {"message": f"{type(e).__name__}: {e}"}}


@app.post("/v1/characters/{name}/reference")
@app.post("/characters/{name}/reference")
async def add_character_reference(name: str, req: CharacterReferenceRequest):
    """Save an image as a character's IP-Adapter reference + appearance anchor.

    Writes ``<comfy_input>/characters/<safe>/<uuid>.<ext>`` and (when provided)
    overwrites ``appearance.txt``. Idempotent per-call: each call adds one more
    reference photo; ``_pick_reference`` later picks the largest. Returns the
    folder key so the caller can store the exact ``character_name`` to use."""
    from pathlib import Path as _P

    safe = _safe_char(name)
    if not safe:
        return {"error": {"message": "invalid character name"}}
    ext = (req.ext or "png").lstrip(".").lower()
    if "." + ext not in _IMG_EXTS:
        ext = "png"
    try:
        raw = base64.b64decode(req.b64)
    except Exception:
        return {"error": {"message": "b64 is not valid base64 image data"}}
    if not raw:
        return {"error": {"message": "empty image payload"}}

    folder = _P(_args.comfy_input) / "characters" / safe
    folder.mkdir(parents=True, exist_ok=True)
    fname = f"{uuid.uuid4().hex[:12]}.{ext}"
    (folder / fname).write_bytes(raw)
    appearance_written = False
    if req.appearance and req.appearance.strip():
        (folder / "appearance.txt").write_text(req.appearance.strip(), encoding="utf-8")
        appearance_written = True
    logger.info("character %r -> saved reference %s (appearance=%s)", safe, fname, appearance_written)
    return {
        "ok": True,
        "character": safe,
        "folder": str(folder),
        "relpath": f"characters/{safe}/{fname}",
        "appearance_written": appearance_written,
    }


@app.get("/health")
async def health():
    ok = False
    try:
        async with httpx.AsyncClient() as client:
            r = await client.get(f"{_args.comfy_url}/system_stats", timeout=5)
            ok = r.status_code == 200
    except Exception:
        ok = False
    return {"status": "ok" if ok else "comfyui_unreachable", "comfy_url": _args.comfy_url, "ckpt": _args.ckpt}


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--comfy-url", default="http://127.0.0.1:8188", help="Base URL of the running ComfyUI server")
    p.add_argument("--ckpt", default="DreamShaperXL_Turbo_v2_1.safetensors", help="Default checkpoint filename")
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=8101)
    # Turbo at 6 steps / CFG 2.0 nailed the subject but ignored secondary
    # attributes ("red scales", "wearing glasses"). 8 steps / CFG 2.8 is the
    # top of turbo's stable range — better adherence for ~+30% gen time.
    p.add_argument("--steps", type=int, default=8, help="Base inference steps (turbo-tuned default)")
    p.add_argument("--cfg", type=float, default=2.8, help="CFG scale (turbo tops out ~3; non-turbo SDXL ~7)")
    p.add_argument("--sampler", default="dpmpp_sde", help="KSampler sampler_name")
    p.add_argument("--scheduler", default="karras", help="KSampler scheduler")
    p.add_argument("--negative", default="lowres, bad anatomy, bad hands, text, watermark, blurry, deformed",
                   help="Default negative prompt")
    p.add_argument("--timeout", type=float, default=420.0, help="Max seconds to wait per image (first ZLUDA run is slow)")
    p.add_argument("--comfy-input",
                   default=os.environ.get("COMFY_INPUT_DIR") or _default_comfy_input(),
                   help="ComfyUI input dir (holds characters/<name>/ reference photos). "
                        "Defaults to the sibling ComfyUI(-Zluda) install; override with COMFY_INPUT_DIR.")
    p.add_argument("--ip-weight", type=float, default=0.62,
                   help="IP-Adapter weight (0..1+). Higher = stronger likeness but copies the reference pose/"
                        "framing more. ~0.6 keeps identity while letting the prompt drive pose; FaceDetailer "
                        "restores face sharpness afterward.")
    p.add_argument("--ip-end-at", type=float, default=0.55,
                   help="Fraction of denoising steps the IP-Adapter stays active (0..1). <1 frees the pose/scene: "
                        "the reference shapes identity early, then the prompt takes over. 1.0 = locked to reference.")
    p.add_argument("--ip-weight-type", default="ease out",
                   help="IPAdapterAdvanced weight schedule. 'ease out' is strong early (identity) then fades "
                        "(pose freedom); 'linear' is constant; 'style transfer' copies look but not composition.")
    p.add_argument("--ip-preset", default="PLUS FACE (portraits)",
                   help="IPAdapterUnifiedLoader preset. 'PLUS FACE (portraits)' locks the face and lets "
                        "the prompt drive scene/outfit (best for consistent character in varied scenes); "
                        "'PLUS (high strength)' transfers the whole reference more strongly.")
    p.add_argument("--no-face-detailer", dest="face_detailer", action="store_false",
                   help="Disable the FaceDetailer high-detail face pass (on by default).")
    p.set_defaults(face_detailer=True)
    p.add_argument("--face-detail-steps", type=int, default=12, help="Steps for the FaceDetailer face pass")
    p.add_argument("--face-detail-denoise", type=float, default=0.45, help="FaceDetailer denoise (0.3-0.5 refines; higher redraws)")
    _args = p.parse_args()
    logger.info("Bridge -> ComfyUI %s | default ckpt %s | %d steps cfg %.1f %s/%s",
                _args.comfy_url, _args.ckpt, _args.steps, _args.cfg, _args.sampler, _args.scheduler)
    uvicorn.run(app, host=_args.host, port=_args.port)
