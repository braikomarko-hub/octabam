# `fet76` — FET76

A model of the UREI / Universal Audio 1176LN FET limiting amplifier (1967),
built from its manual (block diagram, schematic, specifications), as a
per-track insert. Its place in the author's remix is the master: T8's FX2,
after dB666.

Author: MaMarko (Marko Brajković, [braikomarko-hub](https://github.com/braikomarko-hub)): the idea, the listening and the tests on the unit.
**The code was written by Claude (Anthropic)**: model, calibration, DSP code and gates.

FET76 is a provisional name. 1176 and UREI are trademarks of their owners;
this module is not affiliated with or endorsed by Universal Audio, and the
names below only say which unit it models.

## What is modelled

| the 1176LN (manual) | FET76 |
|---|---|
| INPUT attenuator before a FIXED threshold | INPT: gain before the gain cell; no threshold knob |
| Q1, a FET as the lower leg of a divider with R5 | G = 1 / (1 + u), u the gate voltage the detector holds |
| FEEDBACK: the side chain reads the stage's output | the detector reads the output, the loop solved inside the sample (stable at 20 µs) |
| ratio buttons set side-chain level and diode bias | per button a side-chain gain S and a bias T: 4, 8, 12, 20:1 averaged over the first 10 dB of gain reduction |
| ATTACK R55 charging C27 (0.022 µF): 20 … 800 µs | ATK 127 … 1; ATK 0 = OFF (the attack pot's click), no limiting |
| C22 (0.22 µF) behind C27, RELEASE R56 + R57: 50 ms … 1.1 s | two capacitors: a short peak only fills C27 and lets go fast, held limiting fills C22 and lets go at the knob's time (program-dependent release) |
| "LN": the FET linearised | the FET's square-law residue, an even harmonic that grows with gain reduction; REV BLUE = the earlier units, more of it |
| class-A output stage, +22 dBm | z − 0.02 z³ (0.5 % THD at full scale) |
| ALL BUTTONS IN | the four side-chain gains together, the bias of a 16:1, attack three times slower, the residue ×8 |

Assumed (not in the sources): the coupling resistor between the two
capacitors (220 k), the buttons' thresholds at INPT 64 (4:1 −20, 8:1 −17,
12:1 −15, 20:1 −13 dBFS peak), ALL's numbers, the residue's size, the side
chain's rail (it keeps ATK audible on a big step).

## Knobs

| page | slot | name | range | what it does |
|---|---|---|---|---|
| 1 | 0 | INPT | bipolar, default 64 | INPUT: −30 … +30 dB into the fixed threshold |
| 1 | 1 | OUTP | bipolar, default 64 | OUTPUT: −30 … +30 dB |
| 1 | 2 | ATK | 0–127, default 100 | ATTACK: 1 = 800 µs … 127 = 20 µs; 0 = OFF |
| 1 | 3 | REL | 0–127, default 64 | RELEASE: 0 = 1.1 s … 127 = 50 ms (after held limiting) |
| 1 | 4 | RATI | 4:1, 8:1, 12:1, 20:1, ALL | the ratio buttons |
| 1 | 5 | MIX | 0–127, default 127 | dry/wet: 127 = the 1176 alone, 0 = an exact passthrough |
| 2 | 6 | REV | LN / BLUE | the revision: LN, or the earlier units' stronger 2nd harmonic |

Stereo-linked as the 1176 SA: the larger of |L| and |R| drives one gain.

## DSP

No buffer and nothing outside its r7 block: 143 words of P table, 486 of
code (406 until 16 Nov 2026), 320 cycles per sample at worst (cycle_count; 311
before: the count prices every word of the loop, the skips included). Two
24-step divisions per sample at worst (the loop's linearised solve and the
FET's 1/(1 + u)).

Lighter (16 Nov 2026), the same samples bit for bit: the charge (w, lam, its
division, u', the rail) is computed only on a sample where the diode conducts
(its only use was the `tgt` that takes u' then); at uA = 0 (no limiting, or
released to zero) G/2 and the residue are written, not computed; the knob
decode is skipped while the seven page words are the ones last decoded; uA and
the block constants live in registers (r1..r5, n1, n3, n4 are clobbered across
proc, as other modules' are on the unit; n2 is left alone). Old against new on the vendored emulator, standalone
(the dispatcher's ABI, the M registers linear, garbage in the scratch registers and the r7 block): 0
differing samples over 24 knob sets x 6 signals of 0.25 s and 10 runs with every
knob moving every 23 blocks, dirty page words and trig splits; the code before
and after equals `fixed()` there on the three sets tried. Executed instructions a 16-sample block, before ->
after: 4,680 -> 2,627 with no limiting (silence, ATK OFF), 3,342 on an acid
line at the defaults, 4,547 on a full-scale square (limiting on most samples);
the worst block 4,680 -> 4,729 (the cache's compare). `verify_fet76.py` needs
the stock image and was NOT run for this change. The fixed-point model is `fet76_ref.fixed()`; the float model
`fet76_ref.FET76` (the same file) is what the numbers below were measured on.

## Gates

`tools/verify/verify_fet76.py`: the dump against `fixed()` bit for bit
(24 knob sets × three signals, a split block, LFO-dirty page words), MIX 0
an exact passthrough, silence to zeros, and the manual on the fixed model:
the four ratios, ATK OFF, THD < 0.5 % with limiting at the slowest release,
release fast after a 5 ms peak and at the knob's time after one second;
and at ATK 0 with INPT and OUTP up, a clip, never a wrap (OUTPUT's gain is
applied in two normf steps, at most 7 bits each, inside the accumulator's guard bits).

Status: bit-exact in dsp_host; not yet on a unit.
