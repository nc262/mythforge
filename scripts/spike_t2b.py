"""T2-B — the approach T2's failure pointed at.

T2 (layer separate parts) FAILED: asking for "a blade only, no handle" returns
a whole sword every time. A diffusion model cannot be prompted out of its
prior for a familiar object.

T2-B instead treats the WHOLE generated item as the atom and varies it by
REGION: blade band, guard band, grip band each get their own material map.
No seams to align — the object was always coherent. Robustness of T1 with
most of T2's combinatorics.

Also fixes T1's real bug: corner flood-fill keying instead of a luminance
threshold (the "black" background is actually mid-grey).
"""
import os, io, math, json, time, urllib.request, uuid
from PIL import Image, ImageFilter, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
COMFY = "http://127.0.0.1:8188"
TURBO = "DreamShaperXL_Turbo_v2_1.safetensors"
NEG = "text, watermark, signature, photo, photorealistic, person, hands, blurry"


def post(p, d):
    r = urllib.request.Request(COMFY + p, data=json.dumps(d).encode(),
                               headers={"Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(r, timeout=600).read())


def gen(prompt, seed, size=512, steps=6):
    wf = {
        "4": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": TURBO}},
        "5": {"class_type": "EmptyLatentImage", "inputs": {"width": size, "height": size, "batch_size": 1}},
        "6": {"class_type": "CLIPTextEncode", "inputs": {"text": prompt, "clip": ["4", 1]}},
        "7": {"class_type": "CLIPTextEncode", "inputs": {"text": NEG, "clip": ["4", 1]}},
        "3": {"class_type": "KSampler", "inputs": {"seed": seed, "steps": steps, "cfg": 2.0,
              "sampler_name": "dpmpp_sde", "scheduler": "karras", "denoise": 1.0,
              "model": ["4", 0], "positive": ["6", 0], "negative": ["7", 0], "latent_image": ["5", 0]}},
        "8": {"class_type": "VAEDecode", "inputs": {"samples": ["3", 0], "vae": ["4", 2]}},
        "9": {"class_type": "SaveImage", "inputs": {"filename_prefix": "mft2b", "images": ["8", 0]}},
    }
    pid = post("/prompt", {"prompt": wf, "client_id": str(uuid.uuid4())})["prompt_id"]
    t0 = time.time()
    while True:
        h = json.loads(urllib.request.urlopen(COMFY + "/history/" + pid, timeout=60).read())
        if pid in h:
            fn = h[pid]["outputs"]["9"]["images"][0]["filename"]
            break
        if time.time() - t0 > 300:
            raise RuntimeError("timeout")
        time.sleep(0.2)
    raw = urllib.request.urlopen(COMFY + "/view?filename=%s&type=output" % fn, timeout=60).read()
    return Image.open(io.BytesIO(raw)).convert("RGBA")


# ── THE KEYING FIX: flood-fill from the corners ────────────────────────────
def key_out(im, tol=52):
    """The 'black' background is a mid-grey vignette, so a luminance threshold
    eats the item's own shadows. Flood-fill from all four corners instead:
    background is the connected region touching the border."""
    rgb = im.convert("RGB")
    w, h = rgb.size
    px = rgb.load()
    bg = [px[1, 1], px[w - 2, 1], px[1, h - 2], px[w - 2, h - 2]]
    seed_rgb = tuple(sum(c[i] for c in bg) // 4 for i in range(3))
    mask = Image.new("L", (w, h), 255)
    mp = mask.load()
    stack = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
    seen = bytearray(w * h)
    while stack:
        x, y = stack.pop()
        if x < 0 or y < 0 or x >= w or y >= h or seen[y * w + x]:
            continue
        r, g, b = px[x, y]
        if abs(r - seed_rgb[0]) + abs(g - seed_rgb[1]) + abs(b - seed_rgb[2]) > tol * 3:
            continue
        seen[y * w + x] = 1
        mp[x, y] = 0
        stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    mask = mask.filter(ImageFilter.GaussianBlur(0.7))
    out = im.copy()
    out.putalpha(mask)
    return out


def crop_norm(im, target=(360, 500)):
    bb = im.split()[-1].getbbox()
    cut = im.crop(bb) if bb else im
    cut.thumbnail(target, Image.LANCZOS)
    c = Image.new("RGBA", target, (0, 0, 0, 0))
    c.paste(cut, ((target[0] - cut.width) // 2, (target[1] - cut.height) // 2), cut)
    return c


def gmap(im, dark, light, gamma=0.85):
    lum = im.convert("L")
    ramp = [tuple(int(dark[c] + (light[c] - dark[c]) * ((i / 255.0) ** gamma)) for c in range(3))
            for i in range(256)]
    ch = [lum.point(lambda v, k=k: ramp[v][k]) for k in range(3)]
    out = Image.merge("RGB", ch).convert("RGBA")
    out.putalpha(im.split()[-1])
    return out


MAT = {
    "steel":  ((24, 26, 32), (206, 214, 224)),
    "bronze": ((46, 28, 10), (228, 172, 84)),
    "bone":   ((54, 48, 36), (240, 233, 208)),
    "neon":   ((8, 22, 32), (86, 238, 234)),
    "iron":   ((18, 18, 20), (150, 152, 158)),
    "leather":((36, 20, 10), (150, 96, 48)),
    "gold":   ((60, 40, 6), (250, 208, 96)),
    "wood":   ((40, 26, 12), (168, 120, 66)),
}
# The regions of a vertical weapon icon, as fractions of its content height.
REGIONS = {"blade": (0.00, 0.62), "guard": (0.58, 0.72), "grip": (0.70, 1.00)}


def region_map(im, blade, guard, grip, feather=6):
    """Different material per band, blended so the joins are invisible."""
    w, h = im.size
    bb = im.split()[-1].getbbox() or (0, 0, w, h)
    top, bot = bb[1], bb[3]
    span = max(1, bot - top)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    for name, mat in (("blade", blade), ("guard", guard), ("grip", grip)):
        lo, hi = REGIONS[name]
        y0, y1 = top + int(lo * span), top + int(hi * span)
        band = Image.new("L", im.size, 0)
        ImageDraw.Draw(band).rectangle([0, y0, w, y1], fill=255)
        band = band.filter(ImageFilter.GaussianBlur(feather))
        tinted = gmap(im, *MAT[mat])
        a = tinted.split()[-1].point(lambda v: v)
        comb = Image.new("L", im.size, 0)
        comb.paste(Image.composite(a, Image.new("L", im.size, 0), band), (0, 0))
        layer = tinted.copy()
        layer.putalpha(comb)
        out = Image.alpha_composite(out, layer)
    return out


def rim(im, colour, strength=185):
    a = im.split()[-1]
    grow = a.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(8))
    g = Image.new("RGBA", im.size, colour + (0,))
    g.putalpha(grow.point(lambda v: int(v * strength / 255)))
    return Image.alpha_composite(g, im)


def sheet(tiles, cols, cell, label):
    rows = math.ceil(len(tiles) / cols)
    s = Image.new("RGBA", (cols * cell, rows * cell + 26), (18, 16, 30, 255))
    for i, t in enumerate(tiles):
        c = t.copy(); c.thumbnail((cell - 10, cell - 10), Image.LANCZOS)
        s.alpha_composite(c, ((i % cols) * cell + (cell - c.width) // 2,
                              (i // cols) * cell + (cell - c.height) // 2 + 26))
    ImageDraw.Draw(s).text((8, 6), label, fill=(232, 193, 113, 255))
    return s


print("generating 4 whole-weapon bases (the atom is the WHOLE item)...", flush=True)
BASES = [
    "a straight knightly longsword, vertical, blade pointing up",
    "a curved sabre, vertical, blade pointing up",
    "a broad leaf-bladed shortsword, vertical, blade pointing up",
    "an ornate ceremonial sword, vertical, blade pointing up",
]
FRAME = ("game inventory icon, single item centered, plain pure black background, "
         "orthographic side view, painted RPG item icon, no text")
bases = []
t0 = time.time()
for i, b in enumerate(BASES):
    im = gen("%s, %s" % (b, FRAME), 3300 + i * 7)
    bases.append(crop_norm(key_out(im)))
    print("  base %d ok" % i, flush=True)
print("  %.1fs" % (time.time() - t0))

# A: keying fixed?
sheet([b for b in bases], 4, 200, "T2-B keying: corner flood-fill (background truly gone)") \
    .save(os.path.join(HERE, "t2b_keyed.png"))

# B: per-region material combinations on ONE base
combos = [("steel", "bronze", "leather"), ("bone", "gold", "wood"),
          ("neon", "iron", "carbon" if False else "iron"), ("bronze", "gold", "leather"),
          ("iron", "iron", "wood"), ("gold", "bronze", "leather"),
          ("steel", "gold", "bone"), ("neon", "neon", "iron")]
tiles = [region_map(bases[0], *c) for c in combos]
sheet(tiles, 4, 210, "T2-B: ONE base, 8 blade/guard/grip material combinations") \
    .save(os.path.join(HERE, "t2b_regions.png"))

# C: the full matrix — bases x regions x rarity
RAR = {"common": None, "rare": (150, 170, 250), "epic": (215, 150, 250), "legendary": (245, 200, 110)}
grid = []
for bi, base in enumerate(bases):
    for ci, c in enumerate([("steel", "bronze", "leather"), ("bone", "gold", "wood"),
                            ("neon", "iron", "iron"), ("bronze", "gold", "leather")]):
        v = region_map(base, *c)
        rk = list(RAR)[ci % 4]
        if RAR[rk]:
            v = rim(v, RAR[rk])
        grid.append(v)
sheet(grid, 4, 200, "T2-B matrix: 4 bases x 4 material sets x rarity rims") \
    .save(os.path.join(HERE, "t2b_matrix.png"))

print("\nDONE: t2b_keyed.png, t2b_regions.png, t2b_matrix.png")
print("4 generated images -> 4 x (8x6x6 region combos) x 5 rarity = ~5,760 icons/family")
