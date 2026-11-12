#!/usr/bin/env python3
"""Regenerates spec/fixtures/gf2_mmc_alg/ from the ORIGINAL algebra (tools/mmc_gf2_alg.py, the oracle).

  generate.py

writes, next to this file:

  schemes.tsv   named input schemes: `name TAB n m p TAB u v w (hexadecimal) ; u v w ; ...`
  cases.json    per case: the operation, its inputs and parameters, and what the original returns: `out` is a list of
                results, each a scheme as `NxMxP rR sha256` of its terms in the original's order, a `perm` text before a
                scheme where the operation returns pairs, `none`, or an `error` with the original's ValueError message
Everything here is derived from the Python original, never from the Tungsten port.
"""
import hashlib
import itertools
import json
import os
import random
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
BIT = HERE.parents[2]
REPO = BIT.parents[1]
sys.path[:0] = [str(BIT / 'tools'), str(BIT / 'spec')]
os.environ.setdefault('PYTHONDONTWRITEBYTECODE', '1')
import mmc_gf2_alg as G  # noqa: E402
import gf2_record_board as grb  # noqa: E402


def m(*idx):
    return sum(1 << i for i in idx)


STRASSEN = G.Alg(2, 2, 2, [
    (m(0, 3), m(0, 3), m(0, 3)), (m(2, 3), m(0), m(2, 3)), (m(0), m(1, 3), m(1, 3)),
    (m(3), m(0, 2), m(0, 2)), (m(0, 1), m(3), m(0, 1)), (m(0, 2), m(0, 1), m(3)),
    (m(1, 3), m(2, 3), m(0)),
])
assert G.check_exact(STRASSEN)
SEED_FILE = BIT / 'lib/metaflip/seeds/gf2/matmul_3x3x4_rank29_d249_peterson_2026_aws_disjoint_gf2.txt'
seed_shape, seed_terms = grb.decode(SEED_FILE, grb.load(SEED_FILE))

SCHEMES = {
    'naive_2x3x4': G.naive(2, 3, 4), 'naive_3x2x5': G.naive(3, 2, 5), 'naive_1x4x2': G.naive(1, 4, 2),
    'naive_3x3x3': G.naive(3, 3, 3), 'naive_2x2x2': G.naive(2, 2, 2), 'naive_2x3x2': G.naive(2, 3, 2),
    'naive_2x1x3': G.naive(2, 1, 3), 'naive_4x3x2': G.naive(4, 3, 2), 'naive_2x3x5': G.naive(2, 3, 5),
    'naive_2x4x2': G.naive(2, 4, 2), 'naive_3x2x2': G.naive(3, 2, 2), 'naive_2x5x2': G.naive(2, 5, 2),
    'strassen': STRASSEN,
    'strassen_kron_strassen': G.kron(STRASSEN, STRASSEN),
    'strassen_kron_naive_112': G.kron(STRASSEN, G.naive(1, 1, 2)),
    'naive_212_kron_strassen': G.kron(G.naive(2, 1, 2), STRASSEN),
    'seed_3x3x4': G.Alg(*seed_shape, sorted(tuple(t) for t in seed_terms)),
    'strassen_t_c': G.transpose(G.cyclic_shift(G.kron(STRASSEN, G.naive(1, 2, 3)))),
    # terms with a zero factor and repeated terms, for `clean`
    'dirty': G.Alg(2, 2, 2, [(0, 1, 1), (1, 1, 1), (3, 3, 3), (1, 1, 1), (2, 2, 2), (3, 3, 3), (3, 3, 3)]),
}


def digest(a):
    text = ''.join('%x %x %x\n' % t for t in a.terms)
    return f'{a.n}x{a.m}x{a.p} r{a.r} {hashlib.sha256(text.encode()).hexdigest()}'


def lookup_strassen(size):
    if 1 in size:
        return G.naive(*size)
    if tuple(size) == (2, 2, 2):
        return STRASSEN
    return G.naive(*size)


def rank_strassen(size):
    return 7 if tuple(size) == (2, 2, 2) else size[0] * size[1] * size[2]


def lookup_none_big(size):
    return None if max(size) > 4 else G.naive(*size)


def rank_none_big(size):
    return None if max(size) > 4 else size[0] * size[1] * size[2]


CASES = []


def case(**spec):
    out = []
    try:
        result = RUN[spec['op']](spec)
        out = result
    except ValueError as exc:
        out = {'error': str(exc)}
    CASES.append(dict(spec, out=out))


