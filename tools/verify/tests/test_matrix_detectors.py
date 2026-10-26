"""tools/hw/ot_matrix.py's detectors on synthetic audio: a clean copy of BASE is
unflagged; a click train, added noise, a dropout, a level drop, silence and
clipping each raise their flag. No unit and no firmware."""
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "hw"))

try:
    import numpy as np
except ImportError:                     # pragma: no cover
    np = None


@unittest.skipIf(np is None, "numpy is not installed")
class MatrixDetectors(unittest.TestCase):
    FS = 44100

    @classmethod
    def setUpClass(cls):
        import ot_matrix
        cls.m = ot_matrix
        rng = np.random.default_rng(1)
        t = np.arange(cls.FS * 12) / cls.FS
        env = np.exp(-((t * 2) % 1) * 6)
        cls.sig = (0.3 * np.sin(2 * np.pi * 220 * t) * env + 1e-4 * rng.standard_normal(len(t))).astype(np.float32)
        cls.rng = rng
        cls.base = ot_matrix.measure(cls.stereo(cls.sig), cls.FS, 12)

    @staticmethod
    def stereo(s):
        return np.stack([s, s], axis=1)

    def flags(self, s):
        return self.m.judge(self.m.measure(self.stereo(s), self.FS, 12), self.base)

    def test_clean_copy(self):
        self.assertEqual(self.flags(self.sig.copy())[0], [])

    def test_clicks(self):
        s = self.sig.copy()
        for i in range(20):
            s[self.FS + i * 4000] += 0.4
        self.assertIn("CLICKS", self.flags(s)[0])
        self.assertNotIn("ROUGH", self.flags(s)[0])

    def test_dense_events_are_rough_not_clicks(self):
        t = np.arange(len(self.sig)) / self.FS
        saw = (0.3 * ((t * 333.0) % 1.0 - 0.5)).astype(np.float32)           # a hard sawtooth: edges in every block
        f = self.flags(saw)[0]
        self.assertIn("ROUGH", f)
        self.assertNotIn("CLICKS", f)

    def test_static(self):
        s = self.sig + (0.02 * self.rng.standard_normal(len(self.sig))).astype(np.float32)
        self.assertIn("STATIC", self.flags(s)[0])

    def test_dropout_is_a_freeze_at_its_second(self):
        s = self.sig.copy()
        s[5 * self.FS:7 * self.FS] = 0
        flags, at = self.flags(s)
        self.assertIn("FREEZE", flags)
        self.assertEqual(at, [5.0])

    def test_a_layout_still_sounding_after_stop_rings(self):
        play = self.sig
        ring = np.concatenate([play, (0.05 * np.sin(2 * np.pi * 440 * np.arange(3 * self.FS) / self.FS)).astype(np.float32)])
        quiet = np.concatenate([play, np.zeros(3 * self.FS, dtype=np.float32)])
        base = self.m.measure(self.stereo(quiet), self.FS, 12)
        self.assertNotIn("RINGS", self.m.judge(self.m.measure(self.stereo(quiet), self.FS, 12), base)[0])
        self.assertIn("RINGS", self.m.judge(self.m.measure(self.stereo(ring), self.FS, 12), base)[0])
        held = np.concatenate([play, np.full(3 * self.FS, 0.1, dtype=np.float32)])
        f = self.m.judge(self.m.measure(self.stereo(held), self.FS, 12), base)[0]
        self.assertIn("DC", f)
        self.assertNotIn("RINGS", f)

    def test_a_halved_frame_rate_is_an_overload(self):
        m = self.m.measure(self.stereo(self.sig), self.FS, 12)
        full = {"windows": 5, "irq_per_s_median": 2756.0, "cf_share_max": 0.3, "dsp_core0_max": 0.5, "dsp_core1_max": 0.4}
        half = dict(full, irq_per_s_median=1378.0)
        self.assertNotIn("OVERLOAD", self.m.judge(m, self.base, full)[0])
        self.assertIn("OVERLOAD", self.m.judge(m, self.base, half)[0])

    def test_bad_records_in_the_window_are_drops(self):
        m = self.m.measure(self.stereo(self.sig), self.FS, 12)
        ok = {"windows": 5, "irq_per_s_median": 2756.0, "bad_records": 0, "cf_share_max": 0.3, "dsp_core0_max": 0.5, "dsp_core1_max": 0.4}
        self.assertNotIn("DROPS", self.m.judge(m, self.base, ok)[0])
        self.assertIn("DROPS", self.m.judge(m, self.base, dict(ok, bad_records=2950, irq_per_s_median=2560.0))[0])

    def test_level(self):
        self.assertIn("LEVEL", self.flags(self.sig * 0.2)[0])

    def test_silence_is_a_crash(self):
        self.assertEqual(self.flags(np.zeros_like(self.sig))[0], ["CRASH"])

    def test_clip(self):
        self.assertIn("CLIP", self.flags(np.clip(self.sig * 4, -1, 1))[0])


