"""Art styles for image generation — each style is a full SDXL checkpoint that
the ComfyUI bridge loads by filename. Styles the user hasn't installed yet are
downloaded on demand from Hugging Face (a "free style pack"), streamed into the
sibling ComfyUI checkpoints dir with live progress. See the art-style picker in
the studio (per-world) and comfyui_openai_bridge.py (`_resolve_ckpt`).

No new heavy deps: huggingface_hub (already present, for embeddings) resolves the
real checkpoint filename in a repo so a wrong hardcoded name can't break a pull;
httpx (already present) streams the bytes so we get byte-level progress.
"""
import os
import threading
import logging
from typing import Dict, List, Optional

logger = logging.getLogger(__name__)

# Each style: id, human label, one-line vibe, the HF repo to pull from, the
# local checkpoint filename ComfyUI will see, rough download size, and the
# sampler budget that checkpoint wants (turbo checkpoints render in ~6 steps at
# low cfg; standard SDXL needs ~28-30 at cfg 6-7). steps/cfg ride the request so
# turbo and standard styles can coexist behind one bridge.
STYLES: List[Dict] = [
    {
        "id": "artwork", "label": "Painterly Art",
        "desc": "Warm, storybook illustration — the built-in look.",
        "repo": "Lykon/dreamshaper-xl-v2-turbo",
        "ckpt": "DreamShaperXL_Turbo_v2_1.safetensors",
        "size_gb": 6.5, "steps": 7, "cfg": 2.0, "builtin": True,
    },
    {
        "id": "realism", "label": "Realism",
        "desc": "Photoreal — best for slice-of-life and grounded worlds.",
        "repo": "SG161222/RealVisXL_V5.0",
        "ckpt": "RealVisXL_V5.0_fp16.safetensors",
        "size_gb": 6.5, "steps": 30, "cfg": 5.0,
    },
    {
        "id": "fantasy", "label": "High Fantasy",
        "desc": "Painterly fantasy — dragons, myth, epic light.",
        "repo": "cagliostrolab/animagine-xl-3.1",
        "ckpt": "animagine-xl-3.1.safetensors",
        "size_gb": 6.5, "steps": 28, "cfg": 6.0,
    },
    {
        "id": "semireal", "label": "Semi-Real / 3D",
        "desc": "Polished, cinematic — a 3D-animation feel. Great for neon worlds.",
        "repo": "RunDiffusion/Juggernaut-XL-v9",
        "ckpt": "Juggernaut-XL_v9_RunDiffusionPhoto_v2.safetensors",
        "size_gb": 7.0, "steps": 30, "cfg": 5.0,
    },
]

_BY_ID = {s["id"]: s for s in STYLES}

# style_id -> {"state": idle|downloading|done|error, "pct", "mb", "total_mb", "error"}
_PROGRESS: Dict[str, dict] = {}
_LOCK = threading.Lock()


def get_style(style_id: str) -> Optional[dict]:
    return _BY_ID.get(style_id)


def checkpoints_dir() -> Optional[str]:
    """The sibling ComfyUI install's checkpoints dir (ComfyUI-Zluda for AMD,
    ComfyUI for NVIDIA), mirroring the bridge's resolution. None if neither
    install is present (image gen not set up)."""
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    sib = os.path.dirname(here)
    for name in ("ComfyUI-Zluda", "ComfyUI"):
        d = os.path.join(sib, name, "models", "checkpoints")
        if os.path.isdir(d):
            return d
    return None


def _installed_files() -> set:
    d = checkpoints_dir()
    if not d:
        return set()
    try:
        return {f for f in os.listdir(d) if f.endswith(".safetensors")}
    except OSError:
        return set()


def is_installed(style: dict, installed: Optional[set] = None) -> bool:
    files = _installed_files() if installed is None else installed
    if style["ckpt"] in files:
        return True
    # tolerate a slightly different local filename (same stem)
    stem = style["ckpt"].split(".")[0]
    return any(f.split(".")[0] == stem for f in files)


def list_styles() -> List[dict]:
    """Catalog + install/download status for the picker."""
    installed = _installed_files()
    out = []
    for s in STYLES:
        prog = _PROGRESS.get(s["id"], {})
        out.append({
            "id": s["id"], "label": s["label"], "desc": s["desc"],
            "size_gb": s["size_gb"], "installed": is_installed(s, installed),
            "state": prog.get("state", "idle"), "pct": prog.get("pct", 0),
        })
    return out


