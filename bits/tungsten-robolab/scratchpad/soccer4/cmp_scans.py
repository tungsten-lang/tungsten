"""Compare failscan JSON outputs at a common horizon: pass = standing until T-0.1 and one-leg time >= T-5 (default T=8).
usage: cmp_scans.py [--T 8] baseline.json variant1.json [variant2.json ...]"""
import json, sys, math

def load(p, T):
    rows = json.load(open(p))
    out = {}
    for r in rows:
        st = r.get("stand_time") or 0.0
        b = r.get("bal1_s") or 0.0
        # a scan longer than T: use the events? approximate with stand_time and bal1 only when the run ended before T
        ok = (st >= T - 0.1) and (b >= T - 5.0 or st > T + 0.5) and not (r.get("fallen") and st < T)
        out[r["seed"]] = bool(ok)
    return out

def binom_p(k, n, p0):
    # two-sided exact-ish via normal approximation
    if n == 0: return 1.0
    z = (k - n * p0) / math.sqrt(n * p0 * (1 - p0) + 1e-9)
    return 2 * (1 - 0.5 * (1 + math.erf(abs(z) / math.sqrt(2))))

if __name__ == "__main__":
    T = 8.0
    args = sys.argv[1:]
    if args and args[0] == "--T":
        T = float(args[1]); args = args[2:]
    base = load(args[0], T)
    nb = len(base); pb = sum(base.values())
    print(f"{args[0].split('/')[-1]}: {pb}/{nb} pass at {T:.0f} s ({100*pb/nb:.1f} %)")
    for v in args[1:]:
        d = load(v, T)
        seeds = sorted(set(base) & set(d))
        pv = sum(d[s] for s in seeds); pb2 = sum(base[s] for s in seeds)
        fixed = [s for s in seeds if d[s] and not base[s]]
        broke = [s for s in seeds if base[s] and not d[s]]
        # unpaired two-proportion z (paired McNemar is not meaningful under chaotic re-rolls)
        n = len(seeds)
        p1, p2 = pb2 / n, pv / n
        pp = (pb2 + pv) / (2 * n)
        z = (p2 - p1) / math.sqrt(2 * pp * (1 - pp) / n + 1e-12)
        print(f"{v.split('/')[-1]}: {pv}/{n} pass ({100*pv/n:.1f} %), fixed {len(fixed)} broke {len(broke)}, z = {z:+.2f}")
