"""Pad velocity along the pad axis at contact = pelvis part + arm/trunk part (agent T's an15 decomposition), on this run's logs (official body, rung 0)."""
import json, os, sys
import numpy as np
tag = sys.argv[1] if len(sys.argv) > 1 else "0"
rows = {json.loads(l)["seed"]: json.loads(l) for l in open(f"out/tt2/champ_r{tag}_98000.jsonl")}
P, Pel, Rel, S = [], [], [], []
for seed, r in rows.items():
    f = f"out/tt2/logs_r{tag}/{seed}.npz"
    if not r.get("hit") or not os.path.exists(f): continue
    z = np.load(f); L = z["L"]; k = int(z["contact"])
    if k < 12: continue
    t, pad, pel, nrm = L[:, 0], L[:, 7:10], L[:, 16:19], L[:, 13:16]
    kk = k - 1
    vpad = (pad[kk] - pad[kk - 1]) / (t[kk] - t[kk - 1]); vpel = (pel[kk - 1 + 0] - pel[kk - 2]) / (t[kk - 1] - t[kk - 2]) if False else (pel[kk] - pel[kk - 1]) / (t[kk] - t[kk - 1])
    n = nrm[kk] * np.sign(nrm[kk][0]); n = n / np.linalg.norm(n)
    P.append(vpad @ n); Pel.append(vpel @ n); Rel.append((vpad - vpel) @ n); S.append(r["side"])
P, Pel, Rel, S = map(np.array, (P, Pel, Rel, S))
print(f"rung {tag}: hits {len(P)}; velocity along the pad axis at contact (+x oriented): pad {P.mean():+.2f} +- {P.std():.2f} | pelvis part {Pel.mean():+.2f} +- {Pel.std():.2f} | arm+trunk part {Rel.mean():+.2f} +- {Rel.std():.2f}")
for s, nm in ((1, "forehand"), (2, "backhand")):
    m = S == s
    print(f"   {nm} (n {m.sum()}): pad {P[m].mean():+.2f} +- {P[m].std():.2f} | pelvis {Pel[m].mean():+.2f} +- {Pel[m].std():.2f} | arm+trunk {Rel[m].mean():+.2f} +- {Rel[m].std():.2f}")
