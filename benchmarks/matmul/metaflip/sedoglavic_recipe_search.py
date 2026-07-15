#!/usr/bin/env python3
"""Offline coordinate-placement search for flipfleet_sedoglavic.w.

This is a development oracle only; production composition and verification are
pure Tungsten. It searches independent row/inner/column permutations of the
seven exact leaves and reports density/shared-factor Pareto recipes.
"""
from __future__ import annotations

import argparse
import itertools
import random
from collections import Counter


def load(path):
    lines = [x for x in open(path) if x.strip()]
    if lines[0].startswith("R "):
        return tuple(sorted(tuple(map(int, x.split()[1:])) for x in lines))
    return tuple(sorted(tuple(map(int, x.split())) for x in lines[1:]))


def remap(mask, rows, cols, fn):
    return sum(1 << fn(*divmod(b, cols)) for b in range(rows * cols) if mask >> b & 1)


def transpose(mask, rows, cols):
    return remap(mask, rows, cols, lambda i, j: j * rows + i)


def permute(terms, dims, pi, pj, pk):
    n, m, p = dims
    return tuple(
        (
            remap(u, n, m, lambda i, j: pi[i] * m + pj[j]),
            remap(v, m, p, lambda j, k: pj[j] * p + pk[k]),
            remap(w, n, p, lambda i, k: pi[i] * p + pk[k]),
        )
        for u, v, w in terms
    )


def orient(group, terms):
    if group == 1:  # 344 --swap--> 443
        return tuple((transpose(v, 4, 4), transpose(u, 3, 4), transpose(w, 3, 4)) for u, v, w in terms)
    if group == 3:  # 344 --swap,rot--> 434
        return tuple((transpose(u, 3, 4), w, v) for u, v, w in terms)
    if group == 4:  # 334 --swap--> 433
        return tuple((transpose(v, 3, 4), transpose(u, 3, 3), transpose(w, 3, 4)) for u, v, w in terms)
    if group == 6:  # 334 --swap,rot,rot--> 343
        return tuple((w, transpose(v, 3, 4), u) for u, v, w in terms)
    return terms


DIMS = [(4, 4, 4), (4, 4, 3), (3, 4, 4), (4, 3, 4), (4, 3, 3), (3, 3, 4), (3, 4, 3)]


def embed_mask(group, axis, mask, rows, cols):
    out = 0
    for b in range(rows * cols):
        if not (mask >> b & 1):
            continue
        i, j = divmod(b, cols)
        points = []
        if group == 0:
            points = [(i, j)] + ([(4 + i, 4 + j)] if i < 3 and j < 3 else [])
        elif group == 1:
            points = [(i, j)] if axis == 0 else [(i, 4 + j)] + ([(4 + i, 4 + j)] if i < 3 else [])
        elif group == 2:
            if axis == 0:
                points = [(4 + i, j)] + ([(4 + i, 4 + j)] if j < 3 else [])
            elif axis == 1:
                points = [(i, j)]
            else:
                points = [(4 + i, j)] + ([(4 + i, 4 + j)] if j < 3 else [])
        elif group == 3:
            if axis == 0:
                points = [(i, 4 + j)] + ([(4 + i, 4 + j)] if i < 3 else [])
            elif axis == 1:
                points = [(4 + i, j)] + ([(4 + i, 4 + j)] if j < 3 else [])
            else:
                points = [(i, j)]
        elif group == 4:
            if axis == 0:
                points = [(i, j), (i, 4 + j)]
            elif axis == 1:
                points = [(4 + i, 4 + j)]
            else:
                points = [(i, j), (i, 4 + j)]
        elif group == 5:
            if axis == 0:
                points = [(4 + i, 4 + j)]
            elif axis == 1:
                points = [(4 + i, j), (i, j)]
            else:
                points = [(i, j), (4 + i, j)]
        else:
            if axis == 0:
                points = [(i, j), (4 + i, j)]
            elif axis == 1:
                points = [(i, j), (i, 4 + j)]
            else:
                points = [(4 + i, 4 + j)]
        for r, c in points:
            out ^= 1 << (r * 7 + c)
    return out


def embed(group, terms):
    n, m, p = DIMS[group]
    return tuple(sorted((embed_mask(group, 0, u, n, m), embed_mask(group, 1, v, m, p), embed_mask(group, 2, w, n, p)) for u, v, w in terms))


def counters(terms):
    return tuple(Counter(t[a] for t in terms) for a in range(3))


def cross(ca, cb):
    return sum(sum(n * cb[a].get(x, 0) for x, n in ca[a].items()) for a in range(3))


def density(terms):
    return sum(sum(x.bit_count() for x in t) for t in terms)


def candidate_iter(group, base):
    n, m, p = DIMS[group]
    seen = set()
    for pi in itertools.permutations(range(n)):
        for pj in itertools.permutations(range(m)):
            for pk in itertools.permutations(range(p)):
                recipe = (pi, pj, pk)
                terms = embed(group, permute(base, DIMS[group], *recipe))
                if terms in seen:
                    continue
                seen.add(terms)
                yield density(terms), counters(terms), recipe, terms


def total_score(groups):
    cs = [counters(x) for x in groups]
    return sum(cross(cs[i], cs[j]) for i in range(7) for j in range(i))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--s444", required=True)
    ap.add_argument("--s334", required=True)
    ap.add_argument("--s344", required=True)
    ap.add_argument("--lambda-density", type=float, default=0.0)
    ap.add_argument("--sweeps", type=int, default=3)
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()
    raw = [load(args.s444)] + [load(args.s344)] * 3 + [load(args.s334)] * 3
    base = [orient(g, raw[g]) for g in range(7)]
    # Start from the canonical d2958 recipe rather than the disconnected
    # all-identity placement; coordinate ascent otherwise settles in a weak
    # local maximum.
    recipes = [
        ((0, 1, 2, 3), (0, 1, 2, 3), (0, 1, 2, 3)),
        ((0, 3, 1, 2), (0, 3, 1, 2), (0, 1, 2)),
        ((0, 1, 2), (0, 3, 1, 2), (0, 3, 1, 2)),
        ((0, 3, 1, 2), (0, 1, 2), (0, 3, 1, 2)),
        ((0, 1, 2, 3), (0, 1, 2), (0, 1, 2)),
        ((0, 1, 2), (0, 1, 2), (0, 1, 2, 3)),
        ((0, 1, 2), (0, 1, 2, 3), (0, 1, 2)),
    ]
    groups = [embed(g, permute(base[g], DIMS[g], *recipes[g])) for g in range(7)]
    rng = random.Random(args.seed)
    for sweep in range(args.sweeps):
        order = list(range(7))
        rng.shuffle(order)
        for g in order:
            other = [Counter() for _ in range(3)]
            for h in range(7):
                if h == g:
                    continue
                for axis, c in enumerate(counters(groups[h])):
                    other[axis].update(c)
            best = None
            for den, cs, recipe, terms in candidate_iter(g, base[g]):
                shared = cross(cs, other)
                key = (shared - args.lambda_density * den, shared, -den)
                if best is None or key > best[0]:
                    best = (key, recipe, terms)
            recipes[g] = best[1]
            groups[g] = best[2]
        print("sweep", sweep, "density", sum(map(density, groups)), "pairs", total_score(groups), "recipes", recipes, flush=True)


if __name__ == "__main__":
    main()
