"""AtoMizer -- a granular delay insert for FX2, after the Red Panda Particle V1.

The behaviour of the Particle (V1 on the Spin FV-1, 2011; Particle 2, 2019) as its
owner's manual (firmware 2.2, July 2023) and its public changelog describe it,
re-derived for the Octatrack: no Red Panda code, no firmware read. Eight modes
(DELAY + DENS / LFO / REV / PITCH / RND, PITCH + DTUNE / LFO / DENS), a freeze,
and the Particle 2's feedback modes (recycle, post delay, ping pong, grain
repeat), with the changelog's improvements: AUTO feedback (post delay in
DELAY + DENS), a density floor, the BLEND law (dry whole to 64), no knob jumps
when MODE changes, FREZ 0 always releases.

FX2 only: reads the allocator at init (x:>$213) and uses 15,779 words of the Y
slot, up to +$3DA2 like DARK REV, so it never reaches the demand loader's words in the
window slots (README, "Memory and cost"); an FX1 slot (3,072 words) is too small. State
in r7 + $00..$5f. atomizer_ref.py is the bit-exact model the DSP is proven against
(tools/verify/verify_atomizer.py).

0x1e is the PREFERRED id: registry.assign_ids gives the remix's own (docs/contributing/
MODULES.md), so AtoMizer replaces nothing and the stock DELAY stays. Its 1,564 words fit
a donor run or, loaded on demand (Remix.window_demand, docs/proposals/DEMAND_LOAD.md), a
window slot at +$1000: remixes/test/atomizer is built that way, with every stock effect.
On the track whose FX2 slot holds the loaded code the instance stays dry (atomizer.asm).
"""

from remix.schema import (BusRole, Category, Claims, DspSection, Formatter, Gate, Harness, Kind,
                          MenuEntry, ModeView, Module, Param, Proof, YBase)

MODES = ("DDEN", "DLFO", "DREV", "DPCH", "DRND", "PDTN", "PLFO", "PDEN")
FBMDS = ("AUTO", "RCYC", "POST", "PING", "REP", "R1/2", "R1/4", "RPCT")
CHOP_HT = (3, 4, 6, 8, 12, 16, 24, 48)        # SYNC: CHOP's divisions, half MIDI ticks: 1/64 .. 1/4
TIME_HT = (3, 6, 9, 12, 18, 24, 36, 48)       # SYNC: TIME's: 1/64 1/32 3/64 1/16 3/32 1/8 3/16 1/4
EXP = tuple(round(512 * 2 ** (i / 12)) for i in range(-12, 14))   # Q9 increments, -12 .. +13 semitones
PTABLE = CHOP_HT + TIME_HT + EXP

_P = Formatter.PLAIN

# TIME and PARA mean something different in each MODE (the Particle's DELAY/PITCH
# and PARAM knobs): the names follow MODE, the values never jump (the Particle 2.2
# "expert mode": no defaults here, so MODE DEFAULTS leaves the knobs where they are).
_NAMES = {
    0: {1: b"DLY", 2: b"DENS"}, 1: {1: b"RNGE", 2: b"SPD"}, 2: {1: b"DLY", 2: b"DIR"},
    3: {1: b"DLY", 2: b"JUMP"}, 4: {1: b"DLY", 2: b"RAND"}, 5: {1: b"PTCH", 2: b"DTUN"},
    6: {1: b"PTCH", 2: b"RATE"}, 7: {1: b"PTCH", 2: b"DENS"},
}

MODULE = Module(
    name="atomizer",
    key="ATOMIZER",
    kind=Kind.DSP_EFFECT,
    category=Category.TRACK, author="Marko Brajković", author_url="https://github.com/braikomarko-hub",
    proof=Proof.RENDER,
    proof_note="its own render gates (dsp_host, bit-exact against atomizer_ref.py); not on hardware",
    doc="Granular delay after the Red Panda Particle V1: 8 modes, freeze, recycle/post/ping/repeat feedback; FX2.",
    menu=MenuEntry(
        fx2_id=0x1e,                  # preferred; the remix assigns the id (registry.assign_ids)
        donor_desc=0x400d58b8,        # DARK REV: 12 active slots
        abbr=b"ATMZ",
        fullname=b"ATOMIZER",
        build_tag=False,
    ),
    params=(
        Param(b"CHOP", 48, 128, active=True, formatter=_P,
              doc="grain size: 1.5 .. 184 ms; SYNC: 1/64 .. 1/4 of the tempo"),
        Param(b"TIME", 40, 128, active=True, formatter=_P,
              doc="delay modes: delay time (SYNC: 1/64 .. 1/4); pitch modes: -12 .. +12 semitones"),
        Param(b"PARA", 64, 128, active=True, formatter=_P,
              doc="the mode's parameter: density, scan speed, direction, jump, randomness, detune, LFO rate"),
        Param(b"FDBK", 0, 128, active=True, formatter=_P,
              doc="feedback; in the REP modes the repeats (0..8) or, in RPCT, their probability"),
        Param(b"FREZ", 0, 128, active=True, formatter=_P,
              doc="0 off; 1..126 freeze while the input is under the threshold; 127 frozen"),
        Param(b"MIX", 64, 128, active=True, formatter=_P,
              doc="0-64 adds the wet up to unity over the whole dry; 64-127 fades the dry out"),
        Param(b"MODE", 0, 8, active=True, formatter=Formatter.WIDE_STEPPED, labels=MODES,
              doc="DELAY + DENS/LFO/REV/PITCH/RND, PITCH + DTUNE/LFO/DENS (the Particle's eight)"),
        Param(b"TONE", 127, 128, active=True, formatter=_P,
              doc="a low-pass in the feedback: 0 dark .. 127 open"),
        Param(b"FBMD", 0, 8, active=True, formatter=Formatter.WIDE_STEPPED, labels=FBMDS,
              doc="AUTO (POST in DDEN, else RCYC), RCYC, POST, PING, REP, R1/2, R1/4, RPCT; a change clears"),
        Param(b"SPRD", 0, 128, active=True, formatter=_P,
              doc="random stereo spread of the grains"),
        Param(b"SYNC", 0, 2, active=True, formatter=Formatter.STEPPED, labels=("FREE", "SYNC"),
              doc="SYNC: CHOP and TIME are divisions of the tempo, grains restart on the input's attacks"),
        Param(b"V1", 0, 128, active=True, formatter=_P,
              doc="reserved: the FV-1's memory colour (not yet read)"),
    ),
    mode_slot=6,
    mode_views=tuple(ModeView(mode=m, names=n) for m, n in _NAMES.items()),
    dsp=DspSection(
        asm="modules/atomizer/atomizer.asm",
        ptable=PTABLE,
        priority=26,
        bus_role=BusRole.NONE,
        ybase=YBase.NEVER,
        r7_latch_slot=None,
        gate_label=None,
    ),
    claims=Claims(stock_instance_buffer=True, buffer_words=15779),
    harness=Harness(layout_char=None, is_server=False),
    gates=(Gate("tools/verify/verify_atomizer.py", remix_arg=False),),
    dear={"CHOP": 127, "TIME": 127, "PARA": 0, "FDBK": 127, "FREZ": 0, "MIX": 64,
          "MODE": 5, "TONE": 0, "FBMD": 4, "SPRD": 127, "SYNC": 0},
)
