"""Builds every sound in audio/library/ from scratch. No samples, no recordings.

    python3 audio/synth/build_library.py            # everything
    python3 audio/synth/build_library.py step_ fire # only ids containing these words

Short one-shots are written as 16-bit WAV, beds and long sounds as Ogg Vorbis (needs ffmpeg).
The sound direction behind each one is in audio/AUDIO.md.
"""
import os
import subprocess
import sys
import tempfile

import numpy as np
from scipy.io import wavfile

sys.path.insert(0, os.path.dirname(__file__))
from dsp import *  # noqa: E402,F401,F403

OUT = os.path.join(os.path.dirname(__file__), "..", "library")
SOUNDS = {}


def sound(name, ogg=False):
    def deco(fn):
        SOUNDS[name] = (fn, ogg)
        return fn
    return deco


def write(name, x, ogg):
    x = np.nan_to_num(x)
    x = np.clip(x, -1.0, 1.0)
    data = (x.T if x.ndim == 2 else x)
    pcm = (data * 32767).astype(np.int16)
    path = os.path.join(OUT, name + (".ogg" if ogg else ".wav"))
    if not ogg:
        wavfile.write(path, SR, pcm)
        return path
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        wavfile.write(tmp.name, SR, pcm)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp.name, "-c:a", "libvorbis", "-q:a", "5", path], check=True)
    os.unlink(tmp.name)
    return path


# Inks are pitches. Ember, salmon and crimson stack in fifths (D A E); ultraviolet is the
# raised fourth (G#), the bright strange note of D lydian that only sounds right once the
# other three are home.
INK_HZ = {"ember": 146.83, "salmon": 220.00, "crimson": 329.63, "ultraviolet": 415.30}

# Shared spaces. Baked into the long sounds so giants arrive with their own distance.
IR_VAST = make_ir(7.5, 11, predelay=0.09, lo_tau=1.9, hi_tau=0.55)
IR_OPEN = make_ir(3.5, 12, predelay=0.03, lo_tau=0.9, hi_tau=0.3)
IR_HALL = make_ir(9.0, 13, predelay=0.06, lo_tau=2.6, hi_tau=1.3)
IR_SMALL = make_ir(0.6, 14, predelay=0.004, lo_tau=0.12, hi_tau=0.05)


# ======================================================================= NEAR: the little man

def _grains(dur, rate, seed, lo, hi):
    r = rng(seed)
    n = int(round(dur * SR))
    imp = np.zeros(n)
    count = r.poisson(rate * dur)
    idx = r.integers(0, n, count)
    imp[idx] = r.uniform(-1, 1, count) * r.uniform(0.2, 1.0, count) ** 2
    return bp(imp, lo, hi, order=2)


def step_sand(seed):
    r = rng(seed)
    dur = r.uniform(0.17, 0.24)
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    crunch = _grains(dur, r.uniform(2500, 4200), seed, 900, r.uniform(6000, 9000))
    shh = bp(white(dur, seed + 1), 1500, 7000) * 0.35
    body = lp(white(dur, seed + 2), 260, order=4) * 3.5
    env = np.clip(t / 0.012, 0, 1) * np.exp(-t / r.uniform(0.045, 0.07))
    heel = np.exp(-t / 0.018) * np.clip(t / 0.002, 0, 1)
    # the toe settles a beat later
    toe_at = r.uniform(0.05, 0.08)
    toe = np.clip((t - toe_at) / 0.01, 0, 1) * np.exp(-np.clip(t - toe_at, 0, None) / 0.035) * 0.55
    x = (crunch * 3 + shh) * (env + toe) + body * heel
    return fade(normalize_peak(x, r.uniform(-4, -2)), 0.001, 0.03)


def step_stone(seed):
    r = rng(seed)
    dur = 0.2
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    click = bp(white(dur, seed), 1800, 7000) * np.exp(-t / 0.0025)
    thud = lp(white(dur, seed + 1), 320, order=4) * np.exp(-t / 0.02) * 6
    grit = _grains(dur, 1800, seed + 2, 1200, 6000) * np.exp(-t / 0.035) * 2.5
    knock = osc_sine(r.uniform(150, 190), dur) * np.exp(-t / 0.03) * 0.5
    x = click + thud + grit + knock
    x = convolve(x, IR_SMALL, wet=0.12)[0][:n + int(round(0.15 * SR))]
    return fade(normalize_peak(x, r.uniform(-4, -2)), 0.0005, 0.04)


def step_tile(seed):
    """Hollow ceramic: the checker plain rings faintly underfoot."""
    r = rng(seed)
    dur = 0.32
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    exc = white(dur, seed) * np.exp(-t / 0.002)
    modes = [r.uniform(680, 820), r.uniform(1350, 1600), r.uniform(2350, 2700), r.uniform(3900, 4400)]
    body = sum(resonator(exc, f, 40 + 20 * i) * (1.0 / (1 + i * 0.6)) for i, f in enumerate(modes)) * 8
    thud = lp(white(dur, seed + 1), 240, order=4) * np.exp(-t / 0.018) * 5
    click = hp(exc, 4000) * 0.6
    x = body + thud + click
    return fade(normalize_peak(x, r.uniform(-5, -3)), 0.0005, 0.05)


def step_water(seed):
    r = rng(seed)
    dur = 0.45
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    splash = bp(white(dur, seed), 350, 4200) * np.exp(-t / 0.07) * np.clip(t / 0.006, 0, 1)
    x = splash
    for k in range(r.integers(3, 7)):
        at = r.uniform(0.01, 0.2)
        f0 = r.uniform(450, 1300)
        d = r.uniform(0.02, 0.06)
        bt = np.clip(t - at, 0, None)
        chirp = np.sin(TAU * np.cumsum(f0 * (1 + 1.2 * bt / d)) / SR) * np.exp(-bt / d) * (t > at)
        x = x + chirp * r.uniform(0.15, 0.4)
    drip = lp(white(dur, seed + 3), 600) * np.exp(-t / 0.03) * 1.5
    x = x + drip
    return fade(normalize_peak(x, r.uniform(-5, -3)), 0.001, 0.08)


