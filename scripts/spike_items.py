"""World Compiler spikes T1 + T2 — does modular item art actually work?

T1  palette + treatment over a base icon   (low risk, expected to work)
T2  true part layering in registration     (high risk, the real question)

Both produce contact sheets for visual judgement. GPU cost ~15 images.
"""
import json, time, urllib.request, uuid, io, os, math
from PIL import Image, ImageChops, ImageFilter, ImageDraw

COMFY = "http://127.0.0.1:8188"
TURBO = "DreamShaperXL_Turbo_v2_1.safetensors"
NEG = ("text, watermark, signature, photo, photorealistic, person, hands, "
       "multiple objects, cluttered, blurry")
HERE = os.path.dirname(os.path.abspath(__file__))


# ── ComfyUI ────────────────────────────────────────────────────────────────
def post(path, payload):
    req = urllib.request.Request(COMFY + path, data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(req, timeout=600).read())


def get_json(path):
    return json.loads(urllib.request.urlopen(COMFY + path, timeout=60).read())


def gen(prompt, seed, size=512, steps=6):
    wf = {
        "4": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": TURBO}},
        "5": {"class_type": "EmptyLatentImage",
              "inputs": {"width": size, "height": size, "batch_size": 1}},
        "6": {"class_type": "CLIPTextEncode", "inputs": {"text": prompt, "clip": ["4", 1]}},
        "7": {"class_type": "CLIPTextEncode", "inputs": {"text": NEG, "clip": ["4", 1]}},
        "3": {"class_type": "KSampler",
              "inputs": {"seed": seed, "steps": steps, "cfg": 2.0,
                         "sampler_name": "dpmpp_sde", "scheduler": "karras", "denoise": 1.0,
                         "model": ["4", 0], "positive": ["6", 0],
                         "negative": ["7", 0], "latent_image": ["5", 0]}},
        "8": {"class_type": "VAEDecode", "inputs": {"samples": ["3", 0], "vae": ["4", 2]}},
        "9": {"class_type": "SaveImage", "inputs": {"filename_prefix": "mfspike", "images": ["8", 0]}},
    }
    r = post("/prompt", {"prompt": wf, "client_id": str(uuid.uuid4())})
    pid = r["prompt_id"]
    t0 = time.time()
    while True:
        h = get_json("/history/" + pid)
        if pid in h:
            fn = h[pid]["outputs"]["9"]["images"][0]["filename"]
            break
        if time.time() - t0 > 300:
            raise RuntimeError("timeout")
        time.sleep(0.2)
    raw = urllib.request.urlopen(
        COMFY + "/view?filename=%s&type=output" % fn, timeout=60).read()
    return Image.open(io.BytesIO(raw)).convert("RGBA")


# ── Image ops ──────────────────────────────────────────────────────────────
def key_out(im, thresh=38):
    """Dark background -> alpha. Generated icons sit on near-black."""
    g = im.convert("L")
    mask = g.point(lambda v: 0 if v < thresh else 255).filter(ImageFilter.GaussianBlur(0.8))
    out = im.copy()
    out.putalpha(mask)
    return out


def content_box(im):
    a = im.split()[-1]
    return a.getbbox()


