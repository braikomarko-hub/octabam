# Nota 20 (GT, la pista A) — soglie e attese, scritte PRIMA del conto (9 nov 2026, ~15:55 sull'orologio della coordinazione, UTC+2)

Orario corretto il 9 nov, 16:03: l'etichetta di prima era avanti rispetto all'orologio.

`taper.py` è solo aritmetica: la famiglia di piste proposta e le leggi del cap. 7, nessuna simulazione.

- **Controllo di riferimento T1:** con s = 0 (la pista esponenziale con il 15 % a metà, quella di G0), le leggi del cap. 7 devono
  ridare le nodi del circuito della nota 13, entro 0,03 ottave:
  - CUT 0 / +0,44 / +1,14 / +2,05 / +3,15;
  - ENV spazzata 0,93 / 1,14 / 1,64 / 2,78 / 5,58; riposo −0,30 / −0,37 / −0,54 / −0,91 / −1,82.
  Se non tornano, la famiglia non è quella di G0 e mi fermo.
- **T2:** f(0) = 0, f(1) = 1, f(0,5) = 0,15 per ogni s; f cresce con x.
- **Attese 🟡:**
  - a 3/4 di corsa g va da 0,40 (s = 0) a ~0,57 (s = 1); a 1/4 sale anche lui (da ~0,044 a ~0,076);
  - il rapporto riposo / spazzata resta ~0,33 per ogni s, quindi off_b non dipende dalla pista;
  - con TM3 fisso, il nodo di CUT 64 si sposta di meno di 4 passi j (0,005 ottave l'uno) da s = 0 a s = 1.

## Aggiunta (~15:59 sull'orologio della coordinazione), dopo l'estratto di g0lib e PRIMA di `taper2.py`
In g0lib non c'è nessuna frazione del cursore. Ci sono due tavole (SHAPE e SLO della nota 13), e c2 = label(TM3)·2^(off64·slo0).
- **T3:** la forma "assoluta" (le leggi del cap. 7 con f(x; 0)) deve ridare SHAPE e SLO entro 0,02 ottave (l'arrotondamento a 2
  decimali della nota 13 più eventuali piccole differenze di conto).
- La forma "delta" (tavola di G0 + [legge(f(x; s)) − legge(f(x; 0))]) deve ridarle **esattamente** a s = 0, cioè a meno di 1e-12.
- **Attesa per l'ancora** 🟡: slo0 non cambia con s (f(0) = 0), quindi c2 non cambia. Le note dell'ancora (CUT 64 / ENV 64) si spostano
  solo tramite slo2, di (−off64 + coda)·Δslo2.
  - Soglia: se |Δj| ≤ 2 passi per tutto s ∈ [0, 1], l'ancora tiene dentro i 4 passi della regola senza ri-ancorare.
  - Se è fra 2 e 4 passi, si dichiara e si sceglie (la coordinazione); se è > 4, si ri-ancora.
- La coda del MEG a fine nota è 3,7 / 4,0 / 4,8 % della spazzata nelle tre finestre (`g0_leggi/leggi.log`, C2): uso tutte e tre.
- **Ritiro preparato:** il "+1,1…+4,3 passi" del punto 3 della nota 20 supponeva che il nodo di CUT 64 si muovesse. In g0lib non si
  muove, quindi quella cifra non vale per g0lib.
