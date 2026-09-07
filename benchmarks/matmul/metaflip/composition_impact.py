#!/usr/bin/env python3
"""Exact bounded composition prices and conditional one-rank sensitivity.

This planner is not a tensor verifier. Parent structures and seed prices must
come from checked witnesses. A hypothetical channel is NEVER an admitted rank.
Search state identity is unaffected: only identical price expressions are
deduplicated here, not tensor states with the same bucket histogram.

Parents may supply mixed_partitions: complete literal term-index partitions,
with each group specifying axis 0/1/2 (or None for a singleton) and indices.
Small elementary grids instead specify elementary_shape (sides 1..4) and
indices in lexicographic coordinate order. Grids may split recursively along
coordinate planes; shared groups may split along their single free axis.
At each scale any shared group may split into cheaper chunks. Arithmetic
validation checks the cover; the exact materializer also verifies the claimed
factor equality against the pinned parent tensor, before splitting it.
"""
from collections import Counter, defaultdict
from itertools import combinations_with_replacement, product
from math import prod

import numpy as np


def canonical(shape):
    shape = tuple(sorted(shape))
    if len(shape) != 3 or any(type(n) is not int or n < 1 for n in shape):
        raise ValueError('invalid shape')
    return shape


class CompositionImpact:
    def __init__(self, seeds, parents=(), maximum=32, *, deduplicate_parent_pricing=True):
        if type(maximum) is not int or not 2 <= maximum <= 32:
            raise ValueError('invalid maximum')
        self.maximum = maximum
        self.shapes = sorted(combinations_with_replacement(range(1, maximum+1), 3),
                             key=lambda s: (prod(s), s))
        self.index = {s: i for i, s in enumerate(self.shapes)}
        self.seeds = {}
        for shape, rank in seeds.items():
            shape = canonical(shape)
            if max(shape) > maximum or type(rank) is not int or rank < 1:
                raise ValueError('invalid seed')
            self.seeds[shape] = min(rank, self.seeds.get(shape, prod(shape)))
        self.parents = []
        self.buds = defaultdict(list)
        self.mixed_buds = defaultdict(list)
        seen = defaultdict(set)
        mixed_seen = defaultdict(set)
        compiled_parents = set()
        self.parent_pricing_duplicates = 0
        for parent in parents:
            shape = tuple(parent['shape'])
            canonical(shape)
            signature = tuple(tuple(sorted(axis)) for axis in parent['signature'])
            if len(signature) != 3 or not signature[0]:
                raise ValueError('invalid parent signature')
            rank = sum(signature[0])
            if any(sum(a) != rank or any(type(k) is not int or k < 1 for k in a)
                   for a in signature):
                raise ValueError('invalid parent buckets')
            if any(max(a) >= prod(shape) for a in signature):
                raise ValueError('non-decreasing parent dependency')
            partitions = []
            for groups in parent.get('mixed_partitions', ()):
                partition, indices = [], []
                for group in groups:
                    grid = set(group) == {'elementary_shape', 'indices'}
                    if not grid and set(group) != {'axis', 'indices'}:
                        raise ValueError('unsupported mixed group')
                    ids = group['indices']
                    if not ids or any(type(j) is not int for j in ids):
                        raise ValueError('invalid mixed group indices')
                    if len(ids) >= prod(shape):
                        raise ValueError('non-decreasing mixed group')
                    indices.extend(ids)
                    if grid:
                        dims = group['elementary_shape']
                        if (len(dims) != 3 or any(type(d) is not int or not 1 <= d <= 4 for d in dims)
                                or prod(dims) != len(ids)):
                            raise ValueError('invalid elementary grid')
                        partition.append(dict(elementary_shape=list(dims), indices=list(ids)))
                    else:
                        axis = group['axis']
                        if axis is None:
                            if len(ids) != 1:
                                raise ValueError('only singletons can omit axis')
                            axis = 0
                        if type(axis) is not int or axis not in (0, 1, 2):
                            raise ValueError('invalid mixed group axis')
                        partition.append(dict(axis=axis, indices=list(ids)))
                if sorted(indices) != list(range(rank)):
                    raise ValueError('mixed partition must cover each parent term once')
                partitions.append(partition)
            parent_id = len(self.parents)
            self.parents.append(dict(parent, shape=shape, signature=signature,
                                     mixed_partitions=partitions))
            # These counts depend on the literal parent partition, not on the
            # scale or any price channel. Compile them once; keep every full
            # partition above for witness identity and materialization.
            signature_counts = [tuple(sorted(Counter(sizes).items())) for sizes in signature]
            partition_specs = []
            for groups in partitions:
                buckets = []
                for axis in range(3):
                    counts = Counter(len(g['indices']) for g in groups if g.get('axis') == axis)
                    if counts:
                        buckets.append((axis, tuple(sorted(counts.items()))))
                grids = tuple(sorted(Counter(tuple(g['elementary_shape']) for g in groups
                                             if 'elementary_shape' in g).items()))
                partition_specs.append((buckets, grids))
            # Only skip repeated arithmetic expansion. The full parent and
            # every literal partition remain in self.parents above. An equal
            # ordered pricing template emits identical expressions at every
            # scale; the earlier source already wins all first-witness ties.
            pricing_key = (shape, tuple(signature_counts),
                           tuple((tuple(buckets), grids) for buckets, grids in partition_specs))
            if deduplicate_parent_pricing and pricing_key in compiled_parents:
                self.parent_pricing_duplicates += 1
                continue
            compiled_parents.add(pricing_key)
            for scale in product(*(range(1, maximum//d+1) for d in shape)):
                target = canonical(tuple(d*s for d, s in zip(shape, scale)))
                leaf_cache = {}

                def bucket(axis, counts):
                    expanded = (2, 0, 1)[axis]
                    limit = min(counts[-1][0], maximum//scale[expanded])
                    key = (axis, limit)
                    if key not in leaf_cache:
                        # All hypothetical bucket chunks have smaller volume.
                        leaves = []
                        for k in range(1, limit+1):
                            leaf = list(scale)
                            leaf[expanded] *= k
                            leaf = canonical(leaf)
                            if prod(leaf) >= prod(target):
                                raise ValueError('non-decreasing bud leaf')
                            leaves.append(self.index[leaf])
                        leaf_cache[key] = tuple(leaves)
                    return counts, leaf_cache[key]

                for axis, counts in enumerate(signature_counts):
                    counts, leaves = bucket(axis, counts)
                    expression = (counts, leaves)
                    if expression in seen[target]:
                        continue
                    seen[target].add(expression)
                    self.buds[self.index[target]].append(
                        (parent_id, scale, axis, counts, leaves))
                for partition_id, (specs, grids) in enumerate(partition_specs):
                    buckets = [(axis, *bucket(axis, counts)) for axis, counts in specs]
                    expression = (tuple(sorted((counts, leaves) for _, counts, leaves in buckets)),
                                  tuple((dims, count, scale) for dims, count in grids))
                    if expression in mixed_seen[target]:
                        continue
                    mixed_seen[target].add(expression)
                    self.mixed_buds[self.index[target]].append(
                        (parent_id, partition_id, scale, buckets, grids))
        self.blocks, self.kronecker = {}, {}
        for i, shape in enumerate(self.shapes):
            blocks, kron = set(), set()
            if 1 not in shape:
                for axis, extent in enumerate(shape):
                    for cut in range(1, extent//2+1):
                        left, right = list(shape), list(shape)
                        left[axis], right[axis] = cut, extent-cut
                        blocks.add(tuple(sorted((self.index[canonical(left)],
                                                 self.index[canonical(right)]))))
                divisors = [[d for d in range(1, n+1) if n % d == 0] for n in shape]
                for left in product(*divisors):
                    right = tuple(n//d for n, d in zip(shape, left))
                    if left == (1, 1, 1) or right == (1, 1, 1):
                        continue
                    kron.add(tuple(sorted((self.index[canonical(left)],
                                           self.index[canonical(right)]))))
            assert all(a < i and b < i for a, b in blocks | kron)
            self.blocks[i], self.kronecker[i] = sorted(blocks), sorted(kron)

    def solve(self, hypotheses=(), progress=None):
        """Channel zero is constructive; others assume the named rank exists."""
        hypotheses = [(canonical(s), r) for s, r in hypotheses]
        for s, r in hypotheses:
            if s not in self.index or type(r) is not int or not 1 <= r < prod(s):
                raise ValueError('invalid hypothesis')
        forced = defaultdict(list)
        for channel, (shape, rank) in enumerate(hypotheses, 1):
            forced[self.index[shape]].append((channel, rank))
        width = len(hypotheses)+1
        values = np.empty((len(self.shapes), width), dtype=np.int64)
        recipes = []
        bud_checks = 0
        mixed_bud_checks = 0
        for i, shape in enumerate(self.shapes):
            rank = min(prod(shape), self.seeds.get(shape, prod(shape)))
            best = np.full(width, rank, dtype=np.int64)
            recipe = dict(kind='seed' if rank < prod(shape) else 'naive', rank=rank)
            for channel, bound in forced[i]:
                best[channel] = min(int(best[channel]), bound)

            def accept(candidate, description):
                nonlocal recipe
                if candidate[0] < best[0]:
                    recipe = description
                np.minimum(best, candidate, out=best)

            for a, b in self.blocks[i]:
                accept(values[a]+values[b], dict(kind='block', inputs=[a, b]))
            for a, b in self.kronecker[i]:
                accept(values[a]*values[b], dict(kind='kronecker', inputs=[a, b]))
            # Only cache within this target: retaining all vector-valued DPs
            # across the entire grid would consume unnecessary memory.
            cache = {}
            grid_cache = {}

            def bucket_cost(counts, leaves):
                limit = counts[-1][0]
                key = (leaves, limit)
                if key not in cache:
                    dp = [np.zeros(width, dtype=np.int64)]
                    splits = [0]
                    for k in range(1, limit+1):
                        choices = [dp[k-j]+values[leaves[j-1]]
                                   for j in range(1, min(k, len(leaves))+1)]
                        splits.append(1+min(range(len(choices)), key=lambda j: int(choices[j][0])))
                        current = choices[0].copy()
                        for alternative in choices[1:]:
                            np.minimum(current, alternative, out=current)
                        dp.append(current)
                    cache[key] = dp, splits
                dp, splits = cache[key]
                cost = sum((count*dp[k] for k, count in counts),
                           np.zeros(width, dtype=np.int64))
                return cost, splits

            def grid_cost(dims, scale):
                key = (dims, scale)
                if key in grid_cache:
                    return grid_cache[key]
                leaf = canonical(tuple(d*s for d, s in zip(dims, scale)))
                best_grid, tile = None, None
                if max(leaf) <= self.maximum:
                    j = self.index[leaf]
                    assert j < i
                    best_grid, tile = values[j].copy(), dict(kind='leaf')
                for axis, extent in enumerate(dims):
                    for cut in range(1, extent//2+1):
                        left, right = list(dims), list(dims)
                        left[axis], right[axis] = cut, extent-cut
                        lcost, lplan = grid_cost(tuple(left), scale)
                        rcost, rplan = grid_cost(tuple(right), scale)
                        candidate = lcost+rcost
                        if best_grid is None:
                            best_grid = candidate.copy()
                            tile = dict(kind='cut', axis=axis, at=cut, left=lplan, right=rplan)
                        else:
                            if candidate[0] < best_grid[0]:
                                tile = dict(kind='cut', axis=axis, at=cut, left=lplan, right=rplan)
                            np.minimum(best_grid, candidate, out=best_grid)
                assert best_grid is not None
                grid_cache[key] = best_grid, tile
                return grid_cache[key]

            for parent_id, scale, axis, counts, leaves in self.buds.get(i, ()):
                cost, splits = bucket_cost(counts, leaves)
                accept(cost, dict(kind='bud', parent=parent_id, scale=list(scale),
                                  axis=axis, splits=splits))
                bud_checks += 1
            for parent_id, partition_id, scale, buckets, grids in self.mixed_buds.get(i, ()):
                cost = np.zeros(width, dtype=np.int64)
                splits = [None]*3
                for axis, counts, leaves in buckets:
                    part, splits[axis] = bucket_cost(counts, leaves)
                    cost += part
                description = dict(kind='mixed_bud', parent=parent_id, partition=partition_id,
                                   scale=list(scale), splits=splits)
                if grids:
                    description['grid_plans'] = {}
                    for dims, count in grids:
                        part, tile = grid_cost(dims, scale)
                        cost += count*part
                        description['grid_plans']['x'.join(map(str, dims))] = tile
                accept(cost, description)
                bud_checks += 1
                mixed_bud_checks += 1
            assert np.all(best > 0) and np.all(best <= best[0])
            values[i] = best
            recipe['rank'] = int(best[0])
            recipes.append(recipe)
            if progress and i % 500 == 0:
                progress(i, len(self.shapes), bud_checks)
        return dict(values=values, recipes=recipes, hypotheses=hypotheses,
                    bud_checks=bud_checks, mixed_bud_checks=mixed_bud_checks)

    def recipe_dependencies(self, i, recipe):
        if recipe['kind'] in ('seed', 'naive'):
            return []
        if recipe['kind'] not in ('bud', 'mixed_bud'):
            return recipe['inputs']
        parent = self.parents[recipe['parent']]
        scale = recipe['scale']
        if recipe['kind'] == 'bud':
            groups = [dict(axis=recipe['axis'], indices=range(k))
                      for k in parent['signature'][recipe['axis']]]
        else:
            groups = parent['mixed_partitions'][recipe['partition']]
        dependencies = []

        def grid_dependencies(dims, tile):
            if tile['kind'] == 'leaf':
                dependencies.append(self.index[canonical(tuple(d*s for d, s in zip(dims, scale)))])
            else:
                assert tile['kind'] == 'cut'
                axis, cut = tile['axis'], tile['at']
                assert type(axis) is int and 0 <= axis < 3
                assert type(cut) is int and 1 <= cut < dims[axis]
                left, right = list(dims), list(dims)
                left[axis], right[axis] = cut, dims[axis]-cut
                grid_dependencies(left, tile['left'])
                grid_dependencies(right, tile['right'])

        for group in groups:
            if 'elementary_shape' in group:
                dims = group['elementary_shape']
                grid_dependencies(dims, recipe['grid_plans']['x'.join(map(str, dims))])
                continue
            axis, k = group['axis'], len(group['indices'])
            splits = recipe['splits'] if recipe['kind'] == 'bud' else recipe['splits'][axis]
            expanded = (2, 0, 1)[axis]
            while k:
                chunk = splits[k]
                assert 1 <= chunk <= k
                leaf = list(scale)
                leaf[expanded] *= chunk
                dependencies.append(self.index[canonical(leaf)])
                k -= chunk
        assert all(j < i for j in dependencies)
        return dependencies

    def check_baseline_recipes(self, result):
        values, recipes = result['values'], result['recipes']
        for i, recipe in enumerate(recipes):
            deps = self.recipe_dependencies(i, recipe)
            if recipe['kind'] in ('seed', 'naive'):
                expected = min(prod(self.shapes[i]), self.seeds.get(self.shapes[i], prod(self.shapes[i])))
            elif recipe['kind'] == 'kronecker':
                expected = prod(int(values[j, 0]) for j in deps)
            else:
                expected = sum(int(values[j, 0]) for j in deps)
            assert int(values[i, 0]) == recipe['rank'] == expected
        return True
