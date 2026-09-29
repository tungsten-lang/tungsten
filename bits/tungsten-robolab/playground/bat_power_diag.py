"""Where does the swing's speed go? Per-pitch power diagnostics for the bat task.

    .venv/bin/python playground/bat_power_diag.py --params params/bat_v5_load.txt \
        --controller bin/challengers/bat_v5-20260927 [--seeds 0-17] [--workers 4] [--json out.json]

Runs the arena's seeded pitches (BAT_SEEDED_PITCH=1; BAT_BODY defaults to
athlete, ROBOLAB_PROFILE passes through) and reports, per pitch and as means:

  speed      sweet-spot bat speed at contact, its peak over the swing and when
             that peak came (ms before contact), the bottom hand's speed (peak,
             at contact), bat angular speed (peak, at contact)
  chain      each segment's peak and its time before contact (pelvis and torso
             yaw rate, hands, bat angular speed, bat head): a kinematic
             sequence has each peak later than the one below it
  joints     per joint, the peak |joint speed| from the hips firing to contact,
             as a fraction of its unloaded limit (vmax / 0.3 ranges per second:
             MuJoCo's force-velocity curve leaves (1 - v/vmax)^2 of the
             isometric force, so a joint near its limit has no force left)
  activation per muscle group, over the POWER PHASE (each track from its own
             swing chunk to contact; the whole group from the hips firing
             with --window swing), the prime movers' share of time at
             activation >= 0.9 (the prime mover of a joint is the muscle the
             joint's motion over the phase shortens), their mean activation,
             the share of time the pair's more active muscle (the instantaneous
             agonist, for motions that reverse inside the phase) is at >= 0.9,
             the antagonists' mean activation, and the co-contraction index
             CCI = 2 sum(min(a_pm, a_ant)) / sum(a_pm + a_ant) (Falconer &
             Winter 1985; 0 = no overlap, 1 = equal co-activation)

Nothing here drives the controller; it reads the bridge's per-tick log plus
the body state it records each tick.
"""

import argparse
import json
import multiprocessing as mp
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))

# muscle groups by joint prefix (the batter's body; pelvis_* are the pivot's yaw and shift)
GROUPS = {
    "legs": ("l_hip", "r_hip", "l_knee", "r_knee", "l_ankle", "r_ankle"),
    "pelvis": ("pelvis_yaw", "pelvis_shift"),
    "trunk": ("spine_",),
    "shoulders": ("l_shoulder", "r_shoulder"),
    "elbows": ("l_elbow", "r_elbow"),
    "wrists": ("l_wrist", "r_wrist"),
}
# which track drives each group (its power phase starts at the track's swing)
GROUP_TRACK = {"legs": "hips", "pelvis": "hips", "trunk": "torso", "shoulders": "arms", "elbows": "arms",
               "wrists": "arms"}
ACT_HI = 0.9


def load_params(path):
    prm = {}
    if path:
        for line in open(path):
            parts = line.split()
            if len(parts) >= 2 and not line.startswith("#"):
                prm[parts[0]] = float(parts[1])
    return prm