def normalize(im, target=(384, 384)):
    """Crop to content, scale to fit, centre on a fixed canvas — REGISTRATION."""
    bb = content_box(im)
    if not bb:
        return im.resize(target)
    cut = im.crop(bb)
    cut.thumbnail(target, Image.LANCZOS)
    canvas = Image.new("RGBA", target, (0, 0, 0, 0))
    canvas.paste(cut, ((target[0] - cut.width) // 2, (target[1] - cut.height) // 2), cut)
    return canvas


def gradient_map(im, dark, light):
    """Duotone remap by luminance — how you actually recolour metal."""
    lum = im.convert("L")
    ramp = []
    for i in range(256):
        t = i / 255.0
        ramp.append(tuple(int(dark[c] + (light[c] - dark[c]) * (t ** 0.85)) for c in range(3)))
    r = lum.point(lambda v: ramp[v][0])
    g = lum.point(lambda v: ramp[v][1])
    b = lum.point(lambda v: ramp[v][2])
    out = Image.merge("RGB", (r, g, b)).convert("RGBA")
    out.putalpha(im.split()[-1])
    return out


def rim_glow(im, colour, strength=170, spread=9):
    a = im.split()[-1]
    grow = a.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(spread))
    glow = Image.new("RGBA", im.size, colour + (0,))
    glow.putalpha(grow.point(lambda v: int(v * strength / 255)))
    return Image.alpha_composite(glow, im)


def add_wear(im, seed=3):
    import random
    random.seed(seed)
    scratch = Image.new("L", im.size, 0)
    d = ImageDraw.Draw(scratch)
    for _ in range(70):
        x, y = random.randrange(im.size[0]), random.randrange(im.size[1])
        d.line([x, y, x + random.randint(-14, 14), y + random.randint(-14, 14)],
               fill=random.randint(40, 110), width=1)
    scratch = scratch.filter(ImageFilter.GaussianBlur(0.6))
    rgb = im.convert("RGB")
    darkened = ImageChops.subtract(rgb, Image.merge("RGB", (scratch, scratch, scratch)))
    out = darkened.convert("RGBA")
    out.putalpha(im.split()[-1])
    return out


def sheet(tiles, cols, cell=200, label=None):
    rows = math.ceil(len(tiles) / cols)
    W, H = cols * cell, rows * cell + (26 if label else 0)
    s = Image.new("RGBA", (W, H), (18, 16, 30, 255))
    for i, t in enumerate(tiles):
        c = t.copy()
        c.thumbnail((cell - 12, cell - 12), Image.LANCZOS)
        x = (i % cols) * cell + (cell - c.width) // 2
        y = (i // cols) * cell + (cell - c.height) // 2 + (26 if label else 0)
        s.alpha_composite(c, (x, y))
    if label:
        ImageDraw.Draw(s).text((8, 6), label, fill=(232, 193, 113, 255))
    return s


MATERIALS = {
    "iron":   ((26, 28, 34), (196, 204, 214)),
    "bronze": ((48, 30, 12), (226, 172, 88)),
    "bone":   ((52, 46, 34), (238, 231, 206)),
    "neon":   ((10, 24, 34), (92, 240, 236)),
    "blood":  ((38, 8, 10), (206, 74, 74)),
}
RARITY = {"common": None, "uncommon": (140, 220, 150),
          "rare": (150, 170, 250), "epic": (215, 150, 250), "legendary": (245, 200, 110)}

print("=" * 70)
print("SPIKE T1 — palette + treatment over ONE generated base")
print("=" * 70, flush=True)

t0 = time.time()
base_raw = gen("game inventory icon of a straight double-edged sword, vertical, "
               "single item centered, plain black background, painted RPG item icon, "
               "high fantasy, no text", 4242)
base = normalize(key_out(base_raw))
print("  base generated in %.1fs" % (time.time() - t0), flush=True)

t1_tiles = []
for mat, (dk, lt) in MATERIALS.items():
    t1_tiles.append(gradient_map(base, dk, lt))
for rar, col in RARITY.items():
    v = gradient_map(base, *MATERIALS["iron"])
    if rar in ("uncommon", "rare"):
        v = add_wear(v, seed=hash(rar) % 99)
    if col:
        v = rim_glow(v, col, strength=150 if rar != "legendary" else 210)
    t1_tiles.append(v)
sheet(t1_tiles, 5, label="T1: one image -> 5 materials (top) + 5 rarity treatments (bottom)") \
    .save(os.path.join(HERE, "spike_T1.png"))
print("  T1 sheet written: 1 image -> %d variants" % len(t1_tiles), flush=True)

print("\n" + "=" * 70)
print("SPIKE T2 — true part layering (blade / guard / grip) in registration")
print("=" * 70, flush=True)

FRAME = ("isolated on plain solid black background, centered, orthographic side view, "
         "flat even lighting, game asset sheet, painted fantasy, no text")
PARTS = {
    "blade": ["a straight double-edged sword blade only, no handle, no crossguard, vertical",
              "a curved sabre blade only, no handle, no crossguard, vertical",
              "a broad leaf-shaped sword blade only, no handle, vertical"],
    "guard": ["a sword crossguard only, horizontal bar, no blade, no grip",
              "an ornate winged sword crossguard only, horizontal, no blade",
              "a simple straight iron sword crossguard only, horizontal, no blade"],
    "grip":  ["a sword handle grip with round pommel only, no blade, no crossguard, vertical",
              "a leather-wrapped sword grip with gem pommel only, no blade, vertical",
              "a bone sword grip with skull pommel only, no blade, vertical"],
}
lib, t2_time = {}, time.time()
for slot, prompts in PARTS.items():
    lib[slot] = []
    for i, p in enumerate(prompts):
        im = gen("%s, %s" % (p, FRAME), 7000 + i * 13)
        lib[slot].append(key_out(im))
        print("    %s[%d] ok" % (slot, i), flush=True)
print("  %d parts in %.1fs" % (sum(len(v) for v in lib.values()), time.time() - t2_time))

# Compose: normalise each part into its own BAND of a fixed canvas.
CANVAS = (420, 620)
BANDS = {"blade": (0.00, 0.55), "guard": (0.52, 0.66), "grip": (0.63, 1.00)}


def fit_band(part, band, canvas=CANVAS, widen=1.0):
    top, bot = band
    bh = int((bot - top) * canvas[1])
    bw = int(canvas[0] * widen)
    bb = content_box(part)
    cut = part.crop(bb) if bb else part
    cut = cut.resize((max(1, int(cut.width * bh / max(1, cut.height))), bh), Image.LANCZOS)
    if cut.width > bw:
        cut = cut.resize((bw, int(cut.height * bw / cut.width)), Image.LANCZOS)
    lay = Image.new("RGBA", canvas, (0, 0, 0, 0))
    lay.alpha_composite(cut, ((canvas[0] - cut.width) // 2, int(top * canvas[1])))
    return lay


def assemble(bi, gi, gr, material="iron"):
    out = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    out.alpha_composite(fit_band(lib["blade"][bi], BANDS["blade"]))
    out.alpha_composite(fit_band(lib["grip"][gr], BANDS["grip"], widen=0.28))
    out.alpha_composite(fit_band(lib["guard"][gi], BANDS["guard"], widen=0.62))
    return gradient_map(out, *MATERIALS[material])


t2_tiles = []
combos = [(0, 0, 0), (1, 1, 1), (2, 2, 2), (0, 1, 2), (1, 2, 0), (2, 0, 1),
          (0, 2, 1), (1, 0, 2), (2, 1, 0)]
for k, (b, g, r) in enumerate(combos):
    mat = list(MATERIALS)[k % len(MATERIALS)]
    t2_tiles.append(assemble(b, g, r, mat))
sheet(t2_tiles, 3, cell=230,
      label="T2: 9 parts -> 27 silhouettes (9 shown), each material-mapped") \
    .save(os.path.join(HERE, "spike_T2.png"))

raws = []
for slot in PARTS:
    for p in lib[slot]:
        raws.append(normalize(p, (240, 240)))
sheet(raws, 3, cell=170, label="T2 raw parts as generated (blade / guard / grip rows)") \
    .save(os.path.join(HERE, "spike_T2_parts.png"))

print("\nDONE — spike_T1.png, spike_T2.png, spike_T2_parts.png")
print("T1: 1 generated image  -> %d variants" % len(t1_tiles))
print("T2: 9 generated images -> %d silhouettes x %d materials = %d icons"
      % (3 * 3 * 3, len(MATERIALS), 27 * len(MATERIALS)))
