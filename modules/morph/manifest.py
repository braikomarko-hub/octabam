"""MORPH v2 -- a track key held ~1 s (or [TRACK]+[UP]): the track's MORPH window; its scene morph runs by itself.

v2 (25 Oct 2026): TYPE RISE (A -> B once over the cycle, then back on A and parked until the
crossfader is at A: a build-up on single tracks while the rest of the scene does something else);
the long press opens the window of that track (YES arms, the same track key applies and closes, NO
applies nothing); the window redrawn as the owner's sketch (the stock pages' big font, the stock knob
on encoders A..D with its value only while it turns, the knob row in negative, a bar showing where the
track is between A and B).


A morphing track's A/B weight comes from a triangle of one cycle = STEPS x x sequencer 16th steps
(default 16 x 8 = 128; STEPS 0 = the track's length), counted on the sequencer's step word, always
starting on scene A on the step after the keys, instead of from the crossfader; the other tracks
keep the crossfader. MODE SMOOTH or TRIG HOLD. [TRACK]+[DOWN] lets the cycle finish on A and parks
the track there until the crossfader reaches its A end. Inspired by the Korg Electribe's Motion
Sequence. [TRACK]+[UP] opens the window (A STEPS, B x 1..16, C MODE) and arms the held tracks;
releasing the track keys starts them on the next step. The settings and which tracks morph are
saved with the project in morph.work (a STORE client, modules/store).

Sites, measured from the user's 1.40C (base 0x40000400; modules/morph/README.md):
  * the frame builder at 0x4000cc62 (`move.l #96,%macsr ; lea 12(%sp),%sp`, 10 bytes): once a
    frame, after the per-track loop and before 0x4000cc6c, where every path that reads the
    per-track weights 0x80003c60.. starts. No branch in the image lands inside the 10 bytes.
  * the [TRACK]-held key layer 0x400d164a: its keys field 0x400d164e (stock 0x400d1594) points at
    the unit's copy of the stock table with UP (0x33) and DOWN (0x20) added.
"""

import os

from remix.schema import Category, Detour, Gate, Kind, Linked, Module, Proof, SymbolRef

H = bytes.fromhex
_HERE = os.path.relpath(os.path.dirname(os.path.realpath(__file__)))

STOCK_TKEY = 0x40040250
TABLES = (("MKI", 0x400BFC10, 2), ("MKII", 0x400C01F4, 2))   # index of the T1 record in each


def _press_fields():
    """The PRESS field of T1..T8 in both key tables (records 0x1a bytes, code at +0, press at +2;
    the T1 record is the third of each: 0x400bfc44 and 0x400c0228), measured for TRACK MENU on the
    owner's 1.40C (24 Oct 2026) and run on his MKI."""
    refs = []
    for name, table, first in TABLES:
        for t in range(8):
            addr = table + (first + t) * 0x1A + 2
            refs.append(SymbolRef(addr, STOCK_TKEY, "morph", "lp_tpress",
                                  f"{name} key table, T{t + 1} press: the stock handler, then MORPH's long press"))
    return tuple(refs)


FRAME_HOOK = 0x4000CC62
FRAME_STOCK = H("a93c00000060" "4fef000c")          # move.l #96,%macsr ; lea 12(%sp),%sp
KEYS_FIELD = 0x400D164E                              # the [TRACK]-held layer's keys pointer
KEYS_STOCK = 0x400D1594                              # 6 records + the 0xff terminator

MODULE = Module(
    name="morph",
    key="MORPH",
    kind=Kind.CF_PATCH,
    category=Category.PARTS,
    author="MaMarko",
    author_url="https://github.com/braikomarko-hub",
    doc=("Hold a track key about a second (or track + UP): that track's MORPH window. YES arms, the same "
         "track key starts it: from the next step its scene morph runs by itself, LOOP (A -> B -> A over "
         "STEPS x x steps) or RISE (A -> B once, then back on A, parked until the crossfader is at A); "
         "the other tracks keep the crossfader. Track + DOWN finishes the cycle on A and parks it. "
         "Settings saved with the project. Inspired by the Korg Electribe's Motion Sequence."),
    proof=Proof.HARDWARE,
    proof_note=("v2 (long press, RISE, the new window): tools/morph/test_morph.py, not yet on the unit. "
                "v1: the owner's MKI, image MRPPR1 (BUILD 98, remix morph), 23 Oct 2026: the window, the "
                "start on the release, x to 16 and 41.625, saving (SAVE PROJECT, power cycle, RELOAD, "
                "another project and back), stop and parking on A; before, inside aCiDtRacK (ACIDV74MP, "
                "22 Oct): several tracks at once, SMOOTH and TRIG HOLD"),
    linked=(
        Linked("morph", os.path.join(_HERE, "morph.s"), dram=True),
    ),
    detours=(
        Detour(FRAME_HOOK, FRAME_STOCK, "morph", "morph_frame",
               "frame builder, before the scene morph reads the per-track weights: write each "
               "morphing or parked track's weight", kind="jmp", pad_to=10),
    ),
    symbol_refs=(
        SymbolRef(KEYS_FIELD, KEYS_STOCK, "morph", "mp_keys",
                  "[TRACK]-held key layer: the stock table plus UP (MORPH ON) and DOWN (MORPH STOP)"),
    ) + _press_fields(),
    requires=("STORE",),
    conflicts=(
        ("REC_TRIG_MUTE", "it repoints the YES/NO records of the stock [TRACK]-layer table "
                          "0x400d1594, which MORPH replaces with its own copy (its YES/NO would "
                          "silently stop working)"),
    ),
    gates=(
        Gate("tools/morph/test_morph.py", remix_arg=False),
    ),
)
