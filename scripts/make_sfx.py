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


# ── The Interaction Language vocabulary (docs/InteractionLanguage.md §15) ────
# Every sound here is felt, not announced: UI feedback is deliberately small
# and dry, rewards are warmer, ceremony is the only thing allowed to bloom.
# Loudness tiers live in Sfx (Ui.MIX) — these are authored at unity.


def _env(i, attack=0.004, decay=6.0):
    """Click-free envelope: short attack ramp, exponential tail."""
    t = i / SR
    return min(1.0, t / attack) * math.exp(-t * decay)


def tone(n_sec, f0, f1=None, decay=6.0, attack=0.004, harm=0.0, amp=0.5):
    """A sine (optionally gliding f0→f1) with an optional octave harmonic."""
    out = []
    for i in range(int(SR * n_sec)):
        t = i / SR
        f = f0 if f1 is None else f0 + (f1 - f0) * (t / n_sec)
        s = math.sin(2 * math.pi * f * t)
        if harm:
            s += harm * math.sin(2 * math.pi * 2 * f * t)
        out.append(amp * s * _env(i, attack, decay))
    return out


def noise_burst(n_sec, decay=40.0, amp=0.5, lp=0.5):
    """Filtered noise — the 'material' half of a physical sound."""
    out, state = [], 0.0
    for i in range(int(SR * n_sec)):
        state += lp * (random.uniform(-1, 1) - state)
        out.append(amp * state * math.exp(-(i / SR) * decay))
    return out


def mix(*layers):
    n = max(len(x) for x in layers)
    out = [0.0] * n
    for layer in layers:
        for i, s in enumerate(layer):
            out[i] += s
    return [max(-0.99, min(0.99, s)) for s in out]


def delay_by(layer, sec):
    return [0.0] * int(SR * sec) + list(layer)


# — UI feedback: the quiet layer the player feels rather than hears —
def ui_hover():          # a breath of felt
    return tone(0.045, 1800, decay=70.0, amp=0.22)


def ui_click():          # wood on leather
    return mix(tone(0.09, 150, 110, decay=34.0, amp=0.45),
               noise_burst(0.012, decay=90.0, amp=0.28))


def ui_open():           # a drawer sliding out
    return tone(0.26, 220, 330, decay=5.0, attack=0.02, harm=0.18, amp=0.34)


def ui_close():          # it settles back
    return tone(0.20, 330, 220, decay=7.0, attack=0.012, harm=0.12, amp=0.26)


def ui_back():           # one step back — a falling fifth
    return mix(tone(0.14, 392.0, decay=16.0, amp=0.26),
               delay_by(tone(0.12, 261.63, decay=16.0, amp=0.24), 0.05))


def ui_deny():           # muted refusal — damped, no sparkle
    out = []
    for i in range(int(SR * 0.16)):
        t = i / SR
        sq = 1.0 if math.sin(2 * math.pi * 92 * t) > 0 else -1.0
        out.append(0.30 * sq * math.exp(-t * 22) * min(1.0, t / 0.003))
    return out


# — Rewards: warmer, rounder, a little louder in the mix —
def equip():             # metal settling into leather
    return mix(noise_burst(0.06, decay=48.0, amp=0.34, lp=0.35),
               delay_by(tone(0.22, 1180, 980, decay=13.0, harm=0.3, amp=0.30), 0.02))


def purchase():          # three coins, never the same twice
    layers = []
    for k in range(3):
        f = random.choice([1560.0, 1830.0, 2100.0]) * random.uniform(0.97, 1.03)
        layers.append(delay_by(tone(0.16, f, decay=26.0, harm=0.35, amp=0.24),
                               0.02 + k * random.uniform(0.055, 0.085)))
    return mix(*layers)


def loot():              # a small wonder — a rising bell arpeggio
    return mix(*[delay_by(tone(0.30, f, decay=9.0, harm=0.25, amp=0.22), i * 0.075)
                 for i, f in enumerate([659.25, 830.61, 987.77])])


def levelup():           # earned — the loudest thing in the game
    triad = [261.63, 329.63, 392.0, 523.25]
    swell = mix(*[delay_by(tone(1.30, f, decay=2.4, attack=0.05, harm=0.22, amp=0.20), i * 0.09)
                  for i, f in enumerate(triad)])
    shimmer = delay_by(mix(*[tone(0.7, f * 4, decay=5.0, amp=0.06) for f in triad]), 0.22)
    return mix(swell, shimmer)


def quest():             # resolution — a warm perfect fifth
    return mix(tone(0.70, 349.23, decay=4.0, attack=0.02, harm=0.2, amp=0.26),
               tone(0.70, 523.25, decay=4.0, attack=0.02, harm=0.2, amp=0.22))


# — Beats: the small punctuation of play —
def page():              # paper turns
    out, state = [], 0.0
    for i in range(int(SR * 0.28)):
        t = i / SR
        state += (0.12 + 0.5 * t) * (random.uniform(-1, 1) - state)   # brightening sweep
        out.append(0.34 * state * math.sin(math.pi * min(1.0, t / 0.28)))
    return out


def travel():            # departure — a low whoosh
    out, state = [], 0.0
    for i in range(int(SR * 0.6)):
        t = i / SR
        state += 0.05 * (random.uniform(-1, 1) - state)
        out.append(0.42 * state * math.sin(math.pi * min(1.0, t / 0.6)) +
                   0.14 * math.sin(2 * math.pi * (70 + 40 * t) * t) * math.exp(-t * 3.5))
    return out


def save_():             # the quill sets down
    return mix(noise_burst(0.12, decay=18.0, amp=0.20, lp=0.25),
               delay_by(tone(0.30, 1046.5, decay=8.0, harm=0.2, amp=0.18), 0.10))


def crit():              # it lands
    return mix(hit(), delay_by(tone(0.32, 2200, 1600, decay=12.0, harm=0.4, amp=0.26), 0.01))


def turn():              # your move — a soft double tap
    return mix(tone(0.08, 180, decay=30.0, amp=0.30),
               delay_by(tone(0.10, 240, decay=26.0, amp=0.26), 0.09))


write("dice", dice())
write("hit", hit())
write("sting", sting())
write("chime", chime())
for _name, _fn in [
    ("ui_hover", ui_hover), ("ui_click", ui_click), ("ui_open", ui_open),
    ("ui_close", ui_close), ("ui_back", ui_back), ("ui_deny", ui_deny),
    ("equip", equip), ("purchase", purchase), ("loot", loot),
    ("levelup", levelup), ("quest", quest), ("page", page),
    ("travel", travel), ("save", save_), ("crit", crit), ("turn", turn),
]:
    write(_name, _fn())
# Ambient loops — one mood per world, one for battle.
write("amb_embervale", pad([110.0, 164.81, 220.0], 8.0, 0.18))            # warm hearth drone
write("amb_neonspire", pad([98.0, 146.83], 8.0, 0.10, noise=0.35))         # dark fifth + rain
write("amb_everyday", pad([130.81, 196.0, 261.63], 8.0, 0.12))             # soft daylight pad
write("amb_arcane", pad([103.83, 155.56, 207.65], 8.0, 0.2))               # violet mystery
write("amb_combat", pad([73.42, 110.0], 6.0, 0.45, noise=0.12))            # war drums breathing
