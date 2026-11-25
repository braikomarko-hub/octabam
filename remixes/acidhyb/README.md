# aCiDhYb

aCiDtRacK (V96) with the hybrid OCTA303: `OCTA303 SEAM` puts the voice's FM, resonance loop, ladder, VCA pair, level,
OTA, VCA, pin 6, Muffler, DIST pedal, output coupling and DRIV on the DSP at the track's source seam; the ColdFire
keeps the knobs, the sequencer, the envelopes, the accent, the slide and the VCO. Since v9.1 (25 Nov 2026) every voice
plays there (v9.0 left FM, MUFF, DIST and DRIV on the ColdFire), and dEVILish's FM reads the VCA through a one-pole
(1/4 a sample): extreme FM stays wild instead of turning into static. COMPRESSOR, LO-FI and DJ EQ are left out to make
room for the DSP code. MORPH is v1.2 (RET, CURV, END).

Since ACIDV101: SPECTRUM (since ACIDV102 MODULATION, and KITS back) on FX1 in place of COMB FILTER (stock COMB FILTER's code and dispatch stay, off the
chooser); VCA160 in place of dB666 on the same id and store (`ids` pins VCA160 0x1b and DISTORX 0x06), its KEY read
through KEYBUS; TRACK PATTERNS, REC CS1 SKIP and RECORDER LOOP FIX. Stock FILTER is out to make room for SPECTRUM, then MODULATION:
its id 0x04, every track's stock default FX1, now plays the null stub (the track passes unfiltered).

## Where it has run

- ACIDV102 (MODULATION, KITS; 25 Nov 2026): not yet on a unit. Under the port: verify_set, verify_octa303_ui, the
  play gate; in dsp_host: verify_dirty_state, verify_modulation.
- ACIDV101 (25 Nov 2026): built on the author's Mac and cleared to flash; no report yet. Under the port: verify_set on a fresh project, verify_octa303_ui,
  the two-voice play gate; in dsp_host: verify_dirty_state, verify_keybus, verify_vca160 (its own scratch image).
- ACIDV100 (OCTA303 v10.0, Yves Rosius's #1244/#1238/#1245 savings; 25 Nov 2026): on the author's MKI the same
  day, "funziona".
- ACIDV99 (v9.1, every voice on the DSP, FM smoothed; 25 Nov 2026): on the author's MKI the same day, "suona
  perfettamente" (DRIV 127 too), CFIRE 72 % with a full project, a long run without a fault.
- ACIDV97 (v9.0, 19 Nov 2026): on the author's MKI with a full project, OCTA303 on T5 and T6: no clicks, CFIRE about
  70 (80 with dEVILish OVDR and FM, which then ran on the ColdFire).
