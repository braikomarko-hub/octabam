# Come rifare la nota 17 (cartella ricerca/v80/g0_leggi)

Tutto in questa cartella; fuori solo le registrazioni Din Sync (`x0xref/SET-*.wav`).

```
cd g0_leggi
gcc -O2 -o sim sim.c -lm            # il gemello (a), sha256 063b60ff...
gcc -O2 -o sim_tap sim_tap.c -lm    # = sim.c + una variabile di STATO che rende sv/64 con kl_tap 8 (sha256 414539a8...); con
                                    #   kl_tap 0 dà lo stesso audio di sim.c (controllo R2 nel log)
gcc -O2 -o sim_q21 sim_q21.c -lm    # il gemello con il carico di Q21, dal pacchetto Q21 (sha256 51e9480c...)
python3 -I leggi.py gemello_a_tabelle.json <x0xref> onsets.json > leggi.log   # ~2 minuti
```

- `leggi.py` (sha256 c2246b77…): C1–C8 e i controlli R1–R4 (vedi `SOGLIE.md`).
- `g1_input.log` = copia di `g1_carico/g1.log` (letti solo i fattori fK); `g1_ref.py` = copia di `g1_carico/g1.py` (per chi
  confronta le funzioni copiate).
- `q21tab.py`, `sim_q21.c`: dal pacchetto Q21, senza cambi. `ris/`, `risonanza_accento/`, `gemello_a_tabelle.json`,
  `onsets.json`: come in `g0_q12`.
- `leggi_run1.log`: il primo giro (senza C8). `leggi.log`: il secondo; prima di C8 è identico al primo, salvo l'ora e una riga
  vuota (controllato con `diff`).
- `leggi_check.log`: lo stesso comando rigirato dalla cartella pulita; identico a `leggi.log` salvo le due righe con l'ora.
- Le righe "run started / ended" portano l'ora della macchina e cambiano a ogni giro.
