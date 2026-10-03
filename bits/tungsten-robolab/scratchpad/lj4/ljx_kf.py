"""ljx_kf (agent L4): learn the swing-foot LAG feedback (skill: ik_fx<k> reference knots, ik_fxmax, ik_kf_<role>; harness: IKProgram's fxr / fxmax / fkf) on top of a FIXED robust take-off program.
LABELLED BEYOND-HUMAN BODY, UNLIMITED RUN-UP, check mark 151.025. While the plant-side foot has not touched down, the lag = clip(fxr(s) - (foot x - COM x), 0, fxmax) (the foot behind the program's own average
foot-ahead-of-COM trajectory) adds kf_role x lag to every muscle's drive. fxr is the program's mean trajectory over the training states; the 32 role gains are learned by sep-CMA on the official-like
score (clipped at 0) with a tail term. Writes the program file with the ik_fx / ik_kf_ lines added.
    ljx_kf.py train <prog> --captures a,b,c --out prog_kf.txt [--evals --sigma --kfs 20 --workers 6 --risk 0.2 --fmin 1.5]
    ljx_kf.py eval  <prog> <prog_kf> --captures a,b,c
"""
import argparse, json, multiprocessing as mp, os, sys, time
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj3")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj4")
import numpy as np
import long_jump_limits as L
import ljx, ljx_robust, ljx_tail
from search import read_params

CFG = ljx_tail.CFG
_R = {}


def _init(names, prog_path, fmin):
    ljx_tail._init(names, prog_path, fmin)
    R = ljx_tail._R
    mus = R["body"].muscles
    R["roles"] = sorted({L.role_of(m_, "r") for m_ in mus})
    # the program's mean foot-ahead-of-COM trajectory over the states (RecProg), once per process
    pf = R["pf"]
    meta = {"h": pf["ik_h"], "nk": int(round(pf["ik_n"])), "td": pf["ik_td"], "g": pf["j_ik_g"], "kdc": pf.get("j_ik_kdc", 1.0), "kp": R["kp"], "kd": R["kd"], "gap0": pf["ik_gap0"], "end": pf["ik_end"]}
    R["meta"] = meta
    bases = {}
    for cap, tab in zip(R["caps"], R["tabs"]):
        bases[cap["plant"]] = tab
    _, fxr = L.nominal_pitch(R["body"], R["caps"], bases, meta, with_foot=True)
    R["fxr"] = fxr
    _R.update(R)


def kf_tab(base_tab, plant, gains, fxr, fxmax, mus, roles):
    tab = dict(base_tab)
    tab["fxr"] = fxr
    tab["fxmax"] = fxmax
    tab["fkf"] = np.array([gains[roles.index(L.role_of(m_, plant))] for m_ in mus])
    return tab


def score_all(gains, idxs, fxmax, collect=False):
    R = _R
    mus = R["body"].muscles
    out = []
    for i in idxs:
        cap = R["caps"][i]
        tab = kf_tab(R["tabs"][i], cap["plant"], gains, R["fxr"], fxmax, mus, R["roles"]) if gains is not None else R["tabs"][i]
        pf = R["pf"]
        prog = L.IKProgram(tab, pf["ik_h"], pf["ik_td"], pf["j_ik_g"], pf.get("j_ik_kdc", 1.0), R["kp"], R["kd"], pf["ik_gap0"], pf["ik_end"])
        r = ljx_robust.simulate_prog2(R["body"], cap, prog)
        out.append(max(ljx.score2(r, cap, CFG), 0.0) if r["valid"] else 0.0)
    return np.array(out)


def _cand(job):
    x, idxs, kfs, fxmax, risk, tailq = job
    gains = (np.asarray(x) - 0.5) * kfs
    sc = score_all(gains, idxs, fxmax)
    mean = float(sc.mean())
    worst = float(np.sort(sc)[:max(1, int(round(tailq * len(sc))))].mean())
    return mean - risk * (mean - worst), {"mean": mean}


