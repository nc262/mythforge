# One-time SFX synthesis for the Godot client — no downloads, no licenses,
# just math: dice clatter, hit thud, combat sting, reward chime.
#   python scripts/make_sfx.py
import math
import random
import struct
import wave
from pathlib import Path

SR = 22050
OUT = Path(__file__).resolve().parent.parent / "godot" / "assets" / "sfx"
OUT.mkdir(parents=True, exist_ok=True)
random.seed(7)


def write(name, samples):
    path = OUT / f"{name}.wav"
    with wave.open(str(path), "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", max(-32767, min(32767, int(s * 32767)))) for s in samples))
    print("wrote", path.name, len(samples) / SR, "s")


def dice():
    n = int(SR * 0.4)
    out = [0.0] * n
    for burst in range(6):
        start = int(SR * (0.03 + burst * 0.055 + random.uniform(0, 0.01)))
        amp = 0.55 * (0.82 ** burst)
        for i in range(int(SR * 0.02)):
            if start + i < n:
                out[start + i] += amp * random.uniform(-1, 1) * math.exp(-i / (SR * 0.004))
    return out


def hit():
    n = int(SR * 0.28)
    out = []
    for i in range(n):
        t = i / SR
        f = 90 * math.exp(-t * 9) + 42
        s = 0.8 * math.sin(2 * math.pi * f * t) * math.exp(-t * 14)
        if i < SR * 0.012:
            s += 0.5 * random.uniform(-1, 1) * (1 - i / (SR * 0.012))
        out.append(s)
    return out


def sting():
    n = int(SR * 0.9)
    freqs = [110.0, 130.81, 164.81]  # A minor — trouble
    out = []
    for i in range(n):
        t = i / SR
        env = math.exp(-t * 3.2) * min(1.0, t * 80)
        s = sum(0.28 * math.sin(2 * math.pi * f * t) + 0.08 * math.sin(2 * math.pi * 2 * f * t) for f in freqs)
        out.append(s * env)
    return out


def chime():
    n = int(SR * 0.7)
    out = []
    for i in range(n):
        t = i / SR
        s = 0.4 * math.sin(2 * math.pi * 880 * t) * math.exp(-t * 5)
        if t > 0.12:
            s += 0.35 * math.sin(2 * math.pi * 1318.5 * (t - 0.12)) * math.exp(-(t - 0.12) * 5)
        out.append(s)
    return out


write("dice", dice())
write("hit", hit())
write("sting", sting())
write("chime", chime())
