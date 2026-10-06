"""Nominal contraction tables for the tracking servo of a table stage (round 5; fit_nominal.py of round 3 on the replay records instead of live traces).

    scratchpad/btl5/py scratchpad/btl5/nom3.py rec_dir stage table.npz base_params.txt out_params.txt [ridge] [lead]

From closed-loop records of starts whose stage `stage` ran the table in table.npz (fit3.py output: blocks, feature nominal / spread), regress the stroking arm's
16 muscle contractions (what the skill's frame reports: the state's contraction less one step of its rate) at the 17 table knots (25 ms apart from the trigger
tick) on the stage's own schedule features u (clipped (feature - nominal) / spread, as the skill forms them), c_m(t_j) = N0 + sum_i u_i N_i, and write
pgn<stage>_<m>_<j> (N0), pgnx / pgny (<stage>_<m>_<j>), pgnz<stage>_<i>_<m>_<j> into base_params -> out_params. The servo is switched on separately
(pg_fbs<stage>).
"""
import os
import pickle
import sys

import numpy as np

sys.path.insert(0, "scratchpad/btl5")
sys.path.insert(0, "scratchpad/btl4")
sys.path.insert(0, "scratchpad/btl2")
sys.path.insert(0, "playground")
sys.path.insert(0, "playground/tasks")
from multiprocessing import Pool  # noqa: E402

import fit3 as F  # noqa: E402
import oracle_lib as O  # noqa: E402
import prep as P  # noqa: E402
from common import load, write_params  # noqa: E402

_RP = {}


def one(job):
    seed, path, stage, lead = job
    d = P.one((seed, path, stage, lead))
    if d is None:
        return None
    rec = pickle.load(open(path, "rb"))
    rp = P._RP["rp"]
    rp.rec = rec
    rp.act_ids = rec["act_ids"]
    idx = F.arm_indices(rec["names"], d["hand"])
    ks = d["ks"]
    C = np.zeros((16, F.NK))
    for j in range(F.NK):
        k = ks + int(round(max(0.0, (j * F.DK - d["shift"]) / F.TICK)))      # the tick at stage-clock time j * 25 ms
        if k not in rec["snaps"]:
            return None
        rp.load(k)
        c, cd, _ = rp.sim.contraction()
        c = c - cd * O.DT          # the controller's frame is one physics step stale
        C[:, j] = c[idx]
    return {"seed": seed, "feat": d["feat"], "C": C, "pass_ok": d["pass_ok"], "pass_log": d["pass_log"]}


def main():
    rec_dir, stage, npz, base, outp = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4], sys.argv[5]
    ridge = float(sys.argv[6]) if len(sys.argv) > 6 else 3.0
    lead = float(sys.argv[7]) if len(sys.argv) > 7 else 0.165
    z = np.load(npz)
    nom, sc = z["nom"], z["sc"]
    files = sorted(f for f in os.listdir(rec_dir) if f.startswith("rec_") and f.endswith(".pkl"))
    jobs = [(int(f[4:-4]), os.path.join(rec_dir, f), stage, lead) for f in files]
    with Pool(2) as p:
        rows = [r for r in p.map(one, jobs, chunksize=4) if r is not None]
    # the starts the table played on: crossing inside the design range
    # the starts the table played on in its design situation: the first passes ok, the incoming ball reachable (as fit3's active set)
    def active(r):
        pl = r["pass_log"]
        if len(pl) < 3 or not (r["pass_ok"][0] and r["pass_ok"][1]) or not all(pl[i]["gate"] and pl[i]["body"] == 0 for i in range(3)):
            return False
        x, y = r["feat"][0], r["feat"][1]
        return -0.40 < x < 0.10 and 0.15 < y < 0.55
    def active4(r):
        pl = r["pass_log"]
        if len(pl) < 4 or not all(r["pass_ok"][:3]) or not all(pl[i]["gate"] and pl[i]["body"] == 0 for i in range(4)):
            return False
        x, y = r["feat"][0], r["feat"][1]
        return 0.10 < x < 0.70 and -0.55 < y < 0.0
    if stage == 3:
        rows = [r for r in rows if active(r)]
    elif stage == 4:
        rows = [r for r in rows if active4(r)]
    X = np.array([[1.0] + list(np.clip((r["feat"] - nom) / sc, -2.5, 2.5)) for r in rows])
    Y = np.array([r["C"].reshape(-1) for r in rows])
    Rg = ridge * np.eye(X.shape[1])
    Rg[0, 0] = 0.0
    Bm = np.linalg.solve(X.T @ X + Rg, X.T @ Y)
    res = Y - X @ Bm
    tot = Y.var(0)
    print(f"n {len(rows)}; contraction sd per knot (mean over muscles) {np.round(np.sqrt(tot.reshape(16, F.NK)).mean(0)[::4], 3).tolist()}; "
          f"residual sd {np.round(np.sqrt(res.var(0).reshape(16, F.NK)).mean(0)[::4], 3).tolist()}")
    B = Bm.reshape(X.shape[1], 16, F.NK)
    out = load(base)
    nz = X.shape[1] - 3
    for m in range(16):
        for k in range(F.NK):
            out[f"pgn{stage}_{m}_{k}"] = float(B[0, m, k])
            out[f"pgnx{stage}_{m}_{k}"] = float(B[1, m, k])
            out[f"pgny{stage}_{m}_{k}"] = float(B[2, m, k])
            for i in range(nz):
                out[f"pgnz{stage}_{i}_{m}_{k}"] = float(B[3 + i, m, k])
    write_params(outp, out, f"{base} + nominal contraction tables of stage {stage} (nom3.py on {rec_dir}, ridge {ridge})")
    print("wrote", outp)


if __name__ == "__main__":
    main()
