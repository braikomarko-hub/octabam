#!/usr/bin/env python3
"""Slot costs measured on a unit, and what they say about a remix.

`slot_costs.json` (beside this file) holds, per effect, the DSP cost of one
slot as a share of a frame, read from the LOAD METER on a unit. The tool does
three things:

    costs.py import REPORT [REPORT ...]   merge `ot_matrix.py run` reports into the catalog
    costs.py table                        every effect: worst measured slot cost, settings read
    costs.py check REMIX [--limit 0.95]   worst-case core load of a remix, from the catalog

How a figure is made (docs/contributing/COSTS.md has the method and limits).
A matrix layout puts ONE effect on all 8 tracks of one slot (FX1 or FX2), so a
core carries 4 instances of it: slot cost = (core busy - BASE core busy) / 4.
Pair and split layouts, layouts that overloaded the unit, and the bus remix's
reports (its FX2 slots hold the rig) are not read.

How a remix is bounded. A core has 4 FX1 slots and 4 FX2 slots. The worst
layout fills the FX1 slots with the dearest FX1-capable effect and the FX2
slots with the dearest effect of the remix, each at its dearest measured
setting, so the worst core load is

    base + 4 * max(FX1 effects) + 4 * max(FX2 effects)

and the remix is free of DSP overload in every configuration when that stays
at or under the limit on both cores. The ColdFire's share is not in the sum
(EUCLID adds about 7 points; `cf_over_base` is recorded per effect). An
effect with no measured cost leaves the verdict UNKNOWN.
"""
import argparse
import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
CATALOG = HERE / "slot_costs.json"
LIMIT = 0.95                    # share of a frame a core may be busy; 98.2 % ran clean, 95.8 % dropped frames (EUCLID)
SLOTS_PER_KIND = 4              # FX1 or FX2 instances on one core
NOT_READ = {"CRASH", "FREEZE", "OVERLOAD", "DROPS"}   # flags of a layout whose busy figure the unit did not hold
SINGLE = re.compile(r"^(?P<effect>.+?) (?P<slot>FX1|FX2) (?P<variant>\S+)$")


def load(path=CATALOG):
    if pathlib.Path(path).exists():
        return json.loads(pathlib.Path(path).read_text())
    return {"limit": LIMIT, "slots_per_kind": SLOTS_PER_KIND, "bases": {}, "effects": {}}


def save(cat, path=CATALOG):
    pathlib.Path(path).write_text(json.dumps(cat, indent=1, sort_keys=True) + "\n")


# ---------------------------------------------------------------------------
# import
# ---------------------------------------------------------------------------
def parse_report(path):
    """-> (label, remix, base, rows, skipped). base = (core0 %, core1 %, ColdFire share %);
    rows = [(effect, slot, variant, core0 cost, core1 cost, ColdFire share %)], costs in points of a frame."""
    p = pathlib.Path(path)
    doc = json.loads(p.read_text())
    res = [r for r in doc["results"] if "name" in r]     # `switch` reports have no layouts of this kind
    if not res or res[0]["name"] != "BASE" or not res[0].get("load"):
        raise ValueError(f"{p}: layout 0 is not a BASE with LOAD METER figures")
    b = res[0]["load"]
    base = (100 * b["dsp_core0_mean"], 100 * b["dsp_core1_mean"], 100 * b["cf_share_mean"])
    rows, skipped = [], []
    for r in res[1:]:
        m = SINGLE.match(r["name"])
        if not m or " + " in r["name"] or "T1-4" in r["name"] or not r.get("load"):
            continue
        if NOT_READ & set(r.get("flags", [])):
            skipped.append(r["name"])
            continue
        l = r["load"]
        rows.append((m["effect"], m["slot"], m["variant"],
                     (100 * l["dsp_core0_mean"] - base[0]) / SLOTS_PER_KIND,
                     (100 * l["dsp_core1_mean"] - base[1]) / SLOTS_PER_KIND,
                     100 * l["cf_share_mean"]))
    return (p.parent.name, doc["remix"], base, rows, skipped)


