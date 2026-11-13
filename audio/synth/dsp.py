"""Small DSP kit for the Little Man sound library.

Everything here is deterministic (seeded) so `python3 audio/synth/build_library.py`
always rebuilds the same files. Requires numpy and scipy.
"""
import numpy as np
from scipy import signal

SR = 48000
TAU = 2.0 * np.pi


def rng(seed):
    return np.random.default_rng(seed)


def t_axis(dur):
    return np.arange(int(round(dur * SR))) / SR


# ---------------------------------------------------------------- noise

def white(dur, seed):
    return rng(seed).standard_normal(int(round(dur * SR)))


def pink(dur, seed):
    n = int(round(dur * SR))
    x = rng(seed).standard_normal(n)
    f = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(n, 1 / SR)
    freqs[0] = freqs[1]
    f /= np.sqrt(freqs)
    y = np.fft.irfft(f, n)
    return y / (np.std(y) + 1e-12)


def brown(dur, seed):
    n = int(round(dur * SR))
    x = rng(seed).standard_normal(n)
    f = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(n, 1 / SR)
    freqs[0] = freqs[1]
    f /= freqs
    y = np.fft.irfft(f, n)
    y = hp(y, 12)
    return y / (np.std(y) + 1e-12)


def slow_noise(dur, rate_hz, seed, smooth=4):
    """A smooth random control signal in roughly [-1, 1], changing about `rate_hz` times a second."""
    n = int(round(dur * SR))
    pts = max(4, int(dur * rate_hz) + 4)
    r = rng(seed).uniform(-1, 1, pts)
    x = np.linspace(0, pts - 3, n)
    i = np.floor(x).astype(int)
    f = x - i
    # Catmull-Rom through random points.
    p0, p1, p2, p3 = r[i], r[i + 1], r[i + 2], r[np.minimum(i + 3, pts - 1)]
    y = 0.5 * ((2 * p1) + (-p0 + p2) * f + (2 * p0 - 5 * p1 + 4 * p2 - p3) * f * f + (-p0 + 3 * p1 - 3 * p2 + p3) * f ** 3)
    return np.clip(y, -1.2, 1.2)


# ---------------------------------------------------------------- filters

def _sos(kind, f, order=2):
    nyq = SR / 2
    if isinstance(f, (list, tuple)):
        wn = [max(1.0, min(nyq * 0.99, v)) / nyq for v in f]
    else:
        wn = max(1.0, min(nyq * 0.99, f)) / nyq
    return signal.butter(order, wn, btype=kind, output="sos")


def lp(x, f, order=2):
    return signal.sosfilt(_sos("lowpass", f, order), x, axis=-1)


def hp(x, f, order=2):
    return signal.sosfilt(_sos("highpass", f, order), x, axis=-1)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(_sos("bandpass", [lo, hi], order), x, axis=-1)


def peak(x, f, q, gain_db):
    """RBJ peaking EQ."""
    a = 10 ** (gain_db / 40)
    w0 = TAU * f / SR
    alpha = np.sin(w0) / (2 * q)
    b = [1 + alpha * a, -2 * np.cos(w0), 1 - alpha * a]
    aa = [1 + alpha / a, -2 * np.cos(w0), 1 - alpha / a]
    return signal.lfilter(b, aa, x, axis=-1)


def resonator(x, f, q):
    """Two-pole resonant bandpass, normalised to unity peak."""
    w0 = TAU * f / SR
    alpha = np.sin(w0) / (2 * q)
    b = [alpha, 0, -alpha]
    a = [1 + alpha, -2 * np.cos(w0), 1 - alpha]
    return signal.lfilter(b, a, x, axis=-1)


def svf_lp(x, cutoff, q=0.7):
    """Time-varying state-variable lowpass. `cutoff` is an array (Hz) as long as x."""
    cutoff = np.broadcast_to(cutoff, x.shape)
    g = np.tan(np.pi * np.clip(cutoff, 10, SR * 0.45) / SR)
    k = 1.0 / q
    a1 = 1.0 / (1.0 + g * (g + k))
    a2 = g * a1
    a3 = g * a2
    ic1 = ic2 = 0.0
    out = np.empty_like(x)
    for n in range(len(x)):
        v3 = x[n] - ic2
        v1 = a1[n] * ic1 + a2[n] * v3
        v2 = ic2 + a2[n] * ic1 + a3[n] * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        out[n] = v2
    return out


