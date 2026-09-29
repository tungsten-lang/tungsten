"""kfdrop: does set 3 have one push-off keyframe too many? (Erik's question)

Erik's keyframe set 3 (playground/arena/params/keyframes_erik3-20260927-162054.txt)
has two push-off keyframes 6 % of the stride apart: HR (heel rise, 30 %) and TO
(toe-off, 36 %). They differ mainly in the stance ankle (-1.3 vs +25 deg
plantarflexion) and toe (-19 vs -30). The ablation drops one of them from what
the controller aims at and scores every variant against the FULL set (the arena
trials `run_natural_erik3` / `run_natural_erik3_48` stay fixed).

    kfdrop.py make                       # the reduced keyframe files and the rn2 starts
    kfdrop.py eval --label L --params p.txt --controller bin/x --seeds 7301-7348 --out out.jsonl

Reduced keyframe files (out/runknots/kfdrop/):
  keyframes_erik3_nohr.txt   the full set without HR (td ms to kl)
  keyframes_erik3_noto.txt   the full set without TO (td ms hr kl; `ref_to_phase -1`
                             removes the event from the Reference, whose curve then
                             runs from HR straight to KL)

The rn2 keyframe-chunk runner (RunNaturalSkill with ordered keyframes; the set-3
runner out/run_natural/r2/s3c.txt, td/ms/hr/to, KL already dropped from its
targets) takes the drops as params (no skill change):
  rn2_nohr_init.txt   s3c without its ref_hr_* targets and d_hr_* offsets: the
                      3-chunk stride td -> ms -> to (the drive chunk ends at the
                      foot's release, as before)
  rn2_noto_init.txt   s3c whose TO targets are HR's (and d_to_* its d_hr_*
                      offsets), without the hr chunk: in RunNaturalSkill the
                      chunk ending at toe-off (the release latch) always exists,
                      so dropping the TO keyframe makes it aim at the HR posture

`eval` reports per variant: falls (and guard failures), speed, kin_rms against
the full set (the arena metric), against each reduced set and against the
literature curves, and the per-event error at TD, MS, HR, TO and KL against the
full set (RMS over the joints event_rms counts; both steps).
"""

import argparse
import json
import multiprocessing as mp
import os
import sys

for _v in ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
    os.environ.setdefault(_v, "1")

import numpy as np  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

FULL = os.path.join(HERE, "arena", "params", "keyframes_erik3-20260927-162054.txt")
OUT = os.path.join(ROOT, "out", "runknots", "kfdrop")
S3C = os.path.join(ROOT, "out", "run_natural", "r2", "s3c.txt")
REDUCED = {"nohr": os.path.join(OUT, "keyframes_erik3_nohr.txt"), "noto": os.path.join(OUT, "keyframes_erik3_noto.txt")}
EVENT_SKIP = ("toe",)


def read_lines(path):
    return [ln for ln in open(path)]


def cmd_make(args):
    os.makedirs(OUT, exist_ok=True)
    full = read_lines(FULL)
    with open(REDUCED["nohr"], "w") as f:
        f.write("# Erik's set 3 without the HR (heel rise) keyframe: td ms to kl (kfdrop.py)\n")
        f.writelines(ln for ln in full if not ln.startswith("ref_hr_"))
    with open(REDUCED["noto"], "w") as f:
        f.write("# Erik's set 3 without the TO (toe-off) keyframe: td ms hr kl; ref_to_phase -1 removes the event (kfdrop.py)\n")
        f.writelines(ln for ln in full if not ln.startswith("ref_to_"))
        f.write("ref_to_phase -1.0\n")
    s3c = read_lines(S3C)
    vals = {}
    for ln in s3c:
        t = ln.split()
        if len(t) >= 2 and not ln.startswith("#"):
            vals[t[0]] = t[1]
    head = [f"# kfdrop: from {os.path.relpath(S3C, ROOT)}\n"]
    with open(os.path.join(OUT, "rn2_nohr_init.txt"), "w") as f:
        f.writelines(head + ["# HR dropped: no ref_hr_* targets, no d_hr_* offsets (3-chunk stride td/ms/to)\n"])
        f.writelines(ln for ln in s3c if not ln.startswith("#") and not ln.startswith("ref_hr_") and not ln.startswith("d_hr_"))
    with open(os.path.join(OUT, "rn2_noto_init.txt"), "w") as f:
        f.writelines(head + ["# TO dropped: the chunk ending at toe-off aims at HR's posture (ref_to_* = ref_hr_*, d_to_* = d_hr_*)\n"])
        for ln in s3c:
            if ln.startswith("#") or ln.startswith("ref_hr_") or ln.startswith("d_hr_"):
                continue
            k = ln.split()[0] if ln.split() else ""
            if k.startswith("ref_to_") and k != "ref_to_phase":
                f.write(f"{k} {vals['ref_hr_' + k[7:]]}\n")
            elif k.startswith("d_to_"):
                f.write(f"{k} {vals['d_hr_' + k[5:]]}\n")
            else:
                f.write(ln)
    for p in list(REDUCED.values()) + [os.path.join(OUT, n) for n in ("rn2_nohr_init.txt", "rn2_noto_init.txt")]:
        print("wrote", os.path.relpath(p, ROOT))


