"""HOOKS's boot bridge: BOOT TRACE beside PARTS (with MIDI LOOPBACK, its client) and the stock effects.

Both take the boot's call after the platform loader (0x40000512); the registry appends HOOKS,
which sends BOOT TRACE's note 3 and then runs PARTS's activation (modules/hooks, boot).
"""

from remix.schema import Proof, Remix

REMIX = Remix(
    name="hooks-boot",
    family="mods", proof=Proof.PORT,
    proof_note="verify_hooks: the boot chain under Unicorn and in this image; verify_parts: the activation",
    doc="BOOT TRACE beside PARTS and MIDI LOOPBACK: HOOKS runs both at the boot's post-loader call.",
    modules=("PARTS", "MIDI LOOPBACK", "BOOT TRACE",
             "FILTER", "EQUALIZER", "DJ EQ", "PHASER", "FLANGER",
             "CHORUS", "SPATIALIZER", "COMB FILTER", "COMPRESSOR", "LO-FI",
             "DELAY", "PLATE REV", "SPRING REV", "DARK REV"),
    fallback="NONE",
)
