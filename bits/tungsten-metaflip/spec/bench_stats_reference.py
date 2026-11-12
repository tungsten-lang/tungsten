#!/usr/bin/env python3
"""Independent reference for the metascore statistics, with fixture generator and self-test.

Implements Wilson intervals, type-7 quantiles, ERT, the LCG63 bootstrap (single arm and
two-arm comparison), Kaplan-Meier, descent profiles and log-time AUC, performance profiles,
geometric-mean ratios, throughput, FNV-1a seeds and the fixed-point / LaTeX number formatters.

    python3 bench_stats_reference.py --selftest    check against independent computations
    python3 bench_stats_reference.py --generate    print fixtures/bench/stats_cases.tsv to stdout

Section numbers refer to the numbered definitions of the metascore statistics specification.
"""
import bisect
import hashlib
import math
import os
import random
import sys
import time
from fractions import Fraction

INF = math.inf
Z95 = 1.959963984540054
MASK63 = (1 << 63) - 1
MASK62 = (1 << 62) - 1
MASK64 = (1 << 64) - 1
LCG_A = 6364136223846793005
LCG_C = 1442695040888963407
FNV_OFFSET = 14695981039346656037
FNV_PRIME = 1099511628211
AXES = ("cpu", "instr", "proposals", "flips")
GRID_G = 49
GRID_D = 3
FIXTURE_SEED = 20260930
HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURE_PATH = os.path.join(HERE, "fixtures", "bench", "stats_cases.tsv")
FIXTURE_LIMIT = 150 * 1000


# ------------------------------------------------------------------ 1. Wilson interval

def wilson(k, n):
    """95% Wilson interval for k successes of n (n >= 1)."""
    z2 = Z95 * Z95
    p = k / n
    d = 1 + z2 / n
    center = (p + z2 / (2 * n)) / d
    half = Z95 * math.sqrt(p * (1 - p) / n + z2 / (4 * n * n)) / d
    return max(0.0, center - half), min(1.0, center + half)


# ------------------------------------------------------------------ 2. quantile (numpy type 7)

def quantile(xs, q):
    """Linear-interpolation quantile of the ascending list xs."""
    n = len(xs)
    h = (n - 1) * q
    lo = math.floor(h)
    return float(xs[lo] + (h - lo) * (xs[min(lo + 1, n - 1)] - xs[lo]))


# ------------------------------------------------------------------ 3. ERT

def ert_exact(costs, hits):
    """Exact ERT as a Fraction, None when no run hits."""
    sh = sum(hits)
    return Fraction(sum(costs), sh) if sh else None


def ert(costs, hits):
    """Float ERT (correctly rounded division of the integer sums), inf when no run hits."""
    sh = sum(hits)
    return sum(costs) / sh if sh else INF


# ------------------------------------------------------------------ 4. LCG63

class LCG63:
    def __init__(self, seed):
        self.s = seed & MASK63

    def next(self):
        self.s = (self.s * LCG_A + LCG_C) & MASK63
        return (self.s >> 32) & 0x7FFFFFFF

    def index(self, n):
        return (self.next() * n) >> 31


# ------------------------------------------------------------------ 5. bootstrap of the ERT

def bootstrap_sorted(costs, hits, seed, reps):
    """Ascending bootstrap ERT replicates (inf last) from one LCG63 stream."""
    n = len(costs)
    s = seed & MASK63
    out = []
    for _ in range(reps):
        sc = sh = 0
        for _ in range(n):
            s = (s * LCG_A + LCG_C) & MASK63
            i = (((s >> 32) & 0x7FFFFFFF) * n) >> 31
            sc += costs[i]
            sh += hits[i]
        out.append(sc / sh if sh else INF)
    out.sort()
    return out


def interval(v):
    """95% interval [v[k], v[m-1-k]] of an ascending list, k = m // 40."""
    k = len(v) // 40
    return v[k], v[len(v) - 1 - k]


def list_hash(v):
    return hashlib.sha256(",".join(repr(x) for x in v).encode("ascii")).hexdigest()


# ------------------------------------------------------------------ 6. two-arm comparison bootstrap

def compare_bootstrap(ca, ha, cb, hb, seed, reps):
    """Ascending kept ratio replicates and all difference replicates (A versus reference B)."""
    na, nb = len(ca), len(cb)
    s = seed & MASK63
    ratios, diffs = [], []
    for _ in range(reps):
        sca = sha = scb = shb = 0
        for _ in range(na):
            s = (s * LCG_A + LCG_C) & MASK63
            i = (((s >> 32) & 0x7FFFFFFF) * na) >> 31
            sca += ca[i]
            sha += ha[i]
        for _ in range(nb):
            s = (s * LCG_A + LCG_C) & MASK63
            i = (((s >> 32) & 0x7FFFFFFF) * nb) >> 31
            scb += cb[i]
            shb += hb[i]
        diffs.append(sha / na - shb / nb)
        if sha and shb:
            ratios.append((sca / sha) / (scb / shb))
        elif shb:
            ratios.append(INF)
        elif sha:
            ratios.append(0.0)
    ratios.sort()
    diffs.sort()
    return ratios, diffs


# ------------------------------------------------------------------ 7. Kaplan-Meier

def km_curve(obs):
    """[(t_j, S_j)] at each distinct event time; obs is a list of (time, event) with event 1 for a hit."""
    curve = []
    s = Fraction(1)
    for t in sorted({t for t, e in obs if e}):
        at_risk = sum(1 for u, _ in obs if u >= t)
        events = sum(1 for u, e in obs if e and u == t)
        s *= Fraction(at_risk - events, at_risk)
        curve.append((t, s))
    return curve


def km_time(curve, q):
    """Smallest event time whose exact survival value is at most (100-q)/100."""
    threshold = Fraction(100 - q, 100)
    for t, s in curve:
        if s <= threshold:
            return t
    return None


# ------------------------------------------------------------------ 8. descent profile and AUC

def grid_times(B, D=GRID_D, G=GRID_G):
    return [B * 10 ** (-D + g * D / (G - 1)) for g in range(G)]


def near_grid(t, grid, B):
    """True when t sits within a relative 1e-7 of a grid time (t == B_ms itself is exact)."""
    return t != B and any(abs(t - x) <= 1e-7 * x for x in grid)


def rank_at(ts, rs, r0, t):
    i = bisect.bisect_right(ts, t)
    return rs[i - 1] if i else r0


def descent_rows(sample):
    """[(t_g, q25, q50, q75)] of the run ranks on the log-spaced grid."""
    traces = [([t for t, _ in r.trace], [k for _, k in r.trace]) for r in sample.runs]
    rows = []
    for t in grid_times(sample.B):
        ranks = sorted(rank_at(ts, rs, sample.r0, t) for ts, rs in traces)
        rows.append((t, quantile(ranks, 0.25), quantile(ranks, 0.5), quantile(ranks, 0.75)))
    return rows


def auc_run(trace, r0, rstar, B):
    """Normalised log-time area of (rank - rstar)/(r0 - rstar) over [B/1000, B], exact over trace breakpoints."""
    span = r0 - rstar
    t0 = B / 1000
    level = r0
    i, m = 0, len(trace)
    while i < m and trace[i][0] <= t0:
        level = trace[i][1]
        i += 1
    acc = 0.0
    prev = math.log(t0)
    while i < m and trace[i][0] < B:
        t, k = trace[i]
        cur = math.log(t)
        acc += ((level - rstar) / span) * (cur - prev)
        prev, level = cur, k
        i += 1
    acc += ((level - rstar) / span) * (math.log(B) - prev)
    return acc / math.log(1000)


def auc_sample(sample):
    acc = 0.0
    for r in sample.runs:
        acc += auc_run(r.trace, sample.r0, sample.rstar, sample.B)
    return acc / sample.N


# ------------------------------------------------------------------ 9. performance profile, 10. geometric mean

def perf_profile(table, tasks, algos):
    """table[task][algo] is a float ERT or None (infinite). Returns (n_tasks, {algo: sorted finite ratios})."""
    included = [t for t in tasks if any(table[t][a] is not None for a in algos)]
    ratios = {a: [] for a in algos}
    for t in included:
        best = min(table[t][a] for a in algos if table[t][a] is not None)
        for a in algos:
            if table[t][a] is not None:
                ratios[a].append(table[t][a] / best)
    for a in algos:
        ratios[a].sort()
    return len(included), ratios


def rho(ratios_a, tau, n_tasks):
    return sum(1 for r in ratios_a if r <= tau) / n_tasks


def profile_steps(ratios_a, n_tasks):
    """[(tau, rho(tau))] at each distinct finite ratio, ascending."""
    return [(tau, rho(ratios_a, tau, n_tasks)) for tau in sorted(set(ratios_a))]


def geomean_ratio(table, tasks, algo, ref):
    """(exp(mean(log(ert_algo/ert_ref))), count) over tasks where both are finite; (None, 0) without any."""
    logs = [math.log(table[t][algo] / table[t][ref]) for t in tasks
            if table[t][algo] is not None and table[t][ref] is not None]
    if not logs:
        return None, 0
    acc = 0.0
    for x in logs:
        acc += x
    return math.exp(acc / len(logs)), len(logs)


# ------------------------------------------------------------------ 11. throughput

def throughput(runs, kind):
    """Sum of counts per cpu second over the runs that recorded the count; None when none did."""
    num = ms = 0
    seen = False
    for r in runs:
        c = getattr(r, kind)
        if c is not None:
            num += c
            ms += r.cpu
            seen = True
    if not seen or ms == 0:
        return None
    return float(Fraction(num * 1000, ms))


# ------------------------------------------------------------------ 12. FNV-1a seed hash

def fnv1a64(data):
    h = FNV_OFFSET
    for b in data:
        h ^= b
        h = (h * FNV_PRIME) & MASK64
    return h


def fnv_seed(task, algo):
    return fnv1a64((task + "\t" + algo).encode("utf-8")) & MASK62


# ------------------------------------------------------------------ 13. number formatting

def fmt_fixed(x, decimals):
    """Exact value of the double x, rounded half away from zero to `decimals` places; no exponent, no sign on zero."""
    f = Fraction(x)
    scaled = abs(f) * 10 ** decimals
    q, r = divmod(scaled.numerator, scaled.denominator)
    if 2 * r >= scaled.denominator:
        q += 1
    digits = str(q).rjust(decimals + 1, "0")
    body = digits[:-decimals] + "." + digits[-decimals:] if decimals > 0 else digits
    return "-" + body if f < 0 and q != 0 else body


def fmt_thousands_tex(n):
    s = str(abs(n))
    groups = []
    while len(s) > 3:
        groups.append(s[-3:])
        s = s[:-3]
    groups.append(s)
    return ("-" if n < 0 else "") + "{,}".join(reversed(groups))


# ------------------------------------------------------------------ data model

class Run:
    __slots__ = ("h", "cpu", "instr", "proposals", "flips", "trace")

    def __init__(self, h, cpu, instr, proposals, flips, trace):
        self.h, self.cpu = h, cpu
        self.instr, self.proposals, self.flips = instr, proposals, flips
        self.trace = list(trace)


