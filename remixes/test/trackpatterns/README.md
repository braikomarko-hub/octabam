# `trackpatterns` -- TRACK PATTERNS

TRACK PATTERNS by pgstath and the stock effects.

## What is in it

- **TRACK PATTERNS** -- [`modules/trackpatterns/README.md`](../../../modules/trackpatterns/README.md): a pattern per track, clip style; hold [TRACK n] + [PATTERN] + [TRIG k].
- the 14 stock FX2 effects, listed so the chooser is stock's.

## Status

`make check REMIX=trackpatterns` and the module's gate. Flashed as `OCTABAM3` on the contributor's MKII on 21 Oct 2026: the functional tests and the trig LED checks were reported as passed (`modules/trackpatterns/TESTING.md`).

## Build

```bash
make image REMIX=trackpatterns BUILD=1
```

[BUILDING.md](../../../docs/guide/BUILDING.md) is the walk-through from a fresh machine to a flashed unit. `make check REMIX=trackpatterns` runs every gate first.
