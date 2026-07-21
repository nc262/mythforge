"""Measure T — seconds per image — on the real box, per model/size/steps.

Answers the World Compiler's open question #1: the whole stage budget is
downstream of this number. Also compares a Turbo checkpoint (few steps)
against standard SDXL for BULK item-icon work.
"""
import json, time, urllib.request, uuid, sys

COMFY = "http://127.0.0.1:8188"
OUT = []

ICON_PROMPT = ("game inventory icon of a bronze leaf-bladed shortsword, "
               "single item centered, plain dark background, painted RPG item icon, "
               "high fantasy, no text, no hands")
NEG = "text, watermark, signature, photo, photorealistic, person, hands, blurry"


def post(path, payload):
    req = urllib.request.Request(COMFY + path,
                                 data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(req, timeout=600).read())


def get(path):
    return json.loads(urllib.request.urlopen(COMFY + path, timeout=60).read())


def workflow(ckpt, w, h, steps, cfg, sampler, sched, seed, prompt):
    return {
        "4": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": ckpt}},
        "5": {"class_type": "EmptyLatentImage",
              "inputs": {"width": w, "height": h, "batch_size": 1}},
        "6": {"class_type": "CLIPTextEncode", "inputs": {"text": prompt, "clip": ["4", 1]}},
        "7": {"class_type": "CLIPTextEncode", "inputs": {"text": NEG, "clip": ["4", 1]}},
        "3": {"class_type": "KSampler",
              "inputs": {"seed": seed, "steps": steps, "cfg": cfg,
                         "sampler_name": sampler, "scheduler": sched, "denoise": 1.0,
                         "model": ["4", 0], "positive": ["6", 0],
                         "negative": ["7", 0], "latent_image": ["5", 0]}},
        "8": {"class_type": "VAEDecode", "inputs": {"samples": ["3", 0], "vae": ["4", 2]}},
        "9": {"class_type": "SaveImage",
              "inputs": {"filename_prefix": "mfbench", "images": ["8", 0]}},
    }


def run(label, ckpt, w, h, steps, cfg, sampler="dpmpp_2m", sched="karras", n=3):
    times, files = [], []
    for i in range(n):
        wf = workflow(ckpt, w, h, steps, cfg, sampler, sched, 1000 + i, ICON_PROMPT)
        cid = str(uuid.uuid4())
        t0 = time.time()
        r = post("/prompt", {"prompt": wf, "client_id": cid})
        pid = r["prompt_id"]
        while True:
            hist = get("/history/" + pid)
            if pid in hist:
                break
            if time.time() - t0 > 600:
                print("  TIMEOUT"); return
            time.sleep(0.25)
        dt = time.time() - t0
        times.append(dt)
        try:
            im = hist[pid]["outputs"]["9"]["images"][0]
            files.append(im["filename"])
        except Exception:
            pass
        print("    run %d: %5.1fs" % (i + 1, dt), flush=True)
    med = sorted(times)[len(times) // 2]
    warm = sorted(times[1:])[len(times[1:]) // 2] if len(times) > 1 else med
    OUT.append((label, med, warm, files))
    print("  %-42s median %5.1fs   warm %5.1fs" % (label, med, warm), flush=True)


print("=" * 74)
print("MYTHFORGE ART BENCHMARK — measuring T")
print("=" * 74, flush=True)

TURBO = "DreamShaperXL_Turbo_v2_1.safetensors"
STD = "Juggernaut-XL_v9_RunDiffusionPhoto_v2.safetensors"

# Turbo models want low steps + low CFG + a simple sampler.
print("\n[1] TURBO 1024x1024, 6 steps  (the bulk-generation candidate)", flush=True)
run("turbo-1024-6step", TURBO, 1024, 1024, 6, 2.0, "dpmpp_sde", "karras")

print("\n[2] TURBO 512x512, 6 steps  (icon-sized — parts don't need 1024)", flush=True)
run("turbo-512-6step", TURBO, 512, 512, 6, 2.0, "dpmpp_sde", "karras")

print("\n[3] TURBO 768x768, 8 steps", flush=True)
run("turbo-768-8step", TURBO, 768, 768, 8, 2.0, "dpmpp_sde", "karras")

print("\n[4] STANDARD SDXL 1024x1024, 25 steps  (today's quality path)", flush=True)
run("sdxl-1024-25step", STD, 1024, 1024, 25, 7.0, "dpmpp_2m", "karras", n=2)

print("\n" + "=" * 74)
print("RESULTS  (warm = excludes first-run model load)")
print("=" * 74)
for label, med, warm, files in OUT:
    print("  %-24s median %6.1fs  warm %6.1fs   →  %4d imgs / 30 min"
          % (label, med, warm, int(1800 / warm)))
print("\nfiles:")
for label, _, _, files in OUT:
    for f in files:
        print("   ", label, f)
