"""The hybrid end to end under the port: the same project on two images -- aCiDtRacK (the voice on the ColdFire) and
aCiDhYb (the chain after u on the DSP, OCTA303 SEAM) -- and their main outs compared sample for sample.  The project:
play_gate.py's fixture (T5 and T6 OCTA-303 every step with CUT/RES/ENV/ACC 127, T1 on 1 5 9 13, 300 BPM).
usage (worktree root): port_ab.py IMAGE_CF IMAGE_HYB PROJECT [frames]
What it cannot see: the port runs a frame when its work is done (no cycle limit) and models one DSP core at a time;
equal audio here says the record, the seam and the chain are right, not that the chip has the cycles."""
import os, pathlib, subprocess, sys, wave
ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools/octa303/v82'))
import play_gate as PG
a, b, proj = sys.argv[1:4]; frames = sys.argv[4] if len(sys.argv) > 4 else '3000'
out = ROOT / 'out/octa303/port-ab'; out.mkdir(parents=True, exist_ok=True)
card = PG.fixture(proj, out)
res = {}
for tag, img in (('cf', a), ('hyb', b)):
    wav = out / ('%s.wav' % tag)
    cmd = [str(ROOT / 'out/emu/ot_emu'), '--image', img, '--card', str(card), '--set', 'OCTABAM', '--project', 'RIG',
           '--sequencer', '--internal-clock', '--frames', frames, '--load-ms', '90000', '--dsp', '--main-level', '64',
           '--audio-out', str(wav)]
    with (out / ('%s.log' % tag)).open('w') as log:
        r = subprocess.run(cmd, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=3600)
    lg = (out / ('%s.log' % tag)).read_text()
    print('%s: exit %d, ended %s, loaded %s, ILLEGAL %s' % (tag, r.returncode, 'run ended REACHED' in lg,
          'LOAD PROJECT handled' in lg, 'ILLEGAL' in lg))
    w = wave.open(str(wav) + '_core0.wav')     # the port writes core 0's main out (T5-T8 play there)
    res[tag] = (w.getnchannels(), w.getsampwidth(), w.readframes(w.getnframes())); w.close()
(ca, sa, da), (cb, sb, db) = res['cf'], res['hyb']
print('formats', (ca, sa), (cb, sb), 'bytes', len(da), len(db))
import numpy as np
def dec(d, ch, sw):
    b = np.frombuffer(d[:len(d) // (ch * sw) * ch * sw], dtype=np.uint8).reshape(-1, ch, sw).astype(np.int32)
    v = b[..., 0] | (b[..., 1] << 8) | (b[..., 2] << 16) if sw == 3 else b[..., 0] | (b[..., 1] << 8)
    top = 1 << (8 * sw - 1)
    return np.where(v & top, v - 2 * top, v)
A, B = dec(da, ca, sa), dec(db, cb, sb)
n = min(len(A), len(B)); A, B = A[:n], B[:n]
bad = not A.any()                      # silence on both would pass vacuously
for c in range(ca):
    a, b = A[:, c], B[:, c]
    if not a.any() and not b.any(): continue
    d = np.nonzero(a != b)[0]
    best = min(range(-48, 49), key=lambda L: int(np.abs(a[max(0, -L):n - max(0, L)] - b[max(0, L):n - max(0, -L)]).max()))
    e = np.abs(a[max(0, -best):n - max(0, best)] - b[max(0, best):n - max(0, -best)])
    print('channel %d: %d frames, non-zero %d / %d, differing %d (first at %s); best lag %+d samples: max |d| %d, differing %d'
          % (c, n, int((a != 0).sum()), int((b != 0).sum()), len(d), d[0] if len(d) else '-', best, int(e.max()), int((e != 0).sum())))
    bad |= bool(e.any()) or not a.any()
# PASS: every sounding channel equal word for word at one constant lag (19 Nov 2026: +5 samples; the stock source's
# interpolator ring delays the ColdFire's samples, the seam writes X:0 directly)
print('port_ab: ' + ('PASS' if not bad else 'FAIL'))
sys.exit(1 if bad else 0)
