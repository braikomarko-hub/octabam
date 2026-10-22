"""MORPH v1 -- [TRACK]+[UP] / [TRACK]+[DOWN]: a track's scene morph (A -> B -> A) runs by itself.

A morphing track's A/B weight comes from a triangle of one cycle = STEPS x x sequencer 16th steps
(default 16 x 8 = 128; STEPS 0 = the track's length), counted on the sequencer's step word, always
starting on scene A on the step after the keys, instead of from the crossfader; the other tracks
keep the crossfader. MODE SMOOTH or TRIG HOLD. [TRACK]+[DOWN] lets the cycle finish on A and parks
the track there until the crossfader reaches its A end. Inspired by the Korg Electribe's Motion
Sequence. [TRACK]+[UP] opens the window (A STEPS, B x, C MODE, YES on/off). Not built yet: the
menu row for the master switch, saving.

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
    doc=("Hold a track key and press UP: from the next step that track's scene morph runs by itself, "
         "A -> B -> A over STEPS x x steps, starting on A; the other tracks keep the crossfader. "
         "Track + DOWN finishes the cycle on A and parks the track there until the crossfader reaches "
         "A. Inspired by the Korg Electribe's Motion Sequence."),
    proof=Proof.HARDWARE,
    proof_note=("v0 on the owner's MKI, image ACIDV73MP (aCiDtRacK + MORPH), 21 Oct 2026: the keys, the "
                "morph of the held track, the others on the fader, parking on A. v1 (the step clock, "
                "STEPS x x, TRIG HOLD, the master switch, the window): tools/morph/test_morph.py, 52/52 in cfsim; "
                "the port and the unit pending"),
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
    ),
    conflicts=(
        ("REC_TRIG_MUTE", "it repoints the YES/NO records of the stock [TRACK]-layer table "
                          "0x400d1594, which MORPH replaces with its own copy (its YES/NO would "
                          "silently stop working)"),
    ),
    gates=(
        Gate("tools/morph/test_morph.py", remix_arg=False),
    ),
)
