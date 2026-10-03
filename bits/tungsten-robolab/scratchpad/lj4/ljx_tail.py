"""ljx_tail (agent L4): per-regime post-touchdown offsets on top of a FIXED robust take-off program (harness only; see rgprog.py).

LABELLED BEYOND-HUMAN BODY, UNLIMITED RUN-UP, check mark 151.025. The base program is read from a params file (the output of ljx_robust.py). A state's regime is decided by the base
program's own plant touchdown time T (before any offset exists): early T < t1, late T > t2.

    ljx_tail.py analyse <prog> --captures a,b,c [--fmin 1.5]                     touchdown-time distribution and score by bin
    ljx_tail.py train   <prog> --captures a,b,c --regime 1|2 --t1 .. --t2 .. --evals N --out tail_r.npz [--sigma --pop --risk --workers 6]
    ljx_tail.py eval    <prog> --captures a,b,c --tails tail_1.npz[,tail_2.npz] --t1 .. --t2 ..   score of the base and of base + tails, by regime
"""
import argparse
import json
import math
import multiprocessing as mp
import os
import sys
import time

os.environ.setdefault("MUJOCO_GL", "cgl")
HERE = "/Users/erik/tungsten/bits/tungsten-robolab/playground"
sys.path.insert(0, HERE)
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj3")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np  # noqa: E402
import long_jump_limits as L  # noqa: E402
import ljx  # noqa: E402
import ljx_robust  # noqa: E402
import rgprog  # noqa: E402

_R = {}
CFG = {"board": True, "margin": 0.03, "lmax": -1.5, "lmin": -15.0, "grfcap": 20.0, "grfw": 0.3, "td": 0.0, "tdw": 20.0, "kneeload": 0.0, "kneew": 10.0}


def load_base(prog_path, body, plant, fmin):
    from search import read_params
    pf = read_params(prog_path)
    nk = int(round(pf["ik_n"]))
    _, tab = L.read_ik(prog_path, body.muscles, plant, nk=nk)
    if fmin is not None:
        tab["fmin"] = fmin
    return pf, tab


def make_prog(body, cap, pf, tab, kp, kd, rg, perm, p0):
    """A RegimeIK for this capture; rg is in the muscle order of plant side p0 (mirrored for the other side)."""
    rgc = None
    if rg is not None:
        if cap["plant"] != p0:
            rgc = dict(rg)
            rgc["de"] = {r: a[:, perm] for r, a in rg["de"].items()}
            rgc["dc"] = {r: a[:, perm] for r, a in rg["dc"].items()}
        else:
            rgc = rg
    return rgrog_cls()(tab, pf["ik_h"], pf["ik_td"], pf["j_ik_g"], pf.get("j_ik_kdc", 1.0), kp, kd, pf["ik_gap0"], pf["ik_end"], rgc)


def rgrog_cls():
    return rgprog.RegimeIK


def _init(names, prog_path, fmin):
    caps = [L.load_capture(n) for n in names]
    body = L.Body(caps[0]["task"], caps[0]["board_x"], json.loads(caps[0]["env"]))
    kp, kd = L.reflex_gains(body.muscles, json.loads(caps[0]["params"]))
    p0 = caps[0]["plant"]
    perm = L.side_perm(body.muscles)
    tabs, pf = [], None
    for cap in caps:
        pf, tab = load_base(prog_path, body, cap["plant"], fmin)
        tabs.append(tab)
    _R.update(caps=caps, body=body, kp=kp, kd=kd, perm=perm, p0=p0, tabs=tabs, pf=pf, names=names)


def run_state(i, rg):
    cap, body, pf = _R["caps"][i], _R["body"], _R["pf"]
    prog = make_prog(body, cap, pf, _R["tabs"][i], _R["kp"], _R["kd"], rg, _R["perm"], _R["p0"])
    r = ljx_robust.simulate_prog2(body, cap, prog)
    return r, prog


def score_state(i, rg):
    r, prog = run_state(i, rg)
    return ljx.score2(r, _R["caps"][i], CFG), r, prog


