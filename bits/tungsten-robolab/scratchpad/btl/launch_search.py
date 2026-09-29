"""Calibrate the BTL launch: CMA over the launch params; objective = the ball's
first rise through z=0.85 lands on the right spot, apex >= 0.95, over seeds."""
import os, sys, numpy as np
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks")
from multiprocessing import get_context
import practice as pr
ZC = float(os.environ.get("LAUNCH_ZC", "0.85"))
APEX = float(os.environ.get("LAUNCH_APEX", "1.0"))
NAMES = ["bt_lhx", "bt_lhy", "bt_ldx", "bt_ldy", "bt_lt", "bt_ldrv", "z_rel", "bt_lzc", "bt_lzl"]
LO = np.array([-0.2, -0.2, -0.2, -0.2, 0.05, 0.0, 0.7, 0.8, 0.45]); HI = np.array([0.2, 0.2, 0.2, 0.2, 0.3, 1.0, 1.1, 1.3, 0.95])
def load(p):
    out = {}
    for line in open(p):
        t = line.split()
        if len(t) >= 2 and not line.startswith("#"): out[t[0]] = float(t[1])
    return out
def run(job):
    params, seed, ctl = job
    from bridge import Sim
    from dribble_btl import DribbleBtlTask
    t = DribbleBtlTask(); t.body_kind = "v3"; t.seed = seed
    sim = Sim(t, params=params, controller=ctl)
    st = {"bounced": False, "cross": None, "apex": 0.0, "prevz": 9}
    orig = t.before_step
    def hook(m, d):
        orig(m, d)
        if t.released_t is None or st["cross"] is not None and st["apex"] > 0: return
        p = d.body("ball").xpos; vz = d.qvel[t.ball_dof + 2]
        if not st["bounced"] and p[2] < 0.14 and vz > 0: st["bounced"] = True
        if st["bounced"] and st["cross"] is None and p[2] >= ZC and vz > 0:
            st["cross"] = p[:2].copy(); st["vh"] = float(np.hypot(d.qvel[t.ball_dof], d.qvel[t.ball_dof + 1]))
        if st["bounced"] and vz <= 0 and st["apex"] == 0 and p[2] > 0.3: st["apex"] = float(p[2])
    t.before_step = hook
    try:
        sim.run(params.get("st_hold", 0.8) + 1.6)
    except Exception:
        return 9.0
    spot = np.array([params["bt_fx"], params["bt_fy"]])
    if st["cross"] is None:
        return 3.0 + abs(st["apex"] - APEX) * 5
    return float(np.linalg.norm(st["cross"] - spot)) + 3 * abs(st["apex"] - APEX) + 0.15 * st["vh"]
if __name__ == "__main__":
    base = load(sys.argv[1]); ctl = sys.argv[2]; out = sys.argv[3]
    seeds = [1, 2, 3]
    x0 = np.array([(base.get(n, (l + h) / 2) - l) / (h - l) for n, l, h in zip(NAMES, LO, HI)]).clip(0, 1)
    x0[NAMES.index("bt_lt")] = (0.15 - 0.05) / 0.25
    def params_of(x):
        p = dict(base); p.update({n: float(l + (h - l) * v) for n, l, h, v in zip(NAMES, LO, HI, np.clip(x, 0, 1))}); return p
    es = pr.CMA(x0, 0.2, 10, seed=3)
    best = (9e9, None)
    with get_context("spawn").Pool(4) as pool:
        for g in range(25):
            xs = es.ask()
            res = pool.map(run, [(params_of(x), s, ctl) for x in xs for s in seeds])
            sc = [float(np.mean(res[i * 3:(i + 1) * 3])) for i in range(len(xs))]
            es.tell(xs, [-v - 10 * float(np.sum(np.maximum(0, x - 1) + np.maximum(0, -x))) for v, x in zip(sc, xs)])
            k = int(np.argmin(sc))
            if sc[k] < best[0]:
                best = (sc[k], params_of(xs[k]))
                with open(out, "w") as f:
                    f.write(f"# launch calibration {sc[k]:.3f}\n")
                    for kk in sorted(best[1]): f.write(f"{kk} {best[1][kk]!r}\n")
            print(f"gen {g} best {best[0]:.3f} gen {sc[k]:.3f} " + " ".join(f"{n}={best[1][n]:.3f}" for n in NAMES), flush=True)
