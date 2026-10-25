"""TRACK MENU v1 -- hold a track key ~1 s: that track's menu (a chooser, then MORPH, EUCLACID or ERGOSUM).

A prototype: UP / DOWN and YES choose, the knobs (the stock's) change the settings, the same track
key closes ("Tn START" is only shown), NO goes back. Nothing is saved. MORPH keeps its own
[TRACK]+[UP] window, no Euclidean pattern is printed; the ERGOSUM page PLAYS: the track's trigs read
through a 4x4 grid (idea: Make Noise RENE), SPLIT ALL / NOTES / RHYTHM.
Provisional name: the owner will name the module when MORPH and EUCLACID live in it.

Sites, measured from the user's 1.40C (24 Oct 2026; base 0x40000400):
  * the eight track records (codes 0x10..0x17) of the MKI key table 0x400bfc10 and of the MKII
    table 0x400c01f4: press = release = repeat = 0x40040250, sub-map 0x400d164a, repeat delay 30.
    Only the PRESS field (+2 of each 0x1a-byte record) is repointed, at tm_tpress, which calls
    0x40040250 first, unchanged.
  * ERGOSUM: the trig record builder 0x4009d1e8(track, bank, pattern, step, n) decides the step's
    trig, condition (0x400a5164) and locks; its entry (lea -0x68(sp) ; movem.l d2-d7/a2-a6) is
    displaced, and the builder called with the rhythm's step as the argument and the locks' step one
    long past it. The builder loads the step's lock row at 0x4009d73a and 0x4009d8e0 only
    (`move.l 0x78(sp),d0 ; lsl.l #5,d0`, six bytes each): both jsr es_lk (25 Oct 2026).
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
    doc=("Hold a track key about a second: a small chooser (MORPH, EUCLACID, ERGOSUM); YES opens that "
         "function's page with its settings as the stock knobs; the same track key closes it. "
         "ERGOSUM reads the track's trigs through a 4x4 grid (MODE LIN/XY/SNAKE/DIAG, RATI, SNAK, ERGO, "
         "SPLT ALL/NOTE/RTHM: rhythm and notes from the grid, or one of them); MORPH and EUCLACID are "
         "navigation only."),
    proof=Proof.CHECK,
    proof_note="prototype: tools/trackmenu/test_trackmenu.py (the source under cfsim); not yet on the unit",
    linked=(
        Linked("trackmenu", os.path.join(_HERE, "trackmenu.s"), dram=True),
    ),
    symbol_refs=_press_fields(),
    detours=(
        Detour(0x4009D1E8, bytes.fromhex("4fefff9848d77cfc"), "trackmenu", "es_entry",
               "ERGOSUM: the trig record builder's entry (lea -0x68 ; movem): the steps through the grid",
               kind="jmp", pad_to=8),
        Detour(0x4009D73A, bytes.fromhex("202f0078eb88"), "trackmenu", "es_lk",
               "ERGOSUM SPLIT: the builder's lock row (with a slide): the locks' step, not the rhythm's",
               kind="jsr"),
        Detour(0x4009D8E0, bytes.fromhex("202f0078eb88"), "trackmenu", "es_lk",
               "ERGOSUM SPLIT: the builder's lock row (no slide): the locks' step, not the rhythm's",
               kind="jsr"),
    ),
    gates=(
        Gate("tools/trackmenu/test_trackmenu.py", remix_arg=False),
    ),
)
