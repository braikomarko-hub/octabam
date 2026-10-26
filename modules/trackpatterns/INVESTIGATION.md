# TRACK PATTERNS — what is known, what has to be found

OS 1.40C, ColdFire side. Section 1 is from published sources and earlier
reads, cited per row. ✅ = measured (emulator or unit), 📖 = read from code,
❓ = inferred, unconfirmed. Only addresses and conclusions are kept here,
never firmware listings.

## 1. Anchors

| what | where | source | |
|---|---|---|---|
| transport (0 stopped, 1 playing) | `0x800065b8` | EUCLID, emu_frames | ✅ |
| playing bank / pattern | `0x800065bd` / `0x800065be` | EUCLID, DIRECT JUMP | ✅ |
| per-track step counter, tracks 0–15 (MIDI 8–15) | `0x800064d0[t]` | KYOTI; Play Modes; our emulator runs, 19 Oct 2026 | ✅ |
| bank blob / pattern / track records | `0x400e21e0 + bank·0x9b340`, `+ p·0x8ed8`; audio `+ t·0x91a`, MIDI `+ 0x48d0 + t·0x8b0` | STEP_LOCKS.md, EUCLID | ✅ |
| audio tick: step load, then `0x4009d1e8(track, bank, pattern, step, n)` | load `0x400a2d6a`, call `0x400a2d7e` | Play Modes round 2 | 📖 |
| MIDI tick: `0x4009cf4c(track, bank, pattern, step, n)` | load `0x400a39b6`, call `0x400a39c6` | Play Modes round 2 | 📖 |
| the step handler derives trigs, conditions, micro-timing, swing and locks from its arguments | `0x4009d1e8` | Play Modes round 2 | 📖 |
| rebuild after an edit, `n = -1` | audio `0x4009dc86` (call `0x4009dc9e`), MIDI `0x4009e3dc` | Play Modes round 2 | 📖 |
| per-track length and scale read (track `+0x50` / `+0x51` under PER TRACK, pattern `+0x8e53` under NORMAL) | per-track advance `0x400a3ca4..0x400a3ecc` | KYOTI; Play Modes adapter | 📖 |
| trig-condition pass counters, per track | `0x46107918[t]` | Play Modes round 2 | 📖 |
| UI step query (trig LEDs, live recording, lock editing) | `0x4009b2b0` | Play Modes round 3 | 📖 |
| trig-key dispatcher; GRID REC goes elsewhere; tail call into the trig logic | `0x40060ce0`, GRID REC `0x460d1736`, tail call `0x40060cfc` → `0x400501d8` | STEP REPEAT, 19 Oct 2026 | 📖 |
| trig mode (0 TRACKS), LIVE REC, current track | `0x460d16f0`, `0x460d172a`, `0x100b14cc` (+ MIDI mode `0x80000012`) | STEP REPEAT, 19 Oct 2026 | 📖 |
| toast | `0x4005a2b8(text, duration)`, duration > 0, key-handler context only | KYOTI | ✅ unit |
| rebuild every track's prepared step | `0x4009da20(-1)` | Play Modes `pm_key_entry` | ✅ unit |
| key state per key code: a 24-byte record at `0x46c7d8de + 24·code`, the long at +16 nonzero while held (1; 2 once a layer opened over the key), cleared on release; TRACK 1–8 are codes `0x10`–`0x17` | `0x46c7d8ee + 24·code`, set `0x40031936`, cleared `0x4003180c` | output-matrix (encoder pushes); our emulator runs, 21 Oct 2026 | ✅ emu |
| PATTERN key: press `0x460d1742 = 1`, clears `0x460d173e` and the hold's trig mask `0x460d1ab6`, opens the PATTERN layer; release with no trig pressed latches it (`= 2`, a timed popup), else closes it (`0x40043418`) | `0x4005a044` | read 21 Oct 2026 | 📖 |
| the PATTERN layer's trig press `0x40056b2c(code)`: cancels the latch's timer, marks a trig pressed (`0x460d173e = -1`), selects the global pattern `0x400a1030(bank, code)` for the first trig of the hold or chains `0x4009c634(code)` for another, sets the trig's bit in `0x460d1ab6`, tail `0x40027de4`; its release `0x40043444` clears the bit | key map `0x400bef04` | read 21 Oct 2026 | 📖 ✅ emu |
| MIDI mode: TRACK keys address M1–M8 | `0x80000012 != 0`, toggled by the MIDI key `0x35` (`0x4005557a`) | Play Modes; emulator 21 Oct 2026 | ✅ emu |
| the MIDI step handler's plain trig writes `0x1d` into the same table `0x46c7a810[t]` (t = the MIDI track 0..7) | pc `0x4009d0fc` | read and run 21 Oct 2026 | ✅ emu |
| LEDs: steady on/off bits `0x460ba98c` (17 bytes, id n = byte n/8, bit n%8; on `0x400131a0`, off `0x400131c8`), timed bits `0x460ba9ae` XORed over them; no hardware blink. Trig key k = LEDs 2k (sample trigs) and 2k + 1 | tables `0x400a766e`, `0x400a76ae` | octabam PANEL.md sections 8 and 9; read 21 Oct 2026 | 📖 ✅ emu |
| the LED dispatcher `0x4007e998(slot)`: calls the callback at `0x460e762c + 14·slot`, then flushes `0x400136a8`; runs every few ms, playing or stopped | callbacks: main page `0x40043fdc`, PATTERN layer `0x400353d4` | read and run 21 Oct 2026 | 📖 ✅ emu |
| main page LEDs `0x40043fdc`: GRID REC → `0x40034bd4` draws the current track's trigs from the UI's cursor (bank base `*0x46c82456`, track `0x100b14cc`, pattern `0x100b14d0`, page `0x460d1e04`); TRACKS mode outside GRID REC → no trigs, only flashes; then the running light: both LEDs of the key of step `0x4009b2b0(t)` if `0x4009b290(t)` == 1, t = `0x80000000` (+8 MIDI), in GRID REC only on the page shown | `0x40043fdc..0x40044574` | read 21 Oct 2026 | 📖 ✅ emu |
| PATTERN layer LEDs `0x400353d4`: the UI pattern `0x100b14d0` first LED; a queued pattern both; others the second LED when `0x4009a464(pattern, bank)` says it has content | | read 21 Oct 2026 | 📖 ✅ emu |

