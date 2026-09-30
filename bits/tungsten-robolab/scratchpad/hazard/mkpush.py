"""mkpush.py OUT.json SECONDS a:b PUSHES arm [arm ...]   arm = name@params@controller[@k=v,..];  PUSHES = "dir:mag,dir:mag" with dir in {py,ny,px,nx} (world +y / -y / +x / -x), mag in N (0.2 s at t = 6 s on the torso)
tag = <arm>|<push>|<seed>: a STRESS TEST of the hold (not the official environment): survival of the same starts under the same push for each arm."""
import json, sys
out, secs, rng, pushes = sys.argv[1:5]
lo, hi = rng.split(":")
D = {"py": (0, 1), "ny": (0, -1), "px": (1, 0), "nx": (-1, 0)}
jobs = []
for spec in sys.argv[5:]:
    parts = spec.split("@")
    name, params, ctl = parts[:3]
    st = {}
    if len(parts) > 3 and parts[3]:
        for kv in parts[3].split(","):
            k, v = kv.split("="); st[k] = float(v)
    for pu in pushes.split(","):
        d, mag = pu.split(":")
        fx, fy = D[d][0] * float(mag), D[d][1] * float(mag)
        for s in range(int(lo), int(hi)):
            jobs.append({"tag": f"{name}|{d}{mag}|{s}", "seed": s, "params": params, "controller": ctl, "seconds": float(secs), "set": st,
                         "envvars": {"WSCAN_PUSH": f"6.0:0.2:{fx}:{fy}:torso", "WSCAN_TFROM": "3.0"}})
json.dump(jobs, open(out, "w"))
print(len(jobs), "jobs ->", out)
