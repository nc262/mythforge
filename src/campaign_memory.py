"""Pinpoint campaign memory — a per-adventure beat store with embedding recall.

Replaces the LLM-summary memory (which 502'd under local-model load): each beat
is embedded via the provider's own endpoint (Ollama `all-minilm`, or the
FastEmbed fallback that `get_embedding_client()` already handles) and recalled
with numpy cosine search — no ChromaDB, no per-turn LLM call. Recall is ~10-15ms.
See EXTRACTION.md §4.C.

Storage, per memory key, beside presets.json in `studio_memory/`:
  <key>.json  — list of {text, day, tags, i}
  <key>.npy   — (N, dim) float32 matrix of L2-normalized beat embeddings (row i)

If no embedding backend is reachable, add_beat/recall degrade to no-ops — the
studio keeps its user-editable Key Facts, it just loses automatic recall.
"""
import os
import re
import json
import logging
import threading
from typing import List, Dict, Optional

import numpy as np

logger = logging.getLogger(__name__)

# ponytail: one global lock — beats are written once per GM turn, so contention
# is nil. Go per-key only if concurrent multi-campaign write throughput matters.
_LOCK = threading.RLock()

_client = None
_client_tried = False


def _embed(texts: List[str]) -> Optional[np.ndarray]:
    """Encode texts to L2-normalized row vectors, or None if no embedder is up.

    The client is resolved once per process; if it's unavailable we latch that
    so every later turn skips the (already-latched) connect probe cheaply.
    """
    global _client, _client_tried
    if not texts:
        return None
    if _client is None:
        if _client_tried:
            return None
        _client_tried = True
        try:
            from src.embeddings import get_embedding_client
            _client = get_embedding_client()
        except Exception as e:
            logger.warning("campaign_memory: no embedding backend (%s); recall disabled", e)
            return None
    try:
        return _client.encode(texts)  # (N, dim), L2-normalized
    except Exception as e:
        logger.warning("campaign_memory: embed failed (%s)", e)
        return None


def _safe(key: str) -> str:
    return re.sub(r"[^A-Za-z0-9_-]", "_", key or "")[:120] or "_"


def _paths(mem_dir: str, key: str):
    base = os.path.join(mem_dir, _safe(key))
    return base + ".json", base + ".npy"


def add_beat(mem_dir: str, key: str, text: str, day: int = 0, tags: Optional[list] = None) -> bool:
    """Embed and append one beat. Returns False if there's nothing to store, no
    embedder, or the beat duplicates the immediately preceding one (regenerate /
    double-send)."""
    text = (text or "").strip()
    if not text:
        return False
    vec = _embed([text])
    if vec is None or vec.size == 0:
        return False
    row = vec.astype("float32")  # (1, dim)
    meta_p, vec_p = _paths(mem_dir, key)
    with _LOCK:
        os.makedirs(mem_dir, exist_ok=True)
        metas = _read_metas(meta_p)
        mat = _read_mat(vec_p)
        # Model changed mid-campaign (different dim) → start a fresh matrix
        # rather than crash on vstack; old beats become unsearchable, which is
        # the honest outcome of a model swap.
        if mat is not None and mat.size and mat.shape[1] != row.shape[1]:
            mat, metas = None, []
        # Skip a near-identical repeat of the last beat.
        if mat is not None and mat.shape[0] and float(mat[-1] @ row[0]) > 0.97:
            return False
        mat = row if (mat is None or mat.size == 0) else np.vstack([mat, row])
        metas.append({"text": text[:1200], "day": int(day or 0), "tags": tags or [], "i": len(metas)})
        _atomic_save_npy(vec_p, mat)
        _atomic_save_json(meta_p, metas)
    return True


def recall(mem_dir: str, key: str, query: str, k: int = 5, min_score: float = 0.15) -> List[Dict]:
    """Return up to k beats most similar to `query`, most-relevant first.

    `min_score` floors out near-orthogonal noise so we never inject irrelevant
    beats when nothing in the store actually relates to the moment. Measured
    with all-MiniLM: real matches land ~0.24-0.63, noise ~0.0-0.21, so ~0.15
    keeps signal and drops the clearly-unrelated. Empty list if there's no
    store, no embedder, or a dim mismatch.
    """
    query = (query or "").strip()
    if not query:
        return []
    meta_p, vec_p = _paths(mem_dir, key)
    with _LOCK:
        metas = _read_metas(meta_p)
        mat = _read_mat(vec_p)
    if mat is None or mat.size == 0 or not metas:
        return []
    q = _embed([query])
    if q is None or q.size == 0 or q.shape[1] != mat.shape[1]:
        return []
    sims = mat @ q[0]  # cosine — both are L2-normalized
    order = np.argsort(-sims)
    out = []
    for idx in order:
        i = int(idx)
        if i >= len(metas):
            continue
        score = float(sims[i])
        if score < min_score:
            break  # sorted desc — nothing past here clears the floor either
        out.append({"text": metas[i].get("text", ""), "day": metas[i].get("day", 0),
                    "score": round(score, 3)})
        if len(out) >= max(1, k):
            break
    return out


# ── tiny IO helpers ──────────────────────────────────────────────────────────
def _read_metas(meta_p: str) -> list:
    if not os.path.exists(meta_p):
        return []
    try:
        with open(meta_p, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, list) else []
    except Exception:
        return []


def _read_mat(vec_p: str):
    if not os.path.exists(vec_p):
        return None
    try:
        return np.load(vec_p)
    except Exception:
        return None


def _atomic_save_json(path: str, obj) -> None:
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False)
    os.replace(tmp, path)


def _atomic_save_npy(path: str, mat) -> None:
    tmp = path + ".tmp.npy"
    np.save(tmp, mat)
    os.replace(tmp, path)


# ── runnable self-check (ponytail: the one check the money-path leaves behind) ─
if __name__ == "__main__":
    import tempfile

    # Stub the embedder: deterministic, normalized vectors so cosine is real but
    # needs no Ollama. "goblin king" beat must win recall for "who did we spare".
    def _fake_encode(texts):
        vocab = ["goblin", "king", "spare", "bridge", "troll", "gold", "day", "who", "market"]
        rows = []
        for t in texts:
            tl = t.lower()
            v = np.array([1.0 if w in tl else 0.0 for w in vocab], dtype="float32")
            if v.sum() == 0:
                v[:] = 1.0
            v /= np.linalg.norm(v)
            rows.append(v)
        return np.array(rows, dtype="float32")

    class _C:
        encode = staticmethod(_fake_encode)

    _client, _client_tried = _C(), True

    d = tempfile.mkdtemp()
    assert add_beat(d, "u__cid", "On Day 3 you spared the goblin king at his throne.", day=3)
    assert add_beat(d, "u__cid", "You crossed the troll bridge and paid gold.", day=4)
    assert not add_beat(d, "u__cid", "You crossed the troll bridge and paid gold.", day=4)  # dup
    hits = recall(d, "u__cid", "who did we spare?", k=1)
    assert hits and "goblin king" in hits[0]["text"], hits
    assert hits[0]["day"] == 3, hits
    assert recall(d, "missing__cid", "anything") == []
    print("campaign_memory self-check OK:", hits[0])
