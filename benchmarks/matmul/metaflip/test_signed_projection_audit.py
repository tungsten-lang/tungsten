import unittest
from pathlib import Path

from signed_projection_audit import (
    _profile_paths,
    _relation_stats,
    project_mod2,
    tensor_support,
    transform_scheme,
    verify_gf2,
    verify_integer,
)


class SignedProjectionAuditTest(unittest.TestCase):
    @staticmethod
    def naive_signed(n):
        return tuple(
            ({(i, j): 1}, {(j, k): 1}, {(k, i): 1})
            for i in range(n) for j in range(n) for k in range(n)
        )

    def test_trace_dual_output_is_transposed_for_flipfleet(self):
        signed = self.naive_signed(2)
        self.assertEqual(verify_integer(signed, 2), (True, 0, 0))
        projected = project_mod2(signed, 2)
        self.assertEqual(len(projected), 8)
        self.assertEqual(verify_gf2(projected, 2), (True, 0))

    def test_duplicate_projected_terms_cancel_by_parity(self):
        term = ({(0, 0): 1}, {(0, 0): -1}, {(0, 0): 1})
        self.assertEqual(project_mod2((term, term), 2), ())

    def test_all_twelve_tensor_images_remain_exact(self):
        projected = project_mod2(self.naive_signed(2), 2)
        images = {
            transform_scheme(projected, 2, code, reverse_indices)
            for reverse_indices in (False, True)
            for code in range(6)
        }
        # Naive is highly symmetric, so the image set can collapse; every
        # generated presentation must nevertheless pass the full gate.
        self.assertTrue(images)
        self.assertTrue(all(verify_gf2(image, 2) == (True, 0) for image in images))

    def test_four_term_relation_is_classified_as_an_ordinary_flip(self):
        left = ((1, 1, 1), (1, 2, 2))
        right = ((1, 3, 1), (1, 2, 3))
        relation = tuple(sorted(set(left) ^ set(right)))
        self.assertFalse(tensor_support(relation))
        stats = _relation_stats(relation, left)
        self.assertEqual(stats["ordinary_flip_components"], 1)
        self.assertEqual(stats["side_splits"], (((2, 2), 1),))

    def test_profile_parser_sees_frontier_inventory(self):
        profile = Path(__file__).with_name("flipfleet_profiles.w")
        paths = _profile_paths(profile)
        self.assertEqual(len(paths[4]), 2)
        self.assertGreaterEqual(len(paths[7]), 14)


if __name__ == "__main__":
    unittest.main()
