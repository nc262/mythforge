#!/usr/bin/env python3
"""Fetch stable-diffusion.cpp (Vulkan, Windows) — the image engine.

36 MB download, ~106 MB installed: one native binary that serves the OpenAI
image API directly, so the game POSTs to it with nothing in between.

Vulkan is the point — it needs no vendor SDK and no CUDA shim, so this works the
same on either card.

    python scripts/fetch_sdcpp.py [--dest DIR] [--release TAG]
"""
import argparse
import io
import os
import sys
import urllib.request
import zipfile

REPO = "leejet/stable-diffusion.cpp"
# Sibling of the repo, matching where install.ps1 and the launcher look for it.
DEFAULT_DEST = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "stable-diffusion.cpp")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dest", default=os.environ.get("SDCPP_DIR", DEFAULT_DEST))
    ap.add_argument("--release", default="master-802-e92e86f")
    args = ap.parse_args()

    if os.path.exists(os.path.join(args.dest, "sd-server.exe")):
        print("already installed: %s" % args.dest)
        return

    name = "sd-%s-bin-win-vulkan-x64.zip" % args.release.replace("master-802-", "master-")
    url = "https://github.com/%s/releases/download/%s/%s" % (REPO, args.release, name)
    print("downloading %s (~36 MB)" % url)
    try:
        raw = urllib.request.urlopen(url, timeout=600).read()
    except Exception as e:
        sys.exit("download failed: %s\nCheck the release tag at "
                 "https://github.com/%s/releases" % (e, REPO))

    os.makedirs(args.dest, exist_ok=True)
    z = zipfile.ZipFile(io.BytesIO(raw))
    z.extractall(args.dest)
    print("installed %d files to %s" % (len(z.namelist()), args.dest))
    print("start it with: pwsh scripts/start-image-sdcpp.ps1")


if __name__ == "__main__":
    main()
