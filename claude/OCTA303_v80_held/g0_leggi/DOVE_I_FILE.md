# g0_leggi: where each input of leggi.py is (coordination, 9 Nov 2026 ~15:00)

The project is nearly full, so the researcher's folder was uploaded without its inputs. Each one is listed below with where it
already is in the project, checked by sha256 (first 16 hex digits) against the researcher's own folder.

| file leggi.py needs | where in the project | sha256 |
|---|---|---|
| `sim_tap.c` | **this folder** (uploaded now; `sim.c` + 3 lines: `svx`, `s->svx = sv / 64.0`, `if (T.kl_tap > 7.5) return 64.0 * s->svx;`) | 414539a8677381fe |
| `sim.c` | `claude/OCTA303_v80_held/g0_tm3/twin/sim.c` | 063b60ff0eb49bc4 |
| `sim_q21.c` | `claude/OCTA303_v80_held/g1_carico/sim_q21.c` | 51e9480c96bdbe40 |
| `q21tab.py` | `claude/OCTA303_v80_q21/q21tab.py` | 46edfcc4410f0760 |
| `g1_input.log` | `claude/OCTA303_v80_held/g1_carico/g1.log` (renamed) | 17715c44bbf94a2d |
| `onsets.json` | `claude/OCTA303_dinsync_onsets.json` (renamed) | 2d4105121562b2ef |
| `ris/klaw.py`, `ris/stin.py` | `claude/OCTA303_v80_held/tm3/ris/` | cecf14e960990b05, 8e4f62f128e2f0bd |
| `risonanza_accento/smorza.py` | `claude/OCTA303_v80_held/tm3/risonanza_accento/smorza.py` | ab43f9b869df96a8 |
| `gemello_a_tabelle.json` | not in the project (645 KB): identical to `OCTA303_v79_gemello_a_tabelle.json` in the fork, branch `octa303-v80`, `tools/octa303/v80/gemello_a/` (claude/OCTA303_v79_gemello_a/TABELLA_SU_GITHUB.md); md5 cd080b14… as in g0_q12/RIPRODUCI.md; leggi.py takes it as an argument, so the name does not matter | 1a6a97b579cf56e8 |
| the Din Sync recordings | outside the project, as for q12.py | — |

Folder layout leggi.py expects (run from inside it): the files above side by side, `ris/` and `risonanza_accento/` as
sub-folders, then the command of RIPRODUCI.md.
