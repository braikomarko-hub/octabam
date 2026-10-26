"""tools/hw/ot_stimuli.py: each stimulus has the level, spectrum and events its description says,
two renders are identical, the files round-trip, and a loop has no seam. No unit, no firmware."""
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "hw"))

try:
    import numpy as np
except ImportError:                     # pragma: no cover
    np = None


@unittest.skipIf(np is None, "numpy is not installed")
class Stimuli(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import ot_stimuli
        cls.s = ot_stimuli
        cls.r = {n: ot_stimuli.render(n) for n in ot_stimuli.STIMULI}

    def x(self, name):
        return self.r[name][0].astype(np.float64) / self.s.FULL

    def test_two_tones_level_and_frequency(self):
        x = self.x("two_tones")
        for c, hz in ((0, 997.0), (1, 1499.0)):
            self.assertAlmostEqual(self.s.db(np.sqrt(np.mean(x[:, c] ** 2))), -23.01, places=2)
            spec = np.abs(np.fft.rfft(x[:, c]))
            self.assertAlmostEqual(np.argmax(spec) * self.s.FS / len(x), hz, places=3)

    def test_ladder_steps(self):
        x = self.x("ladder")[:, 0]
        seg = 8 * self.s.FS // 5
        got = [self.s.db(np.abs(x[i * seg:(i + 1) * seg]).max()) for i in range(5)]
        for g, want in zip(got, (-40, -30, -20, -10, -3)):
            self.assertAlmostEqual(g, want, places=2)

    def test_impulses(self):
        x = self.x("impulses")[:, 0]
        self.assertEqual(np.flatnonzero(x).tolist(), list(range(0, 4 * self.s.FS, self.s.FS // 2)))
        self.assertAlmostEqual(self.s.db(x.max()), -1.0, places=3)

    def test_hits_decay_60_db(self):
        x = np.abs(self.x("hits")[:, 0])
        sp = self.s.FS // 2
        self.assertAlmostEqual(self.s.db(x[:sp].max()), -6.0, delta=0.5)
        self.assertLess(self.s.db(x[int(0.15 * self.s.FS):int(0.16 * self.s.FS)].max()), -6.0 - 55)

    def test_pink_rms_and_slope(self):
        x = self.x("pink")[:, 0]
        self.assertAlmostEqual(self.s.db(np.sqrt(np.mean(x ** 2))), -20.0, places=2)
        spec = np.abs(np.fft.rfft(x)) ** 2
        f = np.fft.rfftfreq(len(x), 1 / self.s.FS)
        octave = lambda lo: spec[(f >= lo) & (f < 2 * lo)].sum()          # noqa: E731
        # equal power per octave within a few dB over the middle of the band
        pw = [10 * np.log10(octave(lo)) for lo in (100, 200, 400, 800, 1600, 3200)]
        self.assertLess(max(pw) - min(pw), 6.0)

    def test_white_rms_and_flat(self):
        x = self.x("white")[:, 0]
        self.assertAlmostEqual(self.s.db(np.sqrt(np.mean(x ** 2))), -30.0, places=2)
        spec = np.abs(np.fft.rfft(x)) ** 2
        f = np.fft.rfftfreq(len(x), 1 / self.s.FS)
        lo, hi = spec[(f > 500) & (f < 2000)].mean(), spec[(f > 10000) & (f < 16000)].mean()
        self.assertLess(abs(10 * np.log10(lo / hi)), 1.5)

    def test_channels_of_noise_are_independent(self):
        for n in ("pink", "white"):
            x = self.x(n)
            self.assertLess(abs(np.corrcoef(x[:, 0], x[:, 1])[0, 1]), 0.02)

    def test_silence_and_dc(self):
        self.assertEqual(int(np.abs(self.r["silence"][0]).max()), 0)
        self.assertAlmostEqual(float(self.x("dc").mean()), -0.1, places=6)

    def test_durations_fill_a_pattern(self):
        for n, (q, _) in self.r.items():
            self.assertIn(len(q) / self.s.FS, (2.0, 4.0, 8.0), n)

    def test_render_is_deterministic(self):
        for n in self.s.STIMULI:
            self.assertTrue(np.array_equal(self.s.render(n)[0], self.r[n][0]), n)

    def test_tones_loop_without_a_seam(self):
        x = self.x("two_tones")
        for c in (0, 1):
            step = abs(x[0, c] - x[-1, c])                           # the wrap, against a normal step
            normal = np.abs(np.diff(x[:, c])).max()
            self.assertLessEqual(step, normal * 1.01)

    def test_wav_roundtrip_and_verify(self):
        with tempfile.TemporaryDirectory() as d:
            a = type("A", (), {"out": d, "names": ["two_tones", "impulses"]})
            self.s.cmd_gen(a)
            back = self.s.read_wav(pathlib.Path(d) / "two_tones.wav")
            self.assertTrue(np.array_equal(back, self.r["two_tones"][0]))
            self.assertEqual(self.s.cmd_verify(type("A", (), {"out": d})), 0)


if __name__ == "__main__":
    unittest.main()
