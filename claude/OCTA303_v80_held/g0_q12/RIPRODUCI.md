# Come rifare la nota 15c (cartella ricerca/v80/g0_q12)

Tutto in questa cartella. Fuori ci sono solo le registrazioni Din Sync (`x0xref/SET-*.wav`, le stesse di 15 e 15b; non le copio).

```
cd g0_q12
gcc -O2 -o sim sim.c -lm                      # sim.c = il gemello, sha256 063b60ff... (uguale al pacchetto pubblicato)
python3 -I q12.py . gemello_a_tabelle.json <x0xref> onsets.json > q12.log      # ~10 minuti
```

- `q12.py`: tutte le varianti, le letture e i confronti. Chiama `pack.py` per le tabelle di ogni variante.
  sha256: `q12.py` e5bfdaff9a2b…, `pack.py` 4ac03b25ddaa…, `sim.c` 063b60ff0eb4…, `q12.log` 209ffa8b7ebf….
- `gemello_a_tabelle.json` = le tabelle di (a) (md5 cd080b14…, le stesse di `gemello_a/tabelle.json` e del pacchetto).
- `ris/stin.py`, `ris/klaw.py`, `risonanza_accento/smorza.py`: il modello di curva (copie senza cambi).
- `onsets.json`: gli attacchi delle note Din Sync (copia di `fit8/onsets.json`).
- `SOGLIE.md`: soglie e attese, scritte prima di ogni giro (quattro aggiunte, una per giro).
- `q12_run1.log` … `q12_run4.log`: i giri intermedi, fatti con versioni più corte di `q12.py`. Ogni loro riga c'è identica in
  `q12.log` (controllato: 0 righe mancanti), quindi `q12.log` dell'ultima versione basta per rifare ogni numero.
- `q12_check.log`: lo stesso comando rigirato dalla cartella copiata; deve essere identico a `q12.log` (`cmp`).

Per (a)″1: lo stesso comando con il JSON delle sue tabelle al posto di `gemello_a_tabelle.json`.
