# Passo 2 — soglie scritte PRIMA dei risultati (8 nov 2026, 01:05)
Prova: la scala nuova isolata (ramo m4 di sim.c: M1t + (c''-0) + Q12 su u stimato + G/F TPT), con gli stessi ingressi
x, indice li e k presi dal gemello (prese 4, 6, 7, pre_s = 0), su 18 note (le 4 di riferimento + 14 estreme).
A. Il port Python in virgola mobile della scala deve ridare la presa 1 del gemello: max |errore| <= 1e-6 (unità del
   gemello) su ogni campione di ogni nota. Se no: ci si ferma, il port è sbagliato.
B. Il modello in intero (EMAC frazionario: addendo = floor(2P / 2^24), lettura = floor(acc / 2^8); tabelle quantizzate)
   contro A, per ogni nota:
   - errore RMS / RMS del segnale <= -80,00000 dB;
   - max |errore| <= 64,00000 unità del gemello (= 1 LSB dell'uscita s16, che è /64).
   Passa solo se tutte e 18 le note passano tutte e due le soglie. Se no: si scrive "fallito", si dice dove, e si
   cambia il formato SOLO con una nuova soglia scritta prima.