def write_prog(path, base_path, gains, fxr, fxmax, roles):
    keep = [l.rstrip("\n") for l in open(base_path) if l.split() and not l.split()[0].startswith(("ik_fx", "ik_kf_"))]
    lines = keep + [f"ik_fx{k} {float(v)!r}" for k, v in enumerate(fxr)] + [f"ik_fxmax {float(fxmax)!r}"]
    lines += [f"ik_kf_{role} {float(g)!r}" for role, g in zip(roles, gains)]
    open(path, "w").write("\n".join(lines) + "\n")


def main():
    from search import make_optimizer
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["train", "eval"])
    ap.add_argument("prog")
    ap.add_argument("prog2", nargs="?")
    ap.add_argument("--captures", required=True)
    ap.add_argument("--out")
    ap.add_argument("--evals", type=int, default=150000)
    ap.add_argument("--sigma", type=float, default=0.1)
    ap.add_argument("--kfs", type=float, default=20.0)
    ap.add_argument("--fxmax", type=float, default=0.3)
    ap.add_argument("--risk", type=float, default=0.2)
    ap.add_argument("--tailq", type=float, default=0.1)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--fmin", type=float, default=1.5)
    a = ap.parse_args()
    names = a.captures.split(",")
    if a.cmd == "eval":
        _init(names, a.prog, a.fmin)
        base = score_all(None, range(len(names)), a.fxmax)
        pf2 = read_params(a.prog2)
        roles = _R["roles"]
        gains = np.array([pf2.get(f"ik_kf_{r}", 0.0) for r in roles])
        fxr = np.array([pf2[f"ik_fx{k}"] for k in range(int(round(pf2["ik_n"])))])
        _R["fxr"] = fxr
        kf = score_all(gains, range(len(names)), pf2.get("ik_fxmax", a.fxmax))
        print("%d states: base clipped mean %.3f (legal %d) | with kf %.3f (legal %d) | paired diff %.3f +- %.3f" % (
            len(names), base.mean(), int((base > 0).sum()), kf.mean(), int((kf > 0).sum()), (kf - base).mean(), (kf - base).std(ddof=1) / np.sqrt(len(base))))
        return
    _init(names, a.prog, a.fmin)
    roles = _R["roles"]
    fxr = _R["fxr"]
    idxs = list(range(len(names)))
    base = score_all(None, idxs, a.fxmax)
    print(f"{len(names)} training states; base clipped mean {base.mean():.3f}; fxr {np.round(fxr, 2).tolist()}", flush=True)
    x0 = np.full(len(roles), 0.5)
    opt = make_optimizer("sep_cma", x0, sigma0=a.sigma, seed=1)
    best = (-1e9, x0, None)
    used, gen, t0 = 0, 0, time.time()
    with mp.get_context("spawn").Pool(a.workers, initializer=_init, initargs=(names, a.prog, a.fmin)) as pool:
        f0, m0 = pool.apply(_cand, ((x0, idxs, a.kfs, a.fxmax, a.risk, a.tailq),))
        best = (f0, x0.copy(), m0)
        print(f"x0 {f0:.3f} mean {m0['mean']:.3f}", flush=True)
        while used < a.evals:
            X = np.clip(np.atleast_2d(opt.ask()), 0.0, 1.0)
            res = pool.map(_cand, [(x, idxs, a.kfs, a.fxmax, a.risk, a.tailq) for x in X], chunksize=max(1, len(X) // (a.workers * 2)))
            f = np.array([r[0] for r in res])
            opt.tell(X, f, [r[1] for r in res])
            used += len(X) * len(idxs)
            gen += 1
            i = int(np.argmax(f))
            if f[i] > best[0]:
                best = (float(f[i]), X[i].copy(), res[i][1])
            if gen % 10 == 0:
                print(f"gen {gen} sims {used} best {best[0]:.3f} mean {best[2]['mean']:.3f} sigma {opt.sigma:.4f} ({time.time() - t0:.0f}s)", flush=True)
                write_prog(a.out, a.prog, (best[1] - 0.5) * a.kfs, fxr, a.fxmax, roles)
    write_prog(a.out, a.prog, (best[1] - 0.5) * a.kfs, fxr, a.fxmax, roles)
    print("best", best[0], best[2], flush=True)


if __name__ == "__main__":
    main()
