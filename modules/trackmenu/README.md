# TRACK MENU (v1, prototype)

Hold a track key about a second, with no other key: that track's menu opens, and stays open when
the key is let go. First a small chooser (as the stock TRACKS / CHROMATIC / SLOTS list), then the
chosen function's page, its settings drawn as the stock's own knobs.

```
 T held ~1 s ──► ┌────────────┐   UP / DOWN: the choice     YES ──► █ T5 EUCLACID ████████ 1/2 █
                 │█ MORPH    █│   YES: its page                     PLSA   ROTA   PLSB
                 │  EUCLACID  │   NO or the same T: closed           (o)    (o)    (o)
                 │  ERGOSUM   │                                       4      0      0
                 └────────────┘                                     ROTB   SLDE   SROT ...
```

On a page: the knobs set the values; LEFT / RIGHT turn EUCLACID's two pages; the SAME track key
closes ("T5 START"); NO goes back to the chooser; on EUCLACID YES flashes PRINT and CUE flashes
UNDO in the title bar. The chooser opens on the function last used on that track.

| page | A | B | C | D | E | F |
|---|---|---|---|---|---|---|
| MORPH | STEP (TRK, 1..64) | MULT (1..16) | MODE (SMTH / HOLD) | MRPH (OFF / ARM) | | |
| EUCLACID 1/2 | PLSA | ROTA | PLSB | ROTB | SLDE | SROT |
| EUCLACID 2/2 | MODE (EUCL / GOLD / DENS / NEST) | A+B (OR XOR AND A-B) | LIVE (OFF ROT DENS MUTA OPER) | ONLY (OFF / ON) | EVRY (1..64) | |
| ERGOSUM | MODE (LIN XY SNAKE DIAG) | RATI (1:1 .. 5:7) | SNAK (1..16) | ERGO (OFF / ON) | SPLT (ALL / NOTE / RTHM) | |

MORPH's page shows its cycle under the knobs ("CYCLE 128 STEPS"), as MORPH's own window does.
The knob values are at most five characters (the stock knob's buffer, `docs/firmware/PARAM_PAGES.md`).

**MORPH and EUCLACID are navigation only.** Nothing reads their values yet: MORPH keeps its own
settings and window, no pattern is printed, nothing starts, nothing is saved. **ERGOSUM plays**
(below): ERGO ON acts at once, as the ERGOSUM page did before v1. The name is provisional.

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

| SPLT | rhythm (trigs, conditions, microtiming, slides) | notes (every lock: on OCTA303 TUNE and ACC) |
|---|---|---|
| ALL | the grid's cell | the grid's cell (as before) |
| NOTE | the pattern as written | the grid, skipping the cells that hold no trig: only the written notes, reshuffled |
| RTHM | the grid's cell | the pattern's step, or the last written step before it: the melody keeps its time |

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


Code: written by Claude (Anthropic); idea, design and tests on the Octatrack: MaMarko.

## How the long press works (measured from the user's 1.40C)

- The eight track records of both key tables (MKI `0x400bfc10`, MKII `0x400c01f4`) have one stock
  handler `0x40040250` for press, release and repeat. Only the PRESS field is repointed, at
  `tm_tpress`, which calls the stock handler first and then starts a soft timer.
- The timer (~17 ms) counts while the track key is the only one held (`HELD 0x460fab40`, the panel
  key rows `0x46100b18`). FUNC or CUE down at the press, another key, another track, the release,
  or MIDI mode: no menu. Another window on screen: it waits for it to go.
- The menu is a TEMPO-class window (as MORPH's) with its own input layer over everything: LEFT,
  RIGHT, UP, DOWN, YES, NO, CUE, the track keys and the knobs; trigs, page keys, FUNC, PATTERN,
  BANK, REC, MIDI, TEMPO and LEVEL are swallowed; PLAY and STOP keep working. The chooser (64 x 32)
  and the page (116 x 64) are two sizes of window: going between them destroys one and creates the
  other, with the layer and the timer kept. `tm_swap` keeps the closed callback out of it across
  WDESTROY **and** WCREATE: the stock WCREATE calls the closed callback of the window it replaces
  even after WDESTROY (measured under the port, 25 Oct 2026, `live_shots.py --watch`: `tm_closed`
  called from `0x400582e2` on the chooser -> page swap, which popped the layer and stopped the timer).
- The knobs are the stock PLAYBACK knob `0x400479b4(x, y, slot, value, flags 8, fmt, surface)`
  (as `modules/cxosc/page.s` calls it), the name centred on x + 9 at y + 20 as the stock renderer
  draws it; each list has a formatter fmt(buf, value).
- The held track key keeps the stock handlers while the layer is pushed, so its release reaches the
  stock; once it is up the layer is pushed again so the next press of that key is the menu's.

## Measured

- `tools/trackmenu/test_trackmenu.py`: the source under cfsim with a mocked firmware: the long press
  and everything that cancels it, the chooser, the pages, every knob's range and label, the flash,
  the window swap (the guard up across WCREATE), closing, the remembered function, registers kept
  (81 checks).
- Under the port (owner's Mac, 25 Oct 2026): the long press opens the chooser (held 8 s of wall
  clock: the port runs slower than real time; 5 s was not always enough).

## On the unit

- v0 (one window, pages with LEFT / RIGHT, rows of text) on the owner's MKI, 24 Oct 2026, loaded
  with REMIX SWITCH: opens with the long press, every key answers. The owner asked for v1's shape.
- v1: not yet.

## Open

- Inferred, not measured: that a soft timer callback may create a window; that window-table +32
  bit 0x20 marks every visible window; that the key rows read 0 for keys that are up.
- A knob turned while the track key is held does not cancel the long press.
- MIDI tracks: no menu in v0.
