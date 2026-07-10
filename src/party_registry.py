"""Shared-party campaigns: the registry that lets a friend join your game.

A party maps a join code to one host's campaign (their character id + chat
session) plus a member list. Two consumers:

  - routes/session_routes._verify_session_owner: members may read/post the
    host's chat session (that single gate covers history + chat_stream).
  - routes/character_studio_routes: party endpoints, and world-state reads/
    writes that resolve a member's request onto the host's campaign blob.

Kept in its own tiny module so both routers can import it without cycles.
Storage is a small JSON file next to the app's other data, guarded by a lock —
same durability model as the studio world state.
"""

import json
import os
import random
import threading
import time

_LOCK = threading.Lock()
_PATH = os.path.join("data", "studio_parties.json")

_CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"   # no 0/O/1/I/L look-alikes


def _load() -> dict:
    try:
        with open(_PATH, "r", encoding="utf-8") as f:
            return json.load(f) or {}
    except Exception:
        return {}


def _save(parties: dict) -> None:
    os.makedirs(os.path.dirname(_PATH), exist_ok=True)
    tmp = _PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(parties, f, ensure_ascii=False, indent=2)
    os.replace(tmp, _PATH)


def create_party(host: str, cid: str, sid: str, name: str, world_id: str = "") -> dict:
    """Create (or return the existing) party for a host's campaign."""
    with _LOCK:
        parties = _load()
        for code, p in parties.items():
            if p.get("host") == host and p.get("cid") == cid:
                p["sid"] = sid or p.get("sid")   # session can be remapped by a re-save
                _save(parties)
                return {"code": code, **p}
        while True:
            code = "".join(random.choice(_CODE_ALPHABET) for _ in range(6))
            if code not in parties:
                break
        parties[code] = {
            "host": host, "cid": cid, "sid": sid, "name": name,
            "world_id": world_id, "members": {}, "busy": None,
            "created_at": time.time(),
        }
        _save(parties)
        return {"code": code, **parties[code]}


def get_party(code: str) -> dict | None:
    p = _load().get((code or "").strip().upper())
    return {"code": (code or "").strip().upper(), **p} if p else None


def join_party(code: str, user: str, hero: str, cls: str) -> dict | None:
    with _LOCK:
        parties = _load()
        p = parties.get((code or "").strip().upper())
        if not p:
            return None
        p.setdefault("members", {})[user] = {"hero": hero, "cls": cls, "joined_at": time.time()}
        _save(parties)
        return {"code": (code or "").strip().upper(), **p}


def parties_for(user: str) -> list:
    """Parties this user hosts or has joined."""
    out = []
    for code, p in _load().items():
        if p.get("host") == user or user in (p.get("members") or {}):
            out.append({"code": code, **p})
    return out


def session_allowed(session_id: str, user: str) -> bool:
    """May `user` touch this chat session because a party shares it?"""
    if not session_id or not user:
        return False
    for p in _load().values():
        if p.get("sid") == session_id and (p.get("host") == user or user in (p.get("members") or {})):
            return True
    return False


def resolve_shared_cid(user: str, cid: str) -> str | None:
    """If `user` is a member (not host) of a party for `cid`, return the host
    whose world-state blob should be used instead of the member's own."""
    for p in _load().values():
        if p.get("cid") == cid and user in (p.get("members") or {}) and p.get("host") != user:
            return p.get("host")
    return None


def set_busy(code: str, user: str, busy: bool) -> dict | None:
    """The table lock: 'someone is talking to the GM'. Best-effort, expires."""
    with _LOCK:
        parties = _load()
        p = parties.get((code or "").strip().upper())
        if not p:
            return None
        p["busy"] = {"by": user, "at": time.time()} if busy else None
        _save(parties)
        return p


def get_busy(p: dict) -> dict | None:
    """Current lock, ignoring stale ones (a crashed client mustn't jam the table)."""
    b = (p or {}).get("busy")
    if b and time.time() - (b.get("at") or 0) < 120:
        return b
    return None
