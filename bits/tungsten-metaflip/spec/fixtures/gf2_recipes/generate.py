#!/usr/bin/env python3
"""Regenerates spec/fixtures/gf2_recipes/ from the ORIGINAL replay (tools/wide_composition_recipes.py, the oracle).

  generate.py

writes, next to this file:

  in/recipes.json      named recipes: every kind (seed from a repository file, seed from a caller state, naive, split, product,
                       projection), an orientation different from the canonical one, and mutated copies that must be rejected
  in/state_<name>.txt  the schemes behind the `state` seeds (copies of seed files of lib/metaflip/seeds/gf2)
  expected/cases.tsv   per recipe: `ok`, the rank and the SHA-256 of the result's terms as `u v w` hexadecimal lines in the order
                       the original returns them; or `error` and the message the original raises

Everything here is derived from the Python original, never from the Tungsten port.
"""
import copy
import hashlib
import json
import os
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
BIT = HERE.parents[2]
REPO = BIT.parents[1]
sys.path[:0] = [str(BIT / 'tools'), str(REPO / 'benchmarks/matmul/metaflip')]
os.environ.setdefault('PYTHONDONTWRITEBYTECODE', '1')
import screen_top_two_projection_children as top  # noqa: E402
import wide_composition_recipes as wcr  # noqa: E402

SEEDS = 'bits/tungsten-metaflip/lib/metaflip/seeds/gf2/'
STRASSEN = SEEDS + 'matmul_2x2_rank7_strassen_gf2.txt'
S234 = SEEDS + 'matmul_2x3x4_rank20_d130_global_isotropy_gf2.txt'
S225 = SEEDS + 'matmul_2x2x5_rank18_d84_gf2.txt'


def sha(path):
    return hashlib.sha256((REPO / path).read_bytes()).hexdigest()


def seed(path, shape, rank, target=None):
    return dict(kind='seed', rank=rank, shape=list(target or shape), source_shape=list(shape), source=path, source_sha256=sha(path))


def read_terms(path):
    return [tuple(map(int, l.split()[-3:])) for l in (REPO / path).read_text().splitlines()
            if l.strip() and not l.startswith('#') and not l.strip().isdigit()]


def lines(terms):
    return ''.join(f'{u:x} {v:x} {w:x}\n' for u, v, w in terms)


shutil.rmtree(HERE / 'in', ignore_errors=True)
shutil.rmtree(HERE / 'expected', ignore_errors=True)
(HERE / 'in').mkdir()
(HERE / 'expected').mkdir()
states = {}
for name, path, shape in (('s1', STRASSEN, (2, 2, 2)), ('s2', S225, (2, 2, 5))):
    shutil.copy(REPO / path, HERE / 'in' / f'state_{name}.txt')
    states[name] = (shape, sorted(read_terms(path)))