def rollout(job):
    params, controller, seed, seconds = job[:4]
    fresh = len(job) > 4 and job[4]
    os.environ.setdefault("BAT_BODY", "athlete")
    os.environ["BAT_SEEDED_PITCH"] = "0" if fresh else "1"
    os.environ["BAT_FRESH_PITCH"] = "1" if fresh else "0"
    sys.path.insert(0, HERE)
    sys.path.insert(0, os.path.join(HERE, "tasks"))
    import mujoco
    from bridge import Sim
    import bat as battask

    class DiagSim(Sim):
        """Sim that also records body state after each control tick."""
        def run(self, seconds=None, recorder=None):
            self.extra = []
            m, d = self.m, self.d
            task = self.task
            v = np.zeros(6)
            orig_log = self.log

            class Log(list):
                def append(inner, item):
                    list.append(inner, item)
                    rec = {}
                    mujoco.mj_objectVelocity(m, d, mujoco.mjtObj.mjOBJ_SITE, task.site["bat_sweet"], v, 0)
                    rec["head"] = float(np.linalg.norm(v[3:]))
                    mujoco.mj_objectVelocity(m, d, mujoco.mjtObj.mjOBJ_SITE, task.r_grip, v, 0)
                    rec["hands"] = float(np.linalg.norm(v[3:]))
                    mujoco.mj_objectVelocity(m, d, mujoco.mjtObj.mjOBJ_BODY, task.bat_body, v, 0)
                    rec["bat_w"] = float(np.linalg.norm(v[:3]))
                    mujoco.mj_objectVelocity(m, d, mujoco.mjtObj.mjOBJ_BODY, task.pelvis, v, 0)
                    rec["pelvis"] = abs(float(v[2]))
                    mujoco.mj_objectVelocity(m, d, mujoco.mjtObj.mjOBJ_BODY, task.torso, v, 0)
                    rec["torso"] = abs(float(v[2]))
                    self.extra.append(rec)
            self.log = Log(orig_log)
            return Sim.run(self, seconds, recorder)

    task = battask.BatTask()
    task.seed = seed
    sim = DiagSim(task, params=params, controller=controller)
    res = sim.run(seconds)
    names = [mu.name for mu in sim.muscles]
    ranges = {mu.joint: (mu.qmin, mu.qmax) for mu in sim.muscles}
    vmax = float(sim.m.actuator_gainprm[sim.act_ids[0], 6]) if sim.m.nu else 1.5
    # per-muscle vmax (L0/s) as the model has it
    vm = [float(sim.m.actuator_gainprm[i, 6]) for i in sim.act_ids]
    t = np.array([e[0] for e in sim.log])
    labels = [e[1] for e in sim.log]
    act = np.array([e[2] for e in sim.log])
    c = np.array([e[3] for e in sim.log])
    ex = sim.extra
    del vmax
    rows = analyse(res, names, ranges, vm, t, labels, act, c, ex, task.control_dt)
    for r in rows:   # the run's arena metrics (one pitch per seeded rollout)
        r.update({"seed": seed, "flow": res.get("flow"), "quality": res.get("quality"), "power": res.get("power")})
    return rows


def track_start(labels, t, track, name, t_from, t_to):
    key = f"{track}:{name}"
    for k in range(int(np.searchsorted(t, t_from)), int(np.searchsorted(t, t_to))):
        if key in labels[k].split("|"):
            return t[k]
    return None


