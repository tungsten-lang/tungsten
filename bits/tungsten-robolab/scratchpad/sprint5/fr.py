"""fr.py (sprint 5, agent S5): FALL-RATE measurement of a chain on perturbed standing starts of the arena task (run_v4, 30 s) on the
LABELLED BEYOND-HUMAN body (never compared with the human-body sprint trials).

  .venv/bin/python scratchpad/sprint5/fr.py PARAMS CONTROLLER SEEDS OUT [--seconds 30] [--workers 6] [--set k=v,...] [--attr k=v,...] [--tag NAME]
  .venv/bin/python scratchpad/sprint5/fr.py --summary OUT.jsonl [OUT2.jsonl ...]

SEEDS is "12001-12128" or "1,2,3" or a mix. One JSON line per seed goes to OUT (.jsonl); a summary is printed at the end.

PHASE RULE (fixed 2026-09-30 before any run). The filtered COM speed v_f (pelvis-subtree COM velocity, exponential filter tau 0.15 s) is
tracked at every control tick; t76 / t94 are the first times it reaches 7.6 / 9.4 m/s (the gear-2 and gear-3 handover speeds of chains C and D).
A rollout that ends in a fall at time t is classified:
  START     t <= t76 (or v_f never reached 7.6): gear 1, the start and the acceleration;
  HANDOVER  t76 < t <= t94 (or v_f never reached 9.4): gear 2 (the gear-1 -> gear-2 switch and the 7.6-9.4 m/s range);
  TOP       t > t94: gear 3, the top gear (the sub-count LATE = TOP or any falls at t > 25 s is reported separately).
The arena metric of a start is peak_speed_1s with a fall scored -1e9; the 'all-start mean' below scores a fall as 0 m/s.
"""
import argparse
import json
import math
import multiprocessing as mp
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
# the body of every number this tool prints: the labelled beyond-human body (set for the spawn workers too)
os.environ["ROBOLAB_CALIB"] = "v4"
os.environ["ROBOLAB_PROFILE"] = "beyond"
os.environ["ROBOLAB_PROFILE_PARTS"] = "strength,speed,tendon,activation"
sys.path.insert(0, os.path.join(ROOT, "playground"))

V_FILT_TAU = 0.15
V_HANDOVER = 7.6
V_TOP = 9.4
LATE_T = 25.0


def parse_seeds(spec):
    out = []
    for tok in spec.split(","):
        tok = tok.strip()
        if not tok:
            continue
        if "-" in tok:
            lo, hi = tok.split("-")
            out += list(range(int(lo), int(hi) + 1))
        else:
            out.append(int(tok))
    return out


class Rec:
    """Light recorder: filtered COM speed and torso pitch at every control tick; first crossings of the gear speeds."""

    def __init__(self):
        self.vf = 0.0
        self.t76 = None
        self.t94 = None
        self.vmax = 0.0
        self.tr = []  # (t, v_f, pitch) every 0.1 s
        self.next_tr = 0.0
        self.pid = None
        self.tid = None
        self.last_t = 0.0

    def maybe_capture(self, sim):
        import math as _m
        d = sim.d
        if self.pid is None:
            self.pid = sim.m.body("pelvis").id
            self.tid = sim.m.body("torso").id
        t = float(d.time)
        dt = max(t - self.last_t, 1e-6) if self.last_t else 0.004
        self.last_t = t
        v = float(d.subtree_linvel[self.pid][0])
        k = dt / (V_FILT_TAU + dt)
        self.vf += (v - self.vf) * k
        if self.vf > self.vmax:
            self.vmax = self.vf
        if self.t76 is None and self.vf >= V_HANDOVER:
            self.t76 = t
        if self.t94 is None and self.vf >= V_TOP:
            self.t94 = t
        if t >= self.next_tr:
            tu = d.xmat[self.tid].reshape(3, 3)[:, 2]
            self.tr.append((round(t, 3), round(self.vf, 3), round(_m.atan2(tu[0], tu[2]), 4)))
            self.next_tr = t + 0.1


def classify(fell, t, t76, t94):
    if not fell:
        return "none"
    if t76 is None or t <= t76:
        return "START"
    if t94 is None or t <= t94:
        return "HANDOVER"
    return "TOP"


def one(job):
    from practice import load_task
    from bridge import Sim
    params, ctl, seed, secs, attrs, task_name, envd = job
    os.environ.update(envd)  # RUN_NATURAL_START / ROBOLAB_SNAP for flying (snapshot) starts; read when the task module is first imported
    task = load_task(task_name)
    task.seed = seed
    for k, v in attrs.items():
        setattr(task, k, v)
    t0 = time.time()
    rec = Rec()
    try:
        m = Sim(task, params=dict(params), controller=ctl).run(secs, recorder=rec)
    except Exception as e:  # a crashing rollout is reported, not hidden
        return {"seed": seed, "error": str(e)[:300]}
    fell = bool(m.get("fell"))
    t = float(m.get("time") or 0.0)
    row = {"seed": seed, "fell": fell, "time": t, "peak": m.get("peak_speed_1s"), "steady": m.get("steady_speed"),
           "t76": None if rec.t76 is None else round(rec.t76, 3), "t94": None if rec.t94 is None else round(rec.t94, 3),
           "vmax": round(rec.vmax, 3), "phase": classify(fell, t, rec.t76, rec.t94), "wall": round(time.time() - t0, 1)}
    row["_tr"] = rec.tr
    return row


