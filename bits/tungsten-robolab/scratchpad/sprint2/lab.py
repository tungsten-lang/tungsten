"""lab: flying-start / standing-start rollouts of a controller with a per-stance table, for the round-2 sprint work.

  source scratchpad/sprint2/env.sh      # the v4 P95 body
  ROBOLAB_SNAP=run_v4_p95i .venv/bin/python scratchpad/sprint2/lab.py PARAMS --controller C \
      --seeds 0,1,2,3 --seconds 12 [--start flying] [--set k=v,...] [--stab kp,kd,limit[,mode]] [--table]

Defaults: task sprint_touch_v4, flying start from the snapshot set ROBOLAB_SNAP (fly_touch 2, objective 3, fall_pen 300).
Per seed: fell / fall time, peak_speed_1s, steady speed, and the mean over the right-foot stances of the last `tail`
of the run: contact, flight, step length (v x stride / 2), thigh (world) at touchdown and lift-off, knee at touchdown
and its maximum, mean and peak vertical force, torso pitch at touchdown and lift-off (and its rock over the stance).

--stab kp,kd,limit[,mode]: DIAGNOSTIC ideal trunk stabiliser (an external torque on the torso body: NOT an actuator
the body has). torque = clip(-kp (pitch - pitch_ref) - kd pitch_rate, +-limit) N m about the world y axis; mode
"always" (default) or "stance" (a foot loaded). pitch_ref = the torso pitch at the start unless --stab_ref is given.
"""
import argparse, json, math, multiprocessing as mp, os, sys, time
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
sys.path.insert(0, os.path.join(ROOT, "scratchpad", "sprint_knot"))
import mujoco
import numpy as np
from practice import load_task, read_params
from bridge import Sim
import stridetab as st  # Rec, runs_of


class Stab:
    """the diagnostic external trunk torque"""
    def __init__(self, spec, ref):
        parts = spec.split(",")
        self.kp, self.kd, self.limit = float(parts[0]), float(parts[1]), float(parts[2])
        self.mode = parts[3] if len(parts) > 3 else "always"
        self.ref = ref
        self.impulse = 0.0
        self.peak = 0.0
        self.n = 0

    def install(self, sim, task, floor_geoms):
        m = sim.m
        tid = m.body("torso").id
        orig = task.before_step
        self.applied = []

        def before_step(m_, d):
            orig(m_, d)
            d.xfrc_applied[tid, :] = 0.0
            tu = d.xmat[tid].reshape(3, 3)[:, 2]
            pitch = math.atan2(tu[0], tu[2])
            vv = np.zeros(6)
            mujoco.mj_objectVelocity(m_, d, mujoco.mjtObj.mjOBJ_BODY, tid, vv, 0)
            rate = vv[1]
            on = True
            if self.mode == "stance":
                on = False
                for i in range(d.ncon):
                    c = d.contact[i]
                    if (c.geom1 in floor_geoms) or (c.geom2 in floor_geoms):
                        on = True
                        break
            if on:
                ref = self.ref if self.ref is not None else self.ref0
                tq = -self.kp * (pitch - ref) - self.kd * rate
                tq = max(-self.limit, min(self.limit, tq))
                d.xfrc_applied[tid, 4] = tq
                self.impulse += tq * m_.opt.timestep
                self.peak = max(self.peak, abs(tq))
                self.n += 1
        task.before_step = before_step

    ref0 = 0.0


def run_one(spec):
    (task_name, params, seed, seconds, start, attrs, controller, stab, stab_ref, tail, want_table) = spec
    task = load_task(task_name)
    for k, v in attrs.items():
        setattr(task, k, v)
    if start:
        task.start = start
    task.seed = None if seed in (None, "none", "None") else int(seed)
    sim = Sim(task, params=dict(params), controller=controller)
    rec = st.Rec(sim)
    rec.hook(task)
    stabilizer = None
    if stab:
        stabilizer = Stab(stab, stab_ref)
        floor_geoms = {sim.m.geom(n).id for n in ("l_foot", "r_foot", "l_toes", "r_toes")}
        stabilizer.install(sim, task, floor_geoms)
        # reference pitch: the initial torso pitch (a snapshot's own) unless given
        _orig_reset = task.reset

        def reset(m, d, _o=_orig_reset, _s=stabilizer):
            _o(m, d)
            mujoco.mj_forward(m, d)
            tu = d.body("torso").xmat.reshape(3, 3)[:, 2]
            _s.ref0 = math.atan2(tu[0], tu[2])
        task.reset = reset
    t0 = time.time()
    try:
        res = sim.run(seconds, recorder=rec)
    except Exception as e:  # noqa
        return {"seed": seed, "error": str(e)[:300]}
    out = {"seed": seed, "fell": bool(res.get("fell")), "t": res.get("time"),
           "peak": res.get("peak_speed_1s"), "steady": res.get("steady_speed"), "wall": round(time.time() - t0, 1)}
    if stabilizer is not None:
        out["stab_peak"] = round(stabilizer.peak, 1)
        out["stab_impulse"] = round(stabilizer.impulse, 2)
    tab = stance_table(rec, res, tail)
    out.update(tab)
    if want_table:
        out["_rows"] = tab.get("_rows")
    out.pop("_rows", None) if not want_table else None
    return out


