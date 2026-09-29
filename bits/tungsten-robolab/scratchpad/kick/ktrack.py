"""Feasibility: torque-space joint tracking of the nominal swing (open-loop replay of a noisy run + PD torques on the kicking leg's joints
toward the same-variant noise-0 dump's joint trajectory, aligned at the swing start)."""
import argparse, glob, sys
import numpy as np
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/kick")
import kprobe as P
import kfb
CK = kfb.CK

class JRef:
    def __init__(self, pack, sim, joints):
        m = sim.m
        self.qa = [m.jnt_qposadr[m.joint(j).id] for j in joints]
        self.da = [m.jnt_dofadr[m.joint(j).id] for j in joints]
        tr = pack["trace"]
        k = kfb.first(tr, "swing")
        self.q = np.array([[pack["state"][i]["qpos"][a] for a in self.qa] for i in range(k, len(pack["state"]))])
        self.qd = np.array([[pack["state"][i]["qvel"][a] for a in self.da] for i in range(k, len(pack["state"]))])
        self.t = np.arange(len(self.q)) * 0.01
    def at(self, el):
        i = min(max(int(round(el / 0.01)), 0), len(self.q) - 1)
        return self.q[i], self.qd[i]

def run_track(p, pack, jref, joints, kp, kd, limit, t_on=0.0, t_off=1e9):
    sim = p.sim
    k0 = kfb.first(pack["trace"], "swing")
    qa, da = jref.qa, jref.da
    def law(sim, task, el):
        if el < t_on or el > t_off:
            return None
        d = sim.u.robot.mj_data
        q = np.array([d.qpos[a] for a in qa]); qd = np.array([d.qvel[a] for a in da])
        qr, qdr = jref.at(el)
        tau = kp * (qr - q) + kd * (qdr - qd)
        tau = np.clip(tau, -limit, limit)
        return dict(joints=joints, taus=list(tau))
    r = p.run(pack, k0, law=law)
    c = P.contact_summary(r)
    c["cross_y"] = r["m"].get("cross_y", r["m"].get("pred_y"))
    return c

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--noise", default="0.05")
    ap.add_argument("--n", type=int, default=24)
    ap.add_argument("--kp", type=float, default=100.0)
    ap.add_argument("--kd", type=float, default=5.0)
    ap.add_argument("--limit", type=float, default=80.0)
    ap.add_argument("--joints", default="hip_rotation_r,hip_adduction_r,hip_flexion_r,knee_angle_r")
    ap.add_argument("--ton", type=float, default=0.0)
    ap.add_argument("--verbose", action="store_true")
    a = ap.parse_args()
    joints = a.joints.split(",")
    files = sorted(glob.glob(CK + f"p1base_n{a.noise}_dx*.pkl.gz"))[:a.n]
    p = P.Probe()
    refs = {+1: JRef(P.load(CK + "p1base_n0_dx+0_dy+0_s5000.pkl.gz"), p.sim, joints), -1: JRef(P.load(CK + "p1base_n0_dx+0_dy+0_s5002.pkl.gz"), p.sim, joints)}
    res0, res1 = [], []
    def fmt(c):
        if c.get("toe") is None: return "no contact"
        return f"y {100*c['toe'][1]:+6.1f} z {100*c['toe'][2]:+5.1f} v {c['ball_speed']:5.2f} launch {(c['launch'] or 0):+6.1f} ok {int(kfb.ok(c))}"
    for f in files:
        pack = P.load(f)
        var = kfb.variant(pack)
        k0 = kfb.first(pack["trace"], "swing")
        r0 = p.run(pack, k0); c0 = P.contact_summary(r0); c0["cross_y"] = r0["m"].get("cross_y", r0["m"].get("pred_y"))
        c1 = run_track(p, pack, refs[var], joints, a.kp, a.kd, a.limit, a.ton)
        res0.append(c0); res1.append(c1)
        if a.verbose: print(f"{f.split('/')[-1][:34]:34s} var {var:+d} | base {fmt(c0)} | track {fmt(c1)}", flush=True)
    def summ(rs, tag):
        okn = sum(1 for c in rs if kfb.ok(c)); ys = [c["toe"][1] for c in rs if c.get("toe") is not None]
        print(f"{tag}: ok {okn}/{len(rs)}  contact y mean {100*np.mean(ys):+.1f} std {100*np.std(ys):.1f} cm; speed mean {np.mean([c['ball_speed'] or 0 for c in rs]):.2f}", flush=True)
    summ(res0, f"noise {a.noise} baseline replay")
    summ(res1, f"track {a.joints} kp {a.kp} kd {a.kd} lim {a.limit} ton {a.ton}")
