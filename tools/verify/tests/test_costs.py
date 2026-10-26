"""tools/remix/costs.py: reading a matrix report, merging it, and bounding a remix.

The report here is built by hand, in the shape `ot_matrix.py run` writes
(`results[]` with `name`, `flags`, `load.dsp_core0_mean`, ...).
"""
import json
import pathlib
import sys
import tempfile
import unittest

TOOLS = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(TOOLS)); import toolpath  # noqa: E402,F401
from remix import costs  # noqa: E402


def layout(name, c0, c1, cf=0.61, flags=()):
    return {"name": name, "flags": list(flags),
            "load": {"dsp_core0_mean": c0, "dsp_core1_mean": c1, "cf_share_mean": cf}}


def report(tmp, label, results, remix="octabam-inserts"):
    d = pathlib.Path(tmp) / label
    d.mkdir()
    (d / "report.json").write_text(json.dumps({"remix": remix, "results": results}))
    return d / "report.json"


class Reading(unittest.TestCase):
    def test_slot_cost_is_a_quarter_of_the_busy_rise(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = report(tmp, "r1", [layout("BASE", 0.20, 0.10),
                                   layout("EUCLID FX1 def", 0.40, 0.30, cf=0.68)])
            label, remix, base, rows, skipped = costs.parse_report(p)
        self.assertEqual((label, remix), ("r1", "octabam-inserts"))
        self.assertEqual([round(x, 1) for x in base], [20.0, 10.0, 61.0])
        (e, slot, variant, c0, c1, cf), = rows
        self.assertEqual((e, slot, variant), ("EUCLID", "FX1", "def"))
        self.assertAlmostEqual(c0, 5.0)
        self.assertAlmostEqual(c1, 5.0)
        self.assertAlmostEqual(cf, 68.0)

    def test_pairs_splits_and_overloaded_layouts_are_not_read(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = report(tmp, "r2", [
                layout("BASE", 0.20, 0.10),
                layout("EUCLID FX1 + LOFI2 FX2 dear", 0.90, 0.80),
                layout("MODULATION FX2 T1-4 + SPECTRUM T5-8 (split)", 0.5, 0.5),
                layout("LOFI2 FX2 dear", 1.20, 1.10, flags=["OVERLOAD"]),
                layout("LOFI2 FX2 def", 0.40, 0.30, flags=["LEVEL"])])
            _, _, _, rows, skipped = costs.parse_report(p)
        self.assertEqual([(r[0], r[2]) for r in rows], [("LOFI2", "def")])
        self.assertEqual(skipped, ["LOFI2 FX2 dear"])

    def test_a_report_without_a_base_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = report(tmp, "r3", [layout("EUCLID FX1 def", 0.4, 0.3)])
            with self.assertRaises(ValueError):
                costs.parse_report(p)

    def test_the_newest_report_replaces_an_effect_slot_and_keeps_the_other_slot(self):
        cat = {"limit": 0.95, "bases": {}, "effects": {}}
        costs.merge(cat, "old", "octabam-inserts", (20.0, 10.0, 61.0),
                    [("MODULATION", "FX1", "mode0", 10.0, 10.0, 61.0),
                     ("MODULATION", "FX1", "mode9", 11.0, 11.0, 61.0),
                     ("MODULATION", "FX2", "mode0", 10.0, 10.0, 61.0)])
        costs.merge(cat, "new", "octabam-inserts", (21.0, 10.0, 61.0),
                    [("MODULATION", "FX1", "mode0", 7.0, 7.0, 61.0)])
        c = cat["effects"]["MODULATION"]["costs"]
        self.assertEqual(sorted(c), ["FX1 mode0", "FX2 mode0"])
        self.assertEqual(c["FX1 mode0"]["core0"], 7.0)
        self.assertEqual(c["FX2 mode0"]["report"], "old")
        self.assertEqual(cat["bases"]["octabam-inserts"]["core0"], 21.0)    # the dearest base seen


class Bounding(unittest.TestCase):
    def setUp(self):
        self.cat = {"limit": 0.95, "bases": {"r": {"core0": 20.0, "core1": 10.0}}, "effects": {
            "A": {"costs": {"FX1 def": {"core0": 5.0, "core1": 5.0}, "FX2 def": {"core0": 5.0, "core1": 5.0}}},
            "B": {"costs": {"FX2 dear": {"core0": 15.0, "core1": 14.0}, "FX2 def": {"core0": 8.0, "core1": 8.0}}}}}
        self._effects_of = costs.effects_of
        costs.effects_of = lambda name: (["A"], ["A", "B"], [])

    def tearDown(self):
        costs.effects_of = self._effects_of

    def test_worst_core_is_base_plus_four_dearest_fx1_plus_four_dearest_fx2(self):
        r = costs.bound(self.cat, "r")
        self.assertEqual(r["worst_core"], (20.0 + 4 * 5.0 + 4 * 15.0, 10.0 + 4 * 5.0 + 4 * 15.0))   # B at its dearest setting, on the dearer core
        self.assertTrue(r["verdict"].startswith("OVER"), r["verdict"])

    def test_leaving_an_effect_out_can_bring_a_remix_under(self):
        r = costs.bound(self.cat, "r", without=("B",))
        self.assertEqual(r["worst_core"], (60.0, 50.0))
        self.assertEqual(r["verdict"], "PASS")

    def test_an_unpriced_effect_is_unknown_not_pass(self):
        del self.cat["effects"]["B"]
        r = costs.bound(self.cat, "r")
        self.assertEqual(r["unpriced"], ["B FX2"])
        self.assertTrue(r["verdict"].startswith("UNKNOWN"))

    def test_no_base_is_unknown(self):
        self.assertTrue(costs.bound(self.cat, "other")["verdict"].startswith("UNKNOWN"))


class Shipped(unittest.TestCase):
    def test_every_effect_in_the_catalog_is_a_module(self):
        from remix import registry
        mods = registry.modules()
        cat = costs.load()
        self.assertTrue(cat["effects"], "slot_costs.json is empty")
        self.assertEqual([k for k in cat["effects"] if k not in mods], [])

    def test_every_cost_is_a_share_of_a_frame(self):
        for k, e in costs.load()["effects"].items():
            for name, v in e["costs"].items():
                self.assertTrue(-0.5 <= v["core0"] <= 30 and -0.5 <= v["core1"] <= 30, (k, name, v))


if __name__ == "__main__":
    unittest.main()
