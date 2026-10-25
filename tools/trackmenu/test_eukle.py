#!/usr/bin/env python3
"""test_eukle: modules/trackmenu/eukle.s (EuKle, the track menu's Euclidean printer) under cfsim against its
reference model tools/trackmenu/eukle_ref.py, byte for byte.

A synthetic bank (the record / Part / mirror layout eukle.s documents) with random trigs, trigless trigs,
slides and locks, OCTA-303 tracks (FLEX signed 'T' 'B' 1) and others. What it proves: every generator
(EUCL every k <= n <= 64 at four rotations, GOLD, DENS) equals the model; prints over random settings
(out-of-range bytes too) write the same bytes in the record and in the mirror, never remove a user's trig,
trigless trig or slide, and push one undo level; undo restores the bytes exactly, refuses another pattern's
level and an empty stack; eight levels and the ninth dropping the oldest; LIVE (ROT DENS MUTA OPER in all
four modes) over thousands of UI ticks with the transport running, stopping, restarting, the user editing
trigs, pattern changes, a held trig, a busy engine, a bank change; the store tail after a print or an undo
(the track passed to 0x4009da20), none after a LIVE regeneration; the two busy flags; every register kept by
the entries; cfsim's ColdFire lint. What it cannot: the firmware's own reading of these bytes (the port and
the unit decide that)."""
import os, random, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'octa303', 'sim')); sys.path.insert(0, HERE)
from cfsim import CPU, Mem
import eukle_ref as R

SRC = open(os.path.join(ROOT, 'modules', 'trackmenu', 'eukle.s')).read() + """
        .balign 4
tm_set: .space 256
"""
ED = dict(TIDY=0x40027e00, END=0x40027de4, SENT=0x4009da20, CALL=0x400418e0, REDRAW=0x4004d948)
RESUME = 0x40055962
fails = 0


def check(name, ok, info=''):
    global fails
    print(('PASS  ' if ok else 'FAIL  ') + name + (('   [' + str(info)[:300] + ']') if info else ''))
    if not ok: fails += 1


mem = Mem()
calls = []
def arg(cpu, i): return cpu.mem.r(cpu.a[7] + 4 * i, 'l')
def mk(name):
    def h(cpu):
        calls.append((name, arg(cpu, 0) if name in ('SENT', 'REDRAW') else None))
        for r in (0, 1): cpu.d[r] = 0x5a5a5a5a          # the firmware may clobber d0/d1/a0/a1
        for r in (0, 1): cpu.a[r] = 0x5a5a5a5a
    return h
resumed = []
def h_resume(cpu):                                      # the hook's jmp: the displaced pea is on the stack
    resumed.append(cpu.mem.r(cpu.a[7], 'l')); cpu.a[7] += 4
hooks = {v: mk(k) for k, v in ED.items()}
hooks[RESUME] = h_resume
cpu = CPU(SRC, mem, hooks=hooks)
check('cfsim_lint_and_load', True, '%d instructions' % len(cpu.prog))
C = cpu.consts
SP = 0x47000000
SENT = [0x11110000 + i for i in range(8)]
BANK = 0x40200000
TMSET = C['tm_set']


def call(label, *args, regs=None):
    """args above the return address; returns d0. Checks d1-d7/a0-a6 kept when regs == 'all-but-d0'."""
    for i, v in enumerate(args): mem.w(SP - 4 * len(args) + 4 * i, 'l', v & 0xffffffff)
    for i in range(8): cpu.d[i] = SENT[i]
    for i in range(7): cpu.a[i] = SENT[i] ^ 0xff
    cpu.a[7] = SP - 4 * len(args); cpu.call(label)
    if regs:
        lo = 0 if regs == 'all' else 1
        kept = all(cpu.d[i] == SENT[i] for i in range(lo, 8)) and all(cpu.a[i] == SENT[i] ^ 0xff for i in range(7))
        if not kept: check('registers_kept_by_' + label, False, [hex(x) for x in cpu.d + cpu.a])
    return cpu.d[0]


def reg_call(label, d=(), a=()):
    for i, v in enumerate(d): cpu.d[i] = v & 0xffffffff
    for i, v in enumerate(a): cpu.a[i] = v & 0xffffffff
    cpu.a[7] = SP; cpu.call(label)


