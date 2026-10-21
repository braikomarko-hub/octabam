# MORPH (v0)

Hold a track key and press **UP**: that track's scene morph runs by itself, scene A → B → A, one
cycle every **128 steps**, starting on A. The other tracks keep the crossfader. Hold the track key
and press **DOWN**: the morph finishes its cycle on A and the track stays **parked on A**; it
follows the crossfader again only once the crossfader reaches its A end, so nothing jumps.

Author: MaMarko (Marko Brajković, [braikomarko-hub](https://github.com/braikomarko-hub)): the idea, the listening and the tests on the unit.
**The code was written by Claude (Anthropic)**: engine, calibration, integration and gates.

Inspired by the Korg Electribe's Motion Sequence
(https://support.korguser.net/hc/en-us/articles/205917700-Motion-sequence): there the knob moves
are recorded; here the movement is the ramp between the two scenes the Octatrack already has.

v0 has no settings and saves nothing: the length is fixed, a reloaded project starts with every
track on the crossfader. The full version (a window per track: STEPS, multiplier, SMOOTH / TRIG
HOLD; saved in the project) is specified in the author's project notes and not built.

Markers: ✅ measured, 🟡 inferred.

## Using it

| keys | what happens |
|---|---|
| [TRACK] + [UP] | MORPH ON on every held track: from A. A track already morphing is left alone; a track finishing its cycle carries on (the stop is cancelled); a parked track starts again from A |
| [TRACK] + [DOWN] | MORPH STOP on every held morphing track: the cycle finishes on A, then the track is parked on A |
| crossfader to its A end | a parked track follows the crossfader again |
| [STOP] | the morph holds where it is; [PLAY] carries on |

Several tracks can morph at once, each from the moment its keys were pressed (not from the bar).

## How it works

- ✅ **The weight per track.** The scene morph takes, for each track, a long at
  `0x80003c60 + 4·t`: the high word weights scene A's value, the low word scene B's (the both-scenes
  path at `0x4000ce60`). Only the crossfader writes them (`0x40061e2e`, `0x400626a8`), from the
  curve at `0x400bcd90` (`w = curve[xf]`, `0` … `−32768`; weight `= (w << 16) | ((0xffff8000 − w) &
  0xffff)`); xf 127 is all A, 0 all B. MORPH computes the same word from its own xf.
- ✅ **When.** A detour at `0x4000cc62` (`move.l #96,%macsr ; lea 12(%sp),%sp`, both replayed) runs
  once a frame in the frame builder, after its per-track loop and before `0x4000cc6c`, where all six
  paths that read the weights begin. No branch in the image lands inside the 10 bytes. It writes the
  weight of every morphing or parked track, so a crossfader move, which rewrites all ten, is
  undone for those tracks before the morph reads them.
- ✅ **The ramp.** A 32-bit phase per track advances by `(tempo24 · 8657) >> 8` a frame
  (`tempo24` = BPM × 24 at `0x8000181c`), so a cycle is `127,008,000 / tempo24` frames; the top
  byte of the phase is folded into a triangle, xf 127 → 0 → 127. It does not advance while the
  transport word `0x800065b8` is not 1.
- 🟡 **128 steps.** The period assumes the frame builder runs once per 16-sample frame at 44.1 kHz
  (363 µs). If it does not, the cycle is a different length by the same factor: the first test on
  the unit (time one cycle at a known BPM) settles it.
- ✅ **The keys.** Holding a track key pushes the layer `0x400d164a`, whose table `0x400d1594` has
  six records (STOP, PLAY, BANK, YES, NO, 0x18) and a terminator; UP and DOWN are not in it, so
  stock passes them to the layer below. MORPH carries a copy of the table with UP (`0x33`) and DOWN
  (`0x20`) added, and the layer's keys field `0x400d164e` points at it. The handlers follow stock's
  convention (`handler(keycode, event)`, event 1 = press; Zac Kyoti's REC_TRIG_MUTE uses the same
  table) and show MORPH ON / MORPH STOP.

## Limits (v0)

- **dEVILish's knobs and MIDI tracks follow the crossfader, not MORPH.** OCTA303 morphs dEVILish's
  scene knobs from the crossfader position (`0x460d16c8`), and MIDI SCENES does the same for the
  MIDI tracks; on a morphing track those follow the fader while the rest of the track follows the
  ramp. SCENES P2 reads the weights after the stock morph and follows MORPH.
- Select parameters (MODE, WAVE…) jump at the middle of the morph, as with the crossfader.
- [TRACK] + [UP]/[DOWN] replace what UP/DOWN did while a track key is held (stock: the layer below,
  e.g. a list's cursor).
- Cannot share an image with REC_TRIG_MUTE (both rewrite the [TRACK]-layer table).

## Measured

- ✅ `tools/morph/test_morph.py`: `morph.s` executed from its source text in OCTA303's source
  simulator (`tools/octa303/sim/cfsim.py`, with its ColdFire lint), against a mock of the firmware
  addresses and the user's crossfader curve: 21/21 (21 Oct 2026). The keys' state machine; starts on
  A; B at half a cycle and A again after one cycle (40,708 frames at 130 BPM); one xf step per frame
  at most; every weight is one the crossfader writers produce; the transport stop holds the phase;
  stop finishes on A, parks, holds A against a fader move, re-attaches at the fader's A end and then
  follows it. Not covered: the hook under the real firmware, MACSR (the simulator has none), the
  keys through the real layer.
- Not yet: `make check` under the port, the unit.

## Credits

- Korg, the Electribe's Motion Sequence: the idea.
- Zac Kyoti, REC_TRIG_MUTE (`modules/rec-trig-mute`): the [TRACK]-held layer, its handler
  convention and the toast call.
