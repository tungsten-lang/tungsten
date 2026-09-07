import hashlib
from itertools import product
from pathlib import Path
import tempfile
import unittest

from extend_composition_parents import identity
from projection_composition_scan import scan_parent as minimum_scan, text
from projection_variant_portfolio import scan_parent


def naive(shape):
    n, m, p = shape
    return [(1 << (i*m+j), 1 << (j*p+k), 1 << (i*p+k))
            for i, j, k in product(range(n), range(m), range(p))]


def expansion(terms):
    result = set()
    def positions(word):
        return [i for i in range(word.bit_length()) if (word >> i) & 1]
    for term in terms:
        for basis in product(*(positions(word) for word in term)):
            if basis in result:
                result.remove(basis)
            else:
                result.add(basis)
    return result


class ProjectionVariantsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / 'parent.txt'
        self.shape = (2, 3, 2)

    def entry(self, terms):
        self.assertEqual(expansion(naive(self.shape)), expansion(terms))
        data = text(terms)
        self.path.write_bytes(data)
        return dict(id=0, path=str(self.path), shape=self.shape, rank=len(terms),
                    sha256=hashlib.sha256(data).hexdigest(), identity=identity(self.shape, terms))

    def check_outputs(self, report):
        for row in report['rows']:
            self.assertEqual(expansion(naive(row['shape'])), expansion(row['terms']))
            self.assertEqual(row['identity'], identity(row['shape'], row['terms']))
        self.assertEqual(len(report['rows']), len({r['identity'] for r in report['rows']}))

    def split_parent(self):
        terms = naive(self.shape)
        u, v, w = terms.pop(0)
        delta = 1 << 5
        terms.extend(((u, v ^ delta, w), (u, delta, w)))
        return self.entry(terms)

    def test_keeps_valid_above_minimum_image(self):
        entry = self.split_parent()
        report = scan_parent((entry, {(2, 2, 2): 7}, 2, 2, [], 20000))
        self.check_outputs(report)
        self.assertEqual({8, 9}, {r['rank'] for r in report['rows']})
        self.assertTrue(any(r['above_parent_minimum'] for r in report['rows']))
        control = minimum_scan((entry, [], 20000))
        self.assertEqual([8], [r['rank'] for r in control['rows'] if r['shape'] == (2, 2, 2)])

    def test_keeps_distinct_minimum_ties(self):
        terms = naive(self.shape)
        (u, v, w), (_, vv, ww) = terms[:2]
        terms[:2] = [(u, v ^ vv, w), (u, vv, w ^ ww)]
        entry = self.entry(terms)
        report = scan_parent((entry, {(2, 2, 2): 7}, 1, 2, [], 20000))
        self.check_outputs(report)
        self.assertEqual(2, len(report['rows']))
        self.assertTrue(all(r['rank'] == 8 and not r['above_parent_minimum'] for r in report['rows']))
        self.assertEqual(1, report['within_parent_duplicates'])

    def test_rank_allowance_is_exact(self):
        entry = self.split_parent()
        smaller = scan_parent((entry, {(2, 2, 2): 7}, 1, 2, [], 20000))
        self.check_outputs(smaller)
        self.assertEqual({8}, {r['rank'] for r in smaller['rows']})
        none = scan_parent((entry, {(2, 2, 2): 7}, 0, 2, [], 20000))
        self.assertEqual([], none['rows'])

    def test_overlapping_families_do_not_repeat_views(self):
        entry = self.split_parent()
        a = scan_parent((entry, {(2, 2, 2): 7}, 2, 2, [], 20000))
        b = scan_parent((entry, {(2, 2, 2): 7}, 2, 2, [(2, 2, 2)], 20000))
        self.assertEqual(a['views'], b['views'])
        self.assertEqual(a['rows'], b['rows'])

    def test_rejects_stale_source_or_identity(self):
        entry = self.split_parent()
        for field in ('sha256', 'identity'):
            wrong = dict(entry, **{field: '0'*64})
            with self.assertRaises(ValueError):
                scan_parent((wrong, {(2, 2, 2): 7}, 2, 2, [], 20000))
        with self.assertRaises(ValueError):
            scan_parent((entry, {(2, 2, 2): 7}, -1, 2, [], 20000))


if __name__ == '__main__':
    unittest.main()
