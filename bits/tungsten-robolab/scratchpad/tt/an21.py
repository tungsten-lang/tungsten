import numpy as np, glob, json, sys
np.set_printoptions(precision=2,suppress=True,linewidth=220)
jsonl,logdir=sys.argv[1],sys.argv[2]
rows={json.loads(l)["seed"]:json.loads(l) for l in open(jsonl)}
cnt={1:0,2:0}
for f in sorted(glob.glob(logdir+"/*.npz")):
    seed=int(f.split("/")[-1].split(".")[0]); r=rows.get(seed)
    if r is None or not r.get("hit"): continue
    s=r["side"]
    if cnt[s]>=5: continue
    cnt[s]+=1
    z=np.load(f); L=z["L"]; k=int(z["contact"]); t=L[:,0]; pel=L[:,16:19]
    vx=np.diff(pel[:,0])/np.diff(t)
    sp=np.linalg.norm(r["ball_in_exact"]); u=np.clip(0.47*(sp-4.83),0,1.2)
    idx=np.arange(0,k,4)
    print("side",s,"seed",seed,"k",k,"ball speed %.2f planned u %.2f solved %d"%(sp,u,r["solved"]>0))
    print("   t   :",t[idx])
    print("   x   :",pel[idx,0])
    print("   vx  :",np.r_[0,vx][idx])
