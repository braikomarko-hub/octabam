#!/usr/bin/env python3
"""eukle_ref: the reference model of EuKle (modules/trackmenu/eukle.s), the Euclidean note / slide /
accent printer of the track menu (EUCLACID's engine, renamed EuKle by the owner on 25 Oct 2026).

Integer arithmetic only, written to be followed instruction by instruction by the assembly:
tools/trackmenu/test_eukle.py runs both over the same synthetic bank and compares every byte.

What a print does on track t (the menu's track; the print lands on that track):
  plan     -> notes N, slides S, accents A over the track's length n (bit s = step s, 0-based)
    MODE EUCL  A gen = E(PLSA, n) rotated ROTA                        (Bresenham: hit when j*k mod n < k)
    MODE GOLD  A gen = a Sturmian line of slope PLSA / (n + 1/phi), entered at ROTA (+ n per LIVE ROT
               generation): Euclid's density with a golden drift, never periodic
    MODE DENS  A gen = the PLSA heaviest steps of a fixed weight map (16 1 6 2 11 1 5 3 14 1 7 2 10 2 4 8),
               rotated ROTA: turning PLSA up adds hits and keeps the old ones (a drummer filling)
    MODE NEST  A gen = E(PLSA, n) rotated ROTA; then ACCENTS = E(PLSB, h) and SLIDES = E(SLDE, h) rotated
               ROTB / SROT, counted over the h hits, not over the steps
    B (EUCL / GOLD / DENS, PLSB > 0): E(PLSB, n) rotated ROTB, combined with A by OP: OR XOR AND A-B
    slides (not NEST): E(SLDE, n) rotated SROT; ONLY = ON: only on note steps
  apply    -> ORed into the track: a user's trig is never removed. Pushes one UNDO level (8 a track).
    an OCTA-303 track (FLEX signed 'T' 'B' 1, as octa303.s o3_sig): a slide step is a TIED step, the 303
      slide of OCTA303 v7.1: a trigless trig (mask 1) instead of a note trig, unless the user has a trig
      there; a new trigless step without a TUNE lock gets the TUNE lock of the sounding step before it
      (trig or trigless, cyclic), as OCTA303 does when a trigless is placed by hand; NEST's accents are
      ACC locks (PLAYBACK slot 5) with the Part's ACC, on the planned note steps that trig, where no
      ACC lock is.
    any other track: slides go to the stock slide mask (+0x48), accents are not printed.
  undo     -> the masks as they were and the locks it wrote back to 0xff; only on the same pattern
LIVE (started with the track key that closes the menu): the pattern of its period is regenerated one step
before every EVRY-bar period ends (16 steps a bar from the transport start): ROT (rotates; in GOLD the
line goes on), DENS (PLSA walks +-1 in 1..n-1), MUTA (PLSA +-2, ROTA + 0..3), OPER (OP cycles; without
B, or in NEST, it rotates). A trig added by hand joins the base; a base trig removed stays removed.
"""

W_DENS = (16, 1, 6, 2, 11, 1, 5, 3, 14, 1, 7, 2, 10, 2, 4, 8)
PHI16 = 106039                       # phi * 65536 (106039.56, floored)
M32 = 0xffffffff
EUCL, GOLD, DENS, NEST = 0, 1, 2, 3
L_OFF, L_ROT, L_DENS, L_MUTA, L_OPER = 0, 1, 2, 3, 4
OK, E_BANK, E_LEN, E_HELD, E_NOUNDO, E_BUSY = 0, 1, 2, 3, 4, 5