def stance_table(rec, res, tail):
    S = np.array(rec.steps); T = np.array(rec.ticks)
    if len(S) < 200 or len(T) < 10:
        return {}
    t = S[:, 0]
    tail_t = t[-1] * (1.0 - tail)
    contact = S[:, 4] > 0.01
    lcontact = S[:, 2] > 0.01
    runs = [(x, y) for x, y in st.runs_of(contact, t) if t[x] >= tail_t]
    rows = []
    prev_td = None
    dt = t[1] - t[0]
    for a0, b0 in runs:
        if prev_td is None:
            prev_td = t[a0]
            continue
        sl = slice(a0, b0)
        tt, fx, fz = t[sl], S[sl, 3], S[sl, 4]
        ka = int(np.searchsorted(T[:, 0], tt[0])); kb = int(np.searchsorted(T[:, 0], tt[-1]))
        kb = max(kb, ka + 1)
        if kb >= len(T):
            break
        j = a0
        while j > 0 and not contact[j - 1] and not lcontact[j - 1]:
            j -= 1
        stride = tt[0] - prev_td
        v = 0.5 * (T[ka, 3] + T[kb, 3])
        pitch = T[ka:kb + 1, 5]
        rows.append({"tc": tt[-1] - tt[0], "flight": t[a0] - t[j], "stride": stride, "step": v * stride / 2.0, "v": v,
                     "th_td": T[ka, 7], "th_lo": T[kb, 7], "kn_td": T[ka, 10], "kn_max": T[ka:kb + 1, 10].max(), "kn_lo": T[kb, 10],
                     "fz_mean": fz.mean(), "fz_peak": fz.max(), "brake": -np.minimum(fx, 0).sum() * dt, "prop": np.maximum(fx, 0).sum() * dt,
                     "pitch_td": pitch[0], "pitch_lo": pitch[-1], "pitch_rock": pitch[-1] - pitch[0], "pitch_range": pitch.max() - pitch.min(),
                     "vz_lo": T[kb, 4]})
        prev_td = tt[0]
    if not rows:
        return {}
    keys = list(rows[0].keys())
    out = {k: round(float(np.mean([r[k] for r in rows])), 3) for k in keys}
    out["n_st"] = len(rows)
    out["_rows"] = rows
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("params")
    ap.add_argument("--task", default="sprint_touch_v4")
    ap.add_argument("--controller", default=os.path.join(ROOT, "bin", "challengers", "run_gear-v4c"))
    ap.add_argument("--seeds", default="0,1,2,3")
    ap.add_argument("--seconds", type=float, default=12.0)
    ap.add_argument("--start", default="flying")
    ap.add_argument("--set", default="")
    ap.add_argument("--attrs", default="objective=3,fly_touch=2,fall_pen=300")
    ap.add_argument("--stab"); ap.add_argument("--stab_ref", type=float)
    ap.add_argument("--tail", type=float, default=0.5)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--table", action="store_true")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    p = read_params(a.params) if a.params != "-" else {}
    for kv in a.set.split(","):
        if kv:
            k, v = kv.split("="); p[k] = float(v)
    attrs = {kv.split("=")[0]: float(kv.split("=")[1]) for kv in a.attrs.split(",") if kv}
    seeds = [None if s in ("None", "none") else int(s) for s in a.seeds.split(",")]
    specs = [(a.task, p, s, a.seconds, a.start if a.start != "standing" else None, attrs, a.controller, a.stab, a.stab_ref, a.tail, a.table) for s in seeds]
    if a.workers > 1 and len(specs) > 1:
        with mp.Pool(min(a.workers, len(specs))) as pool:
            res = pool.map(run_one, specs, chunksize=1)
    else:
        res = [run_one(s) for s in specs]
    cols = ["tc", "flight", "step", "th_td", "th_lo", "kn_td", "kn_max", "fz_mean", "fz_peak", "pitch_td", "pitch_lo", "pitch_rock", "vz_lo"]
    print("seed  fell     t   peak steady | " + " ".join(f"{c:>8s}" for c in cols) + (" | stab peak/impulse" if a.stab else ""))
    falls, peaks = 0, []
    for r in res:
        if "error" in r:
            print(r["seed"], "ERROR", r["error"]); continue
        falls += int(r["fell"])
        if not r["fell"] and r.get("peak"):
            peaks.append(r["peak"])
        line = f"{str(r['seed']):>4s}  {'FALL' if r['fell'] else 'ok  '} {r['t']:5.1f} {r.get('peak') or 0:6.3f} {r.get('steady') or 0:6.3f} | "
        line += " ".join(f"{r.get(c, float('nan')):8.3f}" for c in cols)
        if a.stab:
            line += f" | {r.get('stab_peak')} / {r.get('stab_impulse')}"
        print(line)
    print(f"falls {falls}/{len(res)}  mean peak of survivors {np.mean(peaks) if peaks else 0:.3f}  min {min(peaks) if peaks else 0:.3f}")
    if a.table:
        for r in res:
            rows = r.get("_rows") or []
            print("seed", r["seed"], "stances", len(rows))
            for x in rows:
                print("  " + " ".join(f"{k}={x[k]:.3f}" for k in ("tc", "flight", "step", "th_td", "th_lo", "kn_td", "kn_max", "fz_mean", "fz_peak", "pitch_td", "pitch_lo")))


if __name__ == "__main__":
    main()