def merge(cat, label, remix, base, rows):
    """Fold one report in. Per (effect, slot) the newest report replaces what was there: a later run
    of the same effect is a later build of it."""
    bases = cat["bases"].setdefault(remix, {"core0": 0.0, "core1": 0.0, "cf_share": 0.0, "reports": {}})
    bases["reports"][label] = [round(base[0], 2), round(base[1], 2), round(base[2], 2)]
    for k, i in (("core0", 0), ("core1", 1), ("cf_share", 2)):
        bases[k] = max(v[i] for v in bases["reports"].values())     # the dearest base seen: the bound stays safe
    seen = {(e, s) for e, s, *_ in rows}
    for e, s in seen:
        costs = cat["effects"].setdefault(e, {"costs": {}})["costs"]
        for key in [k for k in costs if k.startswith(s + " ")]:
            del costs[key]
    for e, s, v, c0, c1, cf in rows:
        cat["effects"][e]["costs"][f"{s} {v}"] = {
            "core0": round(c0, 2), "core1": round(c1, 2),
            "cf_over_base": round(cf - base[2], 1), "report": label, "remix": remix}
    return cat


def cmd_import(a):
    cat = load()
    cat["limit"], cat["slots_per_kind"] = LIMIT, SLOTS_PER_KIND
    for path in a.reports:
        label, remix, base, rows, skipped = parse_report(path)
        if "REVERB SERVER" in remix_modules(remix):
            print(f"{label}: {remix} is a bus remix (its FX2 slots hold the rig): not read")
            continue
        merge(cat, label, remix, base, rows)
        print(f"{label}: {remix}, base {base[0]:.1f} / {base[1]:.1f} %, {len(rows)} single-effect layouts read"
              + (f", {len(skipped)} not read (flags: {', '.join(skipped)})" if skipped else ""))
    save(cat)
    print(f"{len(cat['effects'])} effects in {CATALOG.name}")
    return 0


# ---------------------------------------------------------------------------
# remix side
# ---------------------------------------------------------------------------
def _registry():
    sys.path.insert(0, str(HERE.parent))
    import toolpath  # noqa: F401  (every tools/ directory on sys.path)
    from remix import registry
    return registry


def remix_modules(name):
    try:
        return _registry().remix(name).modules
    except Exception:
        return ()


def effects_of(name):
    """-> (fx1 keys, fx2 keys, notes) for the track effects of a remix (servers and clients are not read)."""
    reg = _registry()
    from remix import stock
    remix, mods = reg.remix(name), reg.modules()
    notes = []
    if "REVERB SERVER" in remix.modules:
        notes.append("bus remix: its FX2 slots hold the rig, only track effects are bounded")
    fx1 = remix.fx1 or tuple(k for k in stock.p_spans("A") if mods[k].menu.fx2_id in stock.fx1_ids())
    from remix.schema import Category
    fx2 = [k for k in remix.modules if k in mods and mods[k].menu is not None and k not in remix.hidden
           and mods[k].category in (Category.TRACK, Category.STOCK) and k not in
           ("SEND", "REVERB SERVER", "DELAY SERVER")]
    fx1 = [k for k in fx1 if k in mods and mods[k].category in (Category.TRACK, Category.STOCK)]
    return fx1, fx2, notes


def worst(cat, key, slot):
    """-> (dearest measured cost over cores and settings, the entry's name) or None."""
    best = None
    for name, v in cat["effects"].get(key, {}).get("costs", {}).items():
        if not name.startswith(slot + " "):
            continue
        c = max(v["core0"], v["core1"])
        if best is None or c > best[0]:
            best = (c, name)
    return best


