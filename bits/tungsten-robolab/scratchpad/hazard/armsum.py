"""armsum.py ROWS.jsonl [--ref ARM] [--min-stand S]: per arm (tag before '|'): starts, hold passes, falls (seed@stand), exposure (mean e4 / e3 over passes, |margin| < 1e-4 / 1e-3 of the substeps after 3 s),
margin (median of the late mean), other-segment exposure, NaN events; then, against --ref (default: first arm), fixed / broke and the paired sign-flip p."""
import json, sys, math, collections, itertools
import numpy as np
args = sys.argv[1:]
ref = None
if "--ref" in args:
    i = args.index("--ref"); ref = args[i + 1]; del args[i:i + 2]
rows = {}
for l in open(args[0]):
    try:
        r = json.loads(l)
    except Exception:
        continue
    rows[r["tag"]] = r
arms = collections.OrderedDict()
for tag, r in rows.items():
    arms.setdefault(tag.split("|")[0], {})[r["seed"]] = r


def passed(r):
    if "error" in r:
        return False
    T = r["seconds"]
    return (not r.get("fallen")) and (r.get("stand_time") or 0) >= T - 0.11 and (r.get("bal1_raw") or 0) >= T - 5.5


def sign_flip_p(diffs, nperm=20000):
    d = np.array([x for x in diffs if x != 0], float)
    k = len(d)
    if k == 0:
        return 1.0
    obs = abs(d.sum())
    if k <= 16:
        cnt = 0
        for signs in itertools.product((1, -1), repeat=k):
            cnt += abs(sum(s * x for s, x in zip(signs, d))) >= obs - 1e-12
        return cnt / 2 ** k
    rng = np.random.default_rng(1)
    S = rng.choice((-1, 1), size=(nperm, k))
    return float(((np.abs(S @ d) >= obs - 1e-12).mean() * nperm + 1) / (nperm + 1))


names = list(arms)
ref = ref or names[0]
print(f"{'arm':22s} n  pass  falls(seed@stand)                       | e4%   e3%   e2%  | mg_late_med  seg_oth_near3max | nan")
for nm in names:
    A = arms[nm]
    rs = list(A.values())
    ok = [r for r in rs if passed(r)]
    fl = sorted((s, r.get("stand_time") or 0) for s, r in A.items() if not passed(r))
    ex = [r for r in rs if r.get("e4") is not None]
    e4 = np.mean([r["e4"] for r in ex]) * 100 if ex else float("nan")
    e3 = np.mean([r["e3"] for r in ex]) * 100 if ex else float("nan")
    e2 = np.mean([r["e2"] for r in ex]) * 100 if ex else float("nan")
    mg = np.median([r["pr_mg_late_mean"] for r in ok if r.get("pr_mg_late_mean") is not None]) if ok else float("nan")
    so = max([r.get("seg_oth_near3", 0) for r in rs] + [0])
    nan = sum(r.get("nan_events") or 0 for r in rs)
    fs = " ".join(f"{s}@{t:.1f}" for s, t in fl[:6]) + (" ..." if len(fl) > 6 else "")
    print(f"{nm:22s} {len(rs):3d} {len(ok):4d}  {fs:40s} | {e4:5.2f} {e3:5.2f} {e2:5.2f} | {mg:+.2e}    {100 * so:5.2f}%          | {int(nan)}")
if ref in arms:
    print(f"paired against {ref}:")
    for nm in names:
        if nm == ref:
            continue
        common = sorted(set(arms[ref]) & set(arms[nm]))
        d = [int(passed(arms[nm][s])) - int(passed(arms[ref][s])) for s in common]
        fixed = [s for s, x in zip(common, d) if x > 0]
        broke = [s for s, x in zip(common, d) if x < 0]
        print(f"  {nm:22s} on {len(common)} common starts: fixed {len(fixed)} broke {len(broke)} (broke {broke[:8]}) diff {np.mean(d):+.4f} p {sign_flip_p(d):.3f}")
