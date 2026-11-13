# 15c — soglie e attese, scritte PRIMA di girare (9 nov 2026, tra le 12:13 e le 12:18 dell'orologio della macchina)

> **Correzione dell'ora (dopo la revisione).** Qui c'era "~12:30": era sbagliato. Sull'orologio della macchina la cartella e
> `pack.py` sono delle 12:13 e i giri sono delle 12:18 / 12:22 / 12:28 / 12:38 (`q12_run1…4.log`); questa prima sezione è stata
> scritta prima del primo giro, quindi tra le 12:13 e le 12:18. **L'ordine delle sezioni si può controllare solo dal contenuto, non
> dalle date dei file:** ogni aggiunta cita il log del giro prima e ne riporta numeri, e la data del file `SOGLIE.md` è solo quella
> dell'ultima modifica. Della soglia della correlazione (quarta aggiunta) vedi la nota 15c, punto 3: l'ho scritta dopo aver già
> visto i numeri della lettura semplice, che c'erano in ogni giro dal primo.

Gemello: (a) (`sim.c` sha256 063b60ff…, tabelle `gemello_a/tabelle.json` md5 cd080b14…). Le tabelle di (a)″1 non le ho.
Nota: C2 65,62 Hz, dente, CUT / RES / ENV / DEC 64, normale; finestre 900–1100, 1000–1200, 1050–1250 ms (come 15b).
Verità per finestra: fc_lin = curva sulla risposta lineare esatta (come `risposta.py`) a ogni indice intero visitato nella finestra,
media geometrica pesata sul tempo passato a ogni indice; stesso insieme di armoniche usato dal fit dell'audio.

Due modi di lettura:
- **LM**: livello portato a quello di Din Sync (h1 uguale alla media di h1 di C1/C3/C5 n4 nelle stesse finestre), soglia −90 dB, NH 40
  (la condizione di B2);
- **N20**: le prime 20 armoniche, senza soglia (il livello non conta).

Varianti (`pack.py` key=value):
| nome | che cosa cambia | serve a |
|---|---|---|
| base | niente | partenza |
| q12lin | kl_q12 = 0 (Q12 = identità) | domanda 1 |
| outlin | vsat = 0, p6lim = p6hi = 1e30 (uscita lineare) | le altre non linearità |
| lin | q12lin + outlin | tutto lineare: resta solo il tempo (inviluppi, indice a gradini) e la finestra |
| half | gin / 2 | dipende dal livello? |
| half_outlin | gin / 2 + outlin | livello solo su Q12 |
| env0 | ENV 0 (indice fermo) | la fase senza spazzata |

Soglie:
- **"lo scarto sparisce"**: media sulle 9 finestre entro ±0,5 % da fc_lin e nessuna finestra oltre ±1,0 %.
- **"lo scarto si riduce col livello"**: |media half| ≤ 0,7 × |media base| (con Q12 come tanh, metà livello ≈ metà compressione).
- **effetto della fase**: escursione (max − min) su 6 fasi per finestra; "conta" se > 1,0 %, "non conta" se ≤ 0,3 %.
- **finestra spostata di frazioni di periodo** (8 passi di 1/8 di periodo, stessa nota): per un segnale periodico fermo la lettura a
  minimi quadrati non cambia (escursione ≤ 0,1 %); se cambia, conta il non-fermo (inviluppi).

Attese:
1. Se Q12 è la causa: q12lin e lin dentro ±0,5 %; base e half_outlin con lo scarto, half ~metà.
2. Se lo scarto resta in lin: non è non linearità; restano la variazione nel tempo (MEG / VEG, indice intero che salta, LG che
   salta) e la finestra.
3. Fase: in un sistema fermo (anche non lineare) la fase iniziale sposta solo il tempo, quindi la lettura non dovrebbe cambiare; se
   cambia, la causa è ciò che varia nel tempo (inviluppo e indice) rispetto alla forma d'onda. Attesa: escursione piccola in env0.
4. Prima di tutto: (a) in modo LM mostra lo scarto unilaterale −2,4 % di B2 su (a)″1? Se no, lo dico e la risposta vale solo per (a).

