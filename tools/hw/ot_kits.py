#!/usr/bin/env python3
"""Read and rewrite a project's kits.work (KITS, version 2: with MIDI SCENES in the remix).

    python3 tools/hw/ot_kits.py show PROJECT_DIR                  # Kits present, the pattern assignment
    python3 tools/hw/ot_kits.py from-card CARD_AFTER.img OUT_DIR  # the kits.work the firmware wrote, out of a card image
    python3 tools/hw/ot_kits.py assign PROJECT_DIR 4:0 5:1 ...     # pattern index (16 * bank + pattern - 1) : Kit
    python3 tools/hw/ot_kits.py migrate PROJECT_DIR REMIX [--rotate N]   # the firmware makes the Kits (port), installs kits.work
    python3 tools/hw/ot_kits.py rotate PROJECT_DIR N [--patterns 0-3,16-19,...]   # pattern i plays Kit (i's Kit + N)

Layout (modules/kits/README.md "Files", version 2): 64-byte header (`KITS`, version, length, CRC-32 of everything
after the header, an unused word; big-endian), ASSIGN (256 bytes, a Kit number per pattern, 0xff none), VALID (32
bytes, Kit k is bit k % 8 of byte k // 8), RESID (64 bytes, the Kit resident in each Part slot, 0xff none), then 256
records of an 8-byte name, 8 reserved bytes, the 6,322-byte Part and a 4,096-byte lock table (version 2).
`.strd` is written as a byte copy of `.work`, as the project store does.

A Kit is a saved Part and the stimuli projects of `ot_matrix.py proj` stamp one Part per layout: after the firmware's
first load Kit `4 * bank + part` is that Part (the migration), and `rotate` then points patterns at other Kits so
the effects a pattern plays come from its Kit and not from the bank file's Part.
"""
import argparse
import pathlib
import struct
import sys
import zlib

HDR, ASSIGN, VALID, RESID, REC = 64, 256, 32, 64, 10434
O_ASSIGN, O_VALID, O_RESID, O_REC = HDR, HDR + ASSIGN, HDR + ASSIGN + VALID, HDR + ASSIGN + VALID + RESID
NKITS = 256
LENGTH_V2 = O_REC + NKITS * REC          # 2,671,520


def parse(data):
    if data[:4] != b"KITS":
        raise ValueError("not a kits.work (no KITS magic)")
    version, length, crc, _ = struct.unpack(">IIII", data[4:20])
    if length != len(data):
        raise ValueError(f"header length {length}, file {len(data)}")
    if zlib.crc32(data[HDR:]) & 0xFFFFFFFF != crc:
        raise ValueError("CRC-32 of the body does not match the header")
    if version != 2 or length != LENGTH_V2:
        raise ValueError(f"version {version}, {length} bytes: only version 2 ({LENGTH_V2} bytes) is handled")
    return {"version": version, "assign": list(data[O_ASSIGN:O_ASSIGN + ASSIGN]), "valid": data[O_VALID:O_VALID + VALID],
            "resid": list(data[O_RESID:O_RESID + RESID])}


def is_valid(data, k):
    return bool(data[O_VALID + k // 8] >> (k % 8) & 1)


def kit_name(data, k):
    return bytes(data[O_REC + k * REC:O_REC + k * REC + 8]).rstrip(b"\x00 ").decode("latin1")


def fix_crc(data):
    data[12:16] = struct.pack(">I", zlib.crc32(bytes(data[HDR:])) & 0xFFFFFFFF)         # magic, version, length, then the CRC
    return data


def set_assign(data, mapping):
    """mapping: {pattern index: Kit}. The Kit must be valid. Returns the changed copy."""
    d = bytearray(data)
    for p, k in mapping.items():
        if not 0 <= p < 256 or not (k == 0xFF or 0 <= k < 255):
            raise ValueError(f"pattern {p} / Kit {k}")
        if k != 0xFF and not is_valid(d, k):
            raise ValueError(f"Kit {k} is not a valid Kit in this file")
        d[O_ASSIGN + p] = k
    return fix_crc(d)


def write_project(pdir, data):
    pdir = pathlib.Path(pdir)
    (pdir / "kits.work").write_bytes(bytes(data))
    (pdir / "kits.strd").write_bytes(bytes(data))


def spans(text):
    out = []
    for part in text.split(","):
        a, _, b = part.partition("-")
        out += range(int(a), int(b or a) + 1)
    return out


def cmd_show(a):
    d = (pathlib.Path(a.project) / "kits.work").read_bytes()
    info = parse(d)
    kits = [k for k in range(NKITS) if is_valid(d, k)]
    print(f"{len(kits)} Kits: " + ", ".join(f"{k}:{kit_name(d, k) or '-'}" for k in kits[:40]) + (" ..." if len(kits) > 40 else ""))
    asg = [(p, v) for p, v in enumerate(info["assign"]) if v != 0xFF]
    print(f"{len(asg)} patterns assigned: " + " ".join(f"{p}->{v}" for p, v in asg[:48]) + (" ..." if len(asg) > 48 else ""))
    return 0


def cmd_from_card(a):
    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "emu"))
    import emu_card
    files = emu_card.extract_image(pathlib.Path(a.card).read_bytes())
    hits = {p: b for p, b in files.items() if p.lower().endswith("kits.work")}
    if not hits:
        sys.exit("no kits.work in that card image")
    path, data = sorted(hits.items())[0]
    parse(data)
    out = pathlib.Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "kits.work").write_bytes(data)
    (out / "kits.strd").write_bytes(data)
    print(f"{path}: {len(data)} bytes, CRC holds -> {out}")
    return 0


