# Nota 19 — soglie e attese, scritte PRIMA (9 nov 2026)

Non ho `diag/per_nota.tsv`, `tabella.log`, `classi.log` (stanno nel progetto, non nel mio disco). Qui solo: (1) aritmetica dalle
cifre già scritte (cap. 7, nota 13): quale frazione della pista A a 3/4 di corsa (VR3, VR5) darebbe le nodi tarate di (a); (2) la
lista, dal disegno dei set, delle note della metà A che separano le manopole; (3) le soglie dell'analisi per nota, da fare quando
avrò `per_nota.tsv`.

## (1) Aritmetica (conti19.py, nessuna simulazione)
- CUT (cap. 7): I ∝ V_c − 3,8 V, V_c = 4,73 + 7,27·g (g = frazione della pista di VR3). Ottave da CUT 0: log2((0,93 + 7,27 g)/0,93).
- ENV (cap. 7): spazzata = 0,94 + (5,6 − 0,94)·g, riposo = −0,31 − (1,84 − 0,31)·g (g = frazione della pista di VR5).
- Per ogni nodo: la g che dà il valore del circuito (nota 13) e quella che dà il valore di (a). Controllo: il riposo previsto dalla g
  della spazzata di (a) a ENV 95 contro il riposo di (a) (−1,28).
- Attesa 🟡: a 3/4 (nodi 95) la g di (a) sta sopra il 40 % del circuito, dentro o al bordo del campo onesto 30–60 % (nota 13);
  a 127 la g è 1 per tutti e due (la pista non conta).

## (3) Soglie per l'analisi per nota (prima di vedere il file)
- Classi dal disegno dei set (riga = livello di tutte le manopole meno una; numero = la manopola mossa; note 8–15 = manopola mossa
  a 95 / 127):
  - SOLO-CUT = A1 n8–15, C1 n8–15;
  - SOLO-ENV = A3 n8–15, C3 n8–15;
  - SOLO-RES = B2 n8–15;
  - BASSE = A1 n0–7, A3 n0–7 (tutto ≤ 32);
  - TUTTO-ALTO = le note della metà A con CUT, ENV e RES ≥ 95.
- Per il gruppo X ("aggiungi uno"): costo medio per nota in ogni classe. Rumore = deviazione standard del costo di X sulle note
  BASSE.
- "Si separa" se il gruppo CUT costa sulle SOLO-CUT più che sulle SOLO-ENV di più di 2 × rumore, **e** il gruppo ENV fa il contrario.
  Altrimenti la confusione resta e servono note nuove.
- Previsione della pista A 🟡: per i gruppi CUT ed ENV, le note con la manopola a 95 costano più di quelle a 127 (a 127 la pista non
  conta). Smentita se costano di più quelle a 127.

## Aggiunta (9 nov, dopo l'arrivo di `da_progetto/per_nota_c40.tsv`), scritta PRIMA di qualunque conto su quel file
Dichiarato: per controllare il file ho stampato `mk_c40.py`, che contiene tutti i valori trascritti. Li ho quindi visti scorrere,
ma non ho calcolato niente.
- **Correzione di una classe scritta prima:** "BASSE = A1 n0–7, A3 n0–7" era sbagliata. Le note 4–7 hanno la manopola mossa a 64.
  BASSE diventa: A1 n0–3 (CUT 32), A3 n0–3 (ENV 32), A5 n0–15 (tutte le manopole a 0; ACC mossa solo sugli accenti). Sono note con
  CUT, ENV e RES ≤ 32.
- Costo per nota del gruppo X = add_X − R0 (cells40 della nota). Rumore = deviazione standard di quel costo sulle BASSE.
- **Domanda 5 (la cresta della nota 17 B), soglie:**
  - se (a)″1 compensa il k troppo alto con un taglio troppo basso, il costo di ANCH (il taglio portato a Din Sync con k ancora
    0,35) deve **crescere con RES** a parità delle altre manopole;
  - le serie pulite sono B2 (CUT / ENV / DEC / ACC 32; RES 32 / 64 / 95 / 127 su n0–3 / 4–7 / 8–11 / 12–15) e D2 (le altre a 95);
  - "cresta vista" se in **tutte e due** le serie il costo medio di ANCH a RES 127 supera quello a RES 32 di più di 2 × rumore, e la
    pendenza (minimi quadrati sui 16 punti) è positiva;
  - "cresta non vista" se in almeno una serie è il contrario oltre 2 × rumore; altrimenti "non si legge";
  - accanto: il costo di ANCH sulle note "tutte a 64" (C1 n4–7, C3 n4–7, C5 n0–15), cioè le condizioni dell'ancora.
- Ogni risultato che sta a meno di 1 × rumore dalla sua soglia lo dichiaro **marginale** e scrivo le note su cui si regge, perché la
  coordinazione le possa ricontrollare contro l'originale.

## Aggiunta dopo `per19.log`: un conto in più, dichiarato DOPO aver visto i risultati (solo informazione, nessuna soglia)
Il gruppo CUT costa di più sulle SOLO-RES (B2 n8–15: CUT 32, RES 95 / 127), cioè a CUT basso. È proprio la frase di H-a. `post19.py`
divide il costo del gruppo CUT (e di ANCH) per livello di CUT e per "CUT ≤ 32 e RES ≥ 64", come H-a era stato scritto. È fatto dopo
aver visto i dati, quindi non vale come prova: dice solo dove sta il costo.
