# `ids64` -- BBD on id 0x25

BBD beside the stock effects, in an image built with `id_space=64` and BBD pinned to FX2 id `0x25`.

## What is in it

- **BBD** -- [`modules/bbd/README.md`](../../../modules/bbd/README.md), on `0x25` through `Remix.ids`.
- the stock effects as in [`bbd`](../bbd/README.md).

## Status

Port only; not flashed. In the port with this image and the stock project: id `0x25` poked into T1 makes core 1 run BBD's process entry every frame (`r1 = 0x25`), and the firmware's descriptor resolver returns BBD's descriptor for it. The grown blob chain, the SRAM-init cave and the X record at `X:0x8da0` are unproven on hardware (`docs/contributing/PLACEMENT.md`, "The 64-id layout").

## Build

```bash
make check REMIX=ids64
```
