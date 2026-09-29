"""Per-tick trace of the batter's commanded and measured contraction speed
from the front-foot plant through contact (the load -> swing handoff).

    BAT_BODY=athlete .venv/bin/python playground/bat_trace.py --params params/bat.txt [--pitch 0] [--json out.json]

For each tick between the plant and contact (+ `--after` s of follow) it
reports, per muscle group (arms: shoulders, elbows, wrists; trunk: spine and
pelvis yaw), the speed of the commanded contraction vector (the controller's
targets, corrections included) and of the measured one: the L2 norm over the
group's muscles of d(c)/dt, in 1/s. Summary numbers:

  hold_ms      the longest run of ticks whose command speed stays below
               `--still` (1/s): a hold in the motion
  max_dv       the largest tick-to-tick change of the command velocity vector
               (L2 norm, 1/s) from the plant to contact + `--after` (max_dv_to_contact:
               to contact): a velocity jump at a chunk boundary shows up here
  gap_ms       plant -> swing (hips fire), plant -> contact
"""

import json
import os
import sys

import numpy as np

_PLAYGROUND = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _PLAYGROUND)
sys.path.insert(0, os.path.join(_PLAYGROUND, "tasks"))

from bridge import Sim  # noqa: E402
import bat as battask  # noqa: E402

ARMS = ("l_shoulder", "r_shoulder", "l_elbow", "r_elbow", "l_wrist", "r_wrist")
TRUNK = ("spine", "pelvis_yaw")


def load_params(path):
    prm = {}
    if path:
        for line in open(path):
            parts = line.split()
            if len(parts) >= 2 and not line.startswith("#"):
                prm[parts[0]] = float(parts[1])
    return prm


def longest_run(mask, dt):
    best = cur = 0
    for m in mask:
        cur = cur + 1 if m else 0
        best = max(best, cur)
    return round(1000 * best * dt, 1)


def run(params, pitches, controller=None):
    task = battask.BatTask()
    task.pitches = pitches
    sim = Sim(task, params=params, controller=controller)
    res = sim.run(3.2 + 4.2 * len(pitches) + 0.4)
    return sim, res


def analyse(sim, res, after=0.08, still=0.1, rows=False):
    """Per pitch: the window from the plant (or, without a stride, the swing)
    to contact (+ `after` s), and the command/measured speed statistics."""
    names = [mu.name for mu in sim.muscles]
    groups = {"arms": [i for i, n in enumerate(names) if n.startswith(ARMS)],
              "trunk": [i for i, n in enumerate(names) if n.startswith(TRUNK)]}
    t = np.array([e[0] for e in sim.log])
    labels = [e[1] for e in sim.log]
    c = np.array([e[3] for e in sim.log])
    tg = np.array([e[4] for e in sim.log])
    dt = float(np.median(np.diff(t)))
    out = []
    for p in res["pitches"]:
        t0 = p.get("t_plant") or p.get("t_swing")
        tc = p.get("t_contact", p.get("t_closest"))
        if t0 is None or tc is None:
            continue
        k0 = int(np.searchsorted(t, t0))
        kc = int(np.searchsorted(t, tc))
        k1 = int(np.searchsorted(t, tc + after))
        r = {"pitch": p["pitch"], "speed_mph": p.get("speed_mph"), "hit": p["hit"], "fair": p.get("fair"),
             "t_plant": p.get("t_plant"), "t_swing": p.get("t_swing"), "t_contact": tc,
             "plant_to_swing_ms": round(1000 * (p["t_swing"] - p["t_plant"]), 0)
             if p.get("t_swing") and p.get("t_plant") else None,
             "plant_to_contact_ms": round(1000 * (tc - p["t_plant"]), 0) if p.get("t_plant") else None,
             "bat_speed": p.get("bat_speed"), "exit_speed": p.get("exit_speed"), "launch_deg": p.get("launch_deg"),
             "attack_deg": p.get("attack_deg"), "groups": {}}
        ticks = [{"t": round(float(t[k]), 3), "label": labels[k]} for k in range(k0, k1)]
        for g, idx in groups.items():
            vc = np.diff(tg[:, idx], axis=0) / dt          # command velocity over tick k-1 -> k (row k-1)
            vm = np.diff(c[:, idx], axis=0) / dt
            sc = np.linalg.norm(vc, axis=1)
            sm = np.linalg.norm(vm, axis=1)
            dv = np.linalg.norm(np.diff(vc, axis=0), axis=1)   # change of it at tick k (row k-1)
            wc = slice(k0 - 1, kc - 1)                          # plant .. contact
            wd = slice(k0 - 1, k1 - 2)                          # plant .. contact + after
            jd = int(np.argmax(dv[wd])) + k0 - 1
            r["groups"][g] = {
                "hold_ms": longest_run(sc[wc] < still, dt),
                "hold_ms_measured": longest_run(sm[wc] < still, dt),
                "max_cmd_speed": round(float(sc[k0 - 1:k1 - 1].max()), 2),
                "max_dv": round(float(dv[wd].max()), 3),
                "max_dv_to_contact": round(float(dv[k0 - 1:kc - 2].max()), 3),
                "max_dv_at": [round(float(t[jd + 1]), 3), labels[jd + 1]],
            }
            if rows:
                for j, k in enumerate(range(k0, k1)):
                    ticks[j][g + "_cmd"] = round(float(sc[k - 1]), 3)
                    ticks[j][g + "_meas"] = round(float(sm[k - 1]), 3)
        if rows:
            r["ticks"] = ticks
        out.append(r)
    return out


