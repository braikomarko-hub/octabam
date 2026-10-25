# TRACK MENU (v0, prototype) -- the owner's name: ACID BUCKET

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
| ERGOSUM | MODE (LIN / XY / SNAKE / DIAG) | RATIO (1:1 1:2 2:3 3:4 1:3 2:5 3:5 3:7 5:7) | SNAKE (1..16) | ERGOSUM (OFF / ON) | SPLIT (ALL / NOTES / RHYTHM) | |

On the EUCLACID pages YES flashes PRINT and CUE flashes UNDO in the title bar. The page is
remembered per track while the unit is on.

**The MORPH and EUCLACID pages are navigation only.** Nothing reads their values yet: MORPH keeps
its own settings and window, no pattern is printed, nothing starts. **The ERGOSUM page works** (below).
Nothing is saved: the settings live while the unit is on.

Code: written by Claude (Anthropic); idea, design and tests on the Octatrack: MaMarko.

## ERGOSUM

The idea: Make Noise RENE, the Cartesian sequencer. The track's 16 steps are a 4x4 grid; with
ERGOSUM ON the track plays the grid's cell instead of the step: its trig, its trig condition, its
locks and slides, all of the cell. The step shown and the trig LEDs stay the real ones.

```
        x ->                 MODE XY, RATIO 1:3: x moves every step, y every 3 steps
   +--+--+--+--+
 y | 1| 2| 3| 4|             plays 1 2 3 8 5 6 11 12 9 14 15 16 1 2 3 8 ...
   | 5| 6| 7| 8|             (the same 16 steps, another order)
   | 9|10|11|12|
   |13|14|15|16|
   +--+--+--+--+
```

| MODE | the cell for the counter k (the sequencer's step word) |
|---|---|
| LIN | the step itself (ERGOSUM ON changes nothing) |
| XY | x = (k / X) mod 4, y = (k / Y) mod 4, cell = 4y + x; RATIO = X:Y |
| SNAKE | path SNAKE (1..16): rows, snake rows, columns, snake columns, diagonals, anti-diagonals, spiral in, spiral out, the first four reversed, k*5, k*3, k*7, k*11, k*13 (mod 16) |
| DIAG | the diagonals path (SNAKE 5) |

RATIO runs from the most consonant to the least, after Descartes' *Compendium Musicae*: the
sweetness of a consonance follows how often the beats of the two bodies coincide. 1:3 meets every
3 steps (a short, recognisable loop), 5:7 every 35 (it hardly repeats). The ear decides.

**SPLIT** (25 Oct 2026; on Make Noise RENE the knobs and the gates are separate): the rhythm and the
notes can come from different places.

| SPLIT | rhythm (trigs, conditions, microtiming, slides) | notes (every lock: on OCTA303 TUNE and ACC) |
|---|---|---|
| ALL | the grid's cell | the grid's cell (as before) |
| NOTES | the pattern as written | the grid, skipping the cells that hold no trig: only the written notes, reshuffled |
| RHYTHM | the grid's cell | the pattern's step, or the last written step before it: the melody keeps its time |

```
   NOTES, MODE XY 1:3, a four-on-the-floor rhythm and 6 written notes:
   step   1  2  3  4  5  6  7  8 ...     the trigs: the pattern's (1, 5, 9, 13 ...)
   note   C        F#       D#   ...     each trig takes the note of the grid's next written cell
```

A pattern longer than 16 steps is read block by block: the cell stays in the step's block of 16. A
track shorter than 16 steps can land on a cell past its end: no trig there.

**How (measured from the user's 1.40C, 24 Oct 2026).** The trig record builder `0x4009d1e8(track,
bank, pattern, step, n)`, known so far for its locks (STEP_LOCKS.md), is where the step's trig is
decided: the mask `1 << step` against the track record's trig masks, the trig condition
`0x400a5164(track, step, cond, ...)`, then the trig's action at `0x46c7a810 + 4t` and the step's
locks. Its callers: the sequencer tick `0x400a2d7e` (step = the track's step byte `0x800064d0 + t`)
and the position refresh `0x4009da20`. ERGOSUM displaces its entry (`lea -0x68(sp)` ; `movem.l`, 8
bytes) and calls the builder itself with the rhythm's step T as the argument and the locks' step L
one long past the arguments. The builder loads the step's lock row (track record + 0x58 + 32 * step
+ 1) at two places only, `0x4009d73a` (with a slide) and `0x4009d8e0` (without): each
`move.l 0x78(sp),d0 ; lsl.l #5,d0` becomes `jsr es_lk` (d0 = L * 32). Everything else the builder
does with the step (the trig masks, `0x400a5164`, the step word at `0x44d`, the trig's kind, the
search for the next trig of a slide) stays on T. OFF, LIN and tracks above 7: T = L = the step, the
builder as stock. `es_next[t]` holds the cell played next (0xff off, LIN or NOTES): OCTA303 (v7.2)
ties its 303 gate into it when the remix carries this module.

Known limits: on a stock machine's slide trig in NOTES mode the glide aims at the locks of the
pattern's next trig, not the grid's (OCTA303 slides from the pitch it is playing, so it is not
affected); PLOCKS P2's page-2 locks follow the rhythm's step.

Open: the counter is the master step word, so a track at another speed or scale walks the grid at
the master's pace; NOTES counts steps, not trigs (a trig takes the grid's cell for its step, the
next written one from there); not yet run under the port with the sequencer playing, nor on the
unit.

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
  remembered page, registers kept; ERGOSUM's entry against a Python model of the grid (every mode,
  ratio and four snakes, k 0..79 and the word's wrap, three blocks), the arguments the builder
  receives, the displaced movem, OFF and LIN passing the step, tracks above 7; SPLIT ALL / NOTES / RHYTHM against a model of the
  trig masks (1500 random cases), the written-cells rule, `es_lk` (77 checks).

## On the unit

Not yet.

## Open

- Inferred, not measured: that a soft timer callback may create a window; that window-table +32
  bit 0x20 marks every visible window; that the key rows read 0 for keys that are up.
- A knob turned while the track key is held does not cancel the long press.
- MIDI tracks: no menu in v0.
