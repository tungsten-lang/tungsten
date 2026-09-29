"""Round 10: LS posture step from a finite-difference Jacobian of the contact-time errors (see side_id.py).

    .venv-myo/bin/python scratchpad/tt/side_solve.py BASE_TAG PARAMS_FILE --step 0.06 --set "k=v,..." \
        --targets "pit_err=0,yaw_err=0,dz=0.01" --w "1,0.5,30" --lam 0.5 --names bh_elv,bh_sh_elv,... [--prefix bhid_]

Tags are `<prefix><name>` for each name. Prints the predicted errors and the new parameter values.
"""
import argparse, sys, os, json
import numpy as np
from scipy.optimize import lsq_linear
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import importlib.util
np.set_printoptions(precision=3, suppress=True, linewidth=200)

ap = argparse.ArgumentParser()
ap.add_argument("base"); ap.add_argument("params")
ap.add_argument("--step", type=float, default=0.06)
ap.add_argument("--names", required=True)
ap.add_argument("--prefix", default="")
ap.add_argument("--targets", default="pit_err=0,yaw_err=0,dz=0.01")
ap.add_argument("--w", default="1,0.5,30")
ap.add_argument("--lam", type=float, default=0.5)
ap.add_argument("--maxstep", type=float, default=0.2)
ap.add_argument("--lo", default=""); ap.add_argument("--hi", default="")
a = ap.parse_args()

# reuse per_serve from side_id without running its main part
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "side_id.py")).read().split('names = ["pit_err"')[0]
ns = {}
exec(compile(src, "side_id_head", "exec"), ns)
per_serve = ns["per_serve"]
cols = ["pit_err", "yaw_err", "dz", "dy", "hit", "solved", "pad_pit", "pad_yaw"]
names = a.names.split(",")
P = {"base": per_serve(a.base)}
for n in names:
    P[n] = per_serve(a.prefix + n)
common = sorted(set.intersection(*[set(v) for v in P.values()]))
M = {k: np.array([v[s] for s in common]) for k, v in P.items()}
m0 = M["base"].mean(0)
out_idx = [cols.index(t.split("=")[0]) for t in a.targets.split(",")]
tgt = np.array([float(t.split("=")[1]) for t in a.targets.split(",")])
J = np.array([(M[n] - M["base"]).mean(0)[out_idx] / a.step for n in names]).T   # outputs x params, per rad
params = {}
for l in open(a.params):
    if l.startswith("#") or not l.strip():
        continue
    k, v = l.split()
    params[k] = float(v)
base = np.array([params[n] for n in names])
lo = np.array([float(x) for x in a.lo.split(",")]) - base if a.lo else -np.full(len(names), a.maxstep)
hi = np.array([float(x) for x in a.hi.split(",")]) - base if a.hi else np.full(len(names), a.maxstep)
lo = np.maximum(lo, -a.maxstep); hi = np.minimum(hi, a.maxstep)
W = np.diag([float(x) for x in a.w.split(",")])
cur = m0[out_idx]
A = np.vstack([W @ J, np.sqrt(a.lam) * np.eye(len(names))])
y = np.concatenate([W @ (tgt - cur), np.zeros(len(names))])
r = lsq_linear(A, y, bounds=(lo, hi))
dq = r.x
print("common serves", len(common), "| base means", dict(zip([cols[i] for i in out_idx], cur.round(3))))
print("Jacobian (rows: %s; cols: %s) per rad:" % ([cols[i] for i in out_idx], names)); print(J)
print("step", dict(zip(names, dq.round(4))), "predicted", dict(zip([cols[i] for i in out_idx], (cur + J @ dq).round(3))))
print("new values:", ",".join("%s=%s" % (n, round(float(b + d), 5)) for n, b, d in zip(names, base, dq)))
