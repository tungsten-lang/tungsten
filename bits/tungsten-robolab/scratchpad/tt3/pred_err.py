"""Ball prediction error of the controller's own flight model (MyoTTBall.intercept, ported) vs lead time (agent T3): at the tick `lead` before the ball reaches the plane x = x_pad (the pad centre's x at the
contact row), the predicted crossing y, z, time; the reference = the same prediction made 1 tick before the contact row (the ball is then ~1 cm from the plane). Sets A and B, serves the champion hit."""
import json, os, sys
import numpy as np
def intercept(p, v, xh, bounced):
    px, py, pz = p; vx, vy, vz = v; t0 = 0.0
    if not bounced:
        c = pz - 0.805; disc = vz * vz + 2 * 9.81 * c
        if disc < 0: return None
        tb = (vz + np.sqrt(disc)) / 9.81
        px += vx * tb; py += vy * tb; vz = -(vz - 9.81 * tb) * 0.99; vx *= 0.996; vy *= 0.996; pz = 0.805; t0 = tb
    if vx < 0.5: return None
    th = (xh - px) / vx
    if th < 0: return None
    return np.array([t0 + th, py + vy * th, pz + vz * th - 4.905 * th * th])
res = {0.03: [], 0.05: [], 0.10: [], 0.15: []}
for s in "AB":
    for l in open(f"out/tt3/o0_{s}.jsonl"):
        r = json.loads(l)
        if not r.get("hit"): continue
        z = np.load(f"out/tt3/logs_o0/{r['seed']}.npz"); L = z["L"]; k = int(z["contact"])
        if k < 20: continue
        xh = L[k, 7] # pad centre x at the contact row
        ref = intercept(L[k - 1, 1:4], L[k - 1, 4:7], xh, True)
        if ref is None: continue
        for lead in res:
            j = k - 1 - int(round(lead / 0.01))
            pr = intercept(L[j, 1:4], L[j, 4:7], xh, True)
            if pr is not None:
                res[lead].append([(pr[0] + L[j, 0]) - (ref[0] + L[k - 1, 0]), pr[1] - ref[1], pr[2] - ref[2]])
for lead, v in res.items():
    v = np.array(v)
    print(f"lead {lead:.2f} s: n {len(v)}  crossing-time error sd {1000*v[:,0].std():.1f} ms, lateral y error sd {100*v[:,1].std():.2f} cm (mean {100*v[:,1].mean():+.2f}), height z error sd {100*v[:,2].std():.2f} cm (mean {100*v[:,2].mean():+.2f})")
