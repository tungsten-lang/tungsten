"""sep-CMA of the phase-1 kick under phase-2 perturbations: the P2 environment with the reset moved to the P1 position plus a
per-seed offset (dx in [-w, 0], dy in [-w, w]) and the P2 seed's joint noise scaled by s. A curriculum is run by the caller
(successive invocations with growing s, w, resuming from the previous best).

  search6.py --init P --out O --only a,b,c --controller C --noise 0.1 --w 0 --k 12 --gens 15 --pop 14 --workers 4 --seconds 4.5
             [--stage kick2] [--seed0 92000] [--resume]
Writes O (best), O.mean, O.log, O.state.npz (resumable).
"""
import argparse, json, os, sys, time, multiprocessing as mp
import numpy as np

HERE = "/Users/erik/tungsten/bits/tungsten-robolab/playground"
sys.path.insert(0, HERE)
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4")
from search4 import read_params, describe, write  # noqa: E402


def make_state(seed, s, w, dx0=0.0):
    rng = np.random.RandomState(seed)
    dx = dx0 - w * rng.rand() if w > 0 else dx0
    dy = w * (2 * rng.rand() - 1) if w > 0 else 0.0
    return dx, dy


def worker(job):
    params, seed, ctl, seconds, stage, s, w, dx0 = job
    os.environ["MYO_SOCCER_ENV"] = "myoChallengeSoccerP2-v0"
    import mujoco
    from myosuite.utils import gym as mgym
    from myo_bridge import MyoSim
    from tasks.myo_soccer import MyoSoccerTask, practice_score
    dx, dy = make_state(seed, s, w, dx0)
    if dx0 != 0.0:
        params = dict(params)
        params.update({'k4_pdx': -1.077 + dx, 'k4_pdy': 0.0895 + dy, 'k4_rdx': -1.0775 + dx, 'k4_rdy': -0.0925 + dy})
    e1 = mgym.make("myoChallengeSoccerP1-v0"); e1.reset(seed=0)
    q_p1 = e1.unwrapped.mj_data.qpos.copy()
    orig_make = mgym.make

    def make2(*a, **k):
        env = orig_make(*a, **k)
        u = env.unwrapped
        orig_grs = u._get_reset_state

        def grs():
            qn, qv = orig_grs()
            m = u.mj_model
            q = q_p1.copy()
            for j in range(m.njnt):
                if m.jnt_type[j] in (2, 3):
                    adr = m.jnt_qposadr[j]
                    q[adr] = q_p1[adr] + s * (qn[adr] - q_p1[adr])
            ra = m.jnt_qposadr[m.joint("root").id]
            q[ra] = q_p1[ra] + dx
            q[ra + 1] = q_p1[ra + 1] + dy
            return q, np.zeros_like(qv)
        u._get_reset_state = grs
        return env
    mgym.make = make2
    try:
        m = MyoSim(MyoSoccerTask(), params=params, controller=ctl, seed=seed).run(seconds)
        m.pop("events", None)
        return practice_score(m, stage), {k: m.get(k) for k in ("goal", "ball_speed", "fallen", "stand_time", "t_touch", "cross_y", "pred_y")}
    except Exception as e:
        return -1e3, {"error": str(e)[:200]}
    finally:
        mgym.make = orig_make


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--init", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--only", required=True)
    ap.add_argument("--set", default="")
    ap.add_argument("--controller", required=True)
    ap.add_argument("--noise", type=float, default=0.1)
    ap.add_argument("--w", type=float, default=0.0)
    ap.add_argument("--dx0", type=float, default=0.0, help="start forward by dx0 (feet dx0-based k4 spots), for the standing kick")
    ap.add_argument("--k", type=int, default=12)
    ap.add_argument("--gens", type=int, default=15)
    ap.add_argument("--pop", type=int, default=14)
    ap.add_argument("--sigma", type=float, default=0.08)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--seconds", type=float, default=4.5)
    ap.add_argument("--stage", default="kick2")
    ap.add_argument("--seed0", type=int, default=92000)
    ap.add_argument("--rseed", type=int, default=1)
    ap.add_argument("--resume", action="store_true")
    ap.add_argument("--note", default="")
    a = ap.parse_args()
    from search import SepCMA
    init = read_params(a.init)
    for kv in a.set.split(","):
        if "=" in kv:
            k, v = kv.split("="); init[k.strip()] = float(v)
    ctl = os.path.abspath(a.controller)
    tun = {t[0]: t for t in describe(init, "myoChallengeSoccerP2-v0", ctl)}
    names = [n for n in a.only.split(",") if n]
    missing = [n for n in names if n not in tun]
    if missing:
        raise SystemExit(f"not declared: {missing}")
    lo = np.array([tun[n][2] for n in names]); hi = np.array([tun[n][3] for n in names])
    x0 = np.array([(init.get(n, tun[n][1]) - tun[n][2]) / (tun[n][3] - tun[n][2]) for n in names]).clip(0, 1)

    def to_params(x):
        p = dict(init)
        p.update({n: float(l + (h - l) * v) for n, l, h, v in zip(names, lo, hi, np.clip(x, 0, 1))})
        return p
    es = SepCMA(x0, sigma0=a.sigma, seed=a.rseed, popsize=a.pop)
    state_path = a.out + ".state.npz"
    g0, best = 0, -1e18
    if a.resume and os.path.exists(state_path):
        z = np.load(state_path)
        es.mean, es.sigma, es.C, es.pc, es.ps, es.gen = z["mean"], float(z["sigma"]), z["C"], z["pc"], z["ps"], int(z["gen"])
        g0, best = int(z["g"]), float(z["best"])
    log = open(a.out + ".log", "a")
    log.write(json.dumps({"start": time.strftime("%H:%M:%S"), "args": vars(a), "names": names}) + "\n")
    t0 = time.time()
    with mp.Pool(a.workers) as pool:
        for g in range(g0, a.gens):
            seeds = [a.seed0 + g * a.k + j for j in range(a.k)]
            X = es.ask()
            if g == 0:
                X[0] = x0
            jobs = [(to_params(x), sd, ctl, a.seconds, a.stage, a.noise, a.w, a.dx0) for x in X for sd in seeds]
            res = pool.map(worker, jobs)
            k = len(seeds)
            sc = np.array([np.mean([res[i * k + j][0] for j in range(k)]) for i in range(len(X))])
            goals = [sum(1 for j in range(k) if res[i * k + j][1].get("goal")) for i in range(len(X))]
            es.tell(X, sc)
            i = int(np.argmax(sc))
            if sc[i] > best:
                best = float(sc[i])
                write(a.out, to_params(X[i]), [f"search6 {a.note}: noise {a.noise} w {a.w} gen {g + 1} score {sc[i]:.3f} goals {goals[i]}/{k} seeds {seeds}"])
            write(a.out + ".mean", to_params(es.mean), [f"search6 mean after gen {g + 1}"])
            np.savez(state_path, mean=es.mean, sigma=es.sigma, C=es.C, pc=es.pc, ps=es.ps, gen=es.gen, g=g + 1, best=best)
            line = {"gen": g + 1, "t": round(time.time() - t0), "best": round(best, 3), "gen_best": round(float(sc[i]), 3),
                    "gen_mean": round(float(np.mean(sc)), 3), "goals_best": f"{goals[i]}/{k}", "goals_max": max(goals),
                    "goals_x0": f"{goals[0]}/{k}" if g == 0 else None, "sigma": round(float(es.sigma), 4)}
            print(json.dumps(line), flush=True)
            log.write(json.dumps(line) + "\n"); log.flush()


if __name__ == "__main__":
    main()