## Aggiunta dopo il primo giro (`q12_run1.log`), scritta PRIMA del secondo
Il primo giro ha mostrato che anche la variante tutta lineare cambia lettura con la fase (escursione 1,4–3,8 %). Per decidere se è la
variazione nel tempo aggiungo tre varianti:
| nome | che cosa | attesa |
|---|---|---|
| stat_lin | lineare + ENV 0 + veg = 1 (niente MEG, niente VEG: segnale periodico fermo) | escursione di fase ≤ 0,4 % (un passo di griglia 0,35 %) |
| stat_base | come base + ENV 0 + veg = 1 (non lineare ma fermo) | idem: un sistema fermo, anche non lineare, non dipende dalla fase |
| lin_veg1 | lineare, ENV 64, veg = 1 (resta solo l'indice che scende a gradini) | in mezzo |
Se stat_lin e stat_base hanno escursione ≤ 0,4 %, la dipendenza dalla fase viene dalla variazione nel tempo dentro la finestra
(MEG / VEG), non da Q12 né dalla finestra in sé.

## Aggiunta dopo il secondo giro (`q12_run2.log`), scritta PRIMA del terzo
Il secondo giro: i segnali fermi (stat_lin, stat_base) hanno escursione di fase 0,00 %; lin_veg1 ≤ 0,35 %. Quindi la fase conta per via
del VEG che cala dentro la finestra. Per misurare ogni non linearità senza quel rumore, tutte con veg = 1 e ENV 64 (indice vero):
| nome | che cosa | serve a |
|---|---|---|
| q12_veg1 | Q12 acceso, uscita lineare | effetto di Q12 da solo = q12_veg1 − lin_veg1 |
| q12_veg1_half | idem con gin / 2 | Q12 dipende dal livello? attesa ~1/4 dell'effetto (tanh: termine di terzo ordine ∝ livello²) |
| out_veg1 | Q12 lineare, vsat acceso, p6lim e p6hi ÷ 0,494 | l'uscita da sola al livello vero della finestra (VEG a 1,1 s = 0,9997673^(1,1·44100/16) = 0,494; vsat sta prima del VCA, p6 dopo) |
| base_veg1 | Q12 + vsat + p6 ÷ 0,494 | tutto non lineare, fermo |
Soglia "Q12 è la causa dello scarto negativo": q12_veg1 − lin_veg1 ≤ −1,5 % e q12_veg1_half più vicino a 0 di almeno metà.
Stimatore con media su 8 spostamenti di 1/8 di periodo (livelli in dB mediati, poi un solo fit), su base e lin con VEG vero:
attesa escursione di fase ≤ 0,7 % (metà o meno di quella senza media).

## Aggiunta dopo il terzo giro (`q12_run3.log`), scritta PRIMA del quarto
La media su 8 spostamenti NON ha passato la soglia (escursione 2,04 % su base, 2,07 % su lin; attesa ≤ 0,7 %). Provo invece una
lettura delle armoniche che sa del calo: minimi quadrati con, per ogni armonica, coseno e seno più coseno·t e seno·t (t centrato
nella finestra), più DC e DC·t; il livello è l'ampiezza al centro della finestra. Solo per misurare, non è una proposta.
Attese (prima): su lin escursione di fase ≤ 0,7 % e media entro ±0,5 %; su lin_veg1 / stat_lin nessun peggioramento (≤ 0,4 %);
su Din Sync escursione con la finestra spostata minore di quella della lettura semplice (1,4–3,5 %).

## Aggiunta dopo il quarto giro (`q12_run4.log`), scritta PRIMA del quinto (l'ultimo)
La lettura che sa del calo ha passato le soglie (lin: media +0,12 %, max +0,64 %, escursione ≤ 0,70 %; Din Sync: escursione 0,00–0,35 %).
Rifaccio con essa il confronto della forma dei residui (armoniche 1–14) fra Din Sync n4 e le varianti del gemello.
Soglia (prima): "Din Sync porta la firma di Q12" se corr(Din Sync, outlin) ≥ 0,7 e supera di almeno 0,3 sia corr con q12lin sia
corr con lin. Altrimenti "non si vede". Debolezza già nota: 14 punti, forme lisce, correlazioni alte vengono facili.
Aggiungo anche l'andamento dentro la nota (finestra 1 → 3) letto così su Din Sync e sul gemello, solo come dato: è confuso dal MEG.
