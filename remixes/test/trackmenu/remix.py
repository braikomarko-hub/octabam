"""TRACK MENU v1 with OCTA303 (ERGOSUM and its tied gate), MORPH (its own window stays) and STORE, and the stock effects."""

from remix.schema import Proof, Remix

REMIX = Remix(
    name="trackmenu",
    family="mods", proof=Proof.CHECK,
    proof_note="prototype, 24 Oct 2026: tools/trackmenu/test_trackmenu.py; not yet on the unit",
    doc="TRACK MENU v1 (hold a track key ~1 s: the track's menu; ERGOSUM plays, SPLIT ALL/NOTE/RTHM) beside OCTA303, MORPH and STORE, "
        "with the stock effects.",
    modules=("TRACK_MENU", "OCTA303", "MORPH", "STORE", "FILTER", "EQUALIZER", "DJ EQ", "PHASER", "FLANGER",
             "CHORUS", "SPATIALIZER", "COMB FILTER", "COMPRESSOR", "LO-FI",
             "DELAY", "PLATE REV", "SPRING REV", "DARK REV"),
    fallback="NONE",
)