BUF = 0x47200000
def rd_mask(a): return (mem.r(a, 'l') << 32) | mem.r(a + 4, 'l')


# ---------------------------------------------------------------- the generators
cpu.a[5] = 0x47300000                                   # a work area for ek_dens's M_TMP
bad = []
for n in range(1, 65):
    for k in range(0, n + 3):
        for r in (0, 1, n - 1, 63):
            reg_call('ek_euclid', d=(k, n, r), a=(BUF,))
            if rd_mask(BUF) != R.euclid(k, n, r): bad.append(('E', k, n, r))
check('euclid_every_k_n_four_rotations', not bad, bad[:5])
bad = []
rnd = random.Random(7)
for _ in range(3000):
    n = rnd.randint(1, 64); k = rnd.randint(0, 70); j0 = rnd.choice([0, rnd.randint(0, 200), rnd.randint(0, 1 << 31)])
    reg_call('ek_golden', d=(k, n, j0), a=(BUF,), )
    if rd_mask(BUF) != R.golden(k, n, j0): bad.append(('G', k, n, j0))
    r = rnd.randint(0, 70)
    cpu.a[5] = 0x47300000
    reg_call('ek_dens', d=(k, n, r), a=(BUF,))
    if rd_mask(BUF) != R.dens(k, n, r): bad.append(('D', k, n, r))
check('golden_and_dens_equal_the_model', not bad, bad[:5])
check('golden_hits_the_downbeat_and_keeps_its_density',
      all(R.golden(k, 16, 0) & 1 and abs(bin(R.golden(k, 16, 0)).count('1') - k * 16 / (16 + 0.618)) <= 1
          for k in range(1, 16)))
check('dens_keeps_the_old_hits_as_it_fills',
      all(R.dens(k, 16, 0) & R.dens(k + 1, 16, 0) == R.dens(k, 16, 0) for k in range(0, 16)))


# ---------------------------------------------------------------- the synthetic bank
def rec_addr(p, t): return BANK + p * R.PAT_STRIDE + t * R.TRK_STRIDE
def mir_addr(p, t): return R.MIRROR + p * R.PAT_STRIDE + t * R.TRK_STRIDE
def part_addr(pi): return BANK + R.PART_OFF + pi * R.PART_SIZE
REGIONS = []
for p in range(3):
    for t in range(8):
        REGIONS.append((rec_addr(p, t), 0x860)); REGIONS.append((mir_addr(p, t), 0x860))


def w8(a, v): mem.w(a, 'b', v)


def setup(seed):
    """a fresh bank: patterns 0..2, part 0..1, random masks and locks; the mirror equal to the bank"""
    rr = random.Random(seed)
    for a, l in REGIONS:
        for i in range(l): mem.b.pop(a + i, None)
    mem.w(R.BANK_PTR, 'l', BANK); w8(R.PART_IDX, 0); w8(R.PAT_IDX, 0)
    mem.w(R.ENGQ_WAIT, 'l', 0x46000000); mem.w(R.HELD_TRIGS, 'w', 0); mem.w(R.STEPW, 'w', 0)
    for p in range(3):
        ptrn = BANK + p * R.PAT_STRIDE
        w8(ptrn + R.SCALEMODE, rr.choice([0, 0, 1])); w8(ptrn + R.PLEN, rr.choice([16, 16, 32, 64, 12, 7]))
        for t in range(8):
            ra, ma = rec_addr(p, t), mir_addr(p, t)
            w8(ra + R.TLEN, rr.choice([16, 32, 64, 5, 13, 1, 0, 65]) if rr.random() < 0.9 else rr.choice([16, 24]))
            dens_ = rr.choice([0, 0.1, 0.3])
            for off in (0, 8, 0x48):
                m = sum(1 << s for s in range(64) if rr.random() < dens_)
                for i in range(8): w8(ra + off + i, m >> (56 - 8 * i))
            for s in range(64):
                for sl in range(32):
                    w8(ra + R.LOCKS + 32 * s + sl, 0xff if rr.random() < 0.9 else rr.randint(0, 127))
            for i in range(0x860):
                w8(ma + i, mem.r(ra + i, 'b'))
    for pi in range(2):
        pa = part_addr(pi)
        for t in range(8):
            is303 = rr.random() < 0.5
            w8(pa + 0x22 + t, 1 if is303 or rr.random() < 0.3 else rr.choice([0, 2, 3]))
            sig = (0x54, 0x42, 1) if is303 else rr.choice([(0, 0, 0), (0x54, 0x42, 0), (0x54, 0, 1)])
            for i, v in enumerate(sig): w8(pa + 30 * t + 0x3c + i, v)
            w8(pa + 30 * t + 0x35, rr.randint(0, 127))
    for i in range(256): w8(TMSET + i, 0)


