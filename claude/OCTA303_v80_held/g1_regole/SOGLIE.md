# Nota 18 — soglie e attese, scritte PRIMA di girare (9 nov 2026; ora della macchina nel log)

Gemello (a) e pacchetto Q21, come in `g1_carico` e `g0_leggi`. Non ho i file della chat delle tarature in `g0/c/` (g0tab.py,
conv.py, conv_g0.log): uso il gemello (a), che per f_osc e per l'anello coincide con G0 (§43.21 riferito: f_osc uguale, anello
≤ 0,1 Hz, KL4[127] 17,012 contro 17,017 di (a)).

## Che cosa calcolo (`f18.py`)
- **A (domanda 1)** per ogni modello M (U = senza carico; G1 β 250 / 375 / 500 con l'angolo dallo stesso β, KL4 × fK a 12 kHz e a
  4 kHz):
  - la lettura col calo a C1 n4 al variare dell'indice (IMAP + d);
  - per una lettura data (233 e 250 Hz, l'ingresso della nota 15; e 237,52 Hz, il bersaglio) l'indice di taratura che la dà, e
    l'anello del ciclo del modello stesso a RES 127 su quell'indice (con il suo KL4[127]).
  - Il campo di G1 "rifatto come nella nota 15" = 325–365 Hz × anello_G1 / anello_U alla stessa lettura (solo il passo del ciclo
    cambia; riposo di ENV, coda del MEG e pista di VR5 restano quelli della nota 15). Riporto anche l'anello del gemello senza
    carico per 233 / 250 Hz, accanto al 325–365 della nota 15, come controllo della conversione della nota 15.
- **B (domanda 2)** il margine di stabilità con gli accoppiamenti: k_osc del ciclo intero (`step_fn` di `leggi.py`) diviso
  KL4[127]·fK, meno 1, all'indice 445 e il minimo sugli indici 300–445; U, G1 β × fK {12k, 4k}. Accanto, senza accoppiamenti, per
  rifare il conto della nota 16. I fK con gli accoppiamenti (k_osc caricato / scarico agli indici 365 / 370 / 375 e 444).
- **C (domanda 4)** quanto l'anello a RES 127 all'indice di taratura dipende da KL4[127] (×1,00 / ×1,01 / ×1,03): dice se
  TM3 va fissato dopo KL4.

## Controlli di riferimento
- **R1** la lettura di U a d = 0 = 224,19 Hz / k 0,338 (`g1.log`, `leggi.log`).
- **R2** f_osc e anello di U all'indice 190 = quelli di `leggi.log` (383,2 / 335,1 Hz).
- **R3** il k_osc senza accoppiamenti all'indice 185 = `r2.log` (17,0206 / 23,7200 / 21,2379).

## Soglie (prima)
- **Stabile:** margine con gli accoppiamenti > 0 a ogni indice 300–445. Margine "stretto" se < 0,5 % (quello di (a) senza
  accoppiamenti in cima: 0,53 %).
- **Ordine:** TM3 dipende da KL4 se l'anello all'indice di taratura cambia più di un passo della griglia fine (0,35 %) per
  KL4 × 1,03.
- **Attese 🟡:**
  - per G1 il campo in anello caricato scende con β basso (anello 320 / 338 / 348 per β 250 / 375 / 500 al bersaglio, nota 17);
  - con gli accoppiamenti il margine in cima è simile al conto senza (in cima gli accoppiamenti valgono ~1);
  - fK a 4 kHz rende stretto o negativo il margine a β 250.

## Aggiunta dopo `f18.log` (14:50–14:52 dell'orologio della macchina), scritta PRIMA di `b3.py`
`f18.log` mostra che i fK con gli accoppiamenti (B2) sono più piccoli di quelli senza, che sono quelli usati in `g1_carico` e in A/B.
`b3.py` rifà solo il margine in cima (indice 445, accoppiamenti) con KL4 × il fK **con gli accoppiamenti** a 4 kHz (indice 370) e a
12 kHz (indice 444), per β 250 / 375 / 500. Stessa soglia: stabile se il margine è > 0; "stretto" se è sotto lo 0,5 %.
