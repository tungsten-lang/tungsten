"""mksweep.py OUT.json SECONDS a:b BASE_PARAMS CONTROLLER name=v1,v2,.. [name=..]   one-at-a-time sweep (plus the baseline)
tag = <group>|<name>=<value>|<seed>;  the baseline group is 'base'."""
import json, sys
out, secs, rng, base, ctl = sys.argv[1:6]
lo, hi = rng.split(":")
axes = [a.split("=") for a in sys.argv[6:]]
cfgs = [("base", {})]
for nm, vals in axes:
    for v in vals.split(","):
        cfgs.append((f"{nm}={v}", {nm: float(v)}))
jobs = []
for tag, st in cfgs:
    for s in range(int(lo), int(hi)):
        jobs.append({"tag": f"{tag}|{s}", "seed": s, "params": base, "controller": ctl, "seconds": float(secs), "set": st})
json.dump(jobs, open(out, "w"))
print(len(cfgs), "configs,", len(jobs), "jobs ->", out)
