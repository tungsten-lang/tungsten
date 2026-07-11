"""Prepare flip-graph seeds: parse published schemes, reorient formats, apply
cross-format edges, exact-validate, emit an embeddable Tungsten seed block.

Input formats auto-detected per file:
  - MP/KW txt:  one term per line, (a11+a23+...)*(b12+...)*(c13+...)   [1-indexed]
  - mask seed:  lines  us[k] = <int> / vs[k] = <int> / ws[k] = <int>
  - R dump:     lines  R <u> <v> <w>   (searcher stdout harvest)

Ops (applied left to right, each exact-validated against the matmul tensor):
  rot     (n,m,p) -> (m,p,n)   cyclic:  (u,v,w) -> (v,w,u)
  swap    (n,m,p) -> (p,m,n)   transpose: (u,v,w) -> (vT,uT,wT)
  proj    (n,m,p) -> (n,m,p-1) zero last B-col, drop last C-col
  ext     (n,m,p) -> (n,m,p+1) widen + append naive column terms

Usage:
  python3 seed_prep.py <scheme file> <n> <m> <p> [rot|swap|proj|ext ...]
Emits `us[k] = ...` block on stdout; dims/rank/validity report on stderr.
"""
import re
import sys

from metaflip_proto2 import T, recon, extend, project


def parse_terms(path):
    if path.endswith(".json"):
        return None, None  # handled by parse_perminov_json in main()
    with open(path) as stream:
        txt = stream.read()
    if re.search(r'^\s*(us|vs|ws)\[\d+\] = \d+', txt, re.M):
        us, vs, ws = {}, {}, {}
        for mm in re.finditer(r'(us|vs|ws)\[(\d+)\] = (\d+)', txt):
            {'us': us, 'vs': vs, 'ws': ws}[mm.group(1)][int(mm.group(2))] = int(mm.group(3))
        return [(us[r], vs[r], ws[r]) for r in sorted(us)], None
    if re.search(r'^\s*R \d+ \d+ \d+', txt, re.M):
        return [tuple(int(x) for x in mm.groups())
                for mm in re.finditer(r'^\s*R (\d+) (\d+) (\d+)', txt, re.M)], None
    return parse_mp_txt(txt)


