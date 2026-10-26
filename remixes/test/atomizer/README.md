# `atomizer` -- AtoMizer, loaded on demand

AtoMizer beside all 14 stock effects. Its code is not in the image's P memory:
DLPUMP and DLCOPY copy it into the shared window (`P:0x35000`, offset +$1000 of
T8's FX2 slot on core A) while a track uses it, and withdraw it when none does
([`docs/proposals/DEMAND_LOAD.md`](../../../docs/proposals/DEMAND_LOAD.md)).

## What is in it

- **AtoMizer** -- [`modules/atomizer/README.md`](../../../modules/atomizer/README.md),
  on its preferred id (0x1e); it replaces nothing.
- **USB**, **LOAD METER**, **DLPUMP**, **DLCOPY**: the loader, as in `test/dlspike`.
- all 14 stock effects; PLATE REV, DARK REV and SPRING REV are wrapped by DLWRAP
  so they never run over the loaded code.

AtoMizer on **T8's FX2** passes the audio through: its buffer would cover its own
code there. On the other seven FX2 slots it works.

## Where it has run

Port and `dsp_host` gates only (26 Oct 2026): `verify_atomizer`, `verify_dlstub`,
`verify_dlwrap`, `verify_dlload`. Not flashed.

## Build

```bash
make check REMIX=test/atomizer
```
