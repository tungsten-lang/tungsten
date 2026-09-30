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
        self.near_idx = np.array([], dtype=int)
        self.hsub = [[np.zeros(len(EDGES) - 1, dtype=np.int64), np.zeros(len(EDGES) - 1, dtype=np.int64)] for _ in range(n)]   # substep |margin| histograms (pos, neg) per segment
        self.sliver = np.zeros(n, dtype=np.int64)                                                                                # substep states with 0 < margin < 1e-7 per segment
        self.prev = np.full(n, np.nan)          # last control step's margin (crossing speed)
        self.xnan = np.zeros(n)                 # expected NaN events from the tangent crossings (see step)
        self.cross_dmin = np.full(n, 9.0)       # smallest margin change across one control step at a crossing (the slowest crossing)
        self.near2 = np.zeros(n)
        self.sum1 = np.zeros(n)
        self.sum2 = np.zeros(n)
        self.minabs = np.full(n, 9.0)

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
        self.near2 += ok & (np.abs(mg) < 1e-2)
        z = np.where(ok, mg, 0.0)
        self.sum1 += z
        self.sum2 += z * z
        self.minabs = np.where(ok, np.minimum(self.minabs, np.abs(z)), self.minabs)
        pos = np.where(ok, (mg > 0).astype(int), -1)
        self.flips += ok & (self.last >= 0) & (pos != self.last)
        self.last = np.where(ok, pos, self.last)
        # crossings: the margin changes by delta over the control step's 10 substeps, so a substep lands in the NaN sliver (0 < margin < 6e-8) with
        # probability ~ 6e-8 / (delta / 10) and each such state is a NaN with probability ~0.1 (K's closure: 0.07-0.10): expected NaN events per crossing
        both = ok & np.isfinite(self.prev)
        cross = both & ((mg > 0) != (self.prev > 0))
        if cross.any():
            delta = np.abs(z) + np.abs(np.where(np.isfinite(self.prev), self.prev, 0.0))
            self.xnan += np.where(cross, np.minimum(0.5, 0.1 * 6e-7 / np.maximum(delta, 1e-30)), 0.0)
            self.cross_dmin = np.where(cross, np.minimum(self.cross_dmin, delta), self.cross_dmin)
        self.prev = np.where(ok, mg, np.nan)
        # segments that could reach the NaN sliver within the next control step's 10 substeps (|margin| < 0.1 now): the substep watch evaluates only those
        self.near_idx = np.flatnonzero(ok & (np.abs(z) < 0.1))

    def sub(self, d):
        """substep resolution, only for the segments near a tangent at the last control step: histogram of |margin| (positive | negative, EDGES bins) and sliver states"""
        if self.near_idx.size == 0:
            return
        mg = self.margins(d)
        for i in self.near_idx:
            m = mg[i]
            if not np.isfinite(m):
                continue
            b = min(max(int(np.searchsorted(EDGES, abs(m), side="right")) - 1, 0), len(EDGES) - 2)
            self.hsub[i][0 if m > 0 else 1][b] += 1
            if 0 < m < 1e-7:
                self.sliver[i] += 1

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
        nn = np.maximum(self.n, 1)
        mean = self.sum1 / nn
        sd = np.sqrt(np.maximum(self.sum2 / nn - mean ** 2, 0.0))
        fmt = lambda a: ",".join(f"{x:.5g}" for x in a)
        out["segv_mean"] = fmt(mean)                      # per segment (order: seg_names.json): mean margin over the watched control steps
        out["segv_sd"] = fmt(sd)
        out["segv_min"] = fmt(np.where(self.n > 0, self.minabs, np.nan))   # smallest |margin| seen
        out["segv_near2"] = fmt(self.near2 / nn)           # fraction of steps within 1e-2 of the tangent
        out["segv_near3"] = fmt(frac3)
        out["segv_flips"] = fmt(self.flips)
        w1 = np.array([h[0][:6].sum() + h[1][:6].sum() for h in self.hsub])   # substeps within 1e-4 of the tangent, per segment (only counted while near)
        w3 = np.array([h[0][:7].sum() + h[1][:7].sum() for h in self.hsub])
        out["subv_e4"] = fmt(w1)                     # per segment, substeps within 1e-4 / 1e-3 (segments outside |m| < 0.1 at the control step are not evaluated)
        out["subv_e3"] = fmt(w3)
        out["subv_sliver"] = fmt(self.sliver)         # per segment, substeps with 0 < margin < 1e-7
        out["sub_sliver_oth"] = int(self.sliver[oth].sum())    # all non-recfem_r segments together (trunk, left leg, the swing leg's other muscles)
        out["sub_sliver_rf"] = int(self.sliver[rf].sum()) if rf else 0
        out["sub_e4_oth"] = int(w1[oth].sum())
        out["sub_e3_oth"] = int(w3[oth].sum())
        out["seg_xnan"] = float(self.xnan.sum())                    # expected NaN events of the run from all crossings (0.1 x P(a substep lands in the sliver))
        out["seg_xnan_rf"] = float(self.xnan[rf].sum()) if rf else 0.0
        out["seg_xnan_oth"] = float(self.xnan[oth].sum())
        out["seg_xnan_name"] = self.names[int(np.argmax(self.xnan))] if self.xnan.max() > 0 else ""
        out["seg_cross_dmin"] = float(self.cross_dmin.min())          # the slowest crossing (margin change per control step)
        out["seg_flips_rf"] = float(self.flips[rf].sum()) if rf else 0.0
        out["seg_flips_oth"] = float(self.flips[oth].sum())
        return out


