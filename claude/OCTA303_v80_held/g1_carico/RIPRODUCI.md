# Come rifare il calcolo di G1 (addendum della nota 16; cartella ricerca/v80/g1_carico)

Tutto in questa cartella. Fuori ci sono solo le registrazioni Din Sync (`x0xref/SET-*.wav`), come in 15b e 15c.

```
cd g1_carico
gcc -O2 -o sim sim.c -lm            # il gemello (a), sha256 063b60ff...
gcc -O2 -o sim_q21 sim_q21.c -lm    # il gemello con il carico di Q21, dal pacchetto Q21 (sha256 51e9480c...)
python3 -I g1.py gemello_a_tabelle.json <x0xref> onsets.json > g1.log   # ~3 minuti
```

- `g1.py` (sha256 4e7c02c2…): tavole caricate (come `wq21.apply`, con `q21tab.py` del pacchetto, sha256 46edfcc4…), angolo dallo stesso
  β, fattori di KL4, rendering, lettura col calo di 15c, risposta lineare esatta con lo stato di C25, scansione di TM3, controlli T1–T5.
- `ris/`, `risonanza_accento/`, `gemello_a_tabelle.json`, `onsets.json`: copie identiche di quelle di `g0_q12`.
- `SOGLIE.md`: soglie, controlli e attese, scritte prima del primo giro; un'aggiunta prima del secondo.
- `g1_run1.log`: il primo giro (scansione d = 0 … −10). `g1.log`: il secondo (d = +4 … −10). Le righe prima della scansione
  sono identiche nei due giri, salvo l'ora (controllato con `diff`); le righe della scansione per d da 0 a −10 sono le stesse.
- `g1_check.log`: lo stesso comando rigirato dalla cartella pulita: identico a `g1.log` salvo le due righe con l'ora (diff).
- Le due righe con l'ora della macchina ("run started / ended") cambiano a ogni giro; tutto il resto deve tornare identico.
