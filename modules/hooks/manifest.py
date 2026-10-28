"""HOOKS -- the one owner of a stock site that two selected modules both claim.

The ledger allows one claim on a stock site, so two modules that hook one
instruction or repoint one word could not share an image. A BRIDGE here
joins them: when a remix carries two or more of a bridge's participants,
HOOKS takes the site (schema.Override of each participant's claim there)
and calls each participant's own routine, in an order that respects each
one's protocol. A remix carrying one participant, or none, gets nothing
from HOOKS: that module's own claim stands and its bytes do not move, so a
module proven alone on a unit stays exactly what was proven.

The registry appends HOOKS to a remix whenever a bridge has two
participants in it (registry.remix), as it appends MEMORY; no remix lists
it. The participants' sources are not edited: a submodule's stays its
author's (REC_TRIG_MUTE), an in-tree module's keeps its proven bytes.

docs/proposals/SHARED_HOOKS.md is the design. Bridges:

  * track_key -- the [TRACK]-held key layer 0x400d164a. Its keys field
    0x400d164e points at stock's six records at 0x400d1594 (0x1a bytes
    each: code, 0, press, release, 16 zero bytes; then 0xff, 0). MORPH
    repoints the field at its own copy with UP and DOWN added; REC_TRIG_MUTE
    repoints the YES and NO records' handlers inside stock's table. Together,
    MORPH's copy would carry stock's YES/NO and REC_TRIG_MUTE's mute keys
    would silently stop working. Bridged: HOOKS's table is stock's six
    records with each participant's replacements, then each participant's
    added keys, and the field points at it. REC_TRIG_MUTE's own refs into
    stock's table are still written; nothing reads that table once the field
    is repointed.
  * status_icon -- the track status icon renderer's state-cache load
    0x4004bee2 (`lea 0x400c0cb8,%a0`), d3 the track, a4 the state about to be
    compared and drawn. REC_TRIG_MUTE (rtm_glyph) folds a mute into a4 as
    8 | playing; REC THRESHOLD (blink_gate) ORs 0x10 into a4 on an armed
    track's off phase. Both are `jsr` detours that redo the lea and may
    clobber d0/d1/a0/a1, which the renderer reloads before reading.
    Bridged: one jsr calls rtm_glyph, then blink_gate -- the fold first, so
    the blink bit survives it (in the other order rtm_glyph's `and #1`
    would clear 0x10).
"""

import os

from remix.schema import Category, Detour, Gate, Kind, Linked, Module, Override, Proof, SymbolRef

H = bytes.fromhex
_HERE = os.path.relpath(os.path.dirname(os.path.realpath(__file__)))

# ---- track_key -----------------------------------------------------------
KEYS_FIELD = 0x400D164E                 # the [TRACK]-held layer's keys pointer
KEYS_STOCK = 0x400D1594                 # stock's six records + the 0xff terminator
# Stock's records, in stock's order (code, press, release): STOP, PLAY, BANK,
# YES (ARM REC TRK), NO (DISARM REC TRK), 0x18. tools/verify/verify_hooks.py
# compares them with the user's 1.40C.
STOCK_KEYS = (
    (0x27, 0x40083A7C, 0),
    (0x28, 0x40083A30, 0),
    (0x2F, 0x40083CE0, 0),
    (0x31, 0x400834D8, 0x400834D8),
    (0x32, 0x40083488, 0x40083488),
    (0x18, 0x400839DC, 0),
)
# (module key, records it replaces, records it adds, its claim on KEYS_FIELD).
# A record is (code, press symbol, release symbol or None). Table order is
# participant order; a code may be replaced or added by one participant only.
TRACK_KEY = (
    ("REC_TRIG_MUTE", ((0x31, "rtm_yes", "rtm_yes"), (0x32, "rtm_no", "rtm_no")), (), False),
    ("MORPH", (), ((0x33, "morph_up", None), (0x20, "morph_down", None)), True),
)

# ---- status_icon ---------------------------------------------------------
ICON_SITE = 0x4004BEE2
ICON_STOCK = H("41f9400c0cb8")          # lea 0x400c0cb8,%a0
# (module key, its jsr routine at ICON_SITE), in call order.
STATUS_ICON = (
    ("REC_TRIG_MUTE", "rtm_glyph"),
    ("REC THRESHOLD", "blink_gate"),
)


def _present(participants, modules):
    return tuple(p for p in participants if p[0] in modules)