def event_errors(kfs, event):
    """RMS error (deg) at one event over both steps and the joints event_rms counts."""
    errs = []
    for side in ("R", "L"):
        for role, (ref, ach) in kfs.get(f"{side}_{event}", {}).items():
            if role.endswith("toe") or role in ("pelvis", "spine_flex"):
                continue
            errs.append(ach - ref)
    return float(np.sqrt(np.mean(np.square(errs)))) if errs else None


def role_error(kfs, event, role):
    v = [abs(r[1] - r[0]) for s in ("R", "L") for k, r in kfs.get(f"{s}_{event}", {}).items() if k == role]
    return float(np.mean(v)) if v else None


def _job(job):
    params, controller, seed, seconds = job
    os.environ["ROBOLAB_RN_KEYFRAMES"] = FULL
    from bridge import Sim
    from tasks.run_natural import Reference, naturalness, read_keyframes
    from tasks.run_natural_erik import RunNaturalErikTask
    task = RunNaturalErikTask()
    task.seed = seed
    sim = Sim(task, params=params, controller=controller)
    m = sim.run(seconds)
    out = {"seed": seed, "fell": bool(m.get("fell")), "time": m.get("time"), "speed": m.get("speed"),
           "in_band": m.get("in_band"), "kin_rms": m.get("kin_rms"), "event_rms": m.get("event_rms")}
    for g in ("hip", "knee", "ankle", "trunk", "shoulder", "elbow"):
        out["kin_" + g] = m.get("kin_" + g)
    kfs = m.get("keyframes") or {}
    for ev in ("TD", "MS", "HR", "TO", "KL"):
        out[f"err_{ev}"] = event_errors(kfs, ev)
    for ev in ("HR", "TO"):
        out[f"st_ankle_{ev}"] = role_error(kfs, ev, "st_ankle")
    lit = naturalness(task.jrec, Reference(3.5), task.tail_s)
    out["kin_rms_lit"] = lit.get("kin_rms")
    for name, path in REDUCED.items():
        red = naturalness(task.jrec, Reference(task.ref_speed, read_keyframes(path)), task.tail_s)
        out[f"kin_rms_{name}"] = red.get("kin_rms")
        rk = red.get("keyframes") or {}
        for ev in ("HR", "TO"):
            out[f"err_{ev}_{name}"] = event_errors(rk, ev)
    return out


def summarise(rows):
    ok = [r for r in rows if not r["fell"] and r.get("in_band")]
    up = [r for r in rows if not r["fell"]]
    s = {"n": len(rows), "falls": sum(r["fell"] for r in rows), "fails": len(rows) - len(ok)}
    for k in ("speed", "kin_rms", "kin_rms_lit", "kin_rms_nohr", "kin_rms_noto", "event_rms", "err_TD", "err_MS",
              "err_KL", "err_HR", "err_TO", "st_ankle_HR",
              "st_ankle_TO", "err_HR_nohr", "err_TO_nohr", "err_HR_noto", "err_TO_noto", "kin_hip", "kin_knee",
              "kin_ankle", "kin_trunk", "kin_shoulder"):
        v = [r[k] for r in up if isinstance(r.get(k), (int, float))]
        s[k] = round(float(np.mean(v)), 3) if v else None
    return s


def parse_seeds(s):
    out = []
    for part in s.split(","):
        if "-" in part:
            a, b = part.split("-")
            out += list(range(int(a), int(b) + 1))
        else:
            out.append(int(part))
    return out


def cmd_eval(args):
    from practice import read_params
    params = read_params(args.params)
    ctl = os.path.abspath(args.controller)
    seeds = parse_seeds(args.seeds)
    with mp.get_context("spawn").Pool(args.workers) as pool:
        rows = pool.map(_job, [(params, ctl, s, args.seconds) for s in seeds], chunksize=1)
    s = summarise(rows)
    rec = {"label": args.label, "params": os.path.relpath(os.path.abspath(args.params), ROOT),
           "controller": os.path.relpath(ctl, ROOT), "seeds": args.seeds, "summary": s, "rows": rows}
    if args.out:
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        with open(args.out, "a") as f:
            f.write(json.dumps(rec) + "\n")
    print(args.label, json.dumps(s), flush=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("make")
    e = sub.add_parser("eval")
    e.add_argument("--label", required=True)
    e.add_argument("--params", required=True)
    e.add_argument("--controller", required=True)
    e.add_argument("--seeds", default="7301-7348")
    e.add_argument("--seconds", type=float, default=30.0)
    e.add_argument("--workers", type=int, default=3)
    e.add_argument("--out")
    a = ap.parse_args()
    {"make": cmd_make, "eval": cmd_eval}[a.cmd](a)


if __name__ == "__main__":
    main()
