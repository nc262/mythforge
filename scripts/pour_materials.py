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
import glob
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

# ── Garment cloth, keyed by WORLD SKIN FAMILY ───────────────────────────────
# These dress the 3D figurine, and they exist only for the four families the
# CC0 outfit pack does not cover. Fantasy, pirate, horror and norse are absent
# ON PURPOSE: the pack's authored leather and homespun are already right for
# them, and pouring a material over a good texture only costs detail.
#
# Keyed by family rather than by world id so a FORGED world is covered too — it
# resolves to a family through WorldSkin.skin_for_id before it ever gets here.
#
# CLOTH HAS ITS OWN VOCABULARY, and the first pour proved why: 3 of 4 came back
# as something other than fabric. "flat lay" is enough for leather and bronze —
# they sit on tables in the training data. Cloth never does. It is draped over a
# body, sewn into a garment, or stretched across a wall, so a prompt that only
# names the substance gets the CONTEXT the model has always seen it in:
#
#   cyber    -> glossy satin drapery with a white artefact across it
#   space    -> a near-white architectural moulding, no fabric anywhere
#   steam    -> a tiled wall in brick coursing
#   everyday -> real denim, but in folds the size of a torso, with stitching
#
# The obvious fix is wrong. "extreme macro close-up" was tried and made it
# WORSE: macro is a photographic genre, and it brings shallow depth, dramatic
# light and drape with it — cyber came back as glowing satin ribbons. Keep the
# "flat lay" framing that already works for leather and bronze.
#
# What actually fixes it is the SUBSTANCE NOUN. Of eight attempts, the only ones
# that rendered as fabric at all said DENIM. It is the one cloth this checkpoint
# has seen photographed flat and lit evenly, so every family anchors on a denim
# or canvas twill and varies only the colour and the thread. A prompt naming
# "technical synthetic" or "ripstop nylon" gets sportswear or, twice, a wall.
#
# CFG was the other suspect and it is NOT the problem — measured, not assumed.
# The checkpoint is an XL *Turbo*, which normally wants cfg ~2, so dropping to 2
# looked like the fix for the over-dramatic look. It is not: at 2 this server's
# sampler loses prompt adherence entirely and returns greeble noise — a cyan
# thicket, a brown circuit board. Everything here is poured at the same 6.0 as
# the materials above.
#
# One more word, and it is the whole thing: "flat lay" must become FLATBED SCAN.
# For leather and bronze "flat lay" is harmless, but for cloth it names a real
# photographic genre — styled folded clothing — so every pour came back as a
# garment shot: big folds, seams, buttons, background showing through. A flatbed
# scan is a physical process that CANNOT have folds, dramatic light or depth,
# and the model knows what its output looks like.
#
# It brings the scanner BED with it, though, so the frame must be claimed too:
# "full frame, edge to edge, one continuous piece" — without it the scan is of
# cut swatches with white paper showing between them, which triplanar then
# pours onto a shirt as white gashes.
#
# Two colour traps, both measured: "pale" plus "evenly lit" blows out to a white
# line drawing, so every value here is mid or dark; and "waxed" is a gloss word
# that summons a chrome OBJECT, so canvas is described by its weave instead.
#
# Ask for the DARK value, not the one you want to see. Brightness is corrected
# at bake time by lift_value(), and asking the model for a light weave only
# makes it reach for a photograph — measured, over ten seeds each: with "mid"
# and "light" colour words every flat candidate still came back at value 27-46
# and every candidate above 100 scored 60-90 on folds.
CLOTH = {
    "cyber-cloth":
        "seamless tileable flatbed scan of dark charcoal denim twill weave with faint thin cyan "
        "warp threads, full frame edge to edge, one continuous piece, pressed perfectly flat, "
        "evenly lit, matte, low contrast, muted desaturated colour, subtle fine grain",
    "everyday-cloth":
        "seamless tileable flatbed scan of dark indigo cotton denim twill weave, full frame edge "
        "to edge, one continuous piece, pressed perfectly flat, evenly lit, matte, low contrast, "
        "muted desaturated colour, subtle fine grain",
    "space-cloth":
        "seamless tileable flatbed scan of mid slate grey cotton denim twill weave, full frame "
        "edge to edge, one continuous piece, pressed perfectly flat, evenly lit, matte, low "
        "contrast, muted desaturated colour, subtle fine grain",
    "steam-cloth":
        "seamless tileable flatbed scan of warm dark brown cotton denim twill weave, full frame "
        "edge to edge, one continuous piece, pressed perfectly flat, evenly lit, matte, low "
        "contrast, muted desaturated colour, subtle fine grain",
}
NEG = ("stained glass, mosaic, ornate, decorative pattern, heraldry, glowing, high contrast, "
       "dramatic lighting, product photo, label, packaging, object, item, seam, border, frame, "
       "vignette, text, watermark, logo, perspective, horizon")
