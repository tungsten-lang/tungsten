"""When does a noisy P1 run leave the noise-0 run of the same seed? Per time: pelvis position / yaw / joint-vector distance."""
import sys, glob, gzip, pickle
import numpy as np
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/kick")
import kprobe as P
noise = sys.argv[1] if len(sys.argv) > 1 else "0.05"
files = sorted(glob.glob(f"/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/kick/ckpt/p1base/p1base_n{noise}_*.pkl.gz"))
nom_cache = {}
def nominal(seed):
    # same aim variant as the seed: seeds 5000.. have noise-0 runs only for 5000-5007; map others by keeper y side later
    import os
    f = f"/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/kick/ckpt/p1base/p1base_n0_dx+0_dy+0_s{seed}.pkl.gz"
    if os.path.exists(f):
        return P.load(f)
    return None
times = [0.3, 0.6, 1.0, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.75, 1.8, 1.9, 1.95, 2.0]
rows = {t: [] for t in times}
for f in files:
    p = P.load(f)
    nm = nominal(p["seed"])
    if nm is None:
        continue
    for t in times:
        j = int(round(t / 0.01)) - 1
        if j >= len(p["trace"]) or j >= len(nm["trace"]):
            continue
        a, b = p["trace"][j], nm["trace"][j]
        qa, qb = p["state"][j]["qpos"], nm["state"][j]["qpos"]
        dq = np.linalg.norm(qa[7:] - qb[7:])
        rows[t].append((np.linalg.norm(a["pelvis"] - b["pelvis"]), abs(a["yaw"] - b["yaw"]), dq, np.linalg.norm(a["com"] - b["com"]), abs(a["bof_r"][1] - b["bof_r"][1]), np.linalg.norm(a["bof_r"] - b["bof_r"])))
print(f"noise {noise}: {len(files)} runs; median / max over runs of the distance to the noise-0 run of the same seed")
print("  t    | pelvis m        | yaw rad         | joint-vec rad   | com m           | toe y m         | toe m")
for t in times:
    r = np.array(rows[t])
    if len(r) == 0: continue
    print(f" {t:.2f}  | " + " | ".join(f"{np.median(r[:,k]):.3f} / {np.max(r[:,k]):.3f}" for k in range(6)))
