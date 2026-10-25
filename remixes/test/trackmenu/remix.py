"""TRACK MENU v2 (MORPH, EUKLE, ERGOSUM, all working) with OCTA303 (ERGOSUM's tied gate), MORPH (its own window stays) and STORE, and the stock effects."""

from remix.schema import Proof, Remix

REMIX = Remix(
    name="trackmenu",
    family="mods", proof=Proof.CHECK,
    proof_note="v2, 25 Oct 2026: tools/trackmenu/test_trackmenu.py, test_eukle.py; v0 navigated on the owner's MKI",
    doc="TRACK MENU v2 (hold a track key ~1 s: the track's menu; MORPH, EUKLE print/undo/LIVE, ERGOSUM) beside OCTA303, MORPH and STORE, "
        "with the stock effects.",
    modules=("TRACK_MENU", "OCTA303", "MORPH", "STORE", "FILTER", "EQUALIZER", "DJ EQ", "PHASER", "FLANGER",
             "CHORUS", "SPATIALIZER", "COMB FILTER", "COMPRESSOR", "LO-FI",
             "DELAY", "PLATE REV", "SPRING REV", "DARK REV"),
    fallback="NONE",
)
