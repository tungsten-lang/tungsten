import argparse
import os
import unittest

from tensor_profiles import (
    ROLE_KEYS,
    TensorSpec,
    normalize_role_weights,
    parse_tensor,
    profile_for_tensor,
    tensor_arg,
)


class TensorParsingTests(unittest.TestCase):
    def test_ascii_case_spacing_and_unicode_spellings(self):
        for spelling in ("3x3", " 4 X 4 ", "5×5", "6✕6", "7⨉7",
                         "７ｘ７"):
            with self.subTest(spelling=spelling):
                spec = parse_tensor(spelling)
                self.assertEqual((spec.n, spec.n, spec.n), spec.dimensions)

    def test_rejects_rectangular_and_malformed_spellings(self):
        with self.assertRaisesRegex(ValueError, "square"):
            parse_tensor("3x4")
        for spelling in ("5", "5x5x5", "five x five", ""):
            with self.subTest(spelling=spelling):
                with self.assertRaisesRegex(ValueError, "NxN"):
                    parse_tensor(spelling)

    def test_signed_i64_boundary_accepts_seven_and_rejects_eight(self):
        self.assertEqual(49, parse_tensor("7x7").factor_bits)
        with self.assertRaisesRegex(ValueError, "64 factor bits.*maximum square"):
            parse_tensor("8x8")

    def test_argparse_adapter_preserves_a_useful_error(self):
        with self.assertRaises(argparse.ArgumentTypeError):
            tensor_arg("8x8")


class TensorProfileTests(unittest.TestCase):
    def test_known_records_and_bundled_seeds(self):
        expected = {3: 23, 4: 47, 5: 93, 6: 153}
        for n, rank in expected.items():
            with self.subTest(n=n):
                profile = profile_for_tensor(TensorSpec.square(n))
                self.assertTrue(profile.known_record)
                self.assertEqual(rank, profile.default_rank)
                self.assertEqual(rank - 1, profile.target_rank)
                self.assertTrue(os.path.isabs(profile.seed_path))
                self.assertTrue(os.path.isfile(profile.seed_path))

    def test_seven_uses_checked_in_rank247_composition(self):
        profile = profile_for_tensor("7×7")
        self.assertTrue(profile.known_record)
        self.assertEqual(247, profile.default_rank)
        self.assertEqual(343, profile.naive_rank)
        self.assertTrue(os.path.isfile(profile.seed_path))
        self.assertIn("rank247_d3098_global_isotropy", profile.seed_path)
        self.assertEqual("record", profile.seed_kind)
        self.assertFalse(profile.seed_is_c3)
        self.assertTrue(profile.c3_eligible)
        self.assertEqual("naive", profile.c3_seed_kind)
        self.assertFalse(profile.recommendation_measured)

    def test_generic_density_leaders_keep_separate_c3_seeds(self):
        for n, old_density in ((5, "d1155"), (6, "d2502")):
            with self.subTest(n=n):
                profile = profile_for_tensor(n)
                self.assertFalse(profile.seed_is_c3)
                self.assertTrue(profile.c3_eligible)
                self.assertEqual("alternate-record", profile.c3_seed_kind)
                self.assertIn(old_density, profile.c3_seed_path)

    def test_c3_is_only_budgeted_when_default_profile_can_supply_it(self):
        for n in (3, 4):
            profile = profile_for_tensor(n)
            self.assertFalse(profile.c3_eligible)
            self.assertEqual(0, profile.role_weights["symmetry"])
            self.assertEqual(0, profile.role_weights["break"])
            self.assertEqual(0, profile.role_weights["orbit"])
            self.assertEqual(0, profile.role_weights["polarize"])
        for n in (5, 6, 7):
            profile = profile_for_tensor(n)
            self.assertTrue(profile.c3_eligible)
            self.assertGreater(profile.role_weights["symmetry"], 0)
        self.assertTrue(os.path.isfile(profile_for_tensor(6).c3_seed_path))

    def test_all_roles_present_normalized_and_lookup_crossover_applied(self):
        for n in range(3, 8):
            with self.subTest(n=n):
                profile = profile_for_tensor(n)
                self.assertEqual(set(ROLE_KEYS), set(profile.role_weights))
                self.assertEqual(100, sum(profile.role_weights.values()))
                self.assertAlmostEqual(1.0, sum(profile.role_fractions.values()))
                self.assertEqual("scan" if n <= 5 else "hash",
                                 profile.simd_lookup)
                self.assertEqual("i32" if n <= 5 else "i64",
                                 profile.mask_storage)

    def test_normalizer_supports_feedback_and_rejects_bad_maps(self):
        adjusted = normalize_role_weights({"rank": 3, "novelty": 1})
        self.assertEqual(0.75, adjusted["rank"])
        self.assertEqual(0.25, adjusted["novelty"])
        self.assertEqual(0.0, adjusted["mitm"])
        with self.assertRaisesRegex(ValueError, "unknown GPU role"):
            normalize_role_weights({"sat": 1})
        with self.assertRaisesRegex(ValueError, "nonnegative"):
            normalize_role_weights({"rank": -1})
        with self.assertRaisesRegex(ValueError, "at least one"):
            normalize_role_weights({})


if __name__ == "__main__":
    unittest.main()
