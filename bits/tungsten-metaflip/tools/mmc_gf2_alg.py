"""GF(2) bilinear matmul schemes as bitmask term lists, with the composition primitives of
matmulcatalog re-implemented index-for-index (Compose, Recombination, SerendipitousBudProduct,
NonCubicBilinearAlgorithm orientations).

matmulcatalog (https://github.com/solven-eu/matmulcatalog, arXiv:2606.13408) stores many
schemes as recipes over atomic schemes. This module is the algebra half of its GF(2) replay
(`mmc_gf2_replay.py`); it does no I/O. Semantics follow the catalogue's Java sources, and every
primitive is checked against the full matrix-multiplication tensor in
`spec/mmc_gf2_alg_test.py`.

Term layout == MFW1 == matmulcatalog's internal row-major layout:
  a bit i*m+j = A[i][j], b bit j*p+k = B[j][k], c bit i*p+k = C[i][k].
"""
from collections import defaultdict
from functools import lru_cache
from itertools import product


def bits(x):
    while x:
        low = x & -x
        yield low.bit_length() - 1
        x ^= low


def popcount(x):
    return bin(x).count("1")


class Alg:
    __slots__ = ("n", "m", "p", "terms")

    def __init__(self, n, m, p, terms):
        self.n, self.m, self.p = n, m, p
        self.terms = terms

    @property
    def shape(self):
        return (self.n, self.m, self.p)

    @property
    def r(self):
        return len(self.terms)

    def __repr__(self):
        return "Alg<%d,%d,%d>=%d" % (self.n, self.m, self.p, self.r)