def snapshot():
    return {a: mem.b.get(a, 0) for base, l in REGIONS for a in range(base, base + l)}


def settings(t): return [mem.r(TMSET + 32 * t + i, 'b') for i in range(32)]
def set_knobs(t, rr, wild=False):
    vals = dict(plsa=rr.randint(0, 64), rota=rr.randint(0, 63), plsb=rr.choice([0, 0, rr.randint(0, 64)]),
                rotb=rr.randint(0, 63), slde=rr.choice([0, rr.randint(0, 64)]), srot=rr.randint(0, 63),
                mode=rr.randint(0, 3), op=rr.randint(0, 3), only=rr.randint(0, 1), evry=rr.randint(0, 6))
    if wild:
        for k in vals:
            if rr.random() < 0.2: vals[k] = rr.randint(0, 255)
    for k, off in (('plsa', 5), ('rota', 6), ('plsb', 7), ('rotb', 8), ('slde', 9), ('srot', 10), ('mode', 11),
                   ('op', 12), ('only', 14), ('evry', 15)):
        w8(TMSET + 32 * t + off, vals[k])


class Twin:
    """the model over a copy of the cfsim memory (the same bytes before the first operation)"""
    def __init__(self):
        self.m = R.Mem(dict(mem.b))
        self.e = R.Eukle(self.m, settings)
    def sync_env(self):                                  # the environment bytes the test changes
        for a, n in ((R.BANK_PTR, 4), (R.PART_IDX, 1), (R.PAT_IDX, 1), (R.ENGQ_WAIT, 4), (R.HELD_TRIGS, 2),
                     (R.STEPW, 2)):
            for i in range(n): self.m.w8(a + i, mem.b.get(a + i, 0))
    def poke(self, a, v): self.m.w8(a, v); w8(a, v)


def diff(tw):
    out = []
    for base, l in REGIONS:
        for a in range(base, base + l):
            if mem.b.get(a, 0) != tw.m.d.get(a, 0): out.append(hex(a))
            if len(out) > 5: return out
    return out


def diff_live(tw, tracks):
    """the bytes LIVE writes: the masks (0..0x4f) and the TUNE / ACC locks, record and mirror"""
    out = []
    for p in range(3):
        for t in tracks:
            for base in (rec_addr(p, t), mir_addr(p, t)):
                addrs = list(range(base, base + 0x50)) + [base + R.LOCKS + 32 * s_ + sl for s_ in range(64) for sl in (0, 5)]
                for a in addrs:
                    if mem.b.get(a, 0) != tw.m.d.get(a, 0): out.append(hex(a))
                    if len(out) > 5: return out
    return out


def reset_engine():
    for name, size in (('ek_lv', 8 * 88), ('ek_undo_buf', 8 * 392)):
        for i in range(size): mem.b[C[name] + i] = 0
    for name in ('ek_bank', 'ek_clock_seen', 'ek_last_counter', 'ek_idle', 'ek_acc', 'ek_keybusy',
                 'ek_tickbusy', 'ek_prints', 'ek_undos', 'ek_regens', 'ek_starts'):
        mem.w(C[name], 'l', 0)
    mem.w(C['ek_part'], 'l', 0xff)


