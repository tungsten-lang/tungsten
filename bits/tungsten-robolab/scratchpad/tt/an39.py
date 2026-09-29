import json, sys, collections
sys.path.insert(0,"playground"); sys.path.insert(0,"playground/tasks")
from tasks.myo_tt import failure_class
def load(p):
    return {json.loads(l)["seed"]:json.loads(l) for l in open(p)}
tags=sys.argv[1:]
data={t:load(f"out/tt_r10/{t}.jsonl") for t in tags}
seeds=sorted(set.intersection(*[set(d) for d in data.values()]))
seeds=[s for s in seeds if s<710120] if any("710000" in t or t.startswith("v_") for t in tags) else seeds
for side,nm in ((1,"forehand"),(2,"backhand")):
    print(nm)
    for t,d in data.items():
        c=collections.Counter(failure_class(d[s]) for s in seeds if d[s]["side"]==side)
        n=sum(c.values())
        print("  %-22s n %d : "%(t,n)+", ".join("%s %d"%(k.replace("miss: ","m:").replace("hit: ","h:"),v) for k,v in sorted(c.items(),key=lambda x:-x[1])))
