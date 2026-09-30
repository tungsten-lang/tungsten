"""mkknee.py OUT.json SECONDS a:b BASE_PARAMS CONTROLLER TFROM name v1,v2,..   sweep of ONE parameter with the all-segment window starting at TFROM (envvar WSCAN_TFROM)"""
import json, sys
out, secs, rng, base, ctl, tfrom, name, vals = sys.argv[1:9]
lo, hi = rng.split(":")
jobs = []
for v in vals.split(","):
    for s in range(int(lo), int(hi)):
        jobs.append({"tag": f"{name}={v}|{s}", "seed": s, "params": base, "controller": ctl, "seconds": float(secs), "set": {name: float(v)}, "envvars": {"WSCAN_TFROM": tfrom}})
json.dump(jobs, open(out, "w"))
print(len(jobs), "jobs ->", out)