if __name__ == "__main__":
    unittest.main()


@unittest.skipIf(np is None, "numpy is not installed")
class MatrixStimuliProject(unittest.TestCase):
    """The pieces of `ot_matrix.py proj --stimuli` that need no source project."""

    @classmethod
    def setUpClass(cls):
        import ot_matrix
        cls.m = ot_matrix

    def test_round_robin_assignment(self):
        self.assertEqual(self.m.stim_assign(["a", "b", "c"], [1, 2, 3, 4, 5]),
                         [(0, 1), (1, 2), (2, 3), (3, 1), (4, 2)])

    def test_sample_blocks_replace_only_the_named_slots(self):
        import tempfile
        import pathlib
        with tempfile.TemporaryDirectory() as d:
            d = pathlib.Path(d)
            old = (b"[SAMPLE]\r\nTYPE=FLEX\r\nSLOT=001\r\nPATH=old.wav\r\n[/SAMPLE]\r\n\r\n"
                   b"[SAMPLE]\r\nTYPE=FLEX\r\nSLOT=129\r\nPATH=\r\n[/SAMPLE]\r\n\r\n")
            for f in ("project.work", "project.strd"):
                (d / f).write_bytes(b"HEAD\r\n" + old)
            self.m._stim_text(d, ["hits", "pink"], {"hits": 176400, "pink": 352800})
            t = (d / "project.work").read_bytes().decode()
            self.assertNotIn("old.wav", t)
            self.assertIn("SLOT=129", t)
            self.assertIn("SLOT=001\r\nPATH=hits.wav\r\nTRIM_BARSx100=200", t)
            self.assertIn("SLOT=002\r\nPATH=pink.wav\r\nTRIM_BARSx100=400", t)
            self.assertEqual((d / "project.work").read_bytes(), (d / "project.strd").read_bytes())

    def test_markers_hold_the_trim_end_and_a_valid_sum(self):
        import struct
        import tempfile
        import pathlib
        with tempfile.TemporaryDirectory() as d:
            d = pathlib.Path(d)
            (d / "markers.work").write_bytes(bytes(0x16 + 784 * 4 + 2))
            self.m._stim_markers(d, ["hits", "pink"], {"hits": 176400, "pink": 352800})
            b = (d / "markers.work").read_bytes()
            self.assertEqual(struct.unpack(">III", b[0x16:0x16 + 12]), (0, 176400, 0))
            self.assertEqual(struct.unpack(">III", b[0x16 + 784:0x16 + 784 + 12]), (0, 352800, 0))
            self.assertEqual(int.from_bytes(b[-2:], "big"), sum(b[0x10:-2]) & 0xFFFF)


