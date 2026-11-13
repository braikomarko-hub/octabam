# SOGLIE per gt22 (ricercatore 303, 9 nov 2026 ~19:15 UTC+2) — scritte PRIMA di gt22.py
Solo aritmetica sui log copiati (e_logs.md, tarature_s43_22-24.md, nota13_gruppi.md). Nessun verdetto: servono a leggere.
- T1: race_core A di E375 (tabella.log) meno race_core A di (a)''1 (par. 43.23) deve essere uguale a race_B E375 - race_B (a)''1
  entro 1e-5 (lo stesso anello 0,175451 per tutti). Se no: l'anello non e' costante, lo dico.
- T2: FC0 della scala = 12350 / 2^(445/48) deve stare entro 1 % da 20 Hz (lo uso per l'indice di 18 kHz). Se no, non do l'indice.
- "parte che porta la distanza": una parte che pesa > 1/10 della somma delle dieci differenze. Solo lettura.
- Rumore: 0,078 = rumore di race_core sulla meta' B (par. 43.16, copiato dal coordinatore). Unita' di rumore = diff / 0,078.
- (aggiunta prima della seconda parte dello script) T3: la legge "cursore lineare B caricato" g = x/(1 + a·x(1−x)) deve ridare
  0,21 / 0,40 / 0,63 della nota 13 T3 entro 0,01 con UN solo a; se no, non la uso per dare un campo.
