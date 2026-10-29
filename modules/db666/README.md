# `db666` — dB666

A model of the dbx 160 compressor/limiter (1976), built from its schematic and
its manual, as a per-track insert with an id of its own — with a side-chain KEY
from any track over a one-word-per-track bus. Every stock effect stays.

Author: MaMarko (Marko Brajković, [braikomarko-hub](https://github.com/braikomarko-hub)): the idea, the listening and the tests on the unit.
**The code was written by Claude (Anthropic)**: engine, calibration, integration and gates.

The name: decibels and the Devil (it sits beside dEVILish in the author's remix).
dbx is a trademark of Harman; this module is not affiliated with or endorsed by
dbx or Harman, and the name dbx 160 below only says which unit it models. It was
called DBX 160 in the author's images up to ACIDV73MP (October 2026).

The 160's character is its detector: dbx's true-RMS module (RMS 208, M2 on
the schematic; David Blackmer's log-domain RMS, US 3,681,618, one of the
patents printed on the schematic). Attack and release are not knobs on a 160:
they are that detector's single time constant. The manual gives the release
as 125 dB/s, which fixes it at τ = 10·log₁₀(e)/125 = 34.7 ms, and the same τ,
unchanged, gives the manual's attack times. THRESHOLD and COMPRESSION act in
dB on the detector's output and drive a VCA (dbx 200, M1) with the
difference: a hard knee, ratio 1/(1 − k) for a fraction k of the dB over
threshold.

## FX id

`0x1b` preferred (a free id: `schema.FREE_FX2_IDS`), no `replaces`, so no
stock effect is taken and a remix may move it (`registry.assign_ids`). Up to
image ACIDV81 (28 Oct 2026) the author's remix ran it on EQUALIZER's `0x0c`
(`replaces="EQUALIZER"`); a project saved there opens its dB666 tracks on
whatever that remix puts on `0x0c`, so those tracks are re-selected once
(or the remix keeps the old id with `Remix.ids`, where the id is free).

## Knobs

| page | slot | name | range | what it does |
|---|---|---|---|---|
| 1 | 0 | THRS | 0–127, default 96 | THRESHOLD: −50 dBFS (0) … 0 dBFS (127), RMS — the 160's 10 mV … 3 V span (49.5 dB), its top at full scale |
| 1 | 1 | RATI | 0–127, default 50 | COMPRESSION: k = 0.992 × RATI/100 up to 100 (0 = 1:1, 50 = 2:1, 75 = 4:1, 100 = 120:1, the 160's "infinity"); 101…127 carry on to k = 2 (127 = −1:1, the 160A's negative compression: louder in, quieter out) |
| 1 | 2 | OUT | bipolar, default 64 | OUTPUT GAIN (R80): −20 … +20 dB |
| 1 | 3 | KEY | OFF, T1…T8 | the detector's source: OFF = this track (the 160's own input), T1…T8 = that track's level from the bus (the 160's detector input jack) |
| 1 | 4 | MIX | 0–127, default 127 | dry/wet: 127 is the 160 alone, 0 an exact passthrough |
| 2 | 6 | KNEE | HARD / OVER | HARD = the 160; OVER = the 160A's OverEasy, a 10 dB-wide soft knee (width assumed) |

Stereo-linked like two 160s strapped for "true RMS power summing": one
detector on (L² + R²)/2, one gain on both channels.

## The side-chain bus

A `DspHook` at the stock dispatcher's FX1 entry — the site SIDECHAIN_COMPRESSOR
hooks (`sctap`), proven on an MKI — runs `dbt_tap` for every track, every
block, with the track's 16 frames at X:$00–$1F. It writes ONE word, the
block's mean square, at its core's half of the shared window:

| tracks | written by | words |
|---|---|---|
| T1–T4 | payload B (core 1) | Y:$3FFF8–$3FFFB |
| T5–T8 | payload A (core 0) | Y:$37FF8–$37FFB |

A dB666 on either core reads the one word its KEY names, once per block.
One 24-bit store is atomic, so the two cores need no generation counter; a
word is at most one block (0.36 ms) old. The tap uses a, r0, r1, n1, x0 —
inside the set stock reloads after this site — and replays the displaced
`move x:>$208,r6`. Cost: 32 `mac`s and ten words per track per block, about
11 cycles per sample per core; SIDECHAIN_COMPRESSOR copies the whole block
twice per track to offer audio-rate keys and a key listen, which the 160's
RMS detector does not need. The words sit at +$3FF8 of T8's and T4's FX2
slots, above every stock effect's measured extent (DARK REV's +$3DA2), in
Y:0x37F00..0x3FFFF, which payload B's boot zero loop clears. Until 26 Oct 2026
they sat at Y:$33FF8 / $3BFF8 (the last $202 words of each half, measured by
SIDECHAIN_COMPRESSOR as never written by stock code); the demand loader's
window code (DLCOPY from 0x33DC3) now stops payload A's boot zero loop below
them, so they moved. The ledger refuses dB666 beside SIDECHAIN_COMPRESSOR
(the same hook site).

Beside the demand loader (29 Oct 2026, read from the build report of
`octabam` on main bc14452): the highest window words in use are TRANSIENT's
home in the fourth block (to P:0x3FF65) and LOAD METER's B half in the
second (to P:0x37EF7), with its figures at X:$37F10–$37F2F; the bus words
at +$3FF8 of the second and fourth blocks are clear of every home. A
14-effect remix could carry dB666's code in the window as well; that
placement is not made here.

## Measured

