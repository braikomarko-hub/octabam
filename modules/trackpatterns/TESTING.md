# TRACK PATTERNS testing

## Host gate (21 Oct 2026)

`python3 verify.py` on macOS (Apple clang, Homebrew python 3.12,
m68k-elf-gcc 16.2.0): both host suites pass, and the ColdFire unit compiles
and assembles for the 5475 with no calls outside it.

What the suites cover:

- A zeroed state follows the global pattern on every track.
- A queued change lands exactly at the track's own loop start, for lengths
  1–64, with the rest of the pass still on the old pattern.
- The global pattern's trig queues the way back to following; asking for
  what the track already plays withdraws a queued change.
- A global pattern change clears every override and every queued change;
  the same global pattern seen again changes nothing.
- While stopped, a change applies at once and PLAY plays it from step 1.
- The look-ahead names what then plays, across the loop end and after a
  queue (as the key stub has stock rebuild its steps).
- PLAY restarts land a queued change on step 1; the repeated step of a
  MASTER LENGTH restart is a loop start too.
- MIDI tracks (8–15), the popup text (`T5 > A03`, `M2 FOLLOWS`, the bank
  letter), out-of-range tracks and patterns.
- The adapter on fake sequencer memory: transport, playing bank and
  pattern, length source following the track.
- A bank change to the same pattern number (A10 → B10) clears the
  overrides, and the step stock prepares across it is B10's on every track;
  P16 is a pattern like any other.
- The gesture on fake key memory: no TRACK key held leaves the press to
  stock; TRACK 2 held (state 2, as once the PATTERN layer opened over it)
  queues for T2 with the toast `T2 > B05`; the lowest held TRACK key wins;
  MIDI mode addresses M5, not T5; the global pattern's trig makes the track
  follow again; a key past TRACK 8 is not a TRACK key.
- The trig LEDs on fake LED, UI and timer memory: a following track and
  other pages are left as stock drew them; GRID REC's dark half puts only
  the 32 trig LEDs out and names the running light's track (M4 in MIDI
  mode); the playhead is relit only on the page GRID REC shows; outside
  GRID REC the playing pattern's trigs go over stock's running light, page
  2 included, and not in CHROMATIC; MIDI tracks read the MIDI record; the
  PATTERN layer with TRACK 1 held lights T1's pattern, its queued change
  and the global pattern as one with content. Planted defects fail them
  (inverted blink, 6 failures; a key off by one, 3; no running light
  redraw, 2; overwriting stock's LEDs, 3; the page check dropped, 1).

Planted defects fail them: a loop-start test that ignores the repeated step
(5 engine failures), a global change that no longer clears (2 adapter, 9
engine failures).

The hand-written entries in `hooks.s` were disassembled after assembly and
read as written.

## ColdFire port (21 Oct 2026)

Image: native remix `trackpatterns-test` (TRACK PATTERNS + the 14 stock
effects) built in a Modwerk worktree at `c0f513b9` with `make bus`; the six
sites carry their jumps (the rebuild spans padded with `nop`). Emulator
`ot_emu` from the same tree. Project: a copy of the contributor's own,
clock and transport receive off, bank A with `ot_spec.py`: A01 T1 trigs on
steps 1, 5, 9, 13; A03 T1 on 3, 7, 11, 15; both 16 steps at 1X. Script:
NO (the date popup), PLAY, at 4 s a poke of T1's queue (`next[0] = 3`, A03;
no key gesture yet), STOP at 9 s. Watched: T1's counter `0x800064d0`, the
step handler's per-track trig entry `0x46c7a810` (a plain trig writes
`0x1d` at `0x4009d42a`) and `tp_state`.

| | result |
|---|---|
| T1's plain trigs before the change | steps 5, 9, 13, 1, 5, 9, 13 (A01) |
| the queue lands | at 15.97 s, the step T1's counter wraps to step 1: `src[T1] = A03`, `next` cleared |
| T1's plain trigs after it | steps 3, 7, 11, 15, round after round (A03), the global pattern still A01 |

