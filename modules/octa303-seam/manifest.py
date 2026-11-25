"""OCTA303 SEAM -- the hybrid OCTA303: the ColdFire keeps the knobs, the sequencer, the envelopes, the accent, the
slide and the VCO; the DSP renders the rest of the voice (FM, the resonance loop, the ladder, the VCA pair, the level,
the OTA, the VCA, pin 6, MUFF, DIST, the output coupling, DRIV) at the per-track source seam, before the stock AMP,
FX1 and FX2.

The seam is ANALOG BD's (modules/analog-bassdrum/ab_glue.asm): the stock `move a,x:>$20e` before the source
(payload A P:0x39c, B P:0x1a2) becomes a jsr into o3h.asm.  A track whose source record carries the signature
($a303 / $0303) is rendered by o3h into X:0, and the stock code continues after the source (A P:0x426, B P:0x221);
any other record returns into the stock source untouched.  octa303.s writes the record when its remix.inc has
O3_SEAM = 1 (modules/octa303/manifest.py): v9.1 (25 Nov 2026), every voice (v9.0: none with FM, MUFF, DIST or DRIV).
FM reads the VCA's word through a one-pole of 1/4 a sample (the cure for its "TV static", chosen by ear).  The
record's format: tools/octa303/ibrido3/hyb.py.

o3h.asm is generated (tools/octa303/ibrido3/gen_o3h.py; the build does not regenerate it): integer-exact against
ref303, instruction forms with a stock site or a CHIP.md register row only.  Its tables (pin 6, FM's ladder index
table, the clip's, DRIV's) are its ptable, one block (gen_o3h.ptable).
"""
import os
import sys

from remix.schema import Category, Claims, DspHook, DspRange, DspSection, Kind, Module, Proof

_HERE = os.path.relpath(os.path.dirname(os.path.realpath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "tools", "octa303"))
import o3tables as _T  # noqa: E402

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "tools", "octa303", "ibrido3"))
import gen_o3h as _G  # noqa: E402  (generates nothing on import but its lines in memory)

PTABLE = tuple(int(v) & 0xFFFFFF for v in _G.ptable)

MODULE = Module(
    name="octa303-seam",
    key="OCTA303 SEAM",
    kind=Kind.HYBRID,
    category=Category.MACHINES,
    author="MaMarko",
    author_url="https://github.com/braikomarko-hub",
    requires=("OCTA303",),
    doc=("The hybrid OCTA-303: the voice's filter, FM, VCA, MUFF, DIST and output stage (DRIV) run on the DSP at "
         "the track's source, the rest on the ColdFire."),
    proof=Proof.CHECK,
    proof_note=("25 Nov 2026 (v9.1, every voice): the DSP half on the dsp56300 emulator from the seam's jsr, 122,624 "
                "frames a payload (the judge's 208 half-A notes, 160 random runs, 100 with dEVILish: FM, MUFF, SWP, "
                "DIST and DRIV at random), 0 differing samples against ref303, both payloads; the ColdFire half in "
                "cfsim, record for record against tools/octa303/ibrido3/hyb.py. v9.0 (19 Nov, the smooth voice only) "
                "ran on a unit as ACIDV97 (MKI, owner's report: no clicks, CFIRE ~70 with a full project)."),
    claims=Claims(dsp_ranges=(
        DspRange("x", 0x7C00, 0x100, "the four voices' blocks (64 words a voice at 2 * x:$418: 32 state words, then "
                                     "the piece's control block, decoded from the record, and the tables' addresses), "
                                     "in stock's unreferenced X:$7a92-$7fff (no DMA in its 8K block)"),
    )),
    dsp=DspSection(
        asm=os.path.join(_HERE, "o3h.asm"),
        priority=32,
        payloads=frozenset({"A", "B"}),
        ptable=PTABLE,
        hooks=(DspHook({"A": 0x39C, "B": 0x1A2}, (0x567000, 0x00020E), "oh01s",
                       "the per-track source seam: a signed OCTA303 record renders the voice into X:0 and continues "
                       "after the source"),),
    ),
)
