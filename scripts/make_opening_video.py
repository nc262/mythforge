# -*- coding: utf-8 -*-
"""The opening cinematic, as a REAL video: animate each genre panorama with
Stable Video Diffusion (img2vid, stock ComfyUI nodes, local ZLUDA rig),
then assemble the four moving shots with crossfades into a Theora .ogv that
Godot's VideoStreamPlayer plays natively.

Usage:  python -X utf8 scripts/make_opening_video.py
Needs:  ComfyUI at :8188 with Wan 2.2 TI2V-5B + umt5-xxl + wan2.2 VAE,
        pip install imageio-ffmpeg pillow requests.
Output: godot/assets/video/opening.ogv (+ per-shot mp4 masters in build/)

ComfyUI is NO LONGER part of the Mythforge stack (the image engine is
stable-diffusion.cpp on Vulkan, :8189) and nothing starts it for you — start it
by hand before running this. sd.cpp does not do video, so this remains a
ComfyUI job; the .ogv it produces is committed and shipped, so this script is
only needed to REGENERATE the opening, never to play it.
"""
import json, os, shutil, subprocess, sys, time, urllib.request

COMFY = "http://127.0.0.1:8188"
ART = os.path.expandvars(r"%APPDATA%/Godot/app_userdata/Mythforge/art")
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "build", "opening")
FINAL = os.path.join(os.path.dirname(__file__), "..", "godot", "assets", "video", "opening.ogv")
SHOTS = ["cine-fantasy", "cine-neonspire", "cine-everyday", "cine-space"]
## Wan 2.2 is DIRECTED video: each shot gets cinematography, not guesses.
MOTION = {
    "cine-fantasy": "The massive dragon slowly beats its wings and glides forward over the misty valley, castles below, morning mist drifting through the mountains, camera pushes in gently, epic fantasy film, smooth coherent motion, highly detailed",
    "cine-neonspire": "The glowing holographic dragon undulates slowly above the rain-slick cyberpunk city, neon signs flickering, light rain falling, camera drifts sideways slowly, cinematic, smooth coherent motion",
    "cine-everyday": "A peaceful suburban street at golden sunset, tree leaves rustling gently in the breeze, warm light shifting, camera dollies forward slowly, cinematic, calm smooth motion",
    "cine-space": "Starships cruise slowly past glowing nebulae toward a vast orbital station, engine lights pulsing, stars shimmering, camera drifts majestically through the fleet, cinematic space epic, smooth coherent motion",
}
NEGATIVE = "static image, no motion, frozen, jitter, warping, morphing, deformed, low quality, artifacts, watermark, text, subtitles"
FRAMES = 81          # 81 frames @ 24fps = 3.375s per shot, Wan 2.2 native pace
FPS_OUT = 24
SECONDS_PER_SHOT = 3.375
XFADE = 0.6
WIDTH, HEIGHT = 1280, 704

import imageio_ffmpeg
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()


def api(path, payload=None):
    if payload is None:
        with urllib.request.urlopen(COMFY + path, timeout=30) as r:
            return json.load(r)
    req = urllib.request.Request(COMFY + path, json.dumps(payload).encode(),
                                 {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def upload_image(png_path, name):
    import mimetypes, uuid
    boundary = uuid.uuid4().hex
    with open(png_path, "rb") as f:
        data = f.read()
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"image\"; "
            f"filename=\"{name}\"\r\nContent-Type: image/png\r\n\r\n").encode() + data + \
           f"\r\n--{boundary}\r\nContent-Disposition: form-data; name=\"overwrite\"\r\n\r\ntrue\r\n--{boundary}--\r\n".encode()
    req = urllib.request.Request(COMFY + "/upload/image", body,
                                 {"Content-Type": f"multipart/form-data; boundary={boundary}"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)["name"]


def wan_workflow(image_name, prompt, seed):
    return {
        "1": {"class_type": "UNETLoader",
              "inputs": {"unet_name": "wan2.2_ti2v_5B_fp16.safetensors", "weight_dtype": "default"}},
        "2": {"class_type": "CLIPLoader",
              "inputs": {"clip_name": "umt5_xxl_fp8_e4m3fn_scaled.safetensors", "type": "wan", "device": "default"}},
        "3": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 0], "text": prompt}},
        "4": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 0], "text": NEGATIVE}},
        "5": {"class_type": "VAELoader", "inputs": {"vae_name": "wan2.2_vae.safetensors"}},
        "6": {"class_type": "LoadImage", "inputs": {"image": image_name}},
        "7": {"class_type": "Wan22ImageToVideoLatent",
              "inputs": {"vae": ["5", 0], "width": WIDTH, "height": HEIGHT,
                          "length": FRAMES, "batch_size": 1, "start_image": ["6", 0]}},
        "8": {"class_type": "ModelSamplingSD3", "inputs": {"model": ["1", 0], "shift": 8.0}},
        "9": {"class_type": "KSampler",
              "inputs": {"model": ["8", 0], "positive": ["3", 0], "negative": ["4", 0],
                          "latent_image": ["7", 0], "seed": seed, "steps": 20, "cfg": 5.0,
                          "sampler_name": "uni_pc", "scheduler": "simple", "denoise": 1.0}},
        "10": {"class_type": "VAEDecodeTiled",
               "inputs": {"samples": ["9", 0], "vae": ["5", 0], "tile_size": 256,
                           "overlap": 64, "temporal_size": 32, "temporal_overlap": 8}},
        "11": {"class_type": "SaveImage", "inputs": {"images": ["10", 0], "filename_prefix": "mf_wan"}},
    }


