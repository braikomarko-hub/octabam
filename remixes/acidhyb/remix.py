"""aCiDhYb: aCiDtRacK with the hybrid OCTA303 (OCTA303 SEAM: the voice's FM, filter, VCA, MUFF, DIST and output stage on the DSP at the source seam). COMPRESSOR, LO-FI and DJ EQ given up for the DSP code (MaMarko, 19 Nov 2026); stock FILTER for MODULATION, COMB FILTER off the chooser (25 Nov 2026). OCTA303 + dEVILish + MORPH + KITS + TRACK PATTERNS + MODULATION + DISTORX + VCA160 (KEYBUS) + FET76 + LOAD METER + USB AUDIO OUT (MASTER) + BRAIN (REMIX SWITCH), DARK REV the one reverb."""
from remix.schema import Proof, Remix

REMIX = Remix(
    name="acidhyb", family="mods", proof=Proof.CHECK,
    proof_note="25 Nov 2026 (ACIDV102, not yet on a unit): MODULATION (Sam's, 1,297 words) in place of SPECTRUM, KITS back (MaMarko); under the port verify_set, verify_octa303_ui and the play gate pass, in dsp_host verify_dirty_state and verify_modulation. 25 Nov 2026 (ACIDV101, cleared to flash the same day): SPECTRUM in place of COMB FILTER, VCA160 + KEYBUS in place of dB666 (ids pinned: VCA160 0x1b, DISTORX 0x06, as before), TRACK PATTERNS, REC CS1 SKIP, RECORDER LOOP FIX; stock FILTER out for the room (not used, MaMarko); under the port: verify_set, verify_octa303_ui and the play gate pass, and verify_load_meter's DSP records arrive with both bars drawn (its otop/wrap expectations are octabam-bus's); in dsp_host: verify_dirty_state, verify_keybus and verify_vca160 (its own scratch image) pass. 25 Nov 2026 (ACIDV100, on the author's MKI: 'funziona'): OCTA303 v10.0 (Yves Rosius's ColdFire savings from #1244 ported, the DSP voice 40 cycles a sample lighter, a damaged record refused), STORE #1238 and USB #1245 (Yves Rosius) taken before Sam's merge. 25 Nov 2026 (ACIDV99, on the author's MKI: 'suona perfettamente', CFIRE 72 %): OCTA303 SEAM v9.1, every voice on the DSP (FM, MUFF, DIST, DRIV too), FM's source smoothed; MORPH v1.2. 19 Nov 2026 (ACIDV97, on the author's MKI: no clicks, CFIRE ~70): aCiDtRacK (V96, stradaA-1) + OCTA303 SEAM; COMPRESSOR, LO-FI and DJ EQ out (not used: dB666 is the compressor). Before, as aCiDtRacK: 11 Nov 2026 (ACIDV91, the measurement image): STROJ, AtoMizer (and the demand loader DLPUMP/DLCOPY it needed) and KITS left out, MaMarko's call for sound and load work; OCTA303 v8.2 with a stopwatch read over USB (tools/octa303/prof). "
               "2 Nov 2026: FET76 (the 1176LN) added, FLANGER given up; FET76 bit-exact in dsp_host, not yet on the unit. "
               "27 Oct 2026: KITS added (255 Kits per project, for long live sets). "
               "26 Oct 2026: on Sam's tree of 26 Oct with MORPH v1.1, AtoMizer (loaded on demand) and LOAD METER, "
               "TAPE ECHO left out; not yet on the unit in this form. Before: ACIDV77 (24 Oct 2026, the author's MKI: "
               "OCTA303 v7.1, dEVILish, MORPH v1, DISTORX, dB666, TAPE ECHO, BRAIN) 'works perfectly'; ACIDV68..ACIDV71 "
               "(October 2026): hours of live use with two or three OCTA-303 tracks, dEVILish, DISTORX and dB666",
    doc="aCiDhYb: the hybrid OCTA303 (FM, filter, VCA, MUFF, DIST and output on the DSP) + dEVILish + MORPH (track + UP/DOWN: the scene morph by itself) + KITS + TRACK PATTERNS + MODULATION (JUNO, DIM, FLNG, COMB, PHSR, with LOFI) + DISTORX (BOSS SD-1 + Pro Co RAT + Turbo RAT) + VCA160 (the dbx 160, side-chain KEY from any track through KEYBUS) + FET76 (the UREI 1176LN limiter, for the master after VCA160) + LOAD METER + USB AUDIO OUT MASTER + BRAIN (FX presets from the card; switch remixes from the card); DARK REV the one reverb.",
    modules=('OCTA303', 'OCTA303 SEAM', 'DEVILISH', 'MORPH', 'STORE', 'USB', 'BRAIN', 'MEMORY',
             'MODULATION', 'DELAY', 'DARK REV', 'DISTORX', 'VCA160', 'KEYBUS', 'FET76',
             'LOAD METER', 'TRACK PATTERNS', 'REC CS1 SKIP', 'RECORDER LOOP FIX', 'KITS'),
    fx1=('MODULATION', 'DEVILISH', 'DISTORX', 'VCA160'),
    # dB666 is VCA160 now and DISTORX sorts before it: pinned to the ids the author's saved projects use
    ids={"VCA160": 0x1b, "DISTORX": 0x06},
    # The shared window: LOAD METER's DSP half in the gap below 0x37F00 (KEYBUS's words at X:0x37F60..0x37F6F). ACIDV91: AtoMizer and the demand loader (DLCOPY, its stub, DARK REV's guard) are out.
    window=(("LOAD METER", 0x37DA3), ("LOAD METER:B", 0x37E50)),
    fallback='NONE',
    settings={("octabam.usb", "TRACKS"): "OFF", ("octabam.usb", "MAIN"): 0,
              ("octabam.usb", "CUE"): 0, ("octabam.usb", "MASTER"): 1,
              ("octabam.usb", "IN"): "OFF", ("octabam.usb", "MIDI"): 1},
)
