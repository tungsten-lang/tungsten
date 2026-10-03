"""snap5: flying-start snapshot sets of a champion's running in a SPEED WINDOW, one snapshot per standing-start run (anat5, equal-treatment A/B).

  source scratchpad/anat5/env_v4.sh   # or env_v5.sh
  .venv/bin/python scratchpad/anat5/snap5.py PARAMS CONTROLLER OUT.npz --seeds 31-50 --secs 18 --t0 4 --t1 16 --vmin 7.0 --vmax 7.7 [--min_before_fall 1.5]

snap3.py's recorder (every REAL right touchdown: >= 60 ms in the air, the foot ahead of the COM; the state two control ticks before it;
one snapshot per seed, picked by a fixed rng) with one change: a run that FALLS later still yields its snapshot, provided the snapshot
is at least --min_before_fall s before the fall (the champion on the v5 body falls ~1 s after 7.7 m/s; the state before it is a valid
running state). Same npz layout as snap.py (t, qpos, qvel, act, vx, seeds); the file is read by tasks/sprint_touch_v4*.py as
ROBOLAB_SNAP=<OUT's name after sprint_touch_>.
"""
import argparse, multiprocessing as mp, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
import numpy as np
from practice import load_task, read_params
from bridge import Sim


class R:
    def __init__(s, t0, t1, vmin, vmax):
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
    params, ctl, seed, secs, t0, t1, pick, vmin, vmax, mbf = job
    t = load_task("run_v4"); t.seed = seed
    sim = Sim(t, params=params, controller=ctl)
    r = R(t0, t1, vmin, vmax)
    res = sim.run(secs, recorder=r)
    end = float(res.get("time", secs))
    snaps = [x for x in r.snaps if (not res["fell"]) or x[0] <= end - mbf]
    if not snaps:
        return seed, None, res
    rng = np.random.default_rng(pick + seed)
    return seed, snaps[int(rng.integers(len(snaps)))], res


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("params"); ap.add_argument("controller"); ap.add_argument("out")
    ap.add_argument("--seeds", required=True); ap.add_argument("--secs", type=float, default=18.0)
    ap.add_argument("--t0", type=float, default=4.0); ap.add_argument("--t1", type=float, default=16.0)
    ap.add_argument("--workers", type=int, default=3); ap.add_argument("--pick", type=int, default=7)
    ap.add_argument("--vmin", type=float, default=7.0); ap.add_argument("--vmax", type=float, default=7.7)
    ap.add_argument("--min_before_fall", type=float, default=1.5)
    a = ap.parse_args()
    seeds = []
    for tok in a.seeds.split(","):
        if "-" in tok:
            lo, hi = tok.split("-"); seeds += list(range(int(lo), int(hi) + 1))
        else:
            seeds.append(int(tok))
    p = read_params(a.params)
    with mp.Pool(a.workers) as pool:
        out = pool.map(one, [(p, a.controller, s, a.secs, a.t0, a.t1, a.pick, a.vmin, a.vmax, a.min_before_fall) for s in seeds], chunksize=1)
    ok = [(s, x) for s, x, _ in out if x is not None]
    bad = [s for s, x, _ in out if x is None]
    print("recorded", len(ok), "snapshots; seeds without one:", bad)
    print("speeds", [round(x[4], 2) for _, x in ok])
    print("times ", [round(x[0], 1) for _, x in ok])
    print("falls of the source runs:", [(s, round(float(r.get('time', 0)), 1)) for s, _, r in out if r.get("fell")])
    np.savez_compressed(a.out, t=np.array([x[0] for _, x in ok]), qpos=np.array([x[1] for _, x in ok]), qvel=np.array([x[2] for _, x in ok]),
                        act=np.array([x[3] for _, x in ok]), vx=np.array([x[4] for _, x in ok]), seeds=np.array([s for s, _ in ok]), root_x_adr="run_v4")
