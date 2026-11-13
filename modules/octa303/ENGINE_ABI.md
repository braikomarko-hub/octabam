# OCTA303 vFable: the engine's contract with the shell

`octa303.s` on this branch is the OCTA-303 machine's **shell** with an **empty engine**. The shell
makes the track exist and play on the Octatrack:
- the machine row and the Part signature;
- the PLAYBACK and SETUP pages and the knobs;
- dEVILish's knobs;
- the 303 gate and slide, CHROMATIC, held trig + UP / DOWN, the retrig;
- the output stage with DRIV, and the stopwatch.

The engine is three stubs at the end of the file, `o3e_note_on`, `o3e_params` and `o3e_render`, and
`o3e_render` writes silence. This document is everything the engine needs from the shell. The second
half lists the knobs' laws that must stay as they are.

The shell's code is the code that played on the author's MKI with the earlier engines. On this
branch it is checked by:
- `tools/octa303/sim/test_octa303.py` (22 checks), which runs the source in cfsim against a mock of OS 1.40C. It
  covers the engine's inputs, the output stage, the stopwatch, and the gate against `tools/octa303/o3gate.py`:
  the first note after PLAY, and a slide;
- `tools/octa303/play_gate.py IMAGE --project DIR`, under the port;
- `tools/verify/verify_octa303_ui.py`, the panel under the port.

Code and text written by Claude (Anthropic).

## 1. When the engine is called

The packer calls `sy_render(track, ping, start, end)` once per 16-sample frame, or twice when a
START splits the frame (`[0,n)`, then `[n,16)`). For an OCTA-303 track the shell calls the engine in
this order:

```
a START this frame (frame's last call)
   o3_params  -> R_* filled -> o3e_params      (ENGINE)
   o3_note_on -> R_WAVE, R_ACC, R_PNOTE, S_GNEW -> o3e_note_on   (ENGINE)
every call of a latched track
   o3_params  -> o3e_params                     (ENGINE)
   o3_gate    (frame's last call only) -> S_GATE, S_GMODE, S_GLVL
   the stock renderer (the carrier is pinned; its samples are overwritten)
   o3e_render (d7 = n samples)                  (ENGINE)
```

- A track is "latched" from its first START as the TB-303 machine until a START plays something
  else. A latched track is rendered every call, even when muted. This is a measured cost:
  `o3e_render` should be cheap when the voice is silent.
- **Registers.** In every call, `a3` is the track's state (1024 bytes, `ST_SIZE`), `a4` the packer's parameter
  record and `d2` the track.
- `o3e_note_on` and `o3e_params` may clobber `d0`, `d1`, `d4`, `a0` and `a1` only.
- `o3e_render` may clobber everything except `a3` and `sp`. It writes `d7` (1..16) samples to
  `(a1)+`, each as the same long to L and then to R. `o3_out` does this for you; see section 3.

## 2. The state: what the shell gives the engine

Offsets are into the 1024-byte state (`ST_SIZE`, 8 KB for the 8 tracks). Bytes **0..255 belong to the shell**: read them, do not write
them, except `S_GLVL` (see the gate). Bytes **256..1023 (`E_BASE`) belong to the engine** (768 bytes). Add more
state elsewhere only if you must, and measure the cache cost.

