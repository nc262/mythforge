#!/usr/bin/env python3
"""Rebuild the Hall's resume index from the saves that already exist.

Why this is needed
------------------
The Godot client writes its adventure index to studio world-state kind
``adventures``. That kind was missing from ``_WS_KINDS`` on the server, so every
write was refused with ``400 unknown state kind`` — silently, because the client
fires and forgets. Result: no CONTINUE on the title, empty Chronicles, three
separate playtest reports (R8-01, R9-07, R12-01).

The saves themselves were never lost. Each adventure's ``sheet``/``clock``/
``inv``/``quests``/``codex`` blobs are intact on disk; only the *index* that
CONTINUE reads was missing. This reconstructs it from those blobs.

Run once, after the server fix. Idempotent: an owner who already has an
``adventures`` list is left alone unless --force is passed.

    python scripts/rebuild_adventure_index.py [--force] [--dry-run]
"""
import argparse
import json
import os
import shutil
import sys

# Built-in world ids, longest first so "saltmarsh" cannot shadow a longer id
# and cw- custom worlds are matched by prefix.
WORLDS = ["fimbulreach", "brasshaven", "saltmarsh", "neonspire", "embervale", "everyday"]


def state_path(explicit: str = "") -> str:
    """Where the server keeps world state — beside presets.json in DATA_DIR.

    Checked out as a git worktree the repo root is several levels down from the
    real checkout, and on this machine DATA_DIR resolves to a *sibling* project
    entirely, so guessing one location is not enough: walk up and look around.
    """
    if explicit:
        if os.path.isdir(explicit):
            explicit = os.path.join(explicit, "studio_world_state.json")
        if os.path.exists(explicit):
            return explicit
        sys.exit("no state file at %s" % explicit)

    candidates = []
    env = os.environ.get("MYTHFORGE_DATA_DIR") or os.environ.get("DATA_DIR")
    if env:
        candidates.append(env)
    here = os.path.dirname(os.path.abspath(__file__))
    for _ in range(8):
        here = os.path.dirname(here) or here
        candidates.append(os.path.join(here, "data"))
        parent = os.path.dirname(here)
        if parent and os.path.isdir(parent):
            for sib in ("odysseus", "mythforge"):
                candidates.append(os.path.join(parent, sib, "data"))
    seen = set()
    for d in candidates:
        if d in seen:
            continue
        seen.add(d)
        p = os.path.join(d, "studio_world_state.json")
        if os.path.exists(p):
            return p
    sys.exit("studio_world_state.json not found. Pass --path <data dir>.\nLooked in:\n  %s"
             % "\n  ".join(sorted(seen)))


def split_id(cid: str):
    """`dm-embervale-freeroam` -> ("embervale", "Free Roam")."""
    rest = cid[3:] if cid.startswith("dm-") else cid
    for w in WORLDS:
        if rest == w:
            return w, "Free Roam"
        if rest.startswith(w + "-"):
            return w, prettify(rest[len(w) + 1:])
    if rest.startswith("cw-"):
        # cw-<world-slug>-<4char>-<tale...>; the id itself is the world key.
        parts = rest.split("-")
        if len(parts) >= 3:
            return "-".join(parts[:3]), prettify("-".join(parts[3:]) or "freeroam")
    return "", prettify(rest)


def prettify(slug: str) -> str:
    slug = slug.replace("cs-", "", 1) if slug.startswith("cs-") else slug
    if slug in ("freeroam", "free-roam", ""):
        return "Free Roam"
    return " ".join(w.capitalize() for w in slug.split("-") if w)


def as_int(v, default=1) -> int:
    try:
        return int(float(v))
    except (TypeError, ValueError):
        return default


def record_for(cid: str, blob: dict):
    sheet = blob.get("sheet") or {}
    if not isinstance(sheet, dict) or not str(sheet.get("name") or "").strip():
        return None            # never played far enough to have a hero
    clock = blob.get("clock") if isinstance(blob.get("clock"), dict) else {}
    world_id, name = split_id(cid)
    return {
        "id": cid,
        "name": name,
        "world_id": world_id,
        "hero": str(sheet.get("name")),
        "level": as_int(sheet.get("level"), 1),
        "day": as_int(clock.get("day"), 1),
        "done": bool(clock.get("done", False)),
        # Real timestamps are gone — nothing ever recorded one. Rank instead by
        # how far the save got, so CONTINUE offers the meatiest tale rather than
        # an arbitrary one. Ordinary play overwrites this with a true stamp.
        "updated_at": as_int(clock.get("day"), 1) * 1000 + as_int(sheet.get("level"), 1),
        "reconstructed": True,
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true", help="rebuild even if an index exists")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--path", default="", help="data dir or state file")
    args = ap.parse_args()

    p = state_path(args.path)
    with open(p, encoding="utf-8") as f:
        state = json.load(f)

    changed = 0
    for owner, blobs in state.items():
        if not isinstance(blobs, dict):
            continue
        existing = ((blobs.get("_global") or {}).get("adventures")) or []
        if existing and not args.force:
            print("%-18s already has %d record(s) — skipping" % (owner, len(existing)))
            continue
        records = []
        for cid, blob in blobs.items():
            if cid == "_global" or not isinstance(blob, dict):
                continue
            rec = record_for(cid, blob)
            if rec:
                records.append(rec)
        if not records:
            continue
        records.sort(key=lambda r: r["updated_at"], reverse=True)
        print("%-18s %d adventure(s):" % (owner, len(records)))
        for r in records:
            print("    %-46s %-16s lvl %-3d day %d" % (r["id"][:46], r["hero"][:16], r["level"], r["day"]))
        if not args.dry_run:
            blobs.setdefault("_global", {})["adventures"] = records
            changed += 1

    if args.dry_run:
        print("\ndry run — nothing written")
        return
    if not changed:
        print("nothing to do")
        return
    backup = p + ".bak"
    shutil.copy2(p, backup)
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2)
    os.replace(tmp, p)
    print("\nwrote %s (backup at %s)" % (p, os.path.basename(backup)))
    print("Restart the backend, or reopen the Hall, for CONTINUE to pick it up.")


if __name__ == "__main__":
    main()
