#!/usr/bin/env python3
"""Rebuild matmulcatalog's serendipitous-product rank claims over GF(2) and verify them exactly.

matmulcatalog (solven-eu) docs/cited-bounds.json records, as "rank claims without factor matrices", ranks
for formats up to 32 obtained with the serendipitous product of Perminov, arXiv:2606.02480, Sec. 2.5-2.6,
from base schemes in dronperminov/FastMatrixMultiplication (schemes/results/serendipitous_base).  The
scoring rule of the release never read that file.  For every such claim with field Z (integer
coefficients, hence GF(2)-valid) at or below one of our ranks, this script:

  1. loads the named base scheme (integer coefficients) from the FMM clone, reduces it mod 2, verifies it;
  2. splits its rank-one terms into "bud" blocks: terms sharing u (<1,1,k>), sharing v (<k,1,1>) or
     sharing w (<1,k,1>) over GF(2) (single-type blocks only; the paper also allows mixed blocks);
     the block choice maximises the saving k*r2 - R(block (x) second format) per group (exact DP inside a
     group, greedy across the three bud types, all six type orders tried);
  3. builds the product: each trivial term is Kronecker-multiplied with a scheme for the second format;
     each block <N,M,P> is realised with a scheme for <N*n2, M*m2, P*p2> pushed through the linear maps
     e_xy -> u, e_yz -> v, e_zx -> w of the block (the construction of arXiv:2606.02480 Sec. 2.6);
  4. verifies the product against the matrix multiplication tensor over GF(2) (every slice, exactly).

Auxiliary schemes come from the FMM clone (any JSON file with integer coefficients, reduced mod 2 and
verified before use) or are the naive schemes of formats with a unit side.  Blobs are fetched lazily
into the fresh clone W/upstream-latest/fmm (never into the pinned clones).
Convention (as FMM): u is n x m, v is m x p, w is p x n, and sum_l u (x) v (x) w = sum_ijk e_ij (x) e_jk (x) e_ki.
Run: python3 08-serendipitous-check.py [--limit N] [--shape AxBxC] [--with-q] [--rich]
"""
import csv
import itertools
import json
import re
import subprocess
import sys
import time
from pathlib import Path

import numpy as np

W = Path('/Users/erik/.tungsten/metaflip/experiments/record-hunt-20260926/work')
FMM = W / 'upstream-latest/fmm'
MMC = W / 'upstream-latest/matmulcatalog'
EXTRACTED = W / 'upstream-latest/extracted'
RECORDS = W / 'release-0929/gf2-campaign-records/records.tsv'
NAME = re.compile(r'(?:^|/)(\d+)x(\d+)x(\d+)_m(\d+)[^/]*\.json$')


class Scheme:
    """GF(2) scheme for <n,m,p>: U (r,n,m), V (r,m,p), W (r,p,n), uint8 0/1."""

    def __init__(self, fmt, U, V, W):
        self.fmt = tuple(fmt)
        n, m, p = self.fmt
        self.U = (np.asarray(U, dtype=np.int64).reshape(-1, n, m) % 2).astype(np.uint8)
        self.V = (np.asarray(V, dtype=np.int64).reshape(-1, m, p) % 2).astype(np.uint8)
        self.W = (np.asarray(W, dtype=np.int64).reshape(-1, p, n) % 2).astype(np.uint8)
        keep = self.U.any(axis=(1, 2)) & self.V.any(axis=(1, 2)) & self.W.any(axis=(1, 2))
        self.U, self.V, self.W = self.U[keep], self.V[keep], self.W[keep]

    @property
    def rank(self):
        return len(self.U)

    def cyclic(self):  # <m,p,n>
        n, m, p = self.fmt
        return Scheme((m, p, n), self.V, self.W, self.U)

    def transpose(self):  # <p,m,n>: (v^T, u^T, w^T)
        n, m, p = self.fmt
        return Scheme((p, m, n), self.V.transpose(0, 2, 1), self.U.transpose(0, 2, 1), self.W.transpose(0, 2, 1))

    def oriented(self, target):
        s = self
        for _ in range(2):
            for _ in range(3):
                if s.fmt == tuple(target):
                    return s
                s = s.cyclic()
            s = s.transpose()
        raise ValueError(f'{self.fmt} cannot be oriented to {target}')

    def verify(self):
        n, m, p = self.fmt
        r = self.rank
        U2 = self.U.reshape(r, n * m)
        V2 = self.V.reshape(r, m * p).astype(np.float32)
        W2 = self.W.reshape(r, p * n).astype(np.float32)
        for a in range(n * m):
            i, j = divmod(a, m)
            S = np.nonzero(U2[:, a])[0]
            X = np.rint(V2[S].T @ W2[S]).astype(np.int64) % 2
            T = np.zeros((m * p, p * n), dtype=np.int64)
            for k in range(p):
                T[j * p + k, k * n + i] = 1
            if not np.array_equal(X, T):
                return False
        return True