def trace(params, pitch=0, after=0.08, still=0.1, controller=None):
    sim, res = run(params, [battask.PITCHES[pitch]], controller)
    out = analyse(sim, res, after, still, rows=True)[0]
    out["still_threshold"] = still
    return out


def _sweep_job(args):
    params, pitches, controller, after, still = args
    sim, res = run(params, pitches, controller)
    return res, analyse(sim, res, after, still)


def sweep(params, controller=None, after=0.08, still=0.1, workers=3):
    """The report's demo (4 pitches) and speed/location sweep (18), each pitch
    with its smoothness statistics; summaries as in bat.py's report."""
    from multiprocessing import Pool
    sets = [battask.PITCHES] + [[(v, x, z) for x, z in battask.SWEEP_LOCS] for v in battask.SWEEP_SPEEDS]
    with Pool(workers) as pool:
        outs = pool.map(_sweep_job, [(params, ps, controller, after, still) for ps in sets])
    demo, sw = outs[0], outs[1:]
    allp = [p for r, _ in sw for p in r["pitches"]]
    rows = {"demo": demo[1], "sweep": [x for _, a in sw for x in a]}

    def smooth(rs):
        o = {}
        for g in ("arms", "trunk"):
            o[g] = {"max_hold_ms": max(r["groups"][g]["hold_ms"] for r in rs),
                    "max_dv": max(r["groups"][g]["max_dv"] for r in rs),
                    "mean_max_dv": round(float(np.mean([r["groups"][g]["max_dv"] for r in rs])), 3),
                    "mean_peak_cmd_speed": round(float(np.mean([r["groups"][g]["max_cmd_speed"] for r in rs])), 2)}
        gaps = [r["plant_to_swing_ms"] for r in rs if r["plant_to_swing_ms"] is not None]
        o["plant_to_swing_ms"] = [min(gaps), round(float(np.mean(gaps)), 1), max(gaps)] if gaps else None
        return o
    return {"demo": {"summary": battask._summary(demo[0]), "smooth": smooth(rows["demo"]), "pitches": rows["demo"]},
            "sweep": {"summary": battask._summary({"pitches": allp, "effort": round(float(np.mean([r["effort"] for r, _ in sw])), 4)}),
                      "smooth": smooth(rows["sweep"]), "pitches": rows["sweep"]}}


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--params")
    ap.add_argument("--set", action="append", default=[], help="name=value override (repeatable)")
    ap.add_argument("--pitch", type=int, default=0)
    ap.add_argument("--after", type=float, default=0.08)
    ap.add_argument("--still", type=float, default=0.1)
    ap.add_argument("--controller")
    ap.add_argument("--json")
    ap.add_argument("--rows", action="store_true", help="print every tick")
    ap.add_argument("--sweep", action="store_true", help="run the demo and the 18-pitch sweep (3 workers)")
    a = ap.parse_args()
    prm = load_params(a.params)
    for kv in a.set:
        k, _, v = kv.partition("=")
        prm[k] = float(v)
    if a.sweep:
        out = sweep(prm, a.controller, a.after, a.still)
        keys = ("contacts", "fair", "mean_bat_speed_mps", "mean_bat_speed_at_contact_mps", "mean_exit_mps",
                "launch_10_30", "mean_attack_deg", "mean_intercept_err_cm", "mean_plant_to_contact_ms",
                "mean_swing_to_contact_ms", "mean_stride_m", "mean_lift_height_cm", "plant_to_swing_ms",
                "smoothness_plant_to_contact")
        for part in ("demo", "sweep"):
            print(part, json.dumps({k: out[part]["summary"].get(k) for k in keys}))
            print(part, "launch", out[part]["summary"]["launch_deg"])
            print(part, "smooth", json.dumps(out[part]["smooth"]))
        if a.json:
            with open(a.json, "w") as f:
                json.dump(out, f, indent=1, default=float)
        return
    out = trace(prm, a.pitch, a.after, a.still, a.controller)
    if a.rows:
        for r in out["ticks"]:
            print(f"{r['t']:6.3f}  arms cmd {r['arms_cmd']:6.2f} meas {r['arms_meas']:6.2f}   "
                  f"trunk cmd {r['trunk_cmd']:6.2f} meas {r['trunk_meas']:6.2f}   {r['label']}")
    print(json.dumps({k: v for k, v in out.items() if k != "ticks"}, indent=1))
    if a.json:
        with open(a.json, "w") as f:
            json.dump(out, f, indent=1)


if __name__ == "__main__":
    main()