def free_vram():
    """Unload cached SDXL models so the SVD unet loads FULLY (partial offload
    was 109s/step; full load is an order of magnitude faster)."""
    try:
        api("/free", {"unload_models": True, "free_memory": True})
        time.sleep(3)
    except Exception as e:
        print("  (free_vram:", e, ")", flush=True)


def run_prompt(wf, tag):
    free_vram()
    pid = api("/prompt", {"prompt": wf})["prompt_id"]
    print(f"  [{tag}] queued {pid}; sampling on the rig…", flush=True)
    t0 = time.time()
    while True:
        time.sleep(5)
        hist = api(f"/history/{pid}")
        if pid in hist:
            entry = hist[pid]
            status = entry.get("status", {}).get("status_str", "")
            if status == "error":
                raise RuntimeError(f"ComfyUI error for {tag}: {json.dumps(entry.get('status'))[:400]}")
            outs = entry.get("outputs", {})
            if outs:
                frames = []
                for node in outs.values():
                    for im in node.get("images", []):
                        frames.append(im)
                print(f"  [{tag}] {len(frames)} frames in {time.time()-t0:.0f}s", flush=True)
                return frames
        if time.time() - t0 > 3600:
            raise TimeoutError(f"{tag} exceeded 60min")


def fetch_frames(frames, dest):
    os.makedirs(dest, exist_ok=True)
    for i, im in enumerate(frames):
        q = urllib.request.urlencode if False else None
        url = f"{COMFY}/view?filename={urllib.parse.quote(im['filename'])}&subfolder={urllib.parse.quote(im.get('subfolder',''))}&type={im.get('type','output')}"
        with urllib.request.urlopen(url, timeout=60) as r:
            with open(os.path.join(dest, f"f_{i:04d}.png"), "wb") as f:
                f.write(r.read())


import urllib.parse


def prep_input(shot):
    """Cover-crop the panorama to SVD's 1024x576."""
    from PIL import Image
    src = os.path.join(ART, shot + ".png")
    img = Image.open(src).convert("RGB")
    tw, th = WIDTH, HEIGHT
    s = max(tw / img.width, th / img.height)
    img = img.resize((round(img.width * s), round(img.height * s)), Image.LANCZOS)
    x = (img.width - tw) // 2
    y = (img.height - th) // 2
    img = img.crop((x, y, x + tw, y + th))
    p = os.path.join(OUT_DIR, shot + "_in.png")
    img.save(p)
    return p


def _prompt_shot(prompt_nodes):
    try:
        for node in prompt_nodes.values():
            if isinstance(node, dict) and node.get("class_type") == "LoadImage":
                return str(node.get("inputs", {}).get("image", "")).replace("_in.png", "")
        return ""
    except Exception:
        return ""


def find_history_frames(shot):
    """A finished job for this shot already in ComfyUI's history? Reuse it —
    kills and re-runs must never re-pay a 35-minute sample."""
    try:
        hist = api("/history?max_items=50")
    except Exception:
        return None
    for pid, entry in hist.items():
        pr = entry.get("prompt", [])
        nodes = pr[2] if len(pr) > 2 and isinstance(pr[2], dict) else {}
        if _prompt_shot(nodes) == shot and entry.get("outputs"):
            frames = []
            for node in entry["outputs"].values():
                for im in node.get("images", []):
                    frames.append(im)
            if frames:
                print(f"  [{shot}] reusing {len(frames)} frames from history {pid[:8]}", flush=True)
                return frames
    return None


