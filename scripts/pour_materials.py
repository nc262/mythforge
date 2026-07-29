#!/usr/bin/env python3
"""Pour SEAMLESS material textures — the 3D analogue of the art pour.

The existing bake generates `form x material` as pixels and composes rarity,
treatment and tint at draw time (docs/AssetBake.md). In 3D that split gets
better and cheaper: material stops multiplying the generation count, because a
material is a SHADER input rather than a separate picture. One mesh per form,
one tileable texture per material, and the cross product is free.

The gain is not only volume. A "mithril" greatsword composed this way is
actually metallic under the scene's light and from any angle, instead of a
sprite with a blue tint laid over it.

Requires sd-server started with --circular (circular padding on both axes).
That is a LAUNCH flag, not a request field, so materials want their own server
invocation — which is fine, this is a batch job:

    sd-server.exe -m CKPT --listen-port 8190 --diffusion-fa --vae-tiling --circular
    python scripts/pour_materials.py --out build/materials

The mesh side needs TRIPLANAR sampling, not UVs. A poured material pushed
through a model's own UV atlas comes out scrambled, because a game mesh's atlas
is laid out for its specific painted texture, not for tiling. Triplanar samples
by object position and ignores UVs, which is exactly what lets one poured
material drop onto any mesh. See spike3d/portrait_spike.gd. Scale is in OBJECT
units so it must be tuned per mesh size — 0.25 suited a 1.5-unit character;
2.2 tiled so tightly it read as pattern.
"""
import argparse
import base64
import io
import json
import os
import time
import urllib.request

from PIL import Image, ImageChops

SERVER = "http://127.0.0.1:8190/sdapi/v1/txt2img"

# Keyed to the worlds' own treatment vocabulary in world_compiler.gd
# (flame_touched, salt_eaten, storm_struck...), so poured materials speak the
# language the catalogue already uses rather than inventing a parallel one.
# PROMPT VOCABULARY, learned the hard way — twice.
#
# 1. Ask for MATERIAL, not motif. "blackened scorched leather with glowing ember
#    cracks" produced stained glass: a bold decorative pattern that reads as
#    heraldry when wrapped on a character, not as a surface. The words that fix
#    it are matte / low contrast / muted / desaturated / subtle fine grain.
#    A character's surface should whisper the world, not shout it.
# 2. Do NOT say "photographic material sample". It invites stock-photo
#    artefacts, and one pour came back with the words "Casablanca Saddle"
#    printed across it and another as a product shot of a rolled tube — despite
#    "text, watermark" sitting in the negative. Say "flat lay" and describe the
#    substance instead.
MATERIALS = {
    "embervale-subtle":
        "seamless tileable flat lay of worn dark leather with faint ash dusting and hairline "
        "cracks, matte, low contrast, muted desaturated colour, subtle fine grain, even lighting",
    "saltmarsh-subtle":
        "seamless tileable flat lay of weathered grey-green oxidised bronze with fine salt "
        "pitting, matte, low contrast, muted desaturated colour, subtle fine grain, even lighting",
    "neonspire-subtle":
        "seamless tileable flat lay of dark brushed gunmetal with faint thin cyan etched lines, "
        "matte, low contrast, muted desaturated colour, subtle fine grain, even lighting",
}
NEG = ("stained glass, mosaic, ornate, decorative pattern, heraldry, glowing, high contrast, "
       "dramatic lighting, product photo, label, packaging, object, item, seam, border, frame, "
       "vignette, text, watermark, logo, perspective, horizon")


def gen(name: str, prompt: str, out_dir: str, size: int, steps: int,
        cfg: float, seed: int, server: str) -> str:
    body = {"prompt": prompt, "negative_prompt": NEG, "steps": steps,
            "cfg_scale": cfg, "width": size, "height": size, "seed": seed}
    t = time.time()
    req = urllib.request.Request(server, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    res = json.loads(urllib.request.urlopen(req, timeout=900).read())
    path = os.path.join(out_dir, name + ".png")
    Image.open(io.BytesIO(base64.b64decode(res["images"][0]))).convert("RGB").save(path)
    print("  %-32s %5.1fs  seam %s" % (name, time.time() - t, seam_score(path)))
    return path


def seam_score(path: str) -> str:
    """How well does it actually tile? Reported as a RATIO, not a difference.

    Roll the image by half its size so the wrapped edges land in the middle,
    then measure the jump across that join. The trap — and the first version of
    this function fell straight into it — is comparing that jump against zero.
    A picture of a lantern on a flat dark background has near-identical edges
    and scored 0.6, "better" than a genuinely tileable stone texture at 7.7,
    because the metric was really measuring background uniformity.

    So divide by the image's OWN mean adjacent-pixel difference. Now the
    question is "does the seam look like ordinary texture variation, or like a
    line?", which is what the eye is actually asking:

        ~1.0  seam indistinguishable from the texture      -> tiles
        >2    a join you can see                           -> does not tile

    A flat image no longer passes for free: flat means a tiny denominator too.
    """
    im = Image.open(path).convert("L")
    w, h = im.size
    rolled = ImageChops.offset(im, w // 2, h // 2)
    px = rolled.load()

    def mean_abs(pairs):
        vals = [abs(a - b) for a, b in pairs]
        return sum(vals) / max(len(vals), 1)

    cx, cy = w // 2, h // 2
    seam_x = mean_abs([(px[cx - 1, y], px[cx, y]) for y in range(h)])
    seam_y = mean_abs([(px[x, cy - 1], px[x, cy]) for x in range(w)])
    # Baseline: typical neighbour-to-neighbour change away from the join.
    base_x = mean_abs([(px[x, y], px[x + 1, y])
                       for y in range(0, h, 4) for x in range(0, w - 1, 4)])
    base_y = mean_abs([(px[x, y], px[x, y + 1])
                       for y in range(0, h - 1, 4) for x in range(0, w, 4)])
    rx = seam_x / max(base_x, 0.5)
    ry = seam_y / max(base_y, 0.5)
    verdict = "tiles" if max(rx, ry) < 2.0 else "SEAM"
    return "x=%.2f y=%.2f %s" % (rx, ry, verdict)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="build/materials")
    ap.add_argument("--size", type=int, default=512)
    ap.add_argument("--steps", type=int, default=20)
    ap.add_argument("--cfg", type=float, default=6.0)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--server", default=SERVER)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    print("pouring %d materials -> %s" % (len(MATERIALS), a.out))
    for name, prompt in MATERIALS.items():
        gen(name, prompt, a.out, a.size, a.steps, a.cfg, a.seed, a.server)


if __name__ == "__main__":
    main()
