import unittest

from composition_impact import CompositionImpact, canonical
from verify_recursive_portfolio import solver


class CompositionImpactTest(unittest.TestCase):
    def test_parent_pricing_skip_preserves_states_partitions_and_exact_recipes(self):
        from copy import deepcopy
        import numpy as np
        parent = dict(shape=(2, 3, 3), identity='first',
            signature=([3, 3, 2, 2, 1, 1], [4, 4, 4], [2]*6), mixed_partitions=[
                [dict(axis=0, indices=list(range(6))), dict(axis=1, indices=list(range(6, 12)))],
                [dict(elementary_shape=[2, 3, 1], indices=list(range(6))),
                 dict(elementary_shape=[2, 1, 3], indices=list(range(6, 12)))]])
        second = deepcopy(parent)
        second['identity'] = 'second'
        second['mixed_partitions'][0][0]['indices'].reverse()
        reordered = deepcopy(parent)
        reordered['identity'] = 'reordered'
        reordered['mixed_partitions'].reverse()
        models = [CompositionImpact({(2, 2, 2): 7}, [parent, second, reordered], maximum=6,
                    deduplicate_parent_pricing=flag) for flag in (False, True)]
        old, new = models
        self.assertEqual(new.parent_pricing_duplicates, 1)
        self.assertEqual(old.parents, new.parents)
        self.assertEqual(old.buds, new.buds)
        self.assertEqual(old.mixed_buds, new.mixed_buds)
        a, b = [m.solve([((2, 2, 2), 6)]) for m in models]
        np.testing.assert_array_equal(a.pop('values'), b.pop('values'))
        self.assertEqual(a, b)
        self.assertEqual([p['identity'] for p in new.parents], ['first', 'second', 'reordered'])

    def test_scalar_parity_and_counterfactual_isolation(self):
        seeds = {(2, 2, 2): 7, (2, 3, 3): 15, (3, 3, 3): 23}
        model = CompositionImpact(seeds, maximum=6)
        hypotheses = [((2, 3, 3), 14), ((3, 3, 3), 22)]
        result = model.solve(hypotheses)
        for channel, changed in enumerate([None]+hypotheses):
            modified = dict(seeds)
            if changed:
                modified[changed[0]] = changed[1]
            scalar = solver(modified)
            for i, shape in enumerate(model.shapes):
                self.assertEqual(int(result['values'][i, channel]), scalar(shape))
        self.assertTrue(model.check_baseline_recipes(result))

    def test_bud_recurrence_and_recipe(self):
        # A synthetic price-expression fixture, not a tensor witness.
        parent = dict(shape=(2, 2, 3), signature=([2, 2, 3], [1]*7, [1]*7))
        model = CompositionImpact({(2, 2, 2): 7}, [parent], maximum=6)
        result = model.solve([((2, 2, 2), 6)])
        self.assertEqual(int(result['values'][model.index[(2, 2, 3)], 0]), 7)
        self.assertTrue(model.check_baseline_recipes(result))
        for channel, rank in enumerate((7, 6)):
            expressions = {}
            # Independently enumerate every possible bucket partition,
            # without reusing the vector planner's DP or backtracking.
            def parts(n, cap):
                if n == 0:
                    return [()]
                return [(j,)+tail for j in range(1, min(n, cap)+1)
                        for tail in parts(n-j, cap)]
            from itertools import product
            for scale in product(range(1, 4), range(1, 4), range(1, 3)):
                target = canonical(tuple(a*b for a, b in zip(parent['shape'], scale)))
                rows = []
                for axis, sizes in enumerate(parent['signature']):
                    expanded = (2, 0, 1)[axis]
                    for allocation in product(*(parts(k, 6//scale[expanded]) for k in sizes)):
                        leaves = []
                        for chunks in allocation:
                            for k in chunks:
                                leaf = list(scale)
                                leaf[expanded] *= k
                                leaves.append((1, canonical(leaf)))
                        rows.append(tuple(leaves))
                expressions.setdefault(target, []).extend(rows)
            scalar = solver({(2, 2, 2): rank}, expressions)
            for i, shape in enumerate(model.shapes):
                self.assertEqual(int(result['values'][i, channel]), scalar(shape))

    def test_reject_non_decreasing_parent(self):
        with self.assertRaises(ValueError):
            CompositionImpact({}, [dict(shape=(2, 2, 2), signature=([8], [8], [8]))], maximum=4)

    def test_mixed_partition_scalar_parity_and_split_recipes(self):
        # Synthetic arithmetic only; exact shared-factor checks belong to the
        # materializer. Enumerate all literal group splits independently.
        from itertools import product
        groups = [dict(axis=0, indices=[0, 1, 2]), dict(axis=1, indices=[3, 4]),
                  dict(axis=2, indices=[5]), dict(axis=None, indices=[6])]
        parent = dict(shape=(2, 2, 3), signature=([1]*7, [1]*7, [1]*7),
                      mixed_partitions=[groups])
        model = CompositionImpact({(2, 2, 2): 7}, [parent], maximum=6)
        result = model.solve([((2, 2, 2), 6)])
        self.assertGreater(result['mixed_bud_checks'], 0)
        self.assertTrue(any(r['kind'] == 'mixed_bud' for r in result['recipes']))
        self.assertTrue(model.check_baseline_recipes(result))

        def parts(n, cap):
            if not n:
                return [()]
            return [(j,)+tail for j in range(1, min(n, cap)+1)
                    for tail in parts(n-j, cap)]

        expressions = {}
        for scale in product(range(1, 4), range(1, 4), range(1, 3)):
            target = canonical(tuple(a*b for a, b in zip(parent['shape'], scale)))
            rows = [tuple([(1, canonical(scale))]*7)]
            options = []
            for group in groups:
                expanded = (2, 0, 1)[group['axis'] or 0]
                choices = []
                for chunks in parts(len(group['indices']), 6//scale[expanded]):
                    leaves = []
                    for k in chunks:
                        leaf = list(scale)
                        leaf[expanded] *= k
                        leaves.append((1, canonical(leaf)))
                    choices.append(leaves)
                options.append(choices)
            rows.extend(tuple(leaf for group in allocation for leaf in group)
                        for allocation in product(*options))
            expressions.setdefault(target, []).extend(rows)
        for channel, rank in enumerate((7, 6)):
            scalar = solver({(2, 2, 2): rank}, expressions)
            for i, shape in enumerate(model.shapes):
                self.assertEqual(int(result['values'][i, channel]), scalar(shape))

    def test_invalid_mixed_partitions_rejected(self):
        from copy import deepcopy
        parent = dict(shape=(2, 2, 2), signature=([1]*7, [1]*7, [1]*7),
                      mixed_partitions=[[dict(axis=None, indices=[i]) for i in range(7)]])
        for change in ('missing', 'duplicate', 'axis', 'float', 'extra', 'nil_pair'):
            bad = deepcopy(parent)
            groups = bad['mixed_partitions'][0]
            if change == 'missing':
                groups.pop()
            elif change == 'duplicate':
                groups[-1]['indices'] = [0]
            elif change == 'axis':
                groups[0]['axis'] = True
            elif change == 'float':
                groups[0]['indices'] = [0.0]
            elif change == 'extra':
                groups[0]['elementary_shape'] = [1, 1, 1]
            else:
                groups[0]['indices'].extend(groups.pop()['indices'])
            with self.subTest(change=change), self.assertRaises(ValueError):
                CompositionImpact({}, [bad], maximum=4)

    def test_compiled_bucket_tables_preserve_literal_identity_and_first_ties(self):
        from collections import Counter, defaultdict
        from copy import deepcopy
        from itertools import product
        # Arithmetic fixtures only: factor equality remains the materializer's
        # gate. Mixed groups may exceed a signature bucket in an invalid tensor
        # fixture, so the arithmetic cache must not assume that bound implicitly.
        parent = dict(shape=(2, 3, 3), identity='first',
                      signature=([3, 3, 2, 2, 1, 1], [4, 4, 4], [2]*6),
                      mixed_partitions=[
                          [dict(axis=0, indices=list(range(4))),
                           dict(axis=1, indices=list(range(4, 8))),
                           dict(axis=2, indices=list(range(8, 11))),
                           dict(axis=None, indices=[11])],
                          [dict(elementary_shape=[2, 3, 1], indices=[5, 4, 3, 2, 1, 0]),
                           dict(elementary_shape=[2, 1, 3], indices=list(range(6, 12)))]])
        second = deepcopy(parent)
        second['identity'] = 'second'
        second['mixed_partitions'].reverse()
        model = CompositionImpact({(2, 2, 2): 7}, [parent, second], maximum=6)
        self.assertEqual([p['identity'] for p in model.parents], ['first', 'second'])
        self.assertEqual(model.parents[0]['mixed_partitions'][1][0]['indices'], [5, 4, 3, 2, 1, 0])
        expected, seen = defaultdict(list), defaultdict(set)
        # Directly rebuild every expression from its literal group list at
        # every scale, independently of the constructor's compiled metadata.
        for parent_id, p in enumerate(model.parents):
            for scale in product(*(range(1, 6//d+1) for d in p['shape'])):
                target = model.index[canonical(tuple(a*b for a, b in zip(p['shape'], scale)))]
                for partition_id, groups in enumerate(p['mixed_partitions']):
                    buckets = []
                    for axis in range(3):
                        sizes = [len(g['indices']) for g in groups if g.get('axis') == axis]
                        if not sizes:
                            continue
                        expanded = (2, 0, 1)[axis]
                        leaves = []
                        for k in range(1, min(max(sizes), 6//scale[expanded])+1):
                            leaf = list(scale)
                            leaf[expanded] *= k
                            leaves.append(model.index[canonical(leaf)])
                        buckets.append((axis, tuple(sorted(Counter(sizes).items())), tuple(leaves)))
                    grids = tuple(sorted(Counter(tuple(g['elementary_shape']) for g in groups
                                                 if 'elementary_shape' in g).items()))
                    key = (tuple(sorted((counts, leaves) for _, counts, leaves in buckets)),
                           tuple((dims, count, scale) for dims, count in grids))
                    if key not in seen[target]:
                        seen[target].add(key)
                        expected[target].append((parent_id, partition_id, scale, buckets, grids))
        self.assertEqual(dict(model.mixed_buds), dict(expected))
        before = model.solve([((2, 2, 2), 6), ((2, 3, 3), 14)])
        parent['mixed_partitions'][0][0]['indices'].clear()
        after = model.solve([((2, 2, 2), 6), ((2, 3, 3), 14)])
        self.assertEqual(before['recipes'], after['recipes'])
        self.assertEqual(before['values'].tolist(), after['values'].tolist())
        self.assertTrue(model.check_baseline_recipes(after))

    def test_elementary_grid_split_matches_independent_tilings(self):
        from itertools import product
        # Synthetic price fixture; literal factor-map validation is exercised
        # independently in the Ruby materializer and tensor-replay tests.
        dims = (3, 2, 1)
        parent = dict(shape=(2, 2, 3), signature=([1]*7, [1]*7, [1]*7),
                      mixed_partitions=[[dict(elementary_shape=list(dims), indices=list(range(6))),
                                         dict(axis=None, indices=[6])]])
        model = CompositionImpact({(2, 2, 2): 7}, [parent], maximum=6)
        result = model.solve([((2, 2, 2), 6)])
        self.assertTrue(model.check_baseline_recipes(result))
        self.assertTrue(any(r.get('grid_plans') for r in result['recipes']))

        def tilings(shape, scale):
            leaf = tuple(d*s for d, s in zip(shape, scale))
            choices = {(canonical(leaf),)} if max(leaf) <= 6 else set()
            for axis, extent in enumerate(shape):
                # All ordered cuts, independently of the planner's half-range.
                for cut in range(1, extent):
                    left, right = list(shape), list(shape)
                    left[axis], right[axis] = cut, extent-cut
                    choices.update(tuple(sorted(l+r)) for l in tilings(left, scale)
                                   for r in tilings(right, scale))
            return choices

        expressions = {}
        for scale in product(range(1, 4), range(1, 4), range(1, 3)):
            target = canonical(tuple(a*b for a, b in zip(parent['shape'], scale)))
            rows = [tuple([(1, canonical(scale))]*7)]
            rows.extend(tuple((1, leaf) for leaf in tiles)+( (1, canonical(scale)), )
                        for tiles in tilings(dims, scale))
            expressions.setdefault(target, []).extend(rows)
        for channel, rank in enumerate((7, 6)):
            scalar = solver({(2, 2, 2): rank}, expressions)
            for i, shape in enumerate(model.shapes):
                self.assertEqual(int(result['values'][i, channel]), scalar(shape))
        parent['mixed_partitions'][0][0]['elementary_shape'] = [5, 1, 1]
        with self.assertRaises(ValueError):CompositionImpact({}, [parent], maximum=6)


if __name__ == '__main__':
    unittest.main()
