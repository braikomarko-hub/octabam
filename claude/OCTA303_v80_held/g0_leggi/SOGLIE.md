# Nota 17 — soglie e attese, scritte PRIMA di girare (9 nov 2026; l'ora della macchina è nel log)

Non ho `g0lib.py` né le tabelle di G0, né `scan4.log`: della scansione ho solo le tre righe che la coordinazione riferisce
(TM3 325 → 185,7 Hz; 364 → 213,3 Hz; 365 → 214,06 Hz; k 0,345–0,350). Lavoro sul gemello (a) (tabelle `gemello_a_tabelle.json`),
che legge le stesse note quasi nello stesso punto ((a)″1, che parte da G0 e ha le leggi tarate: 214,06 Hz, come G0 a 365).

## Che cosa calcolo
- **C1** (il ciclo intero, discreto, lineare): la matrice di un campione del ciclo di `sim.c` (scala MAD / MBD, correttore KLA / KLB,
  le catene TPT dell'anello, lo stato di C25 se c'è il carico), autovalori. Per ogni indice della scala: k di oscillazione,
  frequenza di oscillazione f_osc e frequenza dell'anello a k = KL4[127] (RES massima). Senza carico (G0 / (a), angolo 92 Hz) e con
  il carico (β 250 / 375 / 500, angolo dallo stesso β, KL4 × fK di 4 kHz).
- **C2** le leggi di (a) a C1 n4, dalle tabelle e con una presa di ricerca (`sim_tap.c` = `sim.c` + una variabile di stato che
  rende sv / 64): l'indice del convertitore al punto di taratura (CUT 64, ENV 0, MEG 0), a riposo con ENV 64, e la coda del MEG
  nelle tre finestre.
- **C3** la lettura col calo di (a) a C1 n4 al variare dell'indice della scala (IMAP + d, d = −16 … +8).
- **C4** ricostruzione della scansione di G0 con tre ipotesi su che cosa sia "TM3" nel gemello:
  - H1 = frequenza di oscillazione del ciclo intero all'indice di taratura;
  - H1' = frequenza dell'anello a RES massima;
  - H2 = l'etichetta 20·2^(i/48) (oscillazione della scala senza accoppiamenti).
  Con le leggi di (a) fra il punto di taratura e il fine nota.
- **C5** quanto il k a RES 64 sposta la lettura del taglio (la risposta lineare con KL4[64] scalato da k 0,25 a 0,40).
- **C6** la finestra di Roland (anello di 400–667 Hz a CUT metà, RES massima, ENV / DEC al minimo) tradotta nell'unità di TM3 del
  gemello, prendendo come "unità vera" il ciclo con il carico (β 250 / 375 / 500).
- **C7** il TM3 che servirebbe per leggere 237,5 Hz, sotto H1 / H1' / H2, per G0 e per G1 (β 250 / 375 / 500).

## Controlli di riferimento (se uno non passa, mi fermo)
- **R1** C1 senza accoppiamenti (catene a zero) riproduce i k di oscillazione discreti di `r2.log` all'indice 185: 17,0206
  (senza carico), 23,7200 (β 250), 21,2379 (β 500), entro lo 0,01 %.
- **R2** `sim_tap` con presa 0 = `sim.c`, bit per bit; e la lettura di (a) a d = 0 riproduce la riga "base U" di `g1.log`
  (audio fc 224,19 Hz, k 0,338).
- **R3** le righe Din Sync col calo riproducono `q12.log`.
- **R4** C1: la f_osc del ciclo intero all'indice 180 messa accanto al rapporto "accoppiato" di 15b (~1,50 × fc_St = 1,26 ×
  l'etichetta): solo riportata, non è una soglia (15b usava il modello di Stinchcombe, non il gemello).

## Soglie (prima)
- **Pendenza** (non dipende da nessuna calibrazione): la scansione dà 1,22 ottave di lettura per ottava di TM3. Un'ipotesi passa se
  la sua pendenza ricostruita è entro ±0,08; è esclusa se è fuori di più di 0,15.
- **Livello:** con l'ipotesi che passa la pendenza, la ricostruzione con le leggi di (a) a TM3 325 e 364 deve tornare entro ±3 %
  (G0 ha leggi di ENV un po' diverse da (a): lo scarto si riporta e si dimensiona con C2).
- **Attese 🟡:**
  - H1 o H1' passano la pendenza, H2 no;
  - la finestra di Roland tradotta cade intorno a 380–640 Hz nell'unità di G0;
  - il TM3 che serve è ~400 Hz;
  - il k sposta il taglio letto di meno del 2 %.

## Aggiunta dopo il primo giro (`leggi_run1.log`, 13:57–13:59 dell'orologio della macchina), scritta PRIMA del secondo
- Primo giro: R1–R3 passano.
  - H1 passa la pendenza (1,216 contro 1,22) e il livello (−0,9 % a 325 e a 364).
  - H1' (1,069) e H2 (0,601) sono esclusi.
- Il secondo giro aggiunge solo **C8**, una conversione, senza soglia:
  - il campo 325–365 Hz della nota 15 (derivato come anello, cioè nell'unità H1') e la finestra 400–667 Hz di Roland, letti
    nell'unità H1 del gemello (la frequenza di oscillazione del ciclo intero), con le curve di C1 senza carico;
  - e il rapporto f_osc / anello all'indice di taratura.
- Niente altro cambia.