def resolve_for_generation(style_id: str) -> Optional[dict]:
    """The checkpoint + sampler budget to feed the bridge for this style, or
    None if the style is unknown or not installed (caller falls back to default)."""
    s = _BY_ID.get(style_id)
    if not s or not is_installed(s):
        return None
    return {"ckpt": s["ckpt"], "steps": s["steps"], "cfg": s["cfg"]}


def _resolve_repo_filename(repo: str, preferred: str) -> str:
    """Find the real checkpoint filename in the repo — so a stale hardcoded name
    self-corrects to whatever .safetensors the repo actually ships."""
    from huggingface_hub import HfApi
    files = HfApi().list_repo_files(repo)
    if preferred in files:
        return preferred
    safes = [f for f in files if f.endswith(".safetensors") and "/" not in f]
    # prefer same stem, else an fp16 build, else the first checkpoint
    stem = preferred.split(".")[0]
    for f in safes:
        if f.split(".")[0] == stem:
            return f
    for f in safes:
        if "fp16" in f.lower():
            return f
    if not safes:
        raise FileNotFoundError(f"No .safetensors in {repo}")
    return safes[0]


def start_download(style_id: str) -> dict:
    """Kick off a background download of the style's checkpoint. Idempotent while
    one is running. Returns the current progress record."""
    s = _BY_ID.get(style_id)
    if not s:
        return {"state": "error", "error": "unknown style"}
    dest_dir = checkpoints_dir()
    if not dest_dir:
        return {"state": "error", "error": "ComfyUI is not installed — image generation isn't set up."}
    with _LOCK:
        cur = _PROGRESS.get(style_id)
        if cur and cur.get("state") == "downloading":
            return cur
        if is_installed(s):
            _PROGRESS[style_id] = {"state": "done", "pct": 100}
            return _PROGRESS[style_id]
        _PROGRESS[style_id] = {"state": "downloading", "pct": 0, "mb": 0, "total_mb": 0}
    threading.Thread(target=_download_worker, args=(s, dest_dir), daemon=True).start()
    return _PROGRESS[style_id]


def get_progress(style_id: str) -> dict:
    return _PROGRESS.get(style_id, {"state": "idle", "pct": 0})


def _download_worker(style: dict, dest_dir: str) -> None:
    sid = style["id"]
    tmp = os.path.join(dest_dir, style["ckpt"] + ".incomplete")
    final = os.path.join(dest_dir, style["ckpt"])
    try:
        import httpx
        from huggingface_hub import hf_hub_url
        filename = _resolve_repo_filename(style["repo"], style["ckpt"])
        url = hf_hub_url(repo_id=style["repo"], filename=filename)
        os.makedirs(dest_dir, exist_ok=True)
        with httpx.stream("GET", url, follow_redirects=True, timeout=None) as r:
            r.raise_for_status()
            total = int(r.headers.get("content-length", 0))
            done = 0
            with open(tmp, "wb") as f:
                for chunk in r.iter_bytes(chunk_size=1 << 20):  # 1 MB
                    f.write(chunk)
                    done += len(chunk)
                    _PROGRESS[sid] = {
                        "state": "downloading",
                        "pct": round(done * 100 / total, 1) if total else 0,
                        "mb": done >> 20, "total_mb": total >> 20,
                    }
        os.replace(tmp, final)
        _PROGRESS[sid] = {"state": "done", "pct": 100}
        logger.info("art_styles: downloaded %s → %s", style["id"], final)
    except Exception as e:
        logger.warning("art_styles: download failed for %s: %s", sid, e)
        try:
            if os.path.exists(tmp):
                os.remove(tmp)
        except OSError:
            pass
        _PROGRESS[sid] = {"state": "error", "error": str(e)[:200]}


# ── self-check (no network) ──────────────────────────────────────────────────
if __name__ == "__main__":
    assert len({s["id"] for s in STYLES}) == len(STYLES), "duplicate style id"
    for s in STYLES:
        assert s["ckpt"].endswith(".safetensors")
        assert s["steps"] > 0 and s["cfg"] > 0
    # is_installed against a fake installed set
    fake = {"RealVisXL_V5.0_fp16.safetensors"}
    assert is_installed(_BY_ID["realism"], fake)
    assert not is_installed(_BY_ID["fantasy"], fake)
    # stem tolerance
    assert is_installed(_BY_ID["realism"], {"RealVisXL_V5.0.safetensors"})
    # resolve_for_generation returns None when not installed (no real dir here)
    ls = list_styles()
    assert len(ls) == len(STYLES) and all("installed" in x for x in ls)
    print("art_styles self-check OK — styles:", [s["id"] for s in STYLES],
          "| ckpt dir:", checkpoints_dir())
