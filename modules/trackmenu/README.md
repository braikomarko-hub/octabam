# TRACK MENU (v0, prototype)

Hold a track key about a second, with no other key: that track's menu opens, and stays open when
the key is let go.

```
 T held ~1 s ──► ┌█ T5 MORPH ████ 1/3 █┐
                 │ A STEPS          16  │   LEFT / RIGHT: the page
                 │ B x               8  │   knobs: the values
                 │ C MODE       SMOOTH  │   the SAME track key: close ("T5 START")
                 │ D MORPH         OFF  │   NO: close, nothing starts
                 └──────────────────────┘
```

| page | A | B | C | D | E | F |
|---|---|---|---|---|---|---|
| MORPH | STEPS (TRK, 1..64) | x (1..16) | MODE (SMOOTH / HOLD) | MORPH (OFF / ARMED) | | |
| EUCLACID | PULSES A | ROTATE A | PULSES B | ROTATE B | SLIDES | ROT SLIDE |
| EUCL LIVE | MODE (EUCLID / GOLDEN / DENSITY / NESTED) | A+B (OR XOR AND A-B) | LIVE (OFF ROT DENS MUTA OPER) | SLIDE ON NOTE | EVERY BARS (1..64) | |

On the EUCLACID pages YES flashes PRINT and CUE flashes UNDO in the title bar. The page is
remembered per track while the unit is on.

**v0 is the navigation only.** Nothing reads these values yet: MORPH keeps its own settings and
window, no pattern is printed, nothing starts, nothing is saved. The name is provisional: the
module gets its own when MORPH and EUCLACID live in it.

Code: written by Claude (Anthropic); idea, design and tests on the Octatrack: MaMarko.

## How the long press works (measured from the user's 1.40C)

- The eight track records of both key tables (MKI `0x400bfc10`, MKII `0x400c01f4`) have one stock
  handler `0x40040250` for press, release and repeat. Only the PRESS field is repointed, at
  `tm_tpress`, which calls the stock handler first and then starts a soft timer.
- The timer (~17 ms) counts while the track key is the only one held (`HELD 0x460fab40`, the panel
  key rows `0x46100b18`). FUNC or CUE down at the press, another key, another track, the release,
  or MIDI mode: no menu. Another window on screen: it waits for it to go.
- The menu is a TEMPO-class window (as MORPH's) with its own input layer over everything: LEFT,
  RIGHT, YES, NO, CUE, the track keys and the knobs; trigs, page keys, FUNC, PATTERN, BANK, REC,
  MIDI, TEMPO, UP, DOWN and LEVEL are swallowed; PLAY and STOP keep working.
- The held track key keeps the stock handlers while the layer is pushed, so its release reaches the
  stock; once it is up the layer is pushed again so the next press of that key is the menu's.

## Measured

- `tools/trackmenu/test_trackmenu.py`: the source under cfsim with a mocked firmware: the long press
  and everything that cancels it, the pages, every knob's range, the flash, closing, the
  remembered page, registers kept (52 checks).

## On the unit

Not yet.

## Open

- Inferred, not measured: that a soft timer callback may create a window; that window-table +32
  bit 0x20 marks every visible window; that the key rows read 0 for keys that are up.
- A knob turned while the track key is held does not cancel the long press.
- MIDI tracks: no menu in v0.
