"""MORPH alone: track + UP / DOWN runs a track's scene morph by itself, with the stock effects."""

from remix.schema import Proof, Remix

REMIX = Remix(
    name="morph",
    family="mods", proof=Proof.CHECK,
    proof_note="v0, 21 Oct 2026: tools/morph/test_morph.py (source level) and tools/morph/port_morph.py "
               "(under the port, with a project); not flashed",
    doc="MORPH (track + UP / DOWN: the scene morph by itself) with the stock effects.",
    modules=("MORPH", "FILTER", "EQUALIZER", "DJ EQ", "PHASER", "FLANGER",
             "CHORUS", "SPATIALIZER", "COMB FILTER", "COMPRESSOR", "LO-FI",
             "DELAY", "PLATE REV", "SPRING REV", "DARK REV"),
    fallback="NONE",
)
