"""ljx_risk: scratchpad/lj4/ljx_robust.py (L4) with UPPER-TAIL objectives for the best-of-six competition (agent L6), LABELLED beyond-human body, unlimited run-up.

Everything of ljx_robust.py is unchanged (same program format, same per-start score = ljx.score2: board distance, graded foul, forward-L / pitch / plant-force penalties,
`--floor` for failed starts) and the DEFAULT objective is ljx_robust's exactly (--obj mean: mean - risk (mean - worst tail)). New, opt-in aggregators of the per-start scores s_i
(floored by --floor, 0 = a failed start costs the whole mark, as the arena scores it):

  --obj convex  J = mean(s) + kappa mean(max(s - c, 0))           slope 1 below c m, 1 + kappa above: a convex reward on the long marks
  --obj topq    J = (1 - lam) mean(best topq fraction of s) + lam mean(s)
  --obj soft    J = mean(sigmoid((s - c) / tau)) + lam mean(s)    a smooth count of starts above c (the per-attempt P(mark > 8.95) surrogate)
  --obj mix     J = mean(sigmoid((s - c) / tau)) + a1 mean(max(s - c1, 0)) + a0 mean(s)   (CALIBRATED: official mark = D_board + 0.215 on average, residual sd 0.29, so c = 8.95 - 0.215 = 8.73)

--eval is parallel (--workers) and prints the tail of the per-start scores (counts at >= 8.5 / 9.0 / 9.15 / 9.5 / 10 m) beside the summary; --json writes the per-start rows.

    ljx_risk.py <base ik file> --captures a,b,c --nk 24 --evals N --out prog.txt --init prog0.txt --kc --fmin 1.5 --floor 0 --obj convex --c 8.0 --kappa 3 [ljx_robust flags]
    ljx_risk.py --eval prog.txt --captures a,b,c --fmin 1.5 [--workers 5] [--json rows.json] [--quiet]
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
TAIL_T = (8.0, 8.5, 8.73, 9.0, 9.5)


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


def objective(sc, meta):
    """The aggregate of the per-start scores sc (array, floored) that the optimiser MAXIMISES."""
    obj = meta.get("obj", "mean")
    n = len(sc)
    mean = float(sc.mean())
    j = _objective(sc, meta, obj, n, mean)
    lf = meta.get("legal_floor", 0.0)
    if obj != "mean" and lf > 0.0:
        # a safety floor against collapse: the pass rule needs >= 50 % legal per attempt; below lf of the training starts legal (score > 0) the objective pays legal_w per unit
        j -= meta.get("legal_w", 1.0) * max(0.0, lf - float((sc > 0).mean()))
    return j


def _objective(sc, meta, obj, n, mean):
    if obj == "mean":
        tq = meta.get("tailq", 0.0)
        worst = float(np.sort(sc)[:max(1, int(round(tq * n)))].mean()) if tq > 0 else float(sc.min())
        return mean - meta["risk"] * (mean - worst)
    if obj == "convex":
        return mean + meta["kappa"] * float(np.maximum(sc - meta["c"], 0.0).mean())
    if obj == "topq":
        k = max(1, int(round(meta["topq"] * n)))
        top = float(np.sort(sc)[-k:].mean())
        return (1.0 - meta["lam"]) * top + meta["lam"] * mean
    if obj == "soft":
        z = np.clip((sc - meta["c"]) / meta["tau"], -30.0, 30.0)
        return float((1.0 / (1.0 + np.exp(-z))).mean()) + meta["lam"] * mean
    if obj == "mix":
        # the expected number of successes (a smoothed count of starts above c: the per-attempt P(mark > 8.95), harness c = 8.95 - 0.215 = 8.73, tau ~ the landing noise)
        # + a1 x a convex reward above c1 + a0 x the mean (a floor against collapse): J ~ 0.03 + ... for the baseline; differences are dominated by the success count
        z = np.clip((sc - meta["c"]) / meta["tau"], -30.0, 30.0)
        soft = float((1.0 / (1.0 + np.exp(-z))).mean())
        return soft + meta["a1"] * float(np.maximum(sc - meta["c1"], 0.0).mean()) + meta["a0"] * mean
    raise ValueError(obj)


def _rworker(names, cfg):
    _R["caps"] = [L.load_capture(n) for n in names]
    c0 = _R["caps"][0]
    _R["body"] = L.Body(c0["task"], c0["board_x"], json.loads(c0["env"]))
    _R["cfg"] = cfg


def _reval(job):
    x, base, meta = job[:3]
    idx = job[3] if len(job) > 3 else None     # L6: a mini-batch (indices into the loaded captures); every candidate of a generation gets the same one
    body, caps, cfg = _R["body"], _R["caps"], _R["cfg"]
    if idx is not None:
        caps = [caps[i] for i in idx]
    tab, g = L._decode(np.asarray(x), base, meta["nk"], len(body.muscles))
    if meta.get("kc"):
        tab = with_kc(tab, x, meta["nk"], len(body.muscles))
    if meta.get("fmin") is not None:
        tab = dict(tab)
        tab["fmin"] = meta["fmin"]
    prog = L.IKProgram(tab, meta["h"], meta["td"], g, 1.0, meta["kp"], meta["kd"], meta["gap0"], meta.get("end"))
    prog_m = None
    scores = []
    for cap in caps:
        pr = prog
        if cap["plant"] != meta.get("p0", cap["plant"]):
            if prog_m is None:
                prog_m = L.IKProgram(L.mirror_tab(tab, L.side_perm(body.muscles)), meta["h"], meta["td"], g, 1.0, meta["kp"], meta["kd"],
                                     meta["gap0"], meta.get("end"))
            pr = prog_m
        r = simulate_prog2(body, cap, pr)
        scores.append(max(ljx.score2(r, cap, cfg), meta.get("floor", -1e9)))
    sc = np.array(scores)
    return objective(sc, meta), {"mean": float(sc.mean()), "min": float(sc.min()), "scores": scores}


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
            "td": 0.0, "tdw": 20.0, "kneeload": float(a.kneeload), "kneew": float(a.kneew), "lw": float(a.lw), "pw": float(a.pw), "pthr": float(a.pthr),
            "shift": float(a.shift)}


def surrogate(sc, shift=0.0):
    """CALIBRATED estimate of the per-attempt P(official mark > 8.95) from harness scores: official = D_board + 0.215 (sd 0.29) on the held-out pool seeds (scratchpad/lj6 LOG), legal states only;
    the harness scores already include a deployment shift. It predicted the official rates 1.99 % (observed 1.8 %, C7) and 2.95 % (3.5 %, Cb10)."""
    sc = np.asarray(sc, dtype=float)
    z = (sc - (8.95 - 0.215)) / 0.29
    return float(np.mean([0.5 * (1.0 + math.erf(x / math.sqrt(2.0))) if v > 0 else 0.0 for x, v in zip(z, sc)]))


def tail_line(sc, label=""):
    """one-line tail summary of raw scores (clipped at 0 = the official-like mark: a failed start is 0)."""
    sc = np.asarray(sc, dtype=float)
    cl = np.maximum(sc, 0.0)
    n = len(sc)
    leg = cl[cl > 0]
    s = "%sn %d legal %d (%.1f %%) clipped mean %.3f legal mean %.3f median %.3f p90 %.3f max %.3f | starts >= " % (
        label, n, len(leg), 100.0 * len(leg) / n, cl.mean(), leg.mean() if len(leg) else 0.0, float(np.median(leg)) if len(leg) else 0.0,
        float(np.percentile(leg, 90)) if len(leg) else 0.0, leg.max() if len(leg) else 0.0)
    s += "  ".join("%.2f: %d (%.1f %%)" % (t, int((cl >= t).sum()), 100.0 * (cl >= t).mean()) for t in TAIL_T)
    s += " | SURROGATE per-attempt P(mark>8.95) %.2f %%" % (100.0 * surrogate(sc))
    return s


def run(a):
    from search import make_optimizer, read_params
    names, caps, body, mus, kp, kd, gaps = setup(a)
    cfg = cfg_of(a)
    pfile, base = L.read_ik(a.ik, mus, caps[0]["plant"], nk=a.nk)
    gap0 = float(np.median(gaps)) if a.gap0 is None else a.gap0
    meta = {"nk": a.nk, "h": pfile["ik_h"], "td": pfile["ik_td"], "kp": kp, "kd": kd, "gap0": gap0, "lmax": float(a.lmax), "risk": a.risk,
            "end": pfile["ik_td"] + a.post, "p0": caps[0]["plant"], "tailq": a.tailq, "kc": a.kc, "fmin": a.fmin, "floor": a.floor,
            "obj": a.obj, "c": a.c, "kappa": a.kappa, "topq": a.topq, "lam": a.lam, "tau": a.tau, "a1": a.a1, "a0": a.a0, "c1": a.c1, "legal_floor": a.legal_floor, "legal_w": a.legal_w}
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
    print(f"risk: {len(caps)} starts, {len(x0)} dims, gap0 {meta['gap0']:.3f}, objective {a.obj} (c {a.c} kappa {a.kappa} topq {a.topq} lam {a.lam} tau {a.tau}), cfg {cfg}", flush=True)
    opt = make_optimizer("sep_cma", x0, sigma0=a.sigma, seed=a.seed, **({"popsize": a.pop} if a.pop else {}))
    t0 = time.time()
    used = 0
    with mp.Pool(a.workers, initializer=_rworker, initargs=(names, cfg)) as pool:
        f0, m0 = pool.apply(_reval, ((x0, base, meta),))
        best = (f0, x0.copy(), m0)
        print(f"x0 J {f0:.4f} mean {m0['mean']:.3f} min {m0['min']:.3f}", flush=True)
        print("x0 " + tail_line(m0["scores"]), flush=True)
        gen = 0
        N = len(caps)
        B = a.batch if 0 < a.batch < N else N
        rng_b = np.random.default_rng(a.seed + 1000)
        while used < a.evals:
            X = np.clip(np.atleast_2d(opt.ask()), 0.0, 1.0)
            idx = None if B == N else sorted(rng_b.choice(N, B, replace=False).tolist())
            res = pool.map(_reval, [(x, base, meta, idx) for x in X], chunksize=max(1, len(X) // (a.workers * 2)))
            f = np.array([r[0] for r in res])
            opt.tell(X, f, [r[1] for r in res])
            used += len(X) * B
            gen += 1
            i = int(np.argmax(f))
            if B < N:
                best = (float(f[i]), X[i].copy(), res[i][1])       # a mini-batch score is not comparable across generations: the snapshot is the CMA mean
            elif f[i] > best[0]:
                best = (float(f[i]), X[i].copy(), res[i][1])
            if gen % a.snap == 0:
                bm = best[2]
                print(f"gen {gen} sims {used} bestJ {best[0]:.4f} meanJ {float(f.mean()):.4f} mean {bm['mean']:.3f} min {bm['min']:.3f} sigma {opt.sigma:.4f} ({time.time() - t0:.0f}s)", flush=True)
                print(f"gen {gen} " + tail_line(bm["scores"]), flush=True)
                xs = np.clip(opt.mean, 0.0, 1.0) if B < N else best[1]
                write_program2(a.out, xs, base, meta, n, mus, caps[0]["plant"], pfile, best, gaps)
                if a.keep:
                    write_program2(a.out.replace(".txt", f"_g{gen}.txt"), xs, base, meta, n, mus, caps[0]["plant"], pfile, best, gaps)
                if os.path.exists(a.out + ".stop"):
                    print("stop file found", flush=True)
                    break
    write_program2(a.out, np.clip(opt.mean, 0.0, 1.0) if B < N else best[1], base, meta, n, mus, caps[0]["plant"], pfile, best, gaps)
    print("best", best[0], json.dumps({k: v for k, v in best[2].items() if k != "scores"}), flush=True)
    print("best " + tail_line(best[2]["scores"]), flush=True)


# ---- parallel evaluation of a finished program ----------------------------------------------------------------------------------------------

def _eworker(first, cfg, path, fmin, g, gap0):
    from search import read_params
    c0 = L.load_capture(first)
    body = L.Body(c0["task"], c0["board_x"], json.loads(c0["env"]))
    mus = body.muscles
    kp, kd = L.reflex_gains(mus, json.loads(c0["params"]))
    pf = read_params(path)
    nk = int(round(pf["ik_n"]))
    progs = {}
    for plant in ("l", "r"):
        _, tab = L.read_ik(path, mus, plant, nk=nk)
        if fmin is not None:
            tab["fmin"] = fmin
        gg = pf["j_ik_g"] if g is None else g
        progs[plant] = L.IKProgram(tab, pf["ik_h"], pf["ik_td"], gg, pf.get("j_ik_kdc", 1.0), kp, kd, pf["ik_gap0"] if gap0 is None else gap0, pf["ik_end"])
    _R["e"] = {"body": body, "progs": progs, "cfg": cfg}


def _eeval(name):
    body, progs, cfg = _R["e"]["body"], _R["e"]["progs"], _R["e"]["cfg"]
    cap = L.load_capture(name)
    mujoco.mj_setState(body.m, body.d, cap["state"], L.SPEC)
    mujoco.mj_forward(body.m, body.d)
    pen = "l" if cap["plant"] == "r" else "r"
    gap = cap["board_x"] - L.seen_site_x(body, f"{pen}_toe")
    r = simulate_prog2(body, cap, progs[cap["plant"]])
    s = ljx.score2(r, cap, cfg)
    row = {"name": name, "plant": cap["plant"], "gap": float(gap), "s": float(s), "valid": bool(r["valid"])}
    if r["valid"]:
        row.update(D_board=float(r["D"] - (cap["board_x"] - r["toe_max"])), off=float(r["toe_max"] - cap["board_x"]), vx=float(r["vx"]), vz=float(r["vz"]),
                   L=float(r["L"]), contact=float(r["contact_s"]), grf12=float(r["grf12_bw"]), pitch=float(r["torso_pitch"]),
                   foul=bool(r["toe_max"] > cap["board_x"] - cfg["margin"] - cfg.get("shift", 0.0)), fwd_risk=bool(r["L"] > 0.0 or r["torso_pitch"] > 0.8))
    else:
        row["why"] = r.get("why")
    return row


def evaluate(a):
    """Per-start table (parallel over the starts) + the tail summary of a finished program on the captures."""
    names = [n for n in a.captures.split(",") if n]
    # the gap and the program need the first capture's body only; the cfg as the training's
    cfg = cfg_of(a)
    with mp.Pool(a.workers, initializer=_eworker, initargs=(names[0], cfg, a.eval, a.fmin, a.g, a.gap0)) as pool:
        rows = pool.map(_eeval, names, chunksize=max(1, len(names) // (a.workers * 4)))
    if not a.quiet:
        for r in rows:
            if r["valid"]:
                print("%-14s %s gap %.3f score %6.2f D_board %.3f off %+.3f vx %.2f vz %.2f L %6.1f contact %.3f grf12 %.1f%s" % (
                    r["name"], r["plant"], r["gap"], r["s"], r["D_board"], r["off"], r["vx"], r["vz"], r["L"], r["contact"], r["grf12"], "  FOUL" if r["foul"] else ""))
            else:
                print("%-14s %s gap %.3f INVALID %s" % (r["name"], r["plant"], r["gap"], r.get("why")))
    sc = np.array([r["s"] for r in rows])
    val = [r for r in rows if r["valid"]]
    nfoul = sum(1 for r in val if r["foul"])
    fr = sum(1 for r in val if r["fwd_risk"])
    print("forward-risk take-offs (L > 0 or pitch > 0.8): %d of %d" % (fr, len(rows)))
    legal = sc[sc > 0]
    print("SUMMARY %d starts: valid %d, fouls/too close %d, legal(score>0) %d, score mean %.3f (all) / %.3f (legal), min %.3f" % (
        len(rows), len(val), nfoul, len(legal), sc.mean(), legal.mean() if len(legal) else 0.0, sc.min()))
    print("TAIL " + tail_line(sc))
    if val:
        vz = np.array([r["vz"] for r in val])
        print("take-off vz mean %.2f p90 %.2f max %.2f | D_board mean %.3f" % (vz.mean(), np.percentile(vz, 90), vz.max(), np.mean([r["D_board"] for r in val])))
    if a.json:
        json.dump(rows, open(a.json, "w"))


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
    ap.add_argument("--lw", type=float, default=0.2, help="L4: weight per unit of forward L above --lmax (L3: 0.2)")
    ap.add_argument("--pw", type=float, default=0.0, help="L4: weight per rad of take-off torso pitch above --pthr")
    ap.add_argument("--pthr", type=float, default=0.65)
    ap.add_argument("--grfcap", default="20")
    ap.add_argument("--grfw", default="0.3")
    ap.add_argument("--margin", type=float, default=0.03)
    ap.add_argument("--risk", type=float, default=0.3)
    ap.add_argument("--kc", action="store_true", help="also learn the swing-foot clearance reflex (32 gains + its height) on the plant-side foot")
    ap.add_argument("--fmin", type=float, default=None, help="the plant-touchdown latch needs this many body weights of force (skill: ik_fmin; 1.5 ignores a scuffing swing foot)")
    ap.add_argument("--g", type=float, default=None, help="--eval: override the program's reflex gain j_ik_g")
    ap.add_argument("--floor", type=float, default=-1e9, help="per-start score floor: a failed start costs at most this (the arena scores a failure 0)")
    ap.add_argument("--kneeload", type=float, default=0.0)
    ap.add_argument("--kneew", type=float, default=10.0)
    ap.add_argument("--tailq", type=float, default=0.0, help="--obj mean: the risk term uses the mean of the worst tailq fraction of the starts instead of the single worst")
    ap.add_argument("--g0", type=float, default=0.3)
    ap.add_argument("--gap0", type=float, default=None)
    ap.add_argument("--post", type=float, default=0.04, help="program time after the ideal touchdown at which the program hands over")
    ap.add_argument("--init")
    ap.add_argument("--out")
    # L6: upper-tail objectives
    ap.add_argument("--obj", default="mean", choices=("mean", "convex", "topq", "soft", "mix"))
    ap.add_argument("--c", type=float, default=8.0, help="convex / soft: the score (m, harness D_board) above which the reward is steeper (soft: the threshold, ~ 8.95 + landing loss 0.2)")
    ap.add_argument("--kappa", type=float, default=3.0, help="convex: extra slope above c")
    ap.add_argument("--topq", type=float, default=0.25, help="topq: the best fraction of the starts")
    ap.add_argument("--lam", type=float, default=0.3, help="topq / soft: weight of the plain mean")
    ap.add_argument("--tau", type=float, default=0.35, help="soft / mix: the sigmoid's width (m)")
    ap.add_argument("--a1", type=float, default=0.02, help="mix: weight of the convex reward mean(max(s - c1, 0))")
    ap.add_argument("--a0", type=float, default=0.005, help="mix: weight of the plain mean")
    ap.add_argument("--c1", type=float, default=7.8, help="mix: the convex reward's kink (m)")
    ap.add_argument("--shift", type=float, default=0.0, help="the joint check-mark shift d (m) of the deployment: marks + d, the foul line d closer (0 = neutral)")
    ap.add_argument("--legal-floor", dest="legal_floor", type=float, default=0.0, help="non-mean objectives: pay --legal-w per unit when the legal fraction of the training starts is below this")
    ap.add_argument("--legal-w", dest="legal_w", type=float, default=1.0)
    ap.add_argument("--batch", type=int, default=0, help="mini-batch: every generation scores all candidates on this many randomly drawn training starts (0 = all); the snapshots are then the CMA mean")
    ap.add_argument("--snap", type=int, default=10, help="generations between snapshots / log lines")
    ap.add_argument("--keep", action="store_true", help="also keep every snapshot as <out>_g<gen>.txt")
    ap.add_argument("--json", help="--eval: write the per-start rows")
    ap.add_argument("--quiet", action="store_true", help="--eval: no per-start table")
    a = ap.parse_args()
    evaluate(a) if a.eval else run(a)


if __name__ == "__main__":
    main()
