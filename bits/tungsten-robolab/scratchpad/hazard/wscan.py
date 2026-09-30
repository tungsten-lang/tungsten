"""wscan: run soccer starts on the guarded task (myo_soccer_ng) with extra per-control-step telemetry of the swing leg
(margin of recfem_r / recfem_l and the right leg's joint angles), in COUNT-ONLY or nudge mode, and print/collect one row per job.

usage: wscan.py --jobs jobs.json --out rows.jsonl [--workers 4] [--mode 0|1]
  jobs.json: [{"tag": "x-97100", "seed": 97100, "params": "params/x.txt", "controller": "bin/challengers/y", "seconds": 20,
               "set": {"b_sw_knee": 1.7}}, ...]     ("set" overrides params entries; a params file OR "pdict" inline dict)
Rows (jsonl, one per job): base metrics (stand_time, bal1_raw, fallen, t_fall, hold20, nan_*), the substep margin histogram of recfem_r
(wrap_r_hist: 9 |margin| bins x positive|negative, EDGES of the task), exposure fractions e4 / e3 / e5 (|margin| under 1e-4 / 1e-3 / 1e-5 of the
watched substeps after 3 s), and the control-step probe: margin mean / std / min / max, the fraction of steps wrapping, and the right leg's joint means
and stds over t >= 3 s and over the last 5 s.

Mode 0 (default here) counts NaN events without nudging (the official behaviour); mode 1 nudges (the guarded arena's).
Read-only telemetry: a rollout is bit-identical to the plain guarded task's.
"""
import argparse
import json
import multiprocessing as mp
import os
import sys
import time

import numpy as np

HERE = "/Users/erik/tungsten/bits/tungsten-robolab"
sys.path.insert(0, os.path.join(HERE, "playground"))
sys.path.insert(0, os.path.join(HERE, "scratchpad", "soccer4"))

sys.path.insert(0, os.path.join(HERE, "scratchpad", "blowup"))

JOINTS = ["hip_flexion_r", "hip_adduction_r", "hip_rotation_r", "knee_angle_r", "ankle_angle_r", "subtalar_angle_r",
          "hip_flexion_l", "hip_adduction_l", "knee_angle_l"]
EDGES = [0.0, 1e-8, 6e-8, 1e-7, 1e-6, 1e-5, 1e-4, 1e-3, 1e-2, 1e9]


class AllSegs:
    """Vectorised control-step margins of ALL wrapped cylinder/sphere segments (68 in the soccer body): margin = (r^2 - |tmp|^2) / r^2 in each
    wrap's 2D frame (tmp = the nearest point of the tendon line to the axis / centre), sidesites ignored (the margin near the tangent does not
    depend on them). Per segment: steps within 1e-3 / 1e-4 of the tangent, sign changes. Segments with an endpoint inside the circle are skipped."""

    def __init__(self, m):
        import mujoco
        import wrapscan
        self.segs = wrapscan.segments(m)
        self.names = [s[1] + "@" + str(mujoco.mj_id2name(m, mujoco.mjtObj.mjOBJ_GEOM, s[3])) for s in self.segs]
        self.g = np.array([s[3] for s in self.segs])
        self.s0 = np.array([s[2] for s in self.segs])
        self.s1 = np.array([s[4] for s in self.segs])
        self.sph = np.array([s[6] == int(mujoco.mjtWrap.mjWRAP_SPHERE) for s in self.segs])
        self.r = np.array([s[7] for s in self.segs])
        n = len(self.segs)
        self.n = np.zeros(n)
        self.near3 = np.zeros(n)
        self.near4 = np.zeros(n)
        self.flips = np.zeros(n)
        self.last = np.full(n, -1)

    def margins(self, d):
        xm = d.geom_xmat[self.g].reshape(-1, 3, 3)
        c = d.geom_xpos[self.g]
        p0 = np.einsum("nji,nj->ni", xm, d.site_xpos[self.s0] - c)
        p1 = np.einsum("nji,nj->ni", xm, d.site_xpos[self.s1] - c)
        q0, q1 = p0[:, :2].copy(), p1[:, :2].copy()
        if self.sph.any():  # spheres: the plane through the centre, p0 and p1 (a0 along p0)
            i = np.flatnonzero(self.sph)
            a0 = p0[i] / np.linalg.norm(p0[i], axis=1, keepdims=True)
            nrm = np.cross(p0[i], p1[i])
            nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-30)
            a1 = np.cross(nrm, a0)
            q0[i] = np.stack([(p0[i] * a0).sum(1), (p0[i] * a1).sum(1)], 1)
            q1[i] = np.stack([(p1[i] * a0).sum(1), (p1[i] * a1).sum(1)], 1)
        dif = q1 - q0
        dd = (dif * dif).sum(1)
        a = np.clip(-(dif * q0).sum(1) / np.maximum(dd, 1e-30), 0.0, 1.0)
        tmp = q0 + a[:, None] * dif
        r2 = self.r ** 2
        mg = (r2 - (tmp * tmp).sum(1)) / r2
        inside = ((q0 * q0).sum(1) <= r2) | ((q1 * q1).sum(1) <= r2) | (dd < 1e-15)
        mg[inside] = np.nan
        return mg

    def step(self, d):
        mg = self.margins(d)
        ok = np.isfinite(mg)
        self.n += ok
        self.near3 += ok & (np.abs(mg) < 1e-3)
        self.near4 += ok & (np.abs(mg) < 1e-4)
        pos = np.where(ok, (mg > 0).astype(int), -1)
        self.flips += ok & (self.last >= 0) & (pos != self.last)
        self.last = np.where(ok, pos, self.last)

    def summary(self, top=4):
        out = {}
        frac3 = np.where(self.n > 0, self.near3 / np.maximum(self.n, 1), 0)
        frac4 = np.where(self.n > 0, self.near4 / np.maximum(self.n, 1), 0)
        order = np.argsort(-frac3)
        out["seg_top"] = ";".join(f"{self.names[i]}:{frac3[i]:.4f}:{frac4[i]:.4f}:{int(self.flips[i])}" for i in order[:top] if frac3[i] > 0)
        rf = [i for i, nm in enumerate(self.names) if nm.startswith("recfem_r_tendon")]
        oth = [i for i in range(len(self.names)) if i not in rf]
        out["seg_rf_near3"] = float(frac3[rf].max()) if rf else 0.0
        out["seg_rf_near4"] = float(frac4[rf].max()) if rf else 0.0
        out["seg_oth_near3"] = float(frac3[oth].max())
        out["seg_oth_near4"] = float(frac4[oth].max())
        out["seg_oth_name"] = self.names[oth[int(np.argmax(frac3[oth]))]]
        return out


