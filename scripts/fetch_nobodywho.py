#!/usr/bin/env python3
"""Fetch the NobodyWho GDExtension binary this project needs.

The upstream release is one 1.09 GB zip carrying every platform (4.4 GB
unpacked). This pulls it, extracts ONLY the Windows x86_64 release DLL — the
single file `nobodywho.gdextension` actually points at — and throws the rest
away. 145 MB on disk instead of 4.4 GB.

The DLL is gitignored because it is over GitHub's 100 MB per-file hard limit;
the manifest and icon are tracked, so the addon's shape lives in git and only
its weight does not.

    python scripts/fetch_nobodywho.py [--version nobodywho-godot-v9.5.0]
"""
import argparse
import io
import os
import sys
import urllib.request
import zipfile

REPO = "nobodywho-ooo/nobodywho"
KEEP = ("x86_64-pc-windows-msvc-release.dll", "nobodywho.gdextension", "icon.svg")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", default="nobodywho-godot-v9.5.0")
    args = ap.parse_args()

    out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "godot", "addons", "nobodywho")
    dll = os.path.join(out, "libnobodywho-godot-x86_64-pc-windows-msvc-release.dll")
    if os.path.exists(dll):
        print("already present: %s (%.0f MB)" % (dll, os.path.getsize(dll) / 1048576))
        return

    # The asset name repeats the tag in full, so the tag appears twice:
    #   .../download/nobodywho-godot-v9.5.0/nobodywho-godot-nobodywho-godot-v9.5.0.zip
    # It looks like a bug and is not — installer/clean-room checks this exact URL
    # anonymously, so if upstream ever renames it, that fails instead of a player.
    url = "https://github.com/%s/releases/download/%s/nobodywho-godot-%s.zip" % (REPO, args.version, args.version)
    print("downloading %s\n  (1.09 GB — every platform; we keep one file)" % url)
    try:
        raw = urllib.request.urlopen(url, timeout=1800).read()
    except Exception as e:
        sys.exit("download failed: %s" % e)

    os.makedirs(out, exist_ok=True)
    z = zipfile.ZipFile(io.BytesIO(raw))
    kept = 0
    for i in z.infolist():
        base = os.path.basename(i.filename)
        if not base.endswith(KEEP):
            continue
        # Never clobber the trimmed, commented manifest with upstream's.
        if base == "nobodywho.gdextension" and os.path.exists(os.path.join(out, base)):
            continue
        with z.open(i) as src, open(os.path.join(out, base), "wb") as dst:
            dst.write(src.read())
        kept += i.file_size
        print("  kept %-52s %7.1f MB" % (base, i.file_size / 1048576))
    print("done — %.0f MB kept, the other ~4.1 GB discarded" % (kept / 1048576))


if __name__ == "__main__":
    main()
