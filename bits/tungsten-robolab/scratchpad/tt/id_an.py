import numpy as np, glob, json, sys, os
np.set_printoptions(precision=3,suppress=True,linewidth=170)
def orient(n):
    n=np.asarray(n,float); return n*np.sign(n[...,0:1]+1e-12)
def pose(tag):
    rows={json.loads(l)["seed"]:json.loads(l) for l in open(f"out/tt_r10/{tag}.jsonl")}
    out={}
    for f in glob.glob(f"out/tt_r10/{tag}_logs/*.npz"):
        seed=int(f.split("/")[-1].split(".")[0]); r=rows.get(seed)
        if r is None: continue
        z=np.load(f); L=z["L"]; t=L[:,0]; ball=L[:,1:4]; pad=L[:,7:10]; nrm=orient(L[:,13:16]); pel=L[:,16:19]
        d=np.linalg.norm(ball-pad,axis=1); k=int(np.argmin(d))
        out[seed]=np.array([np.degrees(np.arcsin(nrm[k,2])),np.degrees(np.arctan2(nrm[k,1],nrm[k,0])),pad[k,2],ball[k,2]-pad[k,2],ball[k,1]-pad[k,1],pad[k,0],t[k],float(r["solved"]>0),float(r["hit"]>0)])
    return out
names=["pitch","yaw","pad_z","dz(ball-pad)","dy","pad_x","t","solved","hit"]
tags=sys.argv[1:]
P0=pose(tags[0]); common=sorted(P0)
for tg in tags[1:]:
    common=[s for s in common if s in pose(tg)]
print("n common seeds",len(common))
def mean(tag):
    P=pose(tag); return np.array([P[s] for s in common]).mean(0), np.array([P[s] for s in common]).std(0)
m0,s0=mean(tags[0])
print("%-10s"%tags[0]," ".join("%s %.3f"%(n,v) for n,v in zip(names,m0)), "| sd pitch %.1f yaw %.1f z %.3f dz %.3f"%(s0[0],s0[1],s0[2],s0[3]))
for tg in tags[1:]:
    m,s=mean(tg)
    print("%-10s"%tg," ".join("%s %+.3f"%(n,v) for n,v in zip(names,m-m0)),"| sd pitch %.1f dz %.3f"%(s[0],s[3]))
