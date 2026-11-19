# OCTA303 hybrid: the smooth chain on the DSP (coordination, research bench)

Code written by Claude. Nothing here is part of an image, and nothing here contains or needs an Elektron byte or a
Din Sync recording.

Marko's request (19 Nov 2026): OCTA303 "liscia", hybrid, without dEVILish. The ColdFire keeps the oscillator, the
control step and everything up to `u` (after the input highpass and OVDR's gain); the per-sample chain after it
(the resonance and its highpass, the ladder's clip, the 4-stage ladder, the VCA's input pair, the level, the OTA,
the VCA, pin 6, the output coupling and the output clamp) runs on the DSP56300, at the source seam (as ANALOG BD).
Step 2 = this bench: the chain in DSP assembly against `ref303.py`, before any glue, module or image.

| file | what |
|---|---|
| `split303.py` | `ref303.sample` cut in two: `cf_front(st) -> u`, `dsp_chain(st, u)`; ref303's own integer arithmetic |
| `check_split.py` | the cut changes nothing: split == ref303 on the judge's half-A notes |
| `stress.py`, `extreme.py`, `cover.py` | peaks of every stored value (music, random runs, the player's corners) and branch coverage |
| `gen_o3c.py` | generates `o3c.asm`: the chain, integer-exact (method in its docstring) |
| `o3chost.cpp` | the bench: the chain alone on the vendored dsp56300 emulator, piece by piece |
| `vectors.py`, `synth.py`, `cmp.py` | bench vectors from ref303 (music; synthetic edge cases) and the compare |

The judge's note list and split (`O3_GIUDICE`) and its ref303 adapter (`O3_MOTORI`) are private (derived from Din
Sync's recordings): not in the repo.

```bash
V=vendor/dsp56300   # built (make setup)
g++ -std=c++17 -O2 -I$V/source -I$V/source/asmjit/src tools/octa303/ibrido/o3chost.cpp -o o3chost \
    $V/build/source/dsp56kEmu/libdsp56kEmu.a $V/build/source/dsp56kBase/libdsp56kBase.a $V/build/source/asmjit/libasmjit.a -lpthread -ldl
python3 tools/octa303/ibrido/gen_o3c.py o3c.asm && $V/build/source/dsp_host/dsp_asm -in o3c.asm -org 100 -out o3c.bin
python3 tools/octa303/ibrido/vectors.py full 208 55125 40 3000 && ./o3chost o3c.bin 100 100 ytab.bin full.in full.out dis.txt
python3 tools/octa303/ibrido/cmp.py full
```
(`ytab.bin`: P6_F at Y:0x800 and P6_FP at Y:0x910, int32 words; see the step-2 report for the one-liner.)

## Measured (19 Nov 2026, emulator only; nothing on a unit)
- The cut: identical to ref303 on 208 notes x 20,000 samples.
- The chain on the emulator against ref303: **0 differing samples** in 13,384,960 (208 judge notes x 55,125 + 40
  random runs with split frames, knob jumps, saw and square) and in all 159 synthetic runs that stay in the engine's
  domain (the other 41 drive a state past 2^23 on purpose: out of the engine's range).
- 302 P words (the chain and its soft clip; no glue). 269.7 emulator instructions a sample, mean, the piece's
  prologue included (emulator instructions, not chip cycles).
- Largest stored value at the player's corners (`extreme.py`): y1 at 0.39 of 2^23.
