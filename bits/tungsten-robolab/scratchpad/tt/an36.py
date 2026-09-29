import numpy as np, glob, json, sys
sys.path.insert(0,"playground")
np.set_printoptions(precision=3,suppress=True,linewidth=160)
def orient(n):
    n=np.asarray(n,float); return n*np.sign(n[...,0:1]+1e-12)
def stats(jsonl,logdir,side=1):
    rows={json.loads(l)["seed"]:json.loads(l) for l in open(jsonl)}
    out=[]
    for f in sorted(glob.glob(logdir+"/*.npz")):
        seed=int(f.split("/")[-1].split(".")[0]); r=rows.get(seed)
        if r is None or r["side"]!=side: continue
        z=np.load(f); k=int(z["contact"]); L=z["L"]; t=L[:,0]; pad=L[:,7:10]; nrm=orient(L[:,13:16])
        if k<30: 
            kk=len(t)-1
        else: kk=k-1
        def at(tt): return int(np.argmin(np.abs(t-tt)))
        rec={"seed":seed,"solved":r["solved"]>0,"hit":r["hit"]>0}
        for tt in (0.27,0.4):
            i=min(at(tt),kk); rec["p%.2f"%tt]=np.degrees(np.arcsin(nrm[i,2])); rec["z%.2f"%tt]=pad[i,2]
        rec["pc"]=np.degrees(np.arcsin(nrm[kk,2])); rec["zc"]=pad[kk,2]
        rec["yc"]=np.degrees(np.arctan2(nrm[kk,1],nrm[kk,0]))
        out.append(rec)
    return out
for name,(j,d) in {"champion":("out/tt_r10/champ_710000_inst.jsonl","out/tt_r10/champ_logs"),"ffz":("out/tt_r10/v_ffz.jsonl","out/tt_r10/v_ffz_logs")}.items():
    D=stats(j,d)
    D=[x for x in D if x["seed"]<710120]
    print(name,"forehand n",len(D),"solved %.2f"%np.mean([x["solved"] for x in D]))
    for key in ("p0.27","p0.40","pc","yc","z0.27","z0.40","zc"):
        v=np.array([x[key] for x in D]); print("   %-6s mean %.3f sd %.3f"%(key,v.mean(),v.std()))

print("==== backhand pose time course (champion, instrumented)")
def stats2(jsonl,logdir,side):
    rows={json.loads(l)["seed"]:json.loads(l) for l in open(jsonl)}
    out=[]
    for f in sorted(glob.glob(logdir+"/*.npz")):
        seed=int(f.split("/")[-1].split(".")[0]); r=rows.get(seed)
        if r is None or r["side"]!=side: continue
        z=np.load(f); k=int(z["contact"]); L=z["L"]; t=L[:,0]; pad=L[:,7:10]; nrm=orient(L[:,13:16])
        kk=k-1 if k>=30 else len(t)-1
        rec={"tc":t[kk]}
        for tt in (0.1,0.2,0.3,0.4,0.45):
            i=int(np.argmin(np.abs(t-tt)))
            if i<=kk: rec[tt]=(np.degrees(np.arcsin(nrm[i,2])),np.degrees(np.arctan2(nrm[i,1],nrm[i,0])),pad[i,2],pad[i,1])
        rec["c"]=(np.degrees(np.arcsin(nrm[kk,2])),np.degrees(np.arctan2(nrm[kk,1],nrm[kk,0])),pad[kk,2],pad[kk,1])
        # angular rates over the last 30 ms
        i0=max(kk-3,0)
        rec["rate"]=(np.degrees(np.arcsin(nrm[kk,2])-np.arcsin(nrm[i0,2]))/(t[kk]-t[i0]),np.degrees(np.arctan2(nrm[kk,1],nrm[kk,0])-np.arctan2(nrm[i0,1],nrm[i0,0]))/(t[kk]-t[i0]))
        out.append(rec)
    return out
for side in (1,2):
    D=stats2("out/tt_r10/champ_710000_inst.jsonl","out/tt_r10/champ_logs",side)
    print("side",side,"n",len(D))
    for key in (0.1,0.2,0.3,0.4,0.45,"c"):
        v=np.array([d[key] for d in D if key in d])
        print("   t=%s: pitch %.1f+-%.1f | yaw %.1f+-%.1f | pad z %.3f+-%.3f | pad y %.3f+-%.3f"%(key,v[:,0].mean(),v[:,0].std(),v[:,1].mean(),v[:,1].std(),v[:,2].mean(),v[:,2].std(),v[:,3].mean(),v[:,3].std()))
    rt=np.array([d["rate"] for d in D]); print("   face angular rate over the last 30 ms (deg/s): pitch %.0f+-%.0f | yaw %.0f+-%.0f ; median |rate| %.0f / %.0f"%(rt[:,0].mean(),rt[:,0].std(),rt[:,1].mean(),rt[:,1].std(),np.median(np.abs(rt[:,0])),np.median(np.abs(rt[:,1]))))
