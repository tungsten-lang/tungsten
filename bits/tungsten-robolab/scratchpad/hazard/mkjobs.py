"""Write a guardscan jobs file: mkjobs.py OUT.json SECONDS a:b tag=params:controller [tag=params:controller ...]"""
import json, sys
out, secs, rng = sys.argv[1], float(sys.argv[2]), sys.argv[3]
lo, hi = rng.split(":")
jobs = []
for spec in sys.argv[4:]:
    tag, pc = spec.split("=")
    p, c = pc.split(":")
    for s in range(int(lo), int(hi)):
        jobs.append({"tag": f"{tag}-{s}", "seed": s, "params": p, "controller": c, "seconds": secs})
json.dump(jobs, open(out, "w"), indent=0)
print(len(jobs), "jobs ->", out)