class Sample:
    def __init__(self, name, B, r0, rstar, runs):
        self.name, self.B, self.r0, self.rstar = name, B, r0, rstar
        self.runs = list(runs)
        self.validate()

    @property
    def N(self):
        return len(self.runs)

    @property
    def hits(self):
        return [r.h for r in self.runs]

    def presence(self, axis):
        if axis == "cpu":
            return "full"
        n = sum(getattr(r, axis) is not None for r in self.runs)
        return "absent" if n == 0 else ("full" if n == self.N else "mixed")

    def costs(self, axis):
        """Per-run cost list on an axis: cpu uses B_ms for censored runs; None unless every run recorded the axis."""
        if axis == "cpu":
            return [r.cpu if r.h else self.B for r in self.runs]
        vals = [getattr(r, axis) for r in self.runs]
        return None if any(v is None for v in vals) else vals

    def km_obs(self):
        return [(r.cpu if r.h else self.B, r.h) for r in self.runs]

    def validate(self):
        assert self.r0 > self.rstar >= 0 and self.B >= 1 and self.runs
        for r in self.runs:
            assert r.h in (0, 1) and r.cpu >= 1
            for axis in AXES[1:]:
                v = getattr(r, axis)
                assert v is None or v >= 1
            prev_t, prev_k = 0, self.r0
            for t, k in r.trace:
                assert t >= prev_t and k < prev_k and k >= self.rstar, (self.name, r.trace)
                prev_t, prev_k = t, k
            if r.h:
                assert r.cpu <= self.B and r.trace and r.trace[-1] == (r.cpu, self.rstar), (self.name, r.trace)
                assert all(k > self.rstar for _, k in r.trace[:-1])
            else:
                assert all(k > self.rstar for _, k in r.trace)
        for axis in AXES:
            c = self.costs(axis)
            if c is not None:
                assert max(c) * self.N < 2 ** 53

    def check_grid(self):
        grid = grid_times(self.B)
        for r in self.runs:
            for t, _ in r.trace:
                assert not near_grid(t, grid, self.B), (self.name, t)


# ------------------------------------------------------------------ fixture tokens and lines

def tok(x):
    if x is None:
        return "none"
    return repr(x) if isinstance(x, float) else str(x)


def ert_tok(x):
    return "inf" if x is None or x == INF else tok(x)


def run_line(r):
    def c(v):
        return "-" if v is None else str(v)
    trace = ";".join(f"{t}:{k}" for t, k in r.trace) if r.trace else "-"
    return "\t".join(["R", str(r.h), str(r.cpu), c(r.instr), c(r.proposals), c(r.flips), trace])


def case_lines(s, be=(), dg=False):
    """CASE header, run lines and every expectation line of one sample."""
    out = [f"CASE\t{s.name}\t{s.N}\t{s.B}\t{s.r0}\t{s.rstar}"]
    out += [run_line(r) for r in s.runs]
    k = sum(s.hits)
    lo, hi = wilson(k, s.N)
    out.append(f"W\t{k}\t{s.N}\t{tok(lo)}\t{tok(hi)}")
    for axis in AXES:
        state = s.presence(axis)
        if state == "mixed":
            continue
        if state == "absent":
            out.append(f"E\t{axis}\tnone\tnone")
            continue
        fr = ert_exact(s.costs(axis), s.hits)
        if fr is None:
            out.append(f"E\t{axis}\tinf\tinf")
        else:
            out.append(f"E\t{axis}\t{tok(float(fr))}\t{fr.numerator}/{fr.denominator}")
    for axis, seed, reps in be:
        v = bootstrap_sorted(s.costs(axis), s.hits, seed, reps)
        lo, hi = interval(v)
        out.append(f"BE\t{axis}\t{seed}\t{reps}\t{tok(lo)}\t{tok(hi)}\t{list_hash(v)}")
    curve = km_curve(s.km_obs())
    out.append("KM")
    out += [f"KMS\t{t}\t{tok(float(sv))}" for t, sv in curve]
    out += [f"KMT\t{q}\t{tok(km_time(curve, q))}" for q in (25, 50, 75)]
    if dg:
        s.check_grid()
        out.append(f"DG\t{GRID_G}\t{GRID_D}")
        out += [f"DGR\t{tok(t)}\t{tok(a)}\t{tok(b)}\t{tok(c)}" for t, a, b, c in descent_rows(s)]
        out.append(f"AUC\t{tok(auc_sample(s))}")
    for kind in ("proposals", "flips"):
        out.append(f"TH\t{kind}\t{tok(throughput(s.runs, kind))}")
    return out


def pair_lines(a, b, seed, reps):
    ca, cb = a.costs("cpu"), b.costs("cpu")
    ratios, diffs = compare_bootstrap(ca, a.hits, cb, b.hits, seed, reps)
    ea, eb = ert(ca, a.hits), ert(cb, b.hits)
    point = None if INF in (ea, eb) else ea / eb
    dpoint = sum(a.hits) / a.N - sum(b.hits) / b.N
    out = [f"PAIR\t{a.name}\t{b.name}\t{seed}\t{reps}"]
    if ratios:
        rlo, rhi = interval(ratios)
        out.append(f"PR\t{tok(point)}\t{tok(rlo)}\t{tok(rhi)}\t{len(ratios)}")
        out.append(f"PRH\t{list_hash(ratios)}")
    else:
        out.append(f"PR\t{tok(point)}\tnone\tnone\t0")
        out.append("PRH\tnone")
    dlo, dhi = interval(diffs)
    out.append(f"PD\t{tok(dpoint)}\t{tok(dlo)}\t{tok(dhi)}")
    out.append(f"PDH\t{list_hash(diffs)}")
    return out


def profile_lines(name, tasks, algos, table, refs):
    n_tasks, ratios = perf_profile(table, tasks, algos)
    out = [f"PP\t{name}"]
    for t in tasks:
        for a in algos:
            out.append(f"PPT\t{t}\t{a}\t{ert_tok(table[t][a])}")
    for a in algos:
        out.append(f"PPO\t{a}\t{tok(rho(ratios[a], 1.0, n_tasks))}\t{n_tasks}")
    for a in algos:
        steps = profile_steps(ratios[a], n_tasks)
        out.append(f"PPS\t{a}\t" + (";".join(f"{tok(tau)}:{tok(r)}" for tau, r in steps) if steps else "-"))
    for ref in refs:
        for a in algos:
            v, n = geomean_ratio(table, tasks, a, ref)
            out.append(f"GM\t{a}\t{ref}\t{tok(v)}\t{n}")
    return out


# ------------------------------------------------------------------ deterministic data generator

class Gen:
    """Deterministic helpers on random.Random(seed).random() only."""

    def __init__(self, seed):
        self.r = random.Random(seed)

    def u(self):
        return self.r.random()

    def uni(self, a, b):
        return a + (b - a) * self.u()

    def rint(self, a, b):
        return a + int(self.u() * (b - a + 1))

    def expo(self, mean):
        return -mean * math.log(1.0 - self.u())

    def pick(self, seq):
        return seq[int(self.u() * len(seq))]

    def shuffle(self, seq):
        for i in range(len(seq) - 1, 0, -1):
            j = int(self.u() * (i + 1))
            seq[i], seq[j] = seq[j], seq[i]


def nudge(t, lo, hi, grid, B):
    """Nearest integer to t in [lo, hi] that keeps clear of every grid time."""
    if not near_grid(t, grid, B):
        return t
    for d in range(1, 64):
        for c in (t + d, t - d):
            if lo <= c <= hi and not near_grid(c, grid, B):
                return c
    raise ValueError("no free time near %d" % t)


def gen_trace(g, r0, rstar, t_last, kmax, hit, B, grid):
    """Rank descent: up to kmax entries at log-spaced times in [0, t_last]; a hit ends with (t_last, rstar)."""
    span = r0 - rstar
    k = g.rint(0, min(kmax, span - 1))
    ranks = []
    while len(ranks) < k:
        c = rstar + 1 + int(g.u() * (span - 1))
        if c not in ranks:
            ranks.append(c)
    ranks.sort(reverse=True)
    times = sorted(nudge(int(math.exp(g.uni(0.0, math.log(t_last + 2)))) - 1, 0, t_last, grid, B)
                   for _ in range(k))
    trace = list(zip(times, ranks))
    if hit:
        trace.append((t_last, rstar))
    return trace


GROUPS = {  # B_ms, r0, rstar, proposals per ms, instructions per ms
    "a": (2000, 27, 23, 900, 3_200_000),
    "b": (10000, 64, 49, 1500, 2_800_000),
    "c": (60000, 125, 93, 1100, 3_600_000),
    "d": (250000, 343, 250, 700, 3_000_000),
    "e": (3600000, 729, 486, 400, 2_500_000),
    "f": (120, 12, 8, 2500, 3_400_000),
    "g": (1000, 10, 6, 1800, 3_100_000),
}

# name, group, N, hits, mean hit time / B, traces, censored cpu, axes never recorded, axes recorded in some runs
SYN = [
    ("syn01", "a", 5, 0, 0.5, "full", "over", (), ()),
    ("syn02", "a", 8, 2, 0.6, "full", "exact", (), ()),
    ("syn03", "a", 12, 6, 0.3, "full", "under", (), ()),
    ("syn04", "a", 20, 15, 0.2, "hit", "exact", (), ()),
    ("syn05", "a", 16, 16, 0.1, "hit", "exact", ("instr",), ()),
    ("syn06", "a", 12, 11, 0.05, "hit", "over", (), ()),
    ("syn07", "a", 6, 1, 0.7, "full", "exact", (), ()),
    ("syn08", "b", 6, 6, 0.15, "full", "exact", (), ()),
    ("syn09", "b", 10, 1, 0.8, "full", "over", (), ()),
    ("syn10", "b", 15, 5, 0.4, "full", "exact", (), ()),
    ("syn11", "b", 25, 15, 0.3, "full", "exact", (), ()),
    ("syn12", "b", 24, 20, 0.2, "hit", "under", (), ()),
    ("syn13", "b", 10, 0, 0.5, "hit", "exact", (), ()),
    ("syn14", "b", 9, 5, 0.35, "hit", "exact", (), ("proposals",)),
    ("syn15", "c", 7, 3, 0.6, "full", "exact", (), ()),
    ("syn16", "c", 16, 9, 0.3, "full", "over", (), ()),
    ("syn17", "c", 24, 23, 0.1, "full", "exact", (), ()),
    ("syn18", "c", 30, 10, 0.5, "hit", "exact", (), ()),
    ("syn19", "c", 120, 84, 0.25, "hit", "exact", (), ()),
    ("syn20", "c", 10, 10, 0.2, "hit", "exact", (), ()),
    ("syn21", "d", 5, 3, 0.4, "full", "exact", (), ()),
    ("syn22", "d", 11, 2, 0.9, "hit", "under", (), ()),
    ("syn23", "d", 18, 14, 0.2, "hit", "exact", ("proposals", "flips"), ()),
    ("syn24", "d", 20, 9, 0.5, "hit", "over", (), ()),
    ("syn25", "d", 8, 0, 0.5, "hit", "exact", (), ()),
    ("syn26", "e", 5, 2, 0.5, "hit", "exact", (), ()),
    ("syn27", "e", 9, 6, 0.3, "full", "over", (), ()),
    ("syn28", "e", 14, 2, 0.7, "hit", "exact", (), ()),
    ("syn29", "e", 6, 6, 0.1, "full", "exact", (), ()),
    ("syn30", "e", 12, 6, 0.4, "hit", "exact", ("flips",), ("instr",)),
    ("syn31", "f", 10, 5, 0.25, "full", "over", (), ()),
    ("syn32", "f", 20, 16, 0.12, "hit", "exact", (), ()),
    ("syn33", "f", 24, 14, 0.3, "full", "exact", (), ()),
    ("syn34", "f", 16, 16, 0.06, "hit", "exact", (), ("flips",)),
    ("syn35", "f", 13, 4, 0.5, "hit", "exact", (), ()),
    ("syn36", "g", 40, 20, 0.4, "hit", "exact", (), ()),
    ("syn37", "g", 25, 22, 0.15, "full", "exact", (), ()),
    ("syn38", "g", 30, 8, 0.6, "hit", "under", (), ()),
    ("syn39", "g", 17, 12, 0.25, "full", "exact", (), ()),
    ("syn40", "g", 27, 5, 0.7, "hit", "exact", (), ()),
]

