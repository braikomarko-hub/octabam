"""TRACK PATTERNS with the stock effects: a pattern per track, clip style."""

from remix.schema import Proof, Remix

REMIX = Remix(
    name="trackpatterns",
    family="mods", proof=Proof.HARDWARE,
    proof_note="MKII, OCTABAM3, 21 Oct 2026: functional tests and trig LEDs passed (contributor's report)",
    doc="TRACK PATTERNS with the stock effects: hold TRACK + PATTERN + TRIG for a pattern per track.",
    modules=("TRACK PATTERNS",
             "FILTER", "EQUALIZER", "DJ EQ", "PHASER", "FLANGER",
             "CHORUS", "SPATIALIZER", "COMB FILTER", "COMPRESSOR", "LO-FI",
             "DELAY", "PLATE REV", "SPRING REV", "DARK REV"),
    fallback="NONE",
)
