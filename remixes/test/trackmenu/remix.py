"""TRACK MENU v0 with MORPH (its own window stays) and STORE, and the stock effects: the prototype on its own."""

from remix.schema import Proof, Remix

REMIX = Remix(
    name="trackmenu",
    family="mods", proof=Proof.CHECK,
    proof_note="prototype, 24 Oct 2026: tools/trackmenu/test_trackmenu.py; not yet on the unit",
    doc="TRACK MENU v0 (hold a track key ~1 s: the track's menu, navigation only) beside MORPH and STORE, "
        "with the stock effects.",
    modules=("TRACK_MENU", "MORPH", "STORE", "FILTER", "EQUALIZER", "DJ EQ", "PHASER", "FLANGER",
             "CHORUS", "SPATIALIZER", "COMB FILTER", "COMPRESSOR", "LO-FI",
             "DELAY", "PLATE REV", "SPRING REV", "DARK REV"),
    fallback="NONE",
)