def step_felt(seed):
    """The tie road: woven, muffled."""
    r = rng(seed)
    dur = 0.22
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    body = lp(white(dur, seed), 550, order=4) * np.exp(-t / 0.035) * np.clip(t / 0.008, 0, 1) * 4
    weave = bp(white(dur, seed + 1), 1800, 5000) * np.exp(-t / 0.05) * 0.25
    x = body + weave
    return fade(normalize_peak(x, r.uniform(-6, -4)), 0.002, 0.05)


for _i in range(6):
    sound(f"step_sand_{_i + 1}")(lambda i=_i: step_sand(100 + i))
    sound(f"step_stone_{_i + 1}")(lambda i=_i: step_stone(200 + i))
    sound(f"step_tile_{_i + 1}")(lambda i=_i: step_tile(300 + i))
for _i in range(4):
    sound(f"step_water_{_i + 1}")(lambda i=_i: step_water(400 + i))
    sound(f"step_felt_{_i + 1}")(lambda i=_i: step_felt(500 + i))


def _touch(seed):
    r = rng(seed)
    dur = 0.18
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    x = lp(white(dur, seed), 900) * np.exp(-t / 0.03) * np.clip(t / 0.004, 0, 1) * 3
    x += bp(white(dur, seed + 1), 2000, 6000) * np.exp(-t / 0.02) * 0.3
    return fade(normalize_peak(x, -6), 0.001, 0.04)


for _i in range(3):
    sound(f"hand_touch_{_i + 1}")(lambda i=_i: _touch(600 + i))


@sound("pickup")
def pickup():
    dur = 0.5
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    sweep = 400 + 3200 * (t / dur) ** 1.5
    swish = tv_filter(white(dur, 61), "bp", sweep, q=1.4) * np.sin(np.pi * np.clip(t / 0.32, 0, 1)) ** 2
    lift = lp(white(dur, 62), 300) * np.exp(-t / 0.04) * 1.5
    return fade(normalize_peak(swish + lift, -4), 0.002, 0.08)


@sound("putdown")
def putdown():
    dur = 0.6
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    sweep = 2600 - 2200 * np.clip(t / 0.25, 0, 1)
    swish = tv_filter(white(dur, 63), "bp", sweep, q=1.4) * np.sin(np.pi * np.clip(t / 0.25, 0, 1)) ** 2 * 0.7
    at = 0.22
    bt = np.clip(t - at, 0, None)
    thud = lp(white(dur, 64), 280, order=4) * np.exp(-bt / 0.05) * (t > at) * 4
    return fade(normalize_peak(swish + thud, -3), 0.002, 0.1)


@sound("cursor_tick_1")
def tick1():
    return _tick(71, 4200)


@sound("cursor_tick_2")
def tick2():
    return _tick(72, 3700)


@sound("cursor_tick_3")
def tick3():
    return _tick(73, 4800)


def _tick(seed, f):
    """The Stray: a lost pointer's click, small and dry."""
    dur = 0.06
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    exc = white(dur, seed) * np.exp(-t / 0.0006)
    x = resonator(exc, f, 30) * 6 + hp(exc, 6000) * 0.5 + resonator(exc, f * 0.5, 12) * 2
    return fade(normalize_peak(x, -9), 0.0002, 0.02)


@sound("usher_glove")
def usher_glove():
    """Bodiless gloves moving the air: a cloth whoomp, no voice."""
    dur = 0.9
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    cut = 300 + 1100 * np.sin(np.pi * np.clip(t / 0.4, 0, 1))
    x = tv_filter(pink(dur, 81), "lp", cut, q=0.9) * np.sin(np.pi * np.clip(t / 0.45, 0, 1)) ** 1.5 * 2
    x += lp(white(dur, 82), 120) * np.exp(-np.clip(t - 0.2, 0, None) / 0.08) * (t > 0.2) * 3
    x = convolve(x, IR_OPEN, wet=0.18)[0][:n + int(round(0.6 * SR))]
    return fade(normalize_peak(x, -4), 0.01, 0.2)


# ---------------------------------------------------------------- fire and failure

def _crackles(dur, rate, seed, gain=1.0):
    r = rng(seed)
    n = int(round(dur * SR))
    out = np.zeros(n)
    count = r.poisson(rate * dur)
    for _ in range(count):
        at = r.integers(0, n - 4000)
        size = r.uniform(0.2, 1.0) ** 3
        ln = int(r.uniform(0.004, 0.03) * SR)
        burst = white(ln / SR, int(r.integers(1 << 30))) * np.exp(-np.arange(ln) / (ln * 0.2))
        f = r.uniform(1400, 6500)
        burst = resonator(burst, f, r.uniform(2, 8)) * 3 + hp(burst, 3000) * 0.4
        out[at:at + ln] += burst * size
        # pops: a few big ones with a low body
        if r.uniform() < 0.06:
            pl = int(round(0.03 * SR))
            out[at:at + pl] += lp(white(pl / SR, int(r.integers(1 << 30))), 700) * np.exp(-np.arange(pl) / (pl * 0.25)) * 2.0 * size ** 0.3
    return out * gain


@sound("fire_loop", ogg=True)
def fire_loop():
    dur, xf = 12.0, 1.0
    total = dur + xf
    chans = []
    for c in range(2):
        roar = lp(brown(total, 90 + c), 420, order=3)
        flick = 0.65 + 0.35 * slow_noise(total, 3.0, 92 + c)
        roar = roar * flick * 0.9
        breath = bp(pink(total, 94 + c), 500, 2500) * (0.5 + 0.5 * slow_noise(total, 1.2, 95 + c)) * 0.12
        hiss = hp(pink(total, 96 + c), 3500) * 0.05
        cr = _crackles(total, 22, 97 + c, 0.9)
        chans.append(roar + breath + hiss + cr)
    x = np.stack(chans)
    x = make_loop(x, xf)
    return normalize_rms(x, -20)