Port evidence only, one track, queued by a poke.

## Gesture, MIDI track, global change (21 Oct 2026)

**Stock first.** On the image above (no gesture site yet, so the keys are
stock): hold TRACK 1, hold PATTERN, press TRIG 3 while playing. Stock
queued A03 for every track (`0x800065c0 <- 2` at `0x400a06dc`) and played
it at the pattern's end. TRACK 1's key state (`0x46c7d8ee + 24 * 0x10`)
went 1 on the press (pc `0x40031936`), then 2 when the PATTERN layer opened
over it (`0x400312e8`), and 0 on the release (`0x4003180c`). So the
combination has no meaning of its own in stock, and the trig still reaches
the PATTERN layer's handler with the TRACK key still marked as held.

**Image:** the same remix rebuilt with the seventh detour (`0x40056b50 ->
tp_pattern_key`) and the bank-aware tick. `tp_state` at `0x40a95f2c`.

**Project** `STEPTPM`: a copy of `STEPTP` plus A02 T1 trigs on 2 and 10
(`ot_spec.py`), and M1's trig mask written into the bank file's MTRA
records (tag + 9, as the TRAC records): A01 M1 on 1 and 9, A03 M1 on 5 and
13. `.work` and `.strd` checksummed and read back.

**Script:** NO, PLAY; at 3 s hold TRACK 1, hold PATTERN, TRIG 3; at 5 s the
MIDI key (MIDI mode), then the same gesture; at 6.8 s the MIDI key again; at
10 s PATTERN + TRIG 2 with no TRACK key held; STOP at 14 s. Watched: the
playing and queued pattern, `0x80000012`, `src`/`next` of T1 and M1, the
engine's global id, the per-track trig entry `0x46c7a810[0]` (a plain trig
writes `0x1d`: at `0x4009d42a` for T1, at `0x4009d0fc` in the MIDI step
handler for M1), the counters `0x800064d0` and `0x800064d8`.

