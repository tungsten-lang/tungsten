import copy
from itertools import permutations, product
import unittest

from composition_expression_cover import FREE, ordinary_expression_cover
from composition_impact import CompositionImpact


def naive_parent(shape):
    a, b, c = shape
    return dict(shape=shape, rank=a*b*c, signature=[[c]*(a*b), [a]*(b*c), [b]*(a*c)], mixed_partitions=[])


class ExpressionCoverTest(unittest.TestCase):
    def test_all_axis_permutations_emit_identical_model_and_witnesses(self):
        previous = [naive_parent((2, 3, 4))]
        appended = [naive_parent(shape) for shape in permutations((2, 3, 4))]
        cover = ordinary_expression_cover(previous, appended, 8)
        self.assertEqual(len(cover), 6)
        for entry, parent in zip(cover, appended):
            for witness in entry['axes']:
                axis, old_axis, p = witness['axis'], witness['prior_axis'], witness['scale_permutation']
                for scale in product(*(range(1, 8//n+1) for n in parent['shape'])):
                    old_scale = [0]*3
                    for j in range(3):
                        old_scale[p[j]] = scale[j]
                    self.assertEqual(sorted(n*s for n, s in zip(parent['shape'], scale)),
                                     sorted(n*s for n, s in zip(previous[0]['shape'], old_scale)))
                    for size in range(1, max(parent['signature'][axis])+1):
                        new_leaf, old_leaf = list(scale), list(old_scale)
                        new_leaf[FREE[axis]] *= size
                        old_leaf[FREE[old_axis]] *= size
                        self.assertEqual(sorted(new_leaf), sorted(old_leaf))
        left = CompositionImpact({}, previous, maximum=8)
        right = CompositionImpact({}, previous+appended, maximum=8)
        self.assertEqual(left.buds, right.buds)
        self.assertEqual(left.mixed_buds, right.mixed_buds)
        l, r = left.solve(), right.solve()
        self.assertEqual(l['values'].tolist(), r['values'].tolist())
        self.assertEqual(l['recipes'], r['recipes'])
        self.assertEqual(len(right.parents), 7)

    def test_new_signature_and_mixed_partition_require_normal_planner(self):
        previous = [naive_parent((2, 2, 2))]
        parent = copy.deepcopy(previous[0])
        parent['signature'][0] = [1]*8
        self.assertIsNone(ordinary_expression_cover(previous, [parent]))
        parent = copy.deepcopy(previous[0])
        parent['mixed_partitions'] = [[dict(axis=None, indices=[i]) for i in range(8)]]
        self.assertIsNone(ordinary_expression_cover(previous, [parent]))

    def test_rejects_invalid_descriptor_before_cover(self):
        previous = [naive_parent((2, 2, 2))]
        for field, bad in (('rank', 7), ('shape', [2, 2, 33]), ('signature', [[8], [2]*4, [2]*4])):
            parent = dict(previous[0], **{field: bad})
            with self.assertRaises(ValueError):
                ordinary_expression_cover(previous, [parent])


if __name__ == '__main__':
    unittest.main()
