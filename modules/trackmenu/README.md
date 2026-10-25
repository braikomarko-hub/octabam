# TRACK MENU (v2)

Hold a track key about a second, with no other key: that track's menu opens, and stays open when
the key is let go. First a small chooser (as the stock TRACKS / CHROMATIC / SLOTS list), then the
chosen function's page, its settings drawn as the stock's own knobs. **Every function works.**

```
 T held ~1 s ──► ┌────────────┐   UP / DOWN: the choice     YES ──► █ T5 EUKLE ███████████ 1/2 █
                 │█ MORPH    █│   YES: its page                     PLSA   ROTA   PLSB
                 │  EUKLE     │   NO: closed                         (o)    (o)    (o)
                 │  ERGOSUM   │   the same T: closed + START                12
                 └────────────┘                                     ROTB   SLDE   SROT ...
```

On a page: the knobs set the values, and a value shows under its knob while that encoder turns,
then goes, as on the stock pages. LEFT / RIGHT turn EUKLE's two pages; NO goes back to the chooser.

**Armed, then started by the same track key.** The rows that start something (MRPH, LIVE, ERGO)
only arm on the page; the same track key (on a page or on the chooser) closes the menu and applies
them, and a toast says the state of the function shown ("T5 MORPH ON", "T5 LIVE ROT"). NO never
applies anything. When the menu opens, those rows show what runs now.

| page | A | B | C | D | E | F |
|---|---|---|---|---|---|---|
| MORPH | STEP (TRK, 1..64) | MULT (1..16; 41.6 if set in MORPH's window) | MODE (SMTH / HOLD) | MRPH (OFF / ON, armed) | | |
| EUKLE 1/2 | PLSA | ROTA | PLSB | ROTB | SLDE | SROT |
| EUKLE 2/2 | MODE (EUCL / GOLD / DENS / NEST) | A+B (OR XOR AND A-B) | LIVE (OFF ROT DENS MUTA OPER, armed) | ONLY (OFF / ON) | EVRY (1..64 bars) | |
| ERGOSUM | MODE (LIN XY SNAKE DIAG) | RATI (1:1 .. 5:7) | SNAK (1..16) | ERGO (OFF / ON, armed) | SPLT (ALL / NOTE / RTHM) | |

## MORPH

The page is MORPH's own: STEP, MULT and MODE are MORPH's settings (the ones its [TRACK]+[UP] window
edits, saved by MORPH in morph.work), changed at once. MRPH ON + the track key: MORPH starts on the
next step from scene A (as [TRACK]+[UP] and the release); MRPH OFF + the track key: a morphing track
finishes its cycle on A and parks there, an armed one goes back to the crossfader. Under the knobs,
MORPH's state: `CYCLE 128 STEPS` (the fader's), `WAIT  CYCLE 128` (armed), `ON  12/128` (morphing,
the step of the cycle), `STOP 12/128`, `PARK ON A`. TRACK MENU needs MORPH in the image.

## EUKLE

EUCLACID's Euclidean printer, renamed EuKlé by the owner (shown EUKLE: the display has no accents).
It writes ordinary trigs on the menu's track: nothing keeps running unless LIVE does, a printed
pattern plays on a stock unit, and a trig of yours is never removed.

- **YES = PRINT** (at once): the pattern of the knobs is ORed into the track; **CUE = UNDO**: the last
  print taken back (8 levels a track; a level saved in another pattern waits for that pattern; a track
  changed since the print, by hand or by loading another project, is not undone: NO UNDO). The
  result flashes in the title bar: PRINT, UNDO, NO UNDO, BUSY (the Octatrack is loading), HELD (a
  trig key is held), LENGTH, NO BANK.
- **MODE**
  - EUCL: E(PLSA, length) rotated ROTA; B = E(PLSB) rotated ROTB, combined by A+B (OR XOR AND A-B).
  - GOLD: PLSA hits spread along a line of slope PLSA / (length + 1/φ): Euclid's density with a
    golden drift, never quite periodic; ROTA = where it enters the line; with LIVE ROT the line goes
    on, generation after generation, and never repeats.
  - DENS: the PLSA heaviest steps of a weight map (16 1 6 2 11 1 5 3 14 1 7 2 10 2 4 8): turning PLSA
    up adds hits and keeps the old ones, like a drummer filling.
  - NEST: E(PLSA) hits; then ACCENTS = E(PLSB) and SLIDES = E(SLDE), counted over the hits, not the
    steps (rotated ROTB, SROT).
- **SLDE / SROT, ONLY**: the slide generator; ONLY = ON keeps slides on note steps.
- **On an OCTA-303 track** a slide is the 303's: the step becomes a trigless trig tied to the note
  before it (OCTA303's slide), taking that note's TUNE lock, unless you have a trig there; NEST's
  accents are ACC locks with the Part's ACC. On any other track slides go to the stock slide trigs
  and accents are not printed.
- **LIVE** (armed; the track key starts it): generation 0 is printed at once (one undo level), then
  one step before every EVRY-bar period ends the previous generation is replaced: ROT (rotates; in
  GOLD the line goes on), DENS (PLSA walks one up or down), MUTA (PLSA within 2, ROTA + 0..3), OPER
  (A+B cycles; without B, or in NEST, it rotates). A trig you add joins the base and stays; one you
  remove stays removed. LIVE OFF + the track key freezes the pattern where it is (UNDO then goes back
  to before LIVE). A held trig pauses it; a load, a bank or part change, or a pattern change freezes it
  (nothing is written in the other pattern). Regenerations do not mark the project changed.
- Only the rows you turn are applied by the track key: a LIVE that an UNDO froze, or a MORPH that
  parked by itself while the menu was open, is not restarted by a row you did not touch.

The engine is `eukle.s`, the reference model `tools/trackmenu/eukle_ref.py`;
`tools/trackmenu/test_eukle.py` runs both over random banks and compares every byte.

## ERGOSUM

The idea: Make Noise RENE, the Cartesian sequencer. The track's 16 steps are a 4x4 grid; with
ERGOSUM ON (ERGO ON, then the track key) the track plays the grid's cell instead of the step: its trig, its trig condition, its
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
