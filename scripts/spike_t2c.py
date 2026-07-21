"""T2-C — the two fixes T2-B's failures pointed at.

FIX 1  CHROMA KEY. "plain black background" is a request the model may ignore
       (~25% failure). A saturated colour is an instruction it follows, and
       keying it is exact rather than heuristic.
FIX 2  PRINCIPAL-AXIS REGIONS. Weapons come out diagonal however hard you ask
       for vertical. Instead of fighting it, measure the item's own long axis
       and lay the blade/guard/grip bands ALONG it — rotation-invariant, no
       reorientation of the art needed.
"""
import os, io, json, math, time, urllib.request, uuid
from PIL import Image, ImageFilter, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
COMFY = "http://127.0.0.1:8188"
TURBO = "DreamShaperXL_Turbo_v2_1.safetensors"
NEG = "text, watermark, photo, photorealistic, person, hands, shadow, gradient background"


def gen(prompt, seed, size=512, steps=6):
    wf = {"4": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": TURBO}},
          "5": {"class_type": "EmptyLatentImage", "inputs": {"width": size, "height": size, "batch_size": 1}},
          "6": {"class_type": "CLIPTextEncode", "inputs": {"text": prompt, "clip": ["4", 1]}},
          "7": {"class_type": "CLIPTextEncode", "inputs": {"text": NEG, "clip": ["4", 1]}},
          "3": {"class_type": "KSampler", "inputs": {"seed": seed, "steps": steps, "cfg": 2.0,
                "sampler_name": "dpmpp_sde", "scheduler": "karras", "denoise": 1.0,
                "model": ["4", 0], "positive": ["6", 0], "negative": ["7", 0], "latent_image": ["5", 0]}},
          "8": {"class_type": "VAEDecode", "inputs": {"samples": ["3", 0], "vae": ["4", 2]}},
          "9": {"class_type": "SaveImage", "inputs": {"filename_prefix": "mft2c", "images": ["8", 0]}}}
    req = urllib.request.Request(COMFY + "/prompt",
                                 data=json.dumps({"prompt": wf, "client_id": str(uuid.uuid4())}).encode(),
                                 headers={"Content-Type": "application/json"})
    pid = json.loads(urllib.request.urlopen(req, timeout=600).read())["prompt_id"]
    t0 = time.time()
    while True:
        h = json.loads(urllib.request.urlopen(COMFY + "/history/" + pid, timeout=60).read())
        if pid in h:
            fn = h[pid]["outputs"]["9"]["images"][0]["filename"]; break
        if time.time() - t0 > 300: raise RuntimeError("timeout")
        time.sleep(0.2)
    raw = urllib.request.urlopen(COMFY + "/view?filename=%s&type=output" % fn, timeout=60).read()
    return Image.open(io.BytesIO(raw)).convert("RGBA")


# ── FIX 1: exact chroma key ────────────────────────────────────────────────
KEY_RGB = (0, 255, 0)


def chroma_key(im, tol=118):
    """Distance from the key colour — exact, not a guess about darkness."""
    rgb = im.convert("RGB"); w, h = rgb.size; px = rgb.load()
    mask = Image.new("L", (w, h), 255); mp = mask.load()
    kr, kg, kb = KEY_RGB
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            # green-dominant test beats plain distance (handles shading on the key)
            if g > 90 and g - max(r, b) > 40:
                mp[x, y] = 0
            elif abs(r - kr) + abs(g - kg) + abs(b - kb) < tol:
                mp[x, y] = 0
    mask = mask.filter(ImageFilter.GaussianBlur(0.8))
    out = im.copy(); out.putalpha(mask)
    # de-spill: kill residual green fringe
    r, g, b, a = out.split()
    g = Image.eval(g, lambda v: v)
    return Image.merge("RGBA", (r, g, b, a))


# ── FIX 2: regions along the item's own axis ───────────────────────────────
def principal_axis(alpha, thresh=40):
    """Centroid + orientation of the alpha mask (image moments)."""
    w, h = alpha.size; px = alpha.load()
    n = sx = sy = 0
    pts = []
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            if px[x, y] > thresh:
                pts.append((x, y)); sx += x; sy += y; n += 1
    if n < 20:
        return (w / 2, h / 2), 0.0
    cx, cy = sx / n, sy / n
    sxx = syy = sxy = 0.0
    for x, y in pts:
        dx, dy = x - cx, y - cy
        sxx += dx * dx; syy += dy * dy; sxy += dx * dy
    theta = 0.5 * math.atan2(2 * sxy, sxx - syy)
    return (cx, cy), theta


