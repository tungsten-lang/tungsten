"""Reached-vs-asked table of the ideal-arm oracle (agent T3): at the contact tick, per side, over the serves that hit: the commanded posture q_fit (asked), the oracle's reference q_ref,
the reached posture q, the tracking error q - q_ref (mean, rms), and the scatter (sd across serves) of the reached posture in the champion (record-only run `rec`) and under the oracle.
    .venv-myo/bin/python scratchpad/tt3/table_arm.py TAG [SETS=A,B]"""
import json, os, sys
import numpy as np
np.set_printoptions(precision=3, suppress=True, linewidth=220)
JN = ["elv_angle", "shoulder_elv", "shoulder_rot", "elbow_flexion", "pro_sup", "deviation", "flexion"]
tag = sys.argv[1]; sets = (sys.argv[2] if len(sys.argv) > 2 else "A,B").split(",")
def collect(tg):
    out = {1: [], 2: []}
    for s in sets:
        f = f"out/tt3/{tg}_{s}.jsonl"
        if not os.path.exists(f): continue
        for l in open(f):
            r = json.loads(l)
            if "error" in r or not r.get("hit") or r.get("side") not in (1, 2): continue
            z = f"out/tt3/orc_{tg}/{r['seed']}.npz"
            if not os.path.exists(z): continue
            d = np.load(z); t = d["t"][:, 0]
            i = int(np.argmin(np.abs(t - r["t_contact"])))
            out[r["side"]].append(dict(qfit=d["qfit"][i], q=d["q"][i], qref=d["qref"][i] if "qref" in d else None, qd=d["qd"][i], seed=r["seed"]))
    return out
a, b = collect(tag), collect("rec")
for side, nm in ((1, "forehand"), (2, "backhand")):
    A, B = a[side], b[side]
    if not A: continue
    Q = np.array([x["q"] for x in A]); F = np.array([x["qfit"] for x in A]); QB = np.array([x["q"] for x in B]); FB = np.array([x["qfit"] for x in B])
    print(f"== {nm}: {len(A)} hits under {tag} (record-only champion: {len(B)} hits)")
    print("   joint          asked(q_fit)  reference    reached   err(q-ref) mean  rms  | reached sd: champion -> oracle | champion reached mean")
    R = np.array([x["qref"] for x in A]) if A[0]["qref"] is not None else None
    for j, n in enumerate(JN):
        e = (Q[:, j] - R[:, j]) if R is not None else np.zeros(len(Q))
        print(f"   {n:<14} {F[:, j].mean():+8.3f}    {R[:, j].mean() if R is not None else float('nan'):+8.3f}  {Q[:, j].mean():+8.3f}   {e.mean():+7.3f} {np.sqrt((e ** 2).mean()):6.3f}  |  {QB[:, j].std():6.3f} -> {Q[:, j].std():6.3f}   |  {QB[:, j].mean():+8.3f}")
    tp = np.array([json.loads(l).get("o2_tau_peak") for s in sets for l in open(f"out/tt3/{tag}_{s}.jsonl") if json.loads(l).get("o2_tau_peak")])
    if len(tp): print("   peak PD torque per joint (N m), median over serves:", np.median(tp, axis=0), " max", tp.max(axis=0))
