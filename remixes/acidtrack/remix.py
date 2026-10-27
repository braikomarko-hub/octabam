"""aCiDtRacK: OCTA303 + dEVILish + MORPH + DISTORX + dB666 + AtoMizer (loaded on demand) + LOAD METER + USB AUDIO OUT (MASTER) + BRAIN (REMIX SWITCH) + KITS, DARK REV the one reverb."""
from remix.schema import Proof, Remix

REMIX = Remix(
    name="acidtrack", family="mods", proof=Proof.CHECK,
    proof_note="27 Oct 2026: KITS added (255 Kits per project, for long live sets). "
               "26 Oct 2026: on Sam's tree of 26 Oct with MORPH v1.1, AtoMizer (loaded on demand) and LOAD METER, "
               "TAPE ECHO left out; not yet on the unit in this form. Before: ACIDV77 (24 Oct 2026, the author's MKI: "
               "OCTA303 v7.1, dEVILish, MORPH v1, DISTORX, dB666, TAPE ECHO, BRAIN) 'works perfectly'; ACIDV68..ACIDV71 "
               "(October 2026): hours of live use with two or three OCTA-303 tracks, dEVILish, DISTORX and dB666",
    doc="aCiDtRacK: OCTA303 + dEVILish + MORPH (track + UP/DOWN: the scene morph by itself) + DISTORX (BOSS SD-1 + Pro Co RAT + Turbo RAT) + dB666 (side-chain from any track) + AtoMizer (granular delay after the Red Panda Particle, FX2, loaded on demand; dry on T8's FX2) + LOAD METER + USB AUDIO OUT MASTER + BRAIN (switch remixes from the card) + KITS (255 Kits per project: each pattern plays its own Kit); DARK REV the one reverb.",
    modules=('OCTA303', 'DEVILISH', 'MORPH', 'STORE', 'KITS', 'USB', 'BRAIN', 'MEMORY', 'FILTER', 'DJ EQ', 'FLANGER',
             'COMB FILTER', 'COMPRESSOR', 'LO-FI', 'DELAY', 'DARK REV', 'DISTORX', 'DB666',
             'ATOMIZER', 'LOAD METER', 'DLPUMP', 'DLCOPY'),
    fx1=('FILTER', 'DJ EQ', 'FLANGER', 'COMB FILTER', 'COMPRESSOR', 'LO-FI', 'DEVILISH', 'DISTORX', 'DB666'),
    # The shared window (docs/proposals/DEMAND_LOAD.md, as remixes/test/atomizer): DLCOPY, the stub and DARK
    # REV's guard from 0x33DC3 (dB666's side-chain bus sits at Y:0x37FF8 / 0x3FFF8), AtoMizer at +0x1000 of T8's FX2
    # slot (core A), copied there while a track uses it, LOAD METER's DSP half in the gap below 0x37F00.
    window=(("DLCOPY", 0x33DC3), ("ATOMIZER", 0x35000), ("LOAD METER", 0x37DA3), ("LOAD METER:B", 0x37E50)),
    window_demand=("ATOMIZER",),
    window_guard=("DARK REV",),
    window_loader=0x33E56,
    fallback='NONE',
    settings={("octabam.usb", "TRACKS"): "OFF", ("octabam.usb", "MAIN"): 0,
              ("octabam.usb", "CUE"): 0, ("octabam.usb", "MASTER"): 1,
              ("octabam.usb", "IN"): "OFF", ("octabam.usb", "MIDI"): 1},
)