# ---------------------------------------------------------------- prints and undos
bad, removed, mirror_bad, statuses = [], [], [], {}
for case in range(250):
    setup(1000 + case); reset_engine(); tw = Twin()
    rr = random.Random(case)
    for op_i in range(8):
        t = rr.randint(0, 7)
        set_knobs(t, rr, wild=case % 5 == 0)
        if rr.random() < 0.15:
            w8(R.PAT_IDX, rr.randint(0, 2))
        if rr.random() < 0.05:
            w8(R.PART_IDX, rr.randint(0, 1))
        tw.sync_env()
        before = snapshot()
        if rr.random() < 0.65:
            calls.clear()
            got = call('ek_print', t, regs='all-but-d0'); want = tw.e.print_(t)
            ok_tail = (calls == [('TIDY', None), ('SENT', t), ('CALL', None), ('REDRAW', 0xffffffff), ('END', None)]) \
                if want == 0 else calls == []
            if not ok_tail: bad.append(('tail', case, op_i, calls))
            if want == 0:
                st, rec, mir, n = tw.e.resolve(t)
                for off in (0, 8, 0x48):
                    b0 = int.from_bytes(bytes(before[rec + off + i] for i in range(8)), 'big')
                    a0 = rd_mask(rec + off)
                    if b0 & ~a0: removed.append((case, op_i, off))
        else:
            calls.clear()
            got = call('ek_undo', t, regs='all-but-d0'); want = tw.e.undo_(t)
        statuses[want] = statuses.get(want, 0) + 1
        if got != want: bad.append(('status', case, op_i, got, want))
        d = diff(tw)
        if d: bad.append(('bytes', case, op_i, d)); break
        for p in range(3):
            for tt in range(8):
                ra, ma = rec_addr(p, tt), mir_addr(p, tt)
                if any(mem.b.get(ra + i, 0) != mem.b.get(ma + i, 0) for i in list(range(0x50)) + list(range(0x59, 0x859))):
                    mirror_bad.append((case, op_i, p, tt)); break
check('print_and_undo_equal_the_model_byte_for_byte', not bad, bad[:3])
check('statuses_seen', all(statuses.get(s, 0) for s in (R.OK, R.E_LEN, R.E_NOUNDO)), statuses)
check('a_print_never_removes_a_users_trig_trigless_or_slide', not removed, removed[:3])
check('the_mirror_follows_the_bank', not mirror_bad, mirror_bad[:3])

# undo depth: eight levels, the ninth drops the oldest; another pattern's level refused
setup(5); reset_engine(); tw = Twin(); rr = random.Random(5)
w8(BANK + R.PLEN, 16); w8(BANK + R.SCALEMODE, 0)
snaps = []
for i in range(9):
    snaps.append(snapshot()); set_knobs(2, rr); tw.sync_env(); call('ek_print', 2); tw.e.print_(2)
res = [call('ek_undo', 2) for _ in range(9)]
check('eight_undo_levels_the_ninth_refused', res == [0] * 8 + [R.E_NOUNDO] and snapshot() == snaps[1], res)
set_knobs(2, rr); call('ek_print', 2)
w8(R.PAT_IDX, 1)
check('undo_refuses_another_patterns_level', call('ek_undo', 2) == R.E_NOUNDO)
w8(R.PAT_IDX, 0)
check('back_on_its_pattern_the_level_is_reachable', call('ek_undo', 2) == 0)
mem.w(R.HELD_TRIGS, 'w', 4)
check('a_held_trig_refuses_the_print', call('ek_print', 2) == R.E_HELD)
mem.w(R.HELD_TRIGS, 'w', 0)
mem.w(R.ENGQ_WAIT, 'l', 0)
check('a_busy_engine_refuses_the_print', call('ek_print', 2) == R.E_BUSY)
mem.w(R.ENGQ_WAIT, 'l', 0x46000000)
mem.w(C['ek_tickbusy'], 'l', 1)
check('the_tick_busy_refuses_a_key', call('ek_print', 2) == R.E_BUSY and mem.r(C['ek_keybusy'], 'l') == 0)
mem.w(C['ek_tickbusy'], 'l', 0)

# a hand-made OCTA-303 case: slides become tied trigless steps with the note before's TUNE
setup(9); reset_engine()
pa = part_addr(0)
w8(pa + 0x22 + 4, 1); [w8(pa + 30 * 4 + 0x3c + i, v) for i, v in enumerate((0x54, 0x42, 1))]
w8(pa + 30 * 4 + 0x35, 99)
ptrn = BANK; w8(ptrn + R.SCALEMODE, 0); w8(ptrn + R.PLEN, 16)
ra = rec_addr(0, 4)
for off in (0, 8, 0x48):
    for i in range(8): w8(ra + off + i, 0)
