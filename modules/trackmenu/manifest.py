"""TRACK MENU v0 -- hold a track key ~1 s: that track's menu (MORPH and EUCLACID pages).

A prototype: LEFT / RIGHT change page, the knobs change the settings, the same track key closes
("Tn START" is only shown), NO closes. Nothing is saved. MORPH keeps its own [TRACK]+[UP] window and
no Euclidean pattern is printed yet; the ERGOSUM page works: the track's trigs are read through a
4x4 grid (idea: Make Noise RENE). The owner's name for the menu: ACID BUCKET.

ERGOSUM site, measured from the user's 1.40C (24 Oct 2026): the trig record builder 0x4009d1e8
(track, bank, pattern, step, n) decides the step's trig, condition (0x400a5164) and locks; its entry
(lea -0x68(sp) ; movem.l d2-d7/a2-a6) is displaced and the step argument replaced.

Sites, measured from the user's 1.40C (24 Oct 2026; base 0x40000400):
  * the eight track records (codes 0x10..0x17) of the MKI key table 0x400bfc10 and of the MKII
    table 0x400c01f4: press = release = repeat = 0x40040250, sub-map 0x400d164a, repeat delay 30.
    Only the PRESS field (+2 of each 0x1a-byte record) is repointed, at tm_tpress, which calls
    0x40040250 first, unchanged.
"""

import os

from remix.schema import Category, Detour, Gate, Kind, Linked, Module, Proof, SymbolRef

_HERE = os.path.relpath(os.path.dirname(os.path.realpath(__file__)))

STOCK_TKEY = 0x40040250
TABLES = (("MKI", 0x400BFC10, 2), ("MKII", 0x400C01F4, 2))   # index of the T1 record in each


def _press_fields():
    """The PRESS field of T1..T8 in both key tables (records 0x1a bytes, code at +0, press at +2).
    The T1 record is the third of each table (index 2) (measured: 0x400bfc44 and 0x400c0228)."""
    refs = []
    for name, table, first in TABLES:
        for t in range(8):
            addr = table + (first + t) * 0x1A + 2
            refs.append(SymbolRef(addr, STOCK_TKEY, "trackmenu", "tm_tpress",
                                  f"{name} key table, T{t + 1} press: the stock handler, then the long press"))
    return tuple(refs)


MODULE = Module(
    name="trackmenu",
    key="TRACK_MENU",
    kind=Kind.CF_PATCH,
    category=Category.PARTS,
    author="MaMarko",
    author_url="https://github.com/braikomarko-hub",
    doc=("Hold a track key about a second: that track's menu opens and stays open. LEFT / RIGHT turn "
         "the page (MORPH, EUCLACID, EUCL LIVE, ERGOSUM), the knobs set the values, the same track key "
         "closes it. ERGOSUM reads the track's trigs through a 4x4 grid (MODE LIN/XY/SNAKE/DIAG, RATIO, "
         "SNAKE); the other pages are navigation only."),
    proof=Proof.CHECK,
    proof_note="prototype: tools/trackmenu/test_trackmenu.py (the source under cfsim); not yet on the unit",
    linked=(
        Linked("trackmenu", os.path.join(_HERE, "trackmenu.s"), dram=True),
    ),
    symbol_refs=_press_fields(),
    detours=(
        Detour(0x4009D1E8, bytes.fromhex("4fefff9848d77cfc"), "trackmenu", "es_entry",
               "ERGOSUM: the trig record builder's entry (lea -0x68 ; movem): the step through the grid",
               kind="jmp", pad_to=8),
    ),
    gates=(
        Gate("tools/trackmenu/test_trackmenu.py", remix_arg=False),
    ),
)
