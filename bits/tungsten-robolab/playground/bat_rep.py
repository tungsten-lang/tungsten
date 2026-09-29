"""bat_rep: cheap, diagnosable evaluation of in-representation bat swings on fresh pitches (batting round 2).

    .venv/bin/python playground/bat_rep.py eval --params params/bat_v6_knots.txt \
        --controller bin/challengers/bat_v6-knots1 --seeds 1100:1124 [--set k=v,k=v] [--workers 2] [--name x]

One rollout = one fresh pitch (tasks/bat_rep.py: seed -> the arena's fresh draw), stopped at 4.6 s of simulated time
(contact is at ~3.35 s and everything scored - power, flow, aim - is settled by contact + 0.8 s; the arena's
7.8 s rollout gives identical numbers, checked). Prints one row per pitch: the pitch, hit or miss with its aim error
(aim_v_ms: + = bat LATE; aim_n_cm: offset from the swing plane; gap_cm: the closest surface gap of a miss), the
bat speed, the bat_flow score, and a summary that matches the arena's metrics (power = mean bat speed with a miss as 0).
Writes out/bat_r2/<name>.json (every pitch's record) when --name is given.

`--seeds` is a list or a range a:b (b exclusive); `--pitch v,x,z[;v,x,z...]` evaluates explicit pitches instead (a pitch
scan; seeds then only name the rollouts). Arena seeds: 1000-1023 (bat_power_fresh), 1100-1123 (bat_power_fresh_rep);
round-2 practice seeds are 3000+, validation 4000+.

Importable: run_many(jobs, workers) with jobs from job(params, controller, seed, seconds, pitch), and summarise().
"""

import argparse
import json
import multiprocessing as mp
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
if HERE not in sys.path:
    sys.path.insert(0, HERE)
for _v in ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
    os.environ.setdefault(_v, "1")

KEEP = ("hit", "bat_speed", "closest", "fair", "flow", "flow_terms", "aim_v_ms", "aim_n_cm", "aim_dz_cm", "aim_s", "gap_cm",
        "intercept_err_cm", "t_release", "t_swing", "t_contact", "t_plant", "t_lift", "t_closest", "speed_mph", "target_x",
        "target_z", "attack_deg", "launch_deg", "spray_deg", "exit_speed", "impact_from_end", "pelvis_peak_radps",
        "torso_peak_radps", "hand_peak_mps", "bat_w_peak_radps", "peak_ms_before_contact", "plant_to_swing_ms",
        "plant_to_contact_ms", "swing_to_contact_ms", "stride_m", "lift_height_cm", "pelvis_shift_m", "time_in_zone_ms")


def read_params(path):
    out = {}
    if path:
        for line in open(path):
            t = line.split()
            if len(t) >= 2 and not line.startswith("#"):
                out[t[0]] = float(t[1])
    return out


def parse_set(s):
    out = {}
    for kv in (s or "").split(","):
        if kv:
            k, v = kv.split("=")
            out[k.strip()] = float(v)
    return out


def parse_seeds(s):
    out = []
    for part in s.split(","):
        if ":" in part:
            a, b = part.split(":")
            out += list(range(int(a), int(b)))
        elif part:
            out.append(int(part))
    return out


def job(params, controller, seed, seconds=4.6, pitch=None):
    return (params, os.path.abspath(controller), int(seed), float(seconds), tuple(pitch) if pitch else None)


def _init():
    os.environ.setdefault("BAT_BODY", "athlete")
    if HERE not in sys.path:
        sys.path.insert(0, HERE)


def rollout(j):
    """One pitch -> {'seed', 'pitch', 'rec': the pitch's record (KEEP keys), 'flow_ok', 'power', 'wall', 'error'}."""
    params, controller, seed, seconds, pitch = j
    t0 = time.time()
    try:
        from bridge import Sim
        from tasks.bat_rep import BatRepTask
        task = BatRepTask()
        task.seed = seed
        if pitch is not None:
            task.explicit_pitch = pitch
        sim = Sim(task, params=params, controller=controller)
        m = sim.run(seconds)
        ps = m.get("pitches", [])
        rec = {k: v for k, v in (ps[0] if ps else {}).items() if k in KEEP}
        rec = json.loads(json.dumps(rec, default=float))
        return {"seed": seed, "pitch": list(task.pitches[0]), "rec": rec, "hit": bool(ps and ps[0]["hit"]),
                "flow": m.get("flow"), "flow_ok": bool(m.get("flow_ok")), "score": float(task.score(m)),
                "wall": round(time.time() - t0, 1)}
    except Exception as e:  # a crashing candidate scores worst
        return {"seed": seed, "pitch": list(pitch) if pitch else None, "rec": {}, "hit": False, "flow": None,
                "flow_ok": False, "score": -1e9, "wall": round(time.time() - t0, 1), "error": str(e)[:300]}


