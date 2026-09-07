import unittest
from verify_matrix_pockets import image_report, pocket_code, pockets, rank, signature, small_ranks, unreduced_group_order


class PocketChecks(unittest.TestCase):
    def test_lookup_distinguishes_cancellation_from_full_column_rank(self):
        distance = small_ranks()
        four = [(1, 1, 1), (2, 1, 2), (4, 2, 3), (8, 3, 3)]
        code, dim = pocket_code(four, 0)
        self.assertEqual((distance[code], dim), (3, 3))
        self.assertEqual(signature(four), signature([(9, 1, 1), (10, 1, 2), (12, 2, 3)]))
        full = [(1, 1, 1), (2, 1, 2), (4, 2, 1), (8, 2, 2)]
        code, dim = pocket_code(full, 0)
        self.assertEqual((distance[code], dim), (4, 4))
        self.assertIn((0, (0, 1, 2, 3)), list(pockets(four)))

    def test_exact_image_spaces_on_naive_scalar_blocks(self):
        data = image_report([2, 1, 1], [(1, 1, 1), (2, 1, 2)], [[1, 1], [1], [1]], [[1, 1, 1]] * 2)
        self.assertTrue(data['all_disjoint'])
        self.assertEqual(data['pairs'][0]['intersection_dimensions'], [0, 1, 0])
        overlap = image_report([1, 1, 1], [(1, 1, 1)] * 2, [[1], [1], [1]], [[1, 1, 1]] * 2)
        self.assertFalse(overlap['all_disjoint'])
        self.assertEqual(overlap['pairs'][0]['intersection_dimensions'], [1, 1, 1])

    def test_invalid_domain_and_changed_tensor(self):
        self.assertRaises(AssertionError, rank, [-1])
        self.assertNotEqual(signature([(1, 1, 1)]), signature([(1, 1, 2)]))
        self.assertRaises(AssertionError, pocket_code, [(1, 1, 1), (2, 2, 2), (4, 4, 4)], 0)

    def test_empty_compression_history_still_has_a_working_order(self):
        terms = [(1, 1, 1), (2, 2, 2), (4, 4, 1)]
        ordered = unreduced_group_order(terms)
        self.assertEqual(ordered, [terms[0], terms[2], terms[1]])
        self.assertEqual(signature(terms), signature(ordered))
        self.assertRaises(AssertionError, unreduced_group_order, [(1, 1, 1), (1, 1, 2)])


if __name__ == '__main__':
    unittest.main()
