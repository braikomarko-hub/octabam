#!/usr/bin/env python3
"""MU-SHRM's gate: modules/mushrm/mushrm.asm in dsp_host against its integer model, sample for sample.

Written by Claude (Anthropic), 26 Nov 2026.  The model (tools/mushrm/mushrm_ref.py) is the judge; the assembly
is written from it by tools/mushrm/gen_mushrm.py.  What this proves:

  generator   -> modules/mushrm/mushrm.asm is what gen_mushrm.py writes now (--check)
  bit-exact   -> on both payloads, FX1 and FX2 instances, every sample of every render (both sides) equals the model's:
                 the knobs' corners and 60 random knob sets on a 303 loop, noise, a sine sweep and silence,
                 with KEY OFF and KEY T1..T8 (KEYBUS's peak word seeded with -xword), blocks of 16 frames
  guard       -> dsp_host's -guard: no write outside the frame and the instance's state
  stability   -> RES1/RES2 127, DRIV/ASYM/DIRT 127, an impulse then silence: bounded, no runaway
  knobs       -> all knobs at 0, all at 127, junk in the knob words' low bits, KEY T1..T8 each reading its own
                 track's KEYBUS word; with --image, the same on a built image's dumps (the table in the curve bank)

Needs the scratch dump:  python3 tools/remix/audition.py mushrm out/dry/drums_110.wav  (built here when missing),
and a dsp_host with -xword (sambanks/main's; tools/harness/dsp_host/dsp_host.cpp in this tree has it).

    python3 tools/verify/verify_mushrm.py [--host PATH] [--quick]
"""
import argparse
import math
import pathlib
import random
import struct
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools")); import toolpath  # noqa: E402,F401
sys.path.insert(0, str(ROOT / "tools/mushrm"))
import send_probe  # noqa: E402
from remix import registry  # noqa: E402
import mushrm_ref as M  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("--host", default=str(ROOT / "vendor/dsp56300/build/source/dsp_host/dsp_host"))
ap.add_argument("--quick", action="store_true")
ap.add_argument("--image", help="run on a built image's dumps instead of the scratch ones (e.g. out/mainos_bus.bin "
                "of acidhyb: the table parked in the curve bank, the p:( reads as x:()")
ap.add_argument("--fxid", type=lambda v: int(v, 0), help="the id in that image (default: the manifest's)")
args = ap.parse_args()

MOD = registry.by_name("mushrm")
FXID = args.fxid if args.fxid is not None else MOD.menu.fx2_id
FRAMES = 16
TMP = ROOT / "out/_mushgate"
TMP.mkdir(parents=True, exist_ok=True)
fails = 0


def check(label, ok, detail=""):
    global fails
    print(f"  [{'PASS' if ok else 'FAIL'}] {label}{'  ' + detail if detail else ''}", flush=True)
    fails += 0 if ok else 1


r = subprocess.run([sys.executable, str(ROOT / "tools/mushrm/gen_mushrm.py"), "--check"], capture_output=True, text=True)
check("generator: mushrm.asm is what gen_mushrm.py writes", r.returncode == 0, (r.stdout + r.stderr).strip())

MEMS = {p: ROOT / f"out/dsp/_audition_{MOD.name}_{p}.mem" for p in "AB"}
ASM = ROOT / "modules/mushrm/mushrm.asm"
if args.image:
    import dsp_modmap
    img = pathlib.Path(args.image).read_bytes()
    for p in "AB":
        MEMS[p] = TMP / f"image_{p}.mem"
        dsp_modmap.dumpmem(img, [p, str(MEMS[p])])
    print(f"dumps from {args.image}")
elif not all(m.exists() and m.stat().st_mtime >= ASM.stat().st_mtime for m in MEMS.values()):
    for m in MEMS.values():
        m.unlink(missing_ok=True)                     # stale against the assembly: rebuild
    subprocess.run([sys.executable, str(ROOT / "tools/remix/audition.py"), MOD.name, str(ROOT / "out/dry/drums_110.wav")],
                   capture_output=True)
ENTRY = {}
for p, mem in MEMS.items():
    if not mem.exists():
        sys.exit(f"no {mem}: python3 tools/remix/audition.py mushrm out/dry/drums_110.wav")
    ENTRY[p] = send_probe.entry_points(str(mem), FXID)
    if ENTRY[p] == send_probe.entry_points(str(mem), registry.by_name("send").menu.fx2_id):
        sys.exit(f"id 0x{FXID:02x} resolves to SEND's entry points in {mem}: MU-SHRM is not in this dump")
    print(f"payload {p}: init P:0x{ENTRY[p][0]:04x} proc P:0x{ENTRY[p][1]:04x}")