# firmware (1.40C, base 0x40000400): see eukle.s for each address's source
BANK_PTR, PART_IDX, PAT_IDX = 0x46c82456, 0x100b14cf, 0x100b14d0
HELD_TRIGS, STEPW, ENGQ_WAIT = 0x460d174a, 0x800065b2, 0x460d17da
MIRROR = 0x1001614e
PAT_STRIDE, TRK_STRIDE = 0x8ed8, 0x91a
PART_OFF, PART_SIZE = 0x8ed80, 0x18b2
SCALEMODE, PLEN, TLEN = 0x8e55, 0x8e53, 0x50
M_TRIG, M_TRIGLESS, M_SLIDE = 0x00, 0x08, 0x48
LOCKS = 0x59                          # + 32 * step + slot
SL_TUNE, SL_ACC = 0, 5
UNDO_LEVELS = 8
IDLE_RESTART = 60                     # UI ticks (120 Hz) without a step = the transport was stopped

# the track's settings (tm_set, 32 bytes a track), EuKle's bytes
S_PLSA, S_ROTA, S_PLSB, S_ROTB, S_SLDE, S_SROT, S_MODE, S_OP, S_LIVE, S_ONLY, S_EVRY = range(5, 16)


def bit(m, s): return (m >> s) & 1


def euclid(k, n, r):
    if n < 1 or n > 64: return 0
    if k > n: k = n
    r %= n
    m = 0
    for i in range(n):
        j = (i + n - r) % n
        if (j * k) % n < k: m |= 1 << i
    return m


def rotate(m, n, r):
    if n < 1 or n > 64: return 0
    r %= n
    o = 0
    for i in range(n):
        if bit(m, i): o |= 1 << ((i + r) % n)
    return o


def combine(a, b, op):
    if op == 1: return a ^ b
    if op == 2: return a & b
    if op == 3: return a & ~b & ((1 << 64) - 1)
    return a | b


def golden(k, n, j0):
    if k == 0: return 0
    if k >= n: return (1 << n) - 1
    s = ((k * PHI16 * 256) & M32) // (((n * PHI16) + 65536) >> 8)
    acc = (j0 * s) & 0xffff               # frac(j * slope), j = j0 + i: a hit when it is below the slope
    m = 0                                 # (Euclid's rule, so j = 0 is a hit: the downbeat)
    for i in range(n):
        if acc < s: m |= 1 << i
        acc = (acc + s) & 0xffff
    return m


def dens(k, n, r):
    if k >= n: return (1 << n) - 1
    m, c = 0, 0
    for w in range(16, 0, -1):
        for i in range(n):
            if c < k and W_DENS[i & 15] == w:
                m |= 1 << i; c += 1
    return rotate(m, n, r)


def spread(e, hits):
    """e over the hit list: bit idx of e -> the hit's step."""
    m = 0
    for idx, s in enumerate(hits):
        if bit(e, idx): m |= 1 << s
    return m


def plan(p, n):
    """p: plsa rota plsb rotb slde srot mode op only out_rot jx -> (notes, slides, accents)."""
    mode = p['mode'] if p['mode'] <= 3 else EUCL
    op = p['op'] if p['op'] <= 3 else 0
    if mode == GOLD:
        a = golden(p['plsa'], n, (p['rota'] + p['jx']) & M32)
    elif mode == DENS:
        a = dens(p['plsa'], n, p['rota'])
    else:
        a = euclid(p['plsa'], n, p['rota'])
    if mode != NEST and p['plsb']:
        a = combine(a, euclid(p['plsb'], n, p['rotb']), op)
    notes = rotate(a, n, p['out_rot'])
    if mode == NEST:
        hits = [s for s in range(n) if bit(notes, s)]
        h = len(hits)
        acc = spread(euclid(p['plsb'], h, p['rotb']), hits)
        sl = spread(euclid(p['slde'], h, p['srot']), hits)
    else:
        acc = 0
        sl = euclid(p['slde'], n, p['srot'])
        if p['only']: sl &= notes
    return notes, sl, acc


def clamp_pulses(k, n):
    hi = n - 1 if n >= 2 else n
    return max(1, min(hi, k))


class Live:
    def __init__(self): self.clear()

    def clear(self):
        self.active = 0; self.mode = 0; self.rec = 0; self.gen = 0; self.dens = 0; self.rng = 0
        self.base = [0, 0, 0]; self.last = [0, 0, 0]; self.lastw = [0, 0]


