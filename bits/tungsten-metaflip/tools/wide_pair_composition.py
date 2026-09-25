"""Exact multiword shared-factor pair composition over GF(2).

The small leaf is a projected 2x3x3/r15 catalogue tensor. Pairing two parent
terms that share one factor replaces 18 naive scale-three terms by 15. This
is a cold constructor; all proposed outputs must cross a full tensor check.
"""
from collections import Counter
from pathlib import Path

import screen_top_two_projection_children as tensor

HERE = Path(__file__).resolve().parent
LEAF_SOURCE = (HERE.parent / "lib/metaflip/seeds/gf2/"
               "matmul_2x3x5_rank26_peterson_2026_block15_11_gf2.txt")
EDGES = ((0, 1), (1, 2), (0, 2))
TO_OUTPUT_EDGE = ((0, 2, 1), (1, 0, 2), (0, 1, 2))


def bits(word):
    while word:
        bit = word & -word
        yield bit.bit_length() - 1
        word ^= bit


def permute(shape, terms, order):
    """Explicit node permutation, even when dimensions coincide."""
    if sorted(order) != [0, 1, 2]:
        raise ValueError("invalid node permutation")
    result = []
    for term in terms:
        output = []
        for r, c in EDGES:
            old_r, old_c = order[r], order[c]
            edge = EDGES.index(tuple(sorted((old_r, old_c))))
            value = term[edge]
            if old_r > old_c:
                rows, columns = shape[old_c], shape[old_r]
                value = sum(1 << ((bit % columns) * rows + bit // columns)
                            for bit in bits(value))
            output.append(value)
        result.append(tuple(output))
    return tuple(shape[i] for i in order), result


def leaf_three():
    raw = tensor.parse_terms(LEAF_SOURCE.read_bytes(), 26)
    tensor.exact((2, 3, 5), raw)
    shape, terms = tensor.project((2, 3, 5), raw, 2, 4)
    shape, terms = tensor.project(shape, terms, 2, 3)
    if shape != (2, 3, 3) or len(terms) != 15:
        raise ValueError("unexpected projected pair leaf")
    tensor.exact(shape, terms)
    shape, terms = permute(shape, terms, (1, 0, 2))
    tensor.exact(shape, terms)
    return terms


def expand(word, parent_columns, leaf, leaf_rows, leaf_columns):
    output_columns = parent_columns * leaf_columns
    return sum(1 << ((i // parent_columns * leaf_rows + j // leaf_columns) *
                     output_columns + i % parent_columns * leaf_columns +
                     j % leaf_columns)
               for i in bits(word) for j in bits(leaf))


def compose_output_pairs(shape, terms, *, max_rank=16384):
    """Scale first/last dimensions by three; pair terms with equal W."""
    tensor.exact(shape, terms)
    n, m, p = shape
    if max(n * m, m * p, n * p) > 1024:
        raise ValueError("parent factor exceeds 1024-bit cold adapter")
    pending, pairs, singles = {}, [], []
    for term in terms:
        mate = pending.pop(term[2], None)
        if mate is None:
            pending[term[2]] = term
        else:
            pairs.append((mate, term))
    singles.extend(pending.values())
    predicted = 15 * len(pairs) + 9 * len(singles)
    if predicted > max_rank:
        return None
    leaf = leaf_three()
    parity = Counter()
    for first, second in pairs:
        for a, b, c in leaf:
            a0 = sum(1 << (bit // 2) for bit in bits(a) if bit % 2 == 0)
            a1 = sum(1 << (bit // 2) for bit in bits(a) if bit % 2 == 1)
            b0, b1 = b & 7, b >> 3
            output = (
                expand(first[0], m, a0, 3, 1) ^
                expand(second[0], m, a1, 3, 1),
                expand(first[1], p, b0, 1, 3) ^
                expand(second[1], p, b1, 1, 3),
                expand(first[2], p, c, 3, 3),
            )
            if all(output):
                parity[output] ^= 1
    for u, v, w in singles:
        for i in range(3):
            for j in range(3):
                output = (expand(u, m, 1 << i, 3, 1),
                          expand(v, p, 1 << j, 1, 3),
                          expand(w, p, 1 << (3 * i + j), 3, 3))
                parity[output] ^= 1
    target = (3 * n, m, 3 * p)
    result = sorted(term for term, odd in parity.items() if odd)
    tensor.exact(target, result)
    return target, result, len(pairs), predicted


def compose_pairs(shape, terms, axis, *, max_rank=16384):
    """Shared factor axis 0=U, 1=V, 2=W; return exact scaled tensor."""
    if axis not in range(3):
        raise ValueError("invalid shared factor axis")
    order = TO_OUTPUT_EDGE[axis]
    rotated, source = permute(shape, terms, order)
    result = compose_output_pairs(rotated, source, max_rank=max_rank)
    if result is None:
        return None
    target, output, pairs, predicted = result
    inverse = tuple(order.index(i) for i in range(3))
    target, output = permute(target, output, inverse)
    tensor.exact(target, output)
    return target, output, pairs, predicted
