"""Path B, proven end-to-end: generate -> MATTE (InSPyReNet, in-graph) ->
region material map -> rarity. The whole pipeline in one ComfyUI call plus
CPU compositing, with no reliance on the model obeying a background request.
"""
import os, io, json, math, time, urllib.request, uuid
from PIL import Image, ImageFilter, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
COMFY = "http://127.0.0.1:8188"
TURBO = "DreamShaperXL_Turbo_v2_1.safetensors"
NEG = "text, watermark, photo, photorealistic, person, hands, multiple objects"


def gen_matted(prompt, seed, size=512, steps=6):
    """txt2img -> InspyrenetRembg -> PNG with a real alpha channel."""
    wf = {
        "4": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": TURBO}},
        "5": {"class_type": "EmptyLatentImage", "inputs": {"width": size, "height": size, "batch_size": 1}},
        "6": {"class_type": "CLIPTextEncode", "inputs": {"text": prompt, "clip": ["4", 1]}},
        "7": {"class_type": "CLIPTextEncode", "inputs": {"text": NEG, "clip": ["4", 1]}},
        "3": {"class_type": "KSampler", "inputs": {"seed": seed, "steps": steps, "cfg": 2.0,
              "sampler_name": "dpmpp_sde", "scheduler": "karras", "denoise": 1.0,
              "model": ["4", 0], "positive": ["6", 0], "negative": ["7", 0], "latent_image": ["5", 0]}},
        "8": {"class_type": "VAEDecode", "inputs": {"samples": ["3", 0], "vae": ["4", 2]}},
        "10": {"class_type": "InspyrenetRembg", "inputs": {"image": ["8", 0], "torchscript_jit": "default"}},
        "9": {"class_type": "SaveImage", "inputs": {"filename_prefix": "mfmatte", "images": ["10", 0]}},
    }
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
    return Image.open(io.BytesIO(raw)).convert("RGBA"), time.time() - t0


MAT = {"steel": ((24, 26, 32), (206, 214, 224)), "bronze": ((46, 28, 10), (228, 172, 84)),
       "bone": ((54, 48, 36), (240, 233, 208)), "neon": ((8, 22, 32), (86, 238, 234)),
       "leather": ((36, 20, 10), (150, 96, 48)), "gold": ((60, 40, 6), (250, 208, 96)),
       "wood": ((40, 26, 12), (168, 120, 66)), "iron": ((18, 18, 20), (150, 152, 158)),
       "blood": ((38, 8, 10), (206, 74, 74))}


def gmap(im, dark, light, gamma=0.85):
    lum = im.convert("L")
    ramp = [tuple(int(dark[c] + (light[c] - dark[c]) * ((i / 255.0) ** gamma)) for c in range(3)) for i in range(256)]
    ch = [lum.point(lambda v, k=k: ramp[v][k]) for k in range(3)]
    o = Image.merge("RGB", ch).convert("RGBA"); o.putalpha(im.split()[-1]); return o


