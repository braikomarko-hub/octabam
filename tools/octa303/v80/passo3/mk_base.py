"""python3 mk_base.py TABLE_JSON V79_ENGINE_DIR OUT.bin : the twin (a)'s table with the new ladder switched off
(kl_on 0, imap_on 0, kl_q12 0, kl_tpt 0) and LG = the v7.9 engine's per-index LG (Q12 / 4096): the old ladder of V8A,
the base of SOGLIE_passo3.md point 0. Written by Claude, 8 Nov 2026."""
import json, sys, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import wtab
sys.path.insert(0, sys.argv[2]); import o3tables as T
b = dict(json.load(open(sys.argv[1]))['table'])
b.update(kl_on=0.0, imap_on=0.0, kl_q12=0.0, kl_tpt=0.0); b['LG'] = [v / 4096 for v in T.LG]
wtab.write(b, sys.argv[3])