@unittest.skipIf(np is None, "numpy is not installed")
class MatrixProjectText(unittest.TestCase):
    TEXT = (b"[SETTINGS]\r\nTEMPOx24=2908\r\nMIDI_CLOCK_RECEIVE=0\r\nMIDI_TRANSPORT_RECEIVE=1\r\n"
            b"MIDI_PROGRAM_CHANGE_RECEIVE_CH=-1\r\n[/SETTINGS]\r\n\r\n[STATES]\r\nBANK=2\r\nTRACK_MUTE_MASK=127\r\n[/STATES]\r\n")

    @classmethod
    def setUpClass(cls):
        import ot_matrix
        cls.m = ot_matrix

    def stamp(self, settings, states):
        import pathlib
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            d = pathlib.Path(d)
            for f in ("project.work", "project.strd"):
                (d / f).write_bytes(self.TEXT)
            changed = self.m.stamp_text(d, settings, states)
            return changed, (d / "project.work").read_bytes().decode(), (d / "project.strd").read_bytes().decode()

    def test_keys_change_in_both_files_and_nothing_else(self):
        changed, work, strd = self.stamp({"MIDI_CLOCK_RECEIVE": 1, "MIDI_PROGRAM_CHANGE_RECEIVE_CH": 0, "TEMPOx24": 2880},
                                         {"BANK": 0, "TRACK_MUTE_MASK": 0})
        self.assertEqual(work, strd)
        self.assertIn("MIDI_CLOCK_RECEIVE=1\r\n", work)
        self.assertIn("MIDI_PROGRAM_CHANGE_RECEIVE_CH=0\r\n", work)
        self.assertIn("MIDI_TRANSPORT_RECEIVE=1\r\n", work)
        self.assertIn("BANK=0\r\nTRACK_MUTE_MASK=0\r\n", work)
        self.assertEqual(changed, {"MIDI_CLOCK_RECEIVE": [0, 1], "MIDI_PROGRAM_CHANGE_RECEIVE_CH": [-1, 0],
                                   "TEMPOx24": [2908, 2880], "BANK": [2, 0], "TRACK_MUTE_MASK": [127, 0]})

    def test_a_missing_key_is_refused(self):
        with self.assertRaises(SystemExit):
            self.stamp({"NO_SUCH_KEY": 1}, {})

    def test_the_test_settings_name_keys_the_unit_writes(self):
        s = self.m.test_settings(3)
        self.assertEqual(s["MIDI_PROGRAM_CHANGE_RECEIVE_CH"], 2)
        self.assertEqual([s[f"MIDI_TRIG_CH{t}"] for t in range(1, 9)], list(range(8)))


