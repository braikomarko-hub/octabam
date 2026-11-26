#!/usr/bin/env python3
"""Write modules/mushrm/mushrm.asm from the integer model's constants (tools/mushrm/mushrm_ref.py).

Written by Claude (Anthropic), 26 Nov 2026.  Every line here has its twin in mushrm_ref.MuShrM.block: the model
is the judge, verify_mushrm.py runs this code in dsp_host and wants every sample equal to the model's.
dsp_asm has no `equ` and no expressions: every constant is a literal, put in by this script.
`--check` exits non-zero when modules/mushrm/mushrm.asm is not what this script writes.

Rules kept (docs/contributing/TRAPS.md): mpy/mac only in stock's operand orders (x0,y1 / y1,x1 / x0,x0;
x1,y1 assembles as mpysu); a Tcc
reads the compare or arithmetic right above it with only moves between; a knob word is masked with
and #>$7f0000 and read from a1; no rep; init keeps r1; no label is a prefix of another; comments never spell
the build's markers.
"""
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
import mushrm_ref as M  # noqa: E402

C = M.C


def h(v):
    return f"${v & 0xFFFFFF:06x}"


# ---- r7 slots ----------------------------------------------------------------------------------------
S = dict(PHOTO=0x00, CLK=0x01, LFSR=0x02,
         CHB=0x03, CH=0x07,   # a channel's block (L at $03, R at $0a), 7 words: F1 ic1 ic2, F2 ic1 ic2, hold, dc x, dc y
         A1=0x11, A2=0x12, A3=0x13, K=0x14,   # F1's; F2's at +4
         WL=0x19, WB=0x1A, WH=0x1B, DM=0x1C, DCNT=0x1D, CM=0x1E, CCNT=0x1F, AIN=0x20, AOUT=0x21,
         NLEV=0x22, CINC=0x23, LEAK=0x24, SER=0x25, DIRT=0x26, GATE=0x27,
         T0=0x28, NZ=0x29, V=0x2A, V1=0x2B, V2=0x2C, Y1=0x2D, IN2=0x2E, T1=0x2F,
         P1=0x30, P2=0x31, G=0x32, KK=0x33, D4=0x34, ATT=0x35, REL=0x36, TGT=0x37, CNT=0x38, PK=0x39,
         KF=0x3A, KW=0x3B, F50=0x3C, ST=0x3D, RB=0x3E)
STATE_ZERO = [S['PHOTO'], S['CLK']] + list(range(0x03, 0x11))
assert max(S.values()) < 0x84, "the r7 block is $00..$83 (TRAPS: r7 scratch)"

# where each knob arrives (docs/firmware/PARAM_PAGES.md section 6): page 1 at r6+0..5, bits 16-23; page 2 two
# to a word: slot 6 $c bits 16-23, slot 7 $c bits 8-15, slot 8 $d hi, 9 $d lo, 10 $e hi, 11 $e lo
KNOB = dict(BASE=(0, 0), SENS=(1, 0), DPTH=(2, 0), RES1=(3, 0), RES2=(4, 0), HARM=(5, 0),
            MORF=(0xC, 0), KEY=(0xC, 1), SPD=(0xD, 0), DRIV=(0xD, 1), ASYM=(0xE, 0), DIRT=(0xE, 1))


