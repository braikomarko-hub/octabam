# aCiDhYb

aCiDtRacK (V96) with the hybrid OCTA303: `OCTA303 SEAM` puts the voice's FM, resonance loop, ladder, VCA pair, level,
OTA, VCA, pin 6, Muffler, DIST pedal, output coupling and DRIV on the DSP at the track's source seam; the ColdFire
keeps the knobs, the sequencer, the envelopes, the accent, the slide and the VCO. Since v9.1 (25 Nov 2026) every voice
plays there (v9.0 left FM, MUFF, DIST and DRIV on the ColdFire), and dEVILish's FM reads the VCA through a one-pole
(1/4 a sample): extreme FM stays wild instead of turning into static. COMPRESSOR, LO-FI and DJ EQ are left out to make
room for the DSP code. MORPH is v1.2 (RET, CURV, END).

## Where it has run

- ACIDV99 (v9.1, every voice on the DSP, FM smoothed; 25 Nov 2026): not yet on a unit. The DSP half on the dsp56300
  emulator, the ColdFire half in cfsim, both images under the port (`tools/octa303/ibrido3/`, the module's README).
- ACIDV97 (v9.0, 19 Nov 2026): on the author's MKI with a full project, OCTA303 on T5 and T6: no clicks, CFIRE about
  70 (80 with dEVILish OVDR and FM, which then ran on the ColdFire).