def _members_job(i):
    r, prog = run_state(i, None)
    # the touchdown time of the base program: recorded through a probe run
    return i


def decode(x, regimes, nd, n):
    """x: concatenated genes of the listed regimes, each (2 * nd * n)."""
    de, dc = {}, {}
    o = 0
    for r in regimes:
        blk = np.asarray(x[o:o + 2 * nd * n])
        de[r] = (blk[:nd * n].reshape(nd, n) - 0.5) * rgprog.DE_SCALE
        dc[r] = (blk[nd * n:].reshape(nd, n) - 0.5) * rgprog.DC_SCALE
        o += 2 * nd * n
    return de, dc


def _eval_cand(job):
    x, regimes, idxs, t1, t2, risk, tailq = job
    n = len(_R["body"].muscles)
    nd = len(rgprog.TAU_KNOTS)
    de, dc = decode(x, regimes, nd, n)
    rg = {"t1": t1, "t2": t2, "knots": rgprog.TAU_KNOTS, "de": de, "dc": dc}
    sc = np.array([score_state(i, rg)[0] for i in idxs])
    mean = float(sc.mean())
    worst = float(np.sort(sc)[:max(1, int(round(tailq * len(sc))))].mean()) if tailq > 0 else float(sc.min())
    return mean - risk * (mean - worst), {"mean": mean, "min": float(sc.min()), "scores": sc.tolist()}


def regime_of_all(t1, t2):
    out = []
    for i in range(len(_R["caps"])):
        r, prog = run_state(i, None)
        if not r["valid"]:
            out.append((None, -5.0))
            continue
        out.append((prog.t_touch if prog.t_touch is not None else r["td"]["t"], ljx.score2(r, _R["caps"][i], CFG)))
    return out


def cmd_analyse(a):
    names = a.captures.split(",")
    _init(names, a.prog, a.fmin)
    rows = regime_of_all(a.t1, a.t2)
    edges = [0, 0.1, 0.15, 0.2, 0.22, 0.24, 0.26, 0.28, 0.30, 0.35, 0.4, 9]
    T = np.array([r[0] if r[0] is not None else -1 for r in rows])
    S = np.array([r[1] for r in rows])
    print("%d states, mean score %.3f" % (len(rows), S.mean()))
    for lo, hi in zip(edges[:-1], edges[1:]):
        m = (T >= lo) & (T < hi)
        if m.sum():
            print("touchdown T [%.2f, %.2f): n %3d  mean score %6.2f  legal %3d" % (lo, hi, m.sum(), S[m].mean(), int((S[m] > 0).sum())))
    print("invalid:", int((T < 0).sum()))


