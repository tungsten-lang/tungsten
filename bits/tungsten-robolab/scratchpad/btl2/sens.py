"""Sensitivity of a program's outcome to tiny changes of the start: perturb the ball's position at the snapshot.
   .venv/bin/python scratchpad/btl2/sens.py program.npz seeds hand"""
import sys, pickle
sys.path.insert(0, "scratchpad/btl2")
import numpy as np, mujoco
import oracle_lib as O, oracle_search as S, oracle_multi as M
z = np.load(sys.argv[1])
seeds = [int(x) for x in sys.argv[2].split(",")]
who = sys.argv[3] if len(sys.argv) > 3 else "l"
cache = pickle.load(open("scratchpad/btl2/runs/rec_cache.npz.pkl", "rb"))
idx, kt, x = list(z["idx"]), z["kt"], z["x"]
nprog = int(kt[-1]); n = 160
X = np.clip(x.reshape(len(idx), len(kt)), 0, 1)
bounce_no = 2 if who == "l" else 3
rng = np.random.default_rng(1)
for sd in seeds:
    key = next(k for k in cache if k[0] == sd and ((who == "l" and "pgL" not in k[1]) or (who == "r" and "pgL" in k[1])))
    rec = cache[key]
    kc = M.crossing_tick(rec, bounce_no=bounce_no)
    ks = kc - int(z["lead"])
    rp = O.Replay(rec)
    base = rec["acts"][ks:ks + n + 1]
    ov = {}
    for r, mi in enumerate(idx):
        arr = base[:n, mi].copy(); arr[:nprog + 1] = np.interp(np.arange(nprog + 1), kt, X[r]); ov[mi] = arr
    adr = rp.m.jnt_qposadr[rp.m.joint("ball").id]
    rows = []
    for trial in range(9):
        rp.load(ks)
        if trial > 0:
            d = rng.normal(size=3) * (0.001 if trial < 5 else 0.003)
            rp.d.qpos[adr:adr + 3] += d
            mujoco.mj_forward(rp.m, rp.d)
        # run from the (perturbed) loaded state: replicate Replay.run without reloading
        rp.load = lambda k=None, _l=rp.load: None if trial > 0 else _l(k)
        out = rp.run(ov, ticks=n, start=ks) if trial == 0 else None
        if trial > 0:
            # manual run
            m, d = rp.m, rp.d; ids = rp.act_ids
            pos = np.zeros((n, 3)); vel = np.zeros((n, 3)); cf = np.zeros((n, 4)); legs = np.zeros((n, 2, 3, 3))
            for i in range(n):
                a = base[i].copy()
                for mi, arr in ov.items(): a[mi] = arr[i]
                d.ctrl[ids] = a
                for _ in range(5): mujoco.mj_step(m, d)
                pos[i] = d.xpos[rp.ball_id]; vel[i] = d.qvel[rp.ball_dof:rp.ball_dof + 3]
                f = rp.contacts(); cf[i] = (f["l"], f["r"], f["floor"], f["body"])
                for si in range(2):
                    for ji in range(3): legs[i, si, ji] = d.xpos[rp.leg_ids[si][ji]]
            out = {"pos": pos, "vel": vel, "cf": cf, "legs": legs, "t0": 0.0}
        J, sm = S.evaluate(out, "full", who)
        rows.append((J, sm.get("v", np.zeros(3)), sm.get("apex", 0), sm.get("gate", 0)))
        rp.load = O.Replay.load.__get__(rp)
    Js = np.array([r[0] for r in rows])
    print(sd, "J unperturbed %.2f | 1 mm-scale perturbations J: %s | 3 mm: %s" % (Js[0], np.round(Js[1:5], 2).tolist(), np.round(Js[5:], 2).tolist()))