for s in range(16):
    for sl in range(32): w8(ra + R.LOCKS + 32 * s + sl, 0xff)
w8(ra + R.LOCKS + 32 * 0, 40)                             # step 1's TUNE lock: 40
for k, v in (('plsa', 4), ('rota', 0), ('plsb', 2), ('rotb', 0), ('slde', 2), ('srot', 1), ('mode', 3),
             ('op', 0), ('only', 0)):
    w8(TMSET + 32 * 4 + {'plsa': 5, 'rota': 6, 'plsb': 7, 'rotb': 8, 'slde': 9, 'srot': 10, 'mode': 11, 'op': 12, 'only': 14}[k], v)
call('ek_print', 4)
trig, trigless = rd_mask(ra), rd_mask(ra + 8)
# NEST: hits E(4,16) = 0 4 8 12; accents E(2,4) on hits 0, 2 -> steps 0, 8; slides E(2,4) rot 1 -> hits 1, 3 -> 4, 12
check('octa303_nest_slides_are_tied_trigless_steps',
      trig == (1 << 0) | (1 << 8) and trigless == (1 << 4) | (1 << 12), (hex(trig), hex(trigless)))
check('octa303_tied_step_takes_the_tune_before',
      mem.r(ra + R.LOCKS + 32 * 4, 'b') == 40 and mem.r(ra + R.LOCKS + 32 * 12, 'b') == 0xff,
      (mem.r(ra + R.LOCKS + 32 * 4, 'b'), mem.r(ra + R.LOCKS + 32 * 12, 'b')))
check('octa303_accents_are_acc_locks_with_the_parts_acc',
      [mem.r(ra + R.LOCKS + 32 * s + 5, 'b') for s in (0, 4, 8, 12)] == [99, 0xff, 99, 0xff])
call('ek_undo', 4)
check('undo_takes_the_locks_back',
      rd_mask(ra) == 0 and rd_mask(ra + 8) == 0 and mem.r(ra + R.LOCKS + 32 * 4, 'b') == 0xff
      and mem.r(ra + R.LOCKS + 5, 'b') == 0xff and mem.r(ra + R.LOCKS, 'b') == 40)


# ---------------------------------------------------------------- LIVE
def tick(tw):
    tw.sync_env(); call('ek_tick'); tw.e.tick()


