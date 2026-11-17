# The 303 voice on the DSP (OCTA303 vFable, work in progress)

Code written by Claude. Nothing here is part of an image yet, and nothing here contains or needs an Elektron byte.

The idea (Marko, 17 Nov 2026): the ColdFire keeps the oscillator and the control step; the per-sample filter, VCA
and ceiling move to a DSP insert on FX1. The oscillator travels as the track's audio (L, 24 bits); the per-frame
coefficients travel in the R channel (sixteen 15-bit payloads a frame); slow values travel in the voice record.

| path | what |
|---|---|
| `ref/o3k.c` | a copy of `model_v7/o3k.c` plus `o3d_sample`: the neutral voice's per-sample loop as a DSP56300 computes it (56-bit accumulator, 24-bit registers, fractional multiply, limiting moves). The REFERENCE for the assembly |
| `ref/grid3.py` | phase 2: the reference against today's integer model, 288 cases |
| `ref/prova_a.py` | the R channel's payload decode, exhaustive |
| `voice/o3v.asm.in` | the voice as an FX insert (init / proc), assembled by the repo's `dsp_asm` |
| `voice/prova3.py` | phase 3: the assembled voice on the emulator against the reference, sample by sample |
| `host/o3host.cpp` | a small bench on the vendored dsp56300 emulator library: it loads only this insert (no stock payload) |

```bash
tools/octa303/dsp/build.sh                      # needs the built vendor/dsp56300 (make setup)
python3 tools/octa303/dsp/ref/grid3.py          # phase 2
python3 tools/octa303/dsp/voice/prova3.py       # phase 3
```

## Measured (17 Nov 2026, in the model and on the emulator; nothing on a unit)

- Phase 2, 288 cases: total error at worst 54.9 dB below the signal; per 2048-sample window never above
  max(40 dB under the window's signal, 80 dB under the case's loudest window); 0 saturations.
- Phase 3: 976,896 samples of 12 cases and 256,000 samples of four stress runs (random coefficients, full-scale
  input, about 225,000 limiting moves): 0 samples differ from the reference. Without the engine's signature in the
  voice record the audio passes untouched (a track that is not an OCTA-303); with it, a frame whose mark, checksum
  or low bytes are wrong is silenced. About 148 instructions a sample including the per-frame prologue (an emulator
  count, not chip cycles).

## What the bench cannot see

The stock dispatcher, the other effects, the chip's timing and the registers an insert may clobber. Facts about the
channel (the gain ahead of FX1 follows AMP VOL, the voice record is rewritten every frame, L and R reach FX1 apart)
come from emulator probes on the branch `octa303-dsp-sonda`, not from a unit.

## Open before this can be a module

Instruction forms without a site in a shipping module must be checked against the stock payload; the module build's
own checks (round-trip, norep, label prefixes, verify_init_regs, verify_dirty_state) have not run; the output scale
for FX2 / AMP, VOL and BAL redone after the filter, the ColdFire side and the dEVILish features are not written.
