import numpy as np, glob, json, sys
np.set_printoptions(precision=3,suppress=True,linewidth=160)
files=sorted(glob.glob("out/tt_r10/champ_logs/*.npz"))
V=[];PV=[];K=[];side=[]
rows={json.loads(l)["seed"]:json.loads(l) for l in open("out/tt_r10/champ_710000.jsonl")}
data=[]
for f in files:
    z=np.load(f)
    L=z["L"];X=z["X"];k=int(z["contact"])
    seed=int(f.split("/")[-1].split(".")[0])
    if k<12: continue
    t=L[:,0]; pad=L[:,7:10]; pel=L[:,16:19]; nrm=L[:,13:16]
    dt=np.diff(t)
    vpad=np.diff(pad,axis=0)/dt[:,None]        # vpad[j] is the velocity over step j->j+1 (index j corresponds to row j+1)
    vpel=np.diff(pel,axis=0)/dt[:,None]
    data.append((seed,k,t,vpad,vpel,pad,pel,nrm,X,rows[seed]))
print("episodes with contact",len(data))
# velocity at contact (row k-1 convention as the metrics: vw=(pad[kk]-pad[kk-1])/dt with kk=k-1) -> vpad[k-2]
def vat(d,row):   # velocity estimate ending at row `row` (row>=1)
    return d[3][row-1]
res={}
for lag in [1,2,3,5,8,12]:
    err=[];sp=[]
    for d in data:
        k=d[1]; kk=k-1
        v_c=vat(d,kk)          # the metric's velocity at contact
        v_e=vat(d,kk-lag)      # earlier
        err.append(v_c-v_e); sp.append(v_c)
    err=np.array(err); sp=np.array(sp)
    print("pad velocity change from %d ms before to the contact sample: rms per component %s ; contact-sample std %s"%(lag*10,np.sqrt((err**2).mean(0)),sp.std(0)))
# pelvis contribution
rel=[];pv=[];pp=[]
for d in data:
    k=d[1]; kk=k-1
    vpa=vat(d,kk); vpe=d[4][kk-1]
    rel.append(vpa-vpe); pv.append(vpe); pp.append(vpa)
rel=np.array(rel);pv=np.array(pv);pp=np.array(pp)
print("pad velocity at contact: mean %s std %s"%(pp.mean(0),pp.std(0)))
print("pelvis velocity at contact: mean %s std %s"%(pv.mean(0),pv.std(0)))
print("pad minus pelvis (arm+trunk relative): mean %s std %s"%(rel.mean(0),rel.std(0)))
# normal components
nn=[];pn=[];pl=[];rl=[]
for d,(vpa,vpe,rr) in zip(data,zip(pp,pv,rel)):
    n=d[7][d[1]-1]; n=n*np.sign(n[0]) # +x oriented
    nn.append(n); pn.append(vpa@n); pl.append(vpe@n); rl.append(rr@n)
pn=np.array(pn);pl=np.array(pl);rl=np.array(rl)
print("velocity along the pad axis (+x oriented; + = retreating):  pad %.2f +- %.2f | pelvis part %.2f +- %.2f | arm/trunk part %.2f +- %.2f"%(pn.mean(),pn.std(),pl.mean(),pl.std(),rl.mean(),rl.std()))
# by side
sd=np.array([d[9]["side"] for d in data])
for s in (1,2):
    m=sd==s
    print(" side",s,"pad vel along axis %.2f +- %.2f, pelvis %.2f +- %.2f, arm %.2f +- %.2f ; pelvis vx %.2f+-%.2f vy %.2f+-%.2f"%(pn[m].mean(),pn[m].std(),pl[m].mean(),pl[m].std(),rl[m].mean(),rl[m].std(),pv[m][:,0].mean(),pv[m][:,0].std(),pv[m][:,1].mean(),pv[m][:,1].std()))
# joint velocities at contact: arm still moving?
qd=np.array([d[8][d[1]-1][12:20] for d in data])   # servo joint rates at contact row
print("servo joint speeds |qd| at contact (rad/s) median:",np.median(np.abs(qd),axis=0))
# acceleration of the pad near contact
acc=[]
for d in data:
    k=d[1]; kk=k-1
    a=(vat(d,kk)-vat(d,kk-1))/0.01
    acc.append(a)
acc=np.array(acc); print("pad acceleration in the last step (m/s^2): rms per comp",np.sqrt((acc**2).mean(0)))