| | result |
|---|---|
| before any change | T1 on steps 1, 5, 9, 13 and M1 on 1, 9 (A01) |
| TRACK 1 + PATTERN + TRIG 3 | `next[T1] = A03` (15.31 s); no global queue written; the toast reads `T1 ▸ A03` over the A01 screen (the display draws `>` as ▸) |
| T1's loop start | `src[T1] = A03` at 15.97 s; then T1 on 3, 7, 11, 15 round after round; M1 still on 1, 9 |
| MIDI mode, the same gesture | `0x80000012 = 1`; `next[M1] = A03` (17.81 s), T1 untouched |
| M1's loop start | `src[M1] = A03` at 19.13 s; then M1 on 5, 13; T1 still on A03 |
| PATTERN + TRIG 2, no TRACK held | stock's global queue (`0x800065c0 = 1`, 22.11 s); A02 plays at 22.27 s; at the next step the engine clears `src` and `next` of T1 and M1 and records A02 |
| after the global change | T1 on 2, 10 (A02's); M1 silent (A02 has no M1 trigs); no stray A03 step at the change |

Not run yet: MIDI out notes (M1 has no channel in the project copy, so
UART0 carried MIDI clock only) and note-offs across a switch; a bank change
under the port (host-tested only); the latched PATTERN (a tap, then TRACK +
TRIG); TRACK pressed after PATTERN; the rebuild path (an edit while a track
is on another pattern); a different length per track; Play Modes built
alongside; cycle counts; any unit.

## Unit build 1 (21 Oct 2026)

`make image REMIX=trackpatterns-test BUILD=1` in the Modwerk scratch
worktree (`c0f513b9`), module source = this repository at `3c581df`, from
the contributor's own OS 1.40C (`.syx` `0a8d2d2b35c2…`, `.bin`
`34695b606eb0…`, Elektron's files). Version string `OCTABAM1`.

| file | SHA-256 |
|---|---|
| `OCTATRACK_OCTABAM1.bin` (card path) | `ec04c849fb85513ba3d9c3863af501233bb61e7edd3387c2cea598506cce2db4` |
| `OCTATRACK_OS1.40C_OCTABAM1.syx` (MIDI path) | `a54d8d1810a198c93f8368b0f151ce69678cd1432e41744b87cc5ced9adad9d0` |
| `mainos_bus.bin` (the OS section the emulator runs) | `906085659919a8b41394f7e4ce253258cccb52418a63d34d6a8555b5e6aa7849` |

The card file's checksum validates (`bin_decode.py`). The gesture run above
repeated on this exact `mainos_bus.bin` gives the same 72 events at the same
times, booted as an MKI (the emulator's default, as every run above) and
with `--mkii`.

### On the unit: MKII, 21 Oct 2026, reported by pgstath

Image `OCTABAM1` above, flashed from the card. Test project as in the plan:
bank A, T1 trigs A01 1/5/9/13, A02 2/10, A03 3/7/11/15; M1 trigs A01
1/9, A03 5/13; all 16 steps. Only what the contributor reported:

| # | test | result |
|---|---|---|
| 1 | stock PATTERN + TRIG 3 switches every track to A03 at the pattern's end | pass |
| 2 | hold TRACK 1, hold PATTERN, TRIG 3: popup `T1 ▸ A03`, screen stays A01, T1 switches at its own loop start | pass |
| 3 | TRACK 1 + PATTERN + TRIG 1: `T1 FOLLOWS`, T1 back on A01 at its loop start | pass |
| 4 | MIDI mode, M1 to A03; note-offs across the switch | not tested |
| 5 | with T1 on A03, PATTERN + TRIG 2 (no TRACK held): A02 at the pattern's end, T1 on A02's trigs | pass |
| 6 | the gesture while stopped, then PLAY | not tested |
| 7 | latched PATTERN, TRACK after PATTERN, chains, GRID REC | not tested |
| 8 | save, power cycle | not tested |

Not reported: how long it ran, other tracks, CPU load, cycles.

## Build 2: the trig LEDs (21 Oct 2026, emulator only)

`make image REMIX=trackpatterns-test BUILD=2`, same tree and OS; adds the
eighth detour `0x4007e9b6 -> tp_led_pass`. `tp_state` at `0x40a96304`.

| file | SHA-256 |
|---|---|
| `OCTATRACK_OCTABAM2.bin` | `53ccd9fe47002bc4a387a1bc343d77fc6f75f5bc5953172d6a45d7c041aa4ef3` |
| `OCTATRACK_OS1.40C_OCTABAM2.syx` | `f4ed7ea63a741b9818e13b4e623ec0c06e61e1520e6c0c7cf1f0aa957dda1ee2` |
| `mainos_bus.bin` | `56372a524128051a1eb5210a97a1cc678b1b03689a4867e47145a2afa3e03851` |

**Stock first** (`STEPTPM`, playing A01): outside GRID REC the trig keys
show only the running light (both LEDs of the playhead's key, moving every
100 ms at 152 BPM); GRID REC shows A01's T1 trigs on keys 1, 5, 9, 13 (first
LEDs) plus second LEDs the project's own data sets; with PATTERN held, A01's
key lights its first LED and A02, A03 their second (patterns with content).

**Run** (`--mkii`, then the same as an MKI): play; the gesture puts T1 on
A03 (lands at 15.97 s); 3 s later GRID REC on for 2 s, off; then TRACK 1 +
PATTERN held for 0.8 s. Watched: the trig LED bytes `0x460ba98c..f` (state
rebuilt every 50 ms), `src[T1]`, GRID REC, PATTERN held.

| | result |
|---|---|
| T1 on A03, outside GRID REC | A03's trigs (LEDs 4, 12, 20, 28: keys 3, 7, 11, 15) on for about 500 ms, off for about 500 ms; the running light moves through both halves |
| T1 on A03, GRID REC | stock's A01 view for about 500 ms, then about 500 ms with only the running light, repeating |
| TRACK 1 + PATTERN held | LEDs 1, 3, 4: A03 (key 3) as the current pattern, A01 and A02 as patterns with content |
| MKI against MKII | the same LED timeline (event times within 1 ms) |
| the gesture run of build 1, repeated (`--mkii`) | the same 72 events and values in the same order, trigs at the same times; the overrides clear 20 ms earlier at the global change (22.27 s, not 22.29 s), because the LED pass now notices the new pattern first |

Not run under the emulator: MIDI mode's LEDs (host-tested only), patterns
longer than 16 steps, the cycle cost of the LED pass.

### On the unit: MKII, 21 Oct 2026, reported by pgstath

Image `OCTABAM2` above (`53ccd9fe…`), the test project and steps as for
build 1, plus the four LED checks. The contributor reported every test
below as passed; nothing more detailed was reported.

| # | test | result |
|---|---|---|
| 1 | stock PATTERN + TRIG 3 switches every track to A03 at the pattern's end | pass |
| 2 | hold TRACK 1, hold PATTERN, TRIG 3: popup `T1 ▸ A03`, screen stays A01, T1 switches at its own loop start | pass |
| 3 | TRACK 1 + PATTERN + TRIG 1: `T1 FOLLOWS`, T1 back on A01 at its loop start | pass |
| 4 | MIDI mode, TRACK 1 + PATTERN + TRIG 3: `M1 ▸ A03`, M1's notes move from 1, 9 to 5, 13 at its loop start, no hanging note across the switch | pass |
| 5 | with T1 on A03, PATTERN + TRIG 2 (no TRACK held): A02 at the pattern's end, T1 on A02's trigs | pass |
| 6 | the gesture while stopped, then PLAY: T1 plays A03 from step 1 | pass |
| 7 | a tapped (latched) PATTERN then TRACK + TRIG, TRACK pressed after PATTERN, a chain (PATTERN + two trigs), GRID REC editing | pass |
| 8 | save, power cycle: the project intact, every track following the global pattern again | pass |
| L1 | T1 on A03, outside GRID REC: A03's trigs blink about once a second, the playhead keeps moving | pass |
| L2 | GRID REC: A01's trigs blink | pass |
| L3 | hold TRACK 1 + PATTERN: A03's key lit as the current pattern | pass |

Not reported: how long it ran, which colour each LED of a pair shows,
other tracks than T1 and M1, CPU load, cycles.

## Build 3: from this tree (21 Oct 2026)

`make image REMIX=trackpatterns BUILD=3` in octabam at `828edcac` with this
module (branch `trackpatterns`), from the contributor's own OS 1.40C (MAIN
OS section `164f3122…`). The eight detours land on the same addresses as
build 2; `tp_state` at `0x40a96304`. The card file's checksum validates.