@sound("fire_ignite", ogg=True)
def fire_ignite():
    dur = 3.5
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    cut = 180 + 3400 * np.exp(-((t - 0.45) / 0.3) ** 2) + 700 * np.clip(t / 0.6, 0, 1)
    whoosh = tv_filter(pink(dur, 101), "lp", cut, q=1.2) * np.clip(t / 0.35, 0, 1) ** 2 * np.exp(-np.clip(t - 0.5, 0, None) / 0.9) * 2.5
    body = lp(brown(dur, 102), 300) * np.clip((t - 0.3) / 0.4, 0, 1) * np.exp(-np.clip(t - 0.7, 0, None) / 1.2) * 1.2
    cr = _crackles(dur, 45, 103, 1.0) * np.clip((t - 0.35) / 0.3, 0, 1) * np.exp(-np.clip(t - 0.8, 0, None) / 1.0)
    x = whoosh + body + cr
    x = convolve(x, IR_OPEN, wet=0.25)
    return fade(normalize_peak(x[:, :n + SR], -1.5), 0.005, 0.4)


@sound("statue_stiffen", ogg=True)
def statue_stiffen():
    """Caught: he hardens into a small monument. Stone crackle spreading, then set."""
    dur = 1.6
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    r = rng(111)
    density = 400 + 9000 * np.clip(t / 0.7, 0, 1) ** 2 * (t < 0.85)
    imp = (r.uniform(0, 1, n) < density / SR) * r.uniform(-1, 1, n) * r.uniform(0.2, 1, n) ** 2
    crack = sum(resonator(imp, f, 6) for f in (420, 760, 1300, 2300)) * 3 + bp(imp, 2000, 8000)
    grind = bp(brown(dur, 112), 120, 700) * np.clip(t / 0.6, 0, 1) * (t < 0.85) * 0.5
    at = 0.82
    bt = np.clip(t - at, 0, None)
    set_ = (lp(white(dur, 113), 260, order=4) * 4 + osc_sine(62, dur) * 0.8) * np.exp(-bt / 0.12) * (t > at)
    x = crack + grind + set_
    x = convolve(x, IR_SMALL, wet=0.2)
    return fade(normalize_peak(x[:, :n + int(round(0.4 * SR))], -1.5), 0.005, 0.2)


@sound("rewind", ogg=True)
def rewind():
    """The moment rewinds: a reversed bloom with tape wow, cut dead at the end."""
    dur = 1.8
    src = np.zeros(int(round(0.3 * SR)))
    tt = np.arange(len(src)) / SR
    for f in (146.83, 220.0, 329.63, 587.33):
        src += np.sin(TAU * f * tt) * np.exp(-tt / 0.08)
    src += bp(white(0.3, 121), 300, 5000) * np.exp(-tt / 0.03) * 0.6
    wet = convolve(src, make_ir(1.8, 122, lo_tau=0.6, hi_tau=0.35), wet=1.0, dry=0.3)
    x = wet[:, ::-1][:, -int(round(dur * SR)):]
    n = x.shape[-1]
    t = np.arange(n) / SR
    # tape wow: read with a wobbling, accelerating head
    speed = 1.0 + 0.04 * np.sin(TAU * 5.5 * t) + 0.25 * (t / dur) ** 2
    pos = np.cumsum(speed)
    pos = pos / pos[-1] * (n - 1)
    x = np.stack([np.interp(pos, np.arange(n), x[c]) for c in range(2)])
    x *= np.clip(t / 0.3, 0, 1)
    return fade(normalize_peak(x, -2), 0.01, 0.004)


@sound("wake", ogg=True)
def wake():
    """He always gets up. Air returns, then a small high shimmer."""
    dur = 2.4
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    air = tv_filter(pink(dur, 131), "lp", 300 + 2500 * np.clip(t / 1.2, 0, 1), q=0.7) * np.sin(np.pi * np.clip(t / 2.2, 0, 1)) * 0.8
    shimmer = np.zeros(n)
    for k, f in enumerate((1174.66, 1760.0, 2637.0)):
        st = 0.5 + k * 0.12
        bt = np.clip(t - st, 0, None)
        shimmer += np.sin(TAU * f * t) * np.clip(bt / 0.3, 0, 1) * np.exp(-bt / 0.7) * (t > st) * 0.12
    x = convolve(air + shimmer, IR_OPEN, wet=0.35)
    return fade(normalize_peak(x[:, :n + SR], -6), 0.05, 0.5)


# ======================================================================= THINGS THAT TURN TOWARD HIM

@sound("phone_ring", ogg=True)
def phone_ring():
    """A telephone with no dial. Two bells and a hammer; loops every 3 s (ring-ring, pause)."""
    dur = 3.0
    n = int(round(dur * SR))
    out = np.zeros(n + SR)
    bells = (1980.0, 2340.0)
    ratios = [(1.0, 1.0, 0.5), (2.32, 0.5, 0.25), (4.25, 0.25, 0.12), (6.63, 0.12, 0.07)]
    strike_len = int(round(0.9 * SR))
    for burst_at in (0.0, 0.6):
        for k in range(int(0.4 * 22)):
            at = burst_at + k / 22.0
            f = bells[k % 2]
            tt = np.arange(strike_len) / SR
            s = sum(np.sin(TAU * f * r * tt) * a * np.exp(-tt / (tau * 0.45)) for r, a, tau in ratios)
            s += white(strike_len / SR, 140 + k) * np.exp(-tt / 0.002) * 0.3
            place(out, s, at, 0.5)
    out = bp(out, 450, 6000)
    out = soft_clip(out * 0.8, 1.5)
    # fold the bell tails into the loop start so it loops seamlessly
    loop = out[:n].copy()
    loop[:SR] += out[n:n + SR]
    return normalize_peak(loop, -3)