class Mem:
    """byte memory: a dict, reads of unwritten bytes give 0"""
    def __init__(self, d=None): self.d = dict(d or {})
    def r8(self, a): return self.d.get(a & M32, 0)
    def w8(self, a, v): self.d[a & M32] = v & 0xff
    def r16(self, a): return (self.r8(a) << 8) | self.r8(a + 1)
    def r32(self, a): return (self.r16(a) << 16) | self.r16(a + 2)
    def r64(self, a): return (self.r32(a) << 32) | self.r32(a + 4)
    def w64(self, a, v):
        for i in range(8): self.w8(a + i, v >> (56 - 8 * i))


class Eukle:
    def __init__(self, mem, settings):
        """settings(t) -> the 32 bytes of the track's tm_set (a list); mem: Mem"""
        self.m, self.settings = mem, settings
        self.lv = [Live() for _ in range(8)]
        self.undo = [[] for _ in range(8)]
        self.bank = 0; self.part = 0xff
        self.clock_seen = 0; self.last_counter = 0; self.idle = 0; self.acc = 0
        self.commits = []

    # ---- the environment
    def env(self):
        m = self.m
        bank = m.r32(BANK_PTR)
        busy = m.r32(ENGQ_WAIT) == 0
        return bank, m.r8(PART_IDX), m.r8(PAT_IDX), busy

    def resolve(self, t):
        """(status, rec, mirror, n)"""
        bank, part, pat, busy = self.env()
        if busy: return E_BUSY, 0, 0, 0
        if bank == 0 or part > 3 or pat > 15 or t > 7: return E_BANK, 0, 0, 0
        ptrn = (bank + pat * PAT_STRIDE) & M32
        rec = (ptrn + t * TRK_STRIDE) & M32
        mir = MIRROR + pat * PAT_STRIDE + t * TRK_STRIDE
        n = self.m.r8(rec + TLEN) if self.m.r8(ptrn + SCALEMODE) else self.m.r8(ptrn + PLEN)
        if n < 1 or n > 64: return E_LEN, 0, 0, 0
        return OK, rec, mir, n

    def part_ptr(self):
        bank, part, _, _ = self.env()
        return (bank + PART_OFF + (part & 3) * PART_SIZE) & M32

    def is303(self, t):
        pp = self.part_ptr()
        m = self.m
        if m.r8(pp + 0x22 + t) != 1: return 0
        a = pp + 30 * t + 0x3c
        return int(m.r8(a) == 0x54 and m.r8(a + 1) == 0x42 and m.r8(a + 2) == 1)

    def knobs(self, t):
        s = self.settings(t)
        return dict(plsa=s[S_PLSA], rota=s[S_ROTA], plsb=s[S_PLSB], rotb=s[S_ROTB], slde=s[S_SLDE],
                    srot=s[S_SROT], mode=s[S_MODE], op=s[S_OP], only=1 if s[S_ONLY] else 0,
                    out_rot=0, jx=0)

    # ---- writes: the bank's RAM record and its battery-RAM mirror, byte by byte
    def wmask(self, rec, mir, off, v):
        self.m.w64(rec + off, v); self.m.w64(mir + off, v)

    def wlock(self, rec, mir, s, slot, v):
        self.m.w8(rec + LOCKS + 32 * s + slot, v); self.m.w8(mir + LOCKS + 32 * s + slot, v)

    def put(self, t, rec, mir, n, cur, notes, sl, acc):
        """The plan onto the masks cur = [trig, trigless, slide]; writes the masks and the locks.
        -> (last = the planned [notes, tied, slides], lastw = [tune written, acc written])"""
        c0, c1, cs = cur
        if self.is303(t):
            tied = sl & ~c0
            n2 = notes & ~tied
            new0 = c0 | n2
            tl = tied & ~c1
            new1 = c1 | tl
            news = cs
            last = [n2, tied, 0]
        else:
            tied = 0; tl = 0; n2 = notes
            new0 = c0 | notes; new1 = c1; news = cs | sl
            last = [notes, 0, sl]
        self.wmask(rec, mir, M_TRIG, new0)
        self.wmask(rec, mir, M_TRIGLESS, new1)
        self.wmask(rec, mir, M_SLIDE, news)
        tunew = accw = 0
        if tl:
            snd = new0 | new1
            for s in range(n):
                if not bit(tl, s): continue
                if self.m.r8(rec + LOCKS + 32 * s + SL_TUNE) != 0xff: continue
                v = 0xff
                for d in range(1, n):
                    p = (s + n - d) % n
                    if bit(snd, p):
                        v = self.m.r8(rec + LOCKS + 32 * p + SL_TUNE); break
                if v != 0xff:
                    self.wlock(rec, mir, s, SL_TUNE, v); tunew |= 1 << s
        a2 = acc & n2
        if a2 and self.is303(t):
            pp = self.part_ptr()
            av = self.m.r8(pp + 0x30 + 30 * t + 5)
            for s in range(n):
                if bit(a2, s) and self.m.r8(rec + LOCKS + 32 * s + SL_ACC) == 0xff:
                    self.wlock(rec, mir, s, SL_ACC, av); accw |= 1 << s
        return last, [tunew, accw]

    def read3(self, rec):
        return [self.m.r64(rec + M_TRIG), self.m.r64(rec + M_TRIGLESS), self.m.r64(rec + M_SLIDE)]

    def push_undo(self, t, rec, before, w):
        u = self.undo[t]
        if len(u) == UNDO_LEVELS: u.pop(0)
        u.append((rec, list(before), list(w)))

    # ---- the menu's keys (key-handler context)
    def print_(self, t, commit=True):
        st, rec, mir, n = self.resolve(t)
        if st: return st
        if self.m.r16(HELD_TRIGS): return E_HELD
        notes, sl, acc = plan(self.knobs(t), n)
        before = self.read3(rec)
        last, w = self.put(t, rec, mir, n, before, notes, sl, acc)
        self.push_undo(t, rec, before, w)
        if commit: self.commits.append(t)
        return OK

    def undo_(self, t, commit=True):
        st, rec, mir, n = self.resolve(t)
        if st: return st
        if self.m.r16(HELD_TRIGS): return E_HELD
        u = self.undo[t]
        if not u or u[-1][0] != rec: return E_NOUNDO
        self.lv[t].active = 0                      # freeze, then undo (EUCLACID's order)
        _, before, w = u.pop()
        self.wmask(rec, mir, M_TRIG, before[0]); self.wmask(rec, mir, M_TRIGLESS, before[1])
        self.wmask(rec, mir, M_SLIDE, before[2])
        for s in range(64):
            if bit(w[0], s): self.wlock(rec, mir, s, SL_TUNE, 0xff)
            if bit(w[1], s): self.wlock(rec, mir, s, SL_ACC, 0xff)
        if commit: self.commits.append(t)
        return OK

    # ---- LIVE
    def live_params(self, lv, k, n):
        p = dict(k)
        mode = lv.mode
        if mode == L_OPER and (k['plsb'] == 0 or k['mode'] == NEST): mode = L_ROT
        if mode == L_ROT:
            if k['mode'] == GOLD: p['jx'] = (lv.gen * n) & M32
            else: p['out_rot'] = lv.gen % n
        elif mode == L_DENS:
            p['plsa'] = clamp_pulses(k['plsa'] + lv.dens, n)
        elif mode == L_MUTA:
            p['plsa'] = clamp_pulses(k['plsa'] + lv.dens, n)
            p['rota'] = (k['rota'] + ((lv.rng >> 24) % 4 if lv.gen else 0)) % n
        elif mode == L_OPER:
            p['op'] = ((k['op'] if k['op'] <= 3 else 0) + lv.gen) % 4
        return p

    def rnd(self, lv):
        lv.rng = (lv.rng * 1103515245 + 12345) & M32
        return (lv.rng >> 16) & 0x7fff

    def advance(self, lv, k, n):
        lv.gen = (lv.gen + 1) & M32
        if lv.mode == L_DENS:
            kk = k['plsa'] + lv.dens + (1 if self.rnd(lv) & 1 else -1)
            lv.dens = clamp_pulses(kk, n) - k['plsa']
        elif lv.mode == L_MUTA:
            lv.dens = self.rnd(lv) % 5 - 2
            self.rnd(lv)

    def live_start(self, t, mode):
        lv = self.lv[t]
        lv.clear()
        st, rec, mir, n = self.resolve(t)
        if st: return st
        lv.mode = mode
        lv.rng = (0x9e3779b9 ^ (t * 977) ^ self.acc) & M32
        k = self.knobs(t)
        notes, sl, acc = plan(self.live_params(lv, k, n), n)
        before = self.read3(rec)
        last, w = self.put(t, rec, mir, n, before, notes, sl, acc)
        self.push_undo(t, rec, before, w)
        lv.base = before; lv.last = last; lv.lastw = w
        lv.active = 1; lv.rec = rec
        bank, part, _, _ = self.env()             # this context is the tick's from now on
        self.bank, self.part = bank, part
        return OK

    def live_set(self, t, mode):
        """the track key closing the menu: LIVE off = frozen where it is; on = started, or its mode."""
        lv = self.lv[t]
        if mode == L_OFF or mode > 4:
            lv.active = 0; return OK
        if lv.active:
            lv.mode = mode; return OK
        return self.live_start(t, mode)

    @staticmethod
    def keep(cur, base, last):
        return (cur & ~last) | (base & last & cur)

    def live_regen(self, t):
        lv = self.lv[t]
        st, rec, mir, n = self.resolve(t)
        if st: return st
        if rec != lv.rec:
            return self.live_start(t, lv.mode)
        k = self.knobs(t)
        for s in range(64):                        # our locks of the last generation go
            if bit(lv.lastw[0], s): self.wlock(rec, mir, s, SL_TUNE, 0xff)
            if bit(lv.lastw[1], s): self.wlock(rec, mir, s, SL_ACC, 0xff)
        cur = self.read3(rec)
        b = [self.keep(cur[i], lv.base[i], lv.last[i]) for i in range(3)]
        self.advance(lv, k, n)
        notes, sl, acc = plan(self.live_params(lv, k, n), n)
        last, w = self.put(t, rec, mir, n, b, notes, sl, acc)
        lv.base = b; lv.last = last; lv.lastw = w
        return OK

    def stop_all(self):
        for lv in self.lv: lv.active = 0

    def tick(self):
        """one UI tick (the keyrepeat task's loop, 120 Hz)"""
        bank, part, pat, busy = self.env()
        if bank == 0 or part > 3 or busy:
            self.bank = 0; self.stop_all(); return
        if bank != self.bank or part != self.part:
            self.stop_all(); self.bank = bank; self.part = part
        step = 0
        cnt = self.m.r16(STEPW)
        if not self.clock_seen:
            self.clock_seen = 1; self.last_counter = cnt; self.idle = 0
        elif cnt != self.last_counter:
            if self.idle > IDLE_RESTART: self.acc = 0
            else: self.acc = (self.acc + 1) & M32
            self.last_counter = cnt; self.idle = 0; step = 1
        elif self.idle < 0xffff:
            self.idle += 1
        if not step or self.m.r16(HELD_TRIGS): return
        for t in range(8):
            lv = self.lv[t]
            if not lv.active: continue
            ev = self.settings(t)[S_EVRY]
            if ev > 6: ev = 6
            period = 16 << ev
            if self.acc % period == period - 1:
                self.live_regen(t)