def crop_norm(im, target=(330, 440)):
    bb = im.split()[-1].getbbox(); cut = im.crop(bb) if bb else im
    cut.thumbnail(target, Image.LANCZOS)
    c = Image.new("RGBA", target, (0, 0, 0, 0))
    c.paste(cut, ((target[0] - cut.width) // 2, (target[1] - cut.height) // 2), cut); return c


def principal(alpha, step=2, thr=40):
    w, h = alpha.size; px = alpha.load(); pts = []; sx = sy = 0
    for y in range(0, h, step):
        for x in range(0, w, step):
            if px[x, y] > thr: pts.append((x, y)); sx += x; sy += y
    if len(pts) < 20: return (w / 2, h / 2), 0.0
    cx, cy = sx / len(pts), sy / len(pts); sxx = syy = sxy = 0.0
    for x, y in pts:
        dx, dy = x - cx, y - cy; sxx += dx * dx; syy += dy * dy; sxy += dx * dy
    return (cx, cy), 0.5 * math.atan2(2 * sxy, sxx - syy)


def axis_regions(im, mats, feather=9):
    a = im.split()[-1]; (cx, cy), th = principal(a)
    ux, uy = math.cos(th), math.sin(th); w, h = im.size; px = a.load()
    lo, hi = 1e9, -1e9
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            if px[x, y] > 40:
                t = (x - cx) * ux + (y - cy) * uy; lo = min(lo, t); hi = max(hi, t)
    span = max(1.0, hi - lo)
    def width_at(f):
        t0 = lo + span * f; acc = 0
        for y in range(0, h, 3):
            for x in range(0, w, 3):
                if px[x, y] > 40 and abs((x - cx) * ux + (y - cy) * uy - t0) < span * 0.06: acc += 1
        return acc
    blade_first = width_at(0.10) < width_at(0.90)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    for name, f0, f1 in (("blade", 0.0, 0.62), ("guard", 0.58, 0.72), ("grip", 0.70, 1.0)):
        a0, a1 = (f0, f1) if blade_first else (1 - f1, 1 - f0)
        band = Image.new("L", im.size, 0); bp = band.load()
        for y in range(h):
            for x in range(w):
                t = ((x - cx) * ux + (y - cy) * uy - lo) / span
                if a0 <= t <= a1: bp[x, y] = 255
        band = band.filter(ImageFilter.GaussianBlur(feather))
        tint = gmap(im, *MAT[mats[name]])
        lay = tint.copy()
        lay.putalpha(Image.composite(tint.split()[-1], Image.new("L", im.size, 0), band))
        out = Image.alpha_composite(out, lay)
    return out


def rim(im, colour, strength=190):
    a = im.split()[-1]
    grow = a.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(8))
    g = Image.new("RGBA", im.size, colour + (0,)); g.putalpha(grow.point(lambda v: int(v * strength / 255)))
    return Image.alpha_composite(g, im)


def sheet(tiles, cols, cell, label, bg=(18, 16, 30, 255)):
    rows = math.ceil(len(tiles) / cols)
    s = Image.new("RGBA", (cols * cell, rows * cell + 26), bg)
    for i, t in enumerate(tiles):
        c = t.copy(); c.thumbnail((cell - 10, cell - 10), Image.LANCZOS)
        s.alpha_composite(c, ((i % cols) * cell + (cell - c.width) // 2,
                              (i // cols) * cell + (cell - c.height) // 2 + 26))
    ImageDraw.Draw(s).text((8, 6), label, fill=(232, 193, 113, 255)); return s


FRAME = "game inventory icon, single item centered, painted RPG item icon, dramatic lighting, no text"
ITEMS = ["a knightly longsword", "a curved sabre", "a war axe", "a wooden staff topped with a crystal",
         "a round wooden shield", "a steel dagger", "a heavy warhammer", "a recurve bow"]

print("generate + matte, %d items ..." % len(ITEMS), flush=True)
mats, times = [], []
for i, it in enumerate(ITEMS):
    im, dt = gen_matted("%s, %s" % (it, FRAME), 5500 + i * 17)
    mats.append(crop_norm(im)); times.append(dt)
    a = im.split()[-1]
    cover = sum(a.point(lambda v: 1 if v > 40 else 0).getdata()) / (im.size[0] * im.size[1])
    print("  %-38s %.1fs  subject=%4.1f%% of frame" % (it, dt, cover * 100), flush=True)
print("  median %.1fs/image (generate + matte in ONE call)" % sorted(times)[len(times) // 2])

# Checkerboard proves the alpha is real, not a dark background.
chk = Image.new("RGBA", (200, 200), (70, 70, 78, 255))
d = ImageDraw.Draw(chk)
for y in range(0, 200, 20):
    for x in range(0, 200, 20):
        if (x // 20 + y // 20) % 2: d.rectangle([x, y, x + 19, y + 19], fill=(110, 110, 120, 255))
tiles = []
for m in mats:
    t = chk.copy(); c = m.copy(); c.thumbnail((188, 188), Image.LANCZOS)
    t.alpha_composite(c, ((200 - c.width) // 2, (200 - c.height) // 2)); tiles.append(t)
sheet(tiles, 8, 205, "MATTED over checkerboard — alpha is real (8/8?)").save(os.path.join(HERE, "matte_key.png"))

sets = [{"blade": "steel", "guard": "bronze", "grip": "leather"},
        {"blade": "bone", "guard": "gold", "grip": "wood"},
        {"blade": "neon", "guard": "iron", "grip": "iron"},
        {"blade": "blood", "guard": "gold", "grip": "leather"}]
RAR = [None, (150, 170, 250), (215, 150, 250), (245, 200, 110)]
grid = []
for m in mats[:4]:
    for si, s in enumerate(sets):
        v = axis_regions(m, s)
        if RAR[si]: v = rim(v, RAR[si])
        grid.append(v)
sheet(grid, 4, 200, "PATH B: 4 matted bases x 4 material sets x rarity rims") \
    .save(os.path.join(HERE, "matte_full.png"))
print("\nDONE: matte_key.png, matte_full.png")