def make_task():
    from tasks.myo_soccer_ng import NanGuardSoccerTask

    class ProbeTask(NanGuardSoccerTask):
        def episode(self, sim):
            first = getattr(self, "_sim", None) is not sim
            super().episode(sim)
            if first:
                self.rows = []
                self.allsegs = AllSegs(sim.u.robot.mj_model)
                m = sim.u.robot.mj_model
                self.adr = [int(m.jnt_qposadr[m.joint(n).id]) for n in JOINTS]

        def on_step(self, sim, obs, reward, info):
            super().on_step(sim, obs, reward, info)
            t = float(sim.d.time)
            if t >= 3.0:
                d = sim.u.robot.mj_data
                self.allsegs.step(d)
                mgs = []
                for seg in self.watch.segs:
                    mg, _, _ = self.watch.margin_end(d, seg)
                    mgs.append(np.nan if mg is None else mg)
                self.rows.append([t] + mgs + [float(d.qpos[a]) for a in self.adr])

        def metrics(self, sim, log):
            out = super().metrics(sim, log)
            if getattr(self, "allsegs", None) is not None:
                out.update(self.allsegs.summary())
            r = np.array(self.rows) if getattr(self, "rows", None) else np.zeros((0, 3 + len(JOINTS)))
            sp = os.environ.get("WSCAN_SERIES")
            if sp and len(r):
                os.makedirs(os.path.dirname(sp) or ".", exist_ok=True)
                np.save(sp, r)   # columns: t, margin_r, margin_l, then JOINTS
            if len(r) > 5:
                mg = r[:, 1]
                out["pr_n"] = float(len(r))
                out["pr_mg_mean"] = float(np.nanmean(mg))
                out["pr_mg_std"] = float(np.nanstd(mg))
                out["pr_mg_min"] = float(np.nanmin(mg))
                out["pr_mg_max"] = float(np.nanmax(mg))
                out["pr_wrapfrac"] = float(np.mean(mg > 0))
                late = r[r[:, 0] >= r[-1, 0] - 5.0]
                for k, nm in enumerate(JOINTS):
                    out[f"pr_{nm}_mean"] = float(np.mean(r[:, 3 + k]))
                    out[f"pr_{nm}_std"] = float(np.std(r[:, 3 + k]))
                    out[f"pr_{nm}_late"] = float(np.mean(late[:, 3 + k]))
                out["pr_mg_late_mean"] = float(np.nanmean(late[:, 1]))
                out["pr_mg_late_std"] = float(np.nanstd(late[:, 1]))
                out["pr_mg_late_min"] = float(np.nanmin(late[:, 1]))
                out["pr_mg_late_max"] = float(np.nanmax(late[:, 1]))
                out["pr_mg_left_mean"] = float(np.nanmean(r[:, 2]))
            return out

    return ProbeTask()


