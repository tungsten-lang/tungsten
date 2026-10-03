"""One-pass gait probe of a runner on the arena starts: speed, falls, swing-leg fold, heel height, cadence, swing time.

    ROBOLAB_BODY=v4 ROBOLAB_CALIB=<v4|v5> ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation \
      .venv/bin/python scratchpad/anat5/gait_probe.py PARAMS CONTROLLER SEEDS SECONDS [--task run_v4] [--t0 14] [--out NAME.json] [--npz PREFIX]

SEEDS is a comma list or a range `221-232`. Per seed it prints one line and, at the end, the aggregate (means over the seeds that did not
fall, the measurement window starting at --t0 s: the steady tail, default 14 s of a 30 s run). Definitions (both legs pooled, every
swing in the window):
  swing        toe-off (foot load < 0.05 body weights) to the same foot's next touchdown (> 0.05 BW)
  peak fold    max knee flexion in the swing, deg (knee > 0 = flexion); `t_pk` s after toe-off
  gain100      knee flexion gained in the first 0.1 s after toe-off, deg
  heel_z       max heel height in the swing (world z of the heel site), m; `heel_hip` = distance heel-to-hip-centre at the peak fold
  cadence      touchdowns of both feet per second (steps/s), `swing_t` mean swing time, `contact_t` mean contact time
  speed        (x(t_end) - x(t0)) / (t_end - t0) over the window; peak_speed_1s is the arena metric of the whole run
"""
import argparse, importlib, json, os, sys, time
sys.path.insert(0, "playground")
import numpy as np
import mujoco
from bridge import Sim
from search import read_params


def parse_seeds(s):
    out = []
    for part in s.split(","):
        if "-" in part:
            a, b = part.split("-")
            out += list(range(int(a), int(b) + 1))
        else:
            out.append(int(part))
    return out


class Rec:
    def __init__(self, sim):
        m = sim.m
        J = lambda n: mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_JOINT, n)
        self.S = lambda n: mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_SITE, n)
        self.B = lambda n: mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_BODY, n)
        self.qa = {n: m.jnt_qposadr[J(n)] for n in ("root_x", "root_z", "l_knee", "r_knee", "l_hip_flex", "r_hip_flex")}
        self.rows = []

    def maybe_capture(self, s):
        d = s.d
        ct = s.contacts()
        pel = d.xpos[self.B("pelvis")]
        row = [d.time, d.qpos[self.qa["root_x"]], pel[2], d.qpos[self.qa["l_knee"]], d.qpos[self.qa["r_knee"]],
               d.qpos[self.qa["l_hip_flex"]], d.qpos[self.qa["r_hip_flex"]], ct["l_foot"], ct["r_foot"]]
        for side in ("l", "r"):
            h = d.site_xpos[self.S(f"{side}_heel")]
            hip = d.xpos[self.B(f"{side}_thigh")]
            row += [h[2], float(np.hypot(h[0] - hip[0], h[2] - hip[2]))]
        self.rows.append(row)


COLS = ["t", "x", "pelvis_z", "knee_l", "knee_r", "hip_l", "hip_r", "load_l", "load_r", "heel_l_z", "heel_l_hip", "heel_r_z", "heel_r_hip"]


def debounce(load, n):
    """Merge contact flicker: an unloaded gap shorter than n ticks counts as loaded, then a loaded run shorter than n ticks as unloaded."""
    load = load.copy()
    for val in (False, True):
        i = 0
        while i < len(load):
            if load[i] == val:
                j = i
                while j < len(load) and load[j] == val:
                    j += 1
                if j - i < n and i > 0 and j < len(load):
                    load[i:j] = not val
                i = j
            else:
                i += 1
    return load


