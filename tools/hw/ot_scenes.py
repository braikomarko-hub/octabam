#!/usr/bin/env python3
"""Stamp MIDI SCENES locks, a MIDI track and MIDI trigs into a project's files, and read scenes.work back.

    python3 tools/hw/ot_scenes.py show PROJECT_DIR
    python3 tools/hw/ot_scenes.py stamp PROJECT_DIR [--channel 11] [--trigs none|grid4|every]
                                        [--lock SCENE:TRACK:FLAT=VALUE ...] [--all-scenes] [--pattern-steps N=S,S,...] [--banks 1-16]

`stamp` edits PROJECT_DIR in place (copy a pristine project first). project.work and project.strd get
ot_matrix's run settings (clock and transport receive on, program change receive, per-track trig channels, project
opens on A01 unmuted). In every Part of the chosen banks: MIDI track 1
on --channel, its CC1..CC10 enabled, scene A = scene 1, scene B = scene 9. In every pattern of those banks, MIDI
track 1 gets --trigs (grid4: steps 4, 8, 12, 16; every: all 64; step s is bit s - 1 of the 64-bit mask,
the encoding of ot_project.set_pattern_trig). --pattern-steps N=S,S,... gives pattern N (1-16) exactly those steps. Every Part's lock table in scenes.work (and
scenes.strd) gets the --lock entries; the default is CC 1 on track 1 (flat 21): 40 in scene A, 100 in scene B.
--all-scenes locks that knob in all 16 scenes, scene s at 8 + 7 * s.

scenes.work (modules/midi-scenes/scenes.s): 16-byte header ('MSCW', version 1, payload length 262,144, CRC-32 of the
payload; big-endian), then 64 slots of 4,096 bytes, slot = 4 * bank + Part (0-based). An entry is at
`scene << 8 | track << 5 | flat`, 0xff = no lock; flat = MIDI page * 6 + knob (NOTE, LFO, ARP, CTRL1, CTRL2).
The bank-file offsets are the ones tools/verify/verify_scenes.py stages its fixture with.
"""
import argparse
import pathlib
import struct
import sys
import zlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

FILE_PART, FILE_PSTRIDE, NPARTS_FILE = 0x8eed6, 0x18bb, 8
MIDI_SETUP, MIDI_PARAMS, SCENE_A, SCENE_B = 0x4e2, 0x3e2, 0x10, 0x11
PTRN0, PTRN_FSTRIDE, MIDI_MASK = 0x16, 0x8eec, 0x4918
HDR, SLOT, NSLOTS = 16, 4096, 64
DEFAULT_LOCKS = {(0, 0, 21): 40, (8, 0, 21): 100}


def lock_index(scene, track, flat):
    return scene << 8 | track << 5 | flat


def parse_banks(s):
    lo, _, hi = s.partition("-")
    return range(int(lo), int(hi or lo) + 1)


def read_table(path):
    d = path.read_bytes()
    if len(d) != HDR + NSLOTS * SLOT or d[:8] != b"MSCW\0\0\0\1":
        sys.exit(f"{path}: not a scenes.work (size {len(d)}, magic {d[:8]!r})")
    if struct.unpack(">I", d[12:16])[0] != zlib.crc32(d[HDR:]):
        sys.exit(f"{path}: CRC-32 does not match the payload")
    return bytearray(d[HDR:])


def write_table(pdir, payload):
    d = b"MSCW\0\0\0\1" + struct.pack(">II", len(payload), zlib.crc32(payload)) + bytes(payload)
    for suffix in ("work", "strd"):
        (pdir / f"scenes.{suffix}").write_bytes(d)


def cmd_show(a):
    pdir = pathlib.Path(a.project)
    path = pdir / "scenes.work"
    if not path.is_file():
        print("no scenes.work (empty)"); return
    t = read_table(path)
    for slot in range(NSLOTS):
        ents = [(i, v) for i, v in enumerate(t[slot * SLOT:(slot + 1) * SLOT]) if v != 0xff]
        if ents:
            print(f"bank {slot // 4 + 1} part {slot % 4 + 1}: " +
                  " ".join(f"s{i >> 8}.t{(i >> 5) & 7}.f{i & 31}={v}" for i, v in ents))


def stamp_bank(path, channel, trigs, pattern_steps):
    d = bytearray(path.read_bytes())
    for part in range(NPARTS_FILE):
        o = FILE_PART + part * FILE_PSTRIDE + 9
        d[o + MIDI_SETUP] = channel
        d[o + MIDI_PARAMS + 30], d[o + MIDI_PARAMS + 31] = 0x3c, 0x3f
        d[o + SCENE_A], d[o + SCENE_B] = 0, 8
    default = {"none": 0, "grid4": 0x8888, "every": (1 << 64) - 1}[trigs]
    for pat in range(16):
        bits = default
        m = PTRN0 + pat * PTRN_FSTRIDE + MIDI_MASK + 9
        if pat + 1 in pattern_steps:
            bits = sum(1 << (s - 1) for s in pattern_steps[pat + 1])
        d[m:m + 8] = bits.to_bytes(8, "big")
    d[-2:] = (sum(d[0x10:-2]) & 0xffff).to_bytes(2, "big")
    path.write_bytes(bytes(d))


def cmd_stamp(a):
    pdir = pathlib.Path(a.project)
    locks = dict(DEFAULT_LOCKS)
    if a.lock:
        locks = {}
        for spec in a.lock:
            key, _, val = spec.partition("=")
            scene, track, flat = map(int, key.split(":"))
            locks[(scene, track, flat)] = int(val)
    if a.all_scenes:
        locks = {(s, 0, 21): 8 + 7 * s for s in range(16)}
    steps = {}
    for spec in a.pattern_steps or []:
        n, _, lst = spec.partition("=")
        steps[int(n)] = [int(x) for x in lst.split(",")]
    banks = parse_banks(a.banks)
    for b in banks:
        for suffix in ("work", "strd"):
            p = pdir / f"bank{b:02d}.{suffix}"
            if p.is_file():
                stamp_bank(p, a.channel, a.trigs, steps)
    payload = bytearray(b"\xff" * (NSLOTS * SLOT))
    for b in banks:
        for part in range(4):
            base = ((b - 1) * 4 + part) * SLOT
            for (scene, track, flat), v in locks.items():
                payload[base + lock_index(scene, track, flat)] = v
    write_table(pdir, payload)
    import ot_matrix
    changed = ot_matrix.stamp_text(pdir, ot_matrix.test_settings(), ot_matrix.TEST_STATES)
    for key, (old, new) in sorted(changed.items()):
        print(f"project.work {key}: {old} -> {new}")
    print(f"{pdir}: banks {banks.start}-{banks.stop - 1}, MIDI T1 ch {a.channel}, trigs {a.trigs}, "
          f"{len(locks)} lock(s) per Part")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("show"); s.add_argument("project"); s.set_defaults(fn=cmd_show)
    s = sub.add_parser("stamp"); s.add_argument("project")
    s.add_argument("--channel", type=int, default=11)
    s.add_argument("--trigs", choices=("none", "grid4", "every"), default="grid4")
    s.add_argument("--lock", action="append", metavar="SCENE:TRACK:FLAT=VALUE")
    s.add_argument("--all-scenes", action="store_true")
    s.add_argument("--pattern-steps", action="append", metavar="N=S,S,...")
    s.add_argument("--banks", default="1-16")
    s.set_defaults(fn=cmd_stamp)
    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
