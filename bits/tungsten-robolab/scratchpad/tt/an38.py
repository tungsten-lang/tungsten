import numpy as np, glob, json, sys
np.set_printoptions(precision=3,suppress=True,linewidth=160)
def orient(n):
    n=np.asarray(n,float); return n*np.sign(n[...,0:1]+1e-12)
def course(tag,side=1):
    logdir="out/tt_r10/champ_logs" if tag=="champ_710000_inst" else f"out/tt_r10/{tag}_logs"
    rows={json.loads(l)["seed"]:json.loads(l) for l in open(f"out/tt_r10/{tag}.jsonl")}
    out=[]
    for f in sorted(glob.glob(logdir+"/*.npz")):
        seed=int(f.split("/")[-1].split(".")[0]); r=rows.get(seed)
        if r is None or r["side"]!=side or not r.get("hit"): continue
        z=np.load(f); k=int(z["contact"]); L=z["L"]; t=L[:,0]; pad=L[:,7:10]; ball=L[:,1:4]; nrm=orient(L[:,13:16])
        kk=k-1
        rec={}
        for tt in (0.2,0.27,0.35,0.42):
            i=min(int(np.argmin(np.abs(t-tt))),kk); rec[tt]=(pad[i,2],np.degrees(np.arcsin(nrm[i,2])))
        rec["c"]=(pad[kk,2],np.degrees(np.arcsin(nrm[kk,2])),ball[kk,2]-pad[kk,2])
        out.append(rec)
    return out
for tag in sys.argv[1:]:
    D=course(tag)
    print(tag,"forehand hits",len(D))
    for key in (0.2,0.27,0.35,0.42):
        v=np.array([d[key] for d in D]); print("   t=%.2f: pad z %.3f +- %.3f | pitch %.1f +- %.1f"%(key,v[:,0].mean(),v[:,0].std(),v[:,1].mean(),v[:,1].std()))
    v=np.array([d["c"] for d in D]); print("   contact: pad z %.3f +- %.3f | pitch %.1f +- %.1f | ball-pad z %.3f +- %.3f"%(v[:,0].mean(),v[:,0].std(),v[:,1].mean(),v[:,1].std(),v[:,2].mean(),v[:,2].std()))
