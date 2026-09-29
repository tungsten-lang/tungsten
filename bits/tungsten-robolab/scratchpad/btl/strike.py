import sys, numpy as np
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks")
from multiprocessing import Pool
from grid import load
def run(job):
    ctl, params, seed = job
    from bridge import Sim
    from dribble_btl import DribbleBtlTask
    t = DribbleBtlTask(); t.body_kind = "v3"; t.seed = seed
    sim = Sim(t, params=params, controller=ctl)
    st = {}
    orig = t.before_step
    def hook(m, d):
        orig(m, d)
        if not hasattr(t, "moves") or not t.moves: 
            if hasattr(t, "released_t") and t.released_t is not None and "bounce0" not in st:
                p = d.body("ball").xpos
                if p[2] < 0.125 and d.qvel[t.ball_dof + 2] > 0: st["bounce0"] = p[:2].copy()
            return
        mv = t.moves[0]
        p = d.body("ball").xpos.copy(); v = d.qvel[t.ball_dof:t.ball_dof + 3].copy()
        if mv["contact"] and "touch" not in st:
            st["touch"] = np.concatenate([p, v, d.site("r_palm").xpos.copy(), [d.time - mv["t"]]])
        if mv["released"] and "rel" not in st:
            st["rel"] = np.concatenate([p, v])
    t.before_step = hook
    r = sim.run(2.6)
    p0 = r["pass_log"][0] if r["pass_log"] else None
    return seed, st, p0
if __name__ == "__main__":
    ctl, pfile = sys.argv[1], sys.argv[2]
    params = load(pfile)
    with Pool(4) as pool:
        res = pool.map(run, [(ctl, params, s) for s in range(11, 35)])
    X, Y = [], []
    for seed, st, p0 in res:
        if "touch" not in st or "rel" not in st or not p0 or not p0["arrive_xy"]: 
            print(seed, "incomplete", p0 and p0["outcome"]); continue
        tch, rel = st["touch"], st["rel"]
        print(seed, "b0", st.get("bounce0", np.zeros(2)).round(2), "touch ball", tch[:3].round(2), "v", tch[3:6].round(2), "palm", tch[6:9].round(2), "dt", tch[9].round(3),
              "| rel v", rel[3:6].round(2), "| arrive", p0["arrive_xy"], p0["outcome"])
        X.append(np.concatenate([tch[:6], tch[6:9] - tch[:3], [tch[9]]])); Y.append(p0["arrive_xy"][0])
    X, Y = np.array(X), np.array(Y)
    names = ["bx", "by", "bz", "vx", "vy", "vz", "px-bx", "py-by", "pz-bz", "dt"]
    for i, n in enumerate(names):
        c = np.corrcoef(X[:, i], Y)[0, 1]
        print(f"corr(arrive_x, {n}) = {c:+.2f}   range {X[:, i].min():.3f}..{X[:, i].max():.3f}")
