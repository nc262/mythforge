#!/usr/bin/env python3
"""Zip a compiled world package (user://worlds/<src>) into godot/baked/<id>.zip
with a clean id/name, so the game can ship it pre-baked and extract on first run.

    python scripts/bake_zip.py <src_world_dir_id> <ship_id> ["Display Name"]
"""
import json, os, sys, zipfile, glob

src_id = sys.argv[1]
ship_id = sys.argv[2]
name = sys.argv[3] if len(sys.argv) > 3 else None

base = os.path.expandvars(r"%APPDATA%\Godot\app_userdata\Mythforge\worlds")
src = os.path.join(base, src_id)
if not os.path.isdir(src):
    print("source package missing:", src)
    sys.exit(1)

wj = json.load(open(os.path.join(src, "world.json"), encoding="utf-8"))
wj["id"] = ship_id
if name:
    wj["name"] = name

os.makedirs("godot/baked", exist_ok=True)
out = os.path.join("godot", "baked", ship_id + ".zip")
n = 0
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("world.json", json.dumps(wj))
    for f in glob.glob(os.path.join(src, "**", "*"), recursive=True):
        # *.part is a half-written image from a killed pour (bake B4) — never ship it.
        if os.path.isfile(f) and not f.endswith("world.json") and not f.endswith(".part"):
            rel = os.path.relpath(f, src).replace(os.sep, "/")
            z.write(f, rel)
            n += 1
print("wrote %s: %d files, %.1f MB, state=%s, items=%s" % (
    out, n + 1, os.path.getsize(out) / 1e6, wj.get("compile_state"),
    wj.get("catalogue_count")))