def cmd_assign(a):
    p = pathlib.Path(a.project)
    d = set_assign((p / "kits.work").read_bytes(), {int(x.split(":")[0]): int(x.split(":")[1]) for x in a.pairs})
    write_project(p, d)
    print(f"{len(a.pairs)} assignment(s) written")
    return 0


def cmd_rotate(a):
    p = pathlib.Path(a.project)
    d = (p / "kits.work").read_bytes()
    info = parse(d)
    pats = spans(a.patterns) if a.patterns else [i for i, v in enumerate(info["assign"]) if v != 0xFF]
    kits = [info["assign"][i] for i in pats]
    if any(k == 0xFF for k in kits):
        sys.exit("a chosen pattern has no Kit")
    pool = sorted(set(kits))
    mapping = {i: pool[(pool.index(info["assign"][i]) + a.n) % len(pool)] for i in pats}
    write_project(p, set_assign(d, mapping))
    print(f"{len(mapping)} patterns now play the Kit {a.n} further along the {len(pool)} Kits in use: "
          + " ".join(f"{i}->{k}" for i, k in list(mapping.items())[:16]) + (" ..." if len(mapping) > 16 else ""))
    return 0


def cmd_migrate(a):
    """Have the firmware migrate the project's stock Parts into Kits at its first load (a project with no kits.work), under
    the port, and install the kits.work it wrote. `--rotate N` then points every used pattern N Kits along."""
    import shutil
    import subprocess
    root = pathlib.Path(__file__).resolve().parents[2]
    tmp = root / "out" / f"_kits_migrate_{pathlib.Path(a.project).name}"
    if tmp.exists():
        shutil.rmtree(tmp)
    shutil.copytree(a.project, tmp, ignore=shutil.ignore_patterns("kits.*"))
    label = f"migrate_{pathlib.Path(a.project).name}"
    r = subprocess.run([str(root / ".venv/bin/python3"), str(root / "tools/hw/ot_fuzz.py"), "port", a.remix, str(tmp), label,
                        "--seeds", "1", "--seconds", "5", "--jobs", "1", "--keep-card"], cwd=root, capture_output=True, text=True)
    card = root / "out/fuzz_port" / label / "seed1.card"
    if not card.exists():
        sys.exit(f"the port run left no card image:\n{r.stdout[-600:]}{r.stderr[-400:]}")
    a2 = type("A", (), {"card": str(card), "out": str(pathlib.Path(a.project))})
    cmd_from_card(a2)
    shutil.rmtree(tmp)
    if a.rotate:
        used = [i for i, v in enumerate(parse((pathlib.Path(a.project) / "kits.work").read_bytes())["assign"]) if v != 0xFF]
        cmd_rotate(type("A", (), {"project": a.project, "n": a.rotate, "patterns": ",".join(map(str, used))}))
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("show"); p.add_argument("project")
    p = sub.add_parser("from-card"); p.add_argument("card"); p.add_argument("out")
    p = sub.add_parser("assign"); p.add_argument("project"); p.add_argument("pairs", nargs="+")
    p = sub.add_parser("migrate"); p.add_argument("project"); p.add_argument("remix")
    p.add_argument("--rotate", type=int, default=0, help="then point each used pattern this many Kits along")
    p = sub.add_parser("rotate"); p.add_argument("project"); p.add_argument("n", type=int); p.add_argument("--patterns", default="")
    a = ap.parse_args()
    return {"show": cmd_show, "from-card": cmd_from_card, "assign": cmd_assign, "rotate": cmd_rotate, "migrate": cmd_migrate}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main() or 0)
