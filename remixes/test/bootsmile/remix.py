"""BOOT SMILE on its own, with the stock effects: the owner's power-on smile, for its gate."""

from remix.schema import Proof, Remix

REMIX = Remix(
    name="bootsmile",
    family="mods", proof=Proof.CHECK,
    proof_note="24 Oct 2026: tools/bootsmile/test_bootsmile.py; the first build ran on the owner's MKI "
               "(black on white), the inverted frames not yet",
    doc="BOOT SMILE (a white smile grows, stays and melts at power-on) with the stock effects.",
    modules=("BOOT_SMILE", "FILTER", "EQUALIZER", "DJ EQ", "PHASER", "FLANGER",
             "CHORUS", "SPATIALIZER", "COMB FILTER", "COMPRESSOR", "LO-FI",
             "DELAY", "PLATE REV", "SPRING REV", "DARK REV"),
    fallback="NONE",
)
