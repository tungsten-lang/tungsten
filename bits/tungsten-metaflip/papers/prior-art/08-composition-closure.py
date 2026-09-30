#!/usr/bin/env python3
"""Blind spots of the scoring rule: bounds that no public table lists but that follow from published
GF(2)-valid schemes by the two textbook compositions, and rank claims the scoring rule did not read.

Closure rules (valid over every ring, so over GF(2) when both parts are GF(2)-valid):
  direct sum   <a,b,c1> (+) <a,b,c2>  -> <a,b,c1+c2>,    rank r1 + r2   (any of the three axes)
  Kronecker    <a1,b1,c1> (x) <a2,b2,c2> -> <a1a2,b1b2,c1c2>, rank r1 * r2
  and <1,b,c> has rank b*c.  Rank is invariant under permuting (n, m, p), so shapes are sorted.

Base tables (all GF(2)-valid, all public at the latest revisions of 2026-09-29, see 08-rescore-latest.py):
  L0  the GF(2)-valid table of the scoring rule itself (gf2_record_board.public_tables at the latest
      heads: FMM ZT/Z file names outside schemes/known, fmm-schemes ZT/Z, matmulcatalog F2 schemes)
  L1  L0 + FMM ZT/Z files under schemes/known (excluded by the scoring rule)
  L2  L1 + GF(2)-valid rank claims printed in papers (Z2/F2-only tables; imported from
      08-literature-check.py, which verifies each against the paper text)
Also compared, without closure: matmulcatalog docs/cited-bounds.json (literature rank claims without
factor matrices) and docs/derived-from-cited-bounds.json (formula-derived, unbuilt bounds).

For each of the 795 records: the smallest composed bound under L0/L1/L2 and its derivation, the
catalogue claims at or below our rank, and a flag.  Prints JSON; --tsv PATH is not used (no new files).
Run: python3 08-composition-closure.py
"""
import csv
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

os.environ['GIT_NO_LAZY_FETCH'] = '1'
W = Path('/Users/erik/.tungsten/metaflip/experiments/record-hunt-20260926/work')
LATEST = W / 'upstream-latest'
EXTRACTED = LATEST / 'extracted'
RECORDS = W / 'release-0929/gf2-campaign-records/records.tsv'
TOOLS = '/Users/erik/tungsten-mf-ternary/bits/tungsten-metaflip/tools'
sys.path.insert(0, TOOLS)
import gf2_record_board as grb  # noqa: E402

HERE = Path(__file__).resolve().parent
MAXD = 32


def load_module(name, file):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args], text=True).strip()


def key(*dims):
    return tuple(sorted(dims))


def offer(table, k, rank, label):
    if k not in table or rank < table[k][0]:
        table[k] = (rank, [label])
    elif rank == table[k][0] and label not in table[k][1]:
        table[k][1].append(label)


def public_gf2():
    """L0: the scoring rule's GF(2)-valid table at the latest heads, labelled by source; L1 additions."""
    heads = {s: git(LATEST / d, 'rev-parse', 'HEAD') for s, d in
             (('lille', 'fmm_digest'), ('mmc', 'matmulcatalog'), ('fmm', 'fmm'), ('merlijn', 'fmm-schemes'))}
    empty = EXTRACTED / 'empty_lille.json'
    mmc = EXTRACTED / f"mmc_catalog_{heads['mmc'][:12]}.json"
    args = SimpleNamespace(lille=str(EXTRACTED / f"fmm_sota_{heads['lille'][:12]}.json"), matmulcatalog=str(mmc),
                           fmm_repo=str(LATEST / 'fmm'), fmm_revision=heads['fmm'], extra_repo=[str(LATEST / 'fmm-schemes')])
    _, _, gf2 = grb.public_tables(args)  # the exact table the re-score used
    table = {}
    # labels: which source attains the minimum
    for e in json.loads(mmc.read_text())['schemes']:
        if not e.get('commutative') and 'F2' in e['fields']:
            offer(table, key(*e['format']), e['rank'], f"matmulcatalog:{e['source']}")
    names = git(LATEST / 'fmm', 'ls-tree', '-r', '--name-only', heads['fmm'], 'schemes').split('\n')
    extra = [str(p.relative_to(LATEST / 'fmm-schemes')) for p in (LATEST / 'fmm-schemes').rglob('*.json')]
    known = {}
    for origin, pool in (('FMM', names), ('fmm-schemes', extra)):
        for n in pool:
            m = grb.RING.search(n)
            if not m or m.group(5) not in ('ZT', 'Z'):
                continue
            k, r = key(*map(int, m.group(1, 2, 3))), int(m.group(4))
            if '/known/' in n:
                offer(known, k, r, f'{origin}(known):{n.split("/")[-2]}/{m.group(5)}')
            else:
                offer(table, k, r, f'{origin}:{m.group(5)}')
    assert {k: v[0] for k, v in table.items()} == gf2, 'labelled L0 differs from public_tables()'
    return table, known, heads