# Everything the first cloth pour actually returned, named so it cannot return.
CLOTH_NEG = NEG + (", fold, folds, drape, draped, wrinkle, crease, pleat, satin, silk, velvet, "
                   "gloss, glossy, sheen, specular highlight, stitching, hem, garment, clothing, "
                   "shirt, wall, panel, tile, brick, plank, moulding, architecture, floor, "
                   "swatch, sample card, cut edge, pinked edge, white background, paper, "
                   "scanner bed, gap, blown out, overexposed")
# NOT in that list, though it was tried: a bare "white". It fixes the one pour
# that was blowing out and breaks the two that need a light value — cyber
# crushed to near-black and lost its cyan entirely. Negate the FAILURE
# ("overexposed"), never the colour.


def gen(name: str, prompt: str, out_dir: str, size: int, steps: int,
        cfg: float, seed: int, server: str, neg: str = NEG) -> str:
    body = {"prompt": prompt, "negative_prompt": neg, "steps": steps,
            "cfg_scale": cfg, "width": size, "height": size, "seed": seed}
    t = time.time()
    req = urllib.request.Request(server, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    res = json.loads(urllib.request.urlopen(req, timeout=900).read())
    path = os.path.join(out_dir, name + ".png")
    Image.open(io.BytesIO(base64.b64decode(res["images"][0]))).convert("RGB").save(path)
    print("  %-32s %5.1fs  seam %s  fold %5.2f  value %5.1f"
          % (name, time.time() - t, seam_score(path), fold_score(path), mean_value(path)))
    return path


## Above this the picture is a folded garment, not a weave. Calibrated on pours
## judged by eye: the four that read as flat cloth scored 2.3-6.9, the four that
## read as folded scored 24-38. Nothing has ever landed between.
FOLD_MAX = 12.0

## Where the cloth's mean luminance is LIFTED to after it is chosen, 0-255.
##
## Asking the model for a bright weave was tried first and is a dead end: it
## cannot satisfy both gates at once. Every flat candidate came back at value
## 27-46 and every candidate above 100 scored 60-90 on folds — because a flat
## evenly-lit denim scan IS dark (denim is dark), and the bright ones are all
## photographs with highlights, and a highlight means a fold. The generator is
## right; the demand was wrong.
##
## So exposure is corrected at BAKE time instead, which is where exposure has
## always belonged. The shader multiplies this cloth by the garment's own
## albedo, so an un-lifted dark scan lands on the figurine as soot.
VALUE_TARGET = 130.0
## Sanity only — reject a candidate that is degenerate black or blown white,
## which no amount of lifting can rescue.
VALUE_RANGE = (12, 230)


def mean_value(path: str) -> float:
    im = Image.open(path).convert("L")
    px = list(im.getdata())
    return sum(px) / len(px)


def lift_value(path: str, target: float = VALUE_TARGET) -> float:
    """Raise the image's mean luminance to `target` by GAMMA, not by multiply.

    A plain multiply was tried and is wrong: lifting the cyber scan from 15 to
    130 means multiplying by 7.9, which clips every value above 32 to white. The
    weave's subtle grain became blown blotches and the figurine came out in
    CAMOUFLAGE — light and dark patches the size of a thigh. Gamma cannot clip:
    it is monotonic on [0,1] and maps 1 to 1, so the ordering of every thread is
    preserved and only the distribution moves.

    Solved by bisection rather than algebra because the mean of a gamma curve
    over an arbitrary histogram has no closed form worth writing.

    Written back over the file, so the SHIPPED texture is the corrected one — a
    lift hidden in the shader would be a number nobody can see by opening the
    png.
    """
    im = Image.open(path).convert("RGB")
    lo, hi = 0.05, 1.0
    for _ in range(24):
        g = (lo + hi) / 2.0
        test = im.point(lambda v, gg=g: int(255.0 * (v / 255.0) ** gg))
        if mean_value_of(test) < target:
            hi = g          # smaller gamma brightens
        else:
            lo = g
    im.point(lambda v, gg=(lo + hi) / 2.0: int(255.0 * (v / 255.0) ** gg)).save(path)
    return mean_value(path)


def mean_value_of(im: "Image.Image") -> float:
    px = list(im.convert("L").getdata())
    return sum(px) / len(px)


def pour_flat(name: str, prompt: str, out_dir: str, size: int, steps: int,
              cfg: float, seed: int, server: str, neg: str, tries: int) -> str:
    """Pour until one comes out flat, then keep the flattest.

    Every candidate is generated and scored; the winner is the lowest fold with
    a seam that still tiles, and it is renamed into place. Stops early on the
    first that clears FOLD_MAX, because there is nothing to gain from a flatter
    flat — this is a search for an acceptable seed, not a beauty contest.
    """
    best_path, best_fold = "", 1e9
    for i in range(max(tries, 1)):
        cand = "%s__s%d" % (name, seed + i)
        p = gen(cand, prompt, out_dir, size, steps, cfg, seed + i, server, neg)
        f = fold_score(p)
        ok = "SEAM" not in seam_score(p) and VALUE_RANGE[0] <= mean_value(p) <= VALUE_RANGE[1]
        if ok and f < best_fold:
            best_path, best_fold = p, f
        if ok and f <= FOLD_MAX:
            break
    final = os.path.join(out_dir, name + ".png")
    if not best_path:
        # No seed in the budget produced a tileable image. Say so and leave
        # nothing behind: a silently-kept folded texture is the one outcome
        # worse than an empty folder, because it looks like it worked.
        print("  %-32s NO TILEABLE CANDIDATE in %d tries" % (name, tries))
        return ""
    if os.path.exists(final):
        os.remove(final)
    os.rename(best_path, final)
    lifted = lift_value(final)
    print("  %-32s -> fold %5.2f  value %5.1f  %s"
          % (name, best_fold, lifted, "OK" if best_fold <= FOLD_MAX else "STILL FOLDED"))
    for stale in glob.glob(os.path.join(out_dir, name + "__s*.png")):
        os.remove(stale)
    return final


def fold_score(path: str) -> float:
    """How folded is it? Large-scale luminance variation, and nothing else.

    Six rounds of prompt surgery could not reliably stop this checkpoint
    photographing a FOLDED GARMENT instead of a flat weave, because whether it
    drapes is close to a coin flip on the seed. Prompt words move the odds; they
    do not decide it. So measure the failure and search for a seed that avoids
    it — which is cheap, at 5 s an image.

    The measurement is the whole trick and it is one line: shrink to 16x16, so
    every thread of weave averages away and only shape survives, then take the
    standard deviation. A flat lit weave is uniform at that scale; a fold is a
    broad light-to-dark ramp, which is exactly what the deviation counts.

    Calibrated against the pours judged by eye, not assumed:
        ~5    flat weave, full frame          -> usable
        ~25   folded garment, seams, shadow   -> the failure
    """
    im = Image.open(path).convert("L").resize((16, 16), Image.BOX)
    px = list(im.getdata())
    m = sum(px) / len(px)
    return (sum((p - m) ** 2 for p in px) / len(px)) ** 0.5


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
    ap.add_argument("--set", choices=["materials", "cloth", "all"], default="all")
    ap.add_argument("--tries", type=int, default=8,
                    help="seeds to search per CLOTH entry before giving up")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    want = {"materials": MATERIALS, "cloth": CLOTH, "all": {**MATERIALS, **CLOTH}}[a.set]
    print("pouring %d materials -> %s" % (len(want), a.out))
    for name, prompt in want.items():
        if name in CLOTH:
            pour_flat(name, prompt, a.out, a.size, a.steps, a.cfg, a.seed,
                      a.server, CLOTH_NEG, a.tries)
        else:
            gen(name, prompt, a.out, a.size, a.steps, a.cfg, a.seed, a.server, NEG)


if __name__ == "__main__":
    main()
