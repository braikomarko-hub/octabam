"""TRACK MENU v0 -- hold a track key ~1 s: that track's menu (MORPH and EUCLACID pages).

A prototype of the navigation only: LEFT / RIGHT change page, the knobs change the settings, the
same track key closes ("Tn START" is only shown), NO closes. Nothing reads the settings yet and
nothing is saved: MORPH keeps its own [TRACK]+[UP] window, no Euclidean pattern is printed.
Provisional name: the owner will name the module when MORPH and EUCLACID live in it.

Sites, measured from the user's 1.40C (24 Oct 2026; base 0x40000400):
  * the eight track records (codes 0x10..0x17) of the MKI key table 0x400bfc10 and of the MKII
    table 0x400c01f4: press = release = repeat = 0x40040250, sub-map 0x400d164a, repeat delay 30.
    Only the PRESS field (+2 of each 0x1a-byte record) is repointed, at tm_tpress, which calls
    0x40040250 first, unchanged.
"""

import os

from remix.schema import Category, Gate, Kind, Linked, Module, Proof, SymbolRef

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
         "the page (MORPH, EUCLACID, EUCL LIVE), the knobs set the values, the same track key closes it. "
         "v0 is the navigation only: nothing reads the values yet."),
    proof=Proof.CHECK,
    proof_note="prototype: tools/trackmenu/test_trackmenu.py (the source under cfsim); not yet on the unit",
    linked=(
        Linked("trackmenu", os.path.join(_HERE, "trackmenu.s"), dram=True),
    ),
    symbol_refs=_press_fields(),
    gates=(
        Gate("tools/trackmenu/test_trackmenu.py", remix_arg=False),
    ),
)