def strassen_patterns():
    """Block-support patterns of the 7 products of every rank-7 GF(2) scheme for <2,2,2> obtained from
    Strassen's by sandwiching (u -> X u Y^-1, v -> Y v Z^-1, w -> Z w X^-1, X, Y, Z in GL2(F2)) and by the
    cyclic / transpose symmetries.  Per product: (rowsA, innerA, innerB, colsB, colsC, rowsC) index sets."""
    import itertools
    import numpy as np
    E = lambda *ij: sum(np.eye(2, dtype=np.int64)[[i]].T @ np.eye(2, dtype=np.int64)[[j]] for i, j in ij)
    # Strassen in the convention u: n x m, v: m x p, w: p x n (w[k, i] = 1 <=> the product feeds C_ik)
    base = [(E((0, 0), (1, 1)), E((0, 0), (1, 1)), E((0, 0), (1, 1))),
            (E((1, 0), (1, 1)), E((0, 0)), E((0, 1), (1, 1))),
            (E((0, 0)), E((0, 1), (1, 1)), E((1, 0), (1, 1))),
            (E((1, 1)), E((1, 0), (0, 0)), E((0, 0), (0, 1))),
            (E((0, 0), (0, 1)), E((1, 1)), E((0, 0), (1, 0))),
            (E((1, 0), (0, 0)), E((0, 0), (0, 1)), E((1, 1))),
            (E((0, 1), (1, 1)), E((1, 0), (1, 1)), E((0, 0)))]
    T = np.zeros((2,) * 6, dtype=np.int64)
    for u, v, w in base:
        T += np.einsum('ab,cd,ef->abcdef', u, v, w)
    Mt = np.zeros_like(T)
    for i, j, k in itertools.product(range(2), repeat=3):
        Mt[i, j, j, k, k, i] = 1
    assert ((T % 2) == Mt).all(), 'Strassen table is wrong'
    gl = [np.array(m).reshape(2, 2) for m in itertools.product((0, 1), repeat=4)
          if (m[0] * m[3] - m[1] * m[2]) % 2]
    inv = {M.tobytes(): next(N for N in gl if ((M @ N) % 2 == np.eye(2, dtype=np.int64)).all()) for M in gl}
    variants, pats = [base], set()
    for _ in range(2):  # close under cyclic and transpose
        more = []
        for sch in variants:
            more.append([(v, w, u) for u, v, w in sch])
            more.append([(v.T, u.T, w.T) for u, v, w in sch])
        variants += more
    for sch in variants:
        for X in gl:
            for Y in gl:
                for Z in gl:
                    Xi, Yi, Zi = inv[X.tobytes()], inv[Y.tobytes()], inv[Z.tobytes()]
                    prods = []
                    for u, v, w in sch:
                        u2, v2, w2 = (X @ u @ Yi) % 2, (Y @ v @ Zi) % 2, (Z @ w @ Xi) % 2
                        prods.append((frozenset(np.nonzero(u2.any(1))[0]), frozenset(np.nonzero(u2.any(0))[0]),
                                      frozenset(np.nonzero(v2.any(1))[0]), frozenset(np.nonzero(v2.any(0))[0]),
                                      frozenset(np.nonzero(w2.any(1))[0]), frozenset(np.nonzero(w2.any(0))[0])))
                    pats.add(tuple(sorted(prods, key=lambda t: tuple(tuple(sorted(x)) for x in t))))
    return sorted(pats, key=str)


PATTERNS = None


