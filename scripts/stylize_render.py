#!/usr/bin/env python3
"""Paint a 3D render, then give it its alpha back.

The 3D render is the source of truth for identity and pose; diffusion only
supplies surface. Two things make that work in practice and neither is obvious:

1. THE ALPHA MUST BE RESTORED. sd-server returns RGB, not RGBA — the cut-out the
   SubViewport produced for free is destroyed by the round trip. A token pasted
   without it carries an opaque square of invented background. We keep the
   render's own alpha and re-apply it, so the silhouette is still decided by
   geometry rather than by whatever the model painted.

2. THE MATTE MUST BE NEUTRAL-DARK, NOT TRANSPARENT. Flattening onto black makes
   the model paint black rim-light into the edges; onto white it paints haze.
   A mid-dark neutral reads as "unlit backdrop" and stays out of the way.

Denoise is the whole dial. Measured on this stack:
    <=0.35  painterly, geometry and identity held exactly     <- usable
     0.45   silhouette held, details re-invented
    >=0.55  fully re-imagined; identity lost

    python scripts/stylize_render.py IN.png OUT.png --denoise 0.35 --prompt "..."
"""
import argparse
import base64
import io
import json
import time
import urllib.request

from PIL import Image

SERVER = "http://127.0.0.1:8189/sdapi/v1/img2img"
MATTE = (38, 34, 46)
NEG = "3d render, cgi, plastic, clay, videogame screenshot, flat vector, blurry, watermark"


def stylize(src: str, dst: str, prompt: str, denoise: float, steps: int,
            cfg: float, seed: int, server: str) -> None:
    img = Image.open(src).convert("RGBA")
    alpha = img.getchannel("A")

    flat = Image.new("RGBA", img.size, MATTE + (255,))
    flat.alpha_composite(img)
    buf = io.BytesIO()
    flat.convert("RGB").save(buf, format="PNG")

    body = {
        "init_images": [base64.b64encode(buf.getvalue()).decode()],
        "prompt": prompt,
        "negative_prompt": NEG,
        "denoising_strength": denoise,
        "steps": steps,
        "cfg_scale": cfg,
        "seed": seed,
        "width": img.width,
        "height": img.height,
    }
    t = time.time()
    req = urllib.request.Request(server, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    res = json.loads(urllib.request.urlopen(req, timeout=900).read())
    out = Image.open(io.BytesIO(base64.b64decode(res["images"][0]))).convert("RGB")

    if out.size != img.size:
        out = out.resize(img.size, Image.LANCZOS)
    out = out.convert("RGBA")
    # Geometry decides the silhouette, not the painter.
    out.putalpha(alpha)
    out.save(dst)
    print("%s -> %s  (denoise %.2f, %.1fs)" % (src, dst, denoise, time.time() - t))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--prompt", required=True)
    ap.add_argument("--denoise", type=float, default=0.35)
    ap.add_argument("--steps", type=int, default=20)
    ap.add_argument("--cfg", type=float, default=6.0)
    ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--server", default=SERVER)
    a = ap.parse_args()
    stylize(a.src, a.dst, a.prompt, a.denoise, a.steps, a.cfg, a.seed, a.server)


if __name__ == "__main__":
    main()
