import json, os, time
os.chdir("/Users/erik/tungsten/bits/tungsten-robolab")
def pending():
    n=0
    for l in open("scratchpad/tt/jobs.jsonl"):
        l=l.strip()
        if not l: continue
        j=json.loads(l)
        if j.get("skip"): continue
        lg=f"out/tt_r10/{j['tag']}.log"
        if not (os.path.exists(lg) and any(x.startswith("{") for x in open(lg))): n+=1
    return n
while pending()>0: time.sleep(10)
time.sleep(15)
open("scratchpad/tt/qd.stop","w").write("stop")