| field | what it is |
|---|---|
| `R_PTGT` | the pitch the knobs ask for now, in Q8 semitones. `P_CENTER` (16384) is TUNE 0 = C3. TUNE runs −24..+24 semitones (raw 40..88), FINE is included, and the value is clamped to `P_LO`..`P_HI` (±36 semitones). A slide is this value changing while the note plays: a trigless PTCH lock on the next step. Glide to it with the slide time (section 4). |
| `R_PNOTE` | the pitch at the START, in the same units |
| `R_CUT` `R_RES` `R_ENV` `R_DEC` | PLAYBACK CUT, RES, ENV MOD and DECAY, raw 0..127, locks / scenes / LFOs applied |
| `R_ACC` | the trig's ACC, raw 0..127, read at the START. 0 = not accented. Above 0 = accented, with the ACCENT knob at that value. |
| `R_WAVE` | SETUP WAVE 0..7: bit 0 = square, bit 1 = `+D` (the pedal), bit 2 = `R` (Roland's factory trim) |
| `R_ACCV` | SETUP ACCV, raw (64 = the 303) |
| `R_DRIV` | SETUP DRIV, raw. `o3_out` applies it; you only need it if you want to know it. |
| `S_FINE` | FINE as Q8 semitones, already inside `R_PTGT` |
| `R_SLID` | the slide knob in force, raw: dEVILish's SLID when dEVILish is on the track, else SETUP's SLID |
| `R_DFON` | 1 = dEVILish is on the track (FX1 or FX2) |
| `R_DF` | 12 bytes, raw 0..127: OVDR FM TRCK VDEC SLID ADEC / SATK SWP SPD MUFF CUTX ENVX. The selects are stored as their index (0..2), so clamp them with `MIN2`. Without dEVILish this is the neutral set 25 0 0 64 0 50 / 0 0 1 0 0 0, the Devil Fish limited to the 303 (Whittle p. 8). **The engine must sound the same with the neutral set as without dEVILish.** |
| `S_GMODE` `S_GATE` `S_GLVL` | the gate. **GATE OFF** (`S_GMODE` 0): `S_GLVL` = 32767 and the AMP page shapes the note. **GATE 303** (`S_GMODE` 1): `S_GATE` = 1 from the START until 3.5 of the step's 6 clocks (Whittle), held through slides; when the sequencer stands still it stays open. With GATE 303 the engine owns `S_GLVL` (Q15). The note's end follows the TB-303 (Whittle, Devil Fish manual 2019, p. 6: "the decay at the end of an unaccented note was about 16 ms – 8 ms of normal volume and 8 ms of linear decay"): after `S_GATE` falls, 8 ms at full level, then 8 ms of linear decay to zero. The note's start has no added delay (the 303's 1–5 ms is left out so the voice stays in time with the other tracks; Marko, 13 Nov 2026). The old engine moved `S_GLVL` by `GATE_K` (3733, Q15 per 16 samples, about 3.2 ms each way): a description of that engine, not a rule. The judge holds the gate for the whole note, so it does not measure the note's end: that is decided by ear. |

Two more fields: `S_GSEL` is SETUP's GATE, and `S_OSIN` is DRIV's gain for `o3_out`.

## 3. The output: `o3_out` (DRIV), kept as it is

`bsr o3_out` with `d6` = your sample `y`, `a1` = the output and `a3` = the state. It writes the
16-bit sample to L and R and does `a1 += 8`. It clobbers `d0`–`d2`, `d6` and `a0`.

- **DRIV 0:** `y` is only clamped to ±2^24 (a safety bound), then `y >> 6`, clamped to ±32767.
  The ceiling that shapes the sound is not here. In the old engine it was inside the voice: the BA662A's
  output, pin 6, cannot leave the supply. It was a soft knee, `y / (1 + (y/L)^4)^(1/4)`, with
  L− = 478,658 and L+ = 698,840 in `y` units: where the knee goes flat, the L in the formula is ~479,100 (fitted on Din Sync 🟡). It came before the output coupling.