def bound(cat, name, limit=None, without=()):
    """-> dict: the worst-case load of each core, the effects that set it, what has no cost, the verdict.
    without: effects left out of the bound, to see what a remix would be without them."""
    limit = 100 * (limit if limit is not None else cat.get("limit", LIMIT))
    fx1, fx2, notes = effects_of(name)
    fx1, fx2 = [k for k in fx1 if k not in without], [k for k in fx2 if k not in without]
    if without:
        notes.append("without " + ", ".join(without))
    base = cat["bases"].get(name)
    out = {"remix": name, "limit": limit, "notes": notes, "fx1": {}, "fx2": {}, "unpriced": []}
    for slot, keys in (("FX1", fx1), ("FX2", fx2)):
        for k in keys:
            w = worst(cat, k, slot)
            if w is None:
                out["unpriced"].append(f"{k} {slot}")
            else:
                out["fx1" if slot == "FX1" else "fx2"][k] = w
    if base is None:
        out["verdict"] = f"UNKNOWN: no base measured for {name}"
        return out
    top = lambda d: max(d.items(), key=lambda kv: kv[1][0]) if d else (None, (0.0, ""))
    t1, t2 = top(out["fx1"]), top(out["fx2"])
    out["base"] = (base["core0"], base["core1"])
    out["worst_core"] = tuple(round(b + SLOTS_PER_KIND * t1[1][0] + SLOTS_PER_KIND * t2[1][0], 1)
                              for b in out["base"])
    out["set_by"] = (t1[0], t2[0])
    over = [i for i in (0, 1) if out["worst_core"][i] > limit]
    if out["unpriced"]:
        out["verdict"] = f"UNKNOWN: {len(out['unpriced'])} effect slot(s) with no measured cost"
    elif over:
        out["verdict"] = f"OVER: core {', core '.join(str(i) for i in over)} reaches " + \
            " / ".join(f"{out['worst_core'][i]:.1f} %" for i in over) + f" against {limit:.0f} %"
    else:
        out["verdict"] = "PASS"
    return out


def cmd_check(a):
    cat = load()
    r = bound(cat, a.remix, a.limit, tuple(a.without))
    print(f"{r['remix']}: limit {r['limit']:.0f} % of a frame per core")
    for n in r["notes"]:
        print(f"  note: {n}")
    if "base" in r:
        print(f"  base {r['base'][0]:.1f} / {r['base'][1]:.1f} %")
        for slot, key, d in (("FX1", r["set_by"][0], r["fx1"]), ("FX2", r["set_by"][1], r["fx2"])):
            if key:
                print(f"  {slot} slots (4 a core) are set by {key}: {d[key][0]:.2f} % at {d[key][1]}")
        print(f"  worst core load: {r['worst_core'][0]:.1f} % / {r['worst_core'][1]:.1f} %")
    for u in r["unpriced"]:
        print(f"  no measured cost: {u}")
    print(f"  {r['verdict']}")
    return 0 if r["verdict"] == "PASS" else 1


def cmd_table(a):
    cat = load()
    base = cat["bases"].get(a.remix) or next(iter(cat["bases"].values()), None)
    cap0 = (100 * cat["limit"] - base["core0"]) / (2 * SLOTS_PER_KIND) if base else None
    cap1 = (100 * cat["limit"] - base["core1"]) / (2 * SLOTS_PER_KIND) if base else None
    print(f"slot cost = points of a frame per slot; free everywhere = at or under "
          f"{cap0:.2f} % (core 0) and {cap1:.2f} % (core 1), the limit over 8 slots, "
          f"for base {base['core0']:.1f} / {base['core1']:.1f} %" if base else "no base")
    print(f"{'effect':22s} {'worst':>6s}  {'at':20s} {'settings':>8s} {'ColdFire':>9s}  free everywhere (* ColdFire share not in the sum)")
    for k in sorted(cat["effects"], key=lambda k: -max((worst(cat, k, s) or (0, ""))[0] for s in ("FX1", "FX2"))):
        ws = [w for w in (worst(cat, k, "FX1"), worst(cat, k, "FX2")) if w]
        w = max(ws)
        costs = cat["effects"][k]["costs"]
        cf = max(v["cf_over_base"] for v in costs.values())
        free = ("yes" if base and w[0] <= min(cap0, cap1) else "no") + ("*" if cf >= 3 else "")
        print(f"{k:22s} {w[0]:6.2f}  {w[1]:20s} {len(costs):8d} {cf:+8.1f}   {free}")
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("import"); p.add_argument("reports", nargs="+")
    p = sub.add_parser("table"); p.add_argument("--remix", default="octabam")
    p = sub.add_parser("check"); p.add_argument("remix"); p.add_argument("--limit", type=float)
    p.add_argument("--without", nargs="*", default=[], help="effects left out of the bound")
    a = ap.parse_args(argv)
    return {"import": cmd_import, "table": cmd_table, "check": cmd_check}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
