#!/usr/bin/env python3
"""Which routers does the GAME actually need? Ask FastAPI, do not parse it.

`trace_backend.py` answers "is this module imported", which is the wrong bar on
its own: app.py imports EVERY router, so email, calendar, documents and deep
research all look reachable while the Godot client never calls one of their
endpoints. That is bloat, not liveness.

The obvious next move was to read paths out of the decorators. That was wrong
too — routers declare paths RELATIVE to a prefix applied at include_router time,
so `@router.post("/login")` in auth_routes is really /api/auth/login, and an AST
pass sees only "/login" and concludes the router serves nothing the client wants.
It confidently listed auth, models, session and stt as unused. All four are
called on the client's first screen.

So: import the real app and enumerate `app.routes`, which has prefixes already
applied and is the same table the server dispatches on. The framework is the
authority on its own routing; a parser is a second implementation that can only
be wrong differently.

    python scripts/route_surface.py
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("AUTH_ENABLED", "false")

# Harvested from the .gd sources: every /api path the Godot client requests.
CLIENT_PATHS = [
    "/api/auth/login", "/api/auth/logout", "/api/auth/status",
    "/api/chat_stream", "/api/default-chat",
    "/api/characters/studio/",
    "/api/models", "/api/presets/templates",
    "/api/session", "/api/history/", "/api/version", "/api/stt/transcribe",
    "/api/generated-image/",
]


def wanted(path: str) -> bool:
    # Compare with placeholders stripped: the client calls /api/history/<id>
    # against a route declared /api/history/{session_id}.
    base = path.split("{")[0].rstrip("/")
    for w in CLIENT_PATHS:
        ww = w.rstrip("/")
        if base == ww or base.startswith(ww + "/") or ww.startswith(base + "/"):
            return True
    return False


def main() -> None:
    import app as appmod  # noqa: F401  (importing builds the route table)

    routes = []
    for r in appmod.app.routes:
        p = getattr(r, "path", None)
        if not p:
            continue
        ep = getattr(r, "endpoint", None)
        mod = getattr(ep, "__module__", "?") if ep else "?"
        routes.append((p, mod))

    by_mod: dict[str, list[str]] = {}
    for p, m in routes:
        by_mod.setdefault(m, []).append(p)

    used, unused = [], []
    for m, paths in sorted(by_mod.items()):
        if m.startswith(("fastapi", "starlette")):
            continue
        (used if any(wanted(p) for p in paths) else unused).append((m, paths))

    print("total routes: %d across %d modules\n" % (len(routes), len(by_mod)))
    print("== MODULES SERVING THE CLIENT (must keep) ==")
    for m, paths in used:
        hit = sorted({p for p in paths if wanted(p)})
        print("  %-42s %2d/%-2d paths used" % (m, len(hit), len(paths)))
        for p in hit[:4]:
            print("        %s" % p)

    print("\n== MODULES THE CLIENT NEVER CALLS (bloat candidates) ==")
    tot = 0
    for m, paths in sorted(unused, key=lambda x: -len(x[1])):
        f = m.replace(".", "/") + ".py"
        n = 0
        if os.path.exists(f):
            with open(f, encoding="utf-8") as fh:
                n = sum(1 for _ in fh)
        tot += n
        print("  %6d  %-42s %d paths" % (n, m, len(paths)))
        for p in sorted(paths)[:3]:
            print("        %s" % p)
    print("\n  %d lines of router code the client never reaches." % tot)
    print("  NOTE: removing a router is a SCOPE decision, not a dead-code")
    print("  finding — some of these back features the game may want later")
    print("  (uploads, gallery, tts). Verify by disabling and running the")
    print("  Godot harnesses, not by trusting this list.")


if __name__ == "__main__":
    main()
