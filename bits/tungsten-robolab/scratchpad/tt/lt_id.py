"""Round 10: pose Jacobians of the forehand's ready posture in the live-tracking regime.

    .venv-myo/bin/python scratchpad/tt/lt_id.py BASE_TAG name:tag name:tag ...     (each perturbed by +STEP)

For every tag (jsonl + <tag>_logs/*.npz from TT_SAVE_LOG runs on the same serves) the per-serve pose is taken at
t = 0.25 s (the ready phase, before the servo starts) and at the ball's closest approach (contact). Prints the
means over the common serves, and for the perturbed runs the change per +0.1 rad (STEP given by --step).
"""
import glob, json, sys, os
import numpy as np
np.set_printoptions(precision=3, suppress=True, linewidth=200)


def orient(n):
    n = np.asarray(n, float)
    return n * np.sign(n[..., 0:1] + 1e-12)


def pose(tag, t_ready=0.25):
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
        L = z["L"]
        t = L[:, 0]
        ball, pad, nrm, pel = L[:, 1:4], L[:, 7:10], orient(L[:, 13:16]), L[:, 16:19]
        i = int(np.argmin(abs(t - t_ready)))
        k = int(np.argmin(np.linalg.norm(ball - pad, axis=1)))
        def p(j):
            return [np.degrees(np.arcsin(np.clip(nrm[j, 2], -1, 1))), np.degrees(np.arctan2(nrm[j, 1], nrm[j, 0])),
                    pad[j, 2], pad[j, 1] - pel[j, 1], pad[j, 0] - pel[j, 0]]
        out[seed] = np.array(p(i) + p(k) + [ball[k, 2] - pad[k, 2], ball[k, 1] - pad[k, 1], float(r.get("hit", 0) > 0), float(r["solved"] > 0)])
    return out


names = ["r_pitch", "r_yaw", "r_z", "r_dy", "r_dx", "c_pitch", "c_yaw", "c_z", "c_dy", "c_dx", "dz", "dy", "hit", "solved"]
step = 0.1
args = sys.argv[1:]
base = args[0]
pert = [a.split(":") for a in args[1:]]
P = {base: pose(base)}
for _, tg in pert:
    P[tg] = pose(tg)
common = sorted(set.intersection(*[set(v) for v in P.values()]))
print("common serves", len(common))
M = {tg: np.array([P[tg][s] for s in common]) for tg in P}
print("%-12s" % "run", " ".join("%8s" % n for n in names))
print("%-12s" % base, " ".join("%8.3f" % v for v in M[base].mean(0)))
print("%-12s" % "  sd", " ".join("%8.3f" % v for v in M[base].std(0)))
print("changes per +%.2f rad (mean over common serves; se of the difference in brackets for r_z, c_z):" % step)
for nm, tg in pert:
    d = M[tg] - M[base]
    print("%-12s" % nm, " ".join("%8.3f" % v for v in d.mean(0)), "  se r_z %.4f c_z %.4f" % (d[:, 2].std() / len(common) ** 0.5, d[:, 7].std() / len(common) ** 0.5))
