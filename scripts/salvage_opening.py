# -*- coding: utf-8 -*-
"""Salvage the in-flight cine-fantasy SVD job (queued before the VRAM fix),
encode its clip, then hand over to make_opening_video.main() for the rest.
Idempotent: re-run freely; finished work is cached."""
import os, sys, time, shutil, subprocess
sys.path.insert(0, os.path.dirname(__file__))
import make_opening_video as m

PID = "a3fb8375-e3d5-44ce-9d7e-7c3a6245ce97"
SHOT = "cine-fantasy"


def salvage():
    clip = os.path.join(m.OUT_DIR, f"{SHOT}.mp4")
    if os.path.exists(clip):
        print("[salvage] clip already cached", flush=True)
        return
    t0 = time.time()
    while True:
        hist = m.api(f"/history/{PID}")
        if PID in hist and hist[PID].get("outputs"):
            frames = []
            for node in hist[PID]["outputs"].values():
                for im in node.get("images", []):
                    frames.append(im)
            print(f"[salvage] {len(frames)} frames ready after {time.time()-t0:.0f}s wait", flush=True)
            fdir = os.path.join(m.OUT_DIR, SHOT + "_frames")
            if os.path.isdir(fdir):
                shutil.rmtree(fdir)
            m.fetch_frames(frames, fdir)
            subprocess.run([m.FFMPEG, "-y", "-framerate", "8", "-i", os.path.join(fdir, "f_%04d.png"),
                            "-vf", f"minterpolate=fps={m.FPS_OUT}:mi_mode=mci:mc_mode=aobmc:vsbmc=1,scale=1280:720:flags=lanczos",
                            "-t", str(m.SECONDS_PER_SHOT), "-c:v", "libx264", "-preset", "slow", "-crf", "16",
                            "-pix_fmt", "yuv420p", clip], check=True, capture_output=True)
            print("[salvage] cine-fantasy.mp4 encoded", flush=True)
            return
        if PID in hist and hist[PID].get("status", {}).get("status_str") == "error":
            sys.exit("[salvage] the in-flight job errored; re-run make_opening_video.py")
        time.sleep(20)
        if time.time() - t0 > 3000:
            sys.exit("[salvage] gave up waiting")


if __name__ == "__main__":
    salvage()
    m.main()
