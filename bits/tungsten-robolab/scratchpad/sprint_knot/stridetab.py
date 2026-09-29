"""stridetab: DIAGNOSTIC. One rollout, then a per-stance table of the steady tail, so a controller's
stance can be compared with the ideal-control stance (ideal_trace.py) number for number.

  ROBOLAB_CALIB=v4 [ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation] \
    .venv/bin/python scratchpad/sprint_knot/stridetab.py TASK PARAMS --controller C [--seed 221] [--seconds 20]
    [--tail 0.5] [--muscles r_knee_neg,...] [--dump out.npz]

Physics-step forces are read in the task's before_step hook (world-frame ground force on each foot, split
into vertical and horizontal), the joint angles / activations once per control tick. Per right-foot stance
(contact runs >= 30 ms, gaps < 20 ms merged) of the last `tail` fraction of the run it prints: contact,
flight before, thigh (world) / knee / ankle at touchdown, knee max, lift-off, vertical GRF mean and peak
(and when), horizontal impulses (braking, propulsion; BW s), the foot's velocity relative to the ground just
before touchdown, COM speed at touchdown and lift-off, and the mean activation of the right leg's muscles in
the four quarters of the stance.
"""
import argparse, json, math, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
import mujoco
import numpy as np
from practice import load_task, read_params
from bridge import Sim


class Rec:
    def __init__(self, sim):
        self.sim = sim
        m = sim.m
        self.floor = m.geom("floor").id
        self.geoms = {"l": {m.geom("l_foot").id, m.geom("l_toes").id}, "r": {m.geom("r_foot").id, m.geom("r_toes").id}}
        self.f6 = np.zeros(6)
        self.steps = []  # (t, lfx, lfz, rfx, rfz) per physics step, BW
        self.ticks = []  # per control tick
        self.pid = m.body("pelvis").id
        self.jq = {j: m.joint(j).qposadr[0] for j in ("r_hip_flex", "r_knee", "r_ankle", "l_hip_flex", "l_knee", "l_ankle", "root_pitch", "spine_flex")}
        self.jv = {j: m.joint(j).dofadr[0] for j in ("r_hip_flex", "r_knee", "r_ankle", "l_hip_flex", "l_knee", "l_ankle", "root_pitch")}
        self.names = [mu.name for mu in sim.muscles]
        self.vel6 = np.zeros(6)

    def hook(self, task):
        orig = task.before_step
        sim = self.sim

        def before_step(m, d):
            orig(m, d)
            f = {"l": [0.0, 0.0], "r": [0.0, 0.0]}
            for i in range(d.ncon):
                c = d.contact[i]
                if c.geom1 != self.floor and c.geom2 != self.floor:
                    continue
                other = c.geom2 if c.geom1 == self.floor else c.geom1
                side = "l" if other in self.geoms["l"] else "r" if other in self.geoms["r"] else None
                if side is None:
                    continue
                mujoco.mj_contactForce(m, d, i, self.f6)
                w = np.asarray(c.frame).reshape(3, 3).T @ self.f6[:3]
                if c.geom1 != self.floor:
                    w = -w
                f[side][0] += w[0]
                f[side][1] += w[2]
            bw = sim.weight
            self.steps.append((d.time, f["l"][0] / bw, f["l"][1] / bw, f["r"][0] / bw, f["r"][1] / bw))
        task.before_step = before_step

    def maybe_capture(self, sim):
        d, m = sim.d, sim.m
        com = d.subtree_com[self.pid]
        comv = d.subtree_linvel[self.pid]
        tor = d.body("torso").xmat.reshape(3, 3)[:, 2]
        def thigh(side):
            v = d.body(f"{side}_shin").xpos - d.body(f"{side}_thigh").xpos
            return math.atan2(v[0], -v[2])
        row = [d.time, com[0], com[2], comv[0], comv[2], math.atan2(tor[0], tor[2]),
               d.qpos[self.jq["root_pitch"]], thigh("r"), thigh("l")]
        row += [d.qpos[self.jq[j]] for j in ("r_hip_flex", "r_knee", "r_ankle", "l_hip_flex", "l_knee", "l_ankle")]
        row += [d.qvel[self.jv[j]] for j in ("r_hip_flex", "r_knee", "r_ankle")]
        for side in ("r", "l"):
            vv = np.zeros(6)
            mujoco.mj_objectVelocity(m, d, mujoco.mjtObj.mjOBJ_BODY, m.body(f"{side}_foot").id, vv, 0)
            row += [vv[3], vv[5], float(d.body(f"{side}_foot").xpos[0]), float(d.body(f"{side}_foot").xpos[2])]
        act = sim.log[-1][2]
        self.ticks.append(np.concatenate([row, act]))


