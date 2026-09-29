import numpy as np, glob, json, sys
np.set_printoptions(precision=3,suppress=True,linewidth=160)
sys.path.insert(0,"scratchpad/tt")
def load(jsonl,logdir):
    rows={}
    for l in open(jsonl):
        r=json.loads(l); rows[r["seed"]]=r
    out=[]
    for f in glob.glob(logdir+"/*.npz"):
        seed=int(f.split("/")[-1].split(".")[0])
        if seed not in rows: continue
        z=np.load(f); k=int(z["contact"])
        if k<12: continue
        L=z["L"]; t=L[:,0]; pad=L[:,7:10]; pel=L[:,16:19]; nrm=L[:,13:16]; X=z["X"]
        vpad=np.diff(pad,axis=0)/np.diff(t)[:,None]; vpel=np.diff(pel,axis=0)/np.diff(t)[:,None]
        kk=k-1; n=nrm[kk]; n=n*np.sign(n[0])
        out.append(dict(seed=seed,side=rows[seed]["side"],vpad=vpad[kk-1],vpel=vpel[kk-1],n=n,solved=rows[seed]["solved"]>0,X=X[kk],k=k,row=rows[seed]))
    return out
for name,(j,d) in {"champion":("out/tt_r10/champ_710000_inst.jsonl","out/tt_r10/champ_logs"),"t_lock 0.10":("out/tt_r10/v_tlock10.jsonl","out/tt_r10/v_tlock10_logs")}.items():
    D=load(j,d)
    print("==",name,len(D))
    for s in (1,2):
        m=[x for x in D if x["side"]==s]
        pad_n=np.array([x["vpad"]@x["n"] for x in m]); pel_n=np.array([x["vpel"]@x["n"] for x in m]); arm_n=pad_n-pel_n
        print(" side",s,"n",len(m),"| pad %.2f+-%.2f | pelvis %.2f+-%.2f | arm %.2f+-%.2f | corr(pelvis,arm)=%.2f"%(pad_n.mean(),pad_n.std(),pel_n.mean(),pel_n.std(),arm_n.mean(),arm_n.std(),np.corrcoef(pel_n,arm_n)[0,1]))
        qd=np.array([x["X"][12:22] for x in m])
        print("   median |joint speed| at contact (elv_angle, sh_elv, sh_rot, elbow, pro_sup, dev, flex, ax_rot, trunk_fe, trunk_lb):",np.median(np.abs(qd),axis=0))
