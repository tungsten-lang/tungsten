#!/usr/bin/env python3
"""Explicit sweep: for every one of the 795 record shapes, the smallest rank reachable from PUBLISHED
explicit GF(2)-valid scheme files by direct sums, Kronecker products and Strassen's algorithm on unequal
2x2x2 block splits; every composition at or below our rank is built term by term and checked exactly
against the matrix multiplication tensor over GF(2).

Scheme files (all public, all read from the fresh clones / tarball trees under W/upstream-latest):
  * FastMatrixMultiplication at ac13ca8855 (integer JSON files, incl. schemes/known; SLP files skipped)
  * matmulcatalog at 5a306526 (explicit files with F2 among their fields; the 'derived/' stubs are skipped)
  * the Kauers-Wood repository github.com/mkauers/matrix-multiplication at 12c26b29 (arXiv:2510.19787's
    data link; .exp and the Z2-only .mod2.exp files) and the FMM copies under schemes/known/meta_flip_graph
  * Arai-Ichikawa-Hukushima github.com/Yamato-Arai/adap at fe7b2040 (arXiv:2312.16960: <4,5,5>:73 and
    <5,5,5>:94, characteristic 2)
  * Medley et al. arXiv:2609.17533, Appendix A (<7,7,7>:245 over F2, decoded from the paper text)
Rank claims without factor matrices (Perminov's Z2 table, catalogue cited bounds) are NOT used here.
Run: python3 08-composition-verify.py [--all]   (--all also builds and verifies the compositions EQUAL to ours)
"""
import csv
import importlib.util
import json
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
W = Path('/Users/erik/.tungsten/metaflip/experiments/record-hunt-20260926/work')
RECORDS = W / 'release-0929/gf2-campaign-records/records.tsv'
spec = importlib.util.spec_from_file_location('sc', HERE / '08-serendipitous-check.py')
sc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sc)


def file_ok(path):
    s = sc.load_medley() if path.startswith('medley:') else sc.load_any(path)
    return s is not None and s.verify()


def build_verified(lib, key, tries=4):
    """Build the cheapest recipe for `key` and verify it; a failing file component is dropped and the
    recipe recomputed."""
    for _ in range(tries):
        s = lib.get(key)
        if s.verify():
            return s, True
        bad = [path for k, path in lib.leaves(key) if not file_ok(path)]
        if not bad:
            return s, False
        for path in bad:
            lib.drop(path)
    return None, False


def main():
    build_equal = '--all' in sys.argv
    lib = sc.Library(with_mmc=True, with_literature=True, strassen=True, verify_files=False)
    rows = []
    t0 = time.time()
    for r in csv.DictReader(RECORDS.open(), delimiter='\t'):
        key = tuple(map(int, r['shape'].split('x')))
        ours = int(r['rank'])
        best, how = lib.best_rank(key)
        row = dict(shape=r['shape'], ours=ours, cls=r['class'], chain=r['chain'], explicit_bound=best)
        if best < ours or (build_equal and best == ours):
            t1 = time.time()
            s, ok = build_verified(lib, key)
            best = lib.best_rank(key)[0]  # may have moved if a component was dropped
            row.update(explicit_bound=best, built=s.rank if s is not None else None, verified_over_F2=ok,
                       recipe=lib.recipe(key), leaves=sorted({p for _, p in lib.leaves(key)}),
                       seconds=round(time.time() - t1, 1))
            print(json.dumps({k: row[k] for k in ('shape', 'ours', 'built', 'verified_over_F2', 'seconds')}),
                  file=sys.stderr, flush=True)
        rows.append(row)
    below = [x for x in rows if x['explicit_bound'] < x['ours']]
    equal = [x for x in rows if x['explicit_bound'] == x['ours']]
    summary = dict(elapsed_s=round(time.time() - t0), records=len(rows),
                   explicit_below=len(below), explicit_below_verified=sum(1 for x in below if x.get('verified_over_F2')),
                   explicit_equal=len(equal), explicit_equal_verified=sum(1 for x in equal if x.get('verified_over_F2')),
                   below=below,
                   equal=[{k: x.get(k) for k in ('shape', 'ours', 'cls', 'chain', 'explicit_bound', 'built',
                                                'verified_over_F2', 'recipe')} for x in equal])
    print(json.dumps(summary, indent=1))


if __name__ == '__main__':
    main()
