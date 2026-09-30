#!/usr/bin/env python3
"""Cross-check: re-verify a sample of the superseding GF(2) schemes built by 08-serendipitous-check.py and
08-composition-verify.py with the release's own verifier (screen_top_two_projection_children.exact from the
repository tools directory, the function gf2_record_board.decode uses), independently of Scheme.verify().

The release verifier takes rank-one terms as bitmasks: u bit i*m+j, v bit j*p+k, w bit i*p+k (C not
transposed); the 08 scripts keep w as a p x n matrix, so w[k, i] maps to bit i*p+k.
Run: python3 08-crosscheck-release-verifier.py [--negative-only]
(--negative-only: both verifiers on 4x5x15:219 intact, with one flipped coefficient in U / V / W, with one term dropped)
"""
import importlib.util
import json
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOLS = '/Users/erik/tungsten-mf-ternary/bits/tungsten-metaflip/tools'
sys.path.insert(0, TOOLS)
import screen_top_two_projection_children as top  # noqa: E402

spec = importlib.util.spec_from_file_location('sc', HERE / '08-serendipitous-check.py')
sc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sc)


def to_bits(s):
    n, m, p = s.fmt
    terms = []
    for u, v, w in zip(s.U, s.V, s.W):
        ub = sum(1 << (i * m + j) for i in range(n) for j in range(m) if u[i, j])
        vb = sum(1 << (j * p + k) for j in range(m) for k in range(p) if v[j, k])
        wb = sum(1 << (i * p + k) for k in range(p) for i in range(n) if w[k, i])
        terms.append((ub, vb, wb))
    return terms


def release_ok(s):
    try:
        top.exact(tuple(s.fmt), to_bits(s))
        return True
    except AssertionError:
        return False


def negative_control():
    """Both verifiers must reject a verified scheme after one coefficient flip (in U, V or W) or one dropped term."""
    lib = sc.Library(with_mmc=True, with_literature=True, strassen=True, verify_files=False)
    s = lib.get((4, 5, 15))
    out = dict(intact=(s.verify(), release_ok(s)))
    for which in 'UVW':
        arr = getattr(s, which).copy()
        arr[3].flat[0] ^= 1
        t = sc.Scheme(s.fmt, *(arr if w == which else getattr(s, w) for w in 'UVW'))
        out[f'flip_{which}'] = (t.verify(), release_ok(t))
    t = sc.Scheme(s.fmt, s.U[1:], s.V[1:], s.W[1:])
    out['drop_term'] = (t.verify(), release_ok(t))
    return out


def main():
    if sys.argv[1:2] == ['--negative-only']:
        print(json.dumps(negative_control()))
        return
    rows = []
    rich = sc.Library(with_mmc=True, with_literature=True, strassen=True, verify_files=False)
    # explicit compositions (08-composition-verify.py recipes)
    for shape in ((7, 7, 7), (4, 5, 15), (8, 8, 15), (16, 20, 20), (20, 20, 25), (13, 19, 21), (8, 8, 9)):
        t0 = time.time()
        s = rich.get(shape)
        rows.append(dict(kind='explicit composition', shape='x'.join(map(str, shape)), rank=s.rank,
                         scheme_verify=s.verify(), release_verifier=release_ok(s), seconds=round(time.time() - t0, 1)))
        print(json.dumps(rows[-1]), flush=True)
    # a rebuilt serendipitous product (08-serendipitous-check.py, 3x14x18 from the FMM 3x7x9 base)
    claims = {c['shape']: c for c in sc.claims()}
    for shape in ('3x14x18', '7x14x20'):
        c = claims[shape]
        t0 = time.time()
        base = sc.load_fmm(c['base'])
        best = None
        for ob in sc.orientations(base):
            for s2f in set(__import__('itertools').permutations(c['s2'])):
                if tuple(sorted(a * b for a, b in zip(ob.fmt, s2f))) == tuple(sorted(c['format'])):
                    blocks, pred = sc.plan(ob, s2f, rich)
                    if best is None or pred < best[0]:
                        best = (pred, ob, s2f, blocks)
        pred, ob, s2f, blocks = best
        s = sc.product(ob, s2f, blocks, rich)
        rows.append(dict(kind='serendipitous product', shape=shape, rank=s.rank, scheme_verify=s.verify(),
                         release_verifier=release_ok(s), seconds=round(time.time() - t0, 1)))
        print(json.dumps(rows[-1]), flush=True)
    print(json.dumps(dict(all_agree=all(r['scheme_verify'] and r['release_verifier'] for r in rows), rows=rows), indent=1))


if __name__ == '__main__':
    main()
