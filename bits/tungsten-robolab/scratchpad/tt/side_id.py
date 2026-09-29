"""Round 10: face/height errors at contact (closest approach) per run, for a Jacobian by finite differences.

    .venv-myo/bin/python scratchpad/tt/side_id.py BASE_TAG name:tag name:tag ... [--step 0.06]

Per serve (from <tag>.jsonl + <tag>_logs/*.npz): pad pitch / yaw at the ball's closest approach minus the aim law's last
normal (deg; the normal oriented to +x), pad z minus the ball's z (m, ball above the pad = +), hit, solved, the pad's
velocity along the normal. Means over the serves common to all runs; for the perturbed runs the change per +STEP rad.
"""
import glob, json, os, sys
import numpy as np
np.set_printoptions(precision=3, suppress=True, linewidth=200)


def orient(n):
    n = np.asarray(n, float)
    return n * np.sign(n[..., 0:1] + 1e-12)


def per_serve(tag):
    rows = {}
    for l in open(f"out/tt_r10/{tag}.jsonl"):
        r = json.loads(l)
        if "error" not in r:
            rows[r["seed"]] = r
    out = {}
    for f in glob.glob(f"out/tt_r10/{tag}_logs/*.npz"):
        seed = int(os.path.basename(f).split(".")[0])
        r = rows.get(seed)
        if r is None:
            continue
        z = np.load(f, allow_pickle=True)
        L = z["L"]; A = z["aim"]
        if not isinstance(A, np.ndarray) or A.ndim < 2:
            continue
        ball, pad, nrm = L[:, 1:4], L[:, 7:10], orient(L[:, 13:16])
        k = int(np.argmin(np.linalg.norm(ball - pad, axis=1)))
        good = [i for i in range(len(A)) if abs(A[i, 4]) < 0.6]
        if not good:
            continue
        an = orient(A[good[-1], 1:4])
        pit = np.degrees(np.arcsin(np.clip(nrm[k, 2], -1, 1)) - np.arcsin(np.clip(an[2], -1, 1)))
        yaw = np.degrees(np.arctan2(nrm[k, 1], nrm[k, 0]) - np.arctan2(an[1], an[0]))
        out[seed] = np.array([pit, yaw, ball[k, 2] - pad[k, 2], ball[k, 1] - pad[k, 1], float(r.get("hit", 0) > 0), float(r["solved"] > 0),
                              np.degrees(np.arcsin(np.clip(nrm[k, 2], -1, 1))), np.degrees(np.arctan2(nrm[k, 1], nrm[k, 0]))])
    return out


names = ["pit_err", "yaw_err", "dz", "dy", "hit", "solved", "pad_pit", "pad_yaw"]
args = [a for a in sys.argv[1:]]
step = 0.06
if "--step" in args:
    i = args.index("--step"); step = float(args[i + 1]); del args[i:i + 2]
base = args[0]
pert = [a.split(":") for a in args[1:]]
P = {base: per_serve(base)}
for _, tg in pert:
    P[tg] = per_serve(tg)
common = sorted(set.intersection(*[set(v) for v in P.values()]))
M = {tg: np.array([P[tg][s] for s in common]) for tg in P}
print("common serves", len(common))
print("%-14s" % "run", " ".join("%8s" % n for n in names))
print("%-14s" % base, " ".join("%8.3f" % v for v in M[base].mean(0)))
print("%-14s" % "  sd", " ".join("%8.3f" % v for v in M[base].std(0)))
print("change per +%.3f rad (multiplied to per-0.1 rad):" % step)
for nm, tg in pert:
    d = (M[tg] - M[base]).mean(0) * 0.1 / step
    se = (M[tg] - M[base]).std(0) / len(common) ** 0.5 * 0.1 / step
    print("%-14s" % nm, " ".join("%8.3f" % v for v in d), "  se pit %.2f yaw %.2f dz %.4f" % (se[0], se[1], se[2]))
