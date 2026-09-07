"""Prove coverage of appended ordinary-bud pricing expressions, not states.

An axis template records its expanded dimension, the other two dimensions,
and the multiset of equal-factor bucket sizes. Matching templates emit the
same target/leaf expressions under a permutation of scale coordinates.
Mixed partitions conservatively require the normal composition planner.
This helper alone does not certify that a supplied price table is closed.
"""
from collections import Counter
from itertools import permutations
from math import prod

FREE = (2, 0, 1)


def ordinary_templates(parent, maximum):
    shape, signature = tuple(parent['shape']), parent['signature']
    if (len(shape) != 3 or any(type(n) is not int or not 1 <= n <= maximum for n in shape) or
        len(signature) != 3 or not signature[0]):
        raise ValueError('invalid ordinary parent')
    rank = sum(signature[0])
    if (rank != parent['rank'] or any(not sizes or sum(sizes) != rank or
        any(type(size) is not int or not 1 <= size < prod(shape) for size in sizes) for sizes in signature)):
        raise ValueError('invalid ordinary bucket partition')
    return tuple((shape[free], tuple(sorted(shape[j] for j in range(3) if j != free)),
                  tuple(sorted(Counter(signature[axis]).items()))) for axis, free in enumerate(FREE))


def ordinary_expression_cover(previous, appended, maximum=32):
    """Return scale-permutation witnesses, or None if any expression is new.

    Every appended tensor remains a separate parent; no identity, terms or
    future flip-search state is deleted. Prior parents may also have mixed
    partitions, since their ordinary axes are always emitted independently.
    """
    if type(maximum) is not int or not 2 <= maximum <= 32:
        raise ValueError('invalid maximum')
    lookup = {}
    for index, parent in enumerate(previous):
        for axis, key in enumerate(ordinary_templates(parent, maximum)):
            lookup.setdefault(key, (index, axis))
    witnesses = []
    for index, parent in enumerate(appended):
        keys = ordinary_templates(parent, maximum)
        if parent.get('mixed_partitions'):
            return None
        axes = []
        for axis, key in enumerate(keys):
            if key not in lookup:
                return None
            old_index, old_axis = lookup[key]
            old_shape = previous[old_index]['shape']
            permutation = next(p for p in permutations(range(3))
                if p[FREE[axis]] == FREE[old_axis] and
                all(parent['shape'][j] == old_shape[p[j]] for j in range(3)))
            axes.append(dict(axis=axis, prior_parent=old_index, prior_axis=old_axis,
                             scale_permutation=permutation))
        witnesses.append(dict(appended_parent=index, axes=axes))
    return witnesses