def runs_of(mask, t, gap=0.02, minlen=0.03):
    out, a = [], None
    for k in range(len(t)):
        if mask[k] and a is None:
            a = k
        elif not mask[k] and a is not None:
            if out and t[a] - t[out[-1][1] - 1] < gap:
                out[-1] = (out[-1][0], k)
            else:
                out.append((a, k))
            a = None
    if a is not None:
        out.append((a, len(t)))
    return [(a, b) for a, b in out if t[b - 1] - t[a] >= minlen]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("task"); ap.add_argument("params")
    ap.add_argument("--controller"); ap.add_argument("--seed", default="221"); ap.add_argument("--seconds", type=float, default=20.0)
    ap.add_argument("--tail", type=float, default=0.5); ap.add_argument("--muscles", default=None)
    ap.add_argument("--dump"); ap.add_argument("--attr"); ap.add_argument("--set"); ap.add_argument("--start"); ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()
    p = read_params(a.params) if a.params != "-" else {}
    for kv in (a.set or "").split(","):
        if kv:
            k, v = kv.split("="); p[k] = float(v)
    task = load_task(a.task)
    for kv in (a.attr or "").split(","):
        if kv:
            setattr(task, kv.split("=")[0], float(kv.split("=")[1]))
    if a.start:
        task.start = a.start
    task.seed = None if a.seed in ("None", "none") else int(a.seed)
    sim = Sim(task, params=p, controller=a.controller)
    rec = Rec(sim)
    rec.hook(task)
    res = sim.run(a.seconds, recorder=rec)
    print({k: res.get(k) for k in ("time", "fell", "distance", "steady_speed", "peak_speed_1s", "step_freq", "contact_time", "flight_time",
                                  "peak_grf", "thigh_td", "thigh_lo", "knee_td", "knee_max", "knee_lo", "stance_t", "stance_fz")})
    S = np.array(rec.steps); T = np.array(rec.ticks)
    if a.dump:
        np.savez_compressed(a.dump, steps=S, ticks=T, names=np.array(rec.names))
    t = S[:, 0]
    tail_t = t[-1] * (1.0 - a.tail)
    mus = a.muscles.split(",") if a.muscles else [n for n in rec.names if n.startswith("r_")]
    mi = [rec.names.index(n) for n in mus]
    contact = S[:, 4] > 0.01
    lcontact = S[:, 2] > 0.01
    runs = [(x, y) for x, y in runs_of(contact, t) if t[x] >= tail_t]
    rows = []
    prev_td = None
    for a0, b0 in runs:
        if prev_td is None:
            prev_td = t[a0]; continue
        sl = slice(a0, b0)
        tt, fx, fz = t[sl], S[sl, 3], S[sl, 4]
        tc = tt[-1] - tt[0]
        ka = np.searchsorted(T[:, 0], tt[0]); kb = np.searchsorted(T[:, 0], tt[-1])
        kb = max(kb, ka + 1)
        k0 = max(ka - 1, 0)
        dt = t[1] - t[0]
        j = a0
        while j > 0 and not contact[j - 1] and not lcontact[j - 1]:
            j -= 1
        r = {"t": tt[0], "tc": tc, "flight": t[a0] - t[j], "stride": tt[0] - prev_td,
             "th_td": T[ka, 7], "th_lo": T[kb, 7], "kn_td": T[ka, 10], "kn_max": T[ka:kb + 1, 10].max(), "kn_lo": T[kb, 10],
             "an_td": T[ka, 11], "an_lo": T[kb, 11],
             "fz_mean": fz.mean(), "fz_peak": fz.max(), "t_peak": tt[np.argmax(fz)] - tt[0],
             "brake": -np.minimum(fx, 0).sum() * dt, "prop": np.maximum(fx, 0).sum() * dt, "vz_imp": fz.sum() * dt,
             "foot_vx": T[k0, 18], "foot_vz": T[k0, 19], "com_v_td": T[ka, 3], "com_v_lo": T[kb, 3], "com_vz_lo": T[kb, 4],
             "com_z_td": T[ka, 2], "pitch_td": T[ka, 5], "pitch_lo": T[kb, 5]}
        n = kb - ka + 1
        q = np.array_split(np.arange(ka, kb + 1), 4)
        acts = T[:, 26:]
        r["act"] = [[float(acts[qq][:, i].mean()) if len(qq) else float("nan") for qq in q] for i in mi]
        rows.append(r)
        prev_td = tt[0]
    if not rows:
        print("no stances in the tail"); return
    keys = ["tc", "flight", "stride", "th_td", "th_lo", "kn_td", "kn_max", "kn_lo", "an_td", "an_lo", "fz_mean", "fz_peak", "t_peak", "brake", "prop", "vz_imp",
            "foot_vx", "foot_vz", "com_v_td", "com_v_lo", "com_vz_lo", "com_z_td", "pitch_td", "pitch_lo"]
    print(f"{len(rows)} right-foot stances in the tail (t >= {tail_t:.1f} s); mean (std)")
    for k in keys:
        v = np.array([r[k] for r in rows])
        print(f"  {k:9s} {v.mean():8.3f} ({v.std():.3f})")
    acts = np.array([r["act"] for r in rows]).mean(axis=0)
    print("  mean activation by stance quarter (right leg):")
    for n, row in zip(mus, acts):
        print(f"    {n:16s} " + " ".join(f"{x:5.2f}" for x in row))
    ext = {"fx_net": np.mean([r["prop"] - r["brake"] for r in rows])}
    print("  net horizontal impulse per stance (BW s):", round(float(ext["fx_net"]), 4), " x BW/mass -> dv per stance (m/s):", round(float(ext["fx_net"]) * 9.81, 3))


if __name__ == "__main__":
    main()