def svf_bp(x, center, q=4.0):
    center = np.broadcast_to(center, x.shape)
    g = np.tan(np.pi * np.clip(center, 10, SR * 0.45) / SR)
    k = 1.0 / q
    a1 = 1.0 / (1.0 + g * (g + k))
    a2 = g * a1
    a3 = g * a2
    ic1 = ic2 = 0.0
    out = np.empty_like(x)
    for n in range(len(x)):
        v3 = x[n] - ic2
        v1 = a1[n] * ic1 + a2[n] * v3
        v2 = ic2 + a2[n] * ic1 + a3[n] * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        out[n] = v1 * k
    return out


# ---------------------------------------------------------------- envelopes and shaping

def env_adsr(n, a, d, s, r, total=None):
    total = total or n / SR
    t = np.arange(n) / SR
    e = np.where(t < a, t / max(a, 1e-6), 1.0)
    e = np.where((t >= a) & (t < a + d), 1 - (1 - s) * (t - a) / max(d, 1e-6), e)
    e = np.where(t >= a + d, s, e)
    rel_start = total - r
    e = np.where(t >= rel_start, e * np.clip((total - t) / max(r, 1e-6), 0, 1), e)
    return e


def exp_decay(n, tau):
    return np.exp(-np.arange(n) / SR / tau)


def fade(x, fin=0.005, fout=0.02):
    x = x.copy()
    n_in = int(round(fin * SR))
    n_out = int(round(fout * SR))
    if n_in:
        x[..., :n_in] *= np.sin(np.linspace(0, np.pi / 2, n_in)) ** 2
    if n_out:
        x[..., -n_out:] *= np.cos(np.linspace(0, np.pi / 2, n_out)) ** 2
    return x


def soft_clip(x, drive=1.0):
    return np.tanh(x * drive) / np.tanh(drive)


def pad(x, dur_after):
    extra = np.zeros(x.shape[:-1] + (int(round(dur_after * SR)),))
    return np.concatenate([x, extra], axis=-1)


def place(dst, src, at_s, gain=1.0):
    i = int(round(at_s * SR))
    if i >= dst.shape[-1]:
        return dst
    m = min(dst.shape[-1] - i, src.shape[-1])
    dst[..., i:i + m] += src[..., :m] * gain
    return dst


# ---------------------------------------------------------------- oscillators

def osc_sine(freq, dur, phase=0.0):
    """freq may be a scalar or an array (Hz per sample)."""
    n = int(round(dur * SR))
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    ph = phase + np.cumsum(f) / SR
    return np.sin(TAU * ph)


def additive(freq, dur, partials, phase_seed=0):
    """partials: list of (ratio, amp, decay_tau or None)."""
    n = int(round(dur * SR))
    r = rng(phase_seed)
    out = np.zeros(n)
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    base = np.cumsum(f) / SR
    for ratio, amp, tau in partials:
        p = np.sin(TAU * (base * ratio + r.uniform()))
        if tau:
            p *= exp_decay(n, tau)
        out += amp * p
    return out


# ---------------------------------------------------------------- space

def make_ir(dur, seed, predelay=0.0, lo_tau=None, hi_tau=None, density_ms=0.0, stereo=True, early=None):
    """Synthetic stereo impulse response. Lows ring longer than highs (air absorption)."""
    lo_tau = lo_tau or dur / 5
    hi_tau = hi_tau or dur / 12
    chans = []
    for c in range(2 if stereo else 1):
        n = int(round(dur * SR))
        nz = rng(seed + c * 101).standard_normal(n)
        low = lp(nz, 900) * exp_decay(n, lo_tau)
        high = hp(nz, 900) * exp_decay(n, hi_tau)
        ir = low * 1.4 + high * 0.7
        ir *= np.clip(np.arange(n) / (0.004 * SR), 0, 1)  # soften onset
        if early:
            for (ms, g) in early:
                i = int(ms / 1000 * SR)
                if i < n:
                    ir[i] += g * (1 if (c + i) % 2 else -1)
        if predelay:
            ir = np.concatenate([np.zeros(int(round(predelay * SR))), ir])
        chans.append(ir)
    ir = np.stack(chans)
    return ir / np.sqrt(np.sum(ir ** 2, axis=-1, keepdims=True))


