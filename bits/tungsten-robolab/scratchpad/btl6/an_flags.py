import pickle, sys, collections
import numpy as np
res = pickle.load(open(sys.argv[1], "rb"))
c = collections.Counter(); tot = 0
for sd, r in res.items():
    if len(r["ok"]) < 2 or not (r["ok"][0] and r["ok"][1]): continue
    fl = r["fl"]
    tot += 1
    f2, f3, f4 = fl.get(2), fl.get(3), fl.get(4)
    why = []
    if not f2["touch"]: why.append("2:no_touch")
    elif not f2["bounced"]: why.append("2:no_bounce")
    if f2["pre"]: why.append("2:pre_body")
    if f2["touch"] and f2["bounced"]:
        if not f2["gate"]: why.append("2:no_gate")
        if f2["bfl"]: why.append("2:body_flight")
        if f3 is None or not f3["touch"]: why.append("3:no_touch")
        elif not f3["bounced"]: why.append("3:no_bounce")
    c[tuple(why) if why else ("v3 ok",)] += 1
print("active starts", tot)
for k, v in sorted(c.items(), key=lambda kv: -kv[1])[:12]: print(v, k)
print("---- given v3 ok: reasons v4 fails")
c = collections.Counter(); tot = 0
for sd, r in res.items():
    if r["v3"] <= 0 or len(r["ok"]) < 3: continue
    fl = r["fl"]; f3, f4 = fl.get(3), fl.get(4)
    tot += 1
    why = []
    if not f3["gate"]: why.append("3:no_gate")
    if f3["bfl"]: why.append("3:body_flight")
    if f4 is None or not f4["touch"]: why.append("4:no_touch")
    elif not f4["bounced"]: why.append("4:no_bounce")
    c[tuple(why) if why else ("v4 ok",)] += 1
print("v3-ok starts", tot)
for k, v in sorted(c.items(), key=lambda kv: -kv[1])[:10]: print(v, k)
