"""Float reference for VOID SCRAPE — same law as modules/void/void.asm.

Order: white → HPF/COLR → FDBK+DRV → AM on noise → WID → BAL vs dry → out.
wet = (1−BAL)·dry + BAL·noise''  with  noise'' = driven_noise·((1−DPTH)+DPTH·uni).
BAL=0 ⇒ exact dry always (AM/DRV/FDBK never touch dry).
WID: 0 = mono (L=R=mid); >0 = second white → same HPF/COLR/DRV (no FDBK)
→ same AM; L=mid+(w/2)·side, R=mid−(w/2)·side (mono keeps mid/LFO).
"""
from __future__ import annotations

import math

FS = 44100.0
A_NOISE = 0x19660D
C_NOISE = 0x6EF35F
_ENV_K = 0x51eb8 / float(1 << 23)  # ≈0.04 — matches asm #$051eb8
_DC_K = 0.02  # feedback DC tracker — matches asm #$028f5c


def rate_hz(k: int) -> float:
    k = max(0, min(127, int(k)))
    return 2.0 * (100.0) ** (k / 127.0)  # 2 Hz .. 200 Hz


def rate_inc(k: int) -> float:
    """Phase step in Q23 units where 2.0 = one cycle (LOFI2 / WarpFold)."""
    return 2.0 * rate_hz(k) / FS


def onepole_coef(f: float) -> float:
    return 1.0 - math.exp(-2.0 * math.pi * f / FS)


def hpf_coef(k: int) -> float:
    k = max(0, min(127, int(k)))
    if k == 0:
        return 0.0
    return onepole_coef(20.0 * (400.0) ** (k / 127.0))  # 20 Hz .. 8 kHz


def color_coef(k: int) -> float:
    k = max(0, min(127, int(k)))
    if k >= 127:
        return 1.0
    return onepole_coef(30.0 * (16000.0 / 30.0) ** (k / 127.0))  # 30 Hz .. 16 kHz


def _wrap_signed(p: float) -> float:
    """Keep phase in [-1, 1) — the a1 wrap of a Q23 phase word."""
    while p >= 1.0:
        p -= 2.0
    while p < -1.0:
        p += 2.0
    return p


def osc(shape: int, p: float) -> float:
    """Bipolar oscillator from signed phase in [-1, 1)."""
    x = _wrap_signed(p)
    shape = int(shape) % 3
    if shape == 0:  # SIN — WarpFold parabola 4 p (1-|p|)
        return 4.0 * x * (1.0 - abs(x))
    if shape == 1:  # SQR
        return 1.0 if x >= 0.0 else -1.0
    return x  # SAW


def soft_clip(x: float, drive: int) -> float:
    """Blend soft-clip: out = x + d·(soft−x). d=0 identity (no 0→1 click)."""
    d = max(0, min(127, int(drive))) / 128.0
    g = 1.0 + 3.0 * d
    u = x * g
    if u > 1.0:
        u = 1.0
    elif u < -1.0:
        u = -1.0
    soft = u - (u * u * u) / 3.0
    return x + d * (soft - x)


def _white_step(state: int) -> tuple[int, float]:
    state = (A_NOISE * (state & 0xFFFFFF) + C_NOISE) & 0xFFFFFF
    s = state if state < 0x800000 else state - 0x1000000
    return state, 0.5 * s / float(1 << 23)


def _kn_q23(k: int) -> float:
    """Panel 0..127 → Q23 gain; 127 is exact 1.0 (matches asm teq)."""
    k = max(0, min(127, int(k)))
    return 1.0 if k >= 127 else k / 128.0


class VoidState:
    def __init__(self):
        self.phase = 0.0
        self.noise = 0x2A5F31
        self.noise2 = 0x5F1A2B
        self.lp_l = 0.0
        self.lp_r = 0.0
        self.hp_l = 0.0
        self.hp_r = 0.0
        self.fb = 0.0
        self.dc = 0.0
        self.env = 0.0


def process_block(
    left: list[float],
    right: list[float],
    *,
    bal: int = 0,
    rate: int = 80,
    shape: int = 0,
    depth: int = 127,
    drive: int = 0,
    fdbk: int = 0,
    color: int = 64,
    hpf: int = 0,
    wid: int = 0,
    src: int = 0,
    nbr_l: list[float] | None = None,
    nbr_r: list[float] | None = None,
    state: VoidState | None = None,
) -> tuple[list[float], list[float]]:
    st = state or VoidState()
    inc = rate_inc(rate)
    d = _kn_q23(depth)
    fb = max(0, min(127, int(fdbk))) / 128.0
    t = _kn_q23(bal)
    w_wid = _kn_q23(wid)
    hc = hpf_coef(hpf)
    cc = color_coef(color)
    use_nbr = int(src) != 0 and nbr_l is not None
    out_l, out_r = [], []
    for i, (x_l, x_r) in enumerate(zip(left, right)):
        st.noise, n = _white_step(st.noise)
        in_l, in_r = x_l, x_r

        if hc > 0.0:
            st.hp_l += hc * (n - st.hp_l)
            n = n - st.hp_l
        if cc < 1.0:
            st.lp_l += cc * (n - st.lp_l)
            n = st.lp_l
        else:
            st.lp_l = n

        n = soft_clip(n + fb * (st.fb - st.dc), drive)
        st.dc += _DC_K * (n - st.dc)
        st.fb = n

        if use_nbr:
            if i >= len(nbr_l):
                mono = 0.0
            else:
                n_l = nbr_l[i]
                n_r = nbr_r[i] if nbr_r is not None else n_l
                mono = 0.5 * (n_l + n_r)
            st.env += _ENV_K * (abs(mono) - st.env)
            uni = min(1.0, st.env * 4.0)
        else:
            st.phase = _wrap_signed(st.phase + inc)
            o = osc(shape, st.phase)
            uni = 0.5 * (o + 1.0)

        gain = (1.0 - d) + d * uni
        n_l = n * gain
        if w_wid <= 0.0:
            n_r = n_l
        else:
            st.noise2, s = _white_step(st.noise2)
            if hc > 0.0:
                st.hp_r += hc * (s - st.hp_r)
                s = s - st.hp_r
            if cc < 1.0:
                st.lp_r += cc * (s - st.lp_r)
                s = st.lp_r
            else:
                st.lp_r = s
            s = soft_clip(s, drive)  # same DRV, no FDBK
            side = s * gain
            mid = n_l
            g = 0.5 * w_wid
            n_l = mid + g * side
            n_r = mid - g * side

        out_l.append(in_l + t * (n_l - in_l))
        out_r.append(in_r + t * (n_r - in_r))
    return out_l, out_r
