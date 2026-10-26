# `atomizer` -- AtoMizer

AtoMizer beside the stock effects (all but DELAY, SPRING REV, PLATE REV and DARK REV, whose words and id it takes).

## What is in it

- **AtoMizer** -- [`modules/atomizer/README.md`](../../../modules/atomizer/README.md).
- the stock effects but DELAY, SPRING REV, PLATE REV and DARK REV, listed so the chooser is otherwise stock's.
  AtoMizer's 1,477 words (with its P table) need the whole run SPRING REV and PLATE REV leave, and
  DARK REV keeps 35 of SPRING REV's words in the middle of it, so DARK REV goes too. AtoMizer takes
  DELAY's id (0x08) for now: every free FX2 id is claimed in this tree (the module's README, "Open").

## Status

Render-gated only: `tools/verify/verify_atomizer.py`, 20 Oct 2026. Not built for the unit yet.

## Build

```bash
make check REMIX=atomizer
```