✅ in a standalone DSP56300 harness (garbage in every register and state
slot; the tap run for all eight tracks before every block, both payloads'
variants), 11 Oct 2026:

- **Bit-exact** against `db666_ref.fixed()`, tap included: defaults, every
  knob at its ends, OverEasy, KEY from T1 (payload B's half) and T7
  (payload A's), KEY out of range, a split block, LFO-dirty page words, the
  other seven tracks carrying a loud square (a wrong word ducks).
- **The manual**: attack to 63 % of the reduction 15.8 / 6.7 / 2.8 ms for
  10 / 20 / 30 dB over threshold at infinity:1 (the manual: 15 / 5 / 3 ms);
  release 123 dB/s (125).
- **Ratios** on a tone 10 dB over threshold: 2:1 → +5.04 dB, 4:1 → +2.56,
  120:1 → +0.08, −1:1 → −10.00.
- **KEY**: a −6 dBFS word on T1 ducks a −30 dBFS tone by −18.63 dB, the float
  law's figure exactly; an empty word does nothing.
- Below threshold at OUT 0 dB, and at MIX 0, the output is the input exactly;
  silence comes out as zeros.
- **Cost**: 297 words of code (the tap's ~20 included) + 66 words of table;
  160 cycles per sample by the pricer, plus the tap.

## How it differs from COMPRESSOR and SIDECHAIN_COMPRESSOR

CONTRIBUTING.md asks a module that overlaps an accepted one to say what
differs. Stock COMPRESSOR, and SIDECHAIN_COMPRESSOR on top of it, is a
compressor with ATTACK and RELEASE knobs; dB666 models one particular unit
whose character is that it has neither.

| | COMPRESSOR / SIDECHAIN_COMPRESSOR | dB666 |
|---|---|---|
| method | stock's compressor (a detector with ATTACK and RELEASE knobs, RMS on page 2) | the 160's true-RMS detector: one time constant, 34.7 ms, from the manual's 125 dB/s; attack and release follow the program (measured above: 15.8 / 6.7 / 2.8 ms at 10 / 20 / 30 dB over) |
| ratio | stock's range | 1:1 … 120:1 (the 160's "infinity") and on to −1:1 (the 160A's negative compression) |
| knee | stock's | HARD (the 160) or OVER (the 160A's OverEasy) |
| parallel | MIX | MIX, with 0 an exact passthrough |
| key | SIDECHAIN_COMPRESSOR: T1–T8 as audio, a base-width key filter (KBAS, KWID), key gain, a key listen (MON) | T1–T8 as a level: one mean-square word per track per block over a bus, about 11 cycles a sample per core for all eight; no filter, no listen (the 160's detector takes a level, not audio) |
| knobs | 6 on page 1 + RMS and 5 key controls on page 2 | 5 on page 1 (THRS RATI OUT KEY MIX) + KNEE |
| in one image | — | not with SIDECHAIN_COMPRESSOR (the same dispatcher hook, `conflicts`); beside stock COMPRESSOR, yes |
| cost on a unit | COMPRESSOR 2.18 % a slot (COSTS.md); SIDECHAIN_COMPRESSOR not read | not read yet (see "Open") |

In short: COMPRESSOR is the tool to shape a transient by hand; dB666 is
a "set threshold and ratio and play" compressor with a sound of its own,
and a pump from the kick in two knobs (KEY, THRS).

## On the unit

✅ The owner's MKI, remix `acidtrack`, on EQUALIZER's id, from 11 Oct 2026
(first flash) to image ACIDV81 (28 Oct 2026): the side-chain ducking heard
clearly from the first flash (KEY on the kick), then hours of live use beside
OCTA303, dEVILish, DISTORX and, from ACIDV79, AtoMizer (demand-loaded into
T8's FX2 slot at +$1000, below the bus words at +$3FF8). `make check
REMIX=acidtrack` (the tap inside the real dispatcher, under the ColdFire
port) passed on the owner's tree. By ear only: no measurement of the ducking
on the unit.

⏳ On its own id (this form, `remixes/test/db666`): not yet flashed. The DSP
code is unchanged by the id; what moves is the dispatch row.

## Open

- Its slot cost on a unit (LOAD METER, defaults and `dear`), and the tap's.
- A recording of the ducking on the unit, against the model's attack and
  release.
- Instruction forms without a stock site (`verify_db666` lists them).
- OverEasy's real width; the 160A's own curves are not published.

## Gates

`tools/verify/verify_db666.py`: generated source, bit-exact on eight
settings (the bus planted with `-pokey`), the passthroughs, the manual's
attack and release, the ratios, the key, silence, every knob.

## Files

| file | what |
|---|---|
| `manifest.py` | the module, the hook, the bus words, every constant |
| `db666.tmpl.asm` | the DSP code with `@NAME@` constants (`@COREBASE@`, `@SBASE@` per payload) |
| `generate_asm.py` | writes `db666.asm`; `--check` |
| `db666_ref.py` | the 160 in float (`DB666`) and the module bit for bit (`fixed`, `tap`) |

## Sources

- dbx 160/161 manual and schematic (dbx Inc., c. 1976): the controls, the
  specifications (attack, ratio 1:1–120:1, threshold 10 mV–3 V), Figs. 4–5.
- dbx 160A cut sheet (Harman): release 125 dB/s, −1:1, OverEasy.
- D. E. Blackmer, US 3,681,618, printed on the schematic: the RMS
  detector.
- Zac-Kyoti, SIDECHAIN_COMPRESSOR (MIT): the dispatcher hook site and the
  shared-window region, measured on an MKI.
