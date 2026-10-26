#!/usr/bin/env python3
"""Compare two refhash manifests: artifacts must match; reports may differ.

    python3 tools/verify/refhash_compare.py BASELINE CURRENT

Exit 0 when every non-<report> artifact line matches (and every <report>
line of a case with rc!=0). Exit 1 on any other mismatch.

A replaces= module that joins LEFT STOCK rewrites every build-report hash
while the bins stay bit-identical (trap-report-api). CI baselines the
merge-base, so those PRs cannot re-save; artifact identity is the
behaviour gate. For a case that exits non-zero the report is often the
only line, so a different refusal reason must still fail; its log is compared
with the two "not in this remix" membership lines masked, because those list
which modules replace a stock effect and change whenever a module's
`replaces` does.
"""
import argparse
import pathlib
import re
import sys

CASE_RC = re.compile(r"^case (.+) rc=(\d+)$")
MEMBERSHIP = re.compile(r"^\s*not in this remix(, LEFT STOCK)?:.*$")


def masked_log(path: pathlib.Path) -> list[str] | None:
    """A case's build log with the module-membership lines masked, or None."""
    if not path.is_file():
        return None
    return [MEMBERSHIP.sub("  <membership>", l) for l in path.read_text().splitlines()]


def arts(text: str, bdir=None) -> dict[str, list[str]]:
    """Per-case lines that must match between manifests.

    Drop `<report>` lines when the case exited 0; keep them when rc != 0
    (those cases often have no artifact lines, so the report is the gate).
    """
    out: dict[str, list[str]] = {}
    case = None
    keep_report = False
    for line in text.splitlines():
        m = CASE_RC.match(line)
        if m:
            case = line
            keep_report = int(m.group(2)) != 0
            out[case] = []
        elif case and line.strip():
            if "<report>" in line and not keep_report:
                continue
            out[case].append(line)
    return out


def same_artifacts(baseline: str, current: str, bdir=None, cdir=None) -> bool:
    a, c = arts(baseline), arts(current)
    if a == c:
        return True
    if a.keys() != c.keys():
        return False
    for case in a:
        if a[case] == c[case]:
            continue
        m = CASE_RC.match(case)
        if not m or int(m.group(2)) == 0 or bdir is None or cdir is None:
            return False
        # only the <report> line may differ, and only in the membership lines
        if [l for l in a[case] if "<report>" not in l] != [l for l in c[case] if "<report>" not in l]:
            return False
        lb, lc = masked_log(bdir / f"{m.group(1)}.log"), masked_log(cdir / f"{m.group(1)}.log")
        if lb is None or lb != lc:
            return False
    return True


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("baseline", type=pathlib.Path)
    ap.add_argument("current", type=pathlib.Path)
    a = ap.parse_args(argv)
    ok = same_artifacts(a.baseline.read_text(), a.current.read_text(), a.baseline.parent, a.current.parent)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