def analyse(res, names, ranges, vm, t, labels, act, c, ex, dt):
    out = []
    for p in res["pitches"]:
        tc = p.get("t_contact", p.get("t_closest"))
        ts = p.get("t_swing")
        if tc is None or ts is None:
            out.append({"hit": p["hit"], "note": "no swing/contact"})
            continue
        r = {"hit": p["hit"], "fair": p.get("fair"), "bat_speed": p.get("bat_speed"),
             "launch_deg": p.get("launch_deg"), "swing_to_contact_ms": p.get("swing_to_contact_ms")}
        # kc: the last logged tick before contact (the impact itself slows the bat)
        k0, kc = int(np.searchsorted(t, ts - 0.05)), int(np.searchsorted(t, tc)) - 1
        kc = min(kc, len(t) - 1)
        seg = {}
        for key in ("pelvis", "torso", "hands", "bat_w", "head"):
            xs = np.array([ex[k][key] for k in range(k0, kc + 1)])
            j = int(np.argmax(xs))
            seg[key] = {"peak": round(float(xs[j]), 2), "ms_before": round(1000 * (tc - t[k0 + j]), 0),
                        "at_contact": round(float(xs[-1]), 2)}
        r["chain"] = seg
        # per-joint speed from the pos muscle's contraction: c_pos = (q - qmin) / range
        kw0 = int(np.searchsorted(t, ts))
        joints = {}
        for i, n in enumerate(names):
            if not n.endswith("_pos"):
                continue
            j = n[:-4]
            lo, hi = ranges[j]
            rng = hi - lo
            qd = np.diff(c[kw0 - 1:kc + 1, i]) / dt * rng
            if len(qd) == 0:
                continue
            lim = vm[i] / 0.3 * rng
            kk = int(np.argmax(np.abs(qd)))
            cs = c[kw0 - 1:kc + 1, i]          # the pos muscle's contraction = the joint's place in its range (0..1)
            margin = np.minimum(cs, 1.0 - cs)  # distance to the nearer end of the range, as a fraction of the range
            joints[j] = {"peak_radps": round(float(abs(qd[kk])), 2), "limit_radps": round(lim, 1),
                         "frac": round(float(abs(qd[kk])) / lim, 3),
                         "ms_before": round(1000 * (tc - t[kw0 + kk]), 0),
                         "at_contact": round(float(qd[-1]), 2),
                         "min_margin": round(float(margin.min()), 3),
                         "pct_near_limit": round(100.0 * float(np.mean(margin < 0.03)), 1)}
        r["joints"] = joints
        # activation over each group's power phase
        acts = {}
        for g, pref in GROUPS.items():
            t0 = track_start(labels, t, GROUP_TRACK[g], "swing", ts - 0.3, tc) or ts
            a0, a1 = int(np.searchsorted(t, t0)), kc
            if a1 - a0 < 2:
                continue
            hi_n = ag_n = pm_sum = ant_sum = cmin = csum = peak = 0.0
            n_t = 0
            for i, n in enumerate(names):
                if not (n.endswith("_pos") and n.startswith(pref)):
                    continue
                j = n[:-4]
                ineg = names.index(j + "_neg")
                # prime mover: the muscle the joint's net motion over the phase shortens
                dq = c[a1, i] - c[a0, i]
                pm, an = (i, ineg) if dq >= 0 else (ineg, i)
                apm, aan = act[a0:a1, pm], act[a0:a1, an]
                hi_n += float(np.sum(apm >= ACT_HI))
                # the instantaneous agonist: the more active muscle of the pair
                ag_n += float(np.sum(np.maximum(apm, aan) >= ACT_HI))
                peak = max(peak, float(apm.max()), float(aan.max()))
                pm_sum += float(np.sum(apm))
                ant_sum += float(np.sum(aan))
                cmin += float(np.sum(np.minimum(apm, aan)))
                csum += float(np.sum(apm + aan))
                n_t += len(apm)
            if n_t:
                acts[g] = {"phase_ms": round(1000 * (t[a1] - t[a0]), 0),
                           "pm_hi_pct": round(100 * hi_n / n_t, 1), "ag_hi_pct": round(100 * ag_n / n_t, 1),
                           "pm_mean": round(pm_sum / n_t, 3), "peak": round(peak, 3),
                           "ant_mean": round(ant_sum / n_t, 3), "cci": round(2 * cmin / max(csum, 1e-9), 3)}
        r["activation"] = acts
        out.append(r)
    return out


