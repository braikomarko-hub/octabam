# `octa303` — OCTA303 vFable (in progress)

**This branch rebuilds the TB-303 voice from zero.** The OCTA-303 machine's shell is here and works:
the machine row, the PLAYBACK and SETUP pages, dEVILish's knobs, the 303 gate and slide, CHROMATIC, held
trig + UP / DOWN, the output stage with DRIV and the stopwatch. **The engine is empty and plays silence.**
The contract between the two, with the knobs' laws that stay, is [`ENGINE_ABI.md`](ENGINE_ABI.md).

Author: MaMarko (Marko Brajković, [braikomarko-hub](https://github.com/braikomarko-hub)): the idea, the listening and the tests on the unit.
**The code is written by Claude (Anthropic).** Markers as in `CHIP.md`: ✅ measured, 🟡 inferred.

## Limit: two machines in a Part

A Part holds at most **two** OCTA-303 tracks. Choosing OCTA-303 for a third shows `MAX 2 OCTA-303` and the
track becomes plain FLEX. A Part loaded with more has its first two signed tracks (by track number) kept and
the rest unsigned by the Part validator.

## Using it

1. Double-tap the track key (the machine list), choose **OCTA-303** (below PICKUP), **YES**.
   FUNC + SRC opens the same list, but on a FLEX or STATIC track with a sample it opens the sample
   list first: LEFT reaches the machines (the stock behaviour).
2. Sequence it like any track. **Accent** = an ACC parameter lock. **Slide** = a trigless trig or a
   trigless lock (FUNC + TRIG) on the following step; since v7.1 it gets the note it slides from as
   its TUNE lock the moment it is placed (the previous step with a trig or a trigless step: its TUNE
   lock, or the Part's TUNE), so the slide ties into that note as on the TB-303. Turn TUNE with the
   step held to slide somewhere else. A step that already has a TUNE lock keeps it.
3. The CHROMATIC keys play semitones on an OCTA-303 track.
4. **The TB-303's UP and DOWN** (v7.1): in GRID RECORDING, hold one or more trigs and press UP or
   DOWN: each held step's TUNE goes an octave up or down (a step without a TUNE lock starts from
   the Part's TUNE; a note past C1..C5 stays where it is), and the screen shows the note
   (`C4 +OCT`). On every other track TRIG + UP / DOWN is stock (the sample-lock list).
5. LFO SETUP names an OCTA-303 track's PLAYBACK destinations TUNE CUT RES ENV DEC ACC (v7.1; before,
   FLEX's PTCH STRT LEN RATE RTRG RTIM: the modulation was right, the names were not).


### PLAYBACK page (the FLEX playback slots)

| slot | name | range | what it does |
|---|---|---|---|
| 0 | TUNE | C1..C5 (raw 40..88) | semitones, shown as note names; C3 = 0 |
| 1 | CUT | 0..127 | cutoff, the 303's CUTOFF FREQ law |
| 2 | RES | 0..127 | resonance (self-oscillation only with dEVILish's SWP) |
| 3 | ENV | 0..127 | ENV MOD (audio taper, as the Roland service notes) |
| 4 | DEC | 0..127 | DECAY (the service notes: MIN 200 ms, MAX 2.5 s to 10 %) |
| 5 | ACC | 0..127 | the ACCENT knob, applied on the notes that carry an ACC lock |

A new OCTA-303 track starts at TUNE C3, CUT RES ENV DEC 64, ACC 0.

### SETUP page (the FLEX setup slots)

| slot | name | values | default | what it does |
|---|---|---|---|---|
| 6 | WAVE | SAW, SQR, SAW+D, SQR+D, RSAW, RSQR, RSAWD, RSQRD | SAW | waveform; `+D` adds a distortion pedal stage after the VCA; `R` = the 303 as Roland's factory trims its filter (TM3: the cutoff +0.575 octave at every CUT; without `R`, Din Sync's 303) |
| 7 | GATE | OFF, 303 | OFF | OFF: the AMP page shapes the note. 303: the 303's own gate, 3.5 of the step's 6 clocks (Whittle), tied into a slide |
| 8 | FINE | −64..+63 | 0 | fine tune, ±½ semitone |
| 9 | SLID | 0..127 | 0 | slide time (0 = the 303's RC; `devilish`'s SLID wins when it is on the track) |
| 10 | DRIV | 0..127 | 0 | the 303's VOLUME (VR8) past Din Sync's position. 0 = the recording's level (pin 6's ceiling only); above 0 up to +10 dB into the output mixer's soft, asymmetric saturation (Q33/Q34). Projects saved with DRIV > 0 sound different |
| 11 | ACCV | 0..127 | 64 | accent loudness: the accent's current into the VCA × ACCV/64; 64 = the 303 |

## How it works

- **Audio.** The FLEX entry of the renderer kind table (`0x400d6438`) points at `sy_render`. On an
  OCTA303 track it lets the stock renderer write the header (PTCH/RATE neutralised, the carrier's
  positions pinned) and then the engine writes its samples into it; every other track is stock. AMP, FX1
  and FX2 stay stock, after the voice.
- **The machine row** uses the seams that repeat98 measured for `analog-bassdrum`: the same
  fifteen detours and six pokes, without its engine pool. A track is stored as FLEX and signed
  `'T','B',1` in its NEIGHBOR PLAYBACK bytes (`Part + 0x3c + 30·track`, unused by NEIGHBOR). Its
  page record is a clone of the user's FLEX descriptor, built at run time, published as UI type 5
  (`0x400d5f4c`). The Part validator (`0x40002318`) sees FLEX's defaults in a signed track's twelve
  bytes and gets ours back after. Projects stay ordinary projects.

## Credits and sources

- **Din Sync**, *TB-303 reference recordings for x0xb0x* —
  http://www.dinsync.info/2010/02/tb-303-reference-recordings-for-x0xb0x.html — the recordings the voice is measured against.
- **Robin Whittle**, *Devil Fish* manual and "TB-303 unique" notes (Real World Interfaces) — the
  gate length (3.5 of 6 clocks), the accent RC values (47k × 0.033 µF; 47k + 100k with 1 µF), the
  slide RC, the square's duty by pitch, every Devil Fish modification in `devilish`. https://www.firstpr.com.au/rwi/dfish/ ; the
  *User Manual for the Devil Fish mods to the TB-303* (2019) is linked there.
- **Tim Stinchcombe**, analysis of the TB-303 diode ladder ("diode2") — the transfer function the
  low-frequency behaviour was checked against. https://www.timstinchcombe.co.uk/index.php?pge=diode2
- **Roland**, TB-303 service notes — DECAY range, ENV MOD taper, slide capacitor.
- **Tim Hastie**, SYNTH MACHINE 2.9 (https://github.com/timhastie/octatrick-modules, MIT) — the FLEX integration
  this module re-does for one voice (renderer entry, START resolution, PTCH/RATE neutral, pinned
  positions, the clean retrig byte, the PLAYBACK page clone) and the semitone tuning system.
- **repeat98** (https://github.com/repeat98), `analog-bassdrum` (this repository) — the measured machine-list seams the OCTA-303
  row uses.
- **Sam Banks**, octabam — the build, the port, the remixer.

## Gates

- `tools/octa303/sim/test_octa303.py`: the shell's promises to the engine (the R_* inputs, the integration as
  poly.s 2.9 does it, the stopwatch) and the output stage bit for bit against `tools/octa303/o3out.py`.
- `tools/verify/verify_octa303_ui.py`: the panel under the port (select and edit, unsign, the validator; needs
  `OT_PROJECT`).
- `tools/octa303/play_gate.py IMAGE --project DIR`: a project with two OCTA-303 tracks playing every step under
  the port; it cannot see a CPU overload (the port counts instructions), the unit's LOAD is the measurement.

The manifest declares it in conflict with SYNTH MACHINE and BLACKPYRAMIDS_303 (the same machine row and FLEX
seams). The Devil Fish knobs need the companion FX module [`devilish`](../devilish/README.md).
