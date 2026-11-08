# v8.0 step 3: the new ladder inside ref303.py, against the twin (a)

Thresholds written before the results: `SOGLIE_passo3.md`. Written by Claude, 8 Nov 2026.

```
# the twin (sim.c, table json from ../gemello_a, written with ../wtab.py)
python3 ../wtab.py ../gemello_a/OCTA303_v79_gemello_a_tabelle.json t.bin
python3 mk_base.py ../gemello_a/OCTA303_v79_gemello_a_tabelle.json <v7.9 tools/octa303> t_base.bin
cc -O2 -o sim <the twin's sim.c> -lm
./sim t.bin n_all.txt o_a.f32 ; ./sim t_base.bin n_all.txt o_base.f32 ; ./sim t.bin n_new.txt o_new.f32
# the engine
python3 render_eng.py <v7.9 tools/octa303> n_all.txt y_v79.npy
python3 render_eng.py <v8.0 tools/octa303> n_all.txt y_v80.npy
python3 render_eng.py <v8.0 tools/octa303> n_new.txt y_new.npy
python3 cmp3.py ; python3 cmp3b.py
```

Results (logs here):
- point 0 (base) did not hold on 5 notes: `cmp3.log`. Tables of the old ladder identical to v7.9's, so the old ladder
  itself, at the attack with CUT/ENV/RES 127, does not follow its float twin. Step-3 verdict on these notes not given.
- point 3b (24 new notes, threshold written before rendering them): PASS, worst E -36.54 dB, P <= 0.020 dB: `cmp3b.log`.
