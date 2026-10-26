# `window-mod` -- MODULATION in the shared P window

CORE with LOAD METER, MODULATION and the stock effects except CHORUS (MODULATION takes its id) and the three reverbs (their words hold LOAD METER's DSP half and the CORE modules). MODULATION's code is one 1,561-word copy (including the 148-word table) at P:0x36300, in payload A's half of the shared window, reached from both cores. `window-ctl` is the same set with MODULATION in internal P.

## What is in it

- CORE and LOAD METER, as in `octabam`.
- MODULATION at P:0x36300 (`Remix.window`).
- FILTER, EQUALIZER, DJ EQ, PHASER, FLANGER, SPATIALIZER, COMB FILTER, COMPRESSOR, LO-FI, DELAY.

## Status

Builds (`make bus REMIX=window-mod`). Per-remix gates (`check_shards`) pass in the port. Not run on a unit.

The unit run reads MODULATION's slot cost per mode in LOAD METER, to set against the same code in internal P (JUNO 7.20, DIM 8.75, FLNG 8.95, COMB 7.93, PHSR 8.65 % of a frame). The difference is the cost of running from the window.

## Build

```bash
make check REMIX=window-mod
```
