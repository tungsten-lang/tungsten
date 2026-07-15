from __future__ import annotations

import tempfile
from pathlib import Path
import unittest

import simdgroup_relay as RELAY


def naive_terms(n: int) -> list[tuple[int, int, int]]:
    return [
        (1 << (i * n + j), 1 << (j * n + k), 1 << (i * n + k))
        for i in range(n) for j in range(n) for k in range(n)
    ]


def write_bare(path: Path, terms: list[tuple[int, int, int]], density=False) -> None:
    total = sum(bin(mask).count("1") for term in terms for mask in term)
    header = f"{len(terms)} {total}" if density else str(len(terms))
    path.write_text(header + "\n" + "".join(
        f"{u} {v} {w}\n" for u, v, w in terms
    ))


def result_line(n: int, rank: int, density: int, output: str,
                mode: int | None = None) -> str:
    if mode is None:
        mode = 0 if n <= 5 else 1
    return (
        "SIMDGROUP_RESULT "
        f"mode={mode} n={n} groups=8 steps=100 dispatches=2 "
        "elapsed_ms=9 attempted=1600 partners=700 aggregate_steps_s=177777 "
        f"trajectory_steps_s=22222 rank={rank} density={density} "
        f"verify_full=1 output={output}"
    )


class SimdgroupRelayTest(unittest.TestCase):
    def test_auto_mode_and_specialization_cover_3_through_7(self) -> None:
        for n in range(3, 8):
            with self.subTest(n=n):
                rank = n ** 3
                cap = RELAY.capacity_for_rank(rank)
                config = RELAY.SimdgroupConfig(n=n, cap=cap)
                self.assertEqual(config.selected_mode,
                                 RELAY.SCAN if n <= 5 else RELAY.HASH)
                self.assertEqual(config.hardware_lanes, config.groups * 32)
                source = RELAY.generate_source(config, f"/tmp/simd-{n}.ll")
                self.assertIn(f"nn = {n}\nmm = {n}\npp = {n}", source)
                self.assertIn(f"CAP = {cap}", source)
                self.assertIn(f"MODE = {config.mode_number}", source)
                if n <= 5:
                    self.assertIn(f"gpu.shared_i32({cap})", source)
                else:
                    self.assertIn(f"gpu.shared_i64({cap})", source)
                    self.assertIn("heads = gpu.shared_i32(1536)", source)
                if n == 7:
                    self.assertIn("umask = uhi * 10000000 + ulo", source)
                    self.assertNotIn("seedu[ii] = parts[colbase].to_i()", source)
                    self.assertIn("best_us_view = metal_buffer_view(best_us, 66", source)
                    self.assertIn("outu[ii] = best_us_view[bestgroup * CAP + ii]", source)
                    self.assertNotIn("metal_buffer_read_i64(best_us", source)
                self.assertLessEqual(
                    RELAY.shared_memory_bytes(n, cap),
                    RELAY.MAX_THREADGROUP_MEMORY,
                )

    def test_runtime_argv_uses_selected_mode(self) -> None:
        config = RELAY.SimdgroupConfig(
            n=6, cap=168, groups=17, steps=1234, dispatches=3, margin=7,
        )
        self.assertEqual(
            RELAY.relay_argv("relay", "seed", "out", config),
            ["relay", "seed", "out", "17", "1234", "3", "7", "1"],
        )

    def test_parse_result_uses_last_line_and_preserves_output_path(self) -> None:
        line = result_line(6, 153, 2508, "/tmp/a run/best.txt")
        parsed = RELAY.parse_result("old noise\n" + line + "\n")
        self.assertEqual(parsed.rank, 153)
        self.assertEqual(parsed.density, 2508)
        self.assertEqual(parsed.output, "/tmp/a run/best.txt")
        self.assertEqual(parsed.verify_full, 1)

    def test_runtime_seed_accepts_density_header_and_sizes_capacity(self) -> None:
        terms = naive_terms(3)
        with tempfile.TemporaryDirectory() as tmp:
            seed = Path(tmp) / "seed.txt"
            write_bare(seed, terms, density=True)
            config = RELAY.config_for_seed(3, seed, groups=8, steps=100)
        self.assertEqual(config.cap, 40)
        self.assertEqual(config.selected_mode, RELAY.SCAN)

    def test_candidate_passes_second_exact_gate(self) -> None:
        terms = naive_terms(3)
        density = 3 * len(terms)
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "best.txt"
            write_bare(output, terms)
            metadata = RELAY.parse_result(
                result_line(3, len(terms), density, str(output))
            )
            candidate = RELAY.load_exact_candidate(output, metadata, 3)
        self.assertEqual(candidate.rank, 27)
        self.assertEqual(candidate.density, 81)

    def test_candidate_rejects_invalid_or_mismatched_output(self) -> None:
        terms = naive_terms(3)
        terms[0] = (3, terms[0][1], terms[0][2])
        density = sum(bin(mask).count("1") for term in terms for mask in term)
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "bad.txt"
            write_bare(output, terms)
            metadata = RELAY.parse_result(
                result_line(3, len(terms), density, str(output))
            )
            with self.assertRaisesRegex(RELAY.SimdgroupRelayError,
                                        "independent Python"):
                RELAY.load_exact_candidate(output, metadata, 3)


if __name__ == "__main__":
    unittest.main()