| file | SHA-256 |
|---|---|
| `OCTATRACK_OCTABAM3.bin` | `a3712dbb2cbefb26895ed42255f5e6e3809379a85bc8297516c5370398200569` |
| `OCTATRACK_OS1.40C_OCTABAM3.syx` | `bc205ce0868578a672939137ff147ebb9bbd17b4eacaa0e1c30fcd6752875ee0` |
| `mainos_bus.bin` | `70b0e299869f576525b33a753d0b5c434ebf789fde08ca68aa1ed7f50e90545c` |

Under this tree's `ot_emu --mkii`, the gesture run and the LED run of build
2 repeated on this exact image: the same 72 events and values in the same
order, every event about 30 ms later (the load ends later); the LEDs as
build 2's (A03's trigs blinking about 500 ms on, 500 ms off outside GRID
REC, A01's in GRID REC, the running light kept; TRACK 1 + PATTERN lighting
LEDs 1, 3, 4).

### On the unit: MKII, 21 Oct 2026, reported by pgstath

Image `OCTABAM3` above (`a3712dbb…`), flashed after build 2's tests, with
the same test project and steps. The contributor reported every test below
as passed; nothing more detailed was reported.

| # | test | result |
|---|---|---|
| 1 | stock PATTERN + TRIG 3 switches every track to A03 at the pattern's end | pass |
| 2 | hold TRACK 1, hold PATTERN, TRIG 3: popup `T1 ▸ A03`, screen stays A01, T1 switches at its own loop start | pass |
| 3 | TRACK 1 + PATTERN + TRIG 1: `T1 FOLLOWS`, T1 back on A01 at its loop start | pass |
| 4 | MIDI mode, TRACK 1 + PATTERN + TRIG 3: `M1 ▸ A03`, M1's notes move from 1, 9 to 5, 13 at its loop start, no hanging note across the switch | pass |
| 5 | with T1 on A03, PATTERN + TRIG 2 (no TRACK held): A02 at the pattern's end, T1 on A02's trigs | pass |
| 6 | the gesture while stopped, then PLAY: T1 plays A03 from step 1 | pass |
| 7 | a tapped (latched) PATTERN then TRACK + TRIG, TRACK pressed after PATTERN, a chain (PATTERN + two trigs), GRID REC editing | pass |
| 8 | save, power cycle: the project intact, every track following the global pattern again | pass |
| L1 | T1 on A03, outside GRID REC: A03's trigs blink about once a second, the playhead keeps moving | pass |
| L2 | GRID REC: A01's trigs blink | pass |
| L3 | hold TRACK 1 + PATTERN: A03's key lit as the current pattern | pass |

