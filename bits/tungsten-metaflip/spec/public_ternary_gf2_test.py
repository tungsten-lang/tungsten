#!/usr/bin/env python3
"""Public integer-scheme reduction to exact GF(2) seeds; no record claim."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'bits/tungsten-metaflip/tools'))
from screen_public_ternary_gf2 import SCHEME, integer_files, parity, reduce_mod2  # noqa: E402
import subprocess  # noqa: E402
import tempfile  # noqa: E402


def scheme(shape, products):
    """products: [(A{(i,j):c}, B{(j,k):c}, C{(i,k):c})] in the public layout."""
    n, m, p = shape
    u = [[a.get((i, j), 0) for i in range(n) for j in range(m)] for a, _, _ in products]
    v = [[b.get((j, k), 0) for j in range(m) for k in range(p)] for _, b, _ in products]
    # The public W row is indexed C[k][i].
    w = [[c.get((i, k), 0) for k in range(p) for i in range(n)] for _, _, c in products]
    return dict(n=list(shape), m=len(products), z2=False, u=u, v=v, w=w)


def strassen():
    a11, a12, a21, a22 = (0, 0), (0, 1), (1, 0), (1, 1)
    return scheme((2, 2, 2), [
        ({a11: 1, a22: 1}, {a11: 1, a22: 1}, {a11: 1, a22: 1}),
        ({a21: 1, a22: 1}, {a11: 1}, {a21: 1, a22: -1}),
        ({a11: 1}, {a12: 1, a22: -1}, {a12: 1, a22: 1}),
        ({a22: 1}, {a21: 1, a11: -1}, {a11: 1, a21: 1}),
        ({a11: 1, a12: 1}, {a22: 1}, {a11: -1, a12: 1}),
        ({a21: 1, a11: -1}, {a11: 1, a12: 1}, {a22: 1}),
        ({a12: 1, a22: -1}, {a21: 1, a22: 1}, {a11: 1}),
    ])


def naive_with_cancelling_pair(shape):
    n, m, p = shape
    products = [({(i, j): 1}, {(j, k): 1}, {(i, k): 1})
                for i in range(n) for j in range(m) for k in range(p)]
    extra = ({(0, 0): 1, (1, 2): -1}, {(2, 3): 1}, {(1, 3): 1})
    # +X and -X cancel over Z; over GF(2) they are equal terms and cancel too.
    products += [extra, ({key: -value for key, value in extra[0].items()}, extra[1], extra[2])]
    return scheme(shape, products)


shape, rank, terms = reduce_mod2(strassen())
assert (shape, rank, len(terms)) == ((2, 2, 2), 7, 7)

shape, rank, terms = reduce_mod2(naive_with_cancelling_pair((2, 3, 4)))
assert (shape, rank, len(terms)) == ((2, 3, 4), 26, 24), (shape, rank, len(terms))

# A transposed W layout must fail the exact gate on a non-square shape.
broken = naive_with_cancelling_pair((2, 3, 4))
broken['w'] = [[row[(i % 2) * 4 + i // 2] for i in range(8)] for row in broken['w']]
try:
    reduce_mod2(broken)
except AssertionError:
    pass
else:
    raise AssertionError('transposed W accepted')

assert parity('1/3') == 1 and parity('-2/3') == 0 and parity(-1) == 1
for bad in ('1/2', '3/4', 0.5):
    try:
        parity(bad)
    except ValueError:
        continue
    raise AssertionError(f'accepted non-GF(2) coefficient {bad!r}')

halved = strassen()
halved['u'][0][0] = '1/2'
try:
    reduce_mod2(halved)
except ValueError:
    pass
else:
    raise AssertionError('even denominator accepted')

assert SCHEME.search('schemes/results/ZT/10x13x14_m1152_ZT.json').group(5) == 'ZT'
assert SCHEME.search('schemes/results/serendipitous_base/6x7x13_m372_1398b6_Q.json').group(5) == 'Q'
assert SCHEME.search('schemes/results/Z/9x10x14_m820_Z.json').group(4) == '820'
# The seed window is anchored on the best integer rank, not a lower _Q file.
with tempfile.TemporaryDirectory() as repo:
    names = ['schemes/results/Q/9x10x14_m808_Q.json', 'schemes/results/Z/9x10x14_m820_Z.json',
             'schemes/results/ZT/9x10x14_m821_ZT.json', 'schemes/results/ZT/9x10x14_m823_ZT.json',
             'schemes/results/Q/7x7x7_m249_Q.json', 'schemes/known/tensor/9x10x14_m800_Z.json']
    for name in names:
        Path(repo, name).parent.mkdir(parents=True, exist_ok=True)
        Path(repo, name).write_text('{}')
    git = ['git', '-C', repo, '-c', 'user.name=t', '-c', 'user.email=t@t']
    subprocess.run(git[:3] + ['init', '-q'], check=True)
    subprocess.run(git + ['add', '-f', '.'], check=True)
    subprocess.run(git + ['commit', '-qm', 'fixture'], check=True)
    assert integer_files(repo, 'HEAD') == {(9, 10, 14): [(820, names[1])]}
    assert integer_files(repo, 'HEAD', 1)[(9, 10, 14)] == [(820, names[1]), (821, names[2])]
    both = integer_files(repo, 'HEAD', 0, rational=True)
    assert both[(9, 10, 14)] == [(808, names[0]), (820, names[1])]
    assert both[(7, 7, 7)] == [(249, names[4])]  # rational-only shape: parity gate decides
print('PASS public ternary GF(2) reduction: layout, cancellation, ring gates, seed window')