# bootstrap plan: sample -> [(axis, replicates)]; replicate counts 199 and 119 give k = R // 40 = 4 and 2
BE_PLAN = {
    "syn01": [("cpu", 200)], "syn02": [("cpu", 200)], "syn03": [("cpu", 2000)], "syn04": [("cpu", 2000)],
    "syn05": [("flips", 2000)], "syn07": [("cpu", 2000)], "syn08": [("cpu", 200)], "syn09": [("cpu", 2000)],
    "syn06": [("cpu", 119)], "syn10": [("cpu", 200)], "syn11": [("instr", 2000)], "syn12": [("proposals", 2000)],
    "syn16": [("flips", 2000)], "syn19": [("cpu", 2000)], "syn20": [("cpu", 199)], "syn21": [("cpu", 200)],
    "syn24": [("cpu", 2000)],
    "syn27": [("cpu", 2000)], "syn28": [("cpu", 200)], "syn31": [("cpu", 2000)], "syn33": [("cpu", 2000)],
    "syn34": [("cpu", 200)], "syn36": [("cpu", 2000)], "syn37": [("instr", 2000)], "syn40": [("cpu", 200)],
}

# comparison plan: (A, B, replicates)
PAIR_PLAN = [
    ("syn03", "syn04", 2000), ("syn04", "syn03", 2000), ("syn05", "syn06", 2000),
    ("syn02", "syn01", 2000), ("syn01", "syn02", 2000), ("syn01", "syn13", 200),
    ("syn07", "syn03", 2000), ("syn03", "syn07", 2000), ("syn09", "syn09", 200),
    ("syn18", "syn19", 2000), ("syn31", "syn32", 200), ("syn08", "syn20", 200),
    ("syn36", "syn37", 2000), ("syn22", "syn23", 200), ("syn11", "syn10", 119),
]


def gen_sample(g, spec):
    name, grp, n, k_hits, scale, style, cpu_mode, absent, mixed = spec
    B, r0, rstar, prate, irate = GROUPS[grp]
    grid = grid_times(B)
    order = list(range(n))
    g.shuffle(order)
    hit_set = set(order[:k_hits])
    runs = []
    for i in range(n):
        is_hit = i in hit_set
        if is_hit:
            t = B
            for _ in range(40):
                c = int(g.expo(scale * B) + 0.5)
                if 1 <= c <= B:
                    t = c
                    break
            cpu = nudge(t, 1, B, grid, B)
        elif cpu_mode == "over":
            cpu = B + int(g.uni(1.0, max(1.5, 0.03 * B)))
        elif cpu_mode == "under":
            cpu = B - int(g.uni(1.0, max(1.5, 0.02 * B)))
        else:
            cpu = B
        props = max(1, int(cpu * prate * g.uni(0.7, 1.3)))
        flips = max(1, int(props * g.uni(0.05, 0.4)))
        instr = max(1, int(cpu * irate * g.uni(0.8, 1.2)))
        if style == "full":
            trace = gen_trace(g, r0, rstar, cpu if is_hit else min(cpu, B), 4 if is_hit else 5, is_hit, B, grid)
            if not is_hit and cpu_mode == "over" and g.u() < 0.5:
                last = trace[-1][1] if trace else r0
                if last - rstar >= 2:
                    trace.append((cpu, rstar + 1 + int(g.u() * (last - rstar - 1))))
        else:
            trace = [(cpu, rstar)] if is_hit else []
        vals = {"instr": instr, "proposals": props, "flips": flips}
        for axis in absent:
            vals[axis] = None
        for axis in mixed:
            if i % 3 == 1:
                vals[axis] = None
        runs.append(Run(1 if is_hit else 0, cpu, vals["instr"], vals["proposals"], vals["flips"], trace))
    return Sample(name, B, r0, rstar, runs)


# ------------------------------------------------------------------ hand-worked samples

def hand_samples():
    """(sample, working comments, bootstrap specs, has descent block) for each hand-worked case."""
    out = []

    s = Sample("hand_mixed4", 1000, 10, 6, [
        Run(1, 200, 2000, 40, 10, [(50, 9), (120, 8), (200, 6)]),
        Run(0, 1000, 9000, 210, 60, [(30, 9), (700, 8)]),
        Run(1, 600, 5000, 120, 30, [(5, 9), (110, 8), (300, 7), (600, 6)]),
        Run(0, 1200, 10000, 250, 70, []),
    ])
    out.append((s, [
        "hand_mixed4: N=4, hits in runs 1 and 3; B=1000, r0=10, r*=6, f(rank) = (rank-6)/4.",
        "  W(2,4): p = 1/2 so center = 1/2; half = z*sqrt(1/16 + z^2/64)/(1 + z^2/4) = 0.349961; interval (0.150039, 0.849961).",
        "  E cpu: costs 200, 1000 (B), 600, 1000 (B) -> 2800/2 = 1400/1; run 4 records 1200 ms and its censored cost is B.",
        "  E instr: (2000+9000+5000+10000)/2 = 13000/1.  E proposals: (40+210+120+250)/2 = 310/1.  E flips: (10+60+30+70)/2 = 85/1.",
        "  KM: (200,1) (600,1) (1000,0) (1000,0): S(200) = 1-1/4 = 3/4; S(600) = 3/4*(1-1/3) = 1/2; T25 = 200, T50 = 600, T75 = none.",
        "  TH: proposals 620 per (200+1000+600+1200 = 3000 ms = 3 s) = 620/3; flips 170/3.",
        "  DG g=0 (t=1): every run is at r0, all quartiles 10.0.  g=48 (t=1000): ranks 6,8,6,10 -> sorted 6,6,8,10:",
        "     q25 = 6.0, q50 = 6+0.5*(8-6) = 7.0, q75 = 8+0.25*(10-8) = 8.5.",
        "  AUC per run: run1 = (ln 50 + 0.75 ln 2.4 + 0.5 ln(5/3))/ln 1000 = 0.698351;",
        "     run2 = (ln 30 + 0.75 ln(70/3) + 0.5 ln(10/7))/ln 1000 = 0.860185;",
        "     run3 = (ln 5 + 0.75 ln 22 + 0.5 ln(30/11) + 0.25 ln 2)/ln 1000 = 0.666303; run4 = 1 (no trace); mean = 0.806210.",
    ], [("cpu", 16, 200)], True))

    s = Sample("hand_none_hit", 500, 5, 2, [
        Run(0, 500, 4000, 100, 20, [(40, 4), (300, 3)]),
        Run(0, 510, 4100, 104, 21, [(7, 4)]),
        Run(0, 490, 3900, 96, 19, []),
        Run(0, 500, 4000, 100, 20, [(250, 3)]),
    ])
    out.append((s, [
        "hand_none_hit: N=4, no run hits; B=500, r0=5, r*=2.",
        "  W(0,4): lo = 0; hi = z^2/(n+z^2) = 0.489891.",
        "  E: no hit -> inf on every axis.  KM: no event -> no KMS line, T25 = T50 = T75 = none.",
        "  BE cpu: no replicate contains a hit -> 200 x inf; interval [inf, inf]; hash of the text inf,inf,...,inf.",
        "  TH: proposals (100+104+96+100) = 400 per (500+510+490+500 = 2000 ms = 2 s) = 200.0; flips 80/2 = 40.0.",
    ], [("cpu", 11, 200)], False))

    s = Sample("hand_all_hit", 800, 8, 4, [
        Run(1, 100, 1000, 10, 5, [(100, 4)]),
        Run(1, 200, 2000, 20, 10, [(30, 6), (200, 4)]),
        Run(1, 300, 3000, 30, 15, [(300, 4)]),
        Run(1, 400, 4000, 40, 20, [(10, 7), (400, 4)]),
    ])
    out.append((s, [
        "hand_all_hit: N=4, hits at 100, 200, 300, 400 ms; B=800, r0=8, r*=4.",
        "  W(4,4): lo = n/(n+z^2) = 0.510109; hi = 1.",
        "  E cpu: (100+200+300+400)/4 = 250/1; instr 10000/4 = 2500/1; proposals 100/4 = 25/1; flips 50/4 = 25/2.",
        "  KM: S = 3/4, 1/2, 1/4, 0 at 100, 200, 300, 400 -> T25 = 100 (S = 3/4 meets the threshold exactly), T50 = 200, T75 = 300.",
        "  TH: proposals 100 per (1000 ms = 1 s) = 100.0; flips 50.0.",
    ], [("cpu", 12, 200), ("flips", 13, 200)], False))

    s = Sample("hand_tie_km", 1000, 8, 6, [
        Run(1, 250, 2500, 50, 10, [(250, 6)]),
        Run(1, 400, 4000, 80, 16, [(120, 7), (400, 6)]),
        Run(1, 400, 4100, 82, 17, [(400, 6)]),
        Run(1, 1000, 10000, 200, 40, [(900, 7), (1000, 6)]),
        Run(0, 1000, 10000, 200, 40, []),
        Run(0, 1000, 10000, 200, 40, [(500, 7)]),
    ])
    out.append((s, [
        "hand_tie_km: N=6; hits at 250, 400, 400 and 1000 (= B), two runs censored at B=1000; r0=8, r*=6.",
        "  W(4,6) = (0.299993, 0.903229).",
        "  E cpu: (250+400+400+1000+1000+1000)/4 = 4050/4 = 2025/2 = 1012.5.",
        "  KM: t=250: n=6, d=1 -> S = 5/6; t=400: n=5, d=2 -> S = 5/6*3/5 = 1/2; t=1000: n=3 (the hit and both censored runs), d=1 -> S = 1/2*2/3 = 1/3.",
        "  T25 = 400; T50 = 400 (S = 1/2 meets the threshold exactly); T75 = none (1/3 > 1/4).",
        "  DG g=48 (t=1000): the entry 1000:6 of run 4 counts (its time <= t); ranks 6,6,6,6,7,8 -> q25 = 6.0, q50 = 6.0, q75 = 6+0.75*(7-6) = 6.75.",
        "  AUC (f = (rank-6)/2, t0 = 1; an entry at t = B adds no area): run1 = ln 250/ln 1000 = 0.799313; run2 = (ln 120 + 0.5 ln(10/3))/ln 1000 = 0.780207;",
        "     run3 = ln 400/ln 1000 = 0.867353; run4 = (ln 900 + 0.5 ln(10/9))/ln 1000 = 0.992374; run5 = 1; run6 = (ln 500 + 0.5 ln 2)/ln 1000 = 0.949828; mean = 0.898179.",
    ], [], True))

    s = Sample("hand_auc_t0", 2500, 11, 1, [
        Run(0, 2500, 20000, 500, 100, []),
        Run(1, 500, 4000, 100, 20, [(1, 8), (2, 6), (5, 5), (50, 3), (500, 1)]),
        Run(0, 2500, 20000, 480, 90, [(2, 9), (30, 7), (300, 5)]),
    ])
    out.append((s, [
        "hand_auc_t0: N=3, B=2500 so t0 = B/1000 = 2.5; r0=11, r*=1, f(rank) = (rank-1)/10.",
        "  Run A censored without trace (f = 1); run B hits at 500 ms; run C censored.",
        "  W(1,3) = (0.061492, 0.792340).  E cpu: (2500+500+2500)/1 = 5500/1.",
        "  KM: one event at 500 with n=3 -> S = 2/3; T25 = 500 (2/3 <= 3/4), T50 = none, T75 = none.",
        "  Run B trace 1:8;2:6;5:5;50:3;500:1: the entries at 1 and 2 precede t0 and leave level 6 (f = 0.5) at t0.",
        "     pieces [2.5,5) f=0.5, [5,50) f=0.4, [50,500) f=0.2, [500,2500] f=0 -> AUC_B = (0.5 ln 2 + 0.6 ln 10)/ln 1000 = 0.5*log10(2)/3 + 0.2 = 0.250172.",
        "  Run C trace 2:9;30:7;300:5: the entry at 2 precedes t0 (f = 0.8 at t0).",
        "     pieces [2.5,30) f=0.8, [30,300) f=0.6, [300,2500] f=0.4 -> AUC_C = (0.8 ln 12 + 0.6 ln 10 + 0.4 ln(25/3))/ln 1000 = 0.610557.",
        "  Sample AUC = (1 + 0.250172 + 0.610557)/3 = 0.620243.",
        "  DG g=0 (t=2.5): ranks A 11, B 6, C 9 -> sorted 6,9,11: q25 = 6+0.5*(9-6) = 7.5, q50 = 9.0, q75 = 9+0.5*(11-9) = 10.0.",
        "     g=48 (t=2500): ranks 11, 1, 5 -> sorted 1,5,11: q25 = 1+0.5*(5-1) = 3.0, q50 = 5.0, q75 = 5+0.5*(11-5) = 8.0.",
    ], [], True))

    s = Sample("hand_counts_missing", 2000, 9, 5, [
        Run(1, 500, 4000, 100, None, [(500, 5)]),
        Run(0, 2000, 16000, None, None, [(90, 8)]),
        Run(1, 1500, 12000, 300, None, [(200, 7), (1500, 5)]),
        Run(0, 2100, 17000, None, None, []),
        Run(1, 1000, 8000, 250, None, [(1000, 5)]),
    ])
    out.append((s, [
        "hand_counts_missing: N=5, B=2000, r0=9, r*=5; proposals recorded in runs 1, 3, 5 only; flips never recorded.",
        "  E cpu: (500+2000+1500+2000+1000)/3 = 7000/3.  E instr: (4000+16000+12000+17000+8000)/3 = 57000/3 = 19000/1.",
        "  E flips: none (axis absent).  No E proposals line (recorded in some runs only).",
        "  TH proposals: (100+300+250) = 650 per runs 1, 3, 5 with 500+1500+1000 = 3000 ms = 3 s -> 650/3 = 216.666...; TH flips: none.",
    ], [], False))

    s = Sample("hand_n1_hit", 100, 4, 2, [
        Run(1, 40, 400, 80, 20, [(12, 3), (40, 2)]),
    ])
    out.append((s, [
        "hand_n1_hit: N=1, one hit at 40 ms; B=100, r0=4, r*=2.",
        "  W(1,1) = (0.206549, 1).  E cpu = 40/1.  KM: S(40) = 1 - 1/1 = 0; T25 = T50 = T75 = 40.",
        "  BE cpu: every replicate resamples the single run -> 200 x 40.0; interval [40.0, 40.0].",
        "  DG: one run, so every quartile equals its rank: 4.0 for t < 12, 3.0 for 12 <= t < 40, 2.0 for t >= 40.",
    ], [("cpu", 14, 200)], True))

    s = Sample("hand_n1_cens", 100, 4, 2, [
        Run(0, 100, 900, 180, 40, [(25, 3)]),
    ])
    out.append((s, [
        "hand_n1_cens: N=1, censored; B=100, r0=4, r*=2.",
        "  W(0,1) = (0, z^2/(1+z^2)) = (0, 0.793451).  E: inf on every axis.  KM: no event.  BE cpu: 200 x inf.",
    ], [("cpu", 15, 200)], False))
    return out


