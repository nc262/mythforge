#!/usr/bin/env python3
"""Fetch stable-diffusion.cpp (Vulkan, Windows) — the image engine.

36 MB download, ~106 MB installed, and it replaces the entire ComfyUI + ZLUDA +
Python tower: one native binary that serves the OpenAI image API directly.

Vulkan is the point. ZLUDA existed only because ComfyUI wants CUDA and this is
an AMD card; a Vulkan backend needs no CUDA, so none of that scaffolding — the
zluda.exe wrapper, the Defender exclusion, cuDNN forced off, Python pinned to
3.11 — has anything left to hold up.

    python scripts/fetch_sdcpp.py [--dest DIR] [--release TAG]
"""
import argparse
import io
import os
import sys
import urllib.request
import zipfile

REPO = "leejet/stable-diffusion.cpp"
# Sibling of the repo, matching where the supervisor and installer look for it.
# Was hardcoded to one developer's home directory, which is fine for a spike and
# wrong the moment install.ps1 calls it.
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
