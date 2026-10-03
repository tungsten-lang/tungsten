"""ckpt: rebuild the ES incumbent at given rollout budgets from an hsearch archive (--archive npz), so arms can be compared at EQUAL budget.

  .venv/bin/python scratchpad/anat5/ckpt.py scratchpad/anat5/es_v4_g3_s1 --lam 16 --budgets 1000,2500,5000 [--nfull 8] [--out-prefix scratchpad/anat5/ckpt_v4_g3_s1]
Replays hsearch.main's acceptance rule over the archived candidates in order (entry 0 = the start, then generations of `lam`): a generation's best candidate is
accepted if it beats the incumbent and ran all `nfull` seeds. Writes <prefix>_u<budget>.txt (a params file: the archive's fixed values + the decoded incumbent) and prints the trajectory.
"""
import argparse, json, sys, os
import numpy as np
ap = argparse.ArgumentParser(); ap.add_argument("base"); ap.add_argument("--lam", type=int, default=16); ap.add_argument("--budgets", default="")
ap.add_argument("--nfull", type=int, default=8); ap.add_argument("--out-prefix"); a = ap.parse_args()
z = np.load(a.base + ".npz", allow_pickle=True)
X, F, R = z["X"], z["F"], z["ran"]; names = [str(n) for n in z["names"]]; lo, hi, v0, x0 = z["lo"], z["hi"], z["v0"], z["x0"]
fixed = json.loads(str(z["fixed"]))
def decode(x):
    x = np.clip(x, 0, 1); v = lo + (hi - lo) * x; v = np.where(x == x0, v0, v)
    p = dict(fixed); p.update({n: float(val) for n, val in zip(names, v)}); return p
budgets = [int(b) for b in a.budgets.split(",") if b]
best_f, best_i, used = float(F[0]), 0, int(R[0])
traj = [(used, best_f, 0)]
pending = list(budgets)
def dump(b, i):
    if not a.out_prefix: return
    p = decode(X[i]); path = f"{a.out_prefix}_u{b}.txt"
    with open(path, "w") as f:
        f.write(f"# robolab params: ES incumbent of {a.base} at {b} rollouts (score {best_f:.3f}, candidate {i}) rebuilt by ckpt.py\n# \n")
        for k in sorted(p): f.write(f"{k} {p[k]:.17g}\n")
n = len(F); i = 1; gen = 0
while i + 0 < n:
    j = min(n, i + a.lam); gen += 1
    seg = slice(i, j)
    used_before = used
    used += int(R[seg].sum())
    while pending and used_before >= pending[0]:
        dump(pending[0], best_i); pending.pop(0)
    k = i + int(np.argmax(F[seg]))
    if F[k] > best_f and R[k] == a.nfull:
        best_f, best_i = float(F[k]), k; traj.append((used, best_f, gen))
    i = j
while pending and used >= pending[0]:
    dump(pending[0], best_i); pending.pop(0)
dump(used, best_i)
print(f"{a.base}: {n} candidates, {used} rollouts, {gen} generations, incumbent score {best_f:.3f} (candidate {best_i}); trajectory (rollouts, best):")
print("  " + " ".join(f"({u},{b:.1f})" for u, b, _ in traj[:40]))