a = seed(STRASSEN, (2, 2, 2), 7)
b = seed(S234, (2, 3, 4), 20)
recipes = {
    'seed-file': a,
    'seed-file-oriented': seed(S234, (2, 3, 4), 20, target=(4, 2, 3)),
    'seed-state': dict(kind='seed', rank=7, shape=[2, 2, 2], source_shape=[2, 2, 2], state='s1'),
    'seed-state-oriented': dict(kind='seed', rank=18, shape=[5, 2, 2], source_shape=[2, 2, 5], state='s2'),
    'naive': dict(kind='naive', rank=18, shape=[3, 3, 2]),
    'split-axis2': dict(kind='split', rank=14, axis=2, shape=[2, 2, 4], left=copy.deepcopy(a), right=copy.deepcopy(a)),
    'split-oriented': dict(kind='split', rank=14, axis=2, shape=[4, 2, 2], left=copy.deepcopy(a), right=copy.deepcopy(a)),
    'split-mixed': dict(kind='split', rank=32, axis=2, shape=[2, 3, 6], left=copy.deepcopy(b), right=dict(kind='naive', rank=12, shape=[2, 3, 2])),
    'product': dict(kind='product', rank=49, shape=[4, 4, 4], left=copy.deepcopy(a), right=copy.deepcopy(a)),
    'product-mixed': dict(kind='product', rank=140, shape=[4, 6, 8], left=copy.deepcopy(a), right=copy.deepcopy(b)),
    'projection': dict(kind='projection', rank=0, shape=[2, 3, 3], parent=copy.deepcopy(b), deletions=[dict(axis=2, coordinate=1)]),
    'projection-two': dict(kind='projection', rank=0, shape=[2, 2, 3], parent=copy.deepcopy(b), deletions=[dict(axis=2, coordinate=0), dict(axis=1, coordinate=2)]),
    'nested': dict(kind='split', rank=81, axis=2, shape=[6, 4, 4], left=dict(kind='product', rank=49, shape=[4, 4, 4], left=copy.deepcopy(a), right=copy.deepcopy(a)),
                   right=dict(kind='split', rank=32, axis=0, shape=[4, 4, 2], left=dict(kind='naive', rank=16, shape=[1, 4, 4]), right=dict(kind='naive', rank=16, shape=[1, 4, 4]))),
}
# projection ranks depend on the result: fix them from the original, so that a correct replay reports them
for name in ('projection', 'projection-two'):
    recipes[name]['rank'] = len(top.project(tuple(b['source_shape']), sorted(read_terms(S234)), *[recipes[name]['deletions'][0][k] for k in ('axis', 'coordinate')])[1]) \
        if name == 'projection' else recipes[name]['rank']
mutated = {}
bad = copy.deepcopy(recipes['split-axis2']); bad['rank'] = 15; mutated['bad-rank'] = bad
bad = copy.deepcopy(recipes['split-axis2']); bad['shape'] = [2, 2, 5]; mutated['bad-cut'] = bad
bad = copy.deepcopy(recipes['seed-state']); bad['state'] = 'nope'; mutated['missing-state'] = bad
bad = copy.deepcopy(recipes['seed-file']); bad['source_sha256'] = '0' * 64; mutated['hash-mismatch'] = bad
bad = copy.deepcopy(recipes['seed-file']); bad['source'] = '../escape.txt'; mutated['unsafe-source'] = bad
bad = copy.deepcopy(recipes['seed-file']); bad['source_shape'] = [2, 2, 3]; mutated['leaf-metadata'] = bad
bad = copy.deepcopy(recipes['product']); bad['rank'] = 48; mutated['product-rank'] = bad
bad = copy.deepcopy(recipes['naive']); bad['rank'] = 17; mutated['naive-rank'] = bad
bad = copy.deepcopy(recipes['split-axis2']); bad['kind'] = 'merge'; mutated['unknown-kind'] = bad
bad = copy.deepcopy(recipes['split-axis2']); bad['shape'] = [2, 2, 40]; bad['rank'] = 14; mutated['shape-range'] = bad
bad = copy.deepcopy(recipes['projection']); bad['parent']['shape'] = [1, 1, 1]; mutated['projection-growth'] = bad
recipes.update(mutated)

# make the projection recipes self-consistent with the original's answer
for name in ('projection', 'projection-two'):
    recipe = recipes[name]
    shape, terms = tuple(recipe['parent']['source_shape']), sorted(read_terms(S234))
    for step in recipe['deletions']:
        shape, terms = top.project(shape, terms, step['axis'], step['coordinate'])
    recipe['rank'] = len(terms)
for name in ('projection-growth',):
    recipes[name]['rank'] = recipes['projection']['rank']
(HERE / 'in' / 'recipes.json').write_text(json.dumps(recipes, indent=1) + '\n')

wcr.verify_file = lambda path: (lambda raw: (*top.read_blob(raw), hashlib.sha256(raw).hexdigest()))(Path(path).read_bytes())
rows = []
for name, recipe in recipes.items():
    try:
        terms = wcr.replay_recipe(recipe, REPO, dict(states), {})
        rows.append(f'{name}\tok\t{len(terms)}\t{hashlib.sha256(lines(terms).encode()).hexdigest()}')
    except (ValueError, AssertionError, KeyError, TypeError) as error:
        rows.append(f'{name}\terror\t{error}')
(HERE / 'expected' / 'cases.tsv').write_text('\n'.join(rows) + '\n')
print('\n'.join(rows))
