"""
Original CC0 ambient loops for Mythforge worlds.
Authored here (numpy additive synthesis) => provably public-domain, seamless,
tuned per world. No samples, no downloads. Output: stereo 16-bit WAV.

Seam handling: everything is built to a whole number of chord cycles, and any
decaying event (pluck/bell) is wrap-added, so the end flows into the start with
no click. A short equal-power tail<->head crossfade is the final safety net.
"""
import numpy as np, wave, os, sys

SR = 32000  # Nyquist 16 kHz — plenty for pads; keeps files small

def _phase(freq, sr):
    """Cumulative phase for a possibly time-varying frequency array."""
    return 2 * np.pi * np.cumsum(freq) / sr

def _smoothstep_seq(values, n_total, sr, glide=1.4):
    """A per-sample sequence that holds each value then glides to the next.
    values: one entry per equal time-slice across n_total samples."""
    seg = n_total // len(values)
    out = np.empty(n_total)
    g = int(glide * sr)
    for i, v in enumerate(values):
        a = i * seg
        b = (i + 1) * seg if i < len(values) - 1 else n_total
        out[a:b] = v
    # glide: linear-interp the first `g` samples of each segment from prev value
    for i in range(1, len(values)):
        a = i * seg
        prev = values[i - 1]; cur = values[i]
        k = np.linspace(0, 1, g)
        out[a:a + g] = prev + (cur - prev) * (k * k * (3 - 2 * k))  # smoothstep
    return out

def _pad_voice(freq_seq, sr, harmonics, detune_cents, bright_lfo):
    """Additive detuned pad. harmonics: list of (mult, amp)."""
    det = 2 ** (detune_cents / 1200.0)
    sig = np.zeros(len(freq_seq))
    for mult, amp in harmonics:
        # higher harmonics breathe with the brightness LFO (a soft "filter")
        hamp = amp * (bright_lfo if mult >= 3 else 1.0)
        ph = _phase(freq_seq * mult * det, sr)
        sig += hamp * np.sin(ph)
    return sig

def _note(freq, dur, sr, decay=2.5, wave_fn=np.sin, harm=(1.0,)):
    n = int(dur * sr)
    t = np.arange(n) / sr
    env = np.exp(-decay * t) * (1 - np.exp(-120 * t))  # fast attack, exp decay
    ph = 2 * np.pi * freq * t
    s = np.zeros(n)
    for i, h in enumerate(harm, start=1):
        s += h * wave_fn(ph * i)
    return s * env

def _wrap_add(buf, sig, start, sr):
    """Add sig into buf at sample `start`, wrapping past the end to the front."""
    n = len(buf); L = len(sig)
    idx = (np.arange(L) + start) % n
    np.add.at(buf, idx, sig)

def _multitap(sig, sr, taps):
    """Cheap sense of space: a few attenuated, delayed copies (feed-forward, wraps)."""
    out = sig.copy()
    for delay_s, gain in taps:
        d = int(delay_s * sr)
        out += gain * np.roll(sig, d)
    return out

def _crossfade_wrap(sig, sr, xf=0.05):
    """Final seam safety: equal-power blend of the tail into the head."""
    g = int(xf * sr)
    if g * 2 >= len(sig):
        return sig
    fade = np.linspace(0, 1, g)
    head = sig[:g].copy(); tail = sig[-g:].copy()
    sig[:g] = head * fade + tail * (1 - fade)
    return sig[:-g]  # drop the now-redundant tail

def semis(root, offsets):
    return [root * 2 ** (s / 12.0) for s in offsets]

WORLDS = {
    # The Embervale — warm D-minor folk hearth: soft triangle pad, low drone,
    # a slow gentle harp arpeggio.
    'embervale': dict(
        root=146.83, pace=6.5, cycles=6,
        prog=[[0, 3, 7, 14], [-2, 2, 7, 12], [0, 5, 8, 12], [-4, 3, 7, 10]],
        harm=[(1, 0.5), (2, 0.22), (3, 0.12), (4, 0.05)],
        detune=6, sub=0.16, sub_mult=0.5,
        arp=dict(offs=[0, 7, 12, 15, 12, 7], step=0.62, decay=3.0,
                 harm=(1.0, 0.4, 0.15), oct=2, gain=0.14, wave='tri'),
        bright=(0.55, 0.9), lvol=0.72),
    # Neon Spire — cold cyberpunk drift: analog saw fifths, sub pulse, sparse bell blips.
    'neonspire': dict(
        root=110.0, pace=7.5, cycles=6,
        prog=[[0, 7, 12, 19], [-2, 5, 10, 17], [0, 3, 10, 15], [-5, 2, 7, 14]],
        harm=[(1, 0.42), (2, 0.26), (3, 0.16), (5, 0.08), (7, 0.04)],
        detune=11, sub=0.2, sub_mult=0.5,
        arp=dict(offs=[24, 19, 24, 26], step=1.05, decay=4.5,
                 harm=(1.0, 0.5, 0.25, 0.12), oct=1, gain=0.1, wave='sin'),
        bright=(0.35, 0.75), lvol_sweep=True, lvol=0.7),
    # Everyday — mellow modern lofi ease: soft F-maj7 electric-piano tones, light pad.
    'everyday': dict(
        root=174.61, pace=6.0, cycles=6,
        prog=[[0, 4, 7, 11], [5, 9, 12, 16], [-3, 0, 4, 9], [2, 5, 9, 14]],
        harm=[(1, 0.46), (2, 0.2), (3, 0.09)],
        detune=4, sub=0.1, sub_mult=1.0,
        arp=dict(offs=[0, 4, 7, 11, 7, 4], step=0.7, decay=4.2,
                 harm=(1.0, 0.55, 0.2, 0.08), oct=1, gain=0.13, wave='epno'),
        bright=(0.6, 0.95), lvol=0.72),
    # Combat — driving C-minor tension: pulsing low ostinato, tense staccato, faster.
    'combat': dict(
        root=130.81, pace=3.4, cycles=8,
        prog=[[0, 3, 7, 12], [-1, 3, 6, 12], [0, 3, 8, 11], [1, 4, 7, 13]],
        harm=[(1, 0.4), (2, 0.28), (3, 0.18), (4, 0.1)],
        detune=8, sub=0.24, sub_mult=0.5,
        arp=dict(offs=[0, 0, 7, 0, 3, 0, 7, 10], step=0.2125, decay=7.0,
                 harm=(1.0, 0.6, 0.3), oct=1, gain=0.16, wave='saw'),
        bright=(0.3, 0.7), lvol=0.7),
}

