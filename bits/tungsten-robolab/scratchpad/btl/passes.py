"""Per-pass analysis: python passes.py params seed secs [overrides] [controller]"""
import os, sys, numpy as np, mujoco
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks")
from bridge import Sim
from dribble_btl import DribbleBtlTask
def load(p):
    out = {}
    for line in open(p):
        t = line.split()
        if len(t) >= 2 and not line.startswith("#"): out[t[0]] = float(t[1])
    return out
def analyze(pfile, seed, secs, over="", ctl="bin/robolab_dribble_btl", quiet=False):
    t = DribbleBtlTask(); t.body_kind = "v3"; t.seed = seed
    params = load(pfile); params.update({k: float(v) for k, v in (kv.split("=") for kv in over.split(",") if kv)})
    sim = Sim(t, params=params, controller=ctl)
    ev = []
    state = {"touch": {"r": False, "l": False}, "floor": False, "body": set()}
    orig = t.before_step
    f6 = np.zeros(6)
    def hook(m, d):
        orig(m, d)
        if not hasattr(t, "ball_geom") or t.released_t is None: return
        p = d.body("ball").xpos.copy(); v = d.qvel[t.ball_dof:t.ball_dof + 3].copy()
        touching = {"r": False, "l": False}; floor = False; body = set()
        for i in range(d.ncon):
            c = d.contact[i]
            if t.ball_geom not in (c.geom1, c.geom2): continue
            o = c.geom2 if c.geom1 == t.ball_geom else c.geom1
            mujoco.mj_contactForce(m, d, i, f6)
            if f6[0] < 0.3 * t.ball_w: continue
            if o == t.floor_geom: floor = True; continue
            side = t.hand_bodies.get(m.geom_bodyid[o])
            if side: touching[side] = True
            else: body.add(m.geom(o).name)
        for s in "rl":
            if touching[s] and not state["touch"][s]: ev.append((d.time, "touch_" + s, p, v))
            if state["touch"][s] and not touching[s]: ev.append((d.time, "leave_" + s, p, v))
        if floor and not state["floor"]: ev.append((d.time, "floor", p, v))
        for b in body - state["body"]: ev.append((d.time, "HIT " + b, p, v))
        state["touch"], state["floor"], state["body"] = touching, floor, body
    t.before_step = hook
    r = sim.run(secs)
    if not quiet:
        for tt, k, p, v in ev:
            print(f"  {tt:6.3f} {k:14s} ball {p.round(2)} v {v.round(2)}")
        for g in t.gate_passes: print("  gate", g)
        for k in getattr(t, "ktouch", []): print("  ktouch", k[0], k[1], " ".join(f"{float(x):+.3f}" for x in k[2:]))
        print(" ", {k: r.get(k) for k in ("btl_rate", "btl_ok", "btl_tried", "btl_streak", "lost", "carry_why")})
        print(" ", [(e["t"], e["k"], e["why"]) for e in r["btl_log"]])
    return r, ev
if __name__ == "__main__":
    analyze(sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), sys.argv[4] if len(sys.argv) > 4 else "",
            sys.argv[5] if len(sys.argv) > 5 else "bin/robolab_dribble_btl")