@sound("mic_swivel", ogg=False)
def mic_swivel():
    """A microphone turning on its mast toward his footsteps: servo whir and a dry stop."""
    dur = 0.75
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    f = 160 + 90 * np.clip(t / 0.55, 0, 1)
    ph = np.cumsum(f) / SR
    buzz = (2 * (ph % 1.0) - 1) * 0.4
    buzz = bp(buzz, 250, 3500) * np.sin(np.pi * np.clip(t / 0.6, 0, 1)) ** 0.5 * (t < 0.6)
    squeak = np.sin(TAU * np.cumsum(2600 + 300 * np.sin(TAU * 7 * t)) / SR) * np.exp(-((t - 0.3) / 0.1) ** 2) * 0.05
    bt = np.clip(t - 0.6, 0, None)
    stop = bp(white(dur, 151), 800, 5000) * np.exp(-bt / 0.004) * (t > 0.6) * 1.2
    x = buzz + squeak + stop
    return fade(normalize_peak(x, -8), 0.01, 0.05)


@sound("mic_feedback", ogg=True)
def mic_feedback():
    """Far masts listening to nothing: a feedback whistle that swells and dies."""
    dur = 3.2
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    f = 2210 * (1 + 0.004 * np.sin(TAU * 4.5 * t)) * (1 + 0.01 * t)
    tone = osc_sine(f, dur) + 0.15 * osc_sine(f * 2, dur) + 0.06 * osc_sine(f * 3, dur)
    env = np.sin(np.pi * np.clip(t / 2.9, 0, 1)) ** 3 * (0.85 + 0.15 * np.sin(TAU * 11 * t))
    x = bp(tone * env, 600, 6000)
    x = convolve(x, IR_OPEN, wet=0.4)
    return fade(normalize_peak(x[:, :n + SR], -6), 0.05, 0.4)


# ======================================================================= THE WATCHER: an empty broadcast