def naive(fmt):
    n, m, p = fmt
    U, V, Wt = [], [], []
    for i, j, k in itertools.product(range(n), range(m), range(p)):
        u = np.zeros((n, m), np.uint8); u[i, j] = 1
        v = np.zeros((m, p), np.uint8); v[j, k] = 1
        w = np.zeros((p, n), np.uint8); w[k, i] = 1
        U.append(u); V.append(v); Wt.append(w)
    return Scheme(fmt, U, V, Wt)


FMM_TREE = W / 'upstream-latest/fmm-tree-ac13ca8855'  # schemes/**/*.json of FMM at ac13ca8855 (codeload tarball)
FMM_HEAD = subprocess.check_output(['git', '-C', str(FMM), 'rev-parse', 'HEAD'], text=True).strip()


def git_show(path, tries=5):
    """Blob at HEAD of the fresh FMM clone: read from the tarball tree of the same commit when present,
    else lazily fetched from the promisor remote (retried)."""
    if FMM_HEAD.startswith('ac13ca8855') and (FMM_TREE / path).is_file():
        return (FMM_TREE / path).read_bytes()
    for i in range(tries):
        try:
            return subprocess.check_output(['git', '-C', str(FMM), 'show', f'HEAD:{path}'], stderr=subprocess.DEVNULL)
        except subprocess.CalledProcessError:
            if i == tries - 1:
                raise
            time.sleep(2 + 3 * i)


def load_fmm(path):
    """Integer FMM scheme -> GF(2) Scheme in the file's own orientation, or None (fractions, other format)."""
    d = json.loads(git_show(path))
    vals = [x for key in ('u', 'v', 'w') for row in d[key] for x in (row if isinstance(row, list) else [None])]
    if not all(isinstance(x, int) for x in vals):
        return None
    n, m, p = d['n']
    return Scheme((n, m, p), d['u'], d['v'], d['w'])


MMC_TREE = W / 'upstream-latest/mmc-tree-5a306526e9c9'  # explicit schemes of matmulcatalog at 5a306526 (tarball)
MMC_HEAD = subprocess.check_output(['git', '-C', str(MMC), 'rev-parse', 'HEAD'], text=True).strip()


def load_mmc(path):
    """Explicit matmulcatalog scheme (src/main/resources/schemes/<path>) -> GF(2) Scheme, or None."""
    local = MMC_TREE / 'src/main/resources/schemes' / path
    if MMC_HEAD.startswith('5a306526e9c9') and local.is_file():
        return _mmc_scheme(local.read_bytes())
    for i in range(5):
        try:
            raw = subprocess.check_output(['git', '-C', str(MMC), 'show', f'HEAD:src/main/resources/schemes/{path}'],
                                          stderr=subprocess.DEVNULL)
            break
        except subprocess.CalledProcessError:
            if i == 4:
                return None
            time.sleep(2 + 3 * i)
    return _mmc_scheme(raw)


def _mmc_scheme(raw):
    d = json.loads(raw)
    if not all(k in d for k in ('u', 'v', 'w')):
        return None
    vals = [x for key in ('u', 'v', 'w') for row in d[key] for x in (row if isinstance(row, list) else [None])]
    if not all(isinstance(x, int) for x in vals):
        return None
    n, m, p = d['n']
    return Scheme((n, m, p), d['u'], d['v'], d['w'])


ADAP = W / 'upstream-latest/adap'  # github.com/Yamato-Arai/adap (arXiv:2312.16960 schemes, characteristic 2)


def parse_m(text):
    """Mathematica list of rank-one terms {{A, B, C}, ...} (A: n x m, B: m x p, C: p x n) -> Scheme or None."""
    body = text.replace('{', '[').replace('}', ']')
    try:
        terms = json.loads(body)
    except json.JSONDecodeError:
        return None
    if not terms or not all(len(t) == 3 for t in terms):
        return None
    A, B, C = terms[0]
    n, m, p = len(A), len(A[0]), len(B[0])
    if len(B) != m or len(C) != p or len(C[0]) != n:
        return None
    vals = [x for t in terms for mat in t for row in mat for x in row]
    if not all(isinstance(x, int) for x in vals):
        return None
    return Scheme((n, m, p), [t[0] for t in terms], [t[1] for t in terms], [t[2] for t in terms])


KAUERS = W / 'upstream-latest/mkauers-matrix-multiplication'  # github.com/mkauers/matrix-multiplication
EXP_TERM = re.compile(r'([+-]?)\s*(\d*)\s*\*?\s*([abc])(\d)(\d)')


