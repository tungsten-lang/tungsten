import sys, json, numpy as np
np.set_printoptions(precision=3, suppress=True, linewidth=200)
tag = sys.argv[1]; s = sys.argv[2] if len(sys.argv) > 2 else "A"
rows0 = {json.loads(l)["seed"]: json.loads(l) for l in open(f"out/tt3/o0_{s}.jsonl")}
rows1 = {json.loads(l)["seed"]: json.loads(l) for l in open(f"out/tt3/{tag}_{s}.jsonl")}
dpos, v0, v1, dt = [], [], [], []
for sd, r in rows1.items():
    if sd not in rows0: continue
    z0 = np.load(f"out/tt3/logs_o0/{sd}.npz"); z1 = np.load(f"out/tt3/logs_{tag}/{sd}.npz")
    k0, k1 = int(z0["contact"]), int(z1["contact"])
    if k0 < 3 or k1 < 3: continue
    p0, p1 = z0["L"][k0, 16:19], z1["L"][k1, 16:19]
    dpos.append((p1 - p0)[:2])
    x0, x1 = z0["X"], z1["X"]
    v0.append(x0[k0, 22:24]); v1.append(x1[k1, 22:24]); dt.append(z1["L"][k1, 0] - z0["L"][k0, 0])
dpos, v0, v1, dt = map(np.array, (dpos, v0, v1, dt))
print(f"{tag} {s}: n {len(dpos)} both-hit serves; pelvis world xy at contact O1 - O0: mean {dpos.mean(0)} rms {np.sqrt((dpos**2).mean(0))}; contact time shift mean {dt.mean():+.3f} sd {dt.std():.3f}")
print("   pelvis joint velocity at contact (qd x, y): O0 sd", v0.std(0), "mean", v0.mean(0), "| O1 sd", v1.std(0), "mean", v1.mean(0), " |v| median O0", np.median(np.linalg.norm(v0,axis=1)), "O1", np.median(np.linalg.norm(v1,axis=1)))
