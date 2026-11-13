# How to reproduce note 15b (ricerca/v80/g0_tm3)
All paths relative to this folder; RD = the ricerca dir (contains ris/ and risonanza_accento/), x0xref and fit8/onsets.json as in the scratchpad.
- Din Sync, whole-curve fit: `NH=40 python3 -I curva.py RD x0xref onsets.json > curva_nh40.log` (= curva.log); `NH=20 ... > curva_nh20.log`.
  (curva.py reads NH from the environment, default 40; it prints both the peak metric and the whole-curve fit.)
- Twin audio: `cd twin; gcc -O2 -o sim sim.c -lm; python3 -I pack.py TABLES sim.c a.bin; ... a_li.bin kl_tap=6; ... a_k.bin kl_tap=7`
  (TABLES = scratchpad/gemello_a/tabelle.json, (a)'s tables); then `NH=20 python3 -I prova.py RD > prova_nh20.log` and NH=40.
- Twin exact linear response (no constant): `python3 -I risposta.py RD TABLES > risposta.log`.
