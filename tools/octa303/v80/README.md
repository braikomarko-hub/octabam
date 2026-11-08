# OCTA303 v8.0, step 2: the new ladder in integers

The new ladder (M1t matrices + trapezoidal loop + (c''-0) + Q12 once on the linear estimate + TPT couplings G and F)
is the tuning chat's twin "(a) solo circuito" (`claude/OCTA303_v79_gemello_a/` in the Octa303 project: `sim.c`,
`tab.py`, the table json and four reference notes). Not in this repo: the twin and its tables.

- `wtab.py`: the twin's `t.bin` from the table json, in `tab.py write()`'s field order (the four reference notes
  come back with the tuning chat's sha256: paletto 8).
- `ladder_f.py`: the ladder alone in floats, a port of `sim.c`'s `kl_on 4` branch. Check A: it gives the twin's
  filter output (tap 1, with the twin's input x, index and k: taps 4, 6, 7, `pre_s` 0) **exactly**, 18 notes.
- `ladder_i.py`: the same in integers as the ColdFire's EMAC computes it (MACSR 0x20: addend floor(2ab / 2^24),
  read-out floor(acc / 2^8), `tools/emu/ot_emu/v4e.cpp`), 8 guard bits on every signal, rounding by +128
  accumulator units, Q31 / Q30 coefficients, Q26 k, the closed form's reciprocal at the control step.
- Check B (thresholds written before, `SOGLIE_passo2.md`): rms error <= -80 dB and max |error| <= 64 twin units
  (1 LSB of the s16 output) on all 18 notes. Result (`testB.log`): **PASS**, worst -94.26 dB, max 1.13 units.

`gemello_a/OCTA303_v79_gemello_a_tabelle.json`: the twin "(a)"'s full table, as the tuning chat published it in the
Octa303 project on 8 Nov 2026 (moved here, unchanged, to free room in the project). With the twin's `sim.c` and
`wtab.py` it gives the four reference notes bit for bit.
