#!/usr/bin/env python3
"""Smoke test: does a persona actually trigger generate_image through the real
agent loop? Drives stream_agent_loop with Lilly's prompt + a selfie request.

Usage (from repo root, with venv):  python scripts/test_persona_image.py [MODEL]
"""
import asyncio
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

MODEL = sys.argv[1] if len(sys.argv) > 1 else "gurubot/girl:latest"
MODE = sys.argv[2] if len(sys.argv) > 2 else "persona"  # persona | plain
ENDPOINT = "http://localhost:11434/v1/chat/completions"

if MODE == "plain":
    messages = [
        {"role": "system", "content": "You are a helpful assistant with tools available."},
        {"role": "user", "content": "Please generate an image of a sunset over snowy mountains, photorealistic."},
    ]
else:
    presets = json.load(open("data/presets.json", encoding="utf-8"))
    lilly = next(p for p in presets["user_templates"] if p["id"] == "user-0706b33c")
    sys_prompt = lilly["system_prompt"]
    messages = [
        {"role": "system", "content": sys_prompt},
        {"role": "user", "content": "hey Lilly!! send me a quick selfie of what you're up to right now 📸"},
    ]

from src.agent_loop import stream_agent_loop


async def run():
    deltas, tools, images = [], [], []
    async for chunk in stream_agent_loop(
        ENDPOINT, MODEL, messages,
        headers={"Content-Type": "application/json"},
        temperature=1.0, max_tokens=2048,
        prompt_type="user-0706b33c",
        max_rounds=6, session_id="imgtest", owner="cptahabb",
    ):
        if not chunk.startswith("data: "):
            continue
        payload = chunk[6:].strip()
        if payload == "[DONE]":
            break
        try:
            d = json.loads(payload)
        except Exception:
            continue
        if "delta" in d and not d.get("thinking"):
            deltas.append(d["delta"])
        t = d.get("type")
        if t == "tool_start":
            tools.append(d.get("tool"))
        if t == "tool_output" and (d.get("tool") == "generate_image" or "image_url" in json.dumps(d)):
            images.append(d)
    return "".join(deltas), tools, images


async def main():
    try:
        text, tools, images = await asyncio.wait_for(run(), timeout=200)
    except asyncio.TimeoutError:
        print("MODEL:", MODEL, "\nTIMEOUT after 200s")
        return
    print("MODEL:", MODEL)
    print("=== assistant text (first 700 chars) ===")
    print(text[:700])
    print("=== tools called ===", tools)
    print("=== image outputs ===")
    for im in images:
        print("  ", {k: im.get(k) for k in ("tool", "image_url", "image_id", "results")})
    print("RESULT: generate_image CALLED =", ("generate_image" in tools) or bool(images))


asyncio.run(main())
