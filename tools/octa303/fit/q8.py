"""The TB-303's square shaper (Roland service notes = x0xb0x netlist), the steady-state cycle at a pitch:
  saw (Q28's source, swinging vlo..vhi) -> R35 100k -> base of Q8 2SA733P (PNP)
                                       -> C10 0.01 uF + R34 10k -> base   (the speed-up path)
  emitter: R45 22k to +12 V, C11 1 uF to ground;  collector: R36 10k to +5.333 V = the square
The BE junction exponential (Is, VT), hFE beta, a Vce(sat) floor.  Unknown (to fit): vlo, vhi, beta."""
import numpy as np, math
VT = 0.02585; IS = 1e-14
def cycle(f0, vlo, vhi, beta, os=32, fs=44100, settle=0.25, vcesat=0.1):
    dt = 1.0 / (fs * os); n_set = int(settle * fs * os); per = fs * os / f0
    ve, q10, vb = 9.0, 0.0, 8.4; ph = 0.0; out = []; total = n_set + int(math.ceil(per)) + 2
    for i in range(total):
        ph += f0 * dt
        if ph >= 1.0: ph -= 1.0
        vs = vlo + (vhi - vlo) * ph
        # base node: (vb - vs)/R35 + (vb - (vs + q10))/R34 = ib(veb) = IS*exp((ve-vb)/VT)/(beta+1)  (Newton on vb)
        for _ in range(8):
            e = math.exp(min((ve - vb) / VT, 80.0)) * IS
            ib = e / (beta + 1.0)
            fval = (vb - vs) / 100e3 + (vb - vs - q10) / 10e3 - ib
            dfd = 1 / 100e3 + 1 / 10e3 + ib / VT
            st = fval / dfd; vb -= max(-0.05, min(0.05, st))
        e = math.exp(min((ve - vb) / VT, 80.0)) * IS; ib = e / (beta + 1.0); ic = beta * ib
        icmax = max(0.0, (ve - vcesat - 5.333) / 10e3)
        if ic > icmax: ic = icmax                          # saturated: the collector sits at ve - vcesat
        i34 = (vb - vs - q10) / 10e3                        # from the base through R34 into C10
        q10 += dt * i34 / 0.01e-6
        ve += dt * ((12.0 - ve) / 22e3 - ic - ib) / 1e-6
        if i >= n_set: out.append(5.333 + ic * 10e3)
    y = np.array(out[:int(per)])
    return y
def table(f0, vlo, vhi, beta, N=1024, fs=44100, **kw):
    """one cycle resampled to N points and band-limited to fs/2 at f0 (harmonics above Nyquist dropped)"""
    y = cycle(f0, vlo, vhi, beta, fs=fs, **kw); x = np.interp(np.linspace(0, len(y), N, endpoint=False), np.arange(len(y)), y)
    X = np.fft.rfft(x); kmax = int((fs / 2) / f0); X[kmax + 1:] = 0; X[0] = 0
    return np.fft.irfft(X, N), x
if __name__ == '__main__':
    import sys
    for vlo, vhi in ((5.0, 10.0), (4.5, 9.5), (5.5, 10.5)):
        for beta in (200, 400):
            t, x = table(65.6, vlo, vhi, beta)
            hi, lo = x.max(), x.min(); duty_low = np.mean(x < (hi + lo) / 2)
            H = np.abs(np.fft.rfft(x - x.mean()))[1:12]; H = 20 * np.log10(H / H[0])
            print('saw %.1f-%.1f hFE %d: swing %.2f-%.2f V, low part %.0f%%, harmonics 2..8 dB: %s' % (vlo, vhi, beta, lo, hi, 100 * duty_low, ' '.join('%.0f' % h for h in H[1:8])))

def table_fast(f0, vlo, vhi, beta, fs=44100):
    """q8tab (C): the cycle on the saw's phase grid (0 = the reset), band-limited at f0, zero mean"""
    import subprocess
    x = np.frombuffer(subprocess.run(['/root/q8/q8tab', '%.6f' % f0, '%.6f' % vlo, '%.6f' % vhi, '%.3f' % beta], capture_output=True, check=True).stdout, np.float64).copy()
    X = np.fft.rfft(x); kmax = int((fs / 2) / f0); X[kmax + 1:] = 0; X[0] = 0
    return np.fft.irfft(X, 1024), x
