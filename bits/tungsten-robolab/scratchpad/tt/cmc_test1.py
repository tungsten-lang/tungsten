import os, sys, json, glob, warnings, time
warnings.filterwarnings("ignore")
os.environ["TT_ENV"]="P2"
sys.path.insert(0,"playground"); sys.path.insert(0,"playground/tasks")
import numpy as np
import tt_fast
from tasks.myo_tt import MyoTTTask
import tt_cmc
# target posture: mean contact-time joint angles of the champion's forehand hits (logs X[:,0:7])
rows={json.loads(l)["seed"]:json.loads(l) for l in open("out/tt_r10/champ_710000_inst.jsonl")}
Q=[]
for f in glob.glob("out/tt_r10/champ_logs/*.npz"):
    seed=int(f.split("/")[-1].split(".")[0]); r=rows.get(seed)
    if r is None or r["side"]!=1 or not r.get("hit"): continue
    z=np.load(f); k=int(z["contact"]); Q.append(z["X"][k-1,0:7])
qt=np.array(Q).mean(0); print("target posture (mean champion contact angles):",qt.round(3))
params=tt_fast.read_params("params/myo_tt_p2_r5_bhprac.txt")
ctl=os.path.abspath("bin/champions/tt_p2_300-20260927-194659")
P=json.load(open("out/tt_r10/pools_740000.json"))
seeds=P["fh"][:int(sys.argv[1]) if len(sys.argv)>1 else 3]
for seed in seeds:
    task=MyoTTTask()
    state={}
    def plan(t,sim):
        if "q0" not in state:
            state["q0"]=np.array([sim.d.qpos[a] for a in sim.cmc.qadr])
        return tt_cmc.min_jerk(state["q0"],qt,0.30,t-0.05)
    sim=tt_cmc.CMCSim(task,params=params,controller=ctl,seed=seed,plan=plan,cmc_kw=dict(kp=400,kd=40,ki=20,a0=0.03))
    t0=time.time(); res=sim.run()
    L=np.array(sim.tt_log); tt=L[:,0]
    print("seed",seed,"solved",res["solved"],"hit",res["hit"],"wall %.1fs"%(time.time()-t0),"t_contact",res.get("t_contact"))
    # tracking error at some times: from cmc.last only final; recompute using recorded joints not stored: print last
    for tq in (0.05,0.1,0.2,0.3,0.4,0.5):
        i=int(np.argmin([abs(x[0]-tq) for x in sim.cmc_log]))
        x=sim.cmc_log[i]
        print("   t %.2f e %s | alloc resid %s | mean act %.2f"%(x[0],x[1].round(3),np.abs(x[2]).max().round(2),x[3]))
