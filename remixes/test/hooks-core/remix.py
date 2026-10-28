"""CORE with every module a HOOKS bridge joins to it: MORPH and REC THRESHOLD (beside CORE's
REC_TRIG_MUTE), CF METER, CF METER IDLE and BOOT TRACE (beside CORE's LOAD METER). The registry
appends HOOKS, which owns the five shared sites (modules/hooks). PHASER gives up its words for
LOAD METER's DSP half (as stock-meter-a); DARK REV's hold CF METER's readout insert (as cfmeter)."""
from remix.schema import Pin, Proof, Remix

CORE = ("BRAIN", "STORE", "KITS", "MIDI SCENES", "SCENES P2", "PLOCKS P2",
        "CC MAP", "CC FEEDBACK", "USB",
        "RECORDER LOOP FIX", "BATCH_BUGFIXES", "ERASE_EMPTY_TRIGLESS_LOCKS",
        "QUANTIZE_LIVE_REC_TOGGLE", "REC_TRIG_MUTE", "MUTE_MODES",
        "SCALE QUANTIZER", "TUNER", "DIRECT_JUMP_KYOTI", "RELOAD_FROM_PROJECT", "RLEN PLEN",
        "ATA WRITE GUARD", "EVENTS",
        "LOAD METER")
BRIDGED = ("MORPH", "REC THRESHOLD", "CF METER", "CF METER IDLE", "BOOT TRACE")
STOCK = ("FILTER", "EQUALIZER", "DJ EQ", "PHASER", "FLANGER", "CHORUS", "SPATIALIZER",
         "COMB FILTER", "COMPRESSOR", "LO-FI", "DELAY", "PLATE REV", "SPRING REV", "DARK REV")
DROPPED = ("PHASER", "DARK REV")

REMIX = Remix(
    name="hooks-core",
    family="mods", proof=Proof.PORT,
    proof_note="verify_hooks: the five bridged sites in this image; the chains under Unicorn",
    doc="CORE + MORPH, REC THRESHOLD, CF METER, CF METER IDLE and BOOT TRACE: HOOKS owns the five sites they share with CORE.",
    modules=CORE + BRIDGED + ("LOFI AMF FIX",) + tuple(e for e in STOCK if e not in DROPPED),
    fx1=tuple(e for e in STOCK[:10] if e not in DROPPED),
    fallback="NONE",
    settings={("octabam.usb", "TRACKS"): "PRE", ("octabam.usb", "MAIN"): 1,
              ("octabam.usb", "CUE"): 1, ("octabam.usb", "MASTER"): 0,
              ("octabam.usb", "IN"): "OFF",
              ("kyoti.mute-modes", "PLACE"): Pin("DRAM")},
)