def scheme_result(a):
    return ['none'] if a is None else [digest(a)]


RUN = {
    'orient': lambda s: scheme_result(G.apply_orientation(SCHEMES[s['a']], s['code'])),
    'orient_by_perm': lambda s: scheme_result(G.orient_by_perm(SCHEMES[s['a']], s['perm'])),
    'orient_as': lambda s: scheme_result(G.orient_as(SCHEMES[s['a']], s['shape'])),
    'permute_axes': lambda s: scheme_result(G.permute_axes(SCHEMES[s['a']], s['perm'])),
    's3_orbit': lambda s: [x for alg, perm in G.s3_orbit_with_perms(SCHEMES[s['a']]) for x in (perm, digest(alg))],
    'orientations': lambda s: [digest(o) for o in G.orientations(SCHEMES[s['a']])],
    'axis_permute': lambda s: scheme_result(G.axis_permute(SCHEMES[s['a']], s['pA'], s['pB'], s['pC'])),
    'kron': lambda s: scheme_result(G.kron(SCHEMES[s['a']], SCHEMES[s['b']])),
    'concat_cols': lambda s: scheme_result(G.concat_cols(SCHEMES[s['a']], SCHEMES[s['b']])),
    'concat_rows': lambda s: scheme_result(G.concat_rows(SCHEMES[s['a']], SCHEMES[s['b']])),
    'concat_inner': lambda s: scheme_result(G.concat_inner_r(SCHEMES[s['a']], SCHEMES[s['b']])),
    'concat_right': lambda s: scheme_result(G.concat_right(SCHEMES[s['a']], SCHEMES[s['b']])),
    'project': lambda s: scheme_result(G.project(SCHEMES[s['a']], s['keepN'], s['keepM'], s['keepP'])),
    'recombination': lambda s: scheme_result(G.recombination(SCHEMES[s['a']], s['allocA'], s['allocB'], s['allocC'],
                                                              lookup_strassen if s['lookup'] == 'strassen' else lookup_none_big)),
    'buds': lambda s: [f'{typ}:{",".join(map(str, g))}' for typ, g in G.find_buds(SCHEMES[s['a']], tuple(s['order']))[0]] +
                      ['trivial:' + ','.join(map(str, G.find_buds(SCHEMES[s['a']], tuple(s['order']))[1]))],
    'serendipitous': lambda s: scheme_result(G.serendipitous(
        SCHEMES[s['a']], s['n2'], s['m2'], s['p2'],
        lookup_strassen if s['res'] == 'strassen' else lookup_none_big,
        rank_strassen if s['res'] == 'strassen' else rank_none_big)),
    'clean': lambda s: scheme_result(G.clean(SCHEMES[s['a']])),
}

names = list(SCHEMES)
# orientations of every kind of input
for name in names:
    for code in range(6):
        case(op='orient', a=name, code=code)
    case(op='s3_orbit', a=name)
    case(op='orientations', a=name)
    for shape in ((2, 3, 4), (4, 3, 2), (3, 3, 4), (4, 3, 3), (3, 4, 3), (2, 2, 2), (5, 3, 2)):
        case(op='orient_as', a=name, shape=list(shape))
    for perm in ('ABC->ABC', 'ABC->CBA', 'ABC->BCA', 'ABC->CAB', 'ABC->ACB', 'ABC->BAC', 'NMP->PMN', 'ABC->AAB', 'ABC>BCA', 'ABC->BC'):
        case(op='permute_axes', a=name, perm=perm)
for perm in itertools.permutations(range(3)):
    case(op='orient_by_perm', a='naive_2x3x4', perm=list(perm))
case(op='orient_by_perm', a='seed_3x3x4', perm=[2, 1, 0])
rng = random.Random(1)
for name in ('naive_2x3x4', 'naive_3x2x5', 'strassen', 'seed_3x3x4', 'naive_1x4x2'):
    a = SCHEMES[name]
    for _ in range(2):
        pA, pB, pC = list(range(a.n)), list(range(a.m)), list(range(a.p))
        rng.shuffle(pA), rng.shuffle(pB), rng.shuffle(pC)
        case(op='axis_permute', a=name, pA=pA, pB=pB, pC=pC)
