"""Screening design + response surface for small parameter effects (round 10).

Single-parameter A/B tests on ~100 serves cannot resolve +-3 point effects, and CMA on 40-60 fresh serves per candidate
is dominated by serve sampling noise. Here every run uses the SAME fixed serves (common random numbers), so a run's score
differs from another's only through its parameters (and the chaotic per-serve flips), and a two-level random design over F
parameters (R runs, R > F) is regressed on the coded levels: the coefficient of factor j is its main effect on the mean score.

    .venv-myo/bin/python playground/tt_rsm.py design --params P --controller C --factors "z_bias:-0.09:-0.05,..." \
        --pool fh --n 100 --runs 32 --out out/tt_r10/rsm_fh1 [--set k=v,...]
    .venv-myo/bin/python playground/tt_rsm.py analyze --out out/tt_r10/rsm_fh1
    .venv-myo/bin/python playground/tt_rsm.py step --out out/tt_r10/rsm_fh1 --scale 1.0 --write params/x.txt

Factors are `name:low:high` (the two levels; the baseline is the params file's value, or the midpoint when absent).
Score per serve: solved + 0.4 (slack + 1.2) / 1.5 (see tt_practice.serve_score); runs are appended to <out>/runs.jsonl and the
design resumes where it stopped.
"""

import argparse
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy as np  # noqa: E402

import tt_fast  # noqa: E402
from tt_practice import serve_score  # noqa: E402


def parse_factors(s):
    fs = []
    for kv in s.split(","):
        n, lo, hi = kv.split(":")
        fs.append((n, float(lo), float(hi)))
    return fs


def make_design(F, R, seed):
    rng = np.random.default_rng(seed)
    best = None
    for _ in range(400):
        D = rng.choice([-1.0, 1.0], size=(R, F))
        # balance each column (equal +/-), then keep the design with the smallest column correlations
        for j in range(F):
            s = D[:, j].sum()
            while abs(s) > 1e-9:
                idx = np.nonzero(D[:, j] == np.sign(s))[0]
                D[rng.choice(idx), j] *= -1
                s = D[:, j].sum()
        C = np.abs(np.corrcoef(D.T) - np.eye(F)).max() if F > 1 else 0.0
        if best is None or C < best[0]:
            best = (C, D.copy())
    return best[1]


def pool_seeds(pool, n, pools_file, offset=0):
    if pool == "all":
        return list(range(740000 + offset, 740000 + offset + n))
    P = json.load(open(pools_file))
    return P["fh" if pool == "fh" else "bh"][offset:offset + n]


def cmd_design(a):
    os.environ.setdefault("TT_ENV", "P2")
    os.makedirs(a.out, exist_ok=True)
    params = tt_fast.read_params(a.params)
    for kv in filter(None, a.set.split(",")):
        k, v = kv.split("=")
        params[k] = float(v)
    fs = parse_factors(a.factors)
    D = make_design(len(fs), a.runs, a.seed)
    meta = {"factors": fs, "design": D.tolist(), "pool": a.pool, "n": a.n, "offset": a.offset, "controller": a.controller, "params": a.params, "set": a.set}
    json.dump(meta, open(os.path.join(a.out, "design.json"), "w"))
    seeds = pool_seeds(a.pool, a.n, a.pools_file, a.offset)
    ctl = os.path.abspath(a.controller)
    path = os.path.join(a.out, "runs.jsonl")
    done = set()
    if os.path.exists(path):
        done = {json.loads(l)["run"] for l in open(path) if l.strip()}
    pool = tt_fast.pool(a.workers)
    f = open(path, "a")
    t0 = time.time()
    # run 0: the baseline (all factors at the params file's values)
    runs = [(-1, None)] + [(r, D[r]) for r in range(a.runs)]
    for r, lev in runs:
        if r in done:
            continue
        p = dict(params)
        if lev is not None:
            for (n, lo, hi), x in zip(fs, lev):
                p[n] = lo if x < 0 else hi
        rows = pool.map(tt_fast.episode, [(dict(p), s, None, ctl) for s in seeds], chunksize=1)
        sc = [serve_score(x) for x in rows]
        rec = {"run": r, "score": float(np.mean(sc)), "solved": float(np.mean([x.get("solved", 0) for x in rows if "error" not in x])),
               "hit": float(np.mean([x.get("hit", 0) for x in rows if "error" not in x])), "scores": [round(float(v), 4) for v in sc],
               "wall_s": round(time.time() - t0)}
        f.write(json.dumps(rec) + "\n")
        f.flush()
        print(json.dumps({k: v for k, v in rec.items() if k != "scores"}), flush=True)


