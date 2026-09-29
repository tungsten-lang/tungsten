import numpy as np, glob, json
np.set_printoptions(precision=3,suppress=True,linewidth=170)
rows={json.loads(l)["seed"]:json.loads(l) for l in open("out/tt_r10/champ_710000_inst.jsonl")}
T={}
for f in sorted(glob.glob("out/tt_r10/champ_logs/*.npz")):
    seed=int(f.split("/")[-1].split(".")[0]); r=rows.get(seed)
    if r is None or r["side"]!=1 or not r.get("hit"): continue
    z=np.load(f); L=z["L"]; A=z["aim"]
    if len(A)==0: continue
    t=L[:,0]; padz=L[:,9]
    for row in A:
        i=int(np.argmin(np.abs(t-row[0])))
        tgt=row[4]+padz[i]      # target pad z = eh + pad z
        T.setdefault(round(row[0],2),[]).append((tgt,padz[i],row[4]))
print("forehand hits: servo target height (plan z + z_bias), pad z, error eh over time")
for k in sorted(T):
    if 0.26<=k<=0.52:
        v=np.array(T[k]); print("t %.2f n %2d | target %.3f +- %.3f | pad %.3f +- %.3f | eh %.3f +- %.3f"%(k,len(v),v[:,0].mean(),v[:,0].std(),v[:,1].mean(),v[:,1].std(),v[:,2].mean(),v[:,2].std()))