bad, regens, modes_seen = [], 0, set()
for case in range(40):
    setup(3000 + case); reset_engine(); rr = random.Random(case)
    t = rr.randint(0, 7); t2 = (t + 3) % 8
    set_knobs(t, rr); set_knobs(t2, rr)
    w8(TMSET + 32 * t + 15, rr.choice([0, 0, 1, 2])); w8(TMSET + 32 * t2 + 15, rr.choice([0, 1]))
    w8(BANK + R.SCALEMODE, 0); w8(BANK + R.PLEN, rr.choice([16, 32, 12]))
    tw = Twin()
    for _ in range(3): tick(tw)
    mode = rr.randint(1, 4); modes_seen.add((mode, settings(t)[11] & 3))
    tw.sync_env()
    got = call('ek_live_set', t, mode, regs='all-but-d0'); want = tw.e.live_set(t, mode)
    m2 = rr.randint(1, 4)
    got2 = call('ek_live_set', t2, m2); want2 = tw.e.live_set(t2, m2)
    if got2 != want2: bad.append(('start2', case, got2, want2)); continue
    if got != want: bad.append(('start', case, got, want)); continue
    stepw = 0
    for k in range(1000):
        ev = rr.random()
        if ev < 0.25:
            stepw = (stepw + 1) & 0xffff; mem.w(R.STEPW, 'w', stepw)
        elif ev < 0.252:
            for _ in range(70): tick(tw)                   # the transport stopped half a second
        elif ev < 0.255:                                   # the user toggles a trig
            st, rec, mir, n = tw.e.resolve(t)
            if st == 0:
                s = rr.randint(0, n - 1); a = rec + 7 - s // 8
                v = mem.r(a, 'b') ^ (1 << (s % 8)); tw.poke(a, v); tw.poke(mir + 7 - s // 8, v)
        elif ev < 0.256:
            w8(R.PAT_IDX, rr.randint(0, 2))
        elif ev < 0.257:
            mem.w(R.HELD_TRIGS, 'w', 1 if mem.r(R.HELD_TRIGS, 'w') == 0 else 0)
        elif ev < 0.2575:
            set_knobs(t, rr)
        elif ev < 0.258 and case % 3 == 0:
            mem.w(R.ENGQ_WAIT, 'l', 0); tick(tw); mem.w(R.ENGQ_WAIT, 'l', 0x46000000)
        calls.clear()
        tick(tw)
        if calls: bad.append(('tail_on_regen', case, k, calls)); break
        if mem.r(C['ek_acc'], 'l') != tw.e.acc: bad.append(('acc', case, k)); break
        d = diff_live(tw, (t, t2))
        if d: bad.append(('bytes', case, k, d)); break
        for tt in (t, t2):
            if mem.r(C['ek_lv'] + 88 * tt, 'l') != tw.e.lv[tt].active:
                bad.append(('active', case, k, tt)); break
    d = diff(tw)
    if d: bad.append(('bytes_at_the_end', case, d))
    regens += mem.r(C['ek_regens'], 'l')
check('live_equals_the_model_over_ticks', not bad, bad[:3])
check('live_regenerated', regens > 200, regens)
check('live_modes_tried', len({m for m, _ in modes_seen}) == 4 and len({g for _, g in modes_seen}) == 4,
      sorted(modes_seen))

# LIVE by hand: ROT on E(4,16) moves one step a generation, the period ends one step early
setup(77); reset_engine(); tw = Twin()
w8(BANK + R.SCALEMODE, 0); w8(BANK + R.PLEN, 16)
ra = rec_addr(0, 1)
for off in (0, 8, 0x48):
    for i in range(8): w8(ra + off + i, 0); w8(mir_addr(0, 1) + off + i, 0)
pa = part_addr(0); w8(pa + 0x22 + 1, 0)
for i, v in enumerate((5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)): w8(TMSET + 32 * 1 + 5 + i, v)
w8(TMSET + 32 * 1 + 5, 4)
tw = Twin()
tick(tw)
call('ek_live_set', 1, 1); tw.e.live_set(1, 1)
seen = [rd_mask(ra)]
for s in range(1, 48):
    mem.w(R.STEPW, 'w', s); tick(tw)
    seen.append(rd_mask(ra))
check('live_rot_moves_a_step_on_step_15_of_each_bar',
      seen[0] == 0x1111 and seen[14] == 0x1111 and seen[15] == 0x2222 and seen[31] == 0x4444, [hex(x) for x in seen[13:17]])
call('ek_live_set', 1, 0)
mem.w(R.STEPW, 'w', 48); tick(tw); m48 = rd_mask(ra)
for s in range(49, 70): mem.w(R.STEPW, 'w', s); tick(tw)
check('live_off_freezes_the_pattern', rd_mask(ra) == m48 == 0x8888, hex(m48))
check('live_mode_reports', call('ek_live_mode', 1) == 0)
call('ek_live_set', 1, 2)
check('live_mode_reports_a_running_mode', call('ek_live_mode', 1) == 2)
mem.w(C['ek_keybusy'], 'l', 1)
r0 = mem.r(C['ek_regens'], 'l')
for s in range(70, 140): mem.w(R.STEPW, 'w', s); call('ek_tick')
check('a_key_busy_tick_skips_its_regenerations', mem.r(C['ek_regens'], 'l') == r0 and mem.r(C['ek_tickbusy'], 'l') == 0)
mem.w(C['ek_keybusy'], 'l', 0)
mem.w(R.BANK_PTR, 'l', BANK + 0x9b340); call('ek_tick')
check('another_bank_freezes_live', call('ek_live_mode', 1) == 0)

# the hook: every register kept, the displaced pea replayed, then 0x40055962
resumed.clear()
call('ek_hook', regs='all')
check('hook_replays_the_pea_and_resumes', resumed == [0x46c7e0e2], resumed)

print('\n%s: %d failure(s)' % ('ALL PASS' if not fails else 'FAILED', fails))
sys.exit(1 if fails else 0)
