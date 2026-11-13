# Come rifare la nota 18 (cartella ricerca/v80/g1_regole)

Tutto in questa cartella; fuori solo le registrazioni Din Sync (`x0xref/SET-*.wav`).

```
cd g1_regole
gcc -O2 -o sim sim.c -lm; gcc -O2 -o sim_tap sim_tap.c -lm; gcc -O2 -o sim_q21 sim_q21.c -lm
python3 -I f18.py gemello_a_tabelle.json <x0xref> onsets.json > f18.log    # ~2 minuti
python3 -I b3.py  gemello_a_tabelle.json <x0xref> onsets.json > b3.log     # ~1 minuto
```

- `lib18.py`: le funzioni di `g0_leggi/leggi.py` copiate senza cambi (lettura col calo, tavole caricate, rendering, matrice del
  ciclo `step_fn`, `kosc`, `ring`). `leggi_ref.py` è la copia intera di `leggi.py`, per confronto; `leggi.log` quella del suo log.
- `f18.py`: A / A2 (unità e campo di TM3 per G1), B / B2 (margine in cima con gli accoppiamenti, fK con e senza accoppiamenti),
  C (quanto l'anello di taratura dipende da KL4).
- `b3.py`: il margine in cima con il fK **con gli accoppiamenti** (scritto dopo `f18.log`, vedi l'aggiunta in `SOGLIE.md`).
- `g1_input.log` = `g1_carico/g1.log` (letti i fK senza accoppiamenti).
- `f18_check.log`, `b3_check.log`: gli stessi comandi rigirati dalla cartella pulita, identici salvo le righe con l'ora.
- `sim.c`, `sim_tap.c`, `sim_q21.c`, `q21tab.py`, `ris/`, `risonanza_accento/`, `gemello_a_tabelle.json`, `onsets.json`: come in
  `g0_leggi`.
