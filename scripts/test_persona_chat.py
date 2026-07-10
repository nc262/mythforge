#!/usr/bin/env python3
"""Hold a short multi-turn conversation with a persona in plain chat mode
(direct Ollama, no tools) to gauge persona adherence + shared-canon cohesion.

Usage:  python scripts/test_persona_chat.py <preset_id> [model]
"""
import json
import sys
from pathlib import Path

import httpx

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

PRESET_ID = sys.argv[1] if len(sys.argv) > 1 else "user-ea9121e3"
MODEL = sys.argv[2] if len(sys.argv) > 2 else "gurubot/girl:latest"
ENDPOINT = "http://localhost:11434/v1/chat/completions"

root = Path(__file__).resolve().parent.parent
presets = json.load(open(root / "data" / "presets.json", encoding="utf-8"))
persona = next(p for p in presets["user_templates"] if p["id"] == PRESET_ID)
name = persona["name"]

USER_TURNS = [
    "hey, how's your day going?",
    "what's everyone up to at home today?",
    "aw I miss you — send me a pic of what you're doing right now",
    "haha love you, talk later",
]

messages = [{"role": "system", "content": persona["system_prompt"]}]
print(f"==================== {name}  ({MODEL}) ====================")
with httpx.Client(timeout=120) as client:
    for turn in USER_TURNS:
        messages.append({"role": "user", "content": turn})
        r = client.post(ENDPOINT, json={"model": MODEL, "messages": messages,
                                        "temperature": float(persona.get("temperature") or 1.0),
                                        "stream": False})
        reply = r.json()["choices"][0]["message"]["content"].strip()
        messages.append({"role": "assistant", "content": reply})
        print(f"\n[you]   {turn}")
        print(f"[{name}] {reply}")
