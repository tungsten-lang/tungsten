"""Composition primitives of the matmulcatalog GF(2) replay against the full tensor identity."""
from pathlib import Path
import random
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from mmc_gf2_alg import *  # noqa: E402,F401,F403

# Strassen in MFW1 layout (2x2x2): A=[a0 a1; a2 a3] etc
def M(*idx):
    return sum(1 << i for i in idx)
strassen = Alg(2, 2, 2, [
    (M(0, 3), M(0, 3), M(0, 3)),
    (M(2, 3), M(0), M(2, 3)),
    (M(0), M(1, 3), M(1, 3)),
    (M(3), M(2, 0), M(0, 2)),
    (M(0, 1), M(3), M(0, 1)),
    (M(2, 0), M(0, 1), M(3)),
    (M(1, 3), M(2, 3), M(0)),
])
assert check_exact(strassen), "strassen"
rng = random.Random(1)
shapes = [(2, 3, 4), (3, 2, 5), (1, 4, 2), (3, 3, 3)]
for s in shapes:
    a = naive(*s)
    assert check_exact(a)
    assert check_exact(cyclic_shift(a)) and check_exact(transpose(a))
    for code in range(6):
        assert check_exact(apply_orientation(a, code))
    for perm in ("ABC->CBA", "ABC->BCA", "ABC->CAB", "ABC->ACB", "ABC->BAC"):
        assert check_exact(permute_axes(a, perm))
    pA = list(range(s[0])); rng.shuffle(pA)
    pB = list(range(s[1])); rng.shuffle(pB)
    pC = list(range(s[2])); rng.shuffle(pC)
    assert check_exact(axis_permute(a, pA, pB, pC))
# orientation consistency with the shape conventions of orientByPerm
a = naive(2, 3, 4)
for code, perm in enumerate(ORIENT_PERMS):
    o = apply_orientation(a, code)
    assert o.shape == tuple(a.shape[i] for i in perm), (code, o.shape)
s2 = kron(strassen, strassen)
assert s2.shape == (4, 4, 4) and s2.r == 49 and check_exact(s2)
k = kron(naive(2, 3, 1), strassen)
assert check_exact(k)
k = kron(transpose(cyclic_shift(kron(strassen, naive(1, 2, 3)))), strassen)
assert check_exact(k), "kron2"
# concat
assert check_exact(concat_cols(naive(2, 3, 2), strassen if False else naive(2, 3, 5)))
assert check_exact(concat_rows(naive(2, 3, 2), naive(4, 3, 2)))
assert check_exact(concat_inner_r(naive(2, 3, 2), naive(2, 4, 2)))
assert check_exact(concat_cols(strassen, naive(2, 2, 3)))
assert check_exact(concat_inner_r(strassen, naive(2, 5, 2)))
assert check_exact(concat_rows(strassen, naive(3, 2, 2)))
assert check_exact(concat_cols(naive(3, 2, 2), naive(2, 2, 2)))  # robust
# project
p = project(s2, [0, 1, 3], [0, 2, 3], [1, 2])
assert p.shape == (3, 3, 2) and check_exact(p), "project"
# recombination with strassen base
def lookup(sz):
    if 1 in sz:
        return naive(*sz)
    if sz == (2, 2, 2):
        return strassen
    return naive(*sz)
for alloc in [([3, 2], [2, 3], [4, 1]), ([1, 1], [2, 2], [3, 3]), ([2, 2], [2, 2], [2, 2])]:
    rec = recombination(strassen, *alloc, lookup)
    assert check_exact(rec), ("recomb", alloc)
rec = recombination(naive(2, 1, 3), [2, 3], [4], [1, 2, 2], lookup)
assert check_exact(rec), "recomb naive base"
# serendipitous
def res(sz):
    if sz == (2, 2, 2):
        return strassen
    return naive(*sz)
def rk(sz):
    return 7 if sz == (2, 2, 2) else sz[0] * sz[1] * sz[2]
for base in (naive(2, 2, 2), naive(2, 3, 2), transpose(naive(1, 2, 3)), strassen, kron(strassen, naive(1, 1, 2))):
    for n2, m2, p2 in ((2, 2, 2), (1, 2, 1), (2, 1, 3)):
        sp = serendipitous(base, n2, m2, p2, res, rk)
        assert check_exact(sp), ("seren", base, n2, m2, p2)
        # force each ordering's bud build
        for order in ORDERINGS:
            buds, triv = find_buds(base, order)
            terms = []
            s2_ = res((n2, m2, p2))
            for i in triv:
                terms += kron(Alg(*base.shape, [base.terms[i]]), s2_).terms
            for typ, g in buds:
                terms += build_bud_block(base, typ, g, res(enlarged_shape(typ, len(g), n2, m2, p2)), n2, m2, p2)
            b = Alg(base.n * n2, base.m * m2, base.p * p2, terms)
            assert check_exact(b), ("bud", order, base, n2, m2, p2)
for base in (naive(2, 2, 2), naive(2, 3, 2), strassen, kron(strassen, naive(1, 1, 2)), kron(naive(2,1,2), strassen)):
    for n2, m2, p2 in ((2, 2, 2), (1, 2, 1), (2, 1, 3)):
        sp, cost = serendipitous_opt(base, n2, m2, p2, res, rk)
        assert check_exact(sp) and sp.r == cost, ("seren_opt", base, n2, m2, p2, sp.r, cost)
print("PASS mmc_gf2_alg: orientations, Kronecker, concatenation, projection, recombination, serendipitous")