# ------------------------------------------------------------------ global record tables

WILSON_CASES = [
    (0, 1), (1, 1), (0, 2), (1, 2), (2, 2), (0, 4), (2, 4), (4, 4), (1, 5), (3, 5), (0, 10), (1, 10),
    (5, 10), (9, 10), (10, 10), (3, 20), (10, 20), (19, 20), (7, 30), (15, 40), (1, 50), (25, 50),
    (49, 50), (30, 100), (50, 100), (95, 100), (0, 120), (60, 120), (120, 120), (0, 1000), (1, 1000),
    (500, 1000), (999, 1000), (1000, 1000), (123, 4567),
]

QUANTILE_FIXED = [
    (0.5, [1, 2, 3, 4]), (0.25, [1, 2, 3, 4]), (0.75, [1, 2, 3, 4]), (0.0, [5, 6, 7]), (1.0, [5, 6, 7]),
    (0.5, [42]), (0.25, [3, 3, 3, 3, 3]), (0.5, [1, 100]), (0.9, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
    (0.5, [0.1, 0.2, 0.7]), (0.25, [0.1, 0.2, 0.7]), (0.75, [0.1, 0.2, 0.7]), (0.1, [-5, -2, 0, 3, 8]),
    (0.5, [2, 4, 4, 4, 5, 5, 7, 9]), (0.25, [2, 4, 4, 4, 5, 5, 7, 9]), (0.75, [2, 4, 4, 4, 5, 5, 7, 9]),
]

LCG_SEEDS = [0, 1, 2, 42, 20260930, 2 ** 31 - 1, 2 ** 31, 2 ** 32 + 1, 2 ** 62 - 1, 2 ** 62, 2 ** 63 - 1]
LCG_MASKED_SEEDS = [2 ** 63, 2 ** 64 - 1, -1, -12345]

HASH_STRINGS = [
    "9x9x9@perminov486\tmetaflip/V0", "9x9x9@perminov486\tmetaflip/V1", "3x3x3@23\tmetaflip/V0",
    "4x4x4@49\tmetaflip/V2", "5x5x5@93\tanneal/plain", "6x6x6@153\tflipgraph/base", "\t", "a\tb",
    "naïve\tμ-flip", "x" * 60 + "\t" + "y" * 60,
]
FNV_PLAIN = ["a", "foobar", "hello world"]

INDEX_CASES = [(1, 4), (42, 4), (16, 4), (7, 10), (20260930, 25), (fnv_seed("3x3x3@23", "metaflip/V0"), 12), (99, 120)]

FIXED_CASES = [
    (0.125, 2), (0.135, 2), (2.675, 2), (1.005, 2), (0.5, 0), (1.5, 0),
    (2.5, 0), (-2.5, 0), (-0.125, 2), (0.0, 2), (-0.0, 2), (-0.001, 2),
    (0.001, 2), (0.005, 2), (0.015, 2), (123456.789, 1), (999.9999, 2),
    (1e-05, 5), (1.5e17, 1), (3.14159265358979, 4), (0.1, 20), (1234.5, 0),
    (99.995, 2), (0.3, 1), (2.0, 3), (100.0, 0), (12345678.9, 2),
    (0.9999, 2), (-1234.5678, 2), (1e21, 2), (0.000123, 5), (7.0, 0),
]

THOUSANDS_CASES = [
    0, 7, 999, 1000, 1150, 12345, 99999, 100000, 123456, 999999, 1000000, 12345678, 1234567890,
    2 ** 40, 2 ** 53, 2 ** 62, -1, -999, -1000, -1150, -12345678, 4567, 65536, 10 ** 12,
]

PP_ALGOS_A = ["metaflip/V0", "metaflip/V1", "metaflip/V2", "flipgraph/base", "anneal/plain"]
PP_TASKS_A = ["2x2x2@7", "2x3x3@15", "3x3x3@23", "3x3x4@29", "3x4x4@38", "4x4x4@49",
              "4x4x5@61", "4x5x5@76", "5x5x5@93", "5x5x6@110", "6x6x6@153", "9x9x9@486"]
PP_ALGOS_B = ["alpha", "beta", "gamma", "delta", "epsilon"]
PP_TASKS_B = ["u%02d" % i for i in range(1, 13)]
PP_TABLE_B = [  # ERT per algorithm; None = infinite
    [100.0, 200.0, 100.0, 400.0, None],
    [300.0, 150.0, None, 150.0, None],
    [None, None, None, None, None],
    [50.0, 75.0, 50.0, 50.0, None],
    [1000.0, None, 2000.0, 4000.0, None],
    [10.0, 10.0, 10.0, 20.0, None],
    [None, 900.0, 450.0, None, 1500.0],
    [250.0, 500.0, 750.0, 1000.0, None],
    [60.0, 40.0, 80.0, None, None],
    [None, None, 300.0, None, 800.0],
    [128.0, 256.0, 512.0, 1024.0, None],
    [90.0, 45.0, 90.0, 180.0, None],
]


def make_table_a(g):
    """12 tasks x 5 algorithms of synthetic ERTs (ms): infinite entries, a tie, an all-infinite task and an all-infinite algorithm."""
    factors = [1.0, 0.7, 1.6, 3.2, 12.0]
    table = {}
    for ti, task in enumerate(PP_TASKS_A):
        base = 10 ** g.uni(3.0, 8.0)
        row = {}
        for ai, algo in enumerate(PP_ALGOS_A):
            v = round(base * factors[ai] * math.exp(g.uni(-0.6, 0.6)), 3)
            p_inf = min(0.9, 0.04 + 0.035 * ti + 0.1 * ai)
            row[algo] = None if g.u() < p_inf else v
        table[task] = row
    table[PP_TASKS_A[5]] = {a: None for a in PP_ALGOS_A}
    row = table[PP_TASKS_A[2]]
    row[PP_ALGOS_A[1]] = row[PP_ALGOS_A[0]] = 4321.5
    for task in PP_TASKS_A:
        table[task][PP_ALGOS_A[4]] = None
    return table


def make_table_b():
    return {t: dict(zip(PP_ALGOS_B, row)) for t, row in zip(PP_TASKS_B, PP_TABLE_B)}


# ------------------------------------------------------------------ fixture text

HEADER = r"""# metascore statistics fixture -- expected values from bench_stats_reference.py (generated; regenerate, do not edit)
# Regenerate: python3 bits/tungsten-metaflip/spec/bench_stats_reference.py --generate > bits/tungsten-metaflip/spec/fixtures/bench/stats_cases.tsv
#
# FORMAT
#   A line is blank, a '#' comment, or TAB-separated fields whose first field is a record tag. Fields split on TAB only.
#   Integers are plain decimal. Floats are Python repr: shortest round-trip IEEE-754 binary64; an exponent (1e-05, 1.5e+17) may appear.
#   inf = positive infinity (an infinite ERT-like value or interval end); none = undefined; '-' = absent value or empty list.
#   Comparison: integers, strings, fractions and hashes compare exactly; floats compare with |got - want| <= 1e-12 * max(1, |want|).
#   In H/HF strings a TAB is written as the two characters \t (backslash, t); no other escapes occur.
#   Task, algorithm and sample names contain no whitespace. Sample and table data are synthetic.
#
# GLOBAL RECORDS
#   W     k n lo hi                       Wilson 95% interval for k successes of n (z = 1.959963984540054)
#   Q     q n v1,...,vn result            type-7 quantile at q of the ascending list v1..vn; result is a float
#   L     seed o1,...,o8                  first 8 outputs of LCG63 started from seed
#   IX    seed n i1,...,i16               first 16 index draws in [0,n) from LCG63 started from seed
#   H     string hash                     fnv1a64(utf8(string)) & (2^62-1), decimal
#   HF    string hex64                    raw FNV-1a 64-bit value, 16 lowercase hex digits
#   F     x decimals expected             fmt_fixed(x, decimals)
#   T     n expected                      fmt_thousands_tex(n)
#
# SAMPLE RECORDS (CASE opens a sample; its lines run until the next CASE, PAIR or PP)
#   CASE  name N B_ms r0 rstar            budget B_ms (integer ms), start rank r0, target rank rstar; N R lines follow
#   R     h cpu_ms instr proposals flips trace
#                                         one run: h in {0,1}; cpu_ms = time to target (hit) or total spent (censored, recorded as measured);
#                                         instr, proposals, flips are counts or '-' when not recorded;
#                                         trace = t_ms:rank pairs joined by ';' (non-decreasing time, strictly falling rank) or '-';
#                                         a hit run's trace ends with cpu_ms:rstar
#   W     k n lo hi                       Wilson interval for the sample's (hits, N)
#   E     axis ert exact                  ERT on axis cpu|instr|proposals|flips; exact = num/den in lowest terms;
#                                         inf inf when no run hits; none none when no run recorded the axis;
#                                         no line when only some runs recorded it
#   BE    axis seed R lo hi sha           bootstrap 95% interval of the ERT on axis; sha = sha256 of the ascending replicate list
#   KM                                    opens the Kaplan-Meier block
#   KMS   t_ms S                          survival value after each distinct hit time (ascending)
#   KMT   q value                         T_q for q = 25, 50, 75: smallest event time with S <= (100-q)/100, or none
#   DG    G D                             opens the descent block: G grid points over D decades (49, 3)
#   DGR   t_ms q25 q50 q75                grid time and quartiles of the run ranks (G lines)
#   AUC   value                           mean over runs of the log-time area under (rank - rstar)/(r0 - rstar)
#   TH    kind value                      proposals|flips per cpu second over the runs that recorded the count, or none
#
# COMPARISON RECORDS (PAIR names two earlier samples; PR/PRH/PD/PDH follow)
#   PAIR  nameA nameB seed R              A versus reference B on the cpu axis
#   PR    ratio rlo rhi rkept             point ERT ratio (none if either ERT is infinite), interval of the kept replicates, their count
#   PRH   sha                             sha256 of the ascending kept ratio replicates ('none' when none are kept)
#   PD    diff dlo dhi                    point pA - pB and the interval over all R replicates
#   PDH   sha                             sha256 of the ascending difference replicates
#
# PROFILE RECORDS (PP opens a table; its lines run until the next PP or the end)
#   PP    name                            table name
#   PPT   task algo ert                   table entry, inf when infinite
#   PPO   algo rho_at_1 ntasks            rho(1) and the number of included tasks
#   PPS   algo tau:rho;tau:rho;...        step points (distinct finite ratios ascending) or '-'
#   GM    algo ref value ntasks           geometric mean of ert_algo/ert_ref over tasks finite in both, or none with ntasks 0
#
# CONVENTIONS
#   Cost. Axis cpu: cpu_ms of a hit, B_ms for a censored run (h = 0). Axes instr, proposals, flips: the recorded value of every run.
#   ERT(axis) = (sum of costs) / (sum of h) over all N runs, inf when nothing hits. Hit costs are positive integers and every sum is below 2^53,
#     so the float ERT is the correctly rounded quotient of two integers.
#   LCG63: s = seed & (2^63-1); next(): s = (s*6364136223846793005 + 1442695040888963407) & (2^63-1); output = (s >> 32) & 0x7fffffff.
#     Index in [0,n) = (output*n) >> 31. Only the low 63 bits are kept, so wrapping 64-bit multiplication gives the same values.
#   Bootstrap (BE): one stream from seed; replicate r draws N indices, resamples the runs and takes the ERT (inf without a hit).
#     Replicates sort ascending with inf last; interval = [v[k], v[R-1-k]] with k = R // 40. sha = sha256 over the ascii text of the sorted
#     values, each in Python repr, joined by ','.
#   Comparison (PAIR): replicate r draws nA indices for A, then nB for B, from one stream. ratio* = ertA*/ertB* (float division) when both are
#     finite, inf when only ertA* is infinite, 0.0 when only ertB* is infinite, dropped when both are infinite. diff* = hitsA*/nA - hitsB*/nB
#     for every replicate. Intervals use k = m // 40 over the m kept values (m = R for diff); m = 0 gives none none and rkept 0.
#   Kaplan-Meier: a hit is (cpu_ms, 1), a censored run (B_ms, 0). S(t_j) = product over event times t <= t_j of (1 - d/n), n = observations with
#     time >= t (events precede censorings at a tied time). KMS values are the correctly rounded float of the exact fraction; KMT uses the exact one.
#   Descent: rank_i(t) = rank of the last trace entry with time <= t, else r0. Grid t_g = B_ms * 10**(-3 + g*3/48), g = 0..48 (t_0 = B/1000, t_48 = B).
#     Trace entries keep a relative distance above 1e-7 from every grid time (an entry at t = B_ms itself is exact), so ranks do not depend on the
#     last ulp of a grid time; grid times compare with the float tolerance. Quartiles are type-7 quantiles of the ascending ranks.
#   AUC: per run (1/ln 1000) * integral over [t0, B_ms] of f d(ln t), f = (rank - rstar)/(r0 - rstar), t0 = B_ms/1000, exact over the trace
#     breakpoints; entries at or before t0 set the starting level, entries at or after B_ms add no area. The sample value is the mean over runs.
#   TH: (sum of counts) / (sum of cpu_ms / 1000) over the runs that recorded the count, using each such run's recorded cpu_ms.
#   Profile: best(task) = least finite ERT; ratio = ert/best; a task without a finite ERT is excluded. rho(tau) = #(ratio <= tau) / #included tasks.
#   GM(algo, ref) = exp(mean(log(ert_algo/ert_ref))) over the tasks where both ERTs are finite.
#   fmt_fixed(x, d): exact binary value of x rounded half away from zero to d decimals; no exponent, no separators, no sign on a zero result.
#   fmt_thousands_tex(n): decimal digits in groups of three joined by {,}; a negative n keeps a leading '-'."""


def generate():
    """The complete fixture text."""
    out = HEADER.split("\n")

    out += ["", "# ==== Wilson intervals (item 1)",
            "# W(0,n): lo = 0, hi = z^2/(n+z^2).  W(n,n): lo = n/(n+z^2), hi = 1.  W(1,1) = (0.206549, 1).  W(2,4) = (0.150039, 0.849961)."]
    for k, n in WILSON_CASES:
        lo, hi = wilson(k, n)
        out.append(f"W\t{k}\t{n}\t{tok(lo)}\t{tok(hi)}")

    gq = Gen(FIXTURE_SEED + 1)
    quantile_qs = [0.0, 0.05, 0.1, 0.25, 1 / 3, 0.5, 0.6180339887498949, 0.75, 0.9, 0.95, 0.99, 1.0]
    cases = list(QUANTILE_FIXED)
    for _ in range(18):
        n = gq.rint(2, 14)
        if gq.u() < 0.6:
            vals = sorted(gq.rint(0, 999) for _ in range(n))
        else:
            vals = sorted(round(gq.uni(0.0, 100.0), 3) for _ in range(n))
        cases.append((gq.pick(quantile_qs), vals))
    out += ["", "# ==== quantiles (item 2): h = (n-1)q, result = x[floor h] + (h - floor h)*(x[floor h + 1] - x[floor h])",
            "# Q 0.5 over 1,2,3,4: h = 1.5 -> 2 + 0.5*(3-2) = 2.5;  Q 0.9 over 1..10: h = 8.1 -> 9 + 0.1*(10-9) = 9.1"]
    for q, vals in cases:
        out.append(f"Q\t{tok(float(q))}\t{len(vals)}\t{','.join(tok(v) for v in vals)}\t{tok(quantile(vals, q))}")

    out += ["", "# ==== LCG63 (item 4); seed 0: state 1 = 1442695040888963407, output 1 = state >> 32 = 335903614",
            "# seeds >= 2^63 and negative seeds are masked to their low 63 bits"]
    for seed in LCG_SEEDS + LCG_MASKED_SEEDS:
        gen = LCG63(seed)
        out.append(f"L\t{seed}\t{','.join(str(gen.next()) for _ in range(8))}")
    out += ["", "# index draws (output*n) >> 31"]
    for seed, n in INDEX_CASES:
        gen = LCG63(seed)
        out.append(f"IX\t{seed}\t{n}\t{','.join(str(gen.index(n)) for _ in range(16))}")

    out += ["", "# ==== FNV-1a 64 seeds (item 12); standard vectors: a -> af63dc4c8601ec8c, foobar -> 85944171f73967e8"]
    for text in FNV_PLAIN:
        out.append(f"HF\t{text}\t{fnv1a64(text.encode('utf-8')):016x}")
    for text in HASH_STRINGS:
        shown = text.replace("\t", "\\t")
        raw = fnv1a64(text.encode("utf-8"))
        out.append(f"H\t{shown}\t{raw & MASK62}")
        out.append(f"HF\t{shown}\t{raw:016x}")

    out += ["", "# ==== fmt_fixed (item 13): exact binary value, half away from zero; 0.125 -> 0.13 (tie), 2.675 -> 2.67 (value below the tie), -0.001 -> 0.00"]
    for x, d in FIXED_CASES:
        out.append(f"F\t{tok(float(x))}\t{d}\t{fmt_fixed(x, d)}")
    out += ["", "# ==== fmt_thousands_tex (item 13)"]
    for n in THOUSANDS_CASES:
        out.append(f"T\t{n}\t{fmt_thousands_tex(n)}")

    out += ["", "# ==== hand-worked samples: z^2 = 3.841458820694124, ln 1000 = 6.907755278982137"]
    for s, notes, be, dg in hand_samples():
        out += ["", "# " + notes[0]] + ["# " + line for line in notes[1:]]
        out += case_lines(s, be, dg)

    samples = {}
    g = Gen(FIXTURE_SEED)
    out += ["", "# ==== synthetic samples: geometric/exponential hit times rounded to ms, censoring at B_ms, rank descents from r0 to rstar"]
    for spec in SYN:
        s = gen_sample(g, spec)
        samples[s.name] = s
        be = [(axis, fnv_seed(s.name, axis), reps) for axis, reps in BE_PLAN.get(s.name, [])]
        out += [""] + case_lines(s, be, spec[5] == "full")

    out += ["", "# ==== two-arm comparisons (item 6), cpu axis; seed = fnv_seed(nameA, nameB)"]
    for a, b, reps in PAIR_PLAN:
        out += [""] + pair_lines(samples[a], samples[b], fnv_seed(a, b), reps)

    out += ["", "# ==== performance profiles and geometric-mean ratios (items 9, 10)"]
    gp = Gen(FIXTURE_SEED + 2)
    table_a = make_table_a(gp)
    out += [""] + profile_lines("pp_a", PP_TASKS_A, PP_ALGOS_A, table_a, [PP_ALGOS_A[0], PP_ALGOS_A[3]])
    table_b = make_table_b()
    out += ["", "# pp_b: u03 is infinite everywhere (excluded); epsilon is finite only where alpha is infinite, so GM(epsilon, alpha) = none 0"]
    out += profile_lines("pp_b", PP_TASKS_B, PP_ALGOS_B, table_b, [PP_ALGOS_B[0], PP_ALGOS_B[4]])
    return "\n".join(out) + "\n"


# ------------------------------------------------------------------ self-test: fixture parsing

def parse_records(text):
    """[(tag, fields, line number)] for every data line of a fixture."""
    recs = []
    for no, line in enumerate(text.split("\n"), 1):
        if line and not line.startswith("#"):
            f = line.split("\t")
            recs.append((f[0], f[1:], no))
    return recs


def parse_blocks(recs):
    """(global records, {name: case}, [pair], [profile]); case, pair and profile dicts carry their trailing lines."""
    top, cases, pairs, profiles = [], {}, [], []
    cur = None
    i = 0
    while i < len(recs):
        tag, f, no = recs[i]
        if tag == "CASE":
            n = int(f[1])
            run_recs = recs[i + 1:i + 1 + n]
            assert len(run_recs) == n and all(r[0] == "R" and len(r[1]) == 6 for r in run_recs), f"line {no}"
            cur = {"name": f[0], "N": n, "B": int(f[2]), "r0": int(f[3]), "rstar": int(f[4]),
                   "runs": [r[1] for r in run_recs], "lines": []}
            cases[f[0]] = cur
            i += 1 + n
            continue
        if tag == "PAIR":
            cur = {"a": f[0], "b": f[1], "seed": int(f[2]), "R": int(f[3]), "lines": []}
            pairs.append(cur)
        elif tag == "PP":
            cur = {"name": f[0], "lines": []}
            profiles.append(cur)
        elif cur is None:
            top.append((tag, f))
        else:
            cur["lines"].append((tag, f))
        i += 1
    return top, cases, pairs, profiles


def num(s):
    """Fixture number token -> int, float, INF or None."""
    if s == "inf":
        return INF
    if s == "none":
        return None
    try:
        return int(s)
    except ValueError:
        return float(s)


def sample_from_case(c):
    runs = []
    for f in c["runs"]:
        instr, props, flips = (None if x == "-" else int(x) for x in f[2:5])
        trace = [] if f[5] == "-" else [tuple(int(x) for x in p.split(":")) for p in f[5].split(";")]
        runs.append(Run(int(f[0]), int(f[1]), instr, props, flips, trace))
    return Sample(c["name"], c["B"], c["r0"], c["rstar"], runs)


def lines_by_tag(lines):
    out = {}
    for tag, f in lines:
        out.setdefault(tag, []).append(f)
    return out


# ------------------------------------------------------------------ self-test: independent computations

def _alt_lcg(seed):
    """LCG63 through modular arithmetic and floor division."""
    s = seed % (1 << 63)
    while True:
        s = (s * 6364136223846793005 + 1442695040888963407) % (1 << 63)
        yield (s // (1 << 32)) % (1 << 31)


def _alt_fnv(data):
    h = 0xCBF29CE484222325
    for b in data:
        h = ((h ^ b) * 0x100000001B3) % (1 << 64)
    return h


def _bf_resample(runs, seed, reps):
    """Brute-force bootstrap on (h, cost) runs: explicit resamples, exact Fraction ERTs, ascending floats."""
    stream = _alt_lcg(seed)
    n = len(runs)
    vals = []
    for _ in range(reps):
        picked = [runs[(next(stream) * n) // (1 << 31)] for _ in range(n)]
        hits = sum(h for h, _ in picked)
        vals.append(INF if hits == 0 else float(Fraction(sum(c for _, c in picked), hits)))
    return sorted(vals)


def _bf_compare(runs_a, runs_b, seed, reps):
    stream = _alt_lcg(seed)
    na, nb = len(runs_a), len(runs_b)
    ratios, diffs = [], []
    for _ in range(reps):
        pa = [runs_a[(next(stream) * na) // (1 << 31)] for _ in range(na)]
        pb = [runs_b[(next(stream) * nb) // (1 << 31)] for _ in range(nb)]
        ha, hb = sum(h for h, _ in pa), sum(h for h, _ in pb)
        ea = None if ha == 0 else float(Fraction(sum(c for _, c in pa), ha))
        eb = None if hb == 0 else float(Fraction(sum(c for _, c in pb), hb))
        diffs.append(ha / na - hb / nb)
        if ea is None and eb is None:
            continue
        ratios.append(INF if ea is None else (0.0 if eb is None else ea / eb))
    return sorted(ratios), sorted(diffs)


def _km_efron(obs):
    """Kaplan-Meier by redistribution to the right: {event time: S} in exact Fractions."""
    n = len(obs)
    order = sorted(range(n), key=lambda i: (obs[i][0], 0 if obs[i][1] else 1, i))
    mass = [Fraction(1, n)] * n
    for pos in range(n - 1):
        if not obs[order[pos]][1]:
            share = mass[pos] / (n - 1 - pos)
            for later in range(pos + 1, n):
                mass[later] += share
    event_mass = {}
    for pos in range(n):
        t, e = obs[order[pos]]
        if e:
            event_mass[t] = event_mass.get(t, Fraction(0)) + mass[pos]
    out, cum = {}, Fraction(0)
    for t in sorted(event_mass):
        cum += event_mass[t]
        out[t] = 1 - cum
    return out


def _bf_rank(trace, r0, t):
    r = r0
    for te, k in trace:
        if te <= t:
            r = k
    return r


def _auc_decimal(trace, r0, rstar, B):
    """Piecewise-constant log-time area in 60-digit decimals from explicit breakpoints."""
    from decimal import Decimal
    t0 = Decimal(B) / 1000
    pts = [t0] + sorted({Decimal(t) for t, _ in trace if t0 < t < B}) + [Decimal(B)]
    total = Decimal(0)
    for a, b in zip(pts, pts[1:]):
        level = r0
        for t, k in trace:
            if Decimal(t) <= a:
                level = k
        total += Decimal(level - rstar) / Decimal(r0 - rstar) * (b.ln() - a.ln())
    return total / Decimal(1000).ln()


def _auc_riemann(trace, r0, rstar, B, cells=8000):
    """Midpoint rule in ln t over [B/1000, B] on the step function f."""
    a, b = math.log(B / 1000), math.log(B)
    acc = 0.0
    for i in range(cells):
        t = math.exp(a + (b - a) * (i + 0.5) / cells)
        acc += (_bf_rank(trace, r0, t) - rstar) / (r0 - rstar)
    return acc / cells


def _wilson_decimal(k, n):
    from decimal import Decimal
    z = Decimal("1.959963984540054")
    nd = Decimal(n)
    p = Decimal(k) / nd
    z2 = z * z
    d = 1 + z2 / nd
    center = (p + z2 / (2 * nd)) / d
    half = z * (p * (1 - p) / nd + z2 / (4 * nd * nd)).sqrt() / d
    return max(Decimal(0), center - half), min(Decimal(1), center + half)


def _alt_profile(table, tasks, algos):
    """Exact-Fraction performance profile: {algo: (n_tasks, [(tau, rho)])}."""
    rows = []
    for t in tasks:
        fin = [Fraction(table[t][a]) for a in algos if table[t][a] is not None]
        if not fin:
            continue
        best = min(fin)
        rows.append({a: None if table[t][a] is None else Fraction(table[t][a]) / best for a in algos})
    out = {}
    for a in algos:
        taus = sorted({r[a] for r in rows if r[a] is not None})
        out[a] = (len(rows), [(tau, Fraction(sum(1 for r in rows if r[a] is not None and r[a] <= tau), len(rows)))
                              for tau in taus])
    return out


def _gm_decimal(table, tasks, algo, ref):
    from decimal import Decimal
    logs = [(Decimal(table[t][algo]) / Decimal(table[t][ref])).ln() for t in tasks
            if table[t][algo] is not None and table[t][ref] is not None]
    if not logs:
        return None, 0
    return (sum(logs) / len(logs)).exp(), len(logs)


def _dec_fixed(x, decimals):
    from decimal import Decimal, ROUND_HALF_UP
    q = Decimal(x).quantize(Decimal(1).scaleb(-decimals), rounding=ROUND_HALF_UP)
    s = format(q, "f")
    return s[1:] if s.startswith("-") and q == 0 else s


# hand-worked values (from the fixture comments and the scratch derivations)
HAND_EXPECT = {
    "hand_mixed4": dict(
        wilson=(0.150039, 0.849961), ert={"cpu": 1400, "instr": 13000, "proposals": 310, "flips": 85},
        km=[(200, Fraction(3, 4)), (600, Fraction(1, 2))], kmt=(200, 600, None),
        th={"proposals": Fraction(620, 3), "flips": Fraction(170, 3)},
        dg_first=(1.0, 10.0, 10.0, 10.0), dg_last=(1000.0, 6.0, 7.0, 8.5),
        auc_runs=(0.698351, 0.860185, 0.666303, 1.0), auc=0.806210),
    "hand_none_hit": dict(
        wilson=(0.0, 0.489891), ert={"cpu": None, "instr": None, "proposals": None, "flips": None},
        km=[], kmt=(None, None, None), th={"proposals": Fraction(200), "flips": Fraction(40)}),
    "hand_all_hit": dict(
        wilson=(0.510109, 1.0), ert={"cpu": 250, "instr": 2500, "proposals": 25, "flips": Fraction(25, 2)},
        km=[(100, Fraction(3, 4)), (200, Fraction(1, 2)), (300, Fraction(1, 4)), (400, Fraction(0))],
        kmt=(100, 200, 300), th={"proposals": Fraction(100), "flips": Fraction(50)}),
    "hand_tie_km": dict(
        wilson=(0.299993, 0.903229), ert={"cpu": Fraction(2025, 2)},
        km=[(250, Fraction(5, 6)), (400, Fraction(1, 2)), (1000, Fraction(1, 3))], kmt=(400, 400, None),
        dg_last=(1000.0, 6.0, 6.0, 6.75),
        auc_runs=(0.799313, 0.780207, 0.867353, 0.992374, 1.0, 0.949828), auc=0.898179),
    "hand_auc_t0": dict(
        wilson=(0.061492, 0.792340), ert={"cpu": 5500}, km=[(500, Fraction(2, 3))], kmt=(500, None, None),
        dg_first=(2.5, 7.5, 9.0, 10.0), dg_last=(2500.0, 3.0, 5.0, 8.0),
        auc_runs=(1.0, 0.250172, 0.610557), auc=0.620243),
    "hand_counts_missing": dict(
        ert={"cpu": Fraction(7000, 3), "instr": 19000}, th={"proposals": Fraction(650, 3), "flips": None}),
    "hand_n1_hit": dict(
        wilson=(0.206549, 1.0), ert={"cpu": 40}, km=[(40, Fraction(0))], kmt=(40, 40, 40)),
    "hand_n1_cens": dict(wilson=(0.0, 0.793451), ert={"cpu": None}, km=[], kmt=(None, None, None)),
}


def selftest():
    import numpy as np
    from decimal import Decimal, getcontext

    getcontext().prec = 60
    started = time.time()
    rng = random.Random(7)
    count = [0]

    def check(cond, what=""):
        count[0] += 1
        if not cond:
            raise AssertionError(what)

    def close(a, b, tol=1e-12):
        if a == b:
            return True
        if a is None or b is None or math.isinf(a) or math.isinf(b):
            return False
        return abs(a - b) <= tol * max(1.0, abs(b))

    text = generate()
    top, cases, pairs, profiles = parse_blocks(parse_records(text))
    samples = {name: sample_from_case(c) for name, c in cases.items()}
    sections = []

    def section(fn):
        sections.append(fn)
        return fn

    def rand_sample(n=None, p=None):
        n = n or rng.randint(1, 30)
        p = rng.random() if p is None else p
        runs = []
        for _ in range(n):
            hit = rng.random() < p
            cpu = rng.randint(1, 900) if hit else 1000
            runs.append(Run(1 if hit else 0, cpu, rng.randint(1, 10 ** 6), rng.randint(1, 10 ** 5),
                            rng.randint(1, 10 ** 4), [(cpu, 1)] if hit else []))
        return Sample("rand", 1000, 5, 1, runs)

    @section
    def s_quantile():
        """quantile: type 7 against numpy.quantile and exact Fractions"""
        for _ in range(500):
            n = rng.randint(1, 40)
            if rng.random() < 0.5:
                xs = sorted(rng.randint(-50, 500) for _ in range(n))
            else:
                xs = sorted(round(rng.uniform(-10, 100), 4) for _ in range(n))
            arr = np.array(xs, dtype=float)
            for q in (0.0, 0.05, 0.25, 1 / 3, 0.5, 0.75, 0.9, 0.95, 1.0, rng.random()):
                got = quantile(xs, q)
                check(isinstance(got, float))
                check(close(got, float(np.quantile(arr, q))), ("numpy", xs, q))
                h = Fraction(q) * (n - 1)
                lo = math.floor(h)
                exact = Fraction(xs[lo]) + (h - lo) * (Fraction(xs[min(lo + 1, n - 1)]) - Fraction(xs[lo]))
                check(close(got, float(exact)), ("exact", xs, q))
        for f in [f for tag, f in top if tag == "Q"]:
            vals = [num(x) for x in f[2].split(",")]
            check(len(vals) == int(f[1]) and vals == sorted(vals))
            check(quantile(vals, float(f[0])) == float(f[3]), f)
            check(close(float(f[3]), float(np.quantile(np.array(vals, dtype=float), float(f[0])))), f)

    @section
    def s_wilson():
        """wilson: 60-digit Decimal evaluation, fixture W lines"""
        def against(k, n, lo, hi):
            dlo, dhi = _wilson_decimal(k, n)
            check(abs(Decimal(lo) - dlo) <= Decimal("2e-15") and abs(Decimal(hi) - dhi) <= Decimal("2e-15"), (k, n))
            check(0.0 <= lo <= hi <= 1.0)
        for n in list(range(1, 61)) + [100, 120, 500, 1000, 4567, 10 ** 5]:
            for k in (range(n + 1) if n <= 60 else [0, 1, n // 3, n // 2, n - 1, n]):
                against(k, n, *wilson(k, n))
        for f in [f for tag, f in top if tag == "W"]:
            k, n = int(f[0]), int(f[1])
            check(wilson(k, n) == (float(f[2]), float(f[3])))
            against(k, n, float(f[2]), float(f[3]))
        for c in cases.values():
            k = sum(int(r[0]) for r in c["runs"])
            f = [f for tag, f in c["lines"] if tag == "W"][0]
            check(int(f[0]) == k and int(f[1]) == c["N"])
            against(k, c["N"], float(f[2]), float(f[3]))

    @section
    def s_lcg():
        """lcg63: independent generator, fixture L and IX lines"""
        check(LCG63(0).next() == 1442695040888963407 // 2 ** 32 == 335903614)
        seeds = [0, 1, 2 ** 62 - 1, 2 ** 63 - 1, 2 ** 63, 2 ** 64 - 1, -1, -12345]
        seeds += [rng.getrandbits(64) for _ in range(100)]
        for seed in seeds:
            a, b = LCG63(seed), _alt_lcg(seed)
            for _ in range(50):
                want = next(b)
                got = a.next()
                check(got == want and 0 <= got < 2 ** 31, seed)
            for n in (1, 7, 120):
                g1, g2 = LCG63(seed), _alt_lcg(seed)
                for _ in range(20):
                    i = g1.index(n)
                    check(i == (next(g2) * n) // 2 ** 31 and 0 <= i < n)
        for f in [f for tag, f in top if tag == "L"]:
            b = _alt_lcg(int(f[0]))
            check([next(b) for _ in range(8)] == [int(x) for x in f[1].split(",")], f)
        for f in [f for tag, f in top if tag == "IX"]:
            b, n = _alt_lcg(int(f[0])), int(f[1])
            check([(next(b) * n) // 2 ** 31 for _ in range(16)] == [int(x) for x in f[2].split(",")], f)

    @section
    def s_fnv():
        """fnv1a64: published vectors, alternate implementation, fixture H and HF lines"""
        for data, want in ((b"", 0xCBF29CE484222325), (b"a", 0xAF63DC4C8601EC8C), (b"foobar", 0x85944171F73967E8)):
            check(fnv1a64(data) == want == _alt_fnv(data))
        check(fnv_seed("9x9x9@perminov486", "metaflip/V0")
              == _alt_fnv("9x9x9@perminov486\tmetaflip/V0".encode()) % 2 ** 62)
        for _ in range(200):
            data = bytes(rng.randrange(256) for _ in range(rng.randint(0, 40)))
            check(fnv1a64(data) == _alt_fnv(data))
        for tag, f in top:
            if tag in ("H", "HF"):
                raw = _alt_fnv(f[0].replace("\\t", "\t").encode("utf-8"))
                check(f[1] == (str(raw % 2 ** 62) if tag == "H" else "%016x" % raw), f)
        wide = 0
        for name, c in cases.items():
            for tag, f in c["lines"]:
                if tag == "BE" and name.startswith("syn"):
                    raw = _alt_fnv((name + "\t" + f[0]).encode())
                    check(int(f[1]) == raw % 2 ** 62, (name, f[0]))
                    wide += raw >> 62 & 1
        for p in pairs:
            raw = _alt_fnv((p["a"] + "\t" + p["b"]).encode())
            check(p["seed"] == raw % 2 ** 62, p)
            wide += raw >> 62 & 1
        check(wide >= 10, "seed masks exercised")

    @section
    def s_format():
        """fmt_fixed against Decimal ROUND_HALF_UP on the exact double; fmt_thousands_tex against str.format"""
        for _ in range(3000):
            d = rng.randint(0, 8)
            x = rng.uniform(-1e4, 1e4) if rng.random() < 0.5 else rng.randint(-10 ** 6, 10 ** 6) / 2 ** rng.randint(0, 12)
            check(fmt_fixed(x, d) == _dec_fixed(x, d), (x, d))
        for x, d in [(0.125, 2), (2.675, 2), (-0.0, 3), (5e-324, 2), (1e22, 3), (0.5, 0), (-0.5, 0), (1.5, 0)]:
            check(fmt_fixed(x, d) == _dec_fixed(x, d), (x, d))
        check(fmt_fixed(0.125, 2) == "0.13" and fmt_fixed(-0.125, 2) == "-0.13" and fmt_fixed(2.675, 2) == "2.67")
        check(fmt_fixed(-0.001, 2) == "0.00" and fmt_fixed(0.5, 0) == "1" and fmt_fixed(1e21, 1) == "1" + "0" * 21 + ".0")
        for tag, f in top:
            if tag == "F":
                check(fmt_fixed(float(f[0]), int(f[1])) == f[2] == _dec_fixed(float(f[0]), int(f[1])), f)
            if tag == "T":
                n = int(f[0])
                check(f[1] == format(n, ",").replace(",", "{,}") == fmt_thousands_tex(n), f)
        for n in [0, 1, 999, 1000, 1150, 12345678, -1, -1000, 10 ** 15, -(10 ** 15) - 7]:
            check(fmt_thousands_tex(n) == format(n, ",").replace(",", "{,}"), n)
        check(fmt_thousands_tex(1150) == "1{,}150" and fmt_thousands_tex(999) == "999"
              and fmt_thousands_tex(12345678) == "12{,}345{,}678")

    @section
    def s_ert():
        """ert: exact Fractions, fixture E lines"""
        for _ in range(300):
            s = rand_sample(p=rng.choice([0.0, 0.3, 0.7, 1.0]))
            for axis in AXES:
                c, h = s.costs(axis), s.hits
                hits = sum(h)
                exact = None if hits == 0 else sum(Fraction(x) for x in c) / hits
                check(ert_exact(c, h) == exact)
                check(ert(c, h) == (INF if exact is None else float(exact)))
        from math import gcd
        for name, s in samples.items():
            lines = lines_by_tag(cases[name]["lines"])
            seen = {}
            for f in lines.get("E", []):
                seen[f[0]] = f
            for axis in AXES:
                state = s.presence(axis)
                check((axis in seen) == (state != "mixed"), (name, axis))
                if state == "mixed":
                    continue
                f = seen[axis]
                if state == "absent":
                    check(f[1:] == ["none", "none"])
                    continue
                c, h = s.costs(axis), s.hits
                if sum(h) == 0:
                    check(f[1:] == ["inf", "inf"])
                    continue
                exact = Fraction(sum(c), sum(h))
                a, b = (int(x) for x in f[2].split("/"))
                check(Fraction(a, b) == exact and gcd(a, b) == 1 and float(f[1]) == float(exact), (name, axis))
        check(ert_exact([10, 20], [0, 0]) is None and ert([10, 20], [0, 0]) == INF)

    @section
    def s_bootstrap():
        """bootstrap: explicit resampling with an independent LCG, fixture BE lines"""
        check(interval(list(range(200))) == (5, 194) and interval(list(range(2000))) == (50, 1949)
              and interval(list(range(39))) == (0, 38))
        for _ in range(40):
            s = rand_sample(p=rng.choice([0.0, 0.1, 0.5, 1.0]))
            axis = rng.choice(AXES)
            seed = rng.getrandbits(62)
            got = bootstrap_sorted(s.costs(axis), s.hits, seed, 200)
            want = _bf_resample(list(zip(s.hits, s.costs(axis))), seed, 200)
            check(got == want and got == sorted(got) and len(got) == 200)
            check(all(isinstance(x, float) for x in got))
        for name, c in cases.items():
            s = samples[name]
            for f in [f for tag, f in c["lines"] if tag == "BE"]:
                axis, seed, reps = f[0], int(f[1]), int(f[2])
                vals = _bf_resample(list(zip(s.hits, s.costs(axis))), seed, reps)
                lo, hi = interval(vals)
                check(num(f[3]) == lo and num(f[4]) == hi and f[5] == list_hash(vals), (name, axis))
                check(f[5] == hashlib.sha256(",".join(repr(v) for v in vals).encode()).hexdigest())
        n_be = sum(1 for c in cases.values() for tag, _ in c["lines"] if tag == "BE")
        check(n_be >= 24 and sum(1 for c in cases.values() for tag, f in c["lines"] if tag == "BE" and f[2] == "2000") >= 12)

    @section
    def s_pair():
        """comparison bootstrap: explicit resampling with an independent LCG, fixture PAIR blocks"""
        for _ in range(20):
            a, b = rand_sample(p=rng.choice([0.0, 0.4, 1.0])), rand_sample(p=rng.choice([0.0, 0.4, 1.0]))
            seed = rng.getrandbits(62)
            got = compare_bootstrap(a.costs("cpu"), a.hits, b.costs("cpu"), b.hits, seed, 200)
            want = _bf_compare(list(zip(a.hits, a.costs("cpu"))), list(zip(b.hits, b.costs("cpu"))), seed, 200)
            check(got == want)
        for p in pairs:
            a, b = samples[p["a"]], samples[p["b"]]
            ratios, diffs = _bf_compare(list(zip(a.hits, a.costs("cpu"))), list(zip(b.hits, b.costs("cpu"))),
                                        p["seed"], p["R"])
            L = lines_by_tag(p["lines"])
            pr, prh, pd, pdh = L["PR"][0], L["PRH"][0], L["PD"][0], L["PDH"][0]
            ea, eb = ert_exact(a.costs("cpu"), a.hits), ert_exact(b.costs("cpu"), b.hits)
            point = None if ea is None or eb is None else float(ea) / float(eb)
            check(num(pr[0]) == point and int(pr[3]) == len(ratios), p)
            if ratios:
                check((num(pr[1]), num(pr[2])) == interval(ratios) and prh[0] == list_hash(ratios), p)
            else:
                check(pr[1:] == ["none", "none", "0"] and prh[0] == "none", p)
            dpoint = sum(a.hits) / a.N - sum(b.hits) / b.N
            check(num(pd[0]) == dpoint and (num(pd[1]), num(pd[2])) == interval(diffs) and pdh[0] == list_hash(diffs), p)
            check(len(diffs) == p["R"] and len(ratios) <= p["R"])
        kinds = [(sum(samples[p["a"]].hits) == 0, sum(samples[p["b"]].hits) == 0) for p in pairs]
        check(len(pairs) >= 10 and (False, True) in kinds and (True, False) in kinds and (True, True) in kinds)

    @section
    def s_km():
        """kaplan-meier: redistribution-to-the-right algorithm, exact threshold times, fixture KM blocks"""
        for _ in range(400):
            n = rng.randint(1, 14)
            horizon = rng.randint(3, 12)
            obs = []
            for _ in range(n):
                if rng.random() < 0.6:
                    obs.append((rng.randint(1, horizon), 1))
                else:
                    obs.append((horizon, 0))
            curve = km_curve(obs)
            want = _km_efron(obs)
            check(dict(curve) == want, obs)
            for q in (25, 50, 75):
                direct = [t for t, s in sorted(want.items()) if 100 * (1 - s) >= q]
                check(km_time(curve, q) == (direct[0] if direct else None), (obs, q))
        for name, c in cases.items():
            s = samples[name]
            L = lines_by_tag(c["lines"])
            want = _km_efron(s.km_obs())
            got = [(int(f[0]), float(f[1])) for f in L.get("KMS", [])]
            check(got == [(t, float(v)) for t, v in sorted(want.items())], name)
            for f in L["KMT"]:
                q = int(f[0])
                direct = [t for t, v in sorted(want.items()) if 100 * (1 - v) >= q]
                check(num(f[1]) == (direct[0] if direct else None), (name, q))

    @section
    def s_descent():
        """descent profile and auc: brute-force ranks, np.quantile, 60-digit grid and area"""
        for B in (120, 1000, 2500, 3600000):
            grid = grid_times(B)
            check(len(grid) == 49 and grid[48] == float(B))
            for g, t in enumerate(grid):
                exact = float(Decimal(B) * Decimal(10) ** (Decimal(g - 48) / 16))
                check(abs(t - exact) <= math.ulp(exact), (B, g))
        for name, c in cases.items():
            L = lines_by_tag(c["lines"])
            if "DG" not in L:
                continue
            s = samples[name]
            rows = L["DGR"]
            check(L["DG"] == [["49", "3"]] and len(rows) == 49 and len(L["AUC"]) == 1, name)
            for g, f in enumerate(rows):
                t = float(f[0])
                check(close(t, grid_times(s.B)[g], 1e-15), (name, g))
                ranks = sorted(_bf_rank(r.trace, s.r0, t) for r in s.runs)
                want = [float(np.quantile(np.array(ranks, dtype=float), q)) for q in (0.25, 0.5, 0.75)]
                check(all(close(float(f[1 + i]), want[i]) for i in range(3)), (name, g))
            aucs = [_auc_decimal(r.trace, s.r0, s.rstar, s.B) for r in s.runs]
            check(close(float(L["AUC"][0][0]), float(sum(aucs) / len(aucs)), 1e-13), name)
            for r, a in zip(s.runs, aucs):
                check(close(auc_run(r.trace, s.r0, s.rstar, s.B), float(a), 1e-13), name)
        picked = [(s, r) for name, s in samples.items() if any(t == "DG" for t, _ in cases[name]["lines"]) for r in s.runs]
        for s, r in [picked[i] for i in range(0, len(picked), max(1, len(picked) // 60))]:
            check(abs(auc_run(r.trace, s.r0, s.rstar, s.B) - _auc_riemann(r.trace, s.r0, s.rstar, s.B)) < 2e-3, s.name)
        check(auc_run([], 10, 6, 1000) == 1.0 or close(auc_run([], 10, 6, 1000), 1.0, 1e-15))
        check(close(auc_run([(0, 6)], 10, 6, 1000), 0.0, 1e-15))
        check(sum(1 for c in cases.values() if any(tag == "DG" for tag, _ in c["lines"])) >= 20)

    @section
    def s_profile():
        """performance profile and geometric mean: exact Fractions and 60-digit logs, fixture PP blocks"""
        def compare(table, tasks, algos, lines):
            L = lines_by_tag(lines)
            alt = _alt_profile(table, tasks, algos)
            n_tasks, ratios = perf_profile(table, tasks, algos)
            for f in L["PPO"]:
                n, steps = alt[f[0]]
                one = [rho_ for tau, rho_ in steps if tau <= 1]
                check(int(f[2]) == n == n_tasks and float(f[1]) == float(one[-1] if one else 0), f)
            for f in L["PPS"]:
                n, steps = alt[f[0]]
                want = ";".join(f"{float(tau)!r}:{float(r)!r}" for tau, r in steps) or "-"
                check(f[1] == want, f)
            for f in L["GM"]:
                v, k = _gm_decimal(table, tasks, f[0], f[1])
                check(int(f[3]) == k and (num(f[2]) is None) == (v is None), f)
                if v is not None:
                    check(abs(Decimal(float(f[2])) - v) <= Decimal("1e-13") * v, f)
        for p in profiles:
            L = lines_by_tag(p["lines"])
            tasks, algos = [], []
            table = {}
            for t, a, v in L["PPT"]:
                if t not in table:
                    tasks.append(t)
                    table[t] = {}
                if a not in algos:
                    algos.append(a)
                table[t][a] = None if v == "inf" else float(v)
            check(len(tasks) == 12 and len(algos) == 5 and any(v is None for r in table.values() for v in r.values()))
            compare(table, tasks, algos, p["lines"])
        for _ in range(40):
            tasks = ["t%d" % i for i in range(rng.randint(1, 9))]
            algos = ["a%d" % i for i in range(rng.randint(1, 5))]
            table = {t: {a: (None if rng.random() < 0.4 else float(rng.choice([1, 2, 3, 4, 6, 8, 12]) * rng.randint(1, 3)))
                         for a in algos} for t in tasks}
            n_tasks, ratios = perf_profile(table, tasks, algos)
            alt = _alt_profile(table, tasks, algos)
            for a in algos:
                n, steps = alt[a]
                check(n == n_tasks and [(float(tau), float(r)) for tau, r in steps] == profile_steps(ratios[a], n_tasks), a)
            for ref in algos:
                for a in algos:
                    v, k = geomean_ratio(table, tasks, a, ref)
                    dv, dk = _gm_decimal(table, tasks, a, ref)
                    check(k == dk and ((v is None) == (dv is None)) and (v is None or abs(Decimal(v) - dv) <= Decimal("1e-13") * dv))

    @section
    def s_throughput():
        """throughput: exact Fractions over the runs that recorded the count, fixture TH lines"""
        for name, s in samples.items():
            for f in [f for tag, f in cases[name]["lines"] if tag == "TH"]:
                rows = [(getattr(r, f[0]), r.cpu) for r in s.runs if getattr(r, f[0]) is not None]
                want = None if not rows else float(Fraction(sum(c for c, _ in rows), 1) / (Fraction(sum(m for _, m in rows), 1000)))
                check(num(f[1]) == want, (name, f))
        runs = [Run(1, 500, None, 10, None, [(500, 1)]), Run(0, 1500, None, None, None, [])]
        check(throughput(runs, "proposals") == 20.0 and throughput(runs, "flips") is None)

    @section
    def s_hand():
        """hand-worked cases: values from the fixture comments"""
        for name, want in HAND_EXPECT.items():
            s = samples[name]
            check(name in cases)
            if "wilson" in want:
                k = sum(s.hits)
                lo, hi = wilson(k, s.N)
                check(abs(lo - want["wilson"][0]) < 5e-7 and abs(hi - want["wilson"][1]) < 5e-7, name)
            for axis, v in want.get("ert", {}).items():
                got = ert_exact(s.costs(axis), s.hits)
                check(got == (None if v is None else Fraction(v)), (name, axis))
            if "km" in want:
                check(km_curve(s.km_obs()) == want["km"], name)
                check(tuple(km_time(km_curve(s.km_obs()), q) for q in (25, 50, 75)) == want["kmt"], name)
            for kind, v in want.get("th", {}).items():
                got = throughput(s.runs, kind)
                check((got is None) == (v is None) and (v is None or close(got, float(v), 1e-14)), (name, kind))
            rows = descent_rows(s)
            if "dg_first" in want:
                check(all(close(a, b, 1e-13) for a, b in zip(rows[0], want["dg_first"])), (name, rows[0]))
            if "dg_last" in want:
                check(all(close(a, b, 1e-13) for a, b in zip(rows[-1], want["dg_last"])), (name, rows[-1]))
            if "auc_runs" in want:
                for r, a in zip(s.runs, want["auc_runs"]):
                    check(abs(auc_run(r.trace, s.r0, s.rstar, s.B) - a) < 5e-7, (name, a))
                check(abs(auc_sample(s) - want["auc"]) < 5e-7, name)
        auc_b = 0.2 + math.log10(2) / 6
        check(abs(auc_run(samples["hand_auc_t0"].runs[1].trace, 11, 1, 2500) - auc_b) < 1e-14)
        auc_c = (0.8 * math.log(12) + 0.6 * math.log(10) + 0.4 * math.log(25 / 3)) / math.log(1000)
        check(abs(auc_run(samples["hand_auc_t0"].runs[2].trace, 11, 1, 2500) - auc_c) < 1e-14)
        n1 = descent_rows(samples["hand_n1_hit"])
        check([r[2] for r in n1] == [4.0] * 34 + [3.0] * 8 + [2.0] * 7)
        inf200 = ",".join(["inf"] * 200)
        forty = ",".join(["40.0"] * 200)
        be = {name: [f for tag, f in cases[name]["lines"] if tag == "BE"] for name in ("hand_none_hit", "hand_n1_hit", "hand_n1_cens")}
        check(be["hand_none_hit"][0][3:] == ["inf", "inf", hashlib.sha256(inf200.encode()).hexdigest()])
        check(be["hand_n1_cens"][0][3:] == ["inf", "inf", hashlib.sha256(inf200.encode()).hexdigest()])
        check(be["hand_n1_hit"][0][3:] == ["40.0", "40.0", hashlib.sha256(forty.encode()).hexdigest()])
        for (k, n), (lo, hi) in {(0, 10): (0.0, 0.2775), (1, 10): (0.0179, 0.4041), (5, 10): (0.2366, 0.7634),
                                 (10, 10): (0.7225, 1.0)}.items():
            check(abs(wilson(k, n)[0] - lo) < 1e-4 and abs(wilson(k, n)[1] - hi) < 1e-4, (k, n))
        check(math.isclose(wilson(0, 4)[1], 3.841458820694124 / (4 + 3.841458820694124), rel_tol=1e-14))
        check(math.isclose(wilson(4, 4)[0], 4 / (4 + 3.841458820694124), rel_tol=1e-14))

    @section
    def s_fixture():
        """fixture: deterministic regeneration, on-disk copy, size, structure, documented tags"""
        check(generate() == text, "regeneration differs")
        raw = text.encode("utf-8")
        check(len(raw) <= FIXTURE_LIMIT, len(raw))
        check(b"\r" not in raw and text.endswith("\n") and not text.endswith("\n\n"))
        check(all(ln == ln.rstrip() for ln in text.split("\n")), "trailing whitespace")
        header = [ln for ln in HEADER.split("\n")]
        recs = parse_records(text)
        for tag in {r[0] for r in recs}:
            check(any(ln[1:].split()[:1] == [tag] for ln in header if ln.startswith("#")), tag)
        arity = {"W": 4, "Q": 4, "L": 2, "IX": 3, "H": 2, "HF": 2, "F": 3, "T": 2, "CASE": 5, "R": 6, "E": 3, "BE": 6,
                 "KM": 0, "KMS": 2, "KMT": 2, "DG": 2, "DGR": 4, "AUC": 1, "TH": 2, "PAIR": 4, "PR": 4, "PRH": 1,
                 "PD": 3, "PDH": 1, "PP": 1, "PPT": 3, "PPO": 3, "PPS": 2, "GM": 4}
        for tag, f, no in recs:
            check(arity[tag] == len(f), (tag, no))
            check(all(x == x.strip() and x for x in f), (tag, no))
        names = [name for tag, f, _ in recs if tag == "CASE" for name in f[:1]]
        check(len(set(names)) == len(names) and len(names) - sum(n.startswith("syn") for n in names) >= 6)
        check(sum(n.startswith("syn") for n in names) == 40)
        for p in pairs:
            check(p["a"] in names and p["b"] in names)
        check(len(profiles) == 2)
        if os.path.exists(FIXTURE_PATH):
            with open(FIXTURE_PATH, "rb") as fh:
                check(fh.read() == raw, "on-disk fixture differs from the generated text")
            print("     fixture file matches the generated text:", FIXTURE_PATH)
        else:
            print("     fixture file not present; generated text checked only")

    for fn in sections:
        before = count[0]
        fn()
        print(f"ok   {fn.__doc__:<100s} {count[0] - before:6d}")
    raw = text.encode("utf-8")
    print(f"selftest passed: {count[0]} checks in {time.time() - started:.1f} s")
    print(f"fixture: {len(raw)} bytes, sha256 {hashlib.sha256(raw).hexdigest()}")
    return 0


def main(argv):
    if "--generate" in argv:
        sys.stdout.buffer.write(generate().encode("utf-8"))
        return 0
    if "--selftest" in argv:
        return selftest()
    sys.stderr.write(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
