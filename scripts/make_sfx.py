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


def pad(freqs, n_sec, wobble=0.15, noise=0.0, lp=None):
    """A looping ambient pad: detuned sines + slow amplitude LFO (+ optional
    filtered noise for rain/wind). Start/end at zero-crossings for looping."""
    n = int(SR * n_sec)
    out = []
    lp_state = 0.0
    for i in range(n):
        t = i / SR
        lfo = 1.0 + wobble * math.sin(2 * math.pi * t / n_sec)  # whole-loop LFO
        s = sum(0.16 * math.sin(2 * math.pi * f * t) + 0.06 * math.sin(2 * math.pi * (f * 1.005) * t) for f in freqs)
        if noise > 0:
            lp_state += 0.04 * (random.uniform(-1, 1) - lp_state)  # cheap low-pass
            s += noise * lp_state
        # gentle fade at the very ends so the loop seam is silent
        env = min(1.0, i / (SR * 0.05), (n - i) / (SR * 0.05))
        out.append(s * lfo * 0.7 * env)
    return out


write("dice", dice())
write("hit", hit())
write("sting", sting())
write("chime", chime())
# Ambient loops — one mood per world, one for battle.
write("amb_embervale", pad([110.0, 164.81, 220.0], 8.0, 0.18))            # warm hearth drone
write("amb_neonspire", pad([98.0, 146.83], 8.0, 0.10, noise=0.35))         # dark fifth + rain
write("amb_everyday", pad([130.81, 196.0, 261.63], 8.0, 0.12))             # soft daylight pad
write("amb_arcane", pad([103.83, 155.56, 207.65], 8.0, 0.2))               # violet mystery
write("amb_combat", pad([73.42, 110.0], 6.0, 0.45, noise=0.12))            # war drums breathing
