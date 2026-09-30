"""snap3 (round 3, the sprinter body; snap.py plus --vmin/--vmax and runs that fall after the window still count): flying-start snapshot sets of a champion's steady running, one snapshot per standing-start run.

  source scratchpad/sprint2/env.sh
  .venv/bin/python scratchpad/sprint2/snap.py PARAMS CONTROLLER OUT.npz --seeds 31-49 [--secs 24] [--t0 14] [--t1 24] [--workers 4] [--pick 7]

Each run (task run_v4, the given standing-start seed) records every REAL right touchdown (>= 60 ms in the air, foot ahead of
the COM; two control ticks before it) between t0 and t1; one of them (chosen by a fixed rng from --pick + seed) goes into the set.
Set index k = the k-th seed in the list. Same npz layout as snapshots2.py (t, qpos, qvel, act, vx).
"""
import argparse, multiprocessing as mp, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
import numpy as np
from practice import load_task, read_params
from bridge import Sim


class R:
    def __init__(s, t0, t1, vmin=0.0, vmax=99.0):
        s.buf = []; s.snaps = []; s.prev = True; s.off_since = 0.0; s.t0 = t0; s.t1 = t1; s.vmin = vmin; s.vmax = vmax
    def maybe_capture(s, sim):
        d = sim.d
        on = sim.contacts()["r_foot"] > 0.05
        pid = sim.m.body("pelvis").id
        s.buf.append((d.time, d.qpos.copy(), d.qvel.copy(), d.act.copy(), float(d.subtree_linvel[pid][0])))
        s.buf = s.buf[-4:]
        ahead = float(d.body("r_foot").xpos[0]) > float(d.subtree_com[pid][0])
        if on and not s.prev and d.time - s.off_since >= 0.06 and ahead and s.t0 <= d.time <= s.t1 and len(s.buf) >= 3 \
                and s.vmin <= s.buf[-3][4] <= s.vmax:
            s.snaps.append(s.buf[-3])
        if s.prev and not on:
            s.off_since = d.time
        s.prev = on


def one(job):
    params, ctl, seed, secs, t0, t1, pick, vmin, vmax = job
    t = load_task("run_v4"); t.seed = seed
    sim = Sim(t, params=params, controller=ctl)
    r = R(t0, t1, vmin, vmax)
    res = sim.run(secs, recorder=r)
    # snap3: a run that falls AFTER the window still yields its snapshots (the recorder only saw the window)
    # S4: a run that fell still yields its snapshots taken at least MARGIN s before the fall (edge-of-instability states: the fall
    # comes soon after, but not so soon that the state is doomed); MARGIN via env SNAP_MARGIN (default 2.0)
    margin = float(os.environ.get("SNAP_MARGIN", "2.0"))
    snaps = [x for x in r.snaps if not res["fell"] or x[0] <= res.get("time", 0.0) - margin]
    if not snaps:
        return seed, None, res
    rng = np.random.default_rng(pick + seed)
    return seed, snaps[int(rng.integers(len(snaps)))], res


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("params"); ap.add_argument("controller"); ap.add_argument("out")
    ap.add_argument("--seeds", required=True); ap.add_argument("--secs", type=float, default=24.0)
    ap.add_argument("--t0", type=float, default=14.0); ap.add_argument("--t1", type=float, default=24.0)
    ap.add_argument("--workers", type=int, default=4); ap.add_argument("--pick", type=int, default=7)
    ap.add_argument("--vmin", type=float, default=0.0); ap.add_argument("--vmax", type=float, default=99.0)
    a = ap.parse_args()
    seeds = []
    for tok in a.seeds.split(","):
        if "-" in tok:
            lo, hi = tok.split("-"); seeds += list(range(int(lo), int(hi) + 1))
        else:
            seeds.append(int(tok))
    p = read_params(a.params)
    with mp.Pool(a.workers) as pool:
        out = pool.map(one, [(p, a.controller, s, a.secs, a.t0, a.t1, a.pick, a.vmin, a.vmax) for s in seeds], chunksize=1)
    ok = [(s, x) for s, x, _ in out if x is not None]
    bad = [s for s, x, _ in out if x is None]
    print("recorded", len(ok), "snapshots; failed seeds (fell or none):", bad)
    print("speeds", [round(x[4], 2) for _, x in ok])
    np.savez_compressed(a.out, t=np.array([x[0] for _, x in ok]), qpos=np.array([x[1] for _, x in ok]), qvel=np.array([x[2] for _, x in ok]),
                        act=np.array([x[3] for _, x in ok]), vx=np.array([x[4] for _, x in ok]), seeds=np.array([s for s, _ in ok]), root_x_adr="run_v4")
