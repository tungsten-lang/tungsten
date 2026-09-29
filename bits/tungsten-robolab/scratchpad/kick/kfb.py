"""Closed-loop feasibility in physics, without the Tungsten controller: from the swing start of a dumped run, replay the
recorded activations (the nominal controller's open-loop swing) plus a feedback correction computed each tick from the live state:
torques about chosen joints (minimum-norm muscle activations from the live moment arms), proportional to the toe's lateral error
from the nominal path at equal distance to the ball.

  kfb.py --noise 0.05 --chan rot_r --gain 100 [--limit 60] [--n 40]
"""
import argparse
import glob
import sys

import numpy as np

sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/kick")
import kprobe as P

CK = "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/kick/ckpt/p1base/"


def first(tr, lab):
    return next(i for i, r in enumerate(tr) if r["lab"] == lab)


class Ref:
    """Nominal toe path (relative to the ball) as a function of the gap: bof_r.x - ball.x, from a noise-0 dump's swing start on."""

    def __init__(self, pack):
        tr = pack["trace"]
        k = first(tr, "swing")
        jt = next(i for i, r in enumerate(tr) if r["ball"][0] > 40.0005)
        gs, ys, zs, ts = [], [], [], []
        for r in tr[k:jt]:
            d = r["bof_r"] - r["ball"]
            gs.append(-d[0])
            ys.append(d[1])
            zs.append(d[2])
            ts.append(r["t"] - tr[k]["t"])
        self.g = np.array(gs)[::-1]
        self.y = np.array(ys)[::-1]
        self.z = np.array(zs)[::-1]
        self.t = np.array(ts)[::-1]

    def at(self, gap):
        return (float(np.interp(gap, self.g, self.y)), float(np.interp(gap, self.g, self.z)), float(np.interp(gap, self.g, self.t)))


def variant(pack):
    tr = pack["trace"]
    k = first(tr, "swing")
    return +1 if tr[k]["keeper"] <= -0.35 else -1


def load_refs():
    return {+1: Ref(P.load(CK + "p1base_n0_dx+0_dy+0_s5000.pkl.gz")), -1: Ref(P.load(CK + "p1base_n0_dx+0_dy+0_s5002.pkl.gz"))}


CHANNELS = {
    "rot_r": (["hip_rotation_r"], [1.0]),
    "add_r": (["hip_adduction_r"], [1.0]),
    "rot_add_r": (["hip_rotation_r", "hip_adduction_r"], [1.0, 1.0]),
    "flex_r": (["hip_flexion_r"], [1.0]),
    "rot_l": (["hip_rotation_l"], [1.0]),
    "add_l": (["hip_adduction_l"], [1.0]),
    "axial": (["axial_rotation"], [1.0]),
    "lat": (["lat_bending"], [1.0]),
}


def run_fb(p, pack, ref, chan, gain, limit, sign=1.0, kd=0.0, t_on=0.0, ez_gain=0.0):
    """Replay from the swing start with the lateral feedback; returns (contact summary, predicted cross y)."""
    sim = p.sim
    task = sim.task
    k0 = first(pack["trace"], "swing")
    joints, w = CHANNELS[chan]
    st = {"prev_e": None, "t0": None}

    def law(sim, task, el):
        tr = task.tr
        if not tr:
            return None
        r = tr[-1]
        d = r["bof_r"] - r["ball"]
        if r["ball"][0] > 40.0005:
            return None
        gap = -d[0]
        yref, zref, tref = ref.at(gap)
        e = d[1] - yref
        de = 0.0
        if st["prev_e"] is not None:
            de = (e - st["prev_e"]) / 0.01
        st["prev_e"] = e
        if el < t_on:
            return None
        tau = -sign * (gain * e + kd * de)
        tau = float(np.clip(tau, -limit, limit))
        return dict(joints=joints, taus=[tau * wi for wi in w])

    r = p.run(pack, k0, law=law)
    c = P.contact_summary(r)
    c["pred_y"] = r["m"].get("pred_y", r["m"].get("cross_y"))
    c["cross_y"] = r["m"].get("cross_y")
    return c


def ok(c):
    if c.get("toe") is None:
        return False
    py = c.get("cross_y") if c.get("cross_y") is not None else c.get("pred_y")
    if py is None:
        return False
    return (c["ball_speed"] or 0) > 8.5 and 0.5 < abs(py) < 3.2


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--noise", default="0.05")
    ap.add_argument("--chan", default="rot_r")
    ap.add_argument("--gain", type=float, default=100.0)
    ap.add_argument("--kd", type=float, default=0.0)
    ap.add_argument("--limit", type=float, default=60.0)
    ap.add_argument("--sign", type=float, default=1.0)
    ap.add_argument("--n", type=int, default=24)
    ap.add_argument("--tag", default="p1base")
    ap.add_argument("--ton", type=float, default=0.0)
    a = ap.parse_args()
    files = sorted(glob.glob(CK + f"{a.tag}_n{a.noise}_dx*.pkl.gz"))[:a.n]
    refs = load_refs()
    p = P.Probe()
    res0, res1 = [], []
    for f in files:
        pack = P.load(f)
        var = variant(pack)
        k0 = first(pack["trace"], "swing")
        r0 = p.run(pack, k0)
        c0 = P.contact_summary(r0)
        c0["cross_y"] = r0["m"].get("cross_y", r0["m"].get("pred_y"))
        c1 = run_fb(p, pack, refs[var], a.chan, a.gain, a.limit, a.sign, a.kd, a.ton)
        res0.append(c0)
        res1.append(c1)
        def fmt(c):
            if c.get("toe") is None:
                return "no contact"
            return f"y {100*c['toe'][1]:+6.1f} z {100*c['toe'][2]:+5.1f} v {c['ball_speed']:5.2f} launch {(c['launch'] or 0):+6.1f} cross {c.get('cross_y') if c.get('cross_y') is not None else float('nan'):+6.2f} ok {int(ok(c))}"
        print(f"{f.split('/')[-1][:34]:34s} var {var:+d} | base {fmt(c0)} | fb {fmt(c1)}", flush=True)
    def summ(rs, tag):
        okn = sum(1 for c in rs if ok(c))
        ys = [c["toe"][1] for c in rs if c.get("toe") is not None]
        print(f"{tag}: ok {okn}/{len(rs)}  contact y mean {100*np.mean(ys):+.1f} std {100*np.std(ys):.1f} cm; speed mean {np.mean([c['ball_speed'] or 0 for c in rs]):.2f}")
    summ(res0, "baseline (recorded open loop)")
    summ(res1, f"feedback {a.chan} gain {a.gain} kd {a.kd} limit {a.limit}")