def load_runs(out):
    meta = json.load(open(os.path.join(out, "design.json")))
    runs = [json.loads(l) for l in open(os.path.join(out, "runs.jsonl")) if l.strip()]
    return meta, runs


def cmd_analyze(a):
    meta, runs = load_runs(a.out)
    fs = meta["factors"]
    D = np.array(meta["design"])
    rr = [r for r in runs if r["run"] >= 0]
    base = [r for r in runs if r["run"] < 0]
    X = D[[r["run"] for r in rr]]
    y = np.array([r["score"] for r in rr])
    ys = np.array([r["solved"] for r in rr])
    A = np.c_[np.ones(len(rr)), X]
    lam = 1e-3
    w = np.linalg.solve(A.T @ A + lam * np.eye(A.shape[1]), A.T @ y)
    res = y - A @ w
    dof = max(len(rr) - A.shape[1], 1)
    s2 = (res ** 2).sum() / dof
    cov = s2 * np.linalg.inv(A.T @ A + lam * np.eye(A.shape[1]))
    se = np.sqrt(np.diag(cov))
    ws = np.linalg.solve(A.T @ A + lam * np.eye(A.shape[1]), A.T @ ys)
    print(f"{len(rr)} runs; baseline score {base[0]['score']:.4f} solved {base[0]['solved']:.3f}" if base else f"{len(rr)} runs")
    print(f"run scores: mean {y.mean():.4f} sd {y.std():.4f}; best {y.max():.4f}; residual sd {np.sqrt(s2):.4f}")
    print(f"{'factor':<14}{'low':>9}{'high':>9}{'effect(score)':>15}{'+-se':>8}{'t':>6}{'effect(solved)':>16}")
    for j, (n, lo, hi) in enumerate(fs):
        print(f"{n:<14}{lo:>9.4g}{hi:>9.4g}{2 * w[1 + j]:>15.4f}{2 * se[1 + j]:>8.4f}{w[1 + j] / se[1 + j]:>6.1f}{2 * ws[1 + j]:>16.4f}")
    return meta, w, se


def cmd_step(a):
    meta, w, se = cmd_analyze(a)
    fs = meta["factors"]
    params = tt_fast.read_params(meta["params"])
    for kv in filter(None, meta["set"].split(",")):
        k, v = kv.split("=")
        params[k] = float(v)
    new = dict(params)
    for j, (n, lo, hi) in enumerate(fs):
        if abs(w[1 + j]) < a.min_t * se[1 + j]:
            continue
        # the coded level moves from -1 (lo) to +1 (hi); step `scale` levels in the direction of gain from the midpoint
        mid = 0.5 * (lo + hi)
        new[n] = mid + np.sign(w[1 + j]) * a.scale * 0.5 * (hi - lo)
    print("step:", {n: round(new[n], 5) if n in new else "(default)" for n, _, _ in fs})
    if a.write:
        with open(a.write, "w") as f:
            f.write(f"# tt_rsm step from {a.out} (scale {a.scale}, min_t {a.min_t})\n")
            for k in sorted(new):
                f.write(f"{k} {float(new[k])!r}\n")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    d = sub.add_parser("design")
    d.add_argument("--params", required=True)
    d.add_argument("--controller", required=True)
    d.add_argument("--factors", required=True)
    d.add_argument("--set", default="")
    d.add_argument("--pool", default="fh", choices=["fh", "bh", "all"])
    d.add_argument("--pools_file", default=os.path.join(HERE, "..", "out", "tt_r10", "pools_740000.json"))
    d.add_argument("--n", type=int, default=100)
    d.add_argument("--offset", type=int, default=0, help="first pool serve used (a fresh block for a second stage)")
    d.add_argument("--runs", type=int, default=32)
    d.add_argument("--seed", type=int, default=1)
    d.add_argument("--workers", type=int, default=3)
    d.add_argument("--out", required=True)
    an = sub.add_parser("analyze")
    an.add_argument("--out", required=True)
    st = sub.add_parser("step")
    st.add_argument("--out", required=True)
    st.add_argument("--scale", type=float, default=1.0)
    st.add_argument("--min_t", type=float, default=1.0)
    st.add_argument("--write")
    a = ap.parse_args()
    {"design": cmd_design, "analyze": cmd_analyze, "step": cmd_step}[a.cmd](a)


if __name__ == "__main__":
    main()
