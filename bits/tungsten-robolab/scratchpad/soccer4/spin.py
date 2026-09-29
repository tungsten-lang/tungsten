"""Foot-yaw drift in the set and shift: run each (override) on one seed for T s and print the feet's world yaw and the pelvis yaw at 0.5 s steps.
usage: spin.py <params> <controller> <seed> <T> "ov1" "ov2" ...   (an override is k=v,k=v or - for none)"""
import math, os, sys, multiprocessing as mp
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4")
from search4 import read_params

def run(job):
    params, seed, ctl, T, ov = job
    os.environ["MYO_SOCCER_ENV"] = "myoChallengeSoccerP2-v0"
    os.environ["MYO_SOCCER_MAX_TIME"] = "310"
    from myo_bridge import MyoSim
    from tasks.myo_soccer import MyoSoccerTask
    rows = []
    class Tk(MyoSoccerTask):
        def on_step(self, sim, obs, reward, info):
            super().on_step(sim, obs, reward, info)
            d, m = sim.d, sim.m
            t = float(d.time)
            k = round(t * 100)
            if k % 50 == 0 and k > 0:
                pel = d.xmat[m.body("pelvis").id].reshape(3, 3)
                fy = {}
                for sd in "lr":
                    R = d.xmat[m.body("calcn_" + sd).id].reshape(3, 3)
                    fy[sd] = math.atan2(R[1, 0], R[0, 0])
                ct = sim.foot_contacts()
                lab = sim.label.split(":")[-1] if sim.label else ""
                rows.append(f"{t:.1f}:{lab[:8]} yaw {math.atan2(pel[1,0],pel[0,0]):+.2f} fyL {fy['l']:+.2f} fyR {fy['r']:+.2f} ld {ct['l']:.2f}/{ct['r']:.2f}")
    p = dict(params)
    for kv in ov.split(","):
        if "=" in kv:
            a, b = kv.split("="); p[a.strip()] = float(b)
    try:
        r = MyoSim(Tk(), params=p, controller=ctl, seed=seed).run(T)
        return ov, rows, r.get("stand_time"), r.get("bal1_s")
    except Exception as e:
        return ov, [str(e)[:100]], None, None

if __name__ == "__main__":
    p = read_params(sys.argv[1]); ctl = os.path.abspath(sys.argv[2]); seed = int(sys.argv[3]); T = float(sys.argv[4])
    ovs = sys.argv[5:]
    with mp.Pool(min(4, len(ovs))) as pool:
        res = pool.map(run, [(p, seed, ctl, T, ov) for ov in ovs])
    for ov, rows, st, b in res:
        print("==", ov, "stand", st, "bal1", b)
        for r in rows: print("  ", r)
