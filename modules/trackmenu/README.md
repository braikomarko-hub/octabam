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
| ERGOSUM | MODE (LIN XY SNAKE DIAG) | RATI (1:1 .. 5:7) | SNAK (1..16) | ARM (OFF / ARM) | | |

MORPH's page shows its cycle under the knobs ("CYCLE 128 STEPS"), as MORPH's own window does.
The knob values are at most five characters (the stock knob's buffer, `docs/firmware/PARAM_PAGES.md`).

**v1 is the navigation only.** Nothing reads these values yet: MORPH keeps its own settings and
window, no pattern is printed, ERGOSUM has no engine, nothing starts, nothing is saved. The name is
provisional.

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
