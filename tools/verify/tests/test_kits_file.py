"""tools/hw/ot_kits.py on a version-2 kits.work built here (the layout is modules/kits/README.md "Files"):
parse, assignment, the CRC kept right, and rotate moving patterns along the Kits in use."""
import pathlib
import struct
import sys
import tempfile
import unittest
import zlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "hw"))


def blank():
    k = sys.modules["ot_kits"]
    d = bytearray(k.LENGTH_V2)
    d[:4] = b"KITS"
    d[4:8] = struct.pack(">I", 2)
    d[8:12] = struct.pack(">I", k.LENGTH_V2)
    d[k.O_ASSIGN:k.O_ASSIGN + 256] = b"\xff" * 256
    d[k.O_RESID:k.O_RESID + 64] = b"\xff" * 64
    for i in range(256):
        o = k.O_REC + i * k.REC
        d[o + 8:o + 16] = b"\xff" * 8
        d[o + 16 + 6322:o + k.REC] = b"\xff" * 4096
    k.fix_crc(d)
    return d


class KitsFile(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import ot_kits
        cls.k = ot_kits

    def with_kits(self, n):
        d = blank()
        for kit in range(n):
            d[self.k.O_VALID + kit // 8] |= 1 << (kit % 8)
            o = self.k.O_REC + kit * self.k.REC
            d[o:o + 8] = f"K{kit:03d}".encode().ljust(8, b"\0")
        for p in range(n):
            d[self.k.O_ASSIGN + p] = p
        self.k.fix_crc(d)
        return bytes(d)

    def test_parse_checks_magic_length_and_crc(self):
        d = self.with_kits(4)
        self.assertEqual(self.k.parse(d)["assign"][:4], [0, 1, 2, 3])
        bad = bytearray(d); bad[1000] ^= 1
        with self.assertRaises(ValueError):
            self.k.parse(bytes(bad))
        with self.assertRaises(ValueError):
            self.k.parse(b"NOPE" + d[4:])

    def test_the_crc_is_over_everything_after_the_header(self):
        d = self.with_kits(2)
        self.assertEqual(struct.unpack(">I", d[12:16])[0], zlib.crc32(d[64:]) & 0xFFFFFFFF)
        self.assertEqual(struct.unpack(">I", d[8:12])[0], len(d))                 # the length field is not the CRC

    def test_valid_bits_and_names(self):
        d = self.with_kits(10)
        self.assertTrue(self.k.is_valid(d, 9) and not self.k.is_valid(d, 10))
        self.assertEqual(self.k.kit_name(d, 3), "K003")

    def test_set_assign_keeps_the_file_valid_and_refuses_an_empty_kit(self):
        d = self.with_kits(4)
        e = self.k.set_assign(d, {2: 0, 3: 1})
        self.assertEqual(self.k.parse(bytes(e))["assign"][:4], [0, 1, 0, 1])
        with self.assertRaises(ValueError):
            self.k.set_assign(d, {0: 9})

    def test_rotate_moves_each_pattern_to_the_next_kit_in_use(self):
        with tempfile.TemporaryDirectory() as t:
            self.k.write_project(t, self.with_kits(4))
            ns = type("A", (), {"project": t, "n": 1, "patterns": ""})
            self.k.cmd_rotate(ns)
            self.assertEqual(self.k.parse((pathlib.Path(t) / "kits.work").read_bytes())["assign"][:4], [1, 2, 3, 0])
            self.assertEqual((pathlib.Path(t) / "kits.work").read_bytes(), (pathlib.Path(t) / "kits.strd").read_bytes())


if __name__ == "__main__":
    unittest.main()
