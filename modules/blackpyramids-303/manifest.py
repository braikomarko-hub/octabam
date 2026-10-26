"""BLACKPYRAMIDS_303 -- BLKPYRAMD, a TB-303 voice (built on Open303, recalibrated on the TB-303's circuit, on the
DSP56300) as a track machine, one per DSP core.

Source: `upstream/` is Zac Kyoti's repository (Zac-Kyoti/octatrack-kyoti-fw,
submodule, pinned to `9b2e35a`). The declaration is
`upstream/octabam-modules/blackpyramids-303/manifest.py`: one DRAM unit (`bp_runtime.s`, the
ColdFire runtime generated from its sources), re-linked and compared with the author's own bytes
(`reference`) every build; 44 detours, 7 pokes, the FLEX renderer `SymbolRef`; and the DSP voice
written by `bp_image.py` through `Module.dsp_source`, as ANALOG BD's `tools/build/ab_image.py`.
Its source paths are derived from its own directory, so it is executed here from the source on
disk, as the registry does for every manifest, and this file only re-exports its MODULE. Nothing
inside `upstream/` is edited here.

On hardware: the author's standalone images on their MKI, 14-16 Oct 2026, and the recalibrated voice's
(FINAL, mainos ecc85887...) 21 Oct 2026: all good; with the link clips CUT-RES and DEC-ACC (FINAL, mainos
88d49307...) 23 Oct 2026: all good. This octabam form (remixes/test/blackpyramids-303) on their MKI: with the
previous voice, 19 Oct 2026, all checks pass; with the recalibrated voice, 21 Oct 2026, all good; the clips'
form is not flashed.
"""

import dataclasses
import pathlib
import runpy

from remix.schema import Category, Proof

_UPSTREAM = pathlib.Path(__file__).resolve().parent / "upstream" / "octabam-modules" / "blackpyramids-303" / "manifest.py"

MODULE = runpy.run_path(str(_UPSTREAM), run_name="remix_manifest_blackpyramids_303")["MODULE"]
# The module table's fields are octabam's (README.md, `make docs`), so they
# are added here rather than in the author's manifest.
MODULE = dataclasses.replace(
    MODULE, category=Category.MACHINES, author="Zac Kyoti", author_url="https://github.com/Zac-Kyoti",
    proof=Proof.HARDWARE, proof_note="the author's MKI: standalone images 14-23 Oct 2026; this octabam form 19 Oct 2026 and, with this voice, 21 Oct 2026 (the 23 Oct link clips: standalone only)")