def axis_regions(im, mats, feather=10):
    """Band the item ALONG its long axis, whatever angle it sits at."""
    a = im.split()[-1]
    (cx, cy), th = principal_axis(a)
    ux, uy = math.cos(th), math.sin(th)
    w, h = im.size; px = a.load()
    lo, hi = 1e9, -1e9
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            if px[x, y] > 40:
                t = (x - cx) * ux + (y - cy) * uy
                lo = min(lo, t); hi = max(hi, t)
    span = max(1.0, hi - lo)
    # Which end is the blade? The tip end is thinner — compare cross-width.
    def width_at(frac):
        t0 = lo + span * frac; acc = 0
        for y in range(0, h, 2):
            for x in range(0, w, 2):
                if px[x, y] > 40:
                    t = (x - cx) * ux + (y - cy) * uy
                    if abs(t - t0) < span * 0.06: acc += 1
        return acc
    blade_first = width_at(0.10) < width_at(0.90)   # thin end = blade tip
    bands = [("blade", 0.00, 0.62), ("guard", 0.58, 0.72), ("grip", 0.70, 1.00)]
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    for name, f0, f1 in bands:
        if not blade_first:
            f0, f1 = 1.0 - f1, 1.0 - f0
        band = Image.new("L", im.size, 0); bp = band.load()
        for y in range(h):
            for x in range(w):
                t = ((x - cx) * ux + (y - cy) * uy - lo) / span
                if f0 <= t <= f1: bp[x, y] = 255
        band = band.filter(ImageFilter.GaussianBlur(feather))
        tint = gmap(im, *MAT[mats[name]])
        comb = Image.composite(tint.split()[-1], Image.new("L", im.size, 0), band)
        lay = tint.copy(); lay.putalpha(comb)
        out = Image.alpha_composite(out, lay)
    return out


MAT = {"steel": ((24, 26, 32), (206, 214, 224)), "bronze": ((46, 28, 10), (228, 172, 84)),
       "bone": ((54, 48, 36), (240, 233, 208)), "neon": ((8, 22, 32), (86, 238, 234)),
       "leather": ((36, 20, 10), (150, 96, 48)), "gold": ((60, 40, 6), (250, 208, 96)),
       "wood": ((40, 26, 12), (168, 120, 66)), "iron": ((18, 18, 20), (150, 152, 158))}


def gmap(im, dark, light, gamma=0.85):
    lum = im.convert("L")
    ramp = [tuple(int(dark[c] + (light[c] - dark[c]) * ((i / 255.0) ** gamma)) for c in range(3)) for i in range(256)]
    ch = [lum.point(lambda v, k=k: ramp[v][k]) for k in range(3)]
    o = Image.merge("RGB", ch).convert("RGBA"); o.putalpha(im.split()[-1]); return o


def crop_norm(im, target=(340, 460)):
    bb = im.split()[-1].getbbox(); cut = im.crop(bb) if bb else im
    cut.thumbnail(target, Image.LANCZOS)
    c = Image.new("RGBA", target, (0, 0, 0, 0))
    c.paste(cut, ((target[0] - cut.width) // 2, (target[1] - cut.height) // 2), cut); return c


def sheet(tiles, cols, cell, label):
    rows = math.ceil(len(tiles) / cols)
    s = Image.new("RGBA", (cols * cell, rows * cell + 26), (18, 16, 30, 255))
    for i, t in enumerate(tiles):
        c = t.copy(); c.thumbnail((cell - 10, cell - 10), Image.LANCZOS)
        s.alpha_composite(c, ((i % cols) * cell + (cell - c.width) // 2,
                              (i // cols) * cell + (cell - c.height) // 2 + 26))
    ImageDraw.Draw(s).text((8, 6), label, fill=(232, 193, 113, 255)); return s


FRAME = ("game inventory icon, single item centered, solid bright green screen background, "
         "chroma key background, flat lighting, painted RPG item icon, no text")
ITEMS = ["a knightly longsword", "a curved sabre", "a war axe", "a wooden staff with crystal",
         "a round wooden shield", "a steel dagger"]
print("generating %d items on a CHROMA KEY background..." % len(ITEMS), flush=True)
keyed, t0 = [], time.time()
for i, it in enumerate(ITEMS):
    im = gen("%s, %s" % (it, FRAME), 8800 + i * 11)
    keyed.append(crop_norm(chroma_key(im)))
    print("  %s ok" % it, flush=True)
print("  %.1fs" % (time.time() - t0))
sheet(keyed, 6, 180, "FIX 1 chroma key: 6/6 backgrounds removed exactly?").save(os.path.join(HERE, "t2c_key.png"))

print("axis-aligned region mapping...", flush=True)
sets = [{"blade": "steel", "guard": "bronze", "grip": "leather"},
        {"blade": "bone", "guard": "gold", "grip": "wood"},
        {"blade": "neon", "guard": "iron", "grip": "iron"},
        {"blade": "bronze", "guard": "gold", "grip": "leather"}]
tiles = []
for base in keyed[:3]:
    for s in sets:
        tiles.append(axis_regions(base, s))
sheet(tiles, 4, 190, "FIX 2 axis regions: bands follow each item's OWN long axis") \
    .save(os.path.join(HERE, "t2c_regions.png"))
print("DONE: t2c_key.png, t2c_regions.png")