@sound("broadcast_hum", ogg=True)
def broadcast_hum():
    """Mains hum through a dead set: 50 Hz and its harmonics, buzzy odd partials,
    and the faint line whistle of a tube. Every partial completes whole cycles: loops clean."""
    dur = 16.0
    n = int(round(dur * SR)) * 2
    t = np.arange(n) / SR
    x = np.zeros(n)
    for h in range(1, 24):
        amp = (1.0 / h) * (1.6 if h % 2 else 0.7)
        if h == 1:
            amp = 0.9
        wob = 1 + 0.15 * np.sin(TAU * (h % 5 + 1) / dur * t + h)  # integer cycles per loop
        x += np.sin(TAU * 50 * h * t + h * 0.7) * amp * wob
    x = soft_clip(x * 0.35, 2.2)
    x = peak(x, 150, 1.0, 4)
    whine = np.sin(TAU * 15734.375 * t) * 0.008
    breath = 0.85 + 0.15 * np.sin(TAU * 3 / dur * t)
    x = x * breath + whine
    return normalize_rms(x[n // 2:], -20)  # second period: filters are settled, loops clean


@sound("broadcast_hiss", ogg=True)
def broadcast_hiss():
    """Snow: a channel with nothing on it. Field-rate flicker, little ticks of interference."""
    dur, xf = 16.0, 1.0
    total = dur + xf
    n = int(round(total * SR))
    chans = []
    for c in range(2):
        nz = white(total, 160 + c)
        x = bp(nz, 180, 9500, order=2)
        x = peak(x, 3200, 0.8, 5)
        field = 1 + 0.06 * np.sign(np.sin(TAU * 50 * np.arange(n) / SR + c))
        roll = 0.85 + 0.15 * slow_noise(total, 0.5, 162 + c)
        r = rng(163 + c)
        ticks = (r.uniform(0, 1, n) < 6 / SR) * r.uniform(-1, 1, n)
        ticks = bp(ticks, 1500, 8000) * 8
        chans.append(x * field * roll + ticks)
    x = make_loop(np.stack(chans), xf)
    return normalize_rms(x, -22)


@sound("broadcast_tone", ogg=True)
def broadcast_tone():
    """The held tone: a test signal nobody is there to hear. 1 kHz, whole cycles, loops clean."""
    dur = 8.0
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    x = np.sin(TAU * 1000 * t) + 0.03 * np.sin(TAU * 2000 * t) + 0.012 * np.sin(TAU * 3000 * t)
    x *= 1 + 0.03 * np.sin(TAU * 2 / dur * t)
    return normalize_rms(x, -21)


@sound("tv_on", ogg=True)
def tv_on():
    dur = 2.2
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    click = bp(white(dur, 171), 1000, 7000) * np.exp(-t / 0.003) * 0.8
    bt = np.clip(t - 0.05, 0, None)
    degauss = sum(np.sin(TAU * 60 * h * t) / h for h in range(1, 8)) * np.exp(-bt / 0.45) * (0.6 + 0.4 * np.sin(TAU * 3 * t)) * (t > 0.05) * 0.5
    degauss = lp(degauss, 900)
    whine = np.sin(TAU * 15734.375 * t) * np.clip((t - 0.1) / 0.4, 0, 1) * 0.03
    snow = bp(white(dur, 172), 200, 9000) * np.clip((t - 0.3) / 0.9, 0, 1) * 0.25
    x = click + degauss + whine + snow
    return fade(normalize_peak(x, -3), 0.0005, 0.3)


@sound("tv_off", ogg=True)
def tv_off():
    """A set's eyes closing: the picture collapses to a point, the snow stops, then nothing."""
    dur = 1.8
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    snow = bp(white(dur, 181), 200, 9000) * (t < 0.05) * 0.4
    f = 40 + 1300 * np.exp(-t / 0.08)
    zip_ = osc_sine(f, dur)
    zip_ = soft_clip(zip_ * 2, 2) * np.exp(-t / 0.18) * 0.6
    tick = bp(white(dur, 182), 1500, 8000) * np.exp(-t / 0.002)
    bt = np.clip(t - 0.12, 0, None)
    discharge = _crackles(dur, 20, 183, 0.25) * np.exp(-bt / 0.25) * (t > 0.12)
    thump = lp(white(dur, 184), 150) * np.exp(-t / 0.06) * 2
    x = snow + zip_ + tick + discharge + thump
    x = convolve(x, IR_SMALL, wet=0.15)
    return fade(normalize_peak(x[:, :n], -2), 0.0005, 0.6)


@sound("static_burst", ogg=False)
def static_burst():
    dur = 0.7
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    x = bp(white(dur, 191), 250, 9000)
    gate = (np.sin(TAU * 31 * t) > -0.2) * 0.7 + 0.3
    x = x * gate * np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 0.4
    return fade(normalize_peak(x, -4), 0.002, 0.05)


@sound("stare_land", ogg=True)
def stare_land():
    """The moment the stare falls on him. The world's air drops out and the dead channel opens."""
    dur = 3.5
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    sub = osc_sine(45 - 18 * np.clip(t / 1.5, 0, 1), dur) * np.clip(t / 0.15, 0, 1) * np.exp(-t / 1.4) * 0.9
    suck = tv_filter(pink(dur, 201), "lp", 6000 * np.exp(-t / 0.15) + 200, q=0.9) * np.exp(-t / 0.2) * 0.8
    hiss = bp(white(dur, 202), 300, 8000) * np.clip((t - 0.25) / 1.2, 0, 1) * np.exp(-np.clip(t - 1.6, 0, None) / 0.9) * 0.18
    tone = np.sin(TAU * 1000 * t) * np.clip((t - 0.35) / 0.8, 0, 1) * np.exp(-np.clip(t - 2.0, 0, None) / 0.6) * 0.1
    x = sub + suck + hiss + tone
    return fade(normalize_peak(x, -1.5), 0.002, 0.4)


# ======================================================================= GIANTS: late and low

def _giant_impact(seed, dur, f_hi, f_lo, crunch=1.0, ir=IR_VAST, tail=6.0):
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    f = f_lo + (f_hi - f_lo) * np.exp(-t / 0.35)
    sub = osc_sine(f, dur) * np.exp(-t / 1.1) * np.clip(t / 0.02, 0, 1) * 1.2
    body = lp(brown(dur, seed), 260, order=4) * np.exp(-t / 0.45) * 1.6
    grit = lp(_grains(dur, 2500, seed + 1, 200, 2500), 1400) * np.exp(-t / 0.3) * 4 * crunch
    debris = lp(_crackles(dur, 25, seed + 2, 1.0), 2000) * np.clip((t - 0.15) / 0.3, 0, 1) * np.exp(-np.clip(t - 0.4, 0, None) / 0.8) * crunch * 0.6
    x = fade(sub + body + grit + debris, 0.0, 0.4)
    x = convolve(x, ir, wet=0.55)
    x = lp(x, 2200, order=4)
    return x[:, :n + int(round(tail * SR))]


@sound("giant_footfall", ogg=True)
def giant_footfall():
    return fade(normalize_peak(_giant_impact(211, 2.5, 52, 23), -1.0), 0.002, 1.5)


@sound("giant_boom", ogg=True)
def giant_boom():
    x = _giant_impact(221, 3.5, 44, 19, crunch=1.4, ir=IR_HALL, tail=7.0)
    return fade(normalize_peak(x, -1.0), 0.002, 2.0)


@sound("giant_settle", ogg=True)
def giant_settle():
    x = _giant_impact(231, 1.4, 80, 38, crunch=0.6, ir=IR_OPEN, tail=2.5)
    return fade(normalize_peak(x, -1.5), 0.002, 0.8)


def _stick_slip(dur, seed, rate_lo, rate_hi):
    """Jerky friction: an amplitude pattern of uneven little lurches."""
    r = rng(seed)
    n = int(round(dur * SR))
    out = np.zeros(n)
    tpos = 0.0
    while tpos < dur:
        tpos += 1.0 / r.uniform(rate_lo, rate_hi)
        i = int(round(tpos * SR))
        ln = int(r.uniform(0.03, 0.12) * SR)
        if i + ln >= n:
            break
        w = np.sin(np.linspace(0, np.pi, ln)) ** 2 * r.uniform(0.3, 1.0)
        out[i:i + ln] += w
    return out


@sound("giant_grind", ogg=True)
def giant_grind():
    """Something the size of a hill moving when nobody looks. Stone on stone, very slow."""
    dur = 6.0
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    swell = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 1.2
    slip = 0.35 + _stick_slip(dur, 241, 6, 14)
    center = 190 + 120 * slow_noise(dur, 0.6, 242)
    grind = tv_filter(brown(dur, 243), "bp", center, q=1.6) * slip * 2.2
    grit = lp(_grains(dur, 1500, 244, 300, 3000), 1800) * slip * 1.5
    sub = osc_sine(29 + 3 * slow_noise(dur, 0.3, 245), dur) * 0.6
    x = (grind + grit + sub) * swell
    x = convolve(x, IR_VAST, wet=0.5)
    x = lp(x, 2200, order=4)
    return fade(normalize_peak(x[:, :n + 4 * SR], -1.0), 0.3, 2.0)


@sound("giant_groan", ogg=True)
def giant_groan():
    """Stone bending under its own weight: a slow creak far below speech."""
    dur = 5.0
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    rate = 16 + 10 * slow_noise(dur, 0.8, 251) + 6 * np.sin(np.pi * t / dur)
    ph = np.cumsum(rate) / SR
    pulses = np.maximum(0, np.sin(TAU * ph)) ** 12
    pulses += white(dur, 252) * 0.02
    creak = sum(resonator(pulses, f, q) * g for f, q, g in ((132, 9, 1.0), (297, 12, 0.7), (611, 14, 0.4), (1130, 10, 0.15)))
    env = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 1.5
    x = creak * env * 4 + lp(brown(dur, 253), 90) * env * 0.4
    x = convolve(x, IR_VAST, wet=0.5)
    x = lp(x, 2400)
    return fade(normalize_peak(x[:, :n + 4 * SR], -1.0), 0.2, 2.0)


@sound("giant_rumble", ogg=True)
def giant_rumble():
    dur = 9.0
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    env = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 2
    roll = lp(brown(dur, 261), 140, order=3) * (0.6 + 0.4 * slow_noise(dur, 1.5, 262))
    beat = (osc_sine(28, dur) + osc_sine(31.3, dur) * 0.8) * 0.4
    grit = lp(_grains(dur, 800, 263, 200, 1500), 900) * 0.8
    x = (roll * 1.5 + beat + grit) * env
    x = convolve(x, IR_VAST, wet=0.45)
    return fade(normalize_peak(lp(x, 1800)[:, :n + 3 * SR], -1.0), 0.5, 2.0)


@sound("sphere_roll_loop", ogg=True)
def sphere_roll_loop():
    """A rolling sphere. Pitch it down for cathedral-sized ones; the seam knocks once a turn."""
    dur = 8.0
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    rumble = lp(brown(dur + 1, 271), 220, order=3)
    rumble = make_loop(rumble, 1.0)
    turn = 2.0  # knocks per second: 16 per loop, whole number, loops clean
    knock = np.zeros(n)
    for k in range(int(dur * turn)):
        at = int(k / turn * SR)
        ln = int(round(0.08 * SR))
        tt = np.arange(ln) / SR
        s = (lp(white(0.08, 272 + k), 500) * 2 + np.sin(TAU * 95 * tt)) * np.exp(-tt / 0.02)
        knock[at:at + ln] += s * (0.8 + 0.2 * np.sin(k))
    x = rumble * (0.85 + 0.15 * np.sin(TAU * turn * t)) + knock * 0.5
    x = dc_block(np.concatenate([x, x]))[n:]
    return normalize_rms(x, -18)


@sound("eyelids_close", ogg=True)
def eyelids_close():
    """The great lids come down. A slow grind that falls in pitch, one soft contact, then silence.
    The tail is cut short on purpose: what follows is the absence of the broadcast."""
    dur = 7.5
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    contact = 6.2
    move = np.clip(t / contact, 0, 1)
    env = np.sin(np.pi * 0.5 * np.clip(t / 1.8, 0, 1)) * (t < contact) * (1 - 0.3 * move)
    slip = 0.5 + _stick_slip(dur, 281, 4, 9) * (1 - move * 0.6)
    center = 420 * (1 - move) + 90 * move
    grind = tv_filter(brown(dur, 282), "bp", center, q=1.8) * slip * env * 2.4
    sub = osc_sine(42 - 18 * move, dur) * env * 0.7
    bt = np.clip(t - contact, 0, None)
    thud = (osc_sine(31 - 6 * np.clip(bt / 0.6, 0, 1), dur) * 1.1 + lp(brown(dur, 283), 160) * 1.4) * np.exp(-bt / 0.35) * np.clip(bt / 0.03, 0, 1)
    x = grind + sub + thud
    wet = convolve(x, make_ir(2.5, 284, predelay=0.05, lo_tau=0.6, hi_tau=0.2), wet=0.4)
    wet = lp(wet, 2400)[:, :n]
    # and then nothing
    wet *= np.clip((dur - t) / 0.5, 0, 1)
    return fade(normalize_peak(wet, -1.0), 0.4, 0.05)


# ======================================================================= INKS: the only music

def _glass(f, dur, seed, bow_attack=0.8, mallet=0.0):
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    r = rng(seed)
    x = np.zeros(n)
    for ratio, amp in ((1, 1.0), (2, 0.35), (3, 0.12), (4.02, 0.06), (0.5, 0.25)):
        det = 1 + r.uniform(-0.0015, 0.0015)
        vib = 1 + 0.002 * np.sin(TAU * r.uniform(4.5, 5.5) * t + r.uniform(0, 6))
        x += osc_sine(f * ratio * det * vib, dur) * amp
    bow = np.clip(t / bow_attack, 0, 1) ** 2
    if mallet:
        hit = sum(np.sin(TAU * f * m * t) * a * np.exp(-t / tau) for m, a, tau in ((1, 1, 1.5), (2.76, 0.4, 0.5), (5.4, 0.2, 0.2)))
        return x * bow + hit * mallet
    return x * bow


for _ink, _hz in INK_HZ.items():
    def _take(ink=_ink, hz=_hz):
        """Carried out of a mended region: the ink's own note, held in the hand."""
        dur = 5.0
        n = int(round(dur * SR))
        t = np.arange(n) / SR
        x = _glass(hz * 2, dur, 300 + int(hz), bow_attack=0.6) * np.exp(-np.clip(t - 1.2, 0, None) / 1.2) * 0.6
        x += _glass(hz * 3, dur, 301 + int(hz), bow_attack=1.0) * np.exp(-np.clip(t - 1.4, 0, None) / 1.0) * 0.18
        x = convolve(fade(x, 0.0, 0.5), IR_HALL, wet=0.45)
        return fade(normalize_peak(x[:, :n + 4 * SR], -3), 0.02, 2.5)

    def _home(ink=_ink, hz=_hz):
        """Planted in the spiral: struck once, then it blooms across three octaves."""
        dur = 7.0
        n = int(round(dur * SR))
        t = np.arange(n) / SR
        bloom = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 1.2
        x = _glass(hz, dur, 310 + int(hz), bow_attack=2.0, mallet=0.0) * bloom * 0.5
        x += _glass(hz * 2, dur, 311 + int(hz), bow_attack=0.05, mallet=1.2) * np.exp(-t / 2.5) * 0.6
        x += _glass(hz * 4, dur, 312 + int(hz), bow_attack=2.5) * bloom * 0.12
        x += osc_sine(hz / 2, dur) * bloom * 0.35
        x = convolve(fade(x, 0.0, 1.0), IR_HALL, wet=0.55)
        return fade(normalize_peak(x[:, :n + 6 * SR], -2), 0.01, 3.0)

    sound(f"ink_{_ink}_take", ogg=True)(_take)
    sound(f"ink_{_ink}_home", ogg=True)(_home)


@sound("mend", ogg=True)
def mend():
    """A region mended: the held breath lets go. D, A and E settle from high to low."""
    dur = 9.0
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    x = np.zeros(n)
    for k, f in enumerate((659.26, 440.0, 293.66, 146.83)):
        st = k * 0.55
        sig = _glass(f, dur, 400 + k, bow_attack=1.4)
        x += np.roll(sig, int(round(st * SR))) * (t > st) * (0.55 - 0.08 * k)
    x *= np.clip((dur - t) / 3.5, 0, 1)
    x += osc_sine(73.42, dur) * np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 2 * 0.25
    x = convolve(fade(x, 0.0, 1.0), IR_HALL, wet=0.6)
    return fade(normalize_peak(x[:, :n + 5 * SR], -2), 0.05, 3.0)


# ======================================================================= BEDS: each region's air

def _wind(total, seed, lo=150, hi=900, gust_rate=0.08, q=0.8, gain=1.0):
    gust = np.clip(0.5 + 0.5 * slow_noise(total, gust_rate, seed), 0, 1)
    gust = 0.25 + 0.75 * gust ** 1.5
    center = lo + (hi - lo) * gust
    w = tv_filter(pink(total, seed + 1), "bp", center, q=q)
    return w * gust * gain, gust


def _bed_out(chans, xf, db=-24):
    x = make_loop(dc_block(np.stack(chans)), xf)
    return normalize_rms(x, db)


@sound("bed_hub_night", ogg=True)
def bed_hub_night():
    """Night shore around the crater: dune wind, blown sand, far surf, the pressure of the pit."""
    dur, xf = 48.0, 4.0
    total = dur + xf
    n = int(round(total * SR))
    t = np.arange(n) / SR
    chans = []
    r = rng(500)
    surf_times = []
    s = 2.0
    while s < total:
        surf_times.append((s, r.uniform(-0.7, 0.7), r.uniform(0.6, 1.0)))
        s += r.uniform(8.5, 13.0)
    for c in range(2):
        wind, gust = _wind(total, 510 + c * 7, 140, 700, 0.07, 0.7, 1.0)
        sand = hp(white(total, 520 + c), 3800) * gust ** 2.5 * (0.6 + 0.4 * slow_noise(total, 9, 521 + c)) * 0.12
        surf = np.zeros(n)
        for at, p, g in surf_times:
            ln = int(round(9.0 * SR))
            i = int(round(at * SR))
            if i + ln > n:
                ln = n - i
            tt = np.arange(ln) / SR
            env = np.clip(tt / 3.0, 0, 1) ** 2 * np.exp(-np.clip(tt - 3.0, 0, None) / 2.2)
            wash = tv_filter(brown(ln / SR, int(at * 100) + c), "lp", 250 + 650 * env, q=0.7) * env
            wash += hp(pink(ln / SR, int(at * 100) + 50 + c), 1500) * np.clip((tt - 2.8) / 0.8, 0, 1) * np.exp(-np.clip(tt - 3.4, 0, None) / 1.3) * 0.08
            side = np.cos((p + 1) * np.pi / 4) if c == 0 else np.sin((p + 1) * np.pi / 4)
            surf[i:i + ln] += wash * g * side * 0.9
        pit = (np.sin(TAU * 31 * t) * 0.5 + lp(brown(total, 530 + c), 60) * 0.6) * (0.7 + 0.3 * slow_noise(total, 0.05, 531)) * 0.25
        chans.append(wind + sand + surf + pit)
    return _bed_out(chans, xf)


@sound("bed_lake", ogg=True)
def bed_lake():
    """The forgotten place. Almost nothing: still air, water touching stone now and then,
    and no broadcast at all, because he has turned his back on it."""
    dur, xf = 48.0, 4.0
    total = dur + xf
    n = int(round(total * SR))
    chans = [lp(pink(total, 540 + c), 260) * 0.35 * (0.8 + 0.2 * slow_noise(total, 0.05, 542 + c)) for c in range(2)]
    r = rng(545)
    tpos = 1.0
    while tpos < total - 1:
        lap = step_water(int(r.integers(1 << 20)))
        lap = lp(lap, r.uniform(1200, 2600)) * r.uniform(0.15, 0.4)
        p = r.uniform(-0.9, 0.9)
        st = pan(lap, p)
        place(chans[0], st[0], tpos)
        place(chans[1], st[1], tpos)
        tpos += r.uniform(1.8, 5.5)
    x = np.stack(chans)
    x = convolve(x, IR_OPEN, wet=0.35)[:, :n]
    t = np.arange(n) / SR
    glass = (np.sin(TAU * 1174.66 * t) + 0.7 * np.sin(TAU * 1760.0 * t + 1)) * (0.5 + 0.5 * slow_noise(total, 0.04, 547)) ** 3 * 0.004
    x = x + glass
    return _bed_out([x[0], x[1]], xf, db=-30)


@sound("bed_checker", ogg=True)
def bed_checker():
    """The checker plain: open wind with a hollow whistle across the spheres, and the tide
    breathing under it every 16 s (three tides a loop)."""
    dur, xf = 48.0, 4.0
    total = dur + xf
    n = int(round(total * SR))
    t = np.arange(n) / SR
    tide = (0.5 - 0.5 * np.cos(TAU * t / 16.0)) ** 2
    chans = []
    for c in range(2):
        wind, gust = _wind(total, 560 + c * 5, 200, 1300, 0.09, 0.8, 0.9)
        whistle = tv_filter(pink(total, 565 + c), "bp", 640 + 220 * slow_noise(total, 0.12, 566), q=9) * gust ** 2 * 0.5
        swell = (lp(brown(total, 567 + c), 110, order=3) * 0.9 + np.sin(TAU * 38 * t) * 0.35) * (0.25 + 0.75 * tide)
        chans.append(wind + whistle + swell)
    r = rng(569)
    tpos = 2.0
    while tpos < total - 1:
        tock = lp(step_tile(int(r.integers(1 << 20))), 2500) * r.uniform(0.05, 0.14)
        st = pan(tock, r.uniform(-0.8, 0.8))
        place(chans[0], st[0], tpos)
        place(chans[1], st[1], tpos)
        tpos += r.uniform(2.5, 7.0)
    x = convolve(np.stack(chans), IR_VAST, wet=0.12)[:, :n]
    return _bed_out([x[0], x[1]], xf)


@sound("bed_grid", ogg=True)
def bed_grid():
    """The Red Grid: pressed flat. A low pressure that beats against itself, fog pouring
    down the sag somewhere far, a thin electric fizz in the lines."""
    dur, xf = 48.0, 4.0
    total = dur + xf
    n = int(round(total * SR))
    t = np.arange(n) / SR
    chans = []
    for c in range(2):
        press = (np.sin(TAU * 41.2 * t) + 0.8 * np.sin(TAU * 41.7 * t + c) + 0.35 * np.sin(TAU * 61.8 * t)) * 0.35
        fall = lp(brown(total, 580 + c), 520, order=2) * (0.8 + 0.2 * slow_noise(total, 0.3, 581 + c)) * 0.8
        r = rng(582 + c)
        fizz = (r.uniform(0, 1, n) < 40 / SR) * r.uniform(-1, 1, n)
        fizz = bp(fizz, 5000, 12000) * 0.8 + hp(white(total, 583 + c), 7000) * 0.01
        chans.append(press + fall + fizz)
    x = convolve(np.stack(chans), IR_VAST, wet=0.2)[:, :n]
    return _bed_out([x[0], x[1]], xf)


@sound("bed_mountain", ogg=True)
def bed_mountain():
    """On the tie road: high wind, deep pressure, and the microphone forest whistling far off."""
    dur, xf = 48.0, 4.0
    total = dur + xf
    n = int(round(total * SR))
    t = np.arange(n) / SR
    chans = []
    for c in range(2):
        wind, gust = _wind(total, 600 + c * 3, 250, 1800, 0.12, 0.9, 1.1)
        whistle = sum(tv_filter(pink(total, 605 + c + k), "bp", f, q=14) for k, f in enumerate((1120, 1690))) * gust ** 3 * 0.6
        pressure = (np.sin(TAU * 27.5 * t) * 0.4 + lp(brown(total, 608 + c), 70) * 0.7) * 0.5
        chans.append(wind + whistle + pressure)
    r = rng(609)
    tpos = 3.0
    fb = mic_feedback()
    while tpos < total - 4:
        g = r.uniform(0.06, 0.15)
        pitch = r.uniform(0.8, 1.25)
        src = np.stack([np.interp(np.arange(0, fb.shape[-1], pitch), np.arange(fb.shape[-1]), fb[k]) for k in range(2)])
        place(chans[0], src[0], tpos, g)
        place(chans[1], src[1], tpos, g)
        tpos += r.uniform(7, 14)
    x = convolve(np.stack(chans), IR_VAST, wet=0.15)[:, :n]
    return _bed_out([x[0], x[1]], xf)


@sound("bed_dawn", ogg=True)
def bed_dawn():
    """After: warm air, a calm sea, and the three inks held as one very quiet chord."""
    dur, xf = 48.0, 4.0
    total = dur + xf
    n = int(round(total * SR))
    t = np.arange(n) / SR
    chans = []
    for c in range(2):
        air = lp(pink(total, 620 + c), 1400) * (0.8 + 0.2 * slow_noise(total, 0.04, 621 + c)) * 0.4
        sea = tv_filter(brown(total, 622 + c), "lp", 300 + 250 * (0.5 + 0.5 * np.sin(TAU * t / 12.0 + c)), q=0.7) * (0.6 + 0.4 * np.sin(TAU * t / 12.0 + c)) * 0.6
        chord = sum(np.sin(TAU * f * t + k) for k, f in enumerate((146.83, 220.0, 329.63, 415.30))) * 0.012 * (0.6 + 0.4 * slow_noise(total, 0.03, 623))
        chans.append(air + sea + chord)
    return _bed_out(chans, xf, db=-28)


# ======================================================================= main

# Seamless loops: never filtered or faded after they are cut.
LOOP_PREFIXES = ("bed_", "broadcast_", "fire_loop", "sphere_roll_loop", "phone_ring")

# Placed in the world with AudioStreamPlayer3D, so they ship as mono.
MONO_PREFIXES = ("giant_", "sphere_", "phone_", "mic_", "fire_loop", "fire_ignite")


def main():
    os.makedirs(OUT, exist_ok=True)
    only = sys.argv[1:]
    for name, (fn, ogg) in SOUNDS.items():
        if only and not any(w in name for w in only):
            continue
        x = fn()
        if x.ndim == 2 and x.shape[0] != 2:
            x = x.T
        if not name.startswith(LOOP_PREFIXES):
            x = fade(dc_block(x), 0.0005, 0.01)
        if x.ndim == 2 and name.startswith(MONO_PREFIXES):
            x = normalize_peak(to_mono(x), 20 * np.log10(np.max(np.abs(x)) + 1e-12))
        path = write(name, x, ogg)
        dur = x.shape[-1] / SR
        print(f"{name:24s} {dur:6.2f}s  {'stereo' if x.ndim == 2 else 'mono  '}  {os.path.getsize(path) / 1024:7.1f} KB")


if __name__ == "__main__":
    main()
