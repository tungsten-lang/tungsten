import numpy as np, glob, json, sys
np.set_printoptions(precision=3,suppress=True,linewidth=160)
def load(jsonl,logdir):
    rows={}
    for l in open(jsonl):
        r=json.loads(l); rows[r["seed"]]=r
    out={}
    for f in glob.glob(logdir+"/*.npz"):
        seed=int(f.split("/")[-1].split(".")[0])
        if seed not in rows: continue
        z=np.load(f); k=int(z["contact"])
        if k<12: continue
        L=z["L"]; t=L[:,0]; pad=L[:,7:10]; pel=L[:,16:19]; nrm=L[:,13:16]
        vpad=np.diff(pad,axis=0)/np.diff(t)[:,None]; vpel=np.diff(pel,axis=0)/np.diff(t)[:,None]
        kk=k-1
        n=nrm[kk]; n=n*np.sign(n[0])
        out[seed]=dict(k=k,vpad=vpad[kk-1],vpel=vpel[kk-1],n=n,row=rows[seed],vpel_hist=vpel[max(kk-12,0):kk],X=z["X"])
    return out
A=load(sys.argv[1],sys.argv[2])
print("episodes with contact",len(A))
for s in (1,2):
    d=[v for v in A.values() if v["row"]["side"]==s]
    if not d: continue
    pn=np.array([v["vpad"]@v["n"] for v in d]); pl=np.array([v["vpel"]@v["n"] for v in d])
    px=np.array([v["vpad"][0] for v in d]); pex=np.array([v["vpel"][0] for v in d])
    sp=np.array([np.linalg.norm(v["row"]["ball_in_exact"]) for v in d])
    print("side",s,"n",len(d),": pad vel along axis %.2f +- %.2f ; pelvis part %.2f +- %.2f ; pelvis vx %.2f +- %.2f"%(pn.mean(),pn.std(),pl.mean(),pl.std(),pex.mean(),pex.std()))
    # planned u vs ball speed
    u=np.clip(0.47*(sp-4.83),0,1.2)
    print("     corr(pelvis vx, planned u)=%.2f ; mean planned u %.2f ; pelvis vx - u: mean %.2f std %.2f"%(np.corrcoef(pex,u)[0,1],u.mean(),(pex-u).mean(),(pex-u).std()))
d=list(A.values())
print("overall solved %.3f hit %.3f"%(np.mean([v["row"]["solved"]>0 for v in d]),1.0))