def bridged(modules) -> tuple[str, ...]:
    """The bridges a selection of module keys needs: those with two or more
    participants in it."""
    out = []
    if len(_present(TRACK_KEY, modules)) >= 2:
        out.append("track_key")
    if len(_present(STATUS_ICON, modules)) >= 2:
        out.append("status_icon")
    return tuple(out)


def track_key_records(modules):
    """HOOKS's [TRACK]-layer table for a selection: [(code, press, release)],
    each handler a stock address or a participant's symbol."""
    recs = [list(r) for r in STOCK_KEYS]
    codes = {r[0] for r in STOCK_KEYS}
    owner = {}
    for key, replaces, adds, _field in _present(TRACK_KEY, modules):
        for code, press, release in replaces:
            if code not in codes:
                raise ValueError(f"HOOKS track_key: {key} replaces key 0x{code:02x}, "
                                 f"which stock's layer does not have")
            if code in owner:
                raise ValueError(f"HOOKS track_key: {key} and {owner[code]} both "
                                 f"replace key 0x{code:02x}")
            owner[code] = key
            r = next(r for r in recs if r[0] == code)
            r[1], r[2] = press, release or 0
        for code, press, release in adds:
            if code in codes or code in owner:
                raise ValueError(f"HOOKS track_key: {key} adds key 0x{code:02x}, "
                                 f"which the layer already has")
            owner[code] = key
            recs.append([code, press, release or 0])
    return [tuple(r) for r in recs]


def _handler(v):
    return f"0x{v:08x}" if isinstance(v, int) else v


def hooks_inc(modules, remix=None):
    """remix.inc for bridge.s: which bridges are on and their tables."""
    on = bridged(modules)
    out = [f".set hk_track_key, {int('track_key' in on)}",
           f".set hk_status_icon, {int('status_icon' in on)}",
           ".macro hk_track_key_records"]
    if "track_key" in on:
        out += [f"    HKREC 0x{c:02x}, {_handler(p)}, {_handler(r)}"
                for c, p, r in track_key_records(modules)]
    out += [".endm", ".macro hk_status_icon_chain"]
    if "status_icon" in on:
        out += [f"    jsr {sym}" for _key, sym in _present(STATUS_ICON, modules)]
    out += [".endm"]
    return "\n".join(out) + "\n"


UNIT = Linked("hooks", os.path.join(_HERE, "bridge.s"), dram=True, include=hooks_inc)


def select(modules):
    """Only the bridges this selection needs enter the bound module: its
    unit, its claims and its overrides of the participants' claims."""
    on = bridged(modules)
    detours, refs, overrides = [], [], []
    if "track_key" in on:
        refs.append(SymbolRef(KEYS_FIELD, KEYS_STOCK, "hooks", "hk_track_keys",
                              "[TRACK]-held key layer: stock's records with each "
                              "participant's replacements and added keys"))
        overrides += [Override(KEYS_FIELD, key)
                      for key, _r, _a, field in _present(TRACK_KEY, modules) if field]
    if "status_icon" in on:
        detours.append(Detour(ICON_SITE, ICON_STOCK, "hooks", "hk_status_icon",
                              "track status icons: each participant's state fold, in order",
                              kind="jsr"))
        overrides += [Override(ICON_SITE, key) for key, _sym in _present(STATUS_ICON, modules)]
    return {"linked": (UNIT,) if on else (), "detours": tuple(detours),
            "symbol_refs": tuple(refs), "overrides": tuple(overrides)}


# The unbound declaration carries every bridge, so the matrix and the
# remixer see HOOKS as the bridge that joins each pair (index.py, app.py);
# ledger.check and registry.bound apply select() to any real selection.
_ALL = select({p[0] for p in TRACK_KEY} | {p[0] for p in STATUS_ICON})

MODULE = Module(
    name="hooks",
    key="HOOKS",
    kind=Kind.CF_PATCH,
    category=Category.SETTINGS, author="Sam Banks", author_url="https://github.com/sambanks",
    proof=Proof.PORT, proof_note="verify_hooks: the bridged tables and chains under Unicorn, and each bridged image's sites",
    doc="Platform: owns a stock site two selected modules both claim, and calls each one's routine there.",
    linked=_ALL["linked"], detours=_ALL["detours"], symbol_refs=_ALL["symbol_refs"],
    overrides=_ALL["overrides"],
    select=select,
    gates=(Gate("tools/verify/verify_hooks.py", once=True, venv=True),),
)