# Kronecker products
for a, b in (('strassen', 'strassen'), ('naive_2x3x2', 'strassen'), ('strassen', 'naive_2x3x2'), ('naive_2x1x3', 'strassen'),
             ('strassen_t_c', 'strassen'), ('seed_3x3x4', 'naive_2x2x2'), ('naive_1x4x2', 'naive_3x2x2'), ('seed_3x3x4', 'strassen')):
    case(op='kron', a=a, b=b)
# concatenation, direct and robust (another orientation), and impossible
pairs = [('naive_2x3x2', 'naive_2x3x5'), ('strassen', 'naive_2x2x2'), ('naive_3x2x2', 'naive_2x2x2'), ('naive_2x3x2', 'naive_4x3x2'),
         ('strassen', 'naive_3x2x2'), ('naive_2x3x2', 'naive_2x4x2'), ('strassen', 'naive_2x5x2'), ('naive_2x3x4', 'naive_3x2x5'),
         ('seed_3x3x4', 'naive_3x3x3'), ('naive_2x3x4', 'naive_2x3x5'), ('naive_2x3x4', 'seed_3x3x4'), ('naive_1x4x2', 'naive_3x2x2'),
         ('strassen_kron_strassen', 'naive_2x3x2')]
for a, b in pairs:
    for kind in ('concat_cols', 'concat_rows', 'concat_inner'):
        case(op=kind, a=a, b=b)
    case(op='concat_right', a=a, b=b)
# projections
k = {
    'strassen_kron_strassen': [([0, 1, 3], [0, 2, 3], [1, 2]), ([0, 1, 2, 3], [0, 1, 2, 3], [0, 1, 2, 3]), ([3], [0, 1], [2, 3]),
                               ([0, 2], [1, 3], [0, 3])],
    'seed_3x3x4': [([0, 1], [0, 1, 2], [0, 1, 2, 3]), ([2, 0], [1, 2], [3, 1, 0]), ([0], [0], [0])],
    'naive_2x3x4': [([1], [0, 2], [1, 2, 3])],
}
for name, lists in k.items():
    for keepN, keepM, keepP in lists:
        case(op='project', a=name, keepN=keepN, keepM=keepM, keepP=keepP)
# recombination
for base, allocs in (('strassen', [([3, 2], [2, 3], [4, 1]), ([1, 1], [2, 2], [3, 3]), ([2, 2], [2, 2], [2, 2]), ([5, 1], [1, 1], [2, 2])]),
                     ('naive_2x1x3', [([2, 3], [4], [1, 2, 2])]),
                     ('naive_2x2x2', [([2, 2], [1, 3], [2, 1])]),
                     ('seed_3x3x4', [([2, 1, 1], [1, 2, 1], [1, 1, 1, 1])]),
                     ('strassen', [([6, 1], [2, 2], [2, 2])])):
    for alloc in allocs:
        for lookup in ('strassen', 'none_big'):
            case(op='recombination', a=base, allocA=alloc[0], allocB=alloc[1], allocC=alloc[2], lookup=lookup)
case(op='recombination', a='strassen', allocA=[1], allocB=[2, 2], allocC=[2, 2], lookup='strassen')
# bud decomposition and the serendipitous product
for name in ('naive_2x2x2', 'naive_2x3x2', 'strassen', 'strassen_kron_naive_112', 'naive_212_kron_strassen', 'seed_3x3x4', 'strassen_t_c'):
    for order in G.ORDERINGS:
        case(op='buds', a=name, order=list(order))
    for n2, m2, p2 in ((2, 2, 2), (1, 2, 1), (2, 1, 3), (3, 1, 1), (1, 1, 2)):
        for res in ('strassen', 'none_big'):
            case(op='serendipitous', a=name, n2=n2, m2=m2, p2=p2, res=res)
case(op='serendipitous', a='naive_2x2x2', n2=5, m2=5, p2=5, res='none_big')
# cleanup
case(op='clean', a='dirty')
case(op='clean', a='strassen')

HERE.joinpath('schemes.tsv').write_text('\n'.join(
    f'{name}\t{a.n} {a.m} {a.p}\t' + ' ; '.join('%x %x %x' % t for t in a.terms) for name, a in SCHEMES.items()) + '\n')
HERE.joinpath('cases.json').write_text(json.dumps(CASES, indent=0, separators=(',', ':')) + '\n')
print(len(CASES), 'cases;', sum(1 for c in CASES if isinstance(c['out'], dict)), 'errors;',
      sum(1 for c in CASES if c['out'] == ['none']), 'none')
