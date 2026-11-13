# SOGLIE per gt21 (ricercatore 303, 9 nov 2026 ~17:00 UTC+2) — scritte PRIMA di gt21.py

Dichiarato: i log di GT li ho gia' letti (sono il dato del compito). Queste soglie le scrivo prima dello
script, ma non "alla cieca" rispetto ai dati. Per questo non ne uso nessuna per un verdetto di gara: servono
solo a dire in modo ripetibile "confermata / smentita / non decidibile" per le previsioni della nota 20 par. 4.

Controlli dello script (devono passare, se no mi fermo):
- T1: ricostruisco taper / cut_oct / sweep dalle formule scritte nella nota 20 (taper.py non e' nella cartella).
  SHAPE(s) e SLO(s) in forma delta a s = 0 e s = 1 devono ridare la tabella dell'aggiunta 15:59 entro 0,002.
- T2: la variazione celle40^2 del log classi (-0,8471) deve tornare con 3,018224^2 - 2,863754^2 entro 0,001.

Lettura delle previsioni (media rms celle40 per gruppo, per_set_info.log; R9 -> GT):
- "migliora molto": variazione <= -0,5 dB e <= -15 % relativo.
- "peggiora": variazione >= +0,2 dB.
- "nessun cambiamento / al piu' -1,5 % di taglio": |variazione| <= 0,1 dB (non ho il rumore per gruppo: dichiarato).
- "poco o niente, forse peggio": variazione >= -0,2 dB. Una variazione <= -0,2 dB la smentisce.
- "s nella meta' alta (0,5-1)": s* >= 0,5. Smentita se s* < 0,5; dico anche se la differenza sta sotto il rumore
  (rumore di race_core sulla meta' B 0,078 = 0,156/2; dichiarato: misurato sulla meta' B, non su race_B meta' A).

## Aggiunta DOPO la corsa (non cambia le soglie sopra)
- T2 NON PASSA (0,9086 contro 0,8471). Il controllo era scritto male da me: la parte "celle40" (3,018 / 2,864) non e' la
  radice della media semplice delle 11345 celle, mentre il -0,8471 del log e' -9610,8 / 11345 (controllato: 0,84714).
  Quindi T2 non dice niente sui dati di GT; dice che non conosco l'aggregazione esatta della parte celle40. Lo lascio
  scritto come fallito. Nessun numero della nota 21 si appoggia su T2.
