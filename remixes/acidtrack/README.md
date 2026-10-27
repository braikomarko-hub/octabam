# acidtrack

aCiDtRacK, MaMarko's (Marko Brajković's) live set on the Octatrack MKI: OCTA303 (the OCTA-303 machine),
dEVILish (Devil Fish), MORPH (the scene morph by itself, saved with the project), DISTORX (SD-1 / RAT /
Turbo RAT), dB666 (side-chain from any track), AtoMizer (a granular delay after the Red Panda Particle,
FX2), LOAD METER, USB (MIDI and AUDIO OUT MASTER) and BRAIN with REMIX SWITCH (other remixes' `.RMX`
images booted from the card without flashing) and KITS (255 named Kits per project, each pattern playing its
own: for long live sets); DARK REV is the one reverb. PLATE REV, SPRING REV, CHORUS,
PHASER, SPATIALIZER and EQUALIZER are given up: DISTORX takes SPATIALIZER's id, dEVILish PHASER's,
dB666 EQUALIZER's, and their DSP words come from the others.

AtoMizer's code is not in the image's P memory: DLPUMP and DLCOPY copy it into the shared window
(`P:0x35000`, offset +$1000 of T8's FX2 slot on core A) while a track uses it
([`docs/proposals/DEMAND_LOAD.md`](../../docs/proposals/DEMAND_LOAD.md)). AtoMizer on **T8's FX2**, and on
any FX1 slot, passes the audio through. DARK REV is wrapped by DLWRAP so it never runs over the code
(on T8's FX2 it stays dry while AtoMizer is loaded).

**At most one AtoMizer per core: one on T1–T4 and one on T5–T8** (`DspSection.max_per_core = 1`).
The unit does not enforce it. Four on one core beside four DISTORX on FX1 price 3,552 cycles a sample
against the 3,120 usable (`tools/build/cycle_count.py`, 27 Oct 2026), and the DSP wall is a cliff.
AtoMizer at MIX 0 rests and costs almost nothing ([`modules/atomizer/README.md`](../../modules/atomizer/README.md)).

KITS is ColdFire only (no DSP cost) and needs STORE, which is here. With KITS the arranger is not supported
(`modules/kits/README.md`): change patterns by hand or with chains. It writes `kits.work` into every project
it opens, so back the card up first.

## Where it has run

- ACIDV77 (24 Oct 2026, with TAPE ECHO and MORPH v1, on an older tree): on the author's MKI, "works perfectly".
- ACIDV68..ACIDV71 (October 2026): hours of live use.
- This form (26–27 Oct 2026: MORPH v1.1, AtoMizer (lighter), LOAD METER, KITS, TAPE ECHO left out): not yet on the unit.
