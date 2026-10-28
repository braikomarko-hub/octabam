"""Loopback routing on stock effects, isolated from personal remixes."""
from remix.schema import Proof, Remix

REMIX = Remix(
    name="midi-loopback", family="mods", proof=Proof.HARDWARE,
    proof_note='',
    doc="Stock effects plus the Part-scoped per-track MIDI loopback routing.",
    modules=("MIDI PART STATE", "MIDI LOOPBACK", "FILTER", "EQUALIZER", "DJ EQ", "PHASER",
             "FLANGER", "CHORUS", "SPATIALIZER", "COMB FILTER", "COMPRESSOR",
             "LO-FI", "DELAY", "PLATE REV", "SPRING REV", "DARK REV"),
    fallback="NONE",
)
