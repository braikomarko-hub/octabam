# `sidechain-compressor` -- SIDECHAIN_COMPRESSOR

One module by Zac Kyoti and the stock effects, less SPRING REV.

## What is in it

- **SIDECHAIN_COMPRESSOR** -- [`modules/sidechain-compressor/README.md`](../../../modules/sidechain-compressor/README.md), in COMPRESSOR's row. This version (the base-width key filter, 22 Oct 2026) ran on the author's MKI in the author's standalone and KYOTI V1.6 images; the previous version ran in an octabam image, 4 Oct 2026.
- 13 of the 14 stock FX2 effects. SPRING REV gives up its words for the module's DSP section, as in the author's standalone build.

## Status

The ColdFire unit's bytes are the author's: `reference` re-links them at the author's address every build and compares. The author's standalone image ran on the author's MKI. This remix as a whole has not been flashed; the previous version of SIDECHAIN_COMPRESSOR ran on the unit in a larger octabam image (all six KYOTI modules, REC_TRIG_MUTE, that module), 4 Oct 2026.

## Build

```bash
make image REMIX=sidechain-compressor BUILD=1
```

[BUILDING.md](../../../docs/guide/BUILDING.md) is the walk-through from a fresh machine to a flashed unit. `make check REMIX=sidechain-compressor` runs every gate first.