def summarize(A, t0):
    col = lambda n: A[:, COLS.index(n)]
    t = col("t")
    sel = t >= t0
    if sel.sum() < 50:
        return None
    dt = float(np.median(np.diff(t)))
    tw = t[sel]
    speed = float((col("x")[sel][-1] - col("x")[sel][0]) / (tw[-1] - tw[0]))
    swings, contacts, tds = [], [], []
    for side, kc, hc, lc, zc, dc in (("l", "knee_l", "hip_l", "load_l", "heel_l_z", "heel_l_hip"), ("r", "knee_r", "hip_r", "load_r", "heel_r_z", "heel_r_hip")):
        k, load, hz, hd, hip = col(kc), debounce(col(lc) > 0.05, int(round(0.03 / dt))), col(zc), col(dc), col(hc)
        toe, td = [], []
        for i in range(1, len(t)):
            if load[i - 1] and not load[i]:
                toe.append(i)
            if (not load[i - 1]) and load[i]:
                td.append(i)
        for i in toe:
            if t[i] < t0:
                continue
            nxt = [j for j in td if j > i]
            if not nxt:
                continue
            j = nxt[0]
            if t[j] - t[i] > 0.6:  # a fall / a stumble, not a swing
                continue
            seg = k[i:j + 1]
            ip = int(np.argmax(seg))
            i100 = min(i + int(round(0.1 / dt)), j)
            swings.append(dict(side=side, fold=float(np.degrees(seg.max())), t_pk=float(ip * dt), gain100=float(np.degrees(k[i100] - k[i])),
                               heel_z=float(hz[i:j + 1].max()), heel_zpk=float(hz[i + ip]), heel_hip=float(hd[i + ip]), swing_t=float(t[j] - t[i]),
                               hip_pk=float(np.degrees(hip[i:j + 1].max()))))
            prev = [q for q in td if q < i]
            if prev:
                contacts.append(float(t[i] - t[prev[-1]]))
        tds += [j for j in td if t[j] >= t0]
    n_td = len(tds)
    out = dict(speed=speed, cadence=n_td / (tw[-1] - tw[0]), n_swings=len(swings))
    if swings:
        for key in ("fold", "t_pk", "gain100", "heel_z", "heel_zpk", "heel_hip", "swing_t", "hip_pk"):
            out[key] = float(np.mean([s[key] for s in swings]))
        out["fold_max"] = float(np.max([s["fold"] for s in swings]))
        out["fold_min"] = float(np.min([s["fold"] for s in swings]))
    if contacts:
        out["contact_t"] = float(np.mean(contacts))
    out["pelvis_z"] = float(col("pelvis_z")[sel].mean())
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("params")
    ap.add_argument("controller")
    ap.add_argument("seeds")
    ap.add_argument("seconds", type=float)
    ap.add_argument("--task", default="run_v4")
    ap.add_argument("--t0", type=float, default=14.0)
    ap.add_argument("--out", default=None)
    ap.add_argument("--npz", default=None)
    ap.add_argument("--attrs", default="", help="task attributes k=v,... (a flying start: objective=3,fly_touch=2,fall_pen=300 with RUN_NATURAL_START=flying and ROBOLAB_SNAP=<set> in the env)")
    args = ap.parse_args()
    attrs = {kv.split("=")[0]: float(kv.split("=")[1]) for kv in args.attrs.split(",") if kv}
    params = read_params(args.params)
    rows = []
    for seed in parse_seeds(args.seeds):
        task = importlib.import_module(f"tasks.{args.task}").TASK()
        task.seed = seed
        for k_, v_ in attrs.items():
            setattr(task, k_, v_)
        w0 = time.time()
        sim = Sim(task, params=params, controller=args.controller)
        rec = Rec(sim)
        res = sim.run(args.seconds, recorder=rec)
        A = np.array(rec.rows)
        if args.npz:
            np.savez(f"{args.npz}_{seed}.npz", arr=A, names=np.array(COLS))
        fell = bool(res.get("fell"))
        st = summarize(A, args.t0) or {}
        tm = {("task_" + k): float(v) for k, v in res.items() if isinstance(v, (int, float, np.floating)) and not isinstance(v, bool)}
        row = dict(seed=seed, fell=fell, t_end=float(A[-1, 0]), peak_speed_1s=float(res.get("peak_speed_1s", 0.0)), wall=round(time.time() - w0, 1), **st, **tm)
        rows.append(row)
        f = lambda k, p=2: (f"{row[k]:.{p}f}" if k in row else "-")
        print(f"seed {seed}: {'FELL at %.1f s' % row['t_end'] if fell else 'ok'} peak1s {row['peak_speed_1s']:.3f} steady {f('speed')} cadence {f('cadence')} "
              f"fold {f('fold', 0)} (min {f('fold_min', 0)} max {f('fold_max', 0)}) gain100 {f('gain100', 0)} t_pk {f('t_pk', 3)} heel_z {f('heel_z')} heel_zpk {f('heel_zpk')} heel_hip {f('heel_hip')} "
              f"swing_t {f('swing_t', 3)} contact_t {f('contact_t', 3)} hip_pk {f('hip_pk', 0)} wall {row['wall']}s", flush=True)
    ok = [r for r in rows if not r["fell"]]
    agg = dict(n=len(rows), falls=len(rows) - len(ok))
    if ok:
        for k in ("peak_speed_1s", "speed", "cadence", "fold", "fold_max", "fold_min", "gain100", "t_pk", "heel_z", "heel_zpk", "heel_hip", "swing_t", "contact_t", "hip_pk", "task_step_freq", "task_steady_speed", "task_contact_time", "task_flight_time", "task_step_length", "task_peak_grf"):
            v = [r[k] for r in ok if k in r]
            if v:
                agg[k] = float(np.mean(v))
    print("AGG", json.dumps({k: (round(v, 4) if isinstance(v, float) else v) for k, v in agg.items()}), flush=True)
    if args.out:
        json.dump(dict(args=vars(args), env={k: v for k, v in os.environ.items() if k.startswith("ROBOLAB_")}, rows=rows, agg=agg), open(args.out, "w"), indent=1)


if __name__ == "__main__":
    main()