def hist_stats(h):
    """wrap_r_hist "p0,..,p8|n0,..,n8" -> exposure fractions"""
    if not h:
        return {}
    pos, neg = h.split("|")
    pos = np.array([int(x) for x in pos.split(",")])
    neg = np.array([int(x) for x in neg.split(",")])
    both = pos + neg
    n = both.sum()
    if n == 0:
        return {}
    # bins: 0 [0,1e-8) 1 [1e-8,6e-8) 2 [6e-8,1e-7) 3 [1e-7,1e-6) 4 [1e-6,1e-5) 5 [1e-5,1e-4) 6 [1e-4,1e-3) 7 [1e-3,1e-2) 8 [1e-2, inf)
    return {"e5": float(both[:5].sum() / n), "e4": float(both[:6].sum() / n), "e3": float(both[:7].sum() / n),
            "e2": float(both[:8].sum() / n), "sliver": int(pos[:2].sum()), "pos_frac": float(pos.sum() / n), "nsub": int(n)}


def run(job):
    os.environ["MYO_SOCCER_ENV"] = job.get("env", "myoChallengeSoccerP2-v0")
    os.environ["MYO_SOCCER_MAX_TIME"] = str(job.get("max_time", 310))
    os.environ["MYO_SOCCER_NANGUARD"] = job["mode"]
    for k, v in (job.get("envvars") or {}).items():
        os.environ[k] = str(v)
    if job.get("series"):
        os.environ["WSCAN_SERIES"] = os.path.join(HERE, job["series"])
    else:
        os.environ.pop("WSCAN_SERIES", None)
    from search4 import read_params
    from myo_bridge import MyoSim
    t0 = time.time()
    try:
        params = job.get("pdict") or read_params(os.path.join(HERE, job["params"]))
        params = dict(params)
        params.update({k: float(v) for k, v in (job.get("set") or {}).items()})
        sim = MyoSim(make_task(), params=params, controller=os.path.join(HERE, job["controller"]), seed=job["seed"])
        res = sim.run(job["seconds"])
    except Exception as e:
        import traceback
        return {"tag": job["tag"], "error": (str(e) + traceback.format_exc())[-400:]}
    keep = {k: v for k, v in res.items() if k in ("time", "stand_time", "bal1_raw", "bal1_300", "fallen", "t_fall", "hold20", "nan_events", "nan_nudged", "nan_other",
                                                    "nan_first_t", "nan_tendons", "wrap_r_hist", "wrap_r_substeps", "wrap_r_visits", "wrap_r_flips", "wrap_r_near3",
                                                    "wrap_r_near4", "wrap_l_hist", "wrap_l_substeps", "nan_expected", "nan_omd")
            or k.startswith("pr_") or k.startswith("seg_")}
    keep.update(hist_stats(res.get("wrap_r_hist")))
    keep.update(tag=job["tag"], seed=job["seed"], seconds=job["seconds"], wall=round(time.time() - t0, 1),
                params=job.get("params"), controller=job.get("controller"), set=job.get("set"))
    return keep


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--jobs", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--mode", default="0")
    a = ap.parse_args()
    jobs = json.load(open(a.jobs))
    done = set()
    if os.path.exists(a.out):  # resumable: skip the tags already in the output
        for line in open(a.out):
            try:
                done.add(json.loads(line)["tag"])
            except Exception:
                pass
    todo = [j for j in jobs if j["tag"] not in done]
    for j in todo:
        j["mode"] = a.mode
    print(f"{len(todo)} of {len(jobs)} jobs to run, {a.workers} workers, mode {a.mode}", flush=True)
    with mp.get_context("spawn").Pool(a.workers) as pool, open(a.out, "a") as f:
        for r in pool.imap_unordered(run, todo):
            f.write(json.dumps(r) + "\n")
            f.flush()
            if "error" in r:
                print("ERROR", r["tag"], r["error"][:300], flush=True)
            else:
                print(f"{r['tag']:>22s} stand {r.get('stand_time', 0):6.2f} bal1 {r.get('bal1_raw', 0):6.2f} fell {int(bool(r.get('fallen')))} nan {r.get('nan_events')} "
                      f"e4 {100 * r.get('e4', 0):5.2f}% e3 {100 * r.get('e3', 0):5.2f}% mg {r.get('pr_mg_late_mean', float('nan')):+.2e} wall {r['wall']}", flush=True)


if __name__ == "__main__":
    main()