def convolve(x, ir, wet=0.3, dry=1.0):
    """x mono (n,) or stereo (2, n); returns stereo (2, n + len(ir) - 1)."""
    if x.ndim == 1:
        x = np.stack([x, x])
    if ir.ndim == 1:
        ir = np.stack([ir, ir])
    out_len = x.shape[-1] + ir.shape[-1] - 1
    y = np.zeros((2, out_len))
    for c in range(2):
        y[c] = signal.fftconvolve(x[c], ir[c]) * wet
        y[c, :x.shape[-1]] += x[c] * dry
    return y


def to_mono(x):
    return x if x.ndim == 1 else x.mean(axis=0)


def widen(x, seed, amount=0.5, max_delay_ms=11):
    """Mono to stereo through a pair of short decorrelating delays."""
    if x.ndim == 2:
        return x
    r = rng(seed)
    d1 = int(r.uniform(2, max_delay_ms) / 1000 * SR)
    d2 = int(r.uniform(2, max_delay_ms) / 1000 * SR)
    l = x + amount * np.concatenate([np.zeros(d1), x[:-d1]])
    rr = x - amount * np.concatenate([np.zeros(d2), x[:-d2]]) * 0.9
    return np.stack([l, rr]) / (1 + amount)


def pan(x, p):
    """p in [-1, 1]. Equal power."""
    a = (p + 1) * np.pi / 4
    return np.stack([x * np.cos(a), x * np.sin(a)])


# ---------------------------------------------------------------- loops and levels

def make_loop(x, xfade):
    """x has `xfade` seconds of extra tail. Returns a seamless loop of len(x) - xfade."""
    c = int(round(xfade * SR))
    body = x[..., :-c].copy()
    tail = x[..., -c:]
    w = np.linspace(0, np.pi / 2, c)
    body[..., :c] = body[..., :c] * np.sin(w) + tail * np.cos(w)
    return body


def rms_db(x):
    return 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-12)


def normalize_peak(x, db=-1.0):
    return x * (10 ** (db / 20) / (np.max(np.abs(x)) + 1e-12))


def normalize_rms(x, db, ceiling=-1.0):
    y = x * (10 ** ((db - rms_db(x)) / 20))
    pk = np.max(np.abs(y))
    lim = 10 ** (ceiling / 20)
    if pk > lim:
        # gentle limiting instead of hard scaling, keeps the bed's level
        y = np.tanh(y / lim * 0.9) * lim / np.tanh(0.9)
    return y


def dc_block(x):
    return hp(x, 8, order=1)


# ---------------------------------------------------------------- fast time-varying biquads (blockwise)

def _rbj(kind, f, q):
    w0 = TAU * np.clip(f, 10, SR * 0.45) / SR
    alpha = np.sin(w0) / (2 * q)
    c = np.cos(w0)
    if kind == "lp":
        b = [(1 - c) / 2, 1 - c, (1 - c) / 2]
    elif kind == "hp":
        b = [(1 + c) / 2, -(1 + c), (1 + c) / 2]
    else:  # constant 0 dB peak bandpass
        b = [alpha, 0.0, -alpha]
    a = [1 + alpha, -2 * c, 1 - alpha]
    return np.array(b) / a[0], np.array(a) / a[0]


def tv_filter(x, kind, freq, q=0.707, block=128):
    """Time-varying biquad. `freq` is an array (Hz) as long as x, or a scalar."""
    freq = np.broadcast_to(np.asarray(freq, dtype=float), x.shape)
    out = np.empty_like(x)
    zi = np.zeros(2)
    for s in range(0, len(x), block):
        e = min(len(x), s + block)
        b, a = _rbj(kind, float(freq[(s + e) // 2]), q)
        out[s:e], zi = signal.lfilter(b, a, x[s:e], zi=zi)
    return out
