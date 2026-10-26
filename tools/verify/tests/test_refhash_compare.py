"""refhash_compare: artifacts gate; rc=0 reports ignored; rc!=0 reports strict."""
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import refhash_compare as C  # noqa: E402

# Minimal 24-case shape: one shipping layout, one refusal, one render.
BASE = """\
case bus rc=0
  aaa0000000000000000000000000000000000000000000000000000000000000  out/mainos_bus.bin
  rrr0000000000000000000000000000000000000000000000000000000000000  <report>
case plain rc=1
  ppp0000000000000000000000000000000000000000000000000000000000000  <report>
case render rc=0
  bbb0000000000000000000000000000000000000000000000000000000000000  out/mainos_bus_dev.bin
  sss0000000000000000000000000000000000000000000000000000000000000  <report>
"""


def exit_of(baseline: str, current: str) -> int:
    with tempfile.TemporaryDirectory() as d:
        d = pathlib.Path(d)
        b, c = d / "b.txt", d / "c.txt"
        b.write_text(baseline)
        c.write_text(current)
        return C.main([str(b), str(c)])


class Compare(unittest.TestCase):
    def test_identical_exits_0(self):
        self.assertEqual(exit_of(BASE, BASE), 0)

    def test_every_report_hash_changed_exits_0(self):
        # every rc=0 <report> hash moves; plain (rc=1) is left alone.
        cur = (BASE
               .replace("rrr0000000000000000000000000000000000000000000000000000000000000",
                        "rrr1111111111111111111111111111111111111111111111111111111111111")
               .replace("sss0000000000000000000000000000000000000000000000000000000000000",
                        "sss1111111111111111111111111111111111111111111111111111111111111"))
        self.assertEqual(exit_of(BASE, cur), 0)

    def test_one_artifact_hash_changed_exits_1(self):
        cur = BASE.replace(
            "aaa0000000000000000000000000000000000000000000000000000000000000",
            "aaa1111111111111111111111111111111111111111111111111111111111111")
        self.assertEqual(exit_of(BASE, cur), 1)

    def test_return_code_changed_exits_1(self):
        cur = BASE.replace("case bus rc=0", "case bus rc=1")
        self.assertEqual(exit_of(BASE, cur), 1)

    def test_rc1_case_report_only_change_exits_1(self):
        # Sam's fifth row: plain rc=1 with only its <report> moved must fail
        # (the report is the only line for a refusal).
        cur = BASE.replace(
            "ppp0000000000000000000000000000000000000000000000000000000000000",
            "ppp1111111111111111111111111111111111111111111111111111111111111")
        self.assertEqual(exit_of(BASE, cur), 1)

    def test_changed_report_on_rc1_case_exits_1(self):
        # Explicit twin of the row above (Sam asked for both).
        cur = BASE.replace(
            "ppp0000000000000000000000000000000000000000000000000000000000000  <report>",
            "deadbeef00000000000000000000000000000000000000000000000000000000  <report>")
        self.assertEqual(exit_of(BASE, cur), 1)

    def exit_with_logs(self, base_log: str, cur_log: str) -> int:
        cur = BASE.replace(
            "ppp0000000000000000000000000000000000000000000000000000000000000",
            "ppp1111111111111111111111111111111111111111111111111111111111111")
        with tempfile.TemporaryDirectory() as d:
            d = pathlib.Path(d)
            (d / "baseline").mkdir()
            (d / "current").mkdir()
            (d / "baseline" / "manifest.txt").write_text(BASE)
            (d / "current" / "manifest.txt").write_text(cur)
            (d / "baseline" / "plain.log").write_text(base_log)
            (d / "current" / "plain.log").write_text(cur_log)
            return C.main([str(d / "baseline" / "manifest.txt"), str(d / "current" / "manifest.txt")])

    def test_rc1_report_differing_only_in_membership_lines_exits_0(self):
        # a module's `replaces` moves it between "LEFT STOCK" and "not in this remix"
        base = "refused: no XBUS\n  not in this remix, LEFT STOCK: A, B -- why\n  not in this remix: C -- alias\n"
        cur = "refused: no XBUS\n  not in this remix, LEFT STOCK: A -- why\n  not in this remix: B, C -- alias\n"
        self.assertEqual(self.exit_with_logs(base, cur), 0)

    def test_rc1_report_with_another_refusal_reason_exits_1(self):
        base = "refused: no XBUS\n  not in this remix: C -- alias\n"
        cur = "refused: something else\n  not in this remix: C -- alias\n"
        self.assertEqual(self.exit_with_logs(base, cur), 1)


if __name__ == "__main__":
    unittest.main()
