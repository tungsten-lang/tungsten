import hashlib
from itertools import permutations
import json
from pathlib import Path
import tempfile
import unittest

from pair_reduction_scan import has_merge, reduce_pairs
from projection_composition_scan import text
from test_fold_projection_scan import walked
from test_projection_variant_portfolio import naive, expansion
from verify_pair_reductions import replay, verify


class PairReductionTest(unittest.TestCase):
    def test_all_orders_preserve_full_tensors_and_reach_pair_free_forms(self):
        shape = (2, 3, 2)
        for seed in range(12):
            terms = walked(shape, seed)
            # Exact rank-increasing split creates a guaranteed cleanup gate.
            term = list(terms.pop())
            left, right = term.copy(), term.copy()
            left[seed % 3] ^= 1
            right[seed % 3] = 1
            if left[seed % 3]:
                terms.extend([tuple(left), tuple(right)])
            else:
                terms.extend([tuple(term), tuple(term), tuple(term)])
            self.assertEqual(expansion(terms), expansion(naive(shape)))
            self.assertTrue(has_merge(terms))
            for order in permutations(range(3)):
                child, trace = reduce_pairs(terms, order)
                row = dict(shape=list(shape), parent_shape=list(shape), keep=[list(range(n)) for n in shape],
                           reduction_order=list(order), reduction_trace=trace)
                self.assertEqual(child, replay(row, terms))
                self.assertEqual(expansion(child), expansion(terms))
                self.assertLess(len(child), len(terms))
                self.assertFalse(has_merge(child))
                self.assertEqual(reduce_pairs(child, order), (child, []))

    def test_duplicate_cancellation_and_invalid_order(self):
        self.assertEqual(reduce_pairs([(1, 2, 4)]*2)[0], [])
        for order in ((0, 1, True), (0, 0, 1), (0, 1), (0, 1, 3)):
            with self.assertRaises(ValueError):
                reduce_pairs([(1, 2, 4)], order)

    def test_full_file_audit_and_corrupt_trace(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            terms = naive((2, 2, 2))
            a, b, c = terms.pop()
            terms.extend([(a, b, c ^ 1), (a, b, 1)])
            child, trace = reduce_pairs(terms)
            source_data, child_data = text(terms), text(child)
            (root/'parent.txt').write_bytes(source_data)
            (root/'child.txt').write_bytes(child_data)
            row = dict(shape=[2, 2, 2], parent_shape=[2, 2, 2], keep=[[0, 1]]*3,
                path='child.txt', sha256=hashlib.sha256(child_data).hexdigest(),
                parent_path='parent.txt', parent_sha256=hashlib.sha256(source_data).hexdigest(),
                rank=len(child), baseline=8, improves_local=False,
                reduction_order=[0, 1, 2], reduction_trace=trace)
            report = dict(complete=True, field='GF(2)', record_claim=False,
                projection_kind='shared_pair_reduction', selected_parents=1, parents_done=1,
                views=6, rows=[dict(views=6)], outputs=[row])
            (root/'report.json').write_text(json.dumps(report))
            self.assertEqual(verify(root, 1)['tensors'], 2)
            row['reduction_trace'][0]['after'] += 1
            (root/'report.json').write_text(json.dumps(report))
            with self.assertRaises(AssertionError):
                verify(root, 1)


if __name__ == '__main__':
    unittest.main()
