import numpy as np, glob, json, sys
sys.path.insert(0,"playground")
import tt_impact as ti
np.set_printoptions(precision=3,suppress=True,linewidth=160)
rows={json.loads(l)["seed"]:json.loads(l) for l in open("out/tt_r10/champ_710000_inst.jsonl")}
def orient(n):
    n=np.asarray(n,float); return n*np.sign(n[...,0:1]+1e-12)
D=[]
for f in sorted(glob.glob("out/tt_r10/champ_logs/*.npz")):
    seed=int(f.split("/")[-1].split(".")[0]); r=rows.get(seed)
    z=np.load(f); k=int(z["contact"])
    if r is None or k<30 or r["side"]!=1: continue
    L=z["L"]; t=L[:,0]; pad=L[:,7:10]; nrm=orient(L[:,13:16]); pel=L[:,16:19]; aim=z["aim"]
    def at(tt):
        i=int(np.argmin(np.abs(t-tt))); return i
    kk=k-1
    row={}
    for tt in (0.2,0.27,0.35,0.42):
        i=at(tt)
        if i<kk: 
            row[tt]=(np.degrees(np.arcsin(nrm[i,2])),pad[i,2],np.degrees(np.arctan2(nrm[i,1],nrm[i,0])),pad[i,1]-pel[i,1])
    row["c"]=(np.degrees(np.arcsin(nrm[kk,2])),pad[kk,2],np.degrees(np.arctan2(nrm[kk,1],nrm[kk,0])),pad[kk,1]-pel[kk,1])
    D.append((seed,r,row,k))
print("forehand episodes",len(D))
for tt in (0.2,0.27,0.35,0.42,"c"):
    v=np.array([d[2][tt] for d in D if tt in d[2]])
    print("t=%s: pad pitch mean %.1f sd %.1f | pad z mean %.3f sd %.3f | yaw mean %.1f sd %.1f | pad-pel y mean %.3f sd %.3f"%(tt,v[:,0].mean(),v[:,0].std(),v[:,1].mean(),v[:,1].std(),v[:,2].mean(),v[:,2].std(),v[:,3].mean(),v[:,3].std()))
# how much of the contact pitch is set by the pitch at 0.27, 0.35, 0.42?
pc=np.array([d[2]["c"][0] for d in D])
for tt in (0.2,0.27,0.35,0.42):
    p=np.array([d[2][tt][0] if tt in d[2] else np.nan for d in D]); m=~np.isnan(p)
    A=np.c_[np.ones(m.sum()),p[m]]; c=np.linalg.lstsq(A,pc[m],rcond=None)[0]
    print("contact pitch vs pitch at t=%.2f: slope %.2f corr %.2f"%(tt,c[1],np.corrcoef(p[m],pc[m])[0,1]))
# contact time vs pitch at contact and pitch change over the servo phase
tc=np.array([d[1]["t_contact"] for d in D]); 
print("corr(contact pitch, t_contact)=%.2f ; corr(pitch@0.27, t_contact)=%.2f"%(np.corrcoef(pc,tc)[0,1],np.corrcoef([d[2][0.27][0] for d in D],tc)[0,1]))