def parse_exp(text, dims):
    """Kauers' .exp format: one product per line, (a..)*(b..)*(c..) with a_ij (n x m), b_jk (m x p), c_ki (p x n)."""
    n, m, p = dims
    U, V, Wt = [], [], []
    for line in text.split('\n'):
        line = line.strip()
        if not line:
            continue
        parts = line.split(')*(')
        if len(parts) != 3:
            return None
        mats = [np.zeros((n, m), np.int64), np.zeros((m, p), np.int64), np.zeros((p, n), np.int64)]
        for idx, part in enumerate(parts):
            for sign, coef, letter, i, j in EXP_TERM.findall(part):
                if 'abc'.index(letter) != idx:
                    return None
                c = int(coef) if coef else 1
                mats[idx][int(i) - 1, int(j) - 1] += -c if sign == '-' else c
        U.append(mats[0]); V.append(mats[1]); Wt.append(mats[2])
    return Scheme((n, m, p), U, V, Wt)


def load_any(path):
    if path.startswith('kauers:'):
        rel = path[7:]
        return parse_exp((KAUERS / rel).read_text(), tuple(int(ch) for ch in rel.split('/')[0]))
    if path.startswith('mmc:'):
        return load_mmc(path[4:])
    if path.startswith('adap:'):
        return parse_m((ADAP / path[5:]).read_text())
    if path.endswith('.m'):
        return parse_m(git_show(path).decode())
    return load_fmm(path)


def kron(a, b):
    """Kronecker product of two schemes (formats multiply coordinate-wise)."""
    U = [np.kron(x, y) for x in a.U for y in b.U]
    V = [np.kron(x, y) for x in a.V for y in b.V]
    Wt = [np.kron(x, y) for x in a.W for y in b.W]
    return Scheme(tuple(i * j for i, j in zip(a.fmt, b.fmt)), U, V, Wt)


def dsum(a, b, ax):
    """Direct sum along axis ax (0: n, 1: m, 2: p); a and b must agree on the two other sides."""
    rot = {2: 0, 0: 1, 1: 2}[ax]  # cyclic steps that bring axis ax to position 2
    for _ in range(rot):
        a, b = a.cyclic(), b.cyclic()
    n, m, p1 = a.fmt
    p2 = b.fmt[2]
    assert b.fmt[:2] == (n, m), (a.fmt, b.fmt)
    U = list(a.U) + list(b.U)
    V = [np.concatenate([v, np.zeros((m, p2), np.uint8)], axis=1) for v in a.V] + \
        [np.concatenate([np.zeros((m, p1), np.uint8), v], axis=1) for v in b.V]
    Wt = [np.concatenate([w, np.zeros((p2, n), np.uint8)], axis=0) for w in a.W] + \
         [np.concatenate([np.zeros((p1, n), np.uint8), w], axis=0) for w in b.W]
    out = Scheme((n, m, p1 + p2), U, V, Wt)
    for _ in range((3 - rot) % 3):
        out = out.cyclic()
    return out


def load_medley():
    """The rank-245 <7,7,7> F2 scheme printed in arXiv:2609.17533, App. A (C factor transposed to p x n)."""
    import base64
    import zlib
    lines = (W / 'upstream-latest/arxiv/2609.17533/paper.txt').read_text().split('\n')
    b = next(i for i, x in enumerate(lines) if 'BEGIN-RANK245-7X7X7-ZLIB-BASE32' in x)
    e = next(i for i, x in enumerate(lines) if 'END-RANK245-7X7X7-ZLIB-BASE32' in x)
    payload = ''.join(''.join(x.split()) for x in lines[b + 1:e])
    data = zlib.decompress(base64.b32decode(payload + '=' * (-len(payload) % 8)))
    U, V, Wt = [], [], []
    for off in range(0, len(data), 21):
        mats = []
        for k in (0, 7, 14):
            x = int.from_bytes(data[off + k:off + k + 7], 'little')
            mats.append(np.array([[x >> (7 * i + j) & 1 for j in range(7)] for i in range(7)], np.uint8))
        U.append(mats[0]); V.append(mats[1]); Wt.append(mats[2].T)
    return Scheme((7, 7, 7), U, V, Wt)