- **DRIV above 0:** `y × G` (0..+10 dB) goes into the output mixer's soft, asymmetric saturation, Q33/Q34.
  Its knees sit on the old pin-6 ceiling: K− = 454,725 and L− = 478,658 (= pin 6's L−); K+ = 818,505
  and L+ = 861,584 (1.8 L−). **For DRIV to behave as now, your voice needs the same ceiling at the same
  levels** (or one that reaches them).
  This is the TB-303's VOLUME (VR8) turned past Din Sync's position. Marko: "the drive must be the
  TB-303's, as it is now."
- The Python model is `tools/octa303/o3out.py`, bit for bit; `test_octa303` checks it.
- **Not in `o3_out`:** the output coupling, the old engine's DC high-pass after `+D`. That belongs to the
  engine.

**Its level is part of the law.** DRIV saturates at fixed points in `y`, so the voice's level in `y`
decides where DRIV bites. These are the previous engine's levels:
- `y` at DRIV 0, measured in its Python model;
- through the shell's call path (`render_call`), from a fresh state, default SETUP, no dEVILish;
- 0.5 s notes, TUNE 0.

Only the third row depends on the whistle fix (the clip near the top of the filter): it is v8.2's, and v8.3
(`CL_GMIN` 0.3) gives 577,551 / 97,724 there. The other rows are the same in both.

| note | peak abs(y) | rms y |
|---|---|---|
| SAW, CUT RES ENV DEC 64, not accented | 213,697 | 52,457 |
| SAW, the same, accented ACC 127 | 504,776 | 81,382 |
| SAW, everything 127, accented | 555,932 | 95,683 |
| SQR, the knobs at 64, not accented | 162,675 | 48,946 |
| SAW, CUT 127, RES 0, ENV 0, not accented | 418,200 | 176,848 |

Keep your voice at the same level (±1 dB), and DRIV, dEVILish's MUFF threshold and the projects'
mix stay where they were.

## 4. The interface laws: what each value means (keep them)

**What binds and what describes** (Marko, 13 Nov 2026). Where this document says "the old engine did this", it is a
description, not an obligation: the TB-303 or the Devil Fish decides. The obligations are the rules on registers,
memory and computing time (sections 1, 2 and 5), and "the engine must sound the same with the neutral set as without
dEVILish".

Two kinds of knob:
- **Sound laws:** CUT, RES, ENV MOD, DECAY and ACCENT are the TB-303's own pots. Find their laws
  from Din Sync's recordings and the Roland service notes; how a position sounds may change.
- **Interface laws:** the knobs below keep their meaning, because Marko's projects use them.

Each law gives a source: W = Robin Whittle's Devil Fish manual (2019), R = the Roland service notes.

| knob | law |
|---|---|
| TUNE | raw 40..88 = −24..+24 semitones, C3 = 0. The CHROMATIC keys play semitones. |
| FINE | (raw − 64) × 2/256 semitone: −½..+0.49 semitone |
| GATE | OFF = the AMP page shapes the note. 303 = the 303's own gate (section 2; W: 3.5 of 6 clocks). |
| SLID (SETUP), and dEVILish SLID | Both knobs use the same law. A one-pole glide of the pitch toward `R_PTGT`, through the RC of R × C35 0.22 µF. 0 = the 303: R = 103.3 kΩ (DAC + protection), τ = 22.7 ms. 127: R = 103.3 + 500 kΩ (the Devil Fish pot), τ = 132.6 ms, linear in raw. Whittle (p. 16) gives these as slide times of 60 → 360 ms. |
| WAVE bit 0 | SAW / SQR, the 303's two waveforms |
| WAVE bit 1, `+D` | a fixed distortion pedal after the VCA (and after MUFF), before the output coupling. The old engine (`1.0` = 2^20): `o = softclip(5·o + 0.12)`, then a one-pole low-pass at 6 kHz. Here `softclip(x)` = `x − x³/6` with x clamped to ±√2. Keep its character: gain 5, a small asymmetry, a 6 kHz tone. |
| WAVE bit 2, `R` | the 303 as Roland's factory trim sets the filter. The law is the trim procedure (R, "ADJ. VCF"; the same in the RE-303 build guide by Din Sync's author, https://smakela.github.io/re-303-buildguide/docs/build_calibration): SAW, note A (110 Hz), CUT at the centre, RES fully clockwise, ENV / DEC / ACC 0; TM3 is set until the resonant peaks at TP6 are 2 ms apart (R: 2–2.5 ms), around 500 Hz. Without `R`, Din Sync's 303. In the old engine this came out as the cutoff +0.575 octave at every CUT (🟡 its result, not the law). |
| ACCV | the accent's loudness: the accent's contribution to the VCA × ACCV/64. 64 = the 303 (R: the accent current into the VCA). |
| DRIV | `o3_out` (section 3), as it is |
| OVDR | the VCO into the filter (W p. 4). 0 = none, 25 = the 303, 127 = 66.6 × normal: gain = raw/25 up to 25, then 66.6^((raw−25)/102). Above normal, the resonance is swamped and the output must not jump: the old engine scaled its resonance level compensation by G^−1.5 and the output by G^−0.3. |
| FM | the VCA's output, after MUFF, moves the cutoff per sample (W pp. 5, 18–19). It is AC coupled, as on the Devil Fish (W p. 12: "the AC coupled output of the VCA (which incorporates the Muffler) via the Filter FM Pot"; W p. 3 puts the corner at about 5 Hz): vFable takes the VCA output through a one-pole high-pass at 5 Hz. (The old engine took it with no high-pass.) With FM at 0 the sound must not change, bit for bit. Its depth: linear in raw; at raw 127, about 47 semitones for abs(VCA out) = 2^20 in `y` units. |
| TRCK | filter tracking, linear in Hz (W pp. 5, 14): at 127 the cutoff rises ~2.7 kHz per octave of pitch, as (raw/127)^1.5 × 2700 Hz/oct, zero at TUNE 0. Low notes can shut the filter. |
| VDEC | the volume decay (W p. 4): 0..64 = 16 ms .. the 303's own decay (τ geometric); 64..127 = that decay with a sustain level from 0 (at 64) to full (at 127). 127 = endless notes. |
| ADEC | the accented notes' filter decay (W p. 4): 30 ms .. 3 s to 10 %, continuous. 50 = the 303's own (200 ms). It is the same envelope circuit with another resistor in place of R138. |
| SATK | the soft attack of non-accented notes (W pp. 4, 24–25). 0 = the 303's own attack. 1..127 = 90 % in 0.3 → 30 ms (log). |
| SWP | ACID = the 303. WHST = the resonance feedback doubled ("double the usual feedback", W p. 18): self-oscillates at mid / high cutoff. SELF = doubled, and the accent sweep circuit off: accents no longer reach the filter and the VCA. |
| SPD | the accent sweep's speed (W pp. 4–5). NORM = the 303. FAST = the first accent strongest, then the next smaller. SLOW = a much longer time constant that can rise twice as high. (The old engine charged and discharged 4× slower and doubled the sweep: an interpretation 🟡.) |
| MUFF | the Muffler after the VCA (W pp. 6, 19): it softens the loudest extremes, with a square-wave clipping buzz, and the bass passes; no effect at low level. The old engine (🟡 interpretation): split at ~150 Hz; above it, SOFT = a soft clip and HARD = a hard clip at 314,572 in `y` units (0.3 × 2^20, the 303's normal peak at RES 0). Note that an open filter (the reference table's last row) peaks above it. |
| CUTX | the CUTOFF pot's range widened (W p. 6): 157 Hz → ~4.8 kHz, exponential in raw |
| ENVX | the ENV MOD pot's range tripled, and including none (W p. 6) |

**What "the same knobs" promises Marko:** every knob is there and does the same thing in the same
direction, so a saved project plays. **What it does not promise:** that a CUT, RES, ENV, DEC or ACC
position sounds exactly as before, because those are the laws vFable re-derives.

## 5. The budget

**At most 10 LOAD points for a voice** (Marko, 11 Nov 2026). It is measured on his MK1 like this:
1. Load the project `tEst85` (148 BPM) after a power-up.
2. Note CFIRE with the project at rest.
3. Play T5 alone with 16 accented trigs, the other tracks without trigs.
4. The difference is the voice's cost.

With the v7.3 engine this was 38 − 26 = 12 points ✅ (10 Nov 2026).

🟡 Inferred:
- **The conversion.** If 1 point is 1 % of the frame interrupt (an assumption), 10 points are about
  9,600 cycles a frame: there are 95,782 cycles in a 16-sample frame at 264 MHz. That is about 600
  cycles a sample, **shell included**.
- **The stock renderer is inside the 10.** The stock FLEX renderer still runs on every call for the
  carrier. Bryan T measured a playing FLEX voice at about 14.6–16.5 µs, about 4–4.5 % of the frame
  (`docs/firmware/ARCHITECTURE.md`). So perhaps 35–45 % of the 600 cycles is spent before the engine
  runs. The stopwatch's entry-to-loop row (`O3_PROF` +12) measures exactly this on the unit.

The v7.3 figure used the same procedure: the project at rest after a power-up (26 %), then T5 alone
with 16 accented trigs (38 %). The shell's own
cost under the port with the empty engine is 2,455 instructions a frame for two voices
(`play_gate`, 11 Nov 2026). That is an instruction count, not cycles: the chip has cost 2.5–4×
the simulator's count. The stopwatch (`O3_PROF`, read over USB with `tools/octa303/prof/o3prof.py`)
measures the call, the shell's part and the sample loop per track on the unit.