class Asm:
    def __init__(self):
        self.lines = []

    def __call__(self, ins, cmt=""):
        self.lines.append(f"        {ins:<28}" + (f"; {cmt}" if cmt else "").rstrip())

    def label(self, name):
        self.lines.append(f"{name}:")

    def c(self, text):
        self.lines.append(f"; {text}")

    def r7(self, slot):
        return f"x:(r7+${slot:02x})"

    def r1(self, off):
        """a channel-block word through r1 = block - $100: the long-displacement form (loads into a, b, x0,
        x1 and the store from b are stock's; the short form through r1 is not)"""
        return f"x:(r1+${0x100 + off:04x})"

    def st1(self, reg, off):
        """store a register into the channel block: through b (stock's store form)"""
        if reg != "b":
            self(f"move {reg},b")
        self(f"move b,{self.r1(off)}")

    # -- the knob, stretched: ws = w + w/127 in x0 (and a) ---------------------------------------------
    def load_knob(self, name):
        """the knob's value 0..127 << 16 in a1 (a2 and a0 clean)"""
        off, lo = KNOB[name]
        self(f"move x:(r6+${off:x}),a", f"{name}{' (bits 8-15)' if lo else ''}")
        if lo:
            self("and #>$007f00,a")
            self("asl #$8,a,a")
        self("and #>$7f0000,a")

    def knob_ws(self, name):
        self.load_knob(name)
        self("bsr mzws", "x0 = ws")

    def knob_byte(self, name):
        """the raw value 0..127 << 16 in a1 (and x1)"""
        self.load_knob(name)
        self("move a1,x1")

    # -- steps: the integer part of ws x c x 128, into a1 ----------------------------------------------
    def steps(self, c):
        self(f"move #>{h(c)},y1")
        self("mpy x0,y1,a")
        self("asr #$10,a,a", "the integer steps")

    # -- 2^(s/16): EXP2[s & 15] into y1, the normf count -((s >> 4) + 1 - off) into the slot cnt ----------
    def exp2(self, cnt, off=0):
        """2^(s/16) for s in a1: y1 = EXP2[s & 15]; the normf count -((s >> 4) + 1) + off into the slot cnt"""
        self("bsr mzexp")
        if off:
            self(f"move {self.r7(S['CNT'])},a")
            self(f"add #${off:x},a")
            self(f"move a1,{self.r7(cnt)}")
        elif cnt != S['CNT']:
            self(f"move {self.r7(S['CNT'])},a")
            self(f"move a1,{self.r7(cnt)}")

    def clamp(self, reg, lo, hi):
        """a = clamp(a, lo, hi); lo/hi are words; leaves the result in a"""
        self(f"move #>{h(lo)},{reg}")
        self(f"cmp {reg},a")
        self(f"tlt {reg},a")
        self(f"move #>{h(hi)},{reg}")
        self(f"cmp {reg},a")
        self(f"tgt {reg},a")