def wilson(k, n, z=1.96):
    if n == 0:
        return (0.0, 0.0)
    p = k / n
    den = 1 + z * z / n
    c = (p + z * z / (2 * n)) / den
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / den
    return (max(0.0, c - h), min(1.0, c + h))


def summarize(rows, label=""):
    ok = [r for r in rows if "error" not in r]
    err = [r for r in rows if "error" in r]
    n = len(ok)
    falls = [r for r in ok if r["fell"]]
    surv = [r for r in ok if not r["fell"] and r.get("peak")]
    lo, hi = wilson(len(falls), n)
    by = {p: [r for r in falls if r["phase"] == p] for p in ("START", "HANDOVER", "TOP")}
    late = [r for r in falls if r["time"] > LATE_T]
    mean_surv = sum(r["peak"] for r in surv) / len(surv) if surv else float("nan")
    mean_all = sum((r["peak"] if not r["fell"] else 0.0) for r in ok) / n if n else float("nan")
    out = []
    out.append(f"{label} n={n} falls={len(falls)} ({100.0 * len(falls) / max(n, 1):.1f} %, Wilson95 {100 * lo:.1f}-{100 * hi:.1f} %)"
               f"  START={len(by['START'])} HANDOVER={len(by['HANDOVER'])} TOP={len(by['TOP'])} (late t>{LATE_T:.0f}s: {len(late)})"
               + (f"  ERRORS={len(err)}" if err else ""))
    if surv:
        pk = [r["peak"] for r in surv]
        out.append(f"  survivors' mean peak {mean_surv:.3f} m/s (min {min(pk):.3f}, max {max(pk):.3f}); mean over ALL starts, falls as 0: {mean_all:.3f} m/s")
    for p in ("START", "HANDOVER", "TOP"):
        if by[p]:
            out.append("  " + p + ": " + ", ".join(f"{r['seed']}@{r['time']:.1f}s" for r in sorted(by[p], key=lambda r: r["time"])))
    return "\n".join(out)


def read_rows(path):
    rows = []
    for line in open(path):
        line = line.strip()
        if line:
            rows.append(json.loads(line))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("params", nargs="?")
    ap.add_argument("controller", nargs="?")
    ap.add_argument("seeds", nargs="?")
    ap.add_argument("out", nargs="?")
    ap.add_argument("--seconds", type=float, default=30.0)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--set", default="")
    ap.add_argument("--attr", default="")
    ap.add_argument("--task", default="run_v4")
    ap.add_argument("--start", default="", help="flying: a snapshot start (task sprint_touch_v4x, --attr fly_touch=2, --snap NAME)")
    ap.add_argument("--snap", default="", help="ROBOLAB_SNAP, e.g. run_v4_s5s (playground/cache/sprint_touch_<snap>.npz)")
    ap.add_argument("--tag", default="")
    ap.add_argument("--summary", nargs="+")
    a = ap.parse_args()
    if a.summary:
        for p in a.summary:
            print(summarize(read_rows(p), os.path.basename(p)))
        return
    from practice import read_params
    params = read_params(a.params) if a.params != "-" else {}
    for kv in a.set.split(","):
        if kv:
            k, v = kv.split("=")
            params[k] = float(v)
    attrs = {kv.split("=")[0]: float(kv.split("=")[1]) for kv in a.attr.split(",") if kv}
    seeds = parse_seeds(a.seeds)
    ctl = os.path.abspath(a.controller)
    envd = {}
    if a.start:
        envd["RUN_NATURAL_START"] = a.start
    if a.snap:
        envd["ROBOLAB_SNAP"] = a.snap
    jobs = [(params, ctl, s, a.seconds, attrs, a.task, envd) for s in seeds]
    t0 = time.time()
    rows = []
    trs = {}
    with mp.get_context("spawn").Pool(a.workers) as pool, open(a.out, "w") as f:
        for r in pool.imap_unordered(one, jobs, chunksize=1):
            tr = r.pop("_tr", None)
            if tr is not None:
                trs[r["seed"]] = tr
            rows.append(r)
            f.write(json.dumps(r) + "\n")
            f.flush()
    rows.sort(key=lambda r: r["seed"])
    with open(a.out + ".trace.json", "w") as f:
        json.dump({str(k): v for k, v in trs.items()}, f)
    print(summarize(rows, (a.tag or os.path.basename(a.out)) + f" [{len(seeds)} seeds, {a.seconds:.0f} s, {time.time() - t0:.0f} s wall]"), flush=True)


if __name__ == "__main__":
    main()
