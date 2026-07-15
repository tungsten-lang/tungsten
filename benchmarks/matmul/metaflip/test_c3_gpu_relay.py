from __future__ import annotations

import tempfile
from pathlib import Path
import unittest

import c3_gpu_relay as C3


def naive_terms(n: int) -> list[tuple[int, int, int]]:
    return [
        (1 << (i * n + j), 1 << (j * n + k), 1 << (i * n + k))
        for i in range(n) for j in range(n) for k in range(n)
    ]


def write_bare(path: Path, terms: list[tuple[int, int, int]], density=True) -> None:
    total = sum(bin(mask).count("1") for term in terms for mask in term)
    header = f"{len(terms)} {total}" if density else str(len(terms))
    path.write_text(header + "\n" + "".join(
        f"{u} {v} {w}\n" for u, v, w in terms
    ))


def result_line(n: int, terms: list[tuple[int, int, int]], output: str) -> str:
    density = sum(bin(mask).count("1") for term in terms for mask in term)
    return (
        "C3GPU_RESULT "
        f"n={n} walkers=32 steps=200 dispatches=1 band=15 plusper=20 "
        "elapsed_ms=34 attempted=6400 partners=913 pluses=315 resets=5 "
        f"aggregate_steps_s=188235 rank={len(terms)} density={density} "
        f"verify_full=1 c3_closed=1 output={output}"
    )


class C3GpuRelayTest(unittest.TestCase):
    def test_checked_sources_match_development_generator(self) -> None:
        for n, cap in C3.BUNDLE_CAPS.items():
            with self.subTest(n=n):
                tag = str(n) * 3
                metal_ll = Path(
                    f"benchmarks/matmul/metaflip/c3_bundle/c3_{tag}.ll"
                )
                expected = C3.generate_source(C3.C3GpuConfig(n=n, cap=cap), metal_ll)
                self.assertEqual(C3.bundle_source(n).read_text(), expected)

    def test_campaign_relay_uses_checked_in_source(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            relay = C3.C3GpuRelay(tmp, C3.C3GpuConfig(n=3, cap=56))
            self.assertEqual(relay.source, C3.bundle_source(3))
            self.assertTrue(relay.source.is_file())
            self.assertIn("c3_bundle", str(relay.source))

    def test_specialization_covers_3_through_7_and_raw_7x7_path(self) -> None:
        for n in range(3, 8):
            with self.subTest(n=n):
                config = C3.C3GpuConfig(
                    n=n, cap=C3.capacity_for_rank(n ** 3), walkers=33,
                )
                source = C3.generate_source(config, f"/tmp/c3-{n}.ll")
                self.assertIn("@gpu fn c3_walk", source)
                self.assertIn(f"NN = {n}", source)
                self.assertIn(f"CAP = {config.cap}", source)
                self.assertIn("while phase < 12", source)
                self.assertIn("while phase < 9", source)
                self.assertEqual(config.threadgroups, 2)
                if n <= 5:
                    self.assertIn("## i32[]: work_us", source)
                else:
                    self.assertIn("## i64[]: work_us", source)
                if n == 7:
                    self.assertIn("umask = uhi * 10000000 + ulo", source)
                    self.assertIn("seed_us_view = metal_buffer_view(seed_us, 66", source)
                    self.assertIn("outu[ii] = best_us_view", source)
                    self.assertNotIn("seedu[ii] = parts[colbase].to_i()", source)

    def test_reference_flip_and_split_preserve_exactness_at_every_step(self) -> None:
        terms = tuple(naive_terms(3))
        self.assertTrue(C3.exact_c3_terms(terms, 3))
        for iteration in range(4):
            axis = iteration % 3
            pair = next(
                (i, j)
                for i, first in enumerate(terms)
                for j, second in enumerate(terms)
                if i != j
                and second not in C3.c3_orbit(first, 3)
                and first[axis] == second[axis]
            )
            terms = C3.apply_c3_flip(terms, pair[0], pair[1], axis, 3)
            self.assertTrue(C3.exact_terms(terms, 3))
            self.assertTrue(C3.is_c3_closed(terms, 3))
            split_axis = (axis + 1) % 3
            donor = next(
                (i, j)
                for i, first in enumerate(terms)
                for j, second in enumerate(terms)
                if first[split_axis] != second[split_axis]
            )
            terms = C3.apply_c3_split(
                terms, donor[0], donor[1], split_axis, 3,
            )
            self.assertTrue(C3.exact_terms(terms, 3))
            self.assertTrue(C3.is_c3_closed(terms, 3))

    def test_config_requires_an_exact_c3_runtime_seed(self) -> None:
        terms = naive_terms(3)
        with tempfile.TemporaryDirectory() as tmp:
            seed = Path(tmp) / "seed.txt"
            write_bare(seed, terms)
            config = C3.config_for_seed(3, seed, walkers=17, steps=23, band=4)
            self.assertGreaterEqual(config.cap, len(terms) + 4 + 6)
            self.assertEqual(config.hardware_lanes, 17)

            # An ordinary non-orbit flip remains tensor-exact but breaks C3.
            broken = set(terms)
            first = terms[0]
            second = terms[1]
            broken.remove(first)
            broken.remove(second)
            broken.add((first[0], first[1], first[2] ^ second[2]))
            broken.add((first[0], first[1] ^ second[1], second[2]))
            broken_terms = sorted(broken)
            self.assertTrue(C3.exact_terms(broken_terms, 3))
            self.assertFalse(C3.is_c3_closed(broken_terms, 3))
            write_bare(seed, broken_terms)
            with self.assertRaisesRegex(ValueError, "not exact and C3"):
                C3.config_for_seed(3, seed)

    def test_result_is_independently_exact_and_c3_gated(self) -> None:
        terms = naive_terms(3)
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "a run" / "best.txt"
            output.parent.mkdir()
            write_bare(output, terms)
            parsed = C3.parse_result(result_line(3, terms, str(output)))
            candidate = C3.load_exact_candidate(output, parsed, 3)
            self.assertEqual(candidate.rank, 27)
            self.assertEqual(candidate.density, 81)
            self.assertEqual(parsed.output, str(output))

    def test_second_gate_rejects_exact_but_asymmetric_output(self) -> None:
        terms = naive_terms(3)
        broken = set(terms)
        first = terms[0]
        second = terms[1]
        broken.remove(first)
        broken.remove(second)
        broken.add((first[0], first[1], first[2] ^ second[2]))
        broken.add((first[0], first[1] ^ second[1], second[2]))
        broken_terms = sorted(broken)
        self.assertTrue(C3.exact_terms(broken_terms, 3))
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "broken.txt"
            write_bare(output, broken_terms)
            parsed = C3.parse_result(result_line(3, broken_terms, str(output)))
            with self.assertRaisesRegex(C3.C3GpuRelayError, "Python C3"):
                C3.load_exact_candidate(output, parsed, 3)


if __name__ == "__main__":
    unittest.main()