def make_task():
    from tasks.myo_soccer_ng import NanGuardSoccerTask
    import tasks.myo_soccer_ng as ng

    class ProbeTask(NanGuardSoccerTask):
        def episode(self, sim):
            first = getattr(self, "_sim", None) is not sim
            super().episode(sim)
            if first:
                self.rows = []
                self.allsegs = AllSegs(sim.u.robot.mj_model)
                m = sim.u.robot.mj_model
                import mujoco
                L, R = set(), set()
                for b in range(m.nbody):
                    nm = m.body(b).name
                    if nm.endswith("_l"):
                        L.add(b)
                    elif nm.endswith("_r"):
                        R.add(b)
                self.LR = (L, R)
                self.legf = []
                allsegs = self.allsegs
                guard = self.guard

                def probe_advance(model, data, n_frames=1, render=None):
                    """NanGuard.advance (task file, unchanged semantics) plus a read-only hook: the substep watch of the segments near a tangent"""
                    import mujoco as _mj
                    watch = guard.watch
                    for _ in range(n_frames):
                        _mj.mj_getState(model, data, guard.snap, ng.SPEC)
                        t0 = float(data.time)
                        _mj.mj_step(model, data)
                        if float(data.time) < t0:
                            guard.after_reset(model, data, t0)
                        elif t0 >= 3.0:
                            if watch is not None:
                                watch.sub(data)
                            allsegs.sub(data)

                sim.u.robot._advance = probe_advance
                self.adr = [int(m.jnt_qposadr[m.joint(n).id]) for n in JOINTS]
                self.push = None   # WSCAN_PUSH="t0:dur:fx:fy:body" (s, s, N, N, body name): a STRESS TEST only, off by default (never the official environment)
                if os.environ.get("WSCAN_PUSH"):
                    a = os.environ["WSCAN_PUSH"].split(":")
                    self.push = (float(a[0]), float(a[1]), float(a[2]), float(a[3]), int(m.body(a[4] if len(a) > 4 else "torso").id))

        def on_step(self, sim, obs, reward, info):
            super().on_step(sim, obs, reward, info)
            t = float(sim.d.time)
            if getattr(self, "push", None) is not None:
                t0, dur, fx, fy, bid = self.push
                xf = sim.u.robot.mj_data.xfrc_applied
                xf[bid, :] = 0.0
                if t0 <= t < t0 + dur:
                    xf[bid, 0], xf[bid, 1] = fx, fy
            if t >= float(os.environ.get("WSCAN_TFROM", "3.0")):   # all-segment watch: any window start, also before 3 s (the lift)
                self.allsegs.step(sim.u.robot.mj_data)
            if 0.3 <= t < 3.0 and os.environ.get("WSCAN_SERIES"):   # the set / shift / lift transient of the swing knee and recfem_r's margin, for the series file
                dd = sim.u.robot.mj_data
                mg0 = self.watch.margin_end(dd, self.watch.segs[0])[0]
                self.early = getattr(self, "early", [])
                self.early.append([t, np.nan if mg0 is None else mg0, float(dd.qpos[self.adr[3]])])
            if t >= 3.0:
                d = sim.u.robot.mj_data
                if len(self.rows) % 5 == 0:   # inter-leg contact force every 5th control step
                    import mujoco
                    m = sim.u.robot.mj_model
                    L, R = self.LR
                    f6 = np.zeros(6)
                    tot = 0.0
                    for i in range(d.ncon):
                        c = d.contact[i]
                        b1, b2 = m.geom_bodyid[c.geom1], m.geom_bodyid[c.geom2]
                        if (b1 in L and b2 in R) or (b1 in R and b2 in L):
                            mujoco.mj_contactForce(m, d, i, f6)
                            tot += abs(f6[0])
                    self.legf.append(tot)
                mgs = []
                for seg in self.watch.segs:
                    mg, _, _ = self.watch.margin_end(d, seg)
                    mgs.append(np.nan if mg is None else mg)
                self.rows.append([t] + mgs + [float(d.qpos[a]) for a in self.adr])

        def metrics(self, sim, log):
            out = super().metrics(sim, log)
            if getattr(self, "allsegs", None) is not None:
                out.update(self.allsegs.summary())
            if getattr(self, "legf", None):
                out["pr_legf_mean"] = float(np.mean(self.legf))
                out["pr_legf_late"] = float(np.mean(self.legf[-max(1, len(self.legf) // 3):]))
            r = np.array(self.rows) if getattr(self, "rows", None) else np.zeros((0, 3 + len(JOINTS)))
            sp = os.environ.get("WSCAN_SERIES")
            if sp and len(r):
                os.makedirs(os.path.dirname(sp) or ".", exist_ok=True)
                np.save(sp, r)   # columns: t, margin_r, margin_l, then JOINTS
                if getattr(self, "early", None):
                    np.save(sp.replace(".npy", "_early.npy"), np.array(self.early))   # t in [0.3, 3): t, margin_r, knee_angle_r
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
            or k.startswith("pr_") or k.startswith("seg_") or k.startswith("segv_") or k.startswith("subv_") or k.startswith("sub_")}
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
