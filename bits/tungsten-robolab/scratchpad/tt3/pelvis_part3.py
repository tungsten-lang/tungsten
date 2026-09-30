"""Pad velocity along the pad axis at contact = pelvis part + arm/trunk part (agent T's an15 decomposition, T2's pelvis_part.py) for any run: python pelvis_part3.py TAG [SETS]"""
import json, os, sys
import numpy as np
tag = sys.argv[1]; sets = (sys.argv[2] if len(sys.argv) > 2 else "A,B").split(",")
P, Pel, Rel, S = [], [], [], []
for s in sets:
    f = f"out/tt3/{tag}_{s}.jsonl"
    if not os.path.exists(f): continue
    for l in open(f):
        r = json.loads(l)
        lg = f"out/tt3/logs_{tag}/{r['seed']}.npz"
        if "error" in r or not r.get("hit") or not os.path.exists(lg): continue
        z = np.load(lg); L = z["L"]; k = int(z["contact"])
        if k < 12: continue
        t, pad, pel, nrm = L[:, 0], L[:, 7:10], L[:, 16:19], L[:, 13:16]
        kk = k - 1
        vpad = (pad[kk] - pad[kk - 1]) / (t[kk] - t[kk - 1]); vpel = (pel[kk] - pel[kk - 1]) / (t[kk] - t[kk - 1])
        n = nrm[kk] * np.sign(nrm[kk][0]); n = n / np.linalg.norm(n)
        P.append(vpad @ n); Pel.append(vpel @ n); Rel.append((vpad - vpel) @ n); S.append(r["side"])
P, Pel, Rel, S = map(np.array, (P, Pel, Rel, S))
print(f"{tag} {','.join(sets)}: hits {len(P)}; velocity along the pad axis at contact (+x oriented): pad {P.mean():+.2f} +- {P.std():.2f} | pelvis part {Pel.mean():+.2f} +- {Pel.std():.2f} | arm+trunk part {Rel.mean():+.2f} +- {Rel.std():.2f}")
for s, nm in ((1, "forehand"), (2, "backhand")):
    m = S == s
    if m.sum(): print(f"   {nm} (n {m.sum()}): pad {P[m].mean():+.2f} +- {P[m].std():.2f} | pelvis {Pel[m].mean():+.2f} +- {Pel[m].std():.2f} | arm+trunk {Rel[m].mean():+.2f} +- {Rel[m].std():.2f}")
