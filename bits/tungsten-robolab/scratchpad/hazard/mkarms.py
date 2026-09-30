"""mkarms.py OUT.json SECONDS a:b arm [arm ...]     arm = name@params@controller[@k=v,k=v]   (one job per arm x seed; tag = name|seed)"""
import json, sys
out, secs, rng = sys.argv[1:4]
lo, hi = rng.split(":")
jobs = []
for spec in sys.argv[4:]:
    parts = spec.split("@")
    name, params, ctl = parts[:3]
    st = {}
    if len(parts) > 3 and parts[3]:
        for kv in parts[3].split(","):
            k, v = kv.split("=")
            st[k] = float(v)
    for s in range(int(lo), int(hi)):
        jobs.append({"tag": f"{name}|{s}", "seed": s, "params": params, "controller": ctl, "seconds": float(secs), "set": st})
json.dump(jobs, open(out, "w"))
print(len(jobs), "jobs ->", out)