def strassen_reps():
    """One representative (seven (u, v, w) 2x2 GF(2) matrices) per block-support pattern among the rank-7
    schemes for <2,2,2> obtained from Strassen's by sandwiching and by the cyclic / transpose symmetries."""
    E = lambda *ij: sum(np.eye(2, dtype=np.int64)[[i]].T @ np.eye(2, dtype=np.int64)[[j]] for i, j in ij)
    base = [(E((0, 0), (1, 1)), E((0, 0), (1, 1)), E((0, 0), (1, 1))), (E((1, 0), (1, 1)), E((0, 0)), E((0, 1), (1, 1))),
            (E((0, 0)), E((0, 1), (1, 1)), E((1, 0), (1, 1))), (E((1, 1)), E((1, 0), (0, 0)), E((0, 0), (0, 1))),
            (E((0, 0), (0, 1)), E((1, 1)), E((0, 0), (1, 0))), (E((1, 0), (0, 0)), E((0, 0), (0, 1)), E((1, 1))),
            (E((0, 1), (1, 1)), E((1, 0), (1, 1)), E((0, 0)))]
    gl = [np.array(m).reshape(2, 2) for m in itertools.product((0, 1), repeat=4) if (m[0] * m[3] - m[1] * m[2]) % 2]
    inv = {M.tobytes(): next(N for N in gl if ((M @ N) % 2 == np.eye(2, dtype=np.int64)).all()) for M in gl}
    variants = [base]
    for _ in range(2):
        more = []
        for sch in variants:
            more.append([(v, w, u) for u, v, w in sch])
            more.append([(v.T, u.T, w.T) for u, v, w in sch])
        variants += more
    reps = {}
    for sch in variants:
        for X, Y, Z in itertools.product(gl, repeat=3):
            Xi, Yi, Zi = inv[X.tobytes()], inv[Y.tobytes()], inv[Z.tobytes()]
            prods = [((X @ u @ Yi) % 2, (Y @ v @ Zi) % 2, (Z @ w @ Xi) % 2) for u, v, w in sch]
            supp = tuple(sorted((tuple(np.nonzero(u.any(1))[0]), tuple(np.nonzero(u.any(0))[0]),
                                 tuple(np.nonzero(v.any(1))[0]), tuple(np.nonzero(v.any(0))[0]),
                                 tuple(np.nonzero(w.any(1))[0]), tuple(np.nonzero(w.any(0))[0])) for u, v, w in prods))
            reps.setdefault(supp, prods)
    return list(reps.values())


def strassen_sizes(rep, splits):
    """Formats the seven products need on a split ((a0,a1),(b0,b1),(c0,c1)): rows = min(max rows of the
    A-support, max rows of the C-targets), inner = min(max of A's and B's inner support), cols likewise."""
    sa, sb, sc_ = splits
    out = []
    for u, v, w in rep:
        rA = [i for i in range(2) if u[i].any()]; iA = [k for k in range(2) if u[:, k].any()]
        iB = [k for k in range(2) if v[k].any()]; cB = [j for j in range(2) if v[:, j].any()]
        cC = [j for j in range(2) if w[j].any()]; rC = [i for i in range(2) if w[:, i].any()]
        out.append((min(max(sa[i] for i in rA), max(sa[i] for i in rC)),
                    min(max(sb[k] for k in iA), max(sb[k] for k in iB)),
                    min(max(sc_[j] for j in cB), max(sc_[j] for j in cC))))
    return out


def strassen_assemble(target, rep, splits, parts):
    """Strassen on unequal blocks: every product's operands are the zero-padded block combinations,
    truncated to the product's format; parts are the inner schemes, oriented as strassen_sizes()."""
    a, b, c = target
    sa, sb, sc_ = splits
    offa, offb, offc = (0, sa[0]), (0, sb[0]), (0, sc_[0])
    U, V, Wt = [], [], []
    for (u, v, w), inner in zip(rep, parts):
        r, k, q = inner.fmt
        for x, y, z in zip(inner.U, inner.V, inner.W):
            gu = np.zeros((a, b), np.uint8); gv = np.zeros((b, c), np.uint8); gw = np.zeros((c, a), np.uint8)
            for i in range(2):
                for kk in range(2):
                    if u[i, kk]:
                        rr, cc_ = min(r, sa[i]), min(k, sb[kk])
                        gu[offa[i]:offa[i] + rr, offb[kk]:offb[kk] + cc_] ^= x[:rr, :cc_]
            for kk in range(2):
                for j in range(2):
                    if v[kk, j]:
                        rr, cc_ = min(k, sb[kk]), min(q, sc_[j])
                        gv[offb[kk]:offb[kk] + rr, offc[j]:offc[j] + cc_] ^= y[:rr, :cc_]
            for j in range(2):
                for i in range(2):
                    if w[j, i]:
                        rr, cc_ = min(q, sc_[j]), min(r, sa[i])
                        gw[offc[j]:offc[j] + rr, offa[i]:offa[i] + cc_] ^= z[:rr, :cc_]
            U.append(gu); V.append(gv); Wt.append(gw)
    return Scheme(target, U, V, Wt)


