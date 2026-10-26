# `pextprobe` -- PEXT PROBE

A measurement instrument: where can a DSP core keep code besides its stock P
memory? Hot reload (the proof of concept on the hot-reload branch) needs a
pool for swapped effects. `DSP.md` section 3 records `P:0x2000` as executable
(a relocated CHORUS ran on the unit, `P:0x2000..0x2148`) and the upper bound
as unmeasured; the stock boot code also runs from the shared window
(`P:0x30000`, `P:0x38000`). It ships in no remix but `remixes/test/pext-probe`.

It is an insert on EQUALIZER's id (every id 4..31 is taken). Its output replaces
its track's audio with a status word, 32 bits a frame, one per sample slot, and
a capture of the track's audio reads it with `decode.py`. `pextprobe.asm` is
written by `gen_pextprobe.py` (the rungs are the same code at different
addresses).

## Results, 25 Oct 2026 (on the unit, run by the hardware session; T1 = core 1, T5 = core 0)

- **First version (image P1), project MXPEXT01:** seven rungs at `P:0x3fe0, 0x5fe0 ... 0xffe0`
  (each congruent to the spare base `0x1fe0` modulo `0x2000`), both cores: every rung ABSENT,
  no alias, no freeze. Without a control it could not tell "P ends below `0x3fe0`" from
  "the register-indirect P store does not work".
- **This version (image P2), project MXPEXT_03_01:**
  - LOW, core 1, two runs: rung 0 (the control, `P:0x1fe0`) REAL, so the store works; rungs 1..6
    (`P:0x2000, 0x2100, 0x2400, 0x2800, 0x3000, 0x3800`) ABSENT. Core 0, one clean run:
    the same, control REAL and the six rungs ABSENT. P ends at `P:0x1fff` on both cores; with
    the first version's rungs, nothing above it answers on either core.
  - WIN, core 1 and core 0, clean runs: seven of seven rungs read/write and EXECUTE
    (`P:0x30100, 0x35900, 0x36300, 0x36800, 0x37000, 0x37800, 0x37e00`), no freeze. Core 1
    ran code written into payload A's half of the shared window.

### Known issues (not fixed here)

- GO passes through LOW on the way to WIN, even for one CC jump (about 150 frames at GO 1):
  the WIN ladder then starts at rung 2. Stamp GO in the Part (slot 0) and select it with a
  program change, as the hardware session did.
- `decode.py` labels a capture by its last frame with GO on, so a capture where GO returns to
  OFF through LOW reads as LOW, with the WIN masks decoded as LOW's. Decode a capture in which
  GO goes from OFF to one value and back, or split it.

## The two ladders

GO is a select: OFF, LOW, WIN. Seven rungs, one every 64 frames (23 ms) after
64 idle frames. Turning GO to OFF starts the ladder over.

| GO | rungs | what a rung does | codes |
|---|---|---|---|
| LOW | `P:0x1fe0` (a control: spare words on both payloads, known real), `0x2000`, `0x2100`, `0x2400`, `0x2800`, `0x3000`, `0x3800` | reads the address and the address `0x2000` below it: equal and non-zero is a wrap onto live code and nothing is written; otherwise writes a pattern, reads it back, puts the old word back | 1 REAL, 2 ALIAS, 3 ABSENT |
| WIN | `P:0x30100, 0x35900, 0x36300, 0x36800, 0x37000, 0x37800, 0x37e00` | writes the pattern and reads it back; then writes a three-word routine (`move #>$a5a5a5,x0` / `rts`), calls it and reads x0; then zeroes the three words | 1 read/write only, 2 read/write and EXECUTE, 3 read/write failed |

If LOW's rung 0 is not REAL, the store does not work and nothing else in LOW
means anything. A call that freezes the core leaves its rung in the last frame.

The WIN addresses are the words the bus remix leaves free in payload A's half of the shared
window, from `Claims.dsp_ranges` (`tools/remix/dsp_ranges.py`): BusVerb takes
`0x30800..0x35800`, the bus scratch `0x36000..0x36200`, stock's staging
`0x30000..0x30048`, the mailbox `0x37f00`, the LOAD METER's figures
`0x37f10..0x37f50`; free: `0x30048..0x30800` (1,976 words), `0x35800..0x36000`
(2,048), `0x36200..0x37f00` (7,424). Payload B's half is BusDelay's LineL
(`0x38000..0x40000`). The window is one memory for both cores, so both
instances use the same words: run one core at a time.

Under `dsp_host` every rung passes (the emulator maps P at all of them), so
`tools/verify/verify_pextprobe.py` proves the instrument, the decoder and the
routine a WIN rung writes and calls, not the hardware's answer;
`tools/verify/tests/test_pextprobe.py` covers the outcomes the emulator cannot
produce (ALIAS, ABSENT, a frozen core, a silent capture). Forms the chip has
not run: a P store through `(r1)` and `jsr (r5)` (the stock listing has
absolute P stores and `jsr` to an address).

## Running it on a unit

1. `make image REMIX=pext-probe BUILD=<n>`, flash it (`docs/guide/BUILDING.md`).
   The remix carries USB audio out, TRACKS PRE (16 channels, the tracks).
2. A project with FX1 = PEXT PROBE (EQUALIZER's id, 12) on T1 and T5, GO OFF.
   Each instance tests its own core.
3. Start a capture of the USB audio, all channels, 44.1 kHz, sample exact
   (T1 is channels 0, 1 and T5 is channels 8, 9).
4. Decode the pairs (`python3 modules/pextprobe/decode.py t1.raw`, `--channels`
   for a `.wav`). Expected before GO: the marker in every frame, GO 0, next rung 0.
   No marker: the probe is not on that pair.
5. With the capture running: set GO to LOW on one track, wait 10 s; set it back
   to OFF; then WIN on the same track; then OFF; then the other track the same way.
6. If frames stop arriving, the core froze on the rung the decoder names:
   power-cycle the unit (no reflash).

The probe writes nowhere a running payload reads except the rungs themselves: a
LOW rung that wraps onto live code is detected before it writes, and the WIN
words are free in the bus remix; the probe remix itself keeps no bus.

## Files

`pextprobe.asm` (written by `gen_pextprobe.py`), `manifest.py`, `decode.py`,
and [`remixes/test/pext-probe`](../../remixes/test/pext-probe/README.md).