## 2. Still to find

Every read needs the contributor's OK, because a short listing of stock
code passes through the assistant's conversation (kept in git-ignored
`out/` files, never committed).

1. **The key gesture: found and run (section 4, `0x40056b50`).** The
   trig keys under PATTERN live in the key map `0x400bef04` (not the layer
   `0x400bebfe`, which holds the encoders, arrows and transport keys).
   Whether a TRACK key is held comes from the stock key-state table, so
   the gesture needs neither Play Modes' TRACK handler nor its trig
   dispatcher site. Open: a TRACK key pressed *after* PATTERN (not the
   documented order) and the latched PATTERN (a tap) with TRACK held.
2. **The track's speed (scale).** The advance latches a track's scale from
   track `+0x51` or the pattern's `+0x8e54` into `0x8000663e[t]` at
   `0x400a3d02..0x400a3d0e` (audio) and `0x400a3e24..0x400a3e30` (MIDI).
   v1 leaves the speed on the playing pattern.
3. **Other readers of a track's trigs during play**: slides, the
   micro-timing look-ahead, NEI / PRE conditions, the pattern-end test.
   The tick also keeps the playing pattern and bank per track in
   `0x46c77b89[t]` / `0x46c769b0[t]` (written at `0x400a3d50`,
   `0x400a3e6e` and three transport starts; read at `0x4009b682`,
   `0x4009bc58`, `0x4009bd82`, `0x400a3f00`); who reads them is open.
