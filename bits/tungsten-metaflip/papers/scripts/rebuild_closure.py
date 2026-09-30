#!/usr/bin/env python3
"""Rebuild every closure row (kind `closure`) of the release bundles A and B from its recipe, the archived leaves and the
repository's seed files, and compare the result byte for byte with the row's SHA-256.

usage: rebuild_closure.py RELEASE_DIR      (RELEASE_DIR = the work directory's release-0929/)

The verifier of the release (verify_gf2_lineage.py) only checks the rank arithmetic of closure rows; this script is the separate
check cited in the methods paper.  Leaves that no longer exist on disk (the `unrecovered` list of the leaves index) make their
recipes fail with "missing composition state"; every other recipe must rebuild identically.
"""
import base64, gzip, hashlib, json, sys, time
from pathlib import Path

sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parents[4]
sys.path[:0] = [str(REPO / 'bits/tungsten-metaflip/tools'), str(REPO / 'benchmarks/matmul/metaflip')]
import screen_top_two_projection_children as top   # noqa: E402
import wide_composition_recipes as wcr             # noqa: E402

R = Path(sys.argv[1])
NAMES = {'A': 'gf2-searched-records', 'B': 'gf2-closure-products', 'C': 'gf2-block47-certificates-2026-07',
         'D': 'gf2-public-ternary-walks-2026-09-26'}
M = {k: json.loads((R / n / 'manifest.json').read_text()) for k, n in NAMES.items()}


def dec(path):
    return gzip.decompress(base64.b64decode(Path(path).read_bytes().replace(b'\n', b''), validate=True))


file_of = {}
for k, n in NAMES.items():
    for r in M[k]['rows']:
        file_of.setdefault(r['sha256'], R / n / r['file'])
idx = json.loads((R / 'gf2-closure-products/leaves/index.json').read_text())
for leaf in idx['leaves']:
    file_of.setdefault(leaf['state'], R / 'gf2-closure-products/leaves' / leaf['file'])
unrecovered = {u['state'] for u in idx['unrecovered']}
closure = [(k, r) for k in 'AB' for r in M[k]['rows'] if r['kind'] == 'closure']
print('closure rows', len(closure))
need = set()
for k, r in closure:
    need |= wcr.recipe_dependencies(r['details']['recipe'])
states, missing = {}, []
for s in need:
    if s in file_of:
        raw = dec(file_of[s])
        shape, terms = top.read_blob(raw)
        assert hashlib.sha256(raw).hexdigest() == s
        states[s] = (shape, terms)
    else:
        missing.append(s)
print('state leaves needed', len(need), 'loaded', len(states), 'not on disk', len(missing), '== unrecovered set:', set(missing) == unrecovered)


def fast_verify(path):                 # leaf exactness is checked when the leaf is read; skip the per-leaf Ruby call
    raw = Path(path).read_bytes()
    shape, terms = top.read_blob(raw)
    return shape, terms, hashlib.sha256(raw).hexdigest()


wcr.verify_file = fast_verify
leaves, res, t0 = {}, {'ok': 0, 'fail': [], 'mismatch': []}, time.time()
for k, r in sorted(closure, key=lambda x: x[1]['rank']):
    shape = tuple(map(int, r['shape'].split('x')))
    try:
        terms = wcr.replay_recipe(r['details']['recipe'], wcr.ROOT, states, leaves)
    except Exception as e:             # noqa: BLE001
        res['fail'].append((k, r['shape'], r['rank'], str(e)[:60]))
        continue
    if hashlib.sha256(top.blob(shape, terms)).hexdigest() == r['sha256']:
        res['ok'] += 1
    else:
        res['mismatch'].append((k, r['shape'], r['rank']))
print('rebuilt byte-identical:', res['ok'], 'of', len(closure), ' failures:', len(res['fail']), ' mismatches:', len(res['mismatch']),
      'elapsed %.0fs' % (time.time() - t0))
print('failure reasons:', {x[3] for x in res['fail']})
print('failing rows:', [(x[0], x[1], x[2]) for x in res['fail']])
print('mismatching rows:', res['mismatch'])
sys.exit(1 if res['mismatch'] else 0)