# ---------------------------------------------------------------- bit remaps
@lru_cache(maxsize=None)
def _ttab(R, C):
    """transpose table of an R x C bit matrix: bit r*C+c -> c*R+r"""
    return tuple((b % C) * R + b // C for b in range(R * C))


def remap(x, tab):
    y = 0
    while x:
        low = x & -x
        y |= 1 << tab[low.bit_length() - 1]
        x ^= low
    return y


_tcache = {}


def T(x, R, C):
    key = (x, R, C)
    v = _tcache.get(key)
    if v is None:
        v = remap(x, _ttab(R, C))
        if len(_tcache) > 4_000_000:
            _tcache.clear()
        _tcache[key] = v
    return v


def cyclic_shift(a):
    n, m, p = a.shape
    return Alg(m, p, n, [(b, T(c, n, p), T(u, n, m)) for u, b, c in a.terms])


def transpose(a):
    n, m, p = a.shape
    return Alg(p, m, n, [(T(b, m, p), T(u, n, m), T(c, n, p)) for u, b, c in a.terms])


def orient_as(a, shape):
    shape = tuple(shape)
    cur = a
    for _ in range(3):
        if cur.shape == shape:
            return cur
        cur = cyclic_shift(cur)
    t = transpose(a)
    for _ in range(3):
        if t.shape == shape:
            return t
        t = cyclic_shift(t)
    return None


ORIENT_PERMS = [(0, 1, 2), (1, 2, 0), (2, 0, 1), (2, 1, 0), (1, 0, 2), (0, 2, 1)]


def apply_orientation(a, code):
    x = a if code < 3 else transpose(a)
    for _ in range(code % 3):
        x = cyclic_shift(x)
    return x


def orient_by_perm(a, perm):
    return apply_orientation(a, ORIENT_PERMS.index(tuple(perm)))


def permute_axes(a, perm):
    """SymmetryTransforms.permuteAxes ("ABC->XYZ"/"NMP->XYZ"); None if not a bijection."""
    arrow = perm.find("->")
    if arrow < 0 or len(perm) - arrow - 2 < 3:
        return None
    tgt = perm[arrow + 2:arrow + 5].replace("N", "A").replace("M", "B").replace("P", "C")
    if tgt == "ABC":
        return a
    if tgt == "CBA":
        return transpose(a)
    if tgt == "BCA":
        return cyclic_shift(a)
    if tgt == "CAB":
        return cyclic_shift(cyclic_shift(a))
    if tgt == "ACB":
        return transpose(cyclic_shift(a))
    if tgt == "BAC":
        return cyclic_shift(transpose(a))
    return None


def s3_orbit_with_perms(a):
    """SymmetryTransforms.s3OrbitWithPerms order (dedup by exact content)."""
    out, seen = [], set()
    cur = a
    t = "ABC"
    for _ in range(3):
        for alg, perm in ((cur, "ABC->" + t), (transpose(cur), "ABC->" + t[::-1])):
            sig = (alg.shape, tuple(alg.terms))
            if sig not in seen:
                seen.add(sig)
                out.append((alg, perm))
        cur = cyclic_shift(cur)
        t = t[1:] + t[0]
    return out


def orientations(a):
    """LineageReplayer.orientations: distinct-shape orientations in its fixed order."""
    n, m, p = a.shape
    out = {}
    for s in ((n, m, p), (n, p, m), (m, n, p), (m, p, n), (p, n, m), (p, m, n)):
        if s in out:
            continue
        o = orient_as(a, s)
        if o is not None:
            out[s] = o
    return list(out.values())


def axis_permute(a, pA, pB, pC):
    n, m, p = a.shape
    tu = [0] * (n * m)
    tv = [0] * (m * p)
    tw = [0] * (n * p)
    for i in range(n):
        for j in range(m):
            tu[i * m + j] = pA[i] * m + pB[j]
    for j in range(m):
        for l in range(p):
            tv[j * p + l] = pB[j] * p + pC[l]
    for i in range(n):
        for l in range(p):
            tw[i * p + l] = pA[i] * p + pC[l]
    return Alg(n, m, p, [(remap(u, tu), remap(v, tv), remap(w, tw)) for u, v, w in a.terms])


def naive(n, m, p):
    return Alg(n, m, p, [(1 << (i * m + j), 1 << (j * p + k), 1 << (i * p + k))
                         for i, j, k in product(range(n), range(m), range(p))])


# ---------------------------------------------------------------- kron
_spread_cache = {}


def spread(x, ci, cols):
    """place bits of an (? x ci) matrix into rows of width `cols` (bit ib*ci+jb -> ib*cols+jb)."""
    if ci == cols:
        return x
    key = (x, ci, cols)
    v = _spread_cache.get(key)
    if v is None:
        v = 0
        for b in bits(x):
            ib, jb = divmod(b, ci)
            v |= 1 << (ib * cols + jb)
        if len(_spread_cache) > 4_000_000:
            _spread_cache.clear()
        _spread_cache[key] = v
    return v


def kron_bits(xo, xi, ro, co, ri, ci):
    """Compose.kronFactor on one column: outer (ro x co) (x) inner (ri x ci)."""
    cols = co * ci
    s = spread(xi, ci, cols)
    y = 0
    for b in bits(xo):
        Ib, Jb = divmod(b, co)
        y |= s << (Ib * ri * cols + Jb * ci)
    return y


def kron(o, i):
    n, m, p = o.n * i.n, o.m * i.m, o.p * i.p
    terms = []
    for uo, vo, wo in o.terms:
        for ui, vi, wi in i.terms:
            terms.append((kron_bits(uo, ui, o.n, o.m, i.n, i.m),
                          kron_bits(vo, vi, o.m, o.p, i.m, i.p),
                          kron_bits(wo, wi, o.n, o.p, i.n, i.p)))
    return Alg(n, m, p, terms)


# ---------------------------------------------------------------- concat
def _rewidth(x, oldc, newc, off=0):
    """row-major (R x oldc) -> (R x newc), columns shifted by `off`."""
    if oldc == newc and off == 0:
        return x
    y = 0
    for b in bits(x):
        r, c = divmod(b, oldc)
        y |= 1 << (r * newc + off + c)
    return y


def concat_right(L, R):  # ConcatCols (+p)
    if L.n != R.n or L.m != R.m:
        raise ValueError("concatRight shape mismatch")
    n, m, p1, p2 = L.n, L.m, L.p, R.p
    p = p1 + p2
    t = [(u, _rewidth(v, p1, p), _rewidth(w, p1, p)) for u, v, w in L.terms]
    t += [(u, _rewidth(v, p2, p, p1), _rewidth(w, p2, p, p1)) for u, v, w in R.terms]
    return Alg(n, m, p, t)


def concat_below(Tp, B):  # ConcatRows (+n)
    if Tp.m != B.m or Tp.p != B.p:
        raise ValueError("concatBelow shape mismatch")
    n1, m, p = Tp.n, Tp.m, Tp.p
    t = list(Tp.terms)
    t += [(u << (n1 * m), v, w << (n1 * p)) for u, v, w in B.terms]
    return Alg(n1 + B.n, m, p, t)


def concat_inner(L, R):  # SumInner (+m)
    if L.n != R.n or L.p != R.p:
        raise ValueError("concatInner shape mismatch")
    n, p, m1, m2 = L.n, L.p, L.m, R.m
    m = m1 + m2
    t = [(_rewidth(u, m1, m), v, w) for u, v, w in L.terms]
    t += [(_rewidth(u, m2, m, m1), v << (m1 * p), w) for u, v, w in R.terms]
    return Alg(n, m, p, t)


def robust_concat(a, b, axis):
    for oa in orientations(a):
        for ob in orientations(b):
            if axis == "P" and oa.n == ob.n and oa.m == ob.m:
                return concat_right(oa, ob)
            if axis == "N" and oa.m == ob.m and oa.p == ob.p:
                return concat_below(oa, ob)
            if axis == "M" and oa.n == ob.n and oa.p == ob.p:
                return concat_inner(oa, ob)
    raise ValueError("robustConcat: no compatible orientation %r %r" % (a, b))


def concat_cols(a, b):
    try:
        return concat_right(a, b)
    except ValueError:
        return robust_concat(a, b, "P")


def concat_rows(a, b):
    try:
        return concat_below(a, b)
    except ValueError:
        return robust_concat(a, b, "N")


def concat_inner_r(a, b):
    try:
        return concat_inner(a, b)
    except ValueError:
        return robust_concat(a, b, "M")


# ---------------------------------------------------------------- project
def project(a, keepN, keepM, keepP):
    n, m, p = a.shape
    n2, m2, p2 = len(keepN), len(keepM), len(keepP)

    def inv(keep, dim):
        v = [-1] * dim
        for i, k in enumerate(keep):
            v[k] = i
        return v
    iN, iM, iP = inv(keepN, n), inv(keepM, m), inv(keepP, p)

    def tab(invR, invC, oldC, newC):
        return [(invR[b // oldC] * newC + invC[b % oldC]) if invR[b // oldC] >= 0 and invC[b % oldC] >= 0 else -1
                for b in range(len(invR) * oldC)]
    tu, tv, tw = tab(iN, iM, m, m2), tab(iM, iP, p, p2), tab(iN, iP, p, p2)

    def rm(x, t):
        y = 0
        for b in bits(x):
            if t[b] >= 0:
                y |= 1 << t[b]
        return y
    out = []
    for u, v, w in a.terms:
        u2 = rm(u, tu)
        if not u2:
            continue
        v2 = rm(v, tv)
        if not v2:
            continue
        w2 = rm(w, tw)
        if not w2:
            continue
        out.append((u2, v2, w2))
    return Alg(n2, m2, p2, out)


# ---------------------------------------------------------------- recombination
def _max_alloc(x, cols, rowAlloc, colAlloc):
    mr = mc = 0
    for b in bits(x):
        i, j = divmod(b, cols)
        if rowAlloc[i] > mr:
            mr = rowAlloc[i]
        if colAlloc[j] > mc:
            mc = colAlloc[j]
    return mr, mc


def recomb_subshapes(base, allocA, allocB, allocC):
    out = []
    for u, v, w in base.terms:
        uu = _max_alloc(u, base.m, allocA, allocB)
        vv = _max_alloc(v, base.p, allocB, allocC)
        ww = _max_alloc(w, base.p, allocA, allocC)
        out.append((min(uu[0], ww[0]), min(uu[1], vv[0]), min(vv[1], ww[1])))
    return out


def _cum(a):
    c = [0]
    for x in a:
        c.append(c[-1] + x)
    return c


_mask_cache = {}


def _block_mask(brs, bcs, cols):
    key = (brs, bcs, cols)
    v = _mask_cache.get(key)
    if v is None:
        row = (1 << bcs) - 1
        v = 0
        for i in range(brs):
            v |= row << (i * cols)
        _mask_cache[key] = v
    return v


def _embed(base_x, sub_x, baseCols, subCols, rowAlloc, colAlloc, cumR, cumC, targetCols):
    s = spread(sub_x, subCols, targetCols)
    y = 0
    for b in bits(base_x):
        iB, jB = divmod(b, baseCols)
        y |= (s & _block_mask(rowAlloc[iB], colAlloc[jB], targetCols)) << (cumR[iB] * targetCols + cumC[jB])
    return y


def recombination(base, allocA, allocB, allocC, sub_lookup):
    """Recombination.constructWithAllocation (no peel). sub_lookup(shape)->Alg exactly that shape."""
    if base.shape != (len(allocA), len(allocB), len(allocC)):
        raise ValueError("allocation length must equal base dim")
    shapes = recomb_subshapes(base, allocA, allocB, allocC)
    tA, tB, tC = sum(allocA), sum(allocB), sum(allocC)
    cA, cB, cC = _cum(allocA), _cum(allocB), _cum(allocC)
    terms = []
    for (u, v, w), sz in zip(base.terms, shapes):
        if 0 in sz:
            continue
        sub = sub_lookup(sz)
        if sub is None or sub.shape != tuple(sz):
            raise ValueError("missing sub-algorithm %r" % (sz,))
        sA, sB, sC = sz
        for su, sv, sw in sub.terms:
            terms.append((_embed(u, su, base.m, sB, allocA, allocB, cA, cB, tB),
                          _embed(v, sv, base.p, sC, allocB, allocC, cB, cC, tC),
                          _embed(w, sw, base.p, sC, allocA, allocC, cA, cC, tC)))
    return Alg(tA, tB, tC, terms)


# ---------------------------------------------------------------- serendipitous product
ORDERINGS = [("U", "V", "W"), ("U", "W", "V"), ("V", "U", "W"),
             ("V", "W", "U"), ("W", "U", "V"), ("W", "V", "U")]
_FI = {"U": 0, "V": 1, "W": 2}


def find_buds(t1, order):
    """Greedy bud decomposition over GF(2): terms sharing an identical (nonzero) factor."""
    used = [False] * t1.r
    buds = []
    for typ in order:
        fi = _FI[typ]
        groups = {}
        for l, term in enumerate(t1.terms):
            if used[l]:
                continue
            groups.setdefault(term[fi], []).append(l)
        for g in groups.values():
            if len(g) >= 2:
                for l in g:
                    used[l] = True
                buds.append((typ, g))
    trivial = [l for l in range(t1.r) if not used[l]]
    return buds, trivial


def enlarged_shape(typ, k, n2, m2, p2):
    return (k * n2 if typ == "V" else n2, k * m2 if typ == "W" else m2, k * p2 if typ == "U" else p2)


def _rowblock(x, l, R, C):
    return (x >> (l * R * C)) & ((1 << (R * C)) - 1)


def _colblock(x, l, R, k, C):
    """column block l (width C) of an R x (k*C) matrix -> R x C."""
    y = 0
    mask = (1 << C) - 1
    W = k * C
    for r in range(R):
        y |= ((x >> (r * W + l * C)) & mask) << (r * C)
    return y


def build_bud_block(t1, typ, terms, s3, n2, m2, p2):
    n1, m1, p1 = t1.shape
    k = len(terms)
    fi = _FI[typ]
    shared = t1.terms[terms[0]][fi]
    out = []
    for sa, sb, sc in s3.terms:
        U = V = W = 0
        if typ == "U":  # s3 = <n2, m2, k p2>
            U = kron_bits(shared, sa, n1, m1, n2, m2)
            for l, t in enumerate(terms):
                _, vl, wl = t1.terms[t]
                V ^= kron_bits(vl, _colblock(sb, l, m2, k, p2), m1, p1, m2, p2)
                W ^= kron_bits(wl, _colblock(sc, l, n2, k, p2), n1, p1, n2, p2)
        elif typ == "V":  # s3 = <k n2, m2, p2>
            V = kron_bits(shared, sb, m1, p1, m2, p2)
            for l, t in enumerate(terms):
                ul, _, wl = t1.terms[t]
                U ^= kron_bits(ul, _rowblock(sa, l, n2, m2), n1, m1, n2, m2)
                W ^= kron_bits(wl, _rowblock(sc, l, n2, p2), n1, p1, n2, p2)
        else:  # W: s3 = <n2, k m2, p2>
            W = kron_bits(shared, sc, n1, p1, n2, p2)
            for l, t in enumerate(terms):
                ul, vl, _ = t1.terms[t]
                U ^= kron_bits(ul, _colblock(sa, l, n2, k, m2), n1, m1, n2, m2)
                V ^= kron_bits(vl, _rowblock(sb, l, m2, p2), m1, p1, m2, p2)
        out.append((U, V, W))
    return out


def serendipitous(t1, n2, m2, p2, resolve, rank_of):
    """SerendipitousBudProduct.productViaBudsBest over GF(2).

    resolve(shape)->Alg oriented exactly (or None); rank_of(shape)->predicted rank (or None).
    Chooses the cheapest ordering by predicted cost (plain Kronecker included)."""
    r2 = rank_of((n2, m2, p2))
    if r2 is None:
        raise ValueError("no inner <%d,%d,%d>" % (n2, m2, p2))
    cands = []
    for order in ORDERINGS:
        buds, trivial = find_buds(t1, order)
        if not buds:
            continue
        cost = len(trivial) * r2
        ok = True
        for typ, g in buds:
            re_ = rank_of(enlarged_shape(typ, len(g), n2, m2, p2))
            if re_ is None:
                ok = False
                break
            cost += re_
        if ok:
            cands.append((cost, order, buds, trivial))
    cands.sort(key=lambda c: c[0])
    s2 = resolve((n2, m2, p2))
    for cost, order, buds, trivial in cands:
        try:
            if cost >= t1.r * r2:
                break
            terms = []
            for i in trivial:
                terms.extend(kron(Alg(*t1.shape, [t1.terms[i]]), s2).terms)
            for typ, g in buds:
                s3 = resolve(enlarged_shape(typ, len(g), n2, m2, p2))
                if s3 is None:
                    raise ValueError("no enlarged")
                terms.extend(build_bud_block(t1, typ, g, s3, n2, m2, p2))
            return Alg(t1.n * n2, t1.m * m2, t1.p * p2, terms)
        except ValueError:
            continue
    return kron(t1, s2)


# ---------------------------------------------------------------- cleanup / verify
def clean(a):
    """Drop terms with a zero factor; cancel identical terms in pairs (mod 2)."""
    cnt = defaultdict(int)
    for t in a.terms:
        if t[0] and t[1] and t[2]:
            cnt[t] ^= 1
    return Alg(a.n, a.m, a.p, [t for t, c in cnt.items() if c])


def check_exact(a):
    """True iff sum of terms == <n,m,p> matmul tensor over GF(2)."""
    n, m, p = a.shape
    fibers = defaultdict(int)
    for u, v, w in a.terms:
        if u >> (n * m) or v >> (m * p) or w >> (n * p):
            return False
        vb = list(bits(v))
        for x in bits(u):
            for y in vb:
                fibers[x, y] ^= w
    for i in range(n):
        for j in range(m):
            for k in range(p):
                fibers[i * m + j, j * p + k] ^= 1 << (i * p + k)
    return not any(fibers.values())


# ---------------------------------------------------------------- optimized bud decomposition
def serendipitous_opt(t1, n2, m2, p2, resolve, rank_of, seed=12345, restarts=24):
    """Generalized serendipitous product over GF(2).

    Every term is assigned to one factor type (U/V/W); terms of the same type sharing an
    identical factor form a group, and each group is split optimally into buds (DP over
    bud sizes; a size-1 part is a plain Kronecker term). Local search over the type
    assignment, seeded by matmulcatalog's six greedy orderings. Each bud block is exactly
    SerendipitousBudProduct.buildBudBlock, so the result is a valid scheme (verified by caller).
    """
    import random
    r = t1.r
    R0 = rank_of((n2, m2, p2))
    if R0 is None:
        raise ValueError("no inner")
    maxk = {}
    cls = []
    for fi in range(3):
        ids = {}
        cls.append([ids.setdefault(t[fi], len(ids)) for t in t1.terms])
    sizes = [max((cls[fi].count(c) for c in set(cls[fi])), default=1) for fi in range(3)]
    typ_names = "UVW"
    Rk = []
    for fi in range(3):
        arr = [0, R0]
        for k in range(2, sizes[fi] + 1):
            v = rank_of(enlarged_shape(typ_names[fi], k, n2, m2, p2))
            arr.append(v if v is not None else 10 ** 12)
        Rk.append(arr)
    # f[fi][s] = optimal split cost, choice[fi][s] = first part
    f, choice = [], []
    for fi in range(3):
        ff, ch = [0], [0]
        for s in range(1, sizes[fi] + 1):
            best, bk = None, None
            for k in range(1, s + 1):
                c = Rk[fi][k] + ff[s - k]
                if best is None or c < best:
                    best, bk = c, k
            ff.append(best)
            ch.append(bk)
        f.append(ff)
        choice.append(ch)

    def total(assign):
        cnt = {}
        for l, fi in enumerate(assign):
            key = (fi, cls[fi][l])
            cnt[key] = cnt.get(key, 0) + 1
        return sum(f[fi][s] for (fi, _), s in cnt.items()), cnt

    def local_search(assign):
        cost, cnt = total(assign)
        improved = True
        while improved:
            improved = False
            for l in range(r):
                cur = assign[l]
                kc = (cur, cls[cur][l])
                sc = cnt[kc]
                base_rm = f[cur][sc - 1] - f[cur][sc]
                bestd, bestfi = 0, None
                for fi in range(3):
                    if fi == cur:
                        continue
                    kn = (fi, cls[fi][l])
                    sn = cnt.get(kn, 0)
                    d = base_rm + f[fi][sn + 1] - f[fi][sn]
                    if d < bestd:
                        bestd, bestfi = d, fi
                if bestfi is not None:
                    cnt[kc] -= 1
                    if not cnt[kc]:
                        del cnt[kc]
                    kn = (bestfi, cls[bestfi][l])
                    cnt[kn] = cnt.get(kn, 0) + 1
                    assign[l] = bestfi
                    cost += bestd
                    improved = True
        return cost, assign

    starts = []
    for order in ORDERINGS:
        buds, triv = find_buds(t1, order)
        a = [0] * r
        for typ, g in buds:
            for l in g:
                a[l] = _FI[typ]
        starts.append(a)
    rng = random.Random(seed)
    for _ in range(restarts):
        starts.append([rng.randrange(3) for _ in range(r)])
    best = None
    for a in starts:
        c, a2 = local_search(list(a))
        if best is None or c < best[0]:
            best = (c, list(a2))
    cost, assign = best
    if cost >= r * R0:
        return kron(t1, resolve((n2, m2, p2))), r * R0
    s2 = resolve((n2, m2, p2))
    groups = {}
    for l, fi in enumerate(assign):
        groups.setdefault((fi, cls[fi][l]), []).append(l)
    terms = []
    for (fi, _), g in groups.items():
        s = len(g)
        pos = 0
        while s:
            k = choice[fi][s]
            part = g[pos:pos + k]
            pos += k
            s -= k
            if k == 1:
                terms.extend(kron(Alg(*t1.shape, [t1.terms[part[0]]]), s2).terms)
            else:
                s3 = resolve(enlarged_shape(typ_names[fi], k, n2, m2, p2))
                if s3 is None:
                    raise ValueError("no enlarged")
                terms.extend(build_bud_block(t1, typ_names[fi], part, s3, n2, m2, p2))
    return Alg(t1.n * n2, t1.m * m2, t1.p * p2, terms), cost
