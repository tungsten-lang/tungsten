from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


HERE = Path(__file__).resolve().parent
MATMUL = HERE.parent
GEN_PATH = HERE / "gpu_simdgroup_gen.py"
SPEC = importlib.util.spec_from_file_location("gpu_simdgroup_gen", GEN_PATH)
assert SPEC and SPEC.loader
GEN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GEN)


def load_terms(path: Path) -> list[tuple[int, int, int]]:
    lines = path.read_text().splitlines()
    rank = int(lines[0])
    terms = [tuple(map(int, line.split())) for line in lines[1:] if line.strip()]
    if len(terms) != rank:
        raise AssertionError((rank, len(terms)))
    return terms


def exact_signature(terms: list[tuple[int, int, int]]) -> int:
    """Full 6x6 tensor bitset, independent of the Tungsten verifier."""
    sig = 0
    for u, v, w in terms:
        us = [i for i in range(36) if (u >> i) & 1]
        vs = [i for i in range(36) if (v >> i) & 1]
        ws = [i for i in range(36) if (w >> i) & 1]
        for a in us:
            for b in vs:
                base = (a * 36 + b) * 36
                for c in ws:
                    sig ^= 1 << (base + c)
    return sig


def matmul_signature(n: int) -> int:
    sig = 0
    n2 = n * n
    for i in range(n):
        for j in range(n):
            for k in range(n):
                a = i * n + j
                b = j * n + k
                c = i * n + k
                sig |= 1 << ((a * n2 + b) * n2 + c)
    return sig


class SimdgroupGeneratorTest(unittest.TestCase):
    def test_5x5_stays_native_i32(self) -> None:
        src = GEN.generate(5, 112, "/tmp/simd555.ll")
        self.assertIn("gpu.shared_i32(112)", src)
        self.assertIn("heads = gpu.shared_i32(768)", src)
        self.assertIn("nexts = gpu.shared_i32(336)", src)
        self.assertNotIn("## i64[]: work_us", src)
        self.assertIn("matmul_5x5_rank93_d1155_gf2.txt", src)
        self.assertIn("MODE = 0", src)
        self.assertIn('if firstparts[0] == "R"', src)

    def test_6x6_uses_i64_and_fits_threadgroup_memory(self) -> None:
        src = GEN.generate(6, 168, "/tmp/simd666.ll")
        self.assertIn("gpu.shared_i64(168)", src)
        self.assertIn("schanged = gpu.shared_i64(6)", src)
        self.assertIn("heads = gpu.shared_i32(1536)", src)
        self.assertIn("nexts = gpu.shared_i32(504)", src)
        self.assertIn("## i64[]: work_us", src)
        self.assertIn("metal_buffer_write_i64(seed_us", src)
        self.assertIn("metal_buffer_read_i64(best_us", src)
        self.assertIn("matmul_6x6_rank153_d2508_gf2.txt", src)
        self.assertIn("MODE = 1", src)
        self.assertNotIn("hashslot = int(", src)

    def test_7x7_keeps_high_masks_on_raw_i64_host_paths(self) -> None:
        src = GEN.generate(7, 360, "/tmp/simd777.ll")
        self.assertIn("umask = uhi * 10000000 + ulo", src)
        self.assertIn(
            "seed_us_view = metal_buffer_view(seed_us, 66, CAP) ## i64[]",
            src,
        )
        self.assertIn(
            "best_us_view = metal_buffer_view(best_us, 66, GROUPS * CAP) ## i64[]",
            src,
        )
        self.assertNotIn("seedu[ii] = parts[colbase].to_i()", src)
        self.assertNotIn("metal_buffer_read_i64(best_us", src)

    def test_tracked_d2508_candidate_is_fully_exact(self) -> None:
        path = MATMUL / "metaflip" / "matmul_6x6_rank153_d2508_gf2.txt"
        terms = load_terms(path)
        self.assertEqual(len(terms), 153)
        self.assertEqual(sum(bin(x).count("1") for term in terms for x in term), 2508)
        self.assertEqual(exact_signature(terms), matmul_signature(6))


if __name__ == "__main__":
    unittest.main()
