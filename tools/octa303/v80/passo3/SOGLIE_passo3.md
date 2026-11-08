# Passo 3 — soglie scritte PRIMA dei risultati (8 nov 2026, 08:00)
Confronto del motore intero (ref303.py) con il gemello float, note intere (pre-roll come sim.c, fase 0,25, Din Sync
65,643 Hz), le stesse 18 note del passo 2 (4 di riferimento + 14 estreme).
Metriche per nota: E = 20 log10(rms(motore - gemello) / rms(gemello)); P = |20 log10(picco motore / picco gemello)|.
0. Base (misurata, non giudicata): ref303 v7.9 (1cbfb970) contro il gemello "V8A ricostruito" = la tabella di (a)
   con kl_on 0, imap_on 0, kl_q12 0, LG = la LG del motore v7.9. Se la base non sta essa stessa entro
   E <= -20 dB e P <= 0,30 dB su tutte le note, la ricostruzione non vale: ci si ferma.
1. v8.0: ref303 (ramo octa303-v80) contro il gemello (a), per ogni nota:
   E_v80 <= E_base + 3,00000 dB  (non peggio di 3 dB della base sulla stessa nota)  e  P_v80 <= 0,30000 dB.
   Passa se tutte le 18 note passano. Se no: fallito, e si cerca il blocco con le prese.

## Esito del punto 0 (8 nov, ~07:45): la base NON vale -> ci si ferma, verdetto del passo 3 NON dato
Misurato: base E <= -20 dB fallita su 5 note (2, 4, 5, 11, 12: CUT/ENV 127 con RES 127), tutte nei primi 50 ms
(E -5..-8 dB nell'attacco, poi -26..-40 dB). Le tabelle della scala vecchia nel json sono IDENTICHE a quelle del motore
v7.9 (KF, KD, LK, LB, KMUL, UD: scarto relativo 0): quindi non e' la ricostruzione delle tabelle, e' la scala vecchia
intera del motore v7.9 che nell'attacco a taglio e risonanza massimi non segue il suo gemello float (dedotto).
I numeri della v8.0 sulle 18 note sono annotati come dato (peggiore E -34,95 dB, P <= 0,020 dB), non come verdetto.

## Punto 3b, scritto DOPO il fallimento del punto 0 e PRIMA di vedere queste note (8 nov, 07:50)
Note nuove, mai rese: 24 note a caso, seme 8112026 (numpy default_rng), CUT/RES/ENV/DEC uniformi 0..127, onda 0/1,
accento: meta' -1, meta' uniforme 0..127; semi -11,9375, fase 0,25. Nessuna base (il punto 0 ha mostrato che la
scala vecchia non la puo' dare). Soglia per nota: E_v80 <= -30,00000 dB e P_v80 <= 0,30000 dB. Passa se passano tutte.
Nota onesta: la soglia -30 dB e' scelta dopo aver visto le 18 note del punto 1 (peggiore -34,95), cioe' con ~5 dB di
margine su quelle; le 24 note qui sono nuove.