def gen():
    a = Asm()
    L = a.lines
    L += [
        "; ---------------------------------------------------------------------------",
        "; MU-SHRM -- the Mu-Tron's photocell on two Sherman-style filters, with the dirt.",
        ";",
        "; GENERATED (do not edit) by tools/mushrm/gen_mushrm.py from tools/mushrm/mushrm_ref.py,",
        "; the integer model it must equal sample for sample (tools/verify/verify_mushrm.py).",
        "; Written by Claude (Anthropic) for MaMarko, 26 Nov 2026.",
        ";",
        "; Insert contract: frames in place at x:(r0) (L, R interleaved), n7 frames, knobs from r6",
        "; (page 1 at +0..5; page 2 two to a word at +12..14, bits 16-23 and 8-15), state in this",
        "; instance's r7 block (and r1 = a channel's block - $100 in the sample loop). In the shared",
        "; window it reads one word: KEYBUS's block peak of the track its KEY names.",
        "; ---------------------------------------------------------------------------",
        "",
        "init:",
    ]
    a("clr a")
    for s in STATE_ZERO:
        a(f"move a,{a.r7(s)}")
    a("move #>$5a5a5a,a", "the noise register: any word but zero")
    a(f"move a,{a.r7(S['LFSR'])}")
    a("rts")
    L.append("")
    L.append("proc:")
    a("move #>$ffffff,m5")
    a("move #>$fab1e0,r4", "the ptable: LOG, EXP2, G, HARM")
    a("move r0,r1")
    # ---- the peak of |L+R|/2 ----------------------------------------------------------------------------
    a.c("---- this block's peak of |L+R| (halved at the move) ----")
    a("clr b")
    a("move #$1,n0")
    a("do n7,>mzpeak")
    a("move x:(r1)+,a")
    a("move x:(r1)+,x0")
    a("add x0,a", "L + R")
    a("abs a")
    a("max a,b")
    a.label("mzpeak")
    a("nop")
    a("asr #$1,b,b", "|L+R|/2")
    a(f"move b,{a.r7(S['PK'])}", "limited")
    # ---- KEY: OFF, or T1..T8 -> KEYBUS's peak word (VCA160's form) ----------------------------------------
    a.c("---- KEY ----")
    a.load_knob("KEY")
    a("asr #$10,a,a", "KEY 0..127")
    a("move a1,x1")
    a("clr a")
    a("move x1,b")
    a("sub #$1,b", "t = KEY - 1")
    a("and #>$fffff8,b", "0 only for t = 0..7")
    a("move #>$7fffff,x0")
    a("teq x0,a", "KEY 1..8: on")
    a(f"move a,{a.r7(S['KF'])}")
    a("move x1,a")
    a("sub #$1,a")
    a("and #$7,a")
    a("move a1,x1")
    a("move x1,a")
    a(f"add #>{h(0x37F60)},a", "KEYBUS's peak word for track t")
    a("move a1,r1")
    a("nop")
    a("nop")
    a("move x:(r1),x0")
    a(f"move x0,{a.r7(S['KW'])}")
    a(f"move {a.r7(S['KF'])},b")
    a(f"move {a.r7(S['KW'])},x0")
    a("tst b")
    a(f"move {a.r7(S['PK'])},a")
    a("tne x0,a", "KEY on: the bus word")
    a("move a,x1", "the peak the photocell sees")
    a(f"move x1,{a.r7(S['PK'])}")
    # ---- SENS -> lvl ---------------------------------------------------------------------------------------
    a.c("---- the photocell: lvl = peak x 2^(SENS steps/16) / 8 ----")
    a.knob_ws("SENS")
    a.steps(C['S96'])
    a.exp2(S['CNT'], off=3)               # -(sh - 3): the /8
    a(f"move {a.r7(S['PK'])},x1")
    a("mpy y1,x1,a")
    a(f"move {a.r7(S['CNT'])},b")
    a("normf b1,a")
    a("move a,x0", "lvl, limited")
    a("move x0,a")
    a("move #>$000001,x0")
    a("cmp x0,a")
    a("tlt x0,a", "at least one LSB")
    # ---- log2(lvl)/32 (VCA160's lines) ------------------------------------------------------------------------
    a("clb a,b")
    a("normf b1,a", "the mantissa in [0.5, 1)")
    a(f"move b1,{a.r7(S['CNT'])}", "the exponent")
    a("move r4,r5")
    a("sub #>$400000,a")
    a("asl #$1,a,a", "u = 2 (m - 1/2)")
    a("move a1,x1")
    a("asr #$12,a,a", "idx")
    a("move a1,n5")
    a("move x1,a")
    a("and #>$3ffff,a")
    a("asl #$5,a,a", "frac")
    a("move (r5)+n5")
    a("move a,x0")
    a("move p:(r5)+,y0", "LOG[i]")
    a("move p:(r5),b", "LOG[i+1]")
    a("move y0,a")
    a("sub a,b")
    a("move b,y1")
    a("mpy x0,y1,a")
    a("add y0,a")
    a(f"move {a.r7(S['CNT'])},b")
    a("asl #$12,b,b", "e/32")
    a("add b,a", "log2(lvl)/32")
    # ---- the LED: (dB + 24)/18 ------------------------------------------------------------------------------
    a("move a,x0")
    a(f"move #>{h(C['LEDC'])},y1")
    a("mpy x0,y1,a")
    a("asl #$4,a,a")
    a(f"move #>{h(C['TWO3'])},x0")
    a("add x0,a")
    a("add x0,a", "+ 4/3")
    a("move #>$000000,x0")
    a("tmi x0,a")
    a("move a,x1", "tgt, 0 .. full scale")
    a(f"move x1,{a.r7(S['TGT'])}")
    # ---- SPD: the attack/release a block; 127 = GATE ----------------------------------------------------------
    a.c("---- SPD ----")
    a.knob_ws("SPD")
    a.steps(C['S64'])
    a.exp2(S['CNT'])
    a(f"move #>{h(C['ATT4'])},x0")
    a("mpy x0,y1,a")
    a(f"move {a.r7(S['CNT'])},b")
    a("normf b1,a")
    a(f"move a,{a.r7(S['ATT'])}")
    a(f"move #>{h(C['REL4'])},x0")
    a("mpy x0,y1,a")
    a("normf b1,a")
    a(f"move a,{a.r7(S['REL'])}")
    a.load_knob("SPD")
    a("move a1,x0")
    a("move x0,b")
    a("clr a")
    a("move #>$7f0000,x0")
    a("cmp x0,b")
    a("move #>$7fffff,x0")
    a("teq x0,a", "SPD 127: GATE")
    a(f"move a,{a.r7(S['GATE'])}")
    # the gate's target: tgt > 1/2 ? full : 0
    a("clr a")
    a(f"move {a.r7(S['TGT'])},b")
    a("move #>$400000,x0")
    a("cmp x0,b")
    a("move #>$7fffff,x1")
    a("tgt x1,a")
    a("move a,x0", "GATE's target")
    a(f"move {a.r7(S['GATE'])},b")
    a("tst b")
    a(f"move {a.r7(S['TGT'])},a")
    a("tne x0,a")
    a(f"move a,{a.r7(S['TGT'])}")
    a(f"move {a.r7(S['GATE'])},b")
    a("tst b")
    a(f"move {a.r7(S['ATT'])},a")
    a("move #>$7fffff,x0")
    a("tne x0,a")
    a(f"move a,{a.r7(S['ATT'])}")
    a(f"move {a.r7(S['GATE'])},b")
    a("tst b")
    a(f"move {a.r7(S['REL'])},a")
    a(f"move #>{h(C['GREL'])},x0")
    a("tne x0,a")
    a(f"move a,{a.r7(S['REL'])}")
    # ---- the photocell's one-pole ---------------------------------------------------------------------------
    a(f"move {a.r7(S['PHOTO'])},x0")
    a(f"move {a.r7(S['TGT'])},b")
    a(f"move {a.r7(S['REL'])},a")
    a("cmp x0,b", "tgt - photo")
    a(f"move {a.r7(S['ATT'])},x1")
    a("tgt x1,a", "rising: the attack")
    a("move a,y1", "the coefficient")
    a("sub x0,b")
    a("move b,x1", "tgt - photo")
    a("move x0,a")
    a("mac y1,x1,a")
    a(f"move a,{a.r7(S['PHOTO'])}")
    # ---- F1, F2 positions -----------------------------------------------------------------------------------
    a.c("---- F1 = BASE + DPTH x photocell; F2 = F1 + HARM ----")
    a.knob_ws("BASE")
    a(f"move #>{h(C['OCT16'])},y1")
    a("mpy x0,y1,a")
    a(f"move a,{a.r7(S['P1'])}")
    a.knob_ws("DPTH")
    a("move x0,a")
    a("sub #>$400000,a")
    a("move a,x0")
    a(f"move #>{h(C['DP'])},y1")
    a("mpy x0,y1,a")
    a("move a,x1", "dp")
    a(f"move {a.r7(S['PHOTO'])},y1")
    a(f"move {a.r7(S['P1'])},a")
    a("mac y1,x1,a")
    a.clamp("x0", 0, C['PMAX'])
    a(f"move a,{a.r7(S['P1'])}")
    a.load_knob("HARM")
    a("asr #$10,a,a", "HARM 0..127")
    a("move #>$000015,x0")
    a("cmp x0,a")
    a("tgt x0,a", "above 21: 21")
    a("move a1,x1", "hb")
    a("move x1,a")
    a("sub #>$00000b,a", "hb - 11")
    a("move x1,x0")
    a("tlt x0,a", "below 11: hb (parallel)")
    a("move a1,x0", "the step 0..10")
    a("move x1,a")
    a("sub x0,a")
    a(f"move a1,{a.r7(S['SER'])}", "hb - step: nonzero = series")
    a("move x0,a")
    a(f"add #>{h(M.AT_HARM)},a")
    a("move a1,n5")
    a("move r4,r5")
    a("nop")
    a("move (r5)+n5")
    a("move p:(r5),b")
    a("move b,y0", "HARM's octaves/16")
    a(f"move {a.r7(S['P1'])},a")
    a("add y0,a")
    a.clamp("x0", 0, C['PMAX'])
    a(f"move a,{a.r7(S['P2'])}")
    # ---- the coefficients of each filter --------------------------------------------------------------------
    for fi, (pslot, res) in enumerate(((S['P1'], "RES1"), (S['P2'], "RES2"))):
        o = 4 * fi
        a.c(f"---- F{fi + 1}: k from {res}, g from the table, a1 = 1/(1 + g(g + 2k)) ----")
        a.knob_ws(res)
        a(f"move {a.r7(pslot)},a")
        a("bsr mzcoef", "y1 = a1; g, k in their slots")
        a(f"move y1,{a.r7(S['A1'] + o)}", "a1")
        a(f"move {a.r7(S['KK'])},x1")
        a(f"move x1,{a.r7(S['K'] + o)}", "k")
        a(f"move {a.r7(S['G'])},x0")
        a("mpy x0,y1,a")
        a("move a,y1")
        a(f"move y1,{a.r7(S['A2'] + o)}", "a2 = g a1")
        a("mpy x0,y1,a")
        a(f"move a,{a.r7(S['A3'] + o)}", "a3 = g a2")
    # ---- MORF -----------------------------------------------------------------------------------------------
    a.c("---- MORF: d = 2 ws - 1; LP max(0,-d), BP 1 - |d|, HP max(0,d) ----")
    a.knob_ws("MORF")
    a("move x0,a")
    a("asl #$1,a,a")
    a("sub #>$7fffff,a")
    a("move a,x1", "d")
    a("move #>$000000,x0")
    a("move x1,a")
    a("cmp x0,a")
    a("tlt x0,a")
    a(f"move a,{a.r7(S['WH'])}")
    a("move x1,a")
    a("neg a")
    a("cmp x0,a")
    a("tlt x0,a")
    a(f"move a,{a.r7(S['WL'])}")
    a("move x1,a")
    a("abs a")
    a("move a,x0")
    a("move #>$7fffff,a")
    a("sub x0,a")
    a(f"move a,{a.r7(S['WB'])}")
    # ---- DRIV and the level back ----------------------------------------------------------------------------
    a.c("---- DRIV: 2^(s/16), s = 0..80; the level back 2^((80 - 2s/3)/16) / 32 ----")
    a.knob_ws("DRIV")
    a.steps(C['S80'])
    a(f"move a1,{a.r7(S['ST'])}")
    a.exp2(S['DCNT'])
    a(f"move y1,{a.r7(S['DM'])}")
    a(f"move {a.r7(S['ST'])},a")
    a("asl #$10,a,a")
    a("move a1,x0", "s << 16")
    a(f"move #>{h(C['THIRD2'])},y1")
    a("mpy x0,y1,a")
    a("asr #$10,a,a")
    a("move a1,x0", "2s/3")
    a("move #>$000050,a")
    a("sub x0,a", "80 - 2s/3")
    a.exp2(S['CCNT'], off=5)               # the /32
    a(f"move y1,{a.r7(S['CM'])}")
    # ---- ASYM ------------------------------------------------------------------------------------------------
    a.knob_ws("ASYM")
    a(f"move #>{h(C['AHALF'])},y1")
    a("mpy x0,y1,a")
    a(f"move a,{a.r7(S['AIN'])}")
    a(f"move {a.r7(S['AIN'])},a")
    a("asr #$1,a,a")
    a(f"move a,{a.r7(S['AOUT'])}")
    # ---- DIRT -------------------------------------------------------------------------------------------------
    a.c("---- DIRT: on/off, the clock's ratio, the noise's level, the leak, the clock's step ----")
    a.knob_byte("DIRT")
    a("clr a")
    a("move x1,b")
    a("tst b")
    a("move #>$7fffff,x0")
    a("tne x0,a")
    a(f"move a,{a.r7(S['DIRT'])}")
    a("move x1,a")
    a("and #>$400000,a")
    a(f"move a1,{a.r7(S['F50'])}", "64..127: the clock at 50:1")
    a.knob_ws("DIRT")
    a.steps(C['S80'])
    a("sub #>$0000a0,a", "- 160")
    a.exp2(S['CNT'])
    a("move y1,a")
    a(f"move {a.r7(S['CNT'])},b")
    a("normf b1,a", "the mantissa >> -(shift)")
    a("move a,x1")
    a(f"move {a.r7(S['DIRT'])},b")
    a("tst b")
    a("move x1,a")
    a("move #>$000000,x0")
    a("teq x0,a", "DIRT 0: no noise")
    a(f"move a,{a.r7(S['NLEV'])}")
    a.knob_ws("DIRT")
    a(f"move #>{h(C['LK1'])},y1")
    a("mpy x0,y1,a")
    a(f"add #>{h(C['LK0'])},a")
    a(f"move a,{a.r7(S['LEAK'])}")
    a(f"move {a.r7(S['P1'])},a")
    a("asr #$f,a,a", "F1 in 1/16 octaves")
    a.exp2(S['CNT'])
    a(f"move {a.r7(S['F50'])},b")
    a("tst b")
    a(f"move #>{h(C['CB100'])},a")
    a(f"move #>{h(C['CB50'])},x0")
    a("tne x0,a")
    a("move a,x0")
    a("mpy x0,y1,a")
    a(f"move {a.r7(S['CNT'])},b")
    a("normf b1,a")
    a(f"move a,{a.r7(S['CINC'])}", "the clock's step, limited")
    # ===================================================================================================
    a("move r7,a")
    a(f"sub #>{h(0x100 - S['CHB'])},a")
    a(f"move a1,{a.r7(S['RB'])}")
    a.c("==== the sample loop ====")
    a("do n7,>mzloop")
    # the clock
    a(f"move {a.r7(S['CLK'])},a")
    a(f"move {a.r7(S['CINC'])},y1")
    a("add y1,a", "phase + step")
    a("move a,x0", "(limited: used only below 1)")
    a(f"move {a.r7(S['CLK'])},a")
    a("sub #>$400000,a")
    a("sub #>$400000,a")
    a("add y1,a", "phase + step - 1")
    a("tlt x0,a", "no wrap: phase + step")
    a(f"move a,{a.r7(S['CLK'])}")
    # the noise: two Galois steps
    a(f"move {a.r7(S['LFSR'])},b")
    for _ in range(2):
        a("clr a")
        a(f"move #>{h(M.TAPS)},x0")
        a("tst b", "bit 23: the bit that goes out")
        a("tmi x0,a")
        a("asl b", "b1 << 1")
        a("move a1,x1")
        a("eor x1,b")
        a("move b1,x1")
        a("move x1,b", "clean")
    a(f"move b1,{a.r7(S['LFSR'])}")
    a(f"move b1,{a.r7(S['NZ'])}")
    a(f"move {a.r7(S['RB'])},r1", "the left channel's block - $100")
    a(f"move #${S['CH']:x},n1")
    a("do #$2,>mzchan")
    a.c("---- a channel: r1 points at its block ----")
    a("move x:(r0),x0")
    a(f"move {a.r7(S['DM'])},y1")
    a("mpy x0,y1,a")
    a(f"move {a.r7(S['DCNT'])},b")
    a("normf b1,a", "DRIV")
    a("move a,x0")
    _asym(a, S['AIN'])
    a(f"move {a.r7(S['NZ'])},x1")
    a(f"move {a.r7(S['NLEV'])},y1")
    a("move x0,a")
    a("mac y1,x1,a", "+ noise")
    a(f"move a,{a.r7(S['V'])}")
    _svf(a, S['V'], 0, 0)
    a(f"move a,{a.r7(S['Y1'])}", "F1's output")
    a(f"move {a.r7(S['SER'])},b")
    a("tst b")
    a(f"move {a.r7(S['V'])},a")
    a(f"move {a.r7(S['Y1'])},x0")
    a("tne x0,a", "series: F2 takes F1")
    a(f"move a,{a.r7(S['IN2'])}")
    _svf(a, S['IN2'], 2, 4)
    a("move a,x0", "F2's output")
    a(f"move {a.r7(S['Y1'])},a")
    a("add x0,a")
    a("asr #$1,a,a")
    a("move a,x1", "parallel: (F1 + F2)/2")
    a(f"move {a.r7(S['SER'])},b")
    a("tst b")
    a("move x1,a")
    a("tne x0,a", "series: F2 alone")
    a(f"move a,{a.r7(S['T0'])}", "y")
    # the clock's hold and leak
    a(f"move {a.r7(S['CINC'])},x0")
    a(f"move {a.r7(S['CLK'])},b")
    a("cmp x0,b", "phase < step: a tick")
    a(f"move {a.r7(S['T0'])},x0")
    a(f"move {a.r1(4)},a")
    a("tlt x0,a")
    a.st1("a", 4)
    a(f"move {a.r7(S['LEAK'])},b")
    a("neg b")
    a("move b,y1", "-leak")
    a(f"move {a.r7(S['CLK'])},b")
    a(f"move {a.r7(S['LEAK'])},a")
    a("move #>$400000,x0")
    a("cmp x0,b")
    a("tge y1,a", "the clock's high half: -leak")
    a("move a,y1")
    a(f"move {a.r1(4)},a")
    a("abs a")
    a("move a,x1", "|held|")
    a(f"move {a.r1(4)},a")
    a("mac y1,x1,a")
    a("move a,x0", "held + leak")
    a(f"move {a.r7(S['DIRT'])},b")
    a("tst b")
    a(f"move {a.r7(S['T0'])},a")
    a("tne x0,a", "DIRT: the held, leaking sample")
    a("move a,x0")
    _asym(a, S['AOUT'])
    a(f"move {a.r7(S['CM'])},y1")
    a("mpy x0,y1,a")
    a(f"move {a.r7(S['CCNT'])},b")
    a("normf b1,a", "the level back")
    a("move a,x1", "y")
    a(f"move {a.r1(5)},x0")
    a("move x1,a")
    a("sub x0,a")
    a(f"move {a.r1(6)},x0")
    a(f"move #>{h(C['DC'])},y1")
    a("mac x0,y1,a", "the DC blocker")
    a.st1("x1", 5)
    a("move a,x0", "o")
    a.st1("x0", 6)
    a(f"move {a.r7(S['PHOTO'])},y1")
    a("mpy x0,y1,a")
    a("move x0,x1", "o")
    a("move a,x0", "o x photocell")
    a(f"move {a.r7(S['GATE'])},b")
    a("tst b")
    a("move x1,a")
    a("tne x0,a", "GATE: the VCA")
    a("move a,x:(r0)+")
    a("move (r1)+n1", "the right channel's block")
    a.label("mzchan")
    a("nop")
    a.label("mzloop")
    a("nop")
    a("rts")
    _subs(a)
    return "\n".join(L) + "\n"


