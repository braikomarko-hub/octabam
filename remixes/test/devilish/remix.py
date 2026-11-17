"""OCTA303 + dEVILish beside the stock effects (PHASER, whose id dEVILish takes, gives up its words).

vFable, 17 Nov 2026 (work in progress, branch octa303_optimus_23): dEVILish's DSP half is the 303 voice's filter
(327 words and two 98-word tables), no longer a pass-through of a few words: COMPRESSOR and LO-FI give up theirs too."""

from remix.schema import Proof, Remix

REMIX = Remix(
    name="devilish",
    family="mods",
    proof=Proof.HARDWARE,
    proof_note="the owner's MKI, image DEVPR2 (BUILD 93, this remix), 22 Oct 2026: every dEVILish knob, an LFO, "
               "a scene, a lock, save and reload; test_octa303 and verify_octa303_ui under the port",
    doc="OCTA303 and dEVILish (the Devil Fish mods on FX1 or FX2 of an OCTA-303 track) beside the stock effects but PHASER.",
    modules=(
        "OCTA303", "DEVILISH",
        "FILTER", "EQUALIZER", "DJ EQ", "FLANGER", "CHORUS",
        "SPATIALIZER", "COMB FILTER",
        "DELAY", "PLATE REV", "SPRING REV", "DARK REV",
    ),
    fx1=("DEVILISH",
         "FILTER", "EQUALIZER", "DJ EQ", "FLANGER", "CHORUS",
         "SPATIALIZER", "COMB FILTER"),
    fallback="NONE",
)
