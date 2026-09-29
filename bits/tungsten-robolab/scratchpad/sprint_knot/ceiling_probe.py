"""Pitch-free ceiling of one body configuration: chain sprint_limits speeds upward from a feasible
solution (each speed warm-started from the previous speed's solution), stop after two failing margins,
fit the margin's zero crossing (least squares over all valid points).
usage: ceiling_probe.py LABEL [--profile p95] [--v0 5.5] [--dv 0.5] [--vmax 12] [--init file.json]
  body options come from the environment: ROBOLAB_BODY=v4, ROBOLAB_CALIB, ROBOLAB_CALIB_SET."""
import argparse, json, os, re, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "out", "sprint_limits")
sys.path.insert(0, os.path.join(ROOT, "playground"))
import numpy as np
ap = argparse.ArgumentParser()
ap.add_argument("label"); ap.add_argument("--profile"); ap.add_argument("--v0", type=float, default=5.5)
ap.add_argument("--dv", type=float, default=0.5); ap.add_argument("--vmax", type=float, default=12.0)
ap.add_argument("--init", default=os.path.join(HERE, "pf_init60.json")); ap.add_argument("--workers", type=int, default=4)
ap.add_argument("--gens", type=int, default=120); ap.add_argument("--cycle", type=int, default=40)
ap.add_argument("--seed", type=int, default=1)
ap.add_argument("--restarts", type=int, default=2, help="optimisations per speed (different seeds); the best margin counts")
ap.add_argument("--stop", default="margin", choices=["margin", "budget"], help="budget: stop when the stance budget falls below 0.33 s twice (the swing is not refined)")
a = ap.parse_args()
prev = a.init
pts, runs, fails = [], [], 0
v = a.v0
t0 = time.time()
def one(v, seed):
    name = f"probe_{a.label}_v{v:g}_k{seed}"
    cmd = [sys.executable, os.path.join(ROOT, "playground", "sprint_limits.py"), "speeds", "--v", f"{v:g}", "--gens", str(a.gens),
           "--cycle-gens", str(a.cycle), "--workers", str(a.workers), "--pitch-free", "--name", name, "--init", prev,
           "--seed", str(seed)]
    if a.profile:
        cmd += ["--profile", a.profile]
    subprocess.run(cmd, cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    path = os.path.join(OUT, f"{name}_speeds.json")
    if not os.path.exists(path):
        return None, None
    r = json.load(open(path))["runs"][0]
    w = r["weyand"]
    if not (w.get("taer_sym", 0) > 0 and w.get("margin") is not None):
        w = dict(w, margin=-9.0)
    return r, path

while v <= a.vmax + 1e-9 and fails < 2:
    best = (None, None)
    for k in range(a.restarts):
        r, path = one(v, a.seed + 100 * k)
        key = (lambda rr: rr["weyand"].get("capacity_score") or -9) if a.stop == "budget" else (lambda rr: rr["weyand"].get("margin") or -9)
        if r is not None and (best[0] is None or key(r) > key(best[0])):
            best = (r, path)
    r, path = best
    if r is None:
        print(f"  v {v:g}: no result", flush=True); fails += 1; v += a.dv; continue
    w = r["weyand"]
    ok = w.get("taer_sym", 0) > 0 and w.get("margin") is not None
    print(f"  v {v:g}: margin {w.get('margin')} tc {w.get('tc')} taer {w.get('taer_sym')} f {w.get('f_step')} Favg {w.get('Favg_W_sym')} "
          f"peak {w.get('peak_grf_W')} thigh {w.get('thigh_td')}/{w.get('thigh_lo')} dw {w.get('dw_pitch')} exc {w.get('pitch_exc')} "
          f"({time.time() - t0:.0f}s)", flush=True)
    if a.stop == "budget":
        cap = w.get("capacity_score") or -9
        if w.get("taer_sym", 0) > 0:
            runs.append(r)
        if cap < 0.33:
            fails += 1
        else:
            fails = 0
            prev = path
    elif ok:
        runs.append(r)
        if w["margin"] < 0:
            fails += 1
        else:
            fails = 0
            prev = path
    else:
        fails += 1
    v += a.dv
pts = np.array([(r["v"], r["weyand"]["margin"]) for r in runs])
res = {"label": a.label, "profile": a.profile, "env": {k: os.environ.get(k) for k in ("ROBOLAB_BODY", "ROBOLAB_CALIB", "ROBOLAB_CALIB_SET")},
       "points": pts.tolist()}
if len(pts) >= 2:
    b, c = np.polyfit(pts[:, 0], pts[:, 1], 1)
    res["ceiling_fit"] = float(-c / b) if b < 0 else None
    pos = pts[pts[:, 1] >= 0]
    res["fastest_positive"] = float(pos[:, 0].max()) if len(pos) else None
json.dump(res, open(os.path.join(OUT, f"probe_{a.label}.json"), "w"), indent=1)
print(f"{a.label}: ceiling (fit) {res.get('ceiling_fit')}, fastest positive margin {res.get('fastest_positive')}", flush=True)
