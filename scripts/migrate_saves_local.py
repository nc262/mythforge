#!/usr/bin/env python3
"""Move every adventure out of the server's world-state blob into the game's
own save folder — the last thing the backend was holding on to.

Why a script rather than the game doing it
------------------------------------------
The client used to import on first launch, by GETting the same endpoints. That
only works if the server can tell WHOSE data to hand back, and with auth
disabled it cannot: `get_current_user()` returns None, so writes land under the
JSON key "null", and a fallback that guesses lands somewhere else again. This
machine has three orphan buckets already — `cptahabb`, `null` and `local` —
which is the whole argument for not keying local data by a user at all.

So the migration reads the file directly and picks the owner with the most
adventures. No identity, no HTTP, no guessing.

    python scripts/migrate_saves_local.py [--dry-run] [--owner NAME]
"""
import argparse
import json
import os
import sys

WORLDS = ["fimbulreach", "brasshaven", "saltmarsh", "neonspire", "embervale", "everyday"]
SHARED = ("cworlds", "cstories", "cgms", "cpersonas", "rel", "artstyle")


def state_file() -> str:
    here = os.path.dirname(os.path.abspath(__file__))
    for _ in range(8):
        here = os.path.dirname(here) or here
        for base in (here, os.path.dirname(here)):
            if not base or not os.path.isdir(base):
                continue
            for sib in ("", "odysseus", "mythforge"):
                p = os.path.join(base, sib, "data", "studio_world_state.json")
                if os.path.exists(p):
                    return p
    sys.exit("studio_world_state.json not found")


def save_dir() -> str:
    return os.path.join(os.environ["APPDATA"], "Godot", "app_userdata", "Mythforge", "saves")


def pretty(cid: str) -> tuple:
    rest = cid[3:] if cid.startswith("dm-") else cid
    for w in WORLDS:
        if rest == w:
            return w, "Free Roam"
        if rest.startswith(w + "-"):
            return w, title(rest[len(w) + 1:])
    if rest.startswith("cw-"):
        parts = rest.split("-")
        if len(parts) >= 3:
            return "-".join(parts[:3]), title("-".join(parts[3:]) or "freeroam")
    return "", title(rest)


def title(slug: str) -> str:
    if slug.startswith("cs-"):
        slug = slug[3:]
    if slug in ("freeroam", "free-roam", ""):
        return "Free Roam"
    return " ".join(w.capitalize() for w in slug.split("-") if w)


def as_int(v, d=1):
    try:
        return int(float(v))
    except (TypeError, ValueError):
        return d


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--owner", default="")
    args = ap.parse_args()

    src = state_file()
    blob = json.load(open(src, encoding="utf-8"))

    if args.owner:
        owner = args.owner
    else:
        # The richest bucket wins — orphan owners ("null", "local") hold almost
        # nothing, which is exactly how you tell them apart from the real one.
        owner = max(blob, key=lambda o: len([k for k in blob[o] if k.startswith("dm-")]))
    adventures = {k: v for k, v in blob.get(owner, {}).items()
                  if k != "_global" and isinstance(v, dict) and v.get("sheet")}
    shelf = {k: v for k, v in (blob.get(owner, {}).get("_global") or {}).items() if k in SHARED}

    print("source : %s" % src)
    print("owner  : %s  (%d adventures, shelf: %s)"
          % (owner, len(adventures), ", ".join(shelf) or "empty"))
    print("target : %s" % save_dir())
    print()

    index = []
    for cid, body in sorted(adventures.items()):
        sheet = body.get("sheet") or {}
        clock = body.get("clock") if isinstance(body.get("clock"), dict) else {}
        world_id, name = pretty(cid)
        index.append({
            "id": cid, "name": name, "world_id": world_id,
            "hero": str(sheet.get("name") or "?"),
            "level": as_int(sheet.get("level")), "day": as_int(clock.get("day")),
            "done": bool(clock.get("done", False)),
            "updated_at": as_int(clock.get("day")) * 1000 + as_int(sheet.get("level")),
        })
        print("  %-46s %-16s lvl %-3d day %d"
              % (cid[:46], str(sheet.get("name"))[:16], as_int(sheet.get("level")), as_int(clock.get("day"))))
    index.sort(key=lambda r: r["updated_at"], reverse=True)

    if args.dry_run:
        print("\ndry run — nothing written")
        return

    d = save_dir()
    os.makedirs(d, exist_ok=True)
    for cid, body in adventures.items():
        with open(os.path.join(d, cid + ".json"), "w", encoding="utf-8") as f:
            json.dump(body, f)
    with open(os.path.join(d, "adventures.json"), "w", encoding="utf-8") as f:
        json.dump(index, f)
    with open(os.path.join(d, "_global.json"), "w", encoding="utf-8") as f:
        json.dump(shelf, f)
    print("\nwrote %d save(s) + adventures.json + _global.json" % len(adventures))
    print("The game no longer reads world state from the backend at all.")


if __name__ == "__main__":
    main()