def summarise(rows):
    rows = [r for r in rows if "chain" in r]
    if not rows:
        return {}
    def mean(xs):
        xs = [x for x in xs if x is not None]
        return round(float(np.mean(xs)), 3) if xs else None
    s = {"n": len(rows), "hits": sum(1 for r in rows if r["hit"]), "fair": sum(1 for r in rows if r.get("fair")),
         "power": mean([r["bat_speed"] if r["hit"] else 0.0 for r in rows]),
         "swing_to_contact_ms": mean([r["swing_to_contact_ms"] for r in rows]),
         # the arena's bat_flow score: a miss adds 1.0
         "flow": mean([(r.get("flow") if r.get("flow") is not None else 0.0) + (0.0 if r["hit"] else 1.0) for r in rows]),
         "quality": mean([r.get("quality") for r in rows])}
    s["chain"] = {k: {f: mean([r["chain"][k][f] for r in rows]) for f in ("peak", "ms_before", "at_contact")}
                  for k in rows[0]["chain"]}
    js = rows[0]["joints"].keys()
    s["joints"] = {j: {f: mean([r["joints"][j][f] for r in rows if j in r["joints"]])
                       for f in ("peak_radps", "limit_radps", "frac", "ms_before", "at_contact", "min_margin", "pct_near_limit")}
                   for j in js}
    gs = [g for g in GROUPS if any(g in r["activation"] for r in rows)]
    s["activation"] = {g: {f: mean([r["activation"][g][f] for r in rows if g in r["activation"]])
                           for f in ("phase_ms", "pm_hi_pct", "ag_hi_pct", "pm_mean", "ant_mean", "cci", "peak")} for g in gs}
    return s


def print_summary(s, label=""):
    print(f"== {label} n {s['n']} hits {s['hits']} fair {s['fair']} power {s['power']} m/s  "
          f"flow {s['flow']} quality {s['quality']}  swing->contact {s['swing_to_contact_ms']} ms")
    print("chain (peak, ms before contact, at contact):")
    for k, v in s["chain"].items():
        print(f"  {k:7s} {v['peak']:7.2f} {v['ms_before']:6.0f} ms  {v['at_contact']:7.2f}")
    print("joints (peak rad/s, unloaded limit, frac, ms before contact, at contact, range margin: closest approach to an end of the "
          "range as a fraction of it, % of the swing within 3 % of an end):")
    for j, v in s["joints"].items():
        if v["peak_radps"] is None:
            continue
        print(f"  {j:18s} {v['peak_radps']:6.2f} / {v['limit_radps']:5.1f}  {v['frac']:.2f}  {v['ms_before']:6.0f} ms  {v['at_contact']:6.2f}"
              f"   margin {v['min_margin']:.3f}  near limit {v['pct_near_limit']:4.1f} %")
    print("activation over each group's power phase (% of it at >= 0.9: prime movers of the net motion, the "
          "instantaneous agonist; pm mean, antagonist mean, CCI):")
    for g, v in s["activation"].items():
        print(f"  {g:9s} {v['phase_ms']:5.0f} ms  pm {v['pm_hi_pct']:5.1f} %  agonist {v['ag_hi_pct']:5.1f} %  "
              f"pm {v['pm_mean']:.3f}  ant {v['ant_mean']:.3f}  CCI {v['cci']:.3f}  peak {v['peak']:.2f}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--params")
    ap.add_argument("--controller")
    ap.add_argument("--set", action="append", default=[], help="k=v param override (repeatable)")
    ap.add_argument("--seeds", default="0-17")
    ap.add_argument("--fresh", action="store_true", help="each seed draws a fresh continuous pitch (BAT_FRESH_PITCH) instead of a grid pitch")
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--seconds", type=float, default=7.8)
    ap.add_argument("--json")
    ap.add_argument("--label", default="")
    a = ap.parse_args()
    prm = load_params(a.params)
    for kv in a.set:
        k, _, v = kv.partition("=")
        prm[k] = float(v)
    lo, _, hi = a.seeds.partition("-")
    seeds = list(range(int(lo), int(hi or lo) + 1))
    ctl = os.path.abspath(a.controller) if a.controller else None
    with mp.get_context("spawn").Pool(a.workers) as pool:
        per = pool.map(rollout, [(prm, ctl, s, a.seconds, a.fresh) for s in seeds])
    rows = [r for rs in per for r in rs]
    s = summarise(rows)
    print_summary(s, a.label or os.path.basename(a.params or "defaults"))
    if a.json:
        with open(a.json, "w") as f:
            json.dump({"summary": s, "rows": rows, "params": prm, "controller": ctl, "seeds": seeds}, f, indent=1)


if __name__ == "__main__":
    main()