@unittest.skipIf(np is None, "numpy is not installed")
class MatrixPredictor(unittest.TestCase):
    """predict: per-core busy of a layout from single-effect runs (no unit, no firmware)."""

    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2]))
        import toolpath  # noqa: F401
        import ot_matrix
        from remix import registry
        cls.m, cls.mods = ot_matrix, registry.modules()

    def report(self, d, slots_by_name):
        """A report.json with BASE and the named single-effect layouts: {name: {slot: mean_counts}}."""
        import json
        base_slots = {f"{c}{p}.{k}": {"mean_counts": 100.0} for c in "AB" for p in range(1, 5) for k in ("FX1", "FX2")}
        res = [{"slot": 0, "name": "BASE", "load": {"dsp_core0_mean": 0.20, "dsp_core1_mean": 0.10, "windows": 5, "slots": base_slots}}]
        for i, (name, over) in enumerate(slots_by_name.items(), 1):
            sl = {k: dict(v) for k, v in base_slots.items()}
            for k, v in over.items():
                sl[k] = {"mean_counts": v}
            res.append({"slot": i, "name": name, "load": {"dsp_core0_mean": 0.5, "dsp_core1_mean": 0.5, "windows": 5, "slots": sl}})
        path = pathlib.Path(d) / "report.json"
        path.write_text(json.dumps({"remix": "octabam-inserts", "project": "p", "results": res}))
        return str(path)

    def test_the_sum_over_the_slots_of_each_core(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            spec_cost = {f"{c}{p}.FX1": 100.0 + 3625.6 for c in "AB" for p in range(1, 5)}      # +0.10 of a frame per slot
            lofi_cost = {f"{c}{p}.FX2": 100.0 + 7251.2 for c in "AB" for p in range(1, 5)}      # +0.20 per slot
            table = self.m.build_costs([self.report(d, {"SPECTRUM FX1 dear": spec_cost, "LOFI2 FX2 dear": lofi_cost})])
        dear = lambda k: (k, dict(getattr(self.mods[k], "dear", None) or {}))                  # noqa: E731
        lo = {t: (dear("SPECTRUM") if t >= 5 else None, dear("LOFI2") if t <= 2 else None) for t in range(1, 9)}
        c0, c1, miss = self.m.predict_layout(lo, table, self.mods)
        self.assertEqual(miss, [])
        self.assertAlmostEqual(c0, 0.20 + 4 * 0.10, places=6)          # four SPECTRUM slots on core 0
        self.assertAlmostEqual(c1, 0.10 + 2 * 0.20, places=6)          # two LOFI2 slots on core 1

    def test_an_effect_without_a_single_run_is_reported(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            table = self.m.build_costs([self.report(d, {})])
        lo = {t: (("SPECTRUM", dict(self.mods["SPECTRUM"].dear)), None) for t in range(1, 9)}
        _c0, _c1, miss = self.m.predict_layout(lo, table, self.mods)
        self.assertEqual(len(miss), 8)


@unittest.skipIf(np is None, "numpy is not installed")
class MatrixSwitch(unittest.TestCase):
    """switch: the metrics around a program change during play, on synthetic readings and audio."""

    FS = 44100

    @classmethod
    def setUpClass(cls):
        import ot_matrix
        cls.m = ot_matrix

    def rows(self, spike_us=None, dsp_spike=None, bad_jump=0):
        out = []
        for i in range(int(14 * 50)):
            t = i / 50.0
            busy = 0.25 if t < 8.0 else 0.85
            if dsp_spike and 8.0 <= t < 8.06:
                busy = dsp_spike
            lon = spike_us if spike_us and 8.0 <= t < 8.06 else 105.0
            bad = 2 + (bad_jump if t >= 8.0 else 0)
            out.append({"t": 1000.0 + t, "cf": {"longest_us": lon},
                        "dsp": {"core0": {"busy": int(busy * 36256), "period": 36256},
                                "core1": {"busy": int(busy * 0.8 * 36256), "period": 36256}, "bad": bad}})
        return out

    def audio(self, gap_ms=0):
        rng = np.random.default_rng(3)
        x = (0.05 * rng.standard_normal((14 * self.FS, 2))).astype(np.float64)
        if gap_ms:
            i = int(8.05 * self.FS)
            x[i:i + int(gap_ms / 1000 * self.FS)] = 0
        return x

    def test_a_clean_switch(self):
        mt = self.m.switch_metrics(self.rows(), self.audio(), self.FS, 1000.0)
        self.assertAlmostEqual(mt["t_switch_s"], 8.0, delta=0.1)
        self.assertEqual(self.m.switch_flags(mt), [])

    def test_a_cf_spike_a_dsp_spike_drops_and_a_gap_each_raise_their_flag(self):
        mt = self.m.switch_metrics(self.rows(spike_us=300.0, dsp_spike=0.95, bad_jump=500), self.audio(gap_ms=80), self.FS, 1000.0)
        f = self.m.switch_flags(mt)
        for want in ("SPIKE_CF", "SPIKE_DSP", "DROPS", "GAP"):
            self.assertIn(want, f)

    def test_equal_levels_fall_back_to_the_nominal_pattern_end(self):
        rows = self.rows()
        for r in rows:
            r["dsp"]["core0"]["busy"] = 9000
        mt = self.m.switch_metrics(rows, self.audio(), self.FS, 1000.0)
        self.assertEqual(mt["t_switch_s"], 8.0)