4. **Bank residency.** Whether banks other than the playing one are in RAM.
5. **MIDI note-offs across a switch.** An emulator run with MIDI out
   captured, switching mid-note: needs a project whose M1 has a MIDI
   channel (the test copy's sends clock only).

## 3. Port checks before any flash

A project with distinct trigs on A01 and A03, T1 queued to A03 while
playing: the step handler's `pattern` argument for T1 changes from 0 to 2
exactly when `0x800064d0[0]` wraps; every other track keeps 0; a global
pattern change clears it. The same for M1 with MIDI out captured.

## 4. The sites (read from 1.40C, 21 Oct 2026)

| site | stock (whole instructions) | what the stub does | |
|---|---|---|---|
| `0x400a2d76` audio tick, 6 | `movel %d3,%sp@-` (pattern) ; `movel %sp@(86),%sp@-` (bank) | pushes `tp_pattern_entry(d5, 0x800064d0[d5], d3)` instead of d3 | 📖 ✅ port |
| `0x400a39c0` MIDI tick, 6 | `movel %d4,%sp@-` (pattern) ; `movel %d3,%sp@-` (bank) ; `movel %d7,%sp@-` (track) | the same for tracks 8 + d7, raw `0x800064d8[d7]` | 📖 |
| `0x4009dc8c` audio rebuild, 8 | `mvsb 0x800065be,%d4` ; `movel %d4,%sp@-` | keeps d4, pushes `tp_peek_entry(d6, d2, 0, d4)` | 📖 |
| `0x4009e3e2` MIDI rebuild, 8 | `mvsb 0x800065be,%d2` ; `movel %d2,%sp@-` (the step still in d2) | the same for d6 = 8..15, then d2 as stock leaves it | 📖 |
| `0x400a3d88` audio advance, 6 | `mvzb %d1,%d1` ; `mvsb %d0,%d0` ; `cmpl %d1,%d0` (counter vs length) | compares with `tp_length_entry(d3, d0)`; the `bgts` after it tests our compare | 📖 |
| `0x400a3ea8` MIDI advance, 6 | the same, d3 = 8..15, the length from the MIDI record's `+0x28` | the same | 📖 |
| `0x40056b50` PATTERN layer's trig press, 6 | `tstw 0x460d1ab6` (the hold's trig mask: select or chain next); d2 = the trig, a2 = the redraw `0x400418e0` | with a TRACK key held (`tp_gesture`): redraw, toast, rebuild `0x4009da20(-1)`, then joins stock at `0x40056ba4` (mark the trig, tail `0x40027de4`); otherwise replays the test and returns to the `bnes` at `0x40056b56` | 📖 ✅ emu ✅ unit (MKII, T1 and M1) |
| `0x4007e9b6` LED dispatcher, 6 | `movel %d2,%sp@-` ; `jsr %a0@` (the slot's LED callback) ; `addql #4,%sp` | replays the call, then `tp_leds(slot)` adjusts the steady trig bits for a current track on its own pattern; after GRID REC's dark half it relights the running light from `0x4009b290` / `0x4009b2b0`; joins stock at `0x4007e9bc` before the flush | 📖 ✅ emu ✅ unit (MKII) |

How the tick picks a step's pattern: with a pattern change pending for
the step it prepares (a flag in d3 at `0x400a2c64`), it takes bank and
pattern from `0x800065c2` / `0x800065c1` (the next pattern), otherwise
from `0x800065bd` / `0x800065be`. The stubs pass stock's bank too (audio:
the long the tick stores at `0x400a2d64`, `82(%sp)` at the site; MIDI:
d3, from `0x400a39b2`), and the adapter returns stock's choice when bank
or pattern differs from the playing one, so a global change lands as
stock, a bank change to the same pattern number (A10 → B10) included.

The step handler `0x4009d1e8` builds the pattern's address from its bank
and pattern arguments, ORs the track's four step masks and tests the step
bit at `0x4009d3a0`; a plain trig writes `0x1d` into the per-track table
`0x46c7a810[t]` at `0x4009d42a`, which the port run below watches.

No branch lands inside any of the eight spans; Play Modes' detours end
where these begin (`0x400a2d74`, `0x400a39be`, `0x4009dc8c`, `0x4009e3e2`).
No Modwerk module or base site patches `0x40056b2c..0x40056bc0` (the
octakit draft only names `0x40056b2c` and `0x40056b6e` in its ABI list)
or the LED dispatcher `0x4007e998..0x4007e9c4`. The LED stub calls
`0x4009b2b0`, Play Modes' detoured step query, as stock's running light
does: with Play Modes installed it gets the mapped step, as stock would.