def cmd_train(a):
    from search import make_optimizer
    names = a.captures.split(",")
    prog_path = a.prog
    base_rows = None
    mp_ctx = mp.get_context("spawn")
    _init(names, prog_path, a.fmin)
    rows = regime_of_all(a.t1, a.t2)
    reg = a.regime
    idxs = [i for i, r in enumerate(rows) if r[0] is not None and ((reg == 1 and r[0] < a.t1) or (reg == 2 and r[0] > a.t2))]
    base_sc = np.array([rows[i][1] for i in idxs])
    print(f"regime {reg}: {len(idxs)} of {len(names)} training states (t1 {a.t1}, t2 {a.t2}); base mean {base_sc.mean():.3f} min {base_sc.min():.3f}", flush=True)
    n = len(_R["body"].muscles)
    nd = len(rgprog.TAU_KNOTS)
    dim = 2 * nd * n
    x0 = np.full(dim, 0.5)
    opt = make_optimizer("sep_cma", x0, sigma0=a.sigma, seed=a.seed, **({"popsize": a.pop} if a.pop else {}))
    best = (-1e9, x0.copy(), None)
    used = 0
    gen = 0
    t0 = time.time()
    with mp_ctx.Pool(a.workers, initializer=_init, initargs=(names, prog_path, a.fmin)) as pool:
        f0, m0 = pool.apply(_eval_cand, ((x0, [reg], idxs, a.t1, a.t2, a.risk, a.tailq),))
        best = (f0, x0.copy(), m0)
        print(f"x0 (zero offsets) {f0:.3f} mean {m0['mean']:.3f} min {m0['min']:.3f}", flush=True)
        while used < a.evals:
            X = np.clip(np.atleast_2d(opt.ask()), 0.0, 1.0)
            res = pool.map(_eval_cand, [(x, [reg], idxs, a.t1, a.t2, a.risk, a.tailq) for x in X], chunksize=max(1, len(X) // (a.workers * 2)))
            f = np.array([r[0] for r in res])
            opt.tell(X, f, [r[1] for r in res])
            used += len(X) * len(idxs)
            gen += 1
            i = int(np.argmax(f))
            if f[i] > best[0]:
                best = (float(f[i]), X[i].copy(), res[i][1])
            if gen % 10 == 0:
                print(f"gen {gen} sims {used} best {best[0]:.3f} mean {best[2]['mean']:.3f} min {best[2]['min']:.3f} sigma {opt.sigma:.4f} ({time.time() - t0:.0f}s)", flush=True)
                np.savez(a.out, x=best[1], regime=reg, nd=nd, t1=a.t1, t2=a.t2, idxs=np.array(idxs), names=np.array(names))
    np.savez(a.out, x=best[1], regime=reg, nd=nd, t1=a.t1, t2=a.t2, idxs=np.array(idxs), names=np.array(names))
    print("best", best[0], "mean", best[2]["mean"], "min", best[2]["min"], flush=True)


def cmd_eval(a):
    names = a.captures.split(",")
    _init(names, a.prog, a.fmin)
    n = len(_R["body"].muscles)
    nd = len(rgprog.TAU_KNOTS)
    de, dc = {}, {}
    for pth in [p for p in a.tails.split(",") if p]:
        z = np.load(pth)
        d1, c1 = decode(z["x"], [int(z["regime"])], nd, n)
        de.update(d1)
        dc.update(c1)
    rg = {"t1": a.t1, "t2": a.t2, "knots": rgprog.TAU_KNOTS, "de": de, "dc": dc}
    rows = []
    for i in range(len(names)):
        s0, r0, p0 = score_state(i, None)
        s1, r1, p1 = score_state(i, rg)
        rows.append((p0.t_touch if (r0["valid"] and p0.t_touch is not None) else -1, s0, s1, p1.regime if r1["valid"] else -1))
    A = np.array(rows, float)
    print("%d states: base mean %.3f, base + tails mean %.3f (legal %d -> %d)" % (len(rows), A[:, 1].mean(), A[:, 2].mean(), int((A[:, 1] > 0).sum()), int((A[:, 2] > 0).sum())))
    for reg, lab in ((0, "normal"), (1, "early"), (2, "late")):
        m = A[:, 3] == reg
        if m.sum():
            print("  regime %-6s n %3d  base %.3f  with tails %.3f  (min %.2f -> %.2f)" % (lab, m.sum(), A[m, 1].mean(), A[m, 2].mean(), A[m, 1].min(), A[m, 2].min()))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["analyse", "train", "eval"])
    ap.add_argument("prog")
    ap.add_argument("--captures", required=True)
    ap.add_argument("--fmin", type=float, default=None)
    ap.add_argument("--t1", type=float, default=0.20)
    ap.add_argument("--t2", type=float, default=0.26)
    ap.add_argument("--regime", type=int, default=1)
    ap.add_argument("--evals", type=int, default=100000)
    ap.add_argument("--sigma", type=float, default=0.05)
    ap.add_argument("--pop", type=int, default=0)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--risk", type=float, default=0.3)
    ap.add_argument("--tailq", type=float, default=0.1)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--out")
    ap.add_argument("--tails", default="")
    a = ap.parse_args()
    {"analyse": cmd_analyse, "train": cmd_train, "eval": cmd_eval}[a.cmd](a)


if __name__ == "__main__":
    main()
