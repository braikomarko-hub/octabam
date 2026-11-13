# gt22 — come riprodurre, e una nota della coordinazione (9 nov 2026 ~19:45 UTC+2)
- `python3 -I gt22.py > gt22.log` dalla cartella. Solo aritmetica. Rifatto dal coordinatore nel cloud: uscita identica (diff vuoto).
- Il ricercatore ha lavorato su copie fatte dal coordinatore (gli aiutanti non leggono il progetto): e_logs.md (risultati di E, parola
  per parola), piano del gruppo E, nota 13 §1–§4, estratti delle note 18 / 19 / 20 / 21, §42.4, §43.22–43.24.
- **Nota della coordinazione su P1 (il tetto a 18 kHz), che il ricercatore non poteva vedere:** il §34.3 di
  claude/OCTA303_v79_tarature.md (7 nov) ha già provato la scala allungata oltre 445 con la stessa formula: la regola del salto NON
  passa dal passo 453 → 454 (14,07 kHz) in su; fino all'indice 453 (13,87 kHz) passa. Quindi P1 a 18 kHz (indice 471) fallisce
  §34.1 per costruzione, e il §34.3 misura anche quanto il tetto potrebbe dare al massimo: righe D 0,000 del tempo sopra 12,4 kHz,
  righe E 0,119. Domande aperte del ricercatore (ring, la parte (5), dec0..4 / dchp / X_a2_gv) da girare alla chat delle tarature.
  La frequenza di campionamento del gemello è 44 100 Hz (FS in g1.py e sim).