WAVES = {
    'sin': lambda ph: np.sin(ph),
    'tri': lambda ph: 2 / np.pi * np.arcsin(np.sin(ph)),
    'saw': lambda ph: 2 * (ph / (2 * np.pi) % 1.0) - 1,
    'epno': lambda ph: np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.12 * np.sin(3 * ph),
}

def render(name, cfg):
    sr = SR
    dur = cfg['pace'] * cfg['cycles']
    n = int(dur * sr)
    # brightness LFO (0..1) breathing the upper harmonics
    blo, bhi = cfg['bright']
    bright = blo + (bhi - blo) * (0.5 + 0.5 * np.sin(2 * np.pi * np.arange(n) / n * cfg['cycles'] / 2))
    # chord tone sequences (one value per pace-slice, glided)
    prog = cfg['prog']; slices = cfg['cycles']
    chord_seq = [prog[i % len(prog)] for i in range(slices)]
    nvoices = len(prog[0])
    mix = np.zeros(n)
    for v in range(nvoices):
        vals = semis(cfg['root'], [c[v] for c in chord_seq])
        fseq = _smoothstep_seq(vals, n, sr, glide=min(1.6, cfg['pace'] * 0.35))
        det = cfg['detune'] * (1 if v % 2 else -1)
        mix += _pad_voice(fseq, sr, cfg['harm'], det, bright) * (0.55 if v == 0 else 0.4)
    # sub drone follows the bass voice
    bass_vals = semis(cfg['root'] * cfg['sub_mult'], [c[0] for c in chord_seq])
    bseq = _smoothstep_seq(bass_vals, n, sr, glide=cfg['pace'] * 0.4)
    mix += cfg['sub'] * np.sin(_phase(bseq, sr))
    # arpeggio / ostinato — wrap-added so events crossing the seam continue at the top
    ar = cfg['arp']
    wf = WAVES[ar['wave']]
    step = ar['step']; t = 0.0; ci = 0
    root_arp = cfg['root'] * ar['oct']
    while t < dur:
        chord = chord_seq[int((t / cfg['pace'])) % slices]
        base = chord[0]
        off = ar['offs'][ci % len(ar['offs'])]
        freq = root_arp * 2 ** ((base + off) / 12.0)
        note = _note(freq, step * 2.2, sr, decay=ar['decay'], wave_fn=wf, harm=ar['harm'])
        _wrap_add(mix, note * ar['gain'], int(t * sr), sr)
        t += step; ci += 1
    # slow overall volume swell for the sweepier worlds
    if cfg.get('lvol_sweep'):
        mix *= 0.75 + 0.25 * (0.5 + 0.5 * np.sin(2 * np.pi * np.arange(n) / n))
    # space: stereo via Haas + light multitap
    tapsL = _multitap(mix, sr, [(0.11, 0.22), (0.23, 0.12)])
    tapsR = _multitap(mix, sr, [(0.13, 0.22), (0.19, 0.12)])
    haas = int(0.012 * sr)
    L = tapsL; R = np.roll(tapsR, haas)
    L = _crossfade_wrap(L, sr); R = _crossfade_wrap(R, sr)
    m = max(np.max(np.abs(L)), np.max(np.abs(R)), 1e-6)
    peak = cfg.get('lvol', 0.7)
    L = (L / m) * peak; R = (R / m) * peak
    # soft-clip guard
    L = np.tanh(L * 1.1) * 0.92; R = np.tanh(R * 1.1) * 0.92
    stereo = np.stack([L, R], axis=1)
    pcm = (stereo * 32767).astype('<i2')
    out = os.path.join(sys.argv[1], name + '.wav')
    with wave.open(out, 'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr)
        w.writeframes(pcm.tobytes())
    sz = os.path.getsize(out) / 1e6
    print(f'{name}.wav  {len(L)/sr:5.1f}s  {sz:5.2f} MB  root {cfg["root"]:.1f}Hz')

if __name__ == '__main__':
    os.makedirs(sys.argv[1], exist_ok=True)
    for name, cfg in WORLDS.items():
        render(name, cfg)
    print('done')
