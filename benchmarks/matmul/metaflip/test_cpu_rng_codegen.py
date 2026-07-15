import hashlib
import os
import re
import subprocess
import sys
import tempfile
import unittest


HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
ZOO = os.path.abspath(os.path.join(HERE, "..", "zoo"))
for directory in (HERE, ZOO):
    if directory not in sys.path:
        sys.path.insert(0, directory)

from bench_decomp import verify  # noqa: E402
from bucket_gen import (  # noqa: E402
    _RNG31_MASK,
    _RNG63_MASK,
    _RNG63_MULT,
    _RNG63_SEED_MASK,
    gen,
    gen_worker,
)


def rng63_words(seed, count):
    seed_state = seed & _RNG63_SEED_MASK
    increment = seed_state + seed_state + 1
    state = (seed_state ^ 1442695040888963407) & _RNG63_MASK
    state = (state * _RNG63_MULT + increment) & _RNG63_MASK
    state = (state * _RNG63_MULT + increment) & _RNG63_MASK
    words = []
    for _ in range(count):
        state = (state * _RNG63_MULT + increment) & _RNG63_MASK
        words.append((state >> 32) & _RNG31_MASK)
    return increment, words


class StandaloneCal2zone2RngTest(unittest.TestCase):
    def test_parameterized_streams_have_full_period_preconditions(self):
        self.assertEqual(1, _RNG63_MULT % 4)
        increments = []
        streams = []
        for seed in (13, 110, 207, 304):
            increment, words = rng63_words(seed, 32)
            self.assertEqual(1, increment & 1)
            self.assertTrue(all(0 <= word <= _RNG31_MASK for word in words))
            increments.append(increment)
            streams.append(words)
        self.assertEqual(len(increments), len(set(increments)))
        self.assertEqual(len(streams), len({tuple(words) for words in streams}))

    def test_only_standalone_cal2zone2_switches_rng(self):
        source = gen(
            3, 3, 3, 22, cap=100, adaptive_esc="cal2zone2",
            world_record=23, plus_axes="any", randstart=True,
        )
        self.assertIn("rnginc = rngseed + rngseed + 1 ## i64", source)
        self.assertIn(
            "rng = (rng * 6364136223846793005 + rnginc) & "
            "9223372036854775807", source)
        self.assertIn(
            "rngword = (rng >> 32) & 2147483647 ## i64", source)
        self.assertIn("td = (rngword * rank) >> 31 ## i64", source)
        self.assertIn(", ui, ti, rngword)", source)
        self.assertIn("pd1 = (rngword * rank) >> 31 ## i64", source)
        self.assertIn("paxis = (((rngword >> 22) & 511) * 3) >> 9", source)
        self.assertIn("bstart = 1 + (rngword % 4) ## i64", source)
        self.assertIn("rnginc = rnginc + 2", source)
        self.assertIn("basetext = av0[0]", source)
        self.assertIn("base = basemask ## i64", source)
        self.assertNotIn("base = av0[0].to_i()", source)
        self.assertNotIn(
            "rng = (rng * 1103515245 + 12345) & 2147483647", source)

        legacy_mode = gen(
            3, 3, 3, 22, cap=100, adaptive_esc="cal2zone",
            world_record=23, plus_axes="any", randstart=True,
        )
        worker = gen_worker(3, 3, 3, 22, plus_axes="any")
        for unchanged in (legacy_mode, worker):
            self.assertNotIn("rnginc", unchanged)
            self.assertIn(
                "rng = (rng * 1103515245 + 12345) & 2147483647",
                unchanged)

    def test_non_cal2zone2_sources_are_byte_stable(self):
        cases = (
            ("none", {"adaptive_esc": None},
             "1b95aef4bde244f4b8f0f9a8b9a3b63d31a56638b1384848e87ee0605d5f1702"),
            ("wcal2", {"adaptive_esc": "wcal2"},
             "7e1bcaf5364c8d83f627526610e54616649bb51f265c71351b2eb15b539f0985"),
            ("wcal", {"adaptive_esc": "wcal"},
             "cf869f9ca8b193d12e03a6f6b3087d2c48651c19b0e535552b284b3af7ba36f1"),
            ("cal2zone", {"adaptive_esc": "cal2zone"},
             "230ca84f03470e174fbcae5d93aaa31177bd931bc142239fda92446c103a8043"),
            ("zones", {"adaptive_esc": "zones"},
             "291d1ecb3aa5b1e875e3a20e6c9775e92cf9d3efc26c9ebea06026933afd9aea"),
            ("numeric", {"adaptive_esc": 12345},
             "b1579f9e36d198786a9320b6129c6025bb1a8ac2327301c3328f80152dbd4fb3"),
            ("none-any-rand", {
                "adaptive_esc": None, "plus_axes": "any", "randstart": True,
             }, "32798ddf8def21fc7c54b14ffd5b409ee5481066920e18e19a3998a98522ad9d"),
        )
        for name, options, expected in cases:
            with self.subTest(name=name):
                source = gen(
                    3, 3, 3, 22, cap=123456, world_record=23,
                    runtime_seed=True, **options)
                self.assertEqual(
                    expected, hashlib.sha256(source.encode()).hexdigest())

        # The embedded/thread-worker cal2zone2 implementation intentionally
        # remains on its historical state layout and RNG.  Only gen()'s
        # standalone process receives the parameterized stream in this change.
        worker_hashes = (
            ({}, "4c71b7338b2bd895cff7a54bbd2c041042401df03d2b5ed78b7a98716cfc4fac"),
            ({"plus_axes": "any"},
             "830a6a171ba77115ad9ead5f1be35ac2ceca7cb5f6d01534391846ce64864ed0"),
        )
        for options, expected in worker_hashes:
            source = gen_worker(3, 3, 3, 22, **options)
            self.assertEqual(expected,
                             hashlib.sha256(source.encode()).hexdigest())

    @unittest.skipUnless(
        os.path.isfile(os.path.join(ROOT, "bin", "tungsten")),
        "native Tungsten compiler is unavailable",
    )
    def test_native_streams_cycleout_and_exact_verify(self):
        source = gen(
            3, 3, 3, 22, cap=500_000, adaptive_esc="cal2zone2",
            band=1, thr0=7, world_record=23, record_bandq=10_000,
            plusper=257, plus_axes="any", randstart=True, rsmax=4,
        )
        with tempfile.TemporaryDirectory() as tmp:
            source_path = os.path.join(tmp, "rng63_cal2zone2.w")
            binary_path = os.path.join(tmp, "rng63_cal2zone2")
            with open(source_path, "w") as stream:
                stream.write(source)
            built = subprocess.run(
                [os.path.join(ROOT, "bin", "tungsten"), "-o", binary_path,
                 source_path, "--release", "--native", "--fast"],
                cwd=ROOT, capture_output=True, text=True, timeout=180,
            )
            self.assertEqual(0, built.returncode, built.stdout + built.stderr)

            outputs = []
            for seed in (13, 110, (1 << 60) + 13):
                # Empty path arguments preserve the standalone CLI positions;
                # one 10K work/wander cycle exercises the stream refresh.
                run = subprocess.run(
                    [binary_path, str(seed), "", "", "", "", "1",
                     "10000", "10000"],
                    cwd=ROOT, capture_output=True, text=True, timeout=30,
                )
                self.assertEqual(0, run.returncode, run.stdout + run.stderr)
                self.assertIn("CYCLEOUT", run.stdout)
                match = re.search(r"DONE best=(\d+) verify=(\d+)", run.stdout)
                self.assertIsNotNone(match, run.stdout[-2000:])
                rank, valid = map(int, match.groups())
                self.assertEqual(1, valid)
                tail = run.stdout[match.end():]
                terms = [tuple(map(int, found)) for found in re.findall(
                    r"^R (-?\d+) (-?\d+) (-?\d+)$", tail, re.MULTILINE)]
                self.assertEqual(rank, len(terms))
                self.assertTrue(verify(terms, 3, 3, 3))
                expected_increment = 2 * (seed & _RNG63_SEED_MASK) + 1
                self.assertIn(f"RNG63 stream={expected_increment}", run.stdout)
                outputs.append(terms)
            self.assertNotEqual(outputs[0], outputs[1])


if __name__ == "__main__":
    unittest.main()
