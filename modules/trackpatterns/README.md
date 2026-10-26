# `trackpatterns` -- TRACK PATTERNS

Each of the 16 tracks (T1–T8, M1–M8) can play its own pattern of the playing
bank, clip style, as on the Korg SQ-64. Hold [TRACK n], hold [PATTERN], press
[TRIG k]: track n plays pattern k from the end of its own loop, in time, while
every other track and the global pattern carry on. The sound stays the
playing Part's.

By pgstath (MIT, as octabam). Source also at
[pgstath/TrackPatterns](https://github.com/pgstath/TrackPatterns). `Kind.CF_PATCH`:
one DRAM unit (`trackpatterns.s`, generated from `trackpattern.c`,
`adapter.c` and `hooks.s` by `generate.py`) and eight detours. A remix with
this module carries the platform loader and its 10 MiB arena reserve, unless
another DRAM module already brings them.

## What it does

| Situation | Behaviour |
| --- | --- |
| Pick a track's pattern | Hold [TRACK n], hold [PATTERN], press [TRIG k]; a popup names it (`T1 > A03`). MIDI mode addresses M1–M8 |
| When it lands | At the end of that track's own loop; while stopped, at once |
| Back to normal | The global pattern's trig for that track (`T1 FOLLOWS`), or any global pattern change, a bank change included, which clears every override |
| Length | Under SCALE MODE PER TRACK a track on another pattern loops at its own length there, inside the global pattern's MASTER LENGTH, which still restarts every track. Under NORMAL every track wraps at the global pattern's length, so a longer pattern's later steps are not played |
| Sound design, tempo, speed | The playing Part; the playing pattern's tempo and track speed |
| Trig LEDs | For the current track on its own pattern: outside GRID REC (TRACKS trig mode), where stock shows only the running light, that pattern's trigs blink slowly, from the 16 steps its playhead is in; in GRID REC the stock trigs (the global pattern the keys edit) blink as a warning. The running light stays. TRACK n + PATTERN lights the pattern T_n plays |
| Editing, recording | The global pattern, as stock |
| Saving | Not saved: after a reload or power cycle every track follows the global pattern |

## How

The tick hands each track's step to the step handler with a pattern
argument; TrackPatterns replaces it with the track's own and lands a queued
change when the track's stock step counter wraps. The rebuild after an edit
and the per-track advance's length compare follow the same choice. A track
with nothing set gets exactly what stock passes, and the step stock
prepares across a global or bank change follows stock.

| site | what |
|---|---|
| `0x400a2d76`, `0x400a39c0` | the tick's pattern argument, audio and MIDI |
| `0x4009dc8c`, `0x4009e3e2` | the rebuild after an edit (8 bytes, padded) |
| `0x400a3d88`, `0x400a3ea8` | the per-track advance: the length the counter wraps at |
| `0x40056b50` | the PATTERN layer's trig press: with a TRACK key held (the stock key-state table `0x46c7d8ee + 24·code`), the trig queues for that track, opens the toast and has stock prepare every track's step again |
| `0x4007e9b6` | the LED dispatcher `0x4007e998`, after a page's LED callback: the trig LEDs above |

`INVESTIGATION.md` has every address, where it came from and what was read
or measured, and names the stock instructions each detour displaces.

## Measured

- `modules/trackpatterns/verify.py` (the gate): the engine and the glue on
  the host, on fake firmware memory: a change landing at the track's own
  loop start for lengths 1–64, MASTER LENGTH's repeated step, PLAY
  restarts, the way back to following, global and bank changes clearing,
  the look-ahead, MIDI tracks, the popup text, the gesture and the trig
  LEDs. Planted defects fail it. With `m68k-elf-gcc` on the PATH it also
  checks that `trackpatterns.s` matches the C and assembles for the 5475.
- Under the ColdFire port (`ot_emu`, a project with distinct trigs on A01,
  A02 and A03 for T1 and M1): the gesture moved T1, then M1, from A01 to A03
  at each track's own loop start with no global queue written; the trig
  entries of the step handler followed; a global change to A02 cleared both;
  the trig LEDs blinked as above with the running light kept; the same as an
  MKI and as an MKII. `TESTING.md`.
- Beside KITS and DIRECT_JUMP_KYOTI: `remixes/test/trackpatterns-core`
  (`octabam-core` with TRACK PATTERNS) builds with no ledger conflict;
  under the port the gesture, MIDI and global-change run gives the same 72
  events as the module alone, and the LEDs behave the same.
- Patterns over 16 steps (port): T1 switched to a 32-step A03 played all
  32 steps with A01's MASTER LENGTH at 32 under PER TRACK, and stopped at 16
  with MASTER LENGTH 16 or under NORMAL (the length row above); the trig
  LEDs showed page 2's trigs while the playhead was on steps 17-32. In
  CHROMATIC (set by writing the mode, not by the keys) the module drew no
  trig LED, as the build without the LED pass.
- `make check REMIX=trackpatterns` (`remixes/test/trackpatterns/`).

## Cost

Measured under the ColdFire port (`ot_emu --mkii`, this build, a run with
changes landing on T1 and M1 and a global change clearing them): the
instructions from each detour's entry to the stock instruction it returns
to, the replayed stock instructions included. These are instruction counts,
exact for the inputs run, not chip cycles.

| detour | runs | instructions per call: median / 99th percentile / max |
|---|---|---|
| audio tick `0x400a2d76` | once per audio track per step | 86 / 89 / 95 |
| MIDI tick `0x400a39c0` | once per MIDI track per step | 89 / 92 / 98 |
| audio advance `0x400a3d88` | once per audio track per step | 60 / 84 / 186 |
| MIDI advance `0x400a3ea8` | once per MIDI track per step | 60 / 84 / 84 |

One step of all 16 tracks: about 2,360 instructions typical, 3,700 at the
largest counts seen. The stock instructions these sites replace are two or
three per call. The LED pass adds 52 instructions per pass with no track on
its own pattern, 658 at most. Memory: the DRAM unit is 3,457 bytes, code and
data with the 84-byte state (`tp_state`, `tp_toast`), no `.bss`, no heap,
no battery RAM, no DSP words; the deepest stack, the tick's, is about 72
bytes below its caller (`-fstack-usage`).

On a unit (MKII, CF METER, 300 BPM, a trig on every step of 15 tracks;
`TESTING.md`):
- With the module loaded and every track following, idle time and the
  frame interrupt match the build without it within the noise.
- With eight tracks on their own patterns, the LED pass and gestures, idle
  is 1.5 points lower, about 5.4 µs of each 362.8 µs frame. The frame
  interrupt's mean is unchanged, and no frame ran late.

## On the unit

- 21 Oct 2026, the contributor's MKII, image `OCTABAM3` built from this
  tree (`make image REMIX=trackpatterns BUILD=3`; hashes in `TESTING.md`):
  stock PATTERN + TRIG, the gesture on T1 and on M1, following again, a
  global change clearing, the stopped case, a latched PATTERN, chains, GRID
  REC, save and power cycle, and the three trig LED checks: all reported as
  passed. The same tests passed earlier that day on images built from this
  source in Modwerk's copy of octabam (`OCTABAM1`, `OCTABAM2`). Not reported:
  run length, LED colours, other tracks.
- 22 Oct 2026, the same MKII, image `OCTABAM8` (`make image
  REMIX=trackpatterns-core BUILD=8`, with KITS and DIRECT_JUMP_KYOTI;
  hashes in `TESTING.md`): the gesture on T1 and on M1, a global change, save
  and power cycle: reported as passed. KITS' and DIRECT JUMP's own actions
  were not tried on it.
- 22 Oct 2026, the same MKII, image `OCTABAM9` (`make image
  REMIX=trackpatterns BUILD=9`): T1 on a 32-step pattern under PER TRACK
  with MASTER LENGTH 32 played all 32 steps, with the trig LEDs following
  the playhead's page; in the other trig modes, CHROMATIC included, the
  module drew no trig LED: reported as working as expected.

## Inferred, open

- Chip cycles per detour are not measured (instruction counts above). The
  unit's load is measured as a whole (CF METER, above), and in 3c it is not
  separated from the gestures' UI work.
- KITS detours `0x40056b2c`, the entry of the handler this module patches
  at `0x40056b50`; KITS acts there with FUNC held, the gesture without. On
  a unit the gesture passed beside KITS (`OCTABAM8`); KITS' own action
  beside the module has not been tried.
- On a unit: MIDI note-offs across a switch with a long note; MASTER
  LENGTH 16 and NORMAL with a 32-step override, and GRID REC's page 2, were
  not reported separately.
- The track's speed (scale) stays the playing pattern's; overrides are not
  saved; trig LEDs and editing in GRID REC address the global pattern.

## Credits

The sequencer addresses build on devilfish707's Play Modes investigation
(Octaplay, `playmodes/INVESTIGATION.md`), which cites octabam (Sam Banks),
Tim Hastie's DIRECT JUMP and SCALE QUANTIZER, the KYOTI notes (Zac-Kyoti)
and EUCLID; the LED model on octabam's `docs/firmware/PANEL.md` (Tim
Hastie's panel work). From Octaplay only addresses and findings are used,
no code; Octaplay is MIT; `THIRD_PARTY.md` has the row.
