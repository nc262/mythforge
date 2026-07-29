#!/usr/bin/env python3
"""Every kind the Godot client SAVES must be a kind the server ACCEPTS.

This drifted silently and cost three playtest findings — "adventures" (no
CONTINUE, empty Chronicles), "cast" (the Cast never recorded anyone) and "lore".
The client fires and forgets, so a refused write is invisible: the feature just
never persists and nothing says why.

    python scripts/check_state_kinds.py      # exit 1 if the contract is broken
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Kinds only ever written by a test, never by the game.
TEST_ONLY = {"unit_kind"}

server = os.path.join(ROOT, "routes", "character_studio_routes.py")
m = re.search(r"_WS_KINDS\s*=\s*\{([^}]*)\}", open(server, encoding="utf-8").read())
if not m:
    sys.exit("could not find _WS_KINDS in %s" % server)
accepted = set(re.findall(r'"([a-z_]+)"', m.group(1)))

written = set()
for dirpath, _dirs, files in os.walk(os.path.join(ROOT, "godot")):
    for f in files:
        if not f.endswith(".gd"):
            continue
        src = open(os.path.join(dirpath, f), encoding="utf-8", errors="replace").read()
        written |= set(re.findall(r'save_kind\(\s*"([a-z_]+)"', src))
written -= TEST_ONLY

missing = sorted(written - accepted)
unused = sorted(accepted - written)

print("client writes : %s" % " ".join(sorted(written)))
print("server accepts: %s" % " ".join(sorted(accepted)))
if unused:
    print("\nnote: accepted but never written (harmless, but likely drift): %s" % " ".join(unused))
if missing:
    print("\nBROKEN CONTRACT — these are written by the client and REFUSED by the server:")
    for k in missing:
        print("    %s   → every save silently 400s" % k)
    sys.exit(1)
print("\nOK — every kind the client saves is accepted.")