def pwords(kn, slot):
    """the knob words with junk in the bits the DSP must ignore (an LFO's low bits): page 1 bits 0-15, page 2
    bits 0-7 (bits 8-15 carry the companion slot)"""
    k = "0" if slot == "fx1" else "0"
    ws = [f"{k}:{i:x}={((kn[i] & 0x7f) << 16) | 0x00a5c3:x}" for i in range(6)]
    for w in range(3):
        ws.append(f"{k}:{0xc + w:x}={((kn[6 + 2 * w] & 0x7f) << 16) | ((kn[7 + 2 * w] & 0x7f) << 8) | 0x5a:x}")
    return ",".join(ws)


def host(p, L, R, kn, key_word=None, slot="fx1", guard=False, dirty_bits=False):
    n = len(L) - len(L) % FRAMES
    inter = []
    for i in range(n):
        inter += [L[i], R[i]]
    src = TMP / "in.raw"; src.write_bytes(struct.pack(f"<{len(inter)}i", *inter))
    out = TMP / "out.raw"
    r7, alloc = ("1", "0") if slot == "fx1" else ("2", "1")
    init, proc = ENTRY[p]
    cmd = [args.host, "-mem", str(MEMS[p]), "-init", f"{init:x}", "-proc", f"{proc:x}", "-inst", "1", "-r7", r7,
           "-alloc", alloc, "-inmask", "1", "-stereo", "-frames", str(FRAMES), "-blocks", str(n // FRAMES),
           "-in", str(src), "-out", str(out), "-params", ",".join(str(v) for v in kn)]
    if key_word is not None:
        kws = key_word if isinstance(key_word, (list, tuple)) else [key_word] * 8
        cmd += ["-xword", ",".join(f"{0x37F60 + t:x}={kws[t] & 0xFFFFFF:x}" for t in range(8))]
    if dirty_bits:
        cmd += ["-pword", pwords(kn, slot)]
    if guard:
        cmd.append("-guard")
    if args.image:
        # an image with OCTA303 SEAM: dsp_host's search for the frame-context setup stops at the seam's hook;
        # its bounds as verify_dirty_state gives them
        cmd += ["-ctx", "372,39b,53e" if p == "A" else "17a,1a1,333"]
    rr = subprocess.run(cmd, capture_output=True, text=True)
    if rr.returncode != 0:
        return None, rr.stdout + rr.stderr
    d = out.read_bytes()
    w = struct.unpack(f"<{len(d) // 4}i", d)
    s24 = lambda v: ((v & 0xFFFFFF) ^ 0x800000) - 0x800000
    return ([s24(v) for v in w[0::2]][:n], [s24(v) for v in w[1::2]][:n]), rr.stdout + rr.stderr


def model(L, R, kn, key_word=None):
    n = len(L) - len(L) % FRAMES
    nb = n // FRAMES
    if isinstance(key_word, (list, tuple)):              # the track KEY names
        t = (kn[7] & 0x7f) - 1
        key_word = key_word[t] if 0 <= t < 8 else 0
    return M.render(L[:n], R[:n], kn, key=None if key_word is None else [key_word] * nb, block=FRAMES)


def compare(label, p, L, R, kn, key_word=None, slot="fx1", dirty_bits=False):
    got, log = host(p, L, R, kn, key_word, slot, dirty_bits=dirty_bits)
    if got is None:
        check(label, False, "dsp_host failed: " + log.strip()[-200:])
        return False
    exp = model(L, R, kn, key_word)
    n = len(L) - len(L) % FRAMES
    if len(got[0]) != n or len(got[1]) != n:
        check(label, False, f"dsp_host gave {len(got[0])}/{len(got[1])} frames, expected {n}")
        return False
    for ch in (0, 1):
        for i, (g, e) in enumerate(zip(got[ch], exp[ch])):
            if g != e:
                check(label, False, f"{'LR'[ch]} sample {i} (block {i // FRAMES}): dsp {g} model {e}; knobs {kn}"
                                    f"{'' if key_word is None else ' key %d' % key_word}")
                return False
    check(label, True, f"{len(got[0])} frames")
    return True


# ---- the signals ----------------------------------------------------------------------------------------
SR = 44100
rnd = random.Random(26112026)
N = 16 * (300 if args.quick else 900)
Q = M.Q
noise = [int(rnd.uniform(-0.5, 0.5) * Q) for _ in range(N)]
noiseR = [int(rnd.uniform(-0.5, 0.5) * Q) for _ in range(N)]
sweep = [int(0.45 * Q * math.sin(2 * math.pi * (40 * i / SR + 2000 * (i / SR) ** 2))) for i in range(N)]
# a 303-like loop: saw notes with a decaying level, so the photocell moves
acidL = []
for i in range(N):
    step, ph = divmod(i, 5000)
    f = 55 * 2 ** ([0, 12, 3, 7, 0, 10, 15, 5][step % 8] / 12)
    acidL.append(int(0.6 * Q * ((i * f / SR) % 1 - 0.5) * math.exp(-ph / 4000)))
acidR = [int(v * 0.8) for v in acidL]
silence = [0] * N
impulse = [Q - 1] + [0] * (N - 1)

knobs = M.knobs
print("---- bit-exact against the model ----")
cases = [
    ("defaults, 303", acidL, acidR, knobs(), None),
    ("all 0, noise", noise, noiseR, [0] * 12, None),
    ("all 127 (HARM 21, KEY 8), noise", noise, noiseR, [127] * 5 + [21, 127, 8, 127, 127, 127, 127], None),
    ("GATE, KEY T1, 303", acidL, acidR, knobs(SPD=127, KEY=1, BASE=60, DPTH=90), Q // 3),
    ("GATE, KEY T1, key silent", acidL, acidR, knobs(SPD=127, KEY=1), 0),
    ("series S-12, DIRT 40, sweep", sweep, sweep, knobs(HARM=13, DIRT=40, RES1=100, RES2=90, MORF=50), None),
    ("DIRT 110, ASYM 110, DRIV 90, 303", acidL, acidR, knobs(DIRT=110, ASYM=110, DRIV=90, RES1=100, HARM=8), None),
    ("KEY T5 (bus word 0.7), DPTH 8 closes", acidL, acidR, knobs(KEY=5, DPTH=8, BASE=90), int(0.7 * Q)),
    ("HARM byte 100 (above 21), KEY 9 (off)", noise, noiseR, knobs(HARM=100, KEY=9), int(0.5 * Q)),
    ("silence, DIRT 127", silence, silence, knobs(DIRT=127), None),
]
KEYS8 = [int(Q * (0.05 + 0.11 * t)) for t in range(8)]       # a different KEYBUS word on every track
for p in "AB":
    for label, L, R, kn, kw in cases:
        compare(f"{p} FX1 {label}", p, L, R, kn, kw)
    for label, L, R, kn, kw in cases[:6]:
        compare(f"{p} FX2 {label}", p, L, R, kn, kw, slot="fx2")
    for t in range(1, 9):
        compare(f"{p} FX1 KEY T{t}: track {t}'s own word", p, acidL[:16 * 200], acidR[:16 * 200],
                knobs(KEY=t, DPTH=110, SENS=90), KEYS8)
    compare(f"{p} FX1 knob words with junk low bits (an LFO's)", p, acidL, acidR,
            knobs(BASE=77, DPTH=20, HARM=14, MORF=90, KEY=3, SPD=40, DRIV=70, ASYM=99, DIRT=101), KEYS8,
            dirty_bits=True)
nrand = 12 if args.quick else 60
ok = 0
for j in range(nrand):
    kn = [rnd.choice([0, 1, 63, 64, 126, 127, rnd.randint(0, 127)]) for _ in range(12)]
    kn[5] = rnd.randint(0, 25); kn[7] = rnd.randint(0, 9)
    sig = rnd.choice([(acidL, acidR), (noise, noiseR), (sweep, sweep)])
    kw = rnd.choice([None, 0, rnd.randint(0, Q - 1)])
    ok += compare(f"{'AB'[j % 2]} FX1 random {j}", "AB"[j % 2], sig[0][:16 * 300], sig[1][:16 * 300], kn, kw)
print(f"random knob sets: {ok}/{nrand} equal")

print("---- guard: no write outside the frame and the state ----")
for p in "AB":
    got, log = host(p, acidL, acidR, knobs(DIRT=100, SPD=127, KEY=3), Q // 2, guard=True)
    bad = got is None or "guard clean" not in log or ", 0 stray write regions" not in log
    check(f"{p} -guard", not bad, "" if not bad else log.strip()[-200:])

print("---- stability ----")
for p in "AB":
    kn = [127, 127, 127, 127, 127, 21, 64, 0, 126, 127, 127, 127]
    got, _ = host(p, impulse, impulse, kn)
    tail = max(abs(v) for v in got[0][-16 * 100:]) / Q if got else 9
    check(f"{p} RES 127, everything at maximum, an impulse: the tail stays bounded", got is not None and tail < 0.5,
          f"tail peak {tail:.3f}")

print(f"verify_mushrm: {fails} failure(s)")
sys.exit(1 if fails else 0)