def wait_running(shot):
    """If a queued/running job is already this shot, wait for IT."""
    try:
        q = api("/queue")
    except Exception:
        return None
    for lane in ["queue_running", "queue_pending"]:
        for item in q.get(lane, []):
            nodes = item[2] if len(item) > 2 and isinstance(item[2], dict) else {}
            if _prompt_shot(nodes) == shot:
                pid = item[1]
                print(f"  [{shot}] job {str(pid)[:8]} already on the rig — waiting on it", flush=True)
                t0 = time.time()
                while time.time() - t0 < 3600:
                    time.sleep(15)
                    hist = api(f"/history/{pid}")
                    if pid in hist and hist[pid].get("outputs"):
                        frames = []
                        for node in hist[pid]["outputs"].values():
                            for im in node.get("images", []):
                                frames.append(im)
                        return frames
                return None
    return None


def make_clip(shot, idx):
    clip_mp4 = os.path.join(OUT_DIR, f"{shot}.mp4")
    if os.path.exists(clip_mp4):
        print(f"  [{shot}] clip cached", flush=True)
        return clip_mp4
    frames = find_history_frames(shot) or wait_running(shot)
    if frames:
        pass
    else:
        inp = prep_input(shot)
        name = upload_image(inp, f"{shot}_in.png")
        frames = run_prompt(wan_workflow(name, MOTION[shot], seed=2000 + idx), shot)
    fdir = os.path.join(OUT_DIR, shot + "_frames")
    if os.path.isdir(fdir):
        shutil.rmtree(fdir)
    fetch_frames(frames, fdir)
    encode_clip(fdir, clip_mp4)
    return clip_mp4


def encode_clip(fdir, clip_mp4):
    """Stretch however many frames we have across the shot's 4 seconds
    (slow, majestic motion), interpolated to smooth 24fps."""
    n = len([f for f in os.listdir(fdir) if f.endswith(".png")])
    rate = max(n / SECONDS_PER_SHOT, 1.0)
    # Plain fps duplication — motion-compensated warping was the "AI slop"
    # smear. Native-pace frames read as a living painting instead.
    subprocess.run([FFMPEG, "-y", "-framerate", f"{rate:.4f}", "-i", os.path.join(fdir, "f_%04d.png"),
                    "-vf", f"fps={FPS_OUT},scale=1280:720:flags=lanczos",
                    "-c:v", "libx264", "-preset", "slow", "-crf", "16",
                    "-pix_fmt", "yuv420p", clip_mp4], check=True, capture_output=True)


def assemble(clips):
    os.makedirs(os.path.dirname(FINAL), exist_ok=True)
    # Chain xfade transitions between the four moving shots.
    inputs = []
    for c in clips:
        inputs += ["-i", c]
    n = len(clips)
    fc = []
    last = "[0:v]"
    t_off = SECONDS_PER_SHOT - XFADE
    for i in range(1, n):
        out = f"[x{i}]" if i < n - 1 else "[vout]"
        fc.append(f"{last}[{i}:v]xfade=transition=fade:duration={XFADE}:offset={t_off:.2f}{out}")
        last = f"[x{i}]"
        t_off += SECONDS_PER_SHOT - XFADE
    # Godot's Theora decoder expects 4:2:0 — 4:4:4 renders black on many GPUs.
    cmd = [FFMPEG, "-y"] + inputs + ["-filter_complex", ";".join(fc), "-map", "[vout]",
           "-c:v", "libtheora", "-q:v", "7", "-pix_fmt", "yuv420p", "-an", FINAL]
    subprocess.run(cmd, check=True, capture_output=True)
    print(f"ASSEMBLED {FINAL} ({os.path.getsize(FINAL)//1024//1024}MB)", flush=True)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    ck = r"C:/Users/cptahabb/Documents/Code/ComfyUI-Zluda/models/diffusion_models/wan2.2_ti2v_5B_fp16.safetensors"
    if not os.path.exists(ck):
        sys.exit("wan2.2_ti2v_5B not in diffusion_models — download still running?")
    clips = []
    for i, shot in enumerate(SHOTS):
        clips.append(make_clip(shot, i))
    assemble(clips)
    print("OPENING-VIDEO OK")


if __name__ == "__main__":
    main()
