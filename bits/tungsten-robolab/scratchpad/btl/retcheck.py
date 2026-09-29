"""First pass received? The return: the ball's velocity after the receiving hand's last touch, and its fate."""
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
    st = {"l_touch": False, "vel_after": None}
    orig = t.before_step
    def hook(m, d):
        orig(m, d)
        if not hasattr(t, "ball_geom") or t.released_t is None: return
        f = t.ball_forces(m, d)
        lt = f["l"] > 0.3 * t.ball_w
        if st["l_touch"] and not lt:
            st["vel_after"] = d.qvel[t.ball_dof:t.ball_dof + 3].round(2).tolist(); st["pos_after"] = d.body("ball").xpos.round(2).tolist()
        st["l_touch"] = lt
    t.before_step = hook
    r = sim.run(3.4)
    pl = r["pass_log"]
    return seed, pl[0]["outcome"] if pl else None, st.get("vel_after"), st.get("pos_after"), [(e["k"], e["why"]) for e in r["btl_log"]]
if __name__ == "__main__":
    ctl, pfile = sys.argv[1], sys.argv[2]
    params = load(pfile); params.update({k: float(v) for k, v in (kv.split("=") for kv in (sys.argv[3] if len(sys.argv) > 3 else "").split(",") if kv)})
    seeds = [int(x) for x in sys.argv[4].split(",")]
    with Pool(4) as p:
        for row in p.map(run, [(ctl, params, s) for s in seeds]): print(*row)
