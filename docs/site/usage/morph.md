A track's scene morph, played by itself. The track moves from scene A to
scene B and back on its own, in time with the pattern, while the other
tracks keep the crossfader. Or, with TYPE RISE, it goes from A to B once and
stops: a rise on one track while the rest of the scene does something else.
Each track has its own settings, and several can morph at once. Inspired by
the Korg Electribe's Motion Sequence.

## Access

Hold a TRACK key for about a second: the MORPH window of that track opens.
Turn A–D, press YES to arm, then press the same TRACK key: the window
closes and the morph starts from scene A on the next step. NO closes
without starting anything. Not in an official remix; build the test remix
`morph`. Needs STORE (it saves through it).

## Operation

- LOOP: A → B → A once every STEP × MULT steps (16 × 8 = 128 by default).
  It counts the sequencer's steps, so it never drifts from the pattern.
- RISE: A → B once in STEP × MULT steps, then the track is parked on A. It
  follows the crossfader again once the crossfader reaches its A end, so
  nothing jumps.
- On a morphing track, YES in the window means STOP: with the same TRACK
  key the cycle finishes on A and the track stays parked there.
- TRACK + UP (the old way) still opens the window armed for the held
  tracks; releasing the keys starts them. TRACK + DOWN stops them.
- STOP holds the morph where it is; PLAY carries on.
- The settings of every track, and which tracks morph, are saved with the
  project (`morph.work`; SAVE PROJECT keeps a `morph.strd` copy that RELOAD
  brings back).
- MIDI tracks keep the crossfader. Select parameters jump at the middle of
  the morph, as with the crossfader.

## Controls

| Control | Does |
|---|---|
| hold TRACK ~1 s | open the window |
| YES | arm / disarm (STOP / ON on a morphing track) |
| the same TRACK | close and apply, with a toast (T2 MORPH ON) |
| NO | close, nothing applied |
| A | STEP: TRK (the track's length) or 1..64 |
| B | MULT: 1..16 |
| C | MODE: SMTH (moves every frame) or HOLD (one value a step) |
| D | TYPE: LOOP or RISE |

The bar under the knobs shows where the track is between A and B; the line
under it shows CYCLE 128, WAIT (starting on the next step), ON 12/128,
STOP 12/128 or PARK ON A.

![MORPH window](../../img/morph/window.png)

![STEPS 8, x 2](../../img/morph/settings.png)