def _subs(a):
    L = a.lines
    L.append("")
    a.c("---- the knob word in a -> x0 = ws = w + w/127 ----")
    a.label("mzws")
    a("and #>$7f0000,a")
    a("move a1,x0", "w = knob/128")
    a(f"move #>{h(C['STR'])},y1")
    a("mac x0,y1,a", "w + w/127")
    a("move a,x0", "ws (127 -> full scale)")
    a("rts")
    a.c("---- s in a1 -> y1 = EXP2[s & 15], the count -((s >> 4) + 1) in the scratch slot ----")
    a.label("mzexp")
    a("move a1,x1", "s")
    a("and #>$00000f,a")
    a("move a1,x0", "s & 15")
    a("move x0,a", "clean")
    a(f"add #>{h(M.AT_EXP)},a")
    a("move a1,n5")
    a("move r4,r5")
    a("move x1,a")
    a("asr #$4,a,a", "s >> 4")
    a("move a1,x1", "the integer part: the asr left the remainder in a0")
    a("move x1,a")
    a("add #$1,a")
    a("neg a", "normf's count")
    a(f"move a1,{a.r7(S['CNT'])}")
    a("move (r5)+n5")
    a("move p:(r5),b")
    a("move b,y1", "the mantissa 2^((s&15)/16)/2")
    a("rts")
    a.c("---- x0 = RES ws, a = p -> k, g in their slots, y1 = 1/(1 + g(g + 2k)) ----")
    a.label("mzcoef")
    a(f"move a,{a.r7(S['T1'])}", "p")
    a(f"move #>{h(C['R98'])},y1")
    a("mpy x0,y1,a")
    a("move a,x0")
    a("move #>$7fffff,a")
    a("sub x0,a")
    a(f"move a,{a.r7(S['KK'])}", "k = 1 - 0.98 RES")
    a(f"move {a.r7(S['T1'])},a")
    a("move a,x1", "p")
    a("asr #$10,a,a", "idx")
    a("move a1,x0")
    a("move x0,a")
    a(f"add #>{h(M.AT_G)},a")
    a("move a1,n5")
    a("move r4,r5")
    a("move x1,a")
    a("and #>$00ffff,a")
    a("asl #$7,a,a", "frac")
    a("move (r5)+n5")
    a("move a1,x0")
    a("move p:(r5)+,y0", "G[i]")
    a("move p:(r5),b", "G[i+1]")
    a("move y0,a")
    a("sub a,b")
    a("move b,y1")
    a("mpy x0,y1,a")
    a("add y0,a")
    a(f"move a,{a.r7(S['G'])}", "g")
    a(f"move {a.r7(S['KK'])},a")
    a("asl #$1,a,a")
    a(f"move {a.r7(S['G'])},x0")
    a("add x0,a", "g + 2k")
    a("asr #$2,a,a")
    a("move a,x0", "(g + 2k)/4")
    a(f"move {a.r7(S['G'])},y1")
    a("mpy x0,y1,a")
    a("add #>$200000,a", "+ 1/4")
    a("move a,x0", "d4 = (1 + g(g + 2k))/4")
    a(f"move #>{h(C['Y0'])},a")
    a(f"add #>{h(C['Y0'])},a")
    a(f"move #>{h(C['Y1'])},y1")
    a("mac -x0,y1,a")
    a("mac -x0,y1,a")
    a("move a,y1", "y0 = 1.29 - 1.16 d4")
    a("do #$4,>mznwt", "Newton: y (2 - d y)")
    a("mpy x0,y1,a", "d4 y")
    a("move a,x1")
    a("move #>$400000,a")
    a("sub x1,a")
    a("move a,x1", "1/2 - d4 y")
    a("mpy y1,x1,a")
    a("asl #$2,a,a")
    a("move a,y1")
    a.label("mznwt")
    a("nop")
    a("rts")