class Library:
    """Best GF(2)-valid scheme per format: an integer-coefficient FMM file (reduced mod 2; the straight-line
    'addition_reduced' files are skipped), optionally explicit matmulcatalog F2 files and published
    literature schemes, or a direct sum / Kronecker product / (optionally) Strassen-on-unequal-blocks
    composition of such schemes when that is smaller, or the naive scheme.  With verify_files=True every
    file is verified when loaded; otherwise the caller verifies the finished composition."""

    def __init__(self, with_mmc=False, with_literature=False, strassen=False, verify_files=True):
        self.strassen, self.verify_files = strassen, verify_files
        self.reps = strassen_reps() if strassen else []
        names = subprocess.check_output(['git', '-C', str(FMM), 'ls-tree', '-r', '--name-only', 'HEAD', 'schemes'],
                                        text=True).split('\n')
        self.cands = {}
        for nm in names:
            mt = NAME.search(nm)
            if mt and '_Q' not in nm.split('/')[-1] and 'mod0' not in nm and '/addition_reduced_ZT/' not in nm:
                key = tuple(sorted(map(int, mt.group(1, 2, 3))))
                self.cands.setdefault(key, []).append((int(mt.group(4)), nm))
        if with_mmc:  # explicit F2-valid matmulcatalog schemes (the 'derived/' entries are unmaterialised stubs)
            head = subprocess.check_output(['git', '-C', str(MMC), 'rev-parse', 'HEAD'], text=True)[:12]
            for e in json.loads((EXTRACTED / f'mmc_catalog_{head}.json').read_text())['schemes']:
                if 'F2' in e['fields'] and not e.get('commutative') and not e['file'].startswith('derived/'):
                    key = tuple(sorted(e['format']))
                    self.cands.setdefault(key, []).append((e['rank'], 'mmc:' + e['file']))
        if with_literature:
            # published F2 schemes outside the tables: Arai-Ichikawa-Hukushima (arXiv:2312.16960) <4,5,5>:73 and
            # <5,5,5>:94 (github.com/Yamato-Arai/adap), and the Kauers-Wood meta-flip-graph schemes that FMM
            # keeps under schemes/known/meta_flip_graph (arXiv:2510.19787; rank = number of terms)
            self.cands.setdefault((7, 7, 7), []).append((245, 'medley:2609.17533'))
            self.cands.setdefault((4, 5, 5), []).append((73, 'adap:data/455_73.m'))
            self.cands.setdefault((5, 5, 5), []).append((94, 'adap:data/555_94.m'))
            for nm in names:
                if '/known/meta_flip_graph/' in nm and nm.endswith('.m') and nm.split('/')[3].isdigit():
                    d = nm.split('/')[3]
                    key = tuple(sorted(map(int, d)))
                    self.cands.setdefault(key, []).append((10 ** 6, nm))  # rank known only after loading
            # Kauers-Wood's own repository (the paper's data link), incl. the Z2-only '.mod2.exp' schemes
            for f in sorted(KAUERS.glob('[0-9][0-9][0-9]/*.exp')):
                key = tuple(sorted(int(ch) for ch in f.parent.name))
                self.cands.setdefault(key, []).append((10 ** 6, 'kauers:' + str(f.relative_to(KAUERS))))
        for v in self.cands.values():
            v.sort()
        self.cache, self.source, self.plan = {}, {}, {}
        self.bad = set()

    def file_scheme(self, key):
        """Smallest verified scheme among the listed files (first one that loads, in listed-rank order) and
        all files whose rank is only known after loading (the .m files)."""
        best, listed_done = (None, None), False
        for rank, path in self.cands.get(key, []):
            if path in self.bad or (listed_done and rank < 10 ** 6):
                continue
            s = load_medley() if path.startswith('medley:') else load_any(path)
            if s is not None and tuple(sorted(s.fmt)) == key and (not self.verify_files or s.verify()):
                if best[0] is None or s.rank < best[0].rank:
                    best = (s, path)
                listed_done = listed_done or rank < 10 ** 6
            else:
                self.bad.add(path)
        return best

    def best_rank(self, key):
        """(rank, recipe) by files, sums and Kronecker products (memoised; recipes built by get)."""
        if key in self.plan:
            return self.plan[key]
        n, m, p = key
        if n == 1:
            res = (m * p, ('naive',))
        else:
            res = (n * m * p, ('naive',))
            s, path = self.file_scheme(key)
            if s is not None:
                self.cache[key], self.source[key] = s, path
                res = (s.rank, ('file', path))
            dims = list(key)
            for ax in range(3):
                for x in range(1, dims[ax] // 2 + 1):
                    a, b = dims.copy(), dims.copy()
                    a[ax], b[ax] = x, dims[ax] - x
                    r = self.best_rank(tuple(sorted(a)))[0] + self.best_rank(tuple(sorted(b)))[0]
                    if r < res[0]:
                        res = (r, ('sum', tuple(a), tuple(b), ax))
            divs = [[d for d in range(1, v + 1) if v % d == 0] for v in dims]
            for x in divs[0]:
                for y in divs[1]:
                    for z in divs[2]:
                        f1, f2 = (x, y, z), (n // x, m // y, p // z)
                        if f1 == (1, 1, 1) or f2 == (1, 1, 1):
                            continue
                        r = self.best_rank(tuple(sorted(f1)))[0] * self.best_rank(tuple(sorted(f2)))[0]
                        if r < res[0]:
                            res = (r, ('kron', f1, f2))
            if self.strassen and n >= 2:
                for splits in itertools.product(*[sorted({(d // 2, d - d // 2), (d - d // 2, d // 2)}) for d in key]):
                    for idx, rep in enumerate(self.reps):
                        sizes = strassen_sizes(rep, splits)
                        r = sum(self.best_rank(tuple(sorted(sz)))[0] for sz in sizes)
                        if r < res[0]:
                            res = (r, ('strassen', idx, splits, tuple(sizes)))
        self.plan[key] = res
        return res

    def leaves(self, key):
        """File leaves of the recipe of `key` (for locating a bad component)."""
        rank, how = self.best_rank(key)
        if how[0] == 'file':
            return {(key, how[1])}
        if how[0] == 'sum':
            return self.leaves(tuple(sorted(how[1]))) | self.leaves(tuple(sorted(how[2])))
        if how[0] == 'kron':
            return self.leaves(tuple(sorted(how[1]))) | self.leaves(tuple(sorted(how[2])))
        if how[0] == 'strassen':
            return set().union(*(self.leaves(tuple(sorted(sz))) for sz in how[3]))
        return set()

    def recipe(self, key, depth=0):
        rank, how = self.best_rank(key)
        name = 'x'.join(map(str, key)) + f':{rank}'
        if how[0] in ('file', 'naive'):
            return f"{name}[{how[1] if how[0] == 'file' else 'naive'}]"
        if depth > 3:
            return name + '(...)'
        if how[0] == 'strassen':
            return name + f'=Strassen{how[2]}(' + ', '.join(self.recipe(tuple(sorted(sz)), depth + 1) for sz in how[3]) + ')'
        op = ' (+) ' if how[0] == 'sum' else ' (x) '
        return name + '=(' + self.recipe(tuple(sorted(how[1])), depth + 1) + op + self.recipe(tuple(sorted(how[2])), depth + 1) + ')'

    def drop(self, path):
        """Forget a component (e.g. one that fails verification) and every plan built on it."""
        self.bad.add(path)
        self.plan, self._built = {}, {}
        self.cache = {k: v for k, v in self.cache.items() if self.source.get(k) != path}

    def get(self, fmt):
        """Scheme for exactly `fmt` (oriented), built once per sorted format."""
        fmt = tuple(fmt)
        key = tuple(sorted(fmt))
        if key not in self.built():
            rank, how = self.best_rank(key)
            if how[0] == 'naive':
                s, src = naive(key), 'naive (unit side)' if key[0] == 1 else 'naive'
            elif how[0] == 'file':
                s, src = self.cache[key], how[1]
            elif how[0] == 'sum':
                _, a, b, ax = how
                s, src = dsum(self.get(a), self.get(b), ax), f'sum {a} + {b}'
            elif how[0] == 'kron':
                _, f1, f2 = how
                s, src = kron(self.get(f1), self.get(f2)), f'kron {f1} x {f2}'
            else:
                _, idx, splits, sizes = how
                s = strassen_assemble(key, self.reps[idx], splits, [self.get(sz) for sz in sizes])
                src = f'strassen {splits}'
            assert s.rank <= rank and tuple(sorted(s.fmt)) == key, (key, s.rank, rank)
            self._built[key], self.source[key] = s, src
        return self._built[key].oriented(fmt)

    def built(self):
        if not hasattr(self, '_built'):
            self._built = {}
        return self._built


def classes(base):
    """Class id of every term's u, v and w over GF(2) (equal factor -> same class)."""
    out = []
    for arr in (base.U, base.V, base.W):
        ids, cls = {}, []
        for t in range(base.rank):
            cls.append(ids.setdefault(arr[t].tobytes(), len(ids)))
        out.append(cls)
    return out


def blocks_candidates(base, cap=20000):
    """Elementary blocks <N,M,P> as index maps {(x,y,z): term}.  Single-type buds (<1,1,k>, <k,1,1>,
    <1,k,1>) and the mixed rectangles <N,1,P> (u by x, v by z), <N,M,1> (v by y, w by x), <1,M,P>
    (u by y, w by z) with N, M, P >= 2, i.e. complete bipartite patterns between two factor classes."""
    cu, cv, cw = classes(base)
    out = []
    members = {}
    for which, cls in (('U', cu), ('V', cv), ('W', cw)):
        for t, c in enumerate(cls):
            members.setdefault((which, c), []).append(t)
    # single-type buds
    for (which, c), ts in members.items():
        if len(ts) < 2:
            continue
        sizes = range(2, len(ts) + 1)
        for k in sizes:
            subsets = itertools.combinations(ts, k) if len(ts) <= 6 else [tuple(ts[:k])]
            for sub in subsets:
                phi = {{'U': (0, 0, i), 'V': (i, 0, 0), 'W': (0, i, 0)}[which]: t for i, t in enumerate(sub)}
                out.append(phi)
    # mixed rectangles: rows = classes of one factor, cols = classes of another, one term per cell
    for (ra, rcls), (cb, ccls), mk in ((('U', cu), ('V', cv), lambda x, z: (x, 0, z)),      # <N,1,P>
                                       (('W', cw), ('V', cv), lambda x, y: (x, y, 0)),      # <N,M,1>: w by x, v by y
                                       (('U', cu), ('W', cw), lambda y, z: (0, y, z))):     # <1,M,P>: u by y, w by z
        cell = {}
        for t in range(base.rank):
            cell.setdefault((rcls[t], ccls[t]), t)
        cols = {}
        for (r, c), t in cell.items():
            cols.setdefault(c, set()).add(r)
        cols = {c: rs for c, rs in cols.items() if len(rs) >= 2}
        colkeys = sorted(cols)
        for P in (2, 3, 4):
            for cs in itertools.combinations(colkeys, P):
                common = set.intersection(*(cols[c] for c in cs))
                if len(common) < 2:
                    continue
                common = sorted(common)
                for N in range(2, min(len(common), 4) + 1):
                    for rs in itertools.combinations(common, N):
                        out.append({mk(i, j): cell[(r, c)] for i, r in enumerate(rs) for j, c in enumerate(cs)})
                        if len(out) > cap:
                            return out
    return out


def block_shape(phi):
    return tuple(max(k[d] for k in phi) + 1 for d in range(3))


def plan(base, s2fmt, lib, restarts=300, seed=1):
    """Pick disjoint blocks maximising sum(|block| * r2 - R(block (x) s2)); returns (blocks, rank)."""
    n2, m2, p2 = s2fmt
    r2 = lib.get(s2fmt).rank
    cands = []
    for phi in blocks_candidates(base):
        N, M, P = block_shape(phi)
        sav = len(phi) * r2 - lib.get((N * n2, M * m2, P * p2)).rank
        if sav > 0:
            cands.append((sav, frozenset(phi.values()), phi))
    rng = np.random.default_rng(seed)
    best = (0, [])
    orders = [sorted(cands, key=lambda c: (-c[0], len(c[1]))), sorted(cands, key=lambda c: (-c[0] / len(c[1]), len(c[1])))]
    for _ in range(restarts):
        noise = rng.random(len(cands))
        orders.append([cands[i] for i in np.argsort([-(c[0] / len(c[1])) * (0.5 + noise[i]) for i, c in enumerate(cands)])])
    for order in orders:
        used, chosen, total = set(), [], 0
        for sav, ts, phi in order:
            if used.isdisjoint(ts):
                used |= ts
                chosen.append(phi)
                total += sav
        if total > best[0]:
            best = (total, chosen)
    return best[1], base.rank * r2 - best[0]


def product(base, s2fmt, blocks, lib):
    n1, m1, p1 = base.fmt
    n2, m2, p2 = s2fmt
    U, V, Wt = [], [], []
    inblock = {t for phi in blocks for t in phi.values()}
    assert len(inblock) == sum(len(phi) for phi in blocks), 'blocks overlap'
    s2 = lib.get(s2fmt)
    for t in range(base.rank):
        if t in inblock:
            continue
        for a, b, c in zip(s2.U, s2.V, s2.W):
            U.append(np.kron(base.U[t], a)); V.append(np.kron(base.V[t], b)); Wt.append(np.kron(base.W[t], c))
    for phi in blocks:
        N, M, P = block_shape(phi)
        assert len(phi) == N * M * P
        alpha, beta, gamma = {}, {}, {}
        for (x, y, z), t in phi.items():
            for d, k, val in ((alpha, (x, y), base.U[t]), (beta, (y, z), base.V[t]), (gamma, (z, x), base.W[t])):
                if k in d:
                    assert np.array_equal(d[k], val), 'block is not an elementary matrix multiplication tensor'
                d[k] = val
        s3 = lib.get((N * n2, M * m2, P * p2))
        for a, b, c in zip(s3.U, s3.V, s3.W):
            u = sum(np.kron(alpha[(x, y)], a[x * n2:(x + 1) * n2, y * m2:(y + 1) * m2]) for (x, y) in alpha)
            v = sum(np.kron(beta[(y, z)], b[y * m2:(y + 1) * m2, z * p2:(z + 1) * p2]) for (y, z) in beta)
            w = sum(np.kron(gamma[(z, x)], c[z * p2:(z + 1) * p2, x * n2:(x + 1) * n2]) for (z, x) in gamma)
            U.append(u % 2); V.append(v % 2); Wt.append(w % 2)
    return Scheme((n1 * n2, m1 * m2, p1 * p2), U, V, Wt)


def orientations(s):
    out, t = [], s
    for _ in range(2):
        for _ in range(3):
            out.append(t)
            t = t.cyclic()
        t = t.transpose()
    return out


def claims():
    ours = {tuple(map(int, r['shape'].split('x'))): r for r in csv.DictReader(RECORDS.open(), delimiter='\t')}
    head = subprocess.check_output(['git', '-C', str(W / 'upstream-latest/matmulcatalog'), 'rev-parse', 'HEAD'], text=True)[:12]
    out = []
    for e in json.loads((EXTRACTED / f'mmc_cited-bounds_{head}.json').read_text())['entries']:
        if 'format' not in e or 'rank' not in e or not e.get('source', '').startswith('Perminov 2026'):
            continue
        k = tuple(sorted(e['format']))
        if k in ours and e['rank'] <= int(ours[k]['rank']):
            m = re.search(r'⟨(\d+),(\d+),(\d+)⟩ ⊗ˢ ⟨(\d+),(\d+),(\d+)⟩', e['algorithm'])
            base_path = e['source_scheme_url'].split('/blob/master/')[1]
            out.append(dict(shape=ours[k]['shape'], ours=int(ours[k]['rank']), cls=ours[k]['class'], claim=e['rank'],
                            field=e['field'], s1=tuple(map(int, m.group(1, 2, 3))), s2=tuple(map(int, m.group(4, 5, 6))),
                            base=base_path, format=e['format']))
    return out


def main():
    args = sys.argv[1:]
    only = args[args.index('--shape') + 1] if '--shape' in args else None
    limit = int(args[args.index('--limit') + 1]) if '--limit' in args else None
    want_q = '--with-q' in args
    # --rich: auxiliary schemes may also come from explicit matmulcatalog files, the published literature
    # schemes and Strassen compositions (every product is still verified exactly)
    lib = Library(with_mmc=True, with_literature=True, strassen=True, verify_files=False) if '--rich' in args else Library()
    rows = []
    todo = [c for c in claims() if (c['field'] == 'Z' or want_q) and (only is None or c['shape'] == only)]
    for c in todo[:limit]:
        try:
            rows.append(check(c, lib))
        except Exception as exc:  # recorded, never silently dropped
            rows.append(dict(c, status=f'error: {exc!r}'))
        r = rows[-1]
        print(json.dumps({k: r.get(k) for k in ('shape', 'ours', 'claim', 'built', 'verified_over_F2', 'status', 'seconds')}),
              file=sys.stderr, flush=True)
    summary = dict(claims_checked=len(rows),
                   verified_and_below_ours=sum(1 for r in rows if r.get('verified_over_F2') and r['built'] < r['ours']),
                   verified_and_equal_ours=sum(1 for r in rows if r.get('verified_over_F2') and r['built'] == r['ours']),
                   verified_at_or_below_claim=sum(1 for r in rows if r.get('verified_over_F2') and r['built'] <= r['claim']),
                   errors=sum(1 for r in rows if str(r.get('status', '')).startswith('error')),
                   library_sources={'x'.join(map(str, k)): v for k, v in sorted(lib.source.items())},
                   rows=rows)
    print(json.dumps(summary, indent=1, default=list))


def check(c, lib):
    """Rebuild one claim; the row records the orientation, blocks, rank and exact GF(2) verification."""
    t0 = time.time()
    base = load_fmm(c['base'])
    row = dict(c)
    if base is None or base.fmt != c['s1'] or not base.verify():
        row.update(status='base scheme unusable over GF(2)')
        return row
    # the catalogue gives formats only; try every orientation of the base scheme and of the second
    # format whose product is the target shape (the bud type that saves depends on the orientation)
    target = tuple(sorted(c['format']))
    options = []
    for ob in orientations(base):
        for s2f in set(itertools.permutations(c['s2'])):
            if tuple(sorted(a * b for a, b in zip(ob.fmt, s2f))) == target:
                blocks, predicted = plan(ob, s2f, lib)
                options.append((predicted, ob.fmt, s2f, blocks, ob))
    predicted, bfmt, s2f, blocks, ob = min(options, key=lambda o: o[0])
    prod = product(ob, s2f, blocks, lib)
    ok = prod.verify()
    row.update(base_rank=base.rank, s2_rank=lib.get(s2f).rank, blocks=len(blocks), orientation=[bfmt, s2f],
               options_tried=len(options),
               block_shapes=sorted('x'.join(map(str, block_shape(b))) for b in blocks),
               predicted=predicted, built=prod.rank, built_format=prod.fmt, verified_over_F2=ok,
               seconds=round(time.time() - t0, 1),
               status=('matches claim' if prod.rank <= c['claim'] else 'above claim') + (
                   ', below ours' if prod.rank < c['ours'] else ', equal to ours' if prod.rank == c['ours'] else ', not below ours'))
    return row


if __name__ == '__main__':
    main()