def parse_perminov_json(path, n, m, p):
    """Perminov FastMatrixMultiplication JSON: keys n=[n,m,p], u/v/w are
    per-product coefficient rows. u over A and v over B are row-major; w is
    stored in trace form (entry e = k*n+i, i.e. C transposed) — brute-force
    validated against his 3x3x7 ZT scheme. Mod-2: keep odd coefficients."""
    import json
    d = json.load(open(path))
    assert list(d["n"]) == [n, m, p], f'dims {d["n"]} != {(n, m, p)}'
    out = []
    for ur, vr, wr in zip(d["u"], d["v"], d["w"]):
        u = sum(1 << i for i, c in enumerate(ur) if c % 2)
        v = sum(1 << i for i, c in enumerate(vr) if c % 2)
        w = sum(1 << ((e % n) * p + e // n) for e, c in enumerate(wr) if c % 2)
        if u and v and w:
            out.append((u, v, w))
    return out


def parse_mp_txt(txt):
    """MP txt terms are 1-indexed entries a<row><col>; needs dims to build masks,
    so return raw index triples and let mask building happen in orient()."""
    terms = []
    for line in txt.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        gg = re.match(r'\(([^)]*)\)\s*\*?\s*\(([^)]*)\)\s*\*?\s*\(([^)]*)\)', line)
        if not gg:
            continue
        fac = []
        for gi, letter in ((1, 'a'), (2, 'b'), (3, 'c')):
            entries = []
            grp = gg.group(gi)
            consumed = 0
            for em in re.finditer(rf'([+-]?)\s*(?:(\d+)\s*\*\s*)?{letter}(\d)(\d)', grp):
                consumed += len(em.group(0))
                coef = int(em.group(2) or 1)
                if coef % 2 == 1:   # mod-2 reduction: even coefficients vanish
                    ij = (int(em.group(3)) - 1, int(em.group(4)) - 1)
                    # same entry appearing twice (e.g. a11 + 2*a11) toggles
                    if ij in entries:
                        entries.remove(ij)
                    else:
                        entries.append(ij)
            fac.append(entries)
        terms.append(tuple(fac))
    return None, terms


def entries_to_masks(raw, n, m, p):
    # MP/KW txt writes the third factor in trace form: token c<r><c> means
    # c_{ki} (k over p, i over n) — validated against MP-93/MP-153. Our w
    # layout is (i,k) -> i*p+k, so token (r,c) lands at bit c*p+r.
    out = []
    for ae, be, ce in raw:
        u = sum(1 << (i * m + j) for i, j in ae)
        v = sum(1 << (j * p + k) for j, k in be)
        w = sum(1 << (c * p + r) for r, c in ce)
        out.append((u, v, w))
    return out


def remap(mask, rows, cols, f):
    """f(i,j) -> (bit index in target layout)"""
    r = 0
    for b in range(rows * cols):
        if (mask >> b) & 1:
            i, j = divmod(b, cols)
            r |= 1 << f(i, j)
    return r


def op_rot(S, n, m, p):
    # a_{ij} b_{jk} c_{ik}  with roles shifted: new A = old B (m x p), new B = old C... careful:
    # cyclic symmetry of matmul tensor: rank<n,m,p> = rank<m,p,n> via (u,v,w) -> (v,w,u),
    # where v (m x p) becomes the new u over A'=m x p, w (n x p) becomes new v over B'=p x n
    # AFTER transposing? Validation decides: try plain (v,w,u) with relabel.
    # New format (m,p,n): A' m x p (entry (j,k) at j*p+k) = old v layout — direct.
    # B' p x n (entry (k,i) at k*n+i) = old w (n x p, (i,k) at i*p+k) transposed.
    # C' m x n (entry (j,i) at j*n+i) = old u (n x m, (i,j) at i*m+j) transposed.
    out = set()
    for u, v, w in S:
        v2 = v
        w2 = remap(w, n, p, lambda i, k: k * n + i)
        u2 = remap(u, n, m, lambda i, j: j * n + i)
        t = (v2, w2, u2)
        out.discard(t) if t in out else out.add(t)
    return out, (m, p, n)


def op_swap(S, n, m, p):
    # C=AB  =>  C^T = B^T A^T : format (p,m,n); (u,v,w) -> (v^T, u^T, w^T)
    out = set()
    for u, v, w in S:
        u2 = remap(v, m, p, lambda j, k: k * m + j)   # B (m x p) -> A' (p x m)
        v2 = remap(u, n, m, lambda i, j: j * n + i)   # A (n x m) -> B' (m x n)
        w2 = remap(w, n, p, lambda i, k: k * n + i)   # C (n x p) -> C' (p x n)
        t = (u2, v2, w2)
        out.discard(t) if t in out else out.add(t)
    return out, (p, m, n)


def main():
    path, n, m, p = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
    ops = sys.argv[5:]
    masks, raw = parse_terms(path)
    if masks is None and raw is None:
        masks = parse_perminov_json(path, n, m, p)
    elif masks is None:
        masks = entries_to_masks(raw, n, m, p)
    S = set()
    for t in masks:
        if not (t[0] and t[1] and t[2]):
            continue  # factor vanished under mod-2 reduction -> term is zero
        S.discard(t) if t in S else S.add(t)
    dims = (n, m, p)
    if recon(S, *dims) != T(*dims):
        print(f"INPUT INVALID as <{dims}>", file=sys.stderr)
        sys.exit(1)
    print(f"loaded <{dims}> rank={len(S)} valid=True", file=sys.stderr)
    for op in ops:
        if op == 'rot':
            S, dims = op_rot(S, *dims)
        elif op == 'swap':
            S, dims = op_swap(S, *dims)
        elif op == 'proj':
            S = project(S, *dims)
            dims = (dims[0], dims[1], dims[2] - 1)
        elif op == 'ext':
            S = extend(S, *dims)
            dims = (dims[0], dims[1], dims[2] + 1)
        else:
            raise SystemExit(f"unknown op {op}")
        valid = recon(S, *dims) == T(*dims)
        print(f"after {op}: <{dims}> rank={len(S)} valid={valid}", file=sys.stderr)
        if not valid:
            sys.exit(1)
    terms = sorted(S)
    for k, (u, v, w) in enumerate(terms):
        print(f"us[{k}] = {u}")
    for k, (u, v, w) in enumerate(terms):
        print(f"vs[{k}] = {v}")
    for k, (u, v, w) in enumerate(terms):
        print(f"ws[{k}] = {w}")
    print(f"FINAL <{dims}> rank={len(terms)}", file=sys.stderr)


if __name__ == "__main__":
    main()