def _asym(a, slot):
    """x0 = v -> x0 = asym(v): v + a v^2, then s - s^3/3"""
    a("mpy x0,x0,a")
    a("move a,x1", "v^2")
    a(f"move {a.r7(slot)},y1")
    a("move x0,a")
    a("mac y1,x1,a")
    a("move a,x0", "v + a v^2")
    a("mpy x0,x0,a")
    a("move a,y1")
    a("mpy x0,y1,a")
    a("move a,x1", "s^3")
    a(f"move #>{h(-C['THIRD'])},y1")
    a("move x0,a")
    a("mac y1,x1,a")
    a("move a,x0", "s - s^3/3")


def _svf(a, xin, f, co):
    """f: the filter's state offset in the channel block (r1)"""
    """the TPT state-variable filter on x:(r7+xin); state at f, f+1; coefficients at A1+co.. ;
    leaves the MORF mix in a"""
    r = a.r7
    q1 = a.r1
    a(f"move {r(xin)},a")
    a(f"move {q1(f + 1)},x0")
    a("sub x0,a")
    a("move a,x1", "v3 = x - ic2")
    a(f"move {q1(f)},x0", "ic1")
    a(f"move {r(S['A1'] + co)},y1")
    a("mpy x0,y1,a")
    a(f"move {r(S['A2'] + co)},y1")
    a("mac y1,x1,a")
    a(f"move a,{r(S['V1'])}", "v1 = a1 ic1 + a2 v3")
    a(f"move {q1(f + 1)},a")
    a("mac x0,y1,a")
    a(f"move {r(S['A3'] + co)},y1")
    a("mac y1,x1,a")
    a(f"move a,{r(S['V2'])}", "v2 = ic2 + a2 ic1 + a3 v3")
    a(f"move {r(S['V1'])},a")
    a("asl #$1,a,a")
    a("sub x0,a")
    a("move a,x0", "n = 2 v1 - ic1")
    a("mpy x0,x0,a")
    a("move a,y1")
    a("mpy x0,y1,a")
    a("move a,x1", "n^3")
    a(f"move #>{h(-C['SIXTH'])},y1")
    a("move x0,a")
    a("mac y1,x1,a")
    a.st1("a", f)
    a(f"move {r(S['V2'])},a")
    a("asl #$1,a,a")
    a(f"move {q1(f + 1)},x0")
    a("sub x0,a")
    a.st1("a", f + 1)
    a(f"move {r(S['V1'])},x0")
    a(f"move {r(S['K'] + co)},y1")
    a(f"move {r(xin)},a")
    a("mac -x0,y1,a")
    a("mac -x0,y1,a")
    a(f"move {r(S['V2'])},x1")
    a("sub x1,a")
    a("move a,x1", "hp = x - k v1 - v2")
    a(f"move {r(S['V2'])},x0")
    a(f"move {r(S['WL'])},y1")
    a("mpy x0,y1,a")
    a(f"move {r(S['V1'])},x0")
    a(f"move {r(S['WB'])},y1")
    a("mac x0,y1,a")
    a(f"move {r(S['WH'])},y1")
    a("mac y1,x1,a", "MORF")


def main():
    out = gen()
    dst = ROOT / "modules/mushrm/mushrm.asm"
    if "--check" in sys.argv:
        if not dst.exists() or dst.read_text() != out:
            sys.exit("modules/mushrm/mushrm.asm is stale: run python3 tools/mushrm/gen_mushrm.py")
        print("mushrm.asm matches the generator")
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(out)
    print(f"wrote {dst.relative_to(ROOT)} ({out.count(chr(10))} lines)")


if __name__ == "__main__":
    main()