_POOLS = {}


def pool(workers):
    if workers not in _POOLS:
        _POOLS[workers] = mp.get_context("spawn").Pool(workers, initializer=_init)
    return _POOLS[workers]


def run_many(jobs, workers=2):
    return pool(workers).map(rollout, jobs, chunksize=1)


def power(r):
    return float(r["rec"].get("bat_speed", 0.0)) if r["hit"] else 0.0


def summarise(rows):
    import numpy as np
    n = len(rows)
    hits = [r for r in rows if r["hit"]]
    pw = [power(r) for r in rows]
    flows = [r["flow"] for r in rows if r.get("flow") is not None]
    return {"n": n, "power": round(float(np.mean(pw)), 3), "hits": len(hits),
            "hit_speed": round(float(np.mean([power(r) for r in hits])), 3) if hits else None,
            "fair": sum(1 for r in hits if r["rec"].get("fair")),
            "flow_mean": round(float(np.mean(flows)), 3) if flows else None,
            "flow_max": round(float(np.max(flows)), 3) if flows else None,
            "flow_ok": sum(1 for r in rows if r["flow_ok"]),
            "score": round(float(np.mean([r["score"] for r in rows])), 3),
            "misses": [r["seed"] for r in rows if not r["hit"]],
            "errors": sum(1 for r in rows if "error" in r)}


def table(rows):
    print(f"{'seed':>6} {'v m/s':>6} {'x':>7} {'z':>6}  {'res':<5} {'speed':>6} {'flow':>5} {'aim_v ms':>8} {'aim_n cm':>8} {'gap cm':>6} {'s m':>5}")
    for r in rows:
        p = r["pitch"] or [0, 0, 0]
        rec = r["rec"]
        print(f"{r['seed']:>6} {p[0]:>6.1f} {p[1]:>+7.3f} {p[2]:>6.3f}  {'HIT' if r['hit'] else 'MISS':<5} "
              f"{power(r):>6.2f} {(r['flow'] if r['flow'] is not None else float('nan')):>5.2f} "
              f"{rec.get('aim_v_ms', float('nan')):>8.1f} {rec.get('aim_n_cm', float('nan')):>8.1f} "
              f"{rec.get('gap_cm', float('nan')):>6.1f} {rec.get('aim_s', float('nan')):>5.2f}"
              + (f"  ERROR {r['error']}" if "error" in r else ""))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["eval"])
    ap.add_argument("--params")
    ap.add_argument("--controller", required=True)
    ap.add_argument("--seeds", default="1100:1124")
    ap.add_argument("--set", help="k=v,... overrides on top of --params")
    ap.add_argument("--pitch", help="v,x,z[;v,x,z...] explicit pitches (one rollout each)")
    ap.add_argument("--workers", type=int, default=2)
    ap.add_argument("--seconds", type=float, default=4.6)
    ap.add_argument("--name")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()
    params = {**read_params(a.params), **parse_set(a.set)}
    if a.pitch:
        pitches = [tuple(float(x) for x in p.split(",")) for p in a.pitch.split(";")]
        jobs = [job(params, a.controller, 0, a.seconds, p) for p in pitches]
    else:
        jobs = [job(params, a.controller, s, a.seconds) for s in parse_seeds(a.seeds)]
    t0 = time.time()
    rows = run_many(jobs, a.workers)
    if not a.quiet:
        table(rows)
    sm = summarise(rows)
    print(json.dumps(sm), f"({time.time() - t0:.0f}s)")
    if a.name:
        os.makedirs(os.path.join(ROOT, "out", "bat_r2"), exist_ok=True)
        path = os.path.join(ROOT, "out", "bat_r2", a.name + ".json")
        with open(path, "w") as f:
            json.dump({"params": a.params, "set": a.set, "controller": a.controller, "seeds": a.seeds, "summary": sm,
                       "rows": rows}, f, indent=1)
        print("wrote", path)


if __name__ == "__main__":
    main()
