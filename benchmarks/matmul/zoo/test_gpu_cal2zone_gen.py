from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


HERE = Path(__file__).resolve().parent
SQUARE_BUNDLE = HERE.parent / "metaflip" / "gpu_bundle"
RECT_BUNDLE = HERE.parent / "metaflip" / "rect_gpu"
GEN_PATH = HERE / "gpu_cal2zone_gen.py"
SPEC = importlib.util.spec_from_file_location("gpu_cal2zone_gen", GEN_PATH)
assert SPEC and SPEC.loader
GEN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GEN)


class Cal2ZoneGeneratorTest(unittest.TestCase):
    def test_334_masks_each_plus_axis_to_its_factor_width(self) -> None:
        src, shared = GEN.gen(
            3, 3, 4, 68, 16, 68, "/tmp/cal2zone_334.ll", nw=256,
        )
        self.assertEqual(shared, 13_056)
        self.assertIn("u1 = u1 & 511", src)   # nm = 9 bits
        self.assertEqual(src.count("u1 = u1 & 4095"), 2)  # mp=np=12
        self.assertIn("nn = 3\nmm = 3\npp = 4", src)
        self.assertIn("NW = 256", src)
        self.assertIn("verify_buf(best_us, best_vs, best_ws", src)
        self.assertIn("verify_buf_error(best_us, best_vs, best_ws", src)
        self.assertIn("GPU_INTERNAL_REJECT_CANDIDATE", src)
        self.assertIn("axis = sid % 3", src)
        self.assertIn("escape_index = sid / 3", src)
        self.assertNotIn("axis = (sid / baserank) % 3", src)

    def test_344_masks_12_16_12_and_fits_shared_memory(self) -> None:
        src, shared = GEN.gen(
            3, 4, 4, 80, 16, 80, "/tmp/cal2zone_344.ll", nw=256,
        )
        self.assertEqual(shared, 15_360)
        self.assertEqual(src.count("u1 = u1 & 4095"), 2)
        self.assertIn("u1 = u1 & 65535", src)
        self.assertIn("nn = 3\nmm = 4\npp = 4", src)
        self.assertIn("target = (escape_index * 37 + axis * 13 + rd * 17) % baserank", src)

    def test_445_masks_16_20_20_and_fits_shared_memory(self) -> None:
        src, shared = GEN.gen(
            4, 4, 5, 112, 16, 112, "/tmp/cal2zone_445.ll", nw=256,
        )
        self.assertEqual(shared, 21_504)
        self.assertEqual(src.count("u1 = u1 & 65535"), 1)
        self.assertEqual(src.count("u1 = u1 & 1048575"), 2)
        self.assertIn("nn = 4\nmm = 4\npp = 5", src)
        self.assertIn("axis = sid % 3", src)

    def test_new_rectangular_leaf_geometries(self) -> None:
        cases = (
            (2, 2, 5, 64, 12_288, ("15", "1023", "1023")),
            (2, 3, 4, 64, 12_288, ("63", "4095", "255")),
            (2, 3, 5, 68, 13_056, ("63", "32767", "1023")),
            (2, 4, 5, 80, 15_360, ("255", "1048575", "1023")),
            (2, 5, 6, 92, 17_664, ("1023", "1073741823", "4095")),
            (3, 3, 5, 77, 14_784, ("511", "32767", "32767")),
            (3, 4, 5, 92, 17_664, ("4095", "1048575", "32767")),
            (3, 4, 6, 104, 19_968, ("4095", "16777215", "262143")),
            (3, 4, 7, 116, 22_272, ("4095", "268435455", "2097151")),
            (3, 5, 6, 122, 23_424, ("32767", "1073741823", "262143")),
            (3, 5, 5, 107, 20_544, ("32767", "33554431", "32767")),
        )
        for n, m, p, cap, expected_shared, masks in cases:
            tag = f"{n}{m}{p}"
            with self.subTest(tag=tag):
                src, shared = GEN.gen(
                    n, m, p, cap, 16, cap, f"/tmp/cal2zone_{tag}.ll", nw=256,
                )
                self.assertEqual(shared, expected_shared)
                actual_masks = [
                    line.strip().rsplit(" ", 1)[-1]
                    for line in src.splitlines()
                    if line.strip().startswith("u1 = u1 &")
                ]
                self.assertEqual(actual_masks, list(masks))
                self.assertIn(f"nn = {n}\nmm = {m}\npp = {p}", src)
                self.assertIn("axis = sid % 3", src)

    def test_square_generation_keeps_equal_axis_masks(self) -> None:
        src, _ = GEN.gen(
            3, 3, 3, 59, 16, 59, "/tmp/cal2zone_333.ll", nw=256,
        )
        self.assertEqual(src.count("u1 = u1 & 511"), 3)
        self.assertIn("axis = (sid / baserank) % 3", src)
        self.assertNotIn("escape_index = sid / 3", src)
        self.assertIn("if vok == 0", src)
        self.assertIn("internal_reject_candidate_path", src)
        self.assertIn("exact_error = verify_buf_error", src)
        self.assertIn("GPU_INTERNAL_REJECT_CANDIDATE", src)

    def test_duplicate_parity_compaction_removes_both_equal_terms(self) -> None:
        src, _ = GEN.gen(
            3, 3, 3, 59, 16, 59, "/tmp/cal2zone_333.ll", nw=256,
        )
        # There are four duplicate-cancellation paths: plus, each of the two
        # touched flip slots, and the periodic defensive scan.  Each orders
        # the indices, removes the higher slot first, and then removes the
        # lower slot.  Copying the last term into the duplicate before both
        # decrements used to retain one copy and discard an unrelated term.
        self.assertEqual(src.count("lo = a"), 4)
        self.assertEqual(src.count("hi = dup"), 4)
        self.assertEqual(src.count("if hi < rank"), 4)
        self.assertEqual(src.count("if lo < rank"), 4)
        self.assertNotIn("sus[dup * 16 + ltid] =", src)

    def test_checked_rectangular_assets_keep_masks_and_exhaustive_gate(self) -> None:
        expected = {
            "225": ("u1 = u1 & 15", "u1 = u1 & 1023", "u1 = u1 & 1023"),
            "234": ("u1 = u1 & 63", "u1 = u1 & 4095", "u1 = u1 & 255"),
            "235": ("u1 = u1 & 63", "u1 = u1 & 32767", "u1 = u1 & 1023"),
            "245": ("u1 = u1 & 255", "u1 = u1 & 1048575", "u1 = u1 & 1023"),
            "256": ("u1 = u1 & 1023", "u1 = u1 & 1073741823", "u1 = u1 & 4095"),
            "334": ("u1 = u1 & 511", "u1 = u1 & 4095", "u1 = u1 & 4095"),
            "335": ("u1 = u1 & 511", "u1 = u1 & 32767", "u1 = u1 & 32767"),
            "344": ("u1 = u1 & 4095", "u1 = u1 & 65535", "u1 = u1 & 4095"),
            "345": ("u1 = u1 & 4095", "u1 = u1 & 1048575", "u1 = u1 & 32767"),
            "355": ("u1 = u1 & 32767", "u1 = u1 & 33554431", "u1 = u1 & 32767"),
            "445": ("u1 = u1 & 65535", "u1 = u1 & 1048575", "u1 = u1 & 1048575"),
        }
        for tag, masks in expected.items():
            with self.subTest(tag=tag):
                src = (RECT_BUNDLE / f"cal2zone_{tag}.w").read_text()
                metal = (RECT_BUNDLE / f"cal2zone_{tag}.metal").read_text()
                actual_masks = [
                    line.strip() for line in src.splitlines()
                    if line.strip().startswith("u1 = u1 &")
                ]
                self.assertEqual(actual_masks, list(masks))
                for mask in set(masks):
                    self.assertEqual(src.count(mask), masks.count(mask))
                    value = mask.rsplit(" ", 1)[-1]
                    self.assertEqual(
                        metal.count(f"u1 = (u1 & {value});"), masks.count(mask)
                    )
                # Every candidate written by the relay crosses all three
                # coefficient dimensions and reaches the exactness result.
                self.assertIn("while ai < ab", src)
                self.assertIn("while bi < bb", src)
                self.assertIn("while ci < cb", src)
                self.assertIn("if got != want", src)
                self.assertIn("if vok == 1", src)
                self.assertLess(src.index("vok = verify_buf"), src.index("write_file(gpubestpath"))
                self.assertIn("axis = sid % 3", src)
                self.assertIn("escape_index = sid / 3", src)
                self.assertIn("persistent_idle_timeout_ms = 600000", src)
                self.assertEqual(src.count("lo = a"), 4)
                self.assertEqual(src.count("if hi < rank"), 4)
                self.assertEqual(src.count("if lo < rank"), 4)
                self.assertNotIn("sus[dup * 16 + ltid] =", src)
                self.assertEqual(metal.count("lo = a;"), 4)
                self.assertEqual(metal.count("if ((hi < rank))"), 4)
                self.assertEqual(metal.count("if ((lo < rank))"), 4)
                if tag in ("225", "234", "235", "245", "256"):
                    self.assertIn('first_parts[0] == "R"', src)
                    self.assertIn("parts[field_base + 2]", src)

    def test_checked_square_assets_use_correct_duplicate_compaction(self) -> None:
        for tag in ("333", "444", "555", "666", "777"):
            with self.subTest(tag=tag):
                src = (SQUARE_BUNDLE / f"cal2zone_{tag}.w").read_text()
                metal = (SQUARE_BUNDLE / f"cal2zone_{tag}.metal").read_text()
                self.assertEqual(src.count("lo = a"), 4)
                self.assertEqual(src.count("if hi < rank"), 4)
                self.assertEqual(src.count("if lo < rank"), 4)
                self.assertNotIn("sus[dup *", src)
                self.assertEqual(metal.count("lo = a;"), 4)
                self.assertEqual(metal.count("if ((hi < rank))"), 4)
                self.assertEqual(metal.count("if ((lo < rank))"), 4)


if __name__ == "__main__":
    unittest.main()
