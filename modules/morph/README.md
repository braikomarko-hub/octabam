# MORPH (v1)

Hold a track key and press **UP**: on the next step, that track's scene morph starts running by
itself, scene A → B → A, one cycle every **STEPS × x steps** (by default 16 × 8 = 128), starting on
A. The other tracks keep the crossfader. Hold the track key and press **DOWN**: the morph finishes
its cycle on A and the track stays **parked on A**; it follows the crossfader again only once the
crossfader reaches its A end, so nothing jumps.

Author: MaMarko (Marko Brajković, [braikomarko-hub](https://github.com/braikomarko-hub)): the idea, the listening and the tests on the unit.
**The code was written by Claude (Anthropic)**: engine, calibration, integration and gates.

Inspired by the Korg Electribe's Motion Sequence
(https://support.korguser.net/hc/en-us/articles/205917700-Motion-sequence): there the knob moves
are recorded; here the movement is the ramp between the two scenes the Octatrack already has.

v1 has the engine of the full version: per track STEPS (0 = the track's length), x and MODE
(SMOOTH / TRIG HOLD), and a master switch. Not built yet: the settings window ([TRACK] + [UP]
opens it), the PROJECT menu row for the master switch, saving in the project and the notice on
loading (the project spec). Until then every track runs the defaults, 16 × 8 SMOOTH: v0's
behaviour, started on the step.

Markers: ✅ measured, 🟡 inferred.

## Using it

| keys | what happens |
|---|---|
| [TRACK] + [UP] | MORPH ON on every held track: it starts on the next step, from A. A track already morphing (or waiting for its step) is left alone; a track finishing its cycle carries on (the stop is cancelled); a parked track starts again from A |
| [TRACK] + [DOWN] | MORPH STOP on every held track: a morphing one finishes its cycle on A, then is parked on A; one still waiting for its step goes back to the crossfader |
| crossfader to its A end | a parked track follows the crossfader again |
| [STOP] | the morph holds where it is; [PLAY] carries on |
| master switch off | every morph finishes its cycle on A and parks; [TRACK] + [UP] shows MORPH IS OFF |

Several tracks can morph at once, each from the step after its keys were pressed (not from the
bar).

| setting (per track) | values | default |
|---|---|---|
| STEPS | 0 = the track's length in the current pattern, 1..64 | 16 |
| x | 1..8: one cycle is STEPS × x steps (at most 512) | 8 |
| MODE | SMOOTH: the weight moves every frame. TRIG HOLD: the step's value for the whole step | SMOOTH |

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
- ✅ **The clock (v1).** The cycle counts the sequencer's steps: every frame the step word
  `0x800065b2` (OCTA303's 303 gate reads it on the unit) is compared with the last frame's; a
  change is a step (a jump of more than 8, a restart or a pattern change, counts as one), and the
  frames since the last step are counted while the transport word `0x800065b8` is 1. A track's k is
  its steps since the cycle began; the triangle position is `(k · 256 + f) / N`, 0..255, folded
  into xf 127 → 0 → 127, where f is the fraction of the current step that has gone (SMOOTH:
  `frames × tempo24 × 4329 >> 24`, at most 255; TRIG HOLD: 0). So TRIG HOLD changes exactly on the
  steps, SMOOTH moves every frame, and neither drifts from the pattern over many cycles. One
  division a frame per morphing track; nothing else runs while every track is on the fader but
  the step-word compare.
- ✅ **STEPS 0** reads the track's length in the current pattern (bank blob `0x46c82456` + pattern
  `0x100b14d0` × `0x8ed8` + track × `0x91a`, the byte at `+0x50`, 1..64, else 16), as OCTA303's gate
  does, every frame: a pattern change is followed; a k past the new N starts again from A.
- 🟡 **The fraction of a step** assumes the frame builder runs once per 16-sample frame at 44.1 kHz
  (363 µs; a step is `992,250 / tempo24` frames). If it did not, SMOOTH would still land on every
  step (the clock is the step word) and only the motion inside a step would be uneven. 🟡 That the
  step word counts every 16th of the master length while playing.
- ✅ **The keys.** Holding a track key pushes the layer `0x400d164a`, whose table `0x400d1594` has
  six records (STOP, PLAY, BANK, YES, NO, 0x18) and a terminator; UP and DOWN are not in it, so
  stock passes them to the layer below. MORPH carries a copy of the table with UP (`0x33`) and DOWN
  (`0x20`) added, and the layer's keys field `0x400d164e` points at it. The handlers follow stock's
  convention (`handler(keycode, event)`, event 1 = press; Zac Kyoti's REC_TRIG_MUTE uses the same
  table) and show MORPH ON / MORPH STOP / MORPH IS OFF.

## Limits

- **MIDI tracks follow the crossfader, not MORPH**: MIDI SCENES morphs them from the crossfader
  position. SCENES P2 reads the weights after the stock morph and follows MORPH. dEVILish (OCTA303)
  follows MORPH since its knobs are read from the DSP voice record (the `devilish` branch, 21 Oct
  2026); before that it followed the crossfader.
- Select parameters (MODE, WAVE…) jump at the middle of the morph, as with the crossfader.
- [TRACK] + [UP]/[DOWN] replace what UP/DOWN did while a track key is held (stock: the layer below,
  e.g. a list's cursor).
- Cannot share an image with REC_TRIG_MUTE (both rewrite the [TRACK]-layer table).
- A track's own scale (×2, ½) is not followed: a step is the master 16th.

## Measured

- ✅ v0 on the owner's MKI, image ACIDV73MP (aCiDtRacK + MORPH), 21 Oct 2026: [TRACK] + [UP] runs
  the track's morph, the others keep the fader, [TRACK] + [DOWN] parks it on A. By ear.
- ✅ `tools/morph/test_morph.py` (v1): `morph.s` executed from its source text in OCTA303's source
  simulator (`tools/octa303/sim/cfsim.py`, with its ColdFire lint), against a mock of the firmware
  addresses, a mock sequencer moving the step word at the tempo, and the user's crossfader curve
  (a stand-in without `out/raw`): 35/35 (22 Oct 2026). Arming and the start on the next step from
  A; B at step 64 and A again at step 128 (16 × 8); one xf step per frame at most (SMOOTH) and the
  triangle's value on each step's first frame; TRIG HOLD one value per step, the 8-step triangle;
  STEPS 0 = the track's length (32 × 2); 512 and 1 steps; the transport stop; stop on A, parking,
  re-attach, cancel, an armed track dropped; the master switch (every morph ends on A, UP refused,
  on again). Not covered: the hook under the real firmware, MACSR (the simulator has none), the
  keys through the real layer.
- Not yet: v1 under the port (`tools/morph/port_morph.py`) and on the unit.

## Credits

- Korg, the Electribe's Motion Sequence: the idea.
- Zac Kyoti, REC_TRIG_MUTE (`modules/rec-trig-mute`): the [TRACK]-held layer, its handler
  convention and the toast call.
