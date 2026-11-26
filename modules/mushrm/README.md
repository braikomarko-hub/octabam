# `mushrm` — MU-SHRM

A per-track filter insert, FX1 or FX2, **mono** (L and R are summed, filtered once, and the result goes to
both sides, as the Mu-Tron III and the Sherman are mono): the Mu-Tron III's photocell (an envelope follower with a fast attack and
a slow release) moves two state-variable filters in the manner of the Sherman Filterbank 2, with the Sherman's
dirt: noise, the switched-capacitor clock that holds the output and leaks into it, and an asymmetric
saturation. KEY lets another track move the filter (the Mutronics Mutator's external input), through KEYBUS.

Idea, choices and listening: MaMarko. Model, generator and code: Claude (Anthropic).

## Knobs

| page | slot | name | range | what it does |
|---|---|---|---|---|
| 1 | 0 | BASE | 0–127 | F1 at rest: 30 Hz .. 10 kHz, exponential |
| 1 | 1 | SENS | −64..+63 | how much the photocell hears: −18 .. +18 dB |
| 1 | 2 | DPTH | −64..+63 | how far the photocell moves F1: 0 none, up opens, down closes, up to 5 octaves |
| 1 | 3 | RES1 | 0–127 | F1's resonance |
| 1 | 4 | RES2 | 0–127 | F2's resonance |
| 1 | 5 | HARM | P-24 .. P+24, S-24 .. S+24 | F2 against F1 (−24 −19 −12 −7 −5 0 +5 +7 +12 +19 +24 semitones); P parallel, S series |
| 2 | 6 | MORF | 0–127 | low-pass (0) → band-pass (64) → high-pass (127), continuous |
| 2 | 7 | KEY | OFF, T1..T8 | who moves the photocell: this track, or that track's block peak on KEYBUS |
| 2 | 8 | SPD | 0–127 | the photocell's speed: 64 = 4 ms attack, 45 ms release; 0 four times slower, 126 about four times faster; **127 = GATE** |
| 2 | 9 | DRIV | 0–127 | 0 .. +30 dB in; two thirds of the dB come back off at the output |
| 2 | 10 | ASYM | 0–127 | the asymmetric saturation, at the input and (half of it) at the output |
| 2 | 11 | DIRT | 0–127 | 0 clean; 1..63 noise + the clock at 100 × F1; 64..127 the clock at 50 × F1 |

GATE (SPD 127): the photocell is either closed or open (at the LED law's middle) and also opens and closes the
output, so a track keyed to a kick plays only on the kick.

## How it works

- **The photocell**, once a block: the peak of |L+R|/2 of the block (or, with KEY, the word KEYBUS publishes for
  that track), through SENS, a LED law (−24 dB .. −6 dB onto 0 .. 1, from log2 by the LOG table), then a one-pole
  whose coefficient depends on the direction (attack or release) and on SPD. The coefficients assume the unit's
  16-frame block.
- **The filters**: Zavalishin's TPT state-variable filter, two a channel. Each block takes g = tan(πf/fs) from a
  69-word table (an eighth of an octave a point, linear interpolation), k = 1 − 0.98 RES, and 1/(1 + g(g + 2k)) by
  four Newton steps. The band-pass state goes through n − n³/6 every sample, so the resonance cannot run away.
  F2 is HARM's step from F1; in series it filters F1's output.
- **The dirt**: a 24-bit Galois noise register (x²⁴ + x⁷ + x² + x + 1, two steps a sample) at −60 .. −30 dB
  before the filters; the clock's phase advances 100 or 50 × F1 a second; at each tick the output is held, and a
  square at the clock's rate, its depth proportional to the held sample, is added (the clock that leaks).
- **The saturations**: v + a v², then s − s³/3, at the input (ASYM/2) and at the output (ASYM/4); a DC blocker
  after them.
- **Mono**: (L + R)/2 in, the one result out on both sides (MaMarko's choice, 26 Nov 2026: half the cycles of
  the stereo first version, 876 a sample in `interlock_scan`'s model).
- **DIRT 0 and GATE off skip their code** (a branch a sample each): the clock and the noise stand still.
- **State**: about 60 words of the instance's r7 block (`$00..$3d`, below the `$84` limit). No delay line: it
  runs in FX1 and FX2.
- **Tables**: 130 words (LOG 33, EXP2 17, G 69, HARM 11), the module's ptable, parked in the stock curve bank in
  a remix without DJ EQ.

## The model and the gate

`tools/mushrm/mushrm_ref.py` is the integer model: every word 24 bits, every multiply kept whole in the
accumulator until the move that floors and limits it. `tools/mushrm/gen_mushrm.py` writes `mushrm.asm` from the
model's constants, using only instruction forms with a stock site or a CHIP.md register row.
`tools/verify/verify_mushrm.py` runs the assembly in `dsp_host` on both payloads, FX1 and FX2 instances, and
compares every sample with the model: the knobs' corners, GATE, KEY with a seeded KEYBUS word, series and
parallel, the dirt, out-of-range bytes, silence and 60 random knob sets; it also runs `-guard` and an impulse at
full resonance. It needs a `dsp_host` with `-xword`.

## Cost

`interlock_scan` (sambanks/main's model from the DSP56300 manual, not a measurement): 393 cycles a sample at the
defaults (230 instructions), 488 with every feature on (DIRT, GATE, series). 847 words of P, 130 of table.

## Not covered

- The unit: the cycles are the model's (`interlock_scan`), the sound has been heard only from the model.
- The photocell's law, the clock's leak and the noise's level are choices, made by ear on the model, not
  measured from a Mu-Tron III or a Sherman Filterbank.