Not reported: how long it ran, which colour each LED of a pair shows,
other tracks than T1 and M1, CPU load, cycles.

## Review round 1 (22 Oct 2026, emulator)

After the maintainer's review of `02d69e57`, on `4ba865a1` (main merged).

**Cost.** `ot_emu --mkii`, this build, the gesture, MIDI and global-change
script (`STEPTPM`); `--watch-pc` on each detour's entry and on the stock
instruction it returns to; the instruction count between the two, per
call (the replayed stock instructions included):

| detour | calls | min | median | 99th pct | max |
|---|---|---|---|---|---|
| audio tick | 1,096 | 85 | 86 | 89 | 95 |
| MIDI tick | 1,096 | 88 | 89 | 92 | 98 |
| audio advance | 1,088 | 60 | 60 | 84 | 186 |
| MIDI advance | 1,088 | 60 | 60 | 84 | 84 |
| the LED pass's own part (`0x40a962d2` to `0x4007e9bc`, the LED script) | 572 | 52 | 52 | 658 | 658 |

Memory: the build report's 3,457 B code + data, 0 B `.bss`; stack frames
from `-fstack-usage` (`tp_leds` 48 B, `tp_key` 24 B, `tp_seq_pattern` 20 B;
the tick's chain about 72 B below its caller).

**Beside KITS and DIRECT_JUMP_KYOTI.** `remixes/test/trackpatterns-core`
(`octabam-core` + TRACK PATTERNS) builds; the ledger reports no conflict.
The gesture, MIDI and global-change run: the same 72 events and values in
the same order as build 3. The LED run, anchored to its own events (the
image's load ends about 1.7 s later): A03's trigs blinking outside GRID
REC, A01's in GRID REC, TRACK 1 + PATTERN lighting LEDs 1, 3, 4, as build 3.

**Patterns over 16 steps.** A03 at 32 steps, T1 trigs 3, 7, 11, 15, 19, 23,
27, 31 (`STEPTP32`), T1 switched by the gesture:

| A01 (global) | T1's loop on A03 |
|---|---|
| SCALE MODE NORMAL, length 16 | wraps at 16; steps 3, 7, 11, 15 only |
| PER TRACK, MASTER LENGTH 16 | wraps at 16 (the master length restarts every track) |
| PER TRACK, MASTER LENGTH 32 | wraps at 32: 3, 7, ... 31; T2 (A01) still at 16 |

The trig LEDs then showed GRID REC's page, not the playhead's: fixed in
`adapter.c` (the page of the track's step counter), with a host test. With
A03's T1 on 3, 7, 11, 15, 18, 22 (`STEPTP32Q`), the rows sent to the panel
(`0x460ba99d`) showed keys 3, 7, 11, 15 while T1 played steps 1-16 and keys
2, 6 while it played 17-32, blinking.

**Other trig modes.** T1 on A03, then the trig mode written to CHROMATIC
(`poke 0x460d16f3=1`, not the panel's keys): no trig LED row changed after
it, with this build and with the build without the LED pass alike.

Not run: any of this on a unit.

## Build 8: beside KITS and DIRECT_JUMP_KYOTI (22 Oct 2026)

`make image REMIX=trackpatterns-core BUILD=8` in octabam at `f1eb1507`,
from the contributor's own OS 1.40C; rebuilt at `05d8701c` (main merged),
the card file is byte-identical.

| file | SHA-256 |
|---|---|
| `OCTATRACK_OCTABAM8.bin` | `2a698188558cf31b7d9c30b0cc978ec97bdcbb5da654e67347ddb272c41c9458` |
| `OCTATRACK_OS1.40C_OCTABAM8.syx` | `4b38d1aaf72b7a2cc25f8ce9303fe1dcee687e08384375b6225d47e0aab1a403` |

### On the unit: MKII, 22 Oct 2026, reported by pgstath

Image `OCTABAM8` above (`2a698188…`), the test project of build 3, A01
playing. The contributor reported 1a to 1d as passed and skipped 1e;
nothing more detailed was reported.

| # | test | result |
|---|---|---|
| 1a | hold TRACK 1, hold PATTERN, TRIG 3: popup `T1 ▸ A03`, T1 switches at its own loop start, the other tracks stay on A01 | pass |
| 1b | MIDI mode, TRACK 1 + PATTERN + TRIG 3: M1 switches to A03 at its loop start, no hanging note | pass |
| 1c | PATTERN + TRIG 2 (no TRACK held): A02 at the pattern's end, T1 and M1 included | pass |
| 1d | T1 on A03, SAVE PROJECT, power cycle, reload: the patterns unchanged, every track following the global pattern | pass |
| 1e | a KITS action and a DIRECT JUMP action of their own | not tried |

Not reported: how long it ran, other tracks than T1 and M1, the trig LEDs.

## CF METER with and without the module (22 Oct 2026)

Two images from `05d8701c`, made from local probe remixes that are not in
the tree. Both have USB (TRACKS PRE, MAIN 1, CUE 1, MASTER 0, IN OFF), CF
METER, CF METER IDLE and the stock effects except DARK REV, which gives up
its words to the meter:

- `OCTABAM10`: TRACK PATTERNS and the modules above.
- `OCTABAM11`: the same without TRACK PATTERNS.

| file | SHA-256 |
|---|---|
| `OCTATRACK_OCTABAM10.bin` | `2bab0a39c9019b020e0f190330354fd85ed0136ccb2042847d04be887fcfd382` |
| `OCTATRACK_OS1.40C_OCTABAM10.syx` | `bf715b8761f4498a736ce7d8075b560024d4b5da52a549f823d05af5bfd4b21a` |
| `OCTATRACK_OCTABAM11.bin` | `90fa968b70ae07cc81376b082f38c03b0e05a8f84778ee03a532d3c84379c916` |
| `OCTATRACK_OS1.40C_OCTABAM11.syx` | `75511ebe723d795ae3599f501fff5106b1f84a007d2938223fbbfcfefe83814c` |

### On the unit: MKII, 22 Oct 2026, workload reported by pgstath

T8 FX2 was CF METER with BURN, MEM and DBRN at 0. T8's USB channels 15/16
were recorded on a Mac for 120 s per take (the recorder of `tools/hw/rec`)
and decoded with `tools/harness/cfmeter.py`. Each take gives 59 cycles of
2 s.

The contributor's workload, the same in every take: 300 BPM; a trig on
every step of T1–T7 and M1–M8 in A01; A02 and A03 copies of A01; T8 left
as the readout.

| take | image | what played | idle %, mean (sd) | frame interrupt, median mean | its longest, median / worst | TUE / ROE |
|---|---|---|---|---|---|---|
| 3a | OCTABAM11 | A01, untouched | 17.58 (2.94) | 244.6 µs | 292.7 / 326.4 µs | 0 / 0 |
| 3b | OCTABAM10 | A01, every track following | 17.78 (2.88) | 244.3 µs | 293.9 / 328.2 µs | 0 / 0 |
| 3c | OCTABAM10 | T1–T4 and M1–M4 on A02 / A03 by the gesture, T1 current outside GRID REC (the LED pass drawing), a few gestures during the take | 16.10 (3.74) | 244.4 µs | 297.3 / 336.2 µs | 0 / 0 |

Every take has a frame period of 362.8 µs and 5,520 DSP frames in every
2 s window.

- **3b against 3a.** With the module loaded and every track following,
  idle is 0.19 points higher (0.4 standard errors) and the frame interrupt
  is the same: no difference within the noise.
- **3c against 3a.**
  - With eight tracks on their own patterns, the LED pass and gestures,
    idle is 1.49 points lower (2.4 standard errors). That is about 5.4 µs
    of each 362.8 µs frame.
  - The frame interrupt's mean is unchanged (245.1 against 245.9 µs over
    all cycles), so the extra work is outside the interrupt (inferred).
  - The interrupt's worst run is 336.2 µs against 326.4 µs, 26.6 µs under
    the frame.
  - 3a had no key presses. Part of the difference is 3c's gestures, popups
    and MIDI-mode switches, not separated from the module's own work.
- **The DSP period.** In 3c's median row it ranges 356.6–370.7 µs, against
  361.1–364.2 µs in 3a and 3b. There is no underrun or overrun.

Not reported: whether the overrides in 3c sounded as expected.

## Build 9: over 16 steps and other trig modes (22 Oct 2026)

`make image REMIX=trackpatterns BUILD=9` in octabam at `f1eb1507`. Rebuilt
at `05d8701c`, the card file is byte-identical.

| file | SHA-256 |
|---|---|
| `OCTATRACK_OCTABAM9.bin` | `4fb7b88903d21f5ea90f524978c14a0d79e063cd986c0c9dbc93d406eb16d2e7` |
| `OCTATRACK_OS1.40C_OCTABAM9.syx` | `b382bfdcfdc7e40b81a1af816589634394ba59011a496eb6326002b92267d337` |

### On the unit: MKII, 22 Oct 2026, reported by pgstath

Image `OCTABAM9` above, with the test sheet's setup:
- A04: T1 at 32 steps, with different trigs on steps 1–16 and 17–32.
- A01: SCALE MODE PER TRACK, MASTER LENGTH 32 or more, T1 at 16 steps.

The contributor reported the 32-step pattern and the other trig modes as
working as expected; nothing more detailed was reported.

| # | test | expected | result |
|---|---|---|---|
| 2a | A01 playing, T1 on A04 by the gesture, T1 current, outside GRID REC | T1 plays all 32 steps; the trig keys blink A04's steps 1–16 while the playhead is on 1–16 and 17–32's while it is on 17–32; the running light kept | as expected |
| 2d | the same, switched to each other trig mode, CHROMATIC included, then back to TRACKS | the module draws no trig LED there; the blink returns in TRACKS | as expected |
| 2b | MASTER LENGTH 16 on A01 | T1 restarts after 16 | not reported separately |
| 2c | SCALE MODE NORMAL on A01 | T1 wraps at A01's length | not reported separately |
| 2e | GRID REC in a 32-step pattern, page 2 | the stock trigs blink as the warning | not reported separately |

## Not yet

On the unit: a long run, more tracks at once. Anywhere: the track's speed
from its own pattern, persistence, chip cycles per detour.
