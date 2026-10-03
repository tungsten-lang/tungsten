"""ljx_robust: long_jump_limits.py's `robust` stage (one closed-loop take-off program, learned over many captured penultimate-touchdown
states of both plant sides, with gap knots and a reflex gain) with L3's objective terms for the LABELLED BEYOND-HUMAN body:

  score per start = board_score (distance from the line, a foot past line - margin is a graded foul, -0.1 per free-foot tick, -0.2 per unit of
                    forward L above --lmax, -2 per rad of take-off pitch outside [-0.5, 0.8])
                    - 0.2 per unit of BACKWARD L below --lmin
                    - --grfw per body weight of the plant foot's 12 ms-averaged normal force above --grfcap
  candidate score = mean - risk (mean - min) over the starts.

Same program format as the harness (`write_program`), so `handover`, `landing` and the skill read the output.
    ljx_robust.py <base ik file> --captures a,b,c --nk 24 --evals 400000 --out prog.txt [--init prog0.txt] [--risk 0.3 --sigma 0.03 --pop 100 --g0 0.3]
                  [--lmax -1.5 --lmin -15 --grfcap 20 --grfw 0.3 --margin 0.03 --post 0.24 --workers 6]
    ljx_robust.py --eval prog.txt --captures a,b,c   (per-start table of a finished program)
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
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mujoco  # noqa: E402
import numpy as np  # noqa: E402

import long_jump_limits as L  # noqa: E402
import ljx  # noqa: E402

_R = {}
KCS = 40.0       # kc gain scale: a gene in [0, 1] is (x - 0.5) KCS per metre of foot-height deficit
CLZ0, CLZW = 0.03, 0.22   # clearance height: CLZ0 + CLZW x


def with_kc(tab, x, nk, n):
    """Add the swing-foot clearance reflex tables (skill: ik_clz, ik_clt, ik_kc_<role>; harness: IKProgram's ckc / clz / clt) from the tail genes."""
    o = 3 * nk * n + 1
    tab = dict(tab)
    tab["ckc"] = (np.asarray(x[o:o + n]) - 0.5) * KCS
    tab["clz"] = CLZ0 + CLZW * float(np.clip(x[o + n], 0.0, 1.0))
    tab["clt"] = 0.04
    return tab


def simulate_prog2(body, cap, prog):
    """long_jump_limits.simulate_prog with ljx.simulate2 (ground force recorded)."""
    m, d = body.m, body.d
    mujoco.mj_setState(m, d, cap["state"], L.SPEC)
    mujoco.mj_forward(m, d)
    prog.start(body, cap)
    until = None
    if prog.end is not None:
        until = lambda t: prog.td_seen and t + prog.shift > prog.end
    return ljx.simulate2(body, cap, lambda t, k: prog(body, t, k), restore=False, until=until)


def _rworker(names, cfg):
    _R["caps"] = [L.load_capture(n) for n in names]
    c0 = _R["caps"][0]
    _R["body"] = L.Body(c0["task"], c0["board_x"], json.loads(c0["env"]))
    _R["cfg"] = cfg


def _reval(job):
    x, base, meta = job
    body, caps, cfg = _R["body"], _R["caps"], _R["cfg"]
    tab, g = L._decode(np.asarray(x), base, meta["nk"], len(body.muscles))
    if meta.get("kc"):
        tab = with_kc(tab, x, meta["nk"], len(body.muscles))
    if meta.get("fmin") is not None:
        tab = dict(tab)
        tab["fmin"] = meta["fmin"]
    prog = L.IKProgram(tab, meta["h"], meta["td"], g, 1.0, meta["kp"], meta["kd"], meta["gap0"], meta.get("end"))
    prog_m = None
    scores, rows = [], []
    for cap in caps:
        pr = prog
        if cap["plant"] != meta.get("p0", cap["plant"]):
            if prog_m is None:
                prog_m = L.IKProgram(L.mirror_tab(tab, L.side_perm(body.muscles)), meta["h"], meta["td"], g, 1.0, meta["kp"], meta["kd"],
                                     meta["gap0"], meta.get("end"))
            pr = prog_m
        r = simulate_prog2(body, cap, pr)
        scores.append(max(ljx.score2(r, cap, cfg), meta.get("floor", -1e9)))
        rows.append({k: r.get(k) for k in ("D", "vx", "vz", "contact_s", "toe_max", "valid", "L", "grf12_bw", "knee_pk")})
    sc = np.array(scores)
    mean = float(sc.mean())
    tq = meta.get("tailq", 0.0)
    worst = float(np.sort(sc)[:max(1, int(round(tq * len(sc))))].mean()) if tq > 0 else float(sc.min())
    return mean - meta["risk"] * (mean - worst), {"mean": mean, "min": float(sc.min()), "scores": scores}


def write_program2(path, x, base, meta, n, mus, plant, pfile, best, gaps):
    L.write_program(path, x, base, meta, n, mus, plant, pfile, best, gaps)
    if meta.get("fmin") is not None:
        with open(path, "a") as f:
            f.write(f"ik_fmin {meta['fmin']!r}\n")
    if meta.get("kc"):
        t = with_kc({}, x, meta["nk"], n)
        with open(path, "a") as f:
            f.write(f"ik_clz {t['clz']!r}\nik_clt {t['clt']!r}\n")
            for i, nm in enumerate(mus):
                f.write(f"ik_kc_{L.role_of(nm, plant)} {float(t['ckc'][i])!r}\n")


def setup(a):
    from search import read_params
    names = [n for n in a.captures.split(",") if n]
    caps = [L.load_capture(n) for n in names]
    body = L.Body(caps[0]["task"], caps[0]["board_x"], json.loads(caps[0]["env"]))
    mus = body.muscles
    params = json.loads(caps[0]["params"])
    kp, kd = L.reflex_gains(mus, params)
    gaps = []
    for cap in caps:
        mujoco.mj_setState(body.m, body.d, cap["state"], L.SPEC)
        mujoco.mj_forward(body.m, body.d)
        pen = "l" if cap["plant"] == "r" else "r"
        gaps.append(cap["board_x"] - L.seen_site_x(body, f"{pen}_toe"))
    return names, caps, body, mus, kp, kd, gaps


def cfg_of(a):
    return {"board": True, "margin": a.margin, "lmax": float(a.lmax), "lmin": float(a.lmin), "grfcap": float(a.grfcap), "grfw": float(a.grfw),
            "td": 0.0, "tdw": 20.0, "kneeload": float(a.kneeload), "kneew": float(a.kneew)}


def run(a):
    from search import make_optimizer, read_params
    names, caps, body, mus, kp, kd, gaps = setup(a)
    cfg = cfg_of(a)
    pfile, base = L.read_ik(a.ik, mus, caps[0]["plant"], nk=a.nk)
    gap0 = float(np.median(gaps)) if a.gap0 is None else a.gap0
    meta = {"nk": a.nk, "h": pfile["ik_h"], "td": pfile["ik_td"], "kp": kp, "kd": kd, "gap0": gap0, "lmax": float(a.lmax), "risk": a.risk,
            "end": pfile["ik_td"] + a.post, "p0": caps[0]["plant"], "tailq": a.tailq, "kc": a.kc, "fmin": a.fmin, "floor": a.floor}
    n = len(mus)
    x0 = np.concatenate([np.clip(base["e"], 0, 1).ravel(), np.full(a.nk * n, 0.5), np.full(a.nk * n, 0.5), [a.g0 / 1.5]])
    if a.init:
        pi = read_params(a.init)
        ni = int(round(pi["ik_n"]))
        _, ti = L.read_ik(a.init, mus, caps[0]["plant"], nk=ni)
        ext = lambda A: np.vstack([A[:a.nk]] + [A[-1:]] * max(0, a.nk - ni))
        E0 = np.clip(ext(ti["e"]), 0, 1)
        dC0 = np.clip((ext(ti["c"]) - base["c"]) / 0.2 + 0.5, 0, 1)
        G0 = np.clip(ext(ti["e1"]) / 4.0 + 0.5, 0, 1)
        x0 = np.concatenate([E0.ravel(), dC0.ravel(), G0.ravel(), [pi.get("j_ik_g", a.g0) / 1.5]])
        meta["gap0"] = pi.get("ik_gap0", gap0)
        if a.kc and "ik_clz" in pi:
            kc0 = np.array([pi.get(f"ik_kc_{L.role_of(nm, caps[0]['plant'])}", 0.0) for nm in mus]) / KCS + 0.5
            x0 = np.concatenate([x0, np.clip(kc0, 0.0, 1.0), [float(np.clip((pi["ik_clz"] - CLZ0) / CLZW, 0.0, 1.0))]])
    if a.kc and len(x0) == 3 * a.nk * n + 1:
        x0 = np.concatenate([x0, np.full(n, 0.5), [0.3]])
    print(f"robust2: {len(caps)} starts, gaps {np.round(gaps, 2).tolist()} (gap0 {meta['gap0']:.3f}), {len(x0)} dims, cfg {cfg}", flush=True)
    opt = make_optimizer("sep_cma", x0, sigma0=a.sigma, seed=a.seed, **({"popsize": a.pop} if a.pop else {}))
    t0 = time.time()
    used = 0
    with mp.Pool(a.workers, initializer=_rworker, initargs=(names, cfg)) as pool:
        f0, m0 = pool.apply(_reval, ((x0, base, meta),))
        best = (f0, x0.copy(), m0)
        print(f"x0 {f0:.3f} {json.dumps({k: round(v, 3) for k, v in m0.items() if k != 'scores'})} {np.round(m0['scores'], 2).tolist()}", flush=True)
        gen = 0
        while used < a.evals:
            X = np.clip(np.atleast_2d(opt.ask()), 0.0, 1.0)
            if a.only_e:
                X[:, a.nk * n:] = x0[a.nk * n:]   # only the excitation knots are free (the per-state fits of the regression experiment)
            res = pool.map(_reval, [(x, base, meta) for x in X], chunksize=max(1, len(X) // (a.workers * 2)))
            f = np.array([r[0] for r in res])
            opt.tell(X, f, [r[1] for r in res])
            used += len(X) * len(caps)
            gen += 1
            i = int(np.argmax(f))
            if f[i] > best[0]:
                best = (float(f[i]), X[i].copy(), res[i][1])
            if gen % 10 == 0:
                bm = best[2]
                print(f"gen {gen} sims {used} best {best[0]:.3f} mean {bm['mean']:.3f} min {bm['min']:.3f} sigma {opt.sigma:.4f} ({time.time() - t0:.0f}s)", flush=True)
                write_program2(a.out, best[1], base, meta, n, mus, caps[0]["plant"], pfile, best, gaps)
    write_program2(a.out, best[1], base, meta, n, mus, caps[0]["plant"], pfile, best, gaps)
    print("best", best[0], json.dumps({k: v for k, v in best[2].items() if k != "scores"}), np.round(best[2]["scores"], 2).tolist(), flush=True)


def evaluate(a):
    """Per-start table of a finished robust program on the captures."""
    from search import read_params
    names, caps, body, mus, kp, kd, gaps = setup(a)
    cfg = cfg_of(a)
    pf = read_params(a.eval)
    nk = int(round(pf["ik_n"]))
    rows = []
    for nm, cap, gp in zip(names, caps, gaps):
        _, tab = L.read_ik(a.eval, mus, cap["plant"], nk=nk)
        if a.fmin is not None:
            tab["fmin"] = a.fmin
        gg = pf["j_ik_g"] if a.g is None else a.g
        prog = L.IKProgram(tab, pf["ik_h"], pf["ik_td"], gg, pf.get("j_ik_kdc", 1.0), kp, kd, pf["ik_gap0"] if a.gap0 is None else a.gap0, pf["ik_end"])
        r = simulate_prog2(body, cap, prog)
        s = ljx.score2(r, cap, cfg)
        rows.append((nm, cap["plant"], gp, r, s))
        if r["valid"]:
            print("%-14s %s gap %.3f score %6.2f D_board %.3f off %+.3f vx %.2f vz %.2f L %6.1f contact %.3f grf12 %.1f%s" % (
                nm, cap["plant"], gp, s, r["D"] - (cap["board_x"] - r["toe_max"]), r["toe_max"] - cap["board_x"], r["vx"], r["vz"], r["L"],
                r["contact_s"], r["grf12_bw"], "  FOUL" if r["toe_max"] > cap["board_x"] else ""))
        else:
            print("%-14s %s gap %.3f INVALID %s" % (nm, cap["plant"], gp, r.get("why")))
    sc = np.array([x[4] for x in rows])
    nval = sum(1 for x in rows if x[3]["valid"])
    nfoul = sum(1 for x in rows if x[3]["valid"] and x[3]["toe_max"] > caps[names.index(x[0])]["board_x"] - cfg["margin"])
    legal = sc[sc > 0]
    print("SUMMARY %d starts: valid %d, fouls/too close %d, legal(score>0) %d, score mean %.3f (all) / %.3f (legal), min %.3f" % (
        len(rows), nval, nfoul, len(legal), sc.mean(), legal.mean() if len(legal) else 0.0, sc.min()))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ik", nargs="?")
    ap.add_argument("--eval")
    ap.add_argument("--captures", required=True)
    ap.add_argument("--nk", type=int, default=24)
    ap.add_argument("--evals", type=int, default=400000, help="simulations (candidates x starts)")
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--sigma", type=float, default=0.03)
    ap.add_argument("--pop", type=int, default=100)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--lmax", default="-1.5")
    ap.add_argument("--lmin", default="-15")
    ap.add_argument("--grfcap", default="20")
    ap.add_argument("--grfw", default="0.3")
    ap.add_argument("--margin", type=float, default=0.03)
    ap.add_argument("--risk", type=float, default=0.3)
    ap.add_argument("--kc", action="store_true", help="also learn the swing-foot clearance reflex (32 gains + its height) on the plant-side foot")
    ap.add_argument("--fmin", type=float, default=None, help="the plant-touchdown latch needs this many body weights of force (skill: ik_fmin; 1.5 ignores a scuffing swing foot)")
    ap.add_argument("--g", type=float, default=None, help="--eval: override the program's reflex gain j_ik_g")
    ap.add_argument("--floor", type=float, default=-1e9, help="per-start score floor: a failed start costs at most this (the arena scores a failure 0)")
    ap.add_argument("--only-e", dest="only_e", action="store_true", help="only the excitation knots are free; c / gap knots / gain stay at the init")
    ap.add_argument("--kneeload", type=float, default=0.0, help="the plant knee must be flexed at least this much (rad) at the instant of the largest plant-foot force")
    ap.add_argument("--kneew", type=float, default=10.0)
    ap.add_argument("--tailq", type=float, default=0.0, help="the risk term uses the mean of the worst tailq fraction of the starts instead of the single worst")
    ap.add_argument("--g0", type=float, default=0.3)
    ap.add_argument("--gap0", type=float, default=None)
    ap.add_argument("--post", type=float, default=0.04, help="program time after the ideal touchdown at which the program hands over")
    ap.add_argument("--init")
    ap.add_argument("--out")
    a = ap.parse_args()
    evaluate(a) if a.eval else run(a)


if __name__ == "__main__":
    main()
