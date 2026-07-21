"""Quality ladder — how good can one item icon get, and what does it cost?

Same subject, same seed, five production settings, all matted. Produces a
side-by-side sheet plus per-tier timings so quality can be bought deliberately
rather than assumed.
"""
import json, urllib.request, uuid, time, io, os, math
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
COMFY = "http://127.0.0.1:8188"
TURBO = "DreamShaperXL_Turbo_v2_1.safetensors"
JUGG = "Juggernaut-XL_v9_RunDiffusionPhoto_v2.safetensors"
RVIS = "RealVisXL_V5.0_fp16.safetensors"

SUBJECT = ("ornate elven longsword with a leaf-shaped blade and engraved crossguard, "
           "game inventory icon, single item centered, vertical, painted RPG item icon, "
           "dramatic rim lighting, intricate detail, crisp edges, high fantasy")
NEG = ("text, watermark, signature, photo, photorealistic, person, hands, blurry, "
       "low detail, jpeg artifacts, oversaturated, flat lighting, extra objects")


def submit(wf):
    r = urllib.request.Request(COMFY + "/prompt",
                               data=json.dumps({"prompt": wf, "client_id": str(uuid.uuid4())}).encode(),
                               headers={"Content-Type": "application/json"})
    try:
        pid = json.loads(urllib.request.urlopen(r, timeout=900).read())["prompt_id"]
    except urllib.error.HTTPError as e:
        print("   REJECTED:", " ".join(e.read().decode()[:300].split()))
        return None, 0.0
    t0 = time.time()
    while time.time() - t0 < 900:
        h = json.loads(urllib.request.urlopen(COMFY + "/history/" + pid, timeout=60).read())
        if pid in h:
            outs = h[pid].get("outputs", {})
            if "OUT" in outs:
                fn = outs["OUT"]["images"][0]["filename"]
                raw = urllib.request.urlopen(COMFY + "/view?filename=%s&type=output" % fn, timeout=120).read()
                return Image.open(io.BytesIO(raw)).convert("RGBA"), time.time() - t0
            msgs = h[pid].get("status", {}).get("messages", [])
            for m in msgs[-2:]:
                if m[0] == "execution_error":
                    print("   ERROR:", str(m[1].get("exception_message"))[:110])
            return None, time.time() - t0
        time.sleep(0.25)
    return None, -1


def base_nodes(ckpt, w, h, steps, cfg, seed, sampler="dpmpp_sde", sched="karras"):
    return {
        "ck": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": ckpt}},
        "lat": {"class_type": "EmptyLatentImage", "inputs": {"width": w, "height": h, "batch_size": 1}},
        "pos": {"class_type": "CLIPTextEncode", "inputs": {"text": SUBJECT, "clip": ["ck", 1]}},
        "neg": {"class_type": "CLIPTextEncode", "inputs": {"text": NEG, "clip": ["ck", 1]}},
        "smp": {"class_type": "KSampler", "inputs": {"seed": seed, "steps": steps, "cfg": cfg,
                "sampler_name": sampler, "scheduler": sched, "denoise": 1.0,
                "model": ["ck", 0], "positive": ["pos", 0], "negative": ["neg", 0], "latent_image": ["lat", 0]}},
        "dec": {"class_type": "VAEDecode", "inputs": {"samples": ["smp", 0], "vae": ["ck", 2]}},
    }


def finish(wf, img_node):
    wf["matte"] = {"class_type": "InspyrenetRembg", "inputs": {"image": [img_node, 0], "torchscript_jit": "default"}}
    wf["OUT"] = {"class_type": "SaveImage", "inputs": {"filename_prefix": "mfqual", "images": ["matte", 0]}}
    return wf


SEED = 90210
RESULTS = []


def tier(name, wf, note):
    print("  %-34s ..." % name, end="", flush=True)
    im, dt = submit(wf)
    print(" %6.1fs %s" % (dt, "OK" if im else "FAILED"), flush=True)
    if im:
        RESULTS.append((name, im, dt, note))


print("QUALITY LADDER — same subject, same seed, matted\n")

# 1 — today's bulk setting
tier("A turbo 512 / 6st  (baseline)",
     finish(base_nodes(TURBO, 512, 512, 6, 2.0, SEED), "dec"), "bulk, current")

# 2 — same model, full resolution
tier("B turbo 1024 / 10st",
     finish(base_nodes(TURBO, 1024, 1024, 10, 2.5, SEED), "dec"), "4x pixels")

# 3 — quality checkpoint, proper step count
tier("C juggernaut 1024 / 30st",
     finish(base_nodes(JUGG, 1024, 1024, 30, 6.5, SEED, "dpmpp_2m"), "dec"), "showcase model")

# 4 — RealVis, the other quality checkpoint
tier("D realvis 1024 / 30st",
     finish(base_nodes(RVIS, 1024, 1024, 30, 6.0, SEED, "dpmpp_2m"), "dec"), "showcase alt")

# 5 — TWO-STAGE: turbo draft -> quality refine (the hires-fix pattern)
wf = base_nodes(TURBO, 768, 768, 8, 2.0, SEED)
wf["ck2"] = {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": JUGG}}
wf["pos2"] = {"class_type": "CLIPTextEncode", "inputs": {"text": SUBJECT, "clip": ["ck2", 1]}}
wf["neg2"] = {"class_type": "CLIPTextEncode", "inputs": {"text": NEG, "clip": ["ck2", 1]}}
wf["up"] = {"class_type": "LatentUpscale", "inputs": {"samples": ["smp", 0], "upscale_method": "nearest-exact",
            "width": 1280, "height": 1280, "crop": "disabled"}}
wf["smp2"] = {"class_type": "KSampler", "inputs": {"seed": SEED + 1, "steps": 18, "cfg": 6.0,
              "sampler_name": "dpmpp_2m", "scheduler": "karras", "denoise": 0.45,
              "model": ["ck2", 0], "positive": ["pos2", 0], "negative": ["neg2", 0], "latent_image": ["up", 0]}}
wf["dec2"] = {"class_type": "VAEDecode", "inputs": {"samples": ["smp2", 0], "vae": ["ck2", 2]}}
tier("E two-stage 768->1280 refine", finish(wf, "dec2"), "draft + refine")

# Contact sheet, big cells so detail is judgeable.
if RESULTS:
    CELL = 430
    cols = len(RESULTS)
    sheet = Image.new("RGBA", (cols * CELL, CELL + 54), (16, 14, 26, 255))
    d = ImageDraw.Draw(sheet)
    d.text((10, 8), "QUALITY LADDER  (same seed, all matted)", fill=(232, 193, 113, 255))
    for i, (name, im, dt, note) in enumerate(RESULTS):
        c = im.copy(); c.thumbnail((CELL - 16, CELL - 16), Image.LANCZOS)
        sheet.alpha_composite(c, (i * CELL + (CELL - c.width) // 2, 40 + (CELL - c.height) // 2))
        d.text((i * CELL + 10, 26), "%s  %.1fs" % (name, dt), fill=(200, 196, 220, 255))
        im.save(os.path.join(HERE, "q_%d.png" % i))
    sheet.save(os.path.join(HERE, "quality_ladder.png"))
    print("\nwrote quality_ladder.png")
    print("\n%-36s %8s   %s" % ("tier", "time", "images/30min"))
    for name, im, dt, note in RESULTS:
        print("%-36s %7.1fs   %5d" % (name, dt, int(1800 / max(dt, 0.1))))