def strassen_rule(best, s):
    """Strassen on a 2x2x2 block split with unequal blocks: product l needs the format (min(max rows of its
    A-support, max rows of its C-targets), min(max inner of A, max inner of B), min(max cols of B, max cols of
    its C-targets)); the smaller operand blocks are zero-padded, unneeded rows/cols are dropped."""
    global PATTERNS
    if PATTERNS is None:
        PATTERNS = strassen_patterns()
    a, b, c = s
    if min(s) < 2:
        return None
    splits = [sorted({(d // 2, d - d // 2), (d - d // 2, d // 2)}) for d in s]
    out = None
    for sa in splits[0]:
        for sb in splits[1]:
            for sc in splits[2]:
                for pat in PATTERNS:
                    total, parts = 0, []
                    for rA, iA, iB, cB, cC, rC in pat:
                        r = min(max(sa[i] for i in rA), max(sa[i] for i in rC))
                        k = min(max(sb[i] for i in iA), max(sb[i] for i in iB))
                        q = min(max(sc[i] for i in cB), max(sc[i] for i in cC))
                        sub = key(r, k, q)
                        total += best[sub][0]
                        parts.append(sub)
                    if out is None or total < out[0]:
                        out = (total, ('strassen', (sa, sb, sc), tuple(parts)))
    return out


def closure(base, strassen=False):
    """Smallest rank reachable by direct sums and Kronecker products (and, with strassen=True, Strassen's
    algorithm on unequal 2x2x2 block splits); returns {shape: (rank, how)}."""
    best = {}
    shapes = sorted({key(a, b, c) for a in range(1, MAXD + 1) for b in range(a, MAXD + 1) for c in range(b, MAXD + 1)},
                    key=lambda s: (s[0] * s[1] * s[2], s))
    for s in shapes:
        a, b, c = s
        if a == 1:
            best[s] = (b * c, ('trivial',))
            continue
        cand = [(base[s][0], ('base', base[s][1]))] if s in base else []
        cand.append((a * b * c, ('naive',)))
        dims = list(s)
        for ax in range(3):
            d = dims[ax]
            for x in range(1, d // 2 + 1):
                p1, p2 = dims.copy(), dims.copy()
                p1[ax], p2[ax] = x, d - x
                k1, k2 = key(*p1), key(*p2)
                cand.append((best[k1][0] + best[k2][0], ('sum', k1, k2)))
        divs = [[x for x in range(1, d + 1) if d % x == 0] for d in dims]
        for x in divs[0]:
            for y in divs[1]:
                for z in divs[2]:
                    f1, f2 = (x, y, z), (a // x, b // y, c // z)
                    if f1 == (1, 1, 1) or f2 == (1, 1, 1):
                        continue
                    k1, k2 = key(*f1), key(*f2)
                    cand.append((best[k1][0] * best[k2][0], ('kron', k1, k2)))
        if strassen:
            st = strassen_rule(best, s)
            if st is not None:
                cand.append(st)
        best[s] = min(cand, key=lambda t: (t[0], 0 if t[1][0] == 'base' else 1))
    return best


def explain(best, s, depth=0):
    """Readable derivation; Strassen nodes list their 7 parts, nesting is cut at depth 4."""
    rank, how = best[s]
    if depth > 4:
        return f"{'x'.join(map(str, s))}:{rank}(...)"
    name = 'x'.join(map(str, s))
    if how[0] == 'trivial':
        return f'{name}:{rank}(trivial)'
    if how[0] == 'naive':
        return f'{name}:{rank}(naive)'
    if how[0] == 'base':
        return f'{name}:{rank}[{" | ".join(how[1][:3])}]'
    if depth > 6:
        return f'{name}:{rank}(...)'
    if how[0] == 'strassen':
        parts = ', '.join(explain(best, p, depth + 1) for p in how[2])
        return f'{name}:{rank}=Strassen[split {how[1]}](' + parts + ')'
    op = ' (+) ' if how[0] == 'sum' else ' (x) '
    return f'{name}:{rank}=(' + explain(best, how[1], depth + 1) + op + explain(best, how[2], depth + 1) + ')'


def literature_gf2():
    """GF(2)-valid rank claims printed in papers (verified against the text by 08-literature-check.py)."""
    lit = load_module('litcheck', '08-literature-check.py')
    out = {}
    for label, tab in {f'{a} {t}': v for a, ts in lit.perminov().items() for t, v in ts.items()}.items():
        for r in tab['rows']:
            if r['ring'] in lit.GF2_VALID:
                offer(out, key(int(r['n']), int(r['m']), int(r['p'])), int(r['rank']), f'arXiv:{label} line {r["line"]} ({r["ring"]})')
    med = lit.medley()
    assert med['verified_over_F2'] and med['rank'] == 245
    offer(out, (7, 7, 7), 245, 'arXiv:2609.17533 App. A (F2, scheme verified)')
    for row in lit.transcribed_gf2():  # transcribed rows, each quote-checked by the literature script
        offer(out, key(*row['format']), row['rank'], row['label'])
    return out


def main():
    recs = list(csv.DictReader(RECORDS.open(), delimiter='\t'))
    ours = {tuple(map(int, r['shape'].split('x'))): r for r in recs}
    l0, known, heads = public_gf2()
    l1 = dict(l0)
    for k, (r, labels) in known.items():
        for lab in labels:
            offer(l1, k, r, lab)
    lit = literature_gf2()
    l2 = dict(l1)
    for k, (r, labels) in lit.items():
        for lab in labels:
            offer(l2, k, r, lab)
    closures = {name: closure(t) for name, t in (('L0', l0), ('L1', l1), ('L2', l2))}
    closures.update({name + 'S': closure(t, strassen=True) for name, t in (('L0', l0), ('L2', l2))})

    # matmulcatalog literature claims and derived bounds (latest and pinned revisions)
    mmc_head = heads['mmc'][:12]
    cited = json.loads((EXTRACTED / f'mmc_cited-bounds_{mmc_head}.json').read_text())['entries']
    derived = json.loads((EXTRACTED / f'mmc_derived-from-cited-bounds_{mmc_head}.json').read_text())['entries']
    cited_pin = json.loads((EXTRACTED / 'mmc_cited-bounds_f0c2ba9e3797.json').read_text())['entries']
    pin_keys = {(key(*e['format']), e['rank'], e['field'], e['source']) for e in cited_pin if 'format' in e and 'rank' in e}

    rows, flags = [], {}
    for k, r in ours.items():
        rank = int(r['rank'])
        row = dict(shape=r['shape'], rank=rank, cls=r['class'], chain=r['chain'])
        for name, best in closures.items():
            row[name] = best[k][0]
        row['derivation_L2'] = explain(closures['L2'], k)
        row['derivation_L2S'] = explain(closures['L2S'], k)
        row['cited'] = [dict(rank=e['rank'], field=e['field'], source=e['source'], algorithm=e.get('algorithm'),
                             in_pinned=(key(*e['format']), e['rank'], e['field'], e['source']) in pin_keys)
                        for e in cited if 'format' in e and 'rank' in e and key(*e['format']) == k and not e.get('commutative') and e['rank'] <= rank]
        row['derived'] = [dict(rank=e['rank'], field=e['field'], breakdown=e.get('breakdown'))
                          for e in derived if 'format' in e and 'rank' in e and key(*e['format']) == k and e['rank'] <= rank]
        f = []
        for name in ('L0', 'L1', 'L2', 'L0S', 'L2S'):
            if row[name] < rank:
                f.append(f'{name}_below')
            elif row[name] == rank:
                f.append(f'{name}_equal')
        if any(c['field'] in ('Z', 'R/Q/Z') and c['rank'] < rank for c in row['cited']):
            f.append('cited_Z_below')
        if any(c['field'] in ('Z', 'R/Q/Z') and c['rank'] == rank for c in row['cited']):
            f.append('cited_Z_equal')
        if any(c['field'] == 'Q' and c['rank'] < rank for c in row['cited']):
            f.append('cited_Q_below')
        if any(d['field'] == 'F2' and d['rank'] < rank for d in row['derived']):
            f.append('derived_F2_below')
        if any(d['field'] == 'F2' and d['rank'] == rank for d in row['derived']):
            f.append('derived_F2_equal')
        row['flags'] = f
        for x in f:
            flags[x] = flags.get(x, 0) + 1
        rows.append(row)
    known_effect = sum(1 for r in rows if r['L1'] != r['L0'])  # records where FMM schemes/known changes the closure
    summary = dict(heads=heads, base_sizes=dict(L0=len(l0), L1=len(l1), L2=len(l2), literature=len(lit)), flag_counts=flags,
                   records_where_L1_differs_from_L0=known_effect,
                   any_flag=sum(1 for r in rows if r['flags']),
                   flagged=[r for r in rows if r['flags']])
    print(json.dumps(summary, indent=1, ensure_ascii=False))


if __name__ == '__main__':
    main()
