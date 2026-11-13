# G1 calcolato — soglie e attese, scritte PRIMA di girare (9 nov 2026, prima del primo giro; ora della macchina nel log)

Che cosa: il gemello (a) con il carico di Q21 (`sim_q21.c` del pacchetto, sha256 51e9480c…; tabelle caricate da `q21tab.py`
del pacchetto, sha256 46edfcc4…, con lo stato di C25 come in `wq21.apply`), l'angolo dell'anello e dell'uscita dallo stesso β
(`kl_lhp[0]`, `kl_fhp[0]` = polo TPT a 1/(2π C25 R_lato): 82,4 / 60,2 / 49,2 Hz per β 250 / 375 / 500) e KL4 moltiplicato per
un fattore fK. Contro lo stesso gemello senza carico (q21_on = 0, angolo 92 Hz: è (a)). Non ho le tabelle di G0: misuro su (a) lo
**spostamento** G1 − base, che è la domanda delle previsioni 1 e 2 della nota 16.

fK ("KL4 ricavato con il carico sopra 4 kHz"), due estremi, più 1 per separare: il rapporto k_osc caricato / scarico dell'anello
continuo (la funzione `kosc_cont` di `r2.py`, copiata) all'indice 370 (4183 Hz) e all'indice 444 (12 177 Hz). Il valore vero
dipende dalle note sopra 4 kHz che la chat delle tarature usa: sta fra i due.

Varianti: base U; per β 250 / 375 / 500: "solo carico" (angolo 92 Hz, fK 1), "carico + angolo" (fK 1), "G1" con fK al valore di
12 kHz e di 4 kHz. Più "G1 lineare" (Q12 = identità, uscita lineare, veg = 1) per β 250, fK 4 kHz, solo per il controllo T5.

Lettura: quella col calo di 15c (`harm_ramp`, livello di Din Sync −37,28 dB su h1, soglia −90 dB, griglia fine), fasi 0 / 0,33 / 0,67,
finestre 900–1100, 1000–1200, 1050–1250 ms. Riduzione come nel quarto TM3: mediana sulle 3 finestre (per fase), poi la media
sulle 3 fasi (le tre note C1/C3/C5 sono la stessa nota nel gemello). Risposta lineare esatta: la forma di `risposta.py` con, in più,
lo stato di C25: Y4 = (P·Bv)₄ / (1 − (P·Bc)₄ z⁻¹ L(z)), P = (I − A z⁻¹)⁻¹, L = il passa-basso TPT di C25; armoniche 1–15.

TM3 riletto: TM3 sposta tutti i tagli dello stesso rapporto (cap. 7: I_E10 ∝ 1/(R73 + TM3)), quindi nel gemello è uno spostamento
uguale dell'indice della scala: IMAP + Δ (Δ = 0, −1, …, −10; dal secondo giro +4 … −10). Δ* = lo spostamento (interpolato) per cui la lettura di G1 torna quella
della base; TM3_G1 / TM3_G0 = 2^(Δ*/48). Per la risposta lineare lo stesso con l'indice frazionario (interpolato fra interi).

## Controlli di riferimento (se uno non passa, mi fermo e lo scrivo)
- **T1** `sim_q21` con q21_on = 0 sulle tabelle di (a) dà lo stesso audio di `sim.c`, bit per bit (sha256 uguale).
- **T2** la mia risposta lineare senza carico riproduce la riga di `risposta.log` "index 180 … NH 20: k 0.370 fc_St 227.8 Hz
  (rms 0.024 dB)" con 20 armoniche.
- **T3** la lettura col calo (con la pseudo-inversa calcolata una volta) riproduce identiche le 4 righe di `q12.log` "Din Sync,
  drift-aware reading, the 3 windows".
- **T4** con il carico a β = 0 (rho = 0, BC = 0) la mia risposta lineare è uguale a quella senza carico (max |differenza| ≤ 1e-9).
- **T5** "G1 lineare": audio letto col calo contro la risposta lineare caricata, stesse armoniche: ogni finestra entro ±0,70 %
  (due passi di griglia; 15c: lin a +0,12 % di media, max 0,64 %). Prova che la mia risposta caricata è quella del gemello.

## Attese (le previsioni della nota 16, scritte prima di questo calcolo; qui non si spostano)
- taglio letto allo stesso TM3, G1 − base: da −2 a +9 % (più probabile +4…+8 % per β ≤ 350);
- k letto: −0,03…−0,10 (G1 a 0,24–0,31);
- TM3 riletto: da −9 a +2 % (più probabile −4…−7 %).
Il calcolo **stringe** queste forbici; se cade fuori, la previsione è smentita e lo scrivo così.

## Aggiunta dopo il primo giro (`g1_run1.log`, 13:34–13:36 dell'orologio della macchina), scritta PRIMA del secondo
Il primo giro: T1–T5 passano. Per β 500 la lettura di G1 allo stesso TM3 sta **sotto** quella della base, quindi lo spostamento che
la riporta è positivo e la scansione (d da 0 a −10) non lo contiene ("none"). Il secondo giro allarga solo la scansione a
d = +4 … −10, per tutte le varianti G1. Niente altro cambia: soglie, attese, letture e varianti sono le stesse.
