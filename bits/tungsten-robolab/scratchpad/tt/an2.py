import json, sys, numpy as np
sys.path.insert(0,"playground")
import tt_impact as ti
rows=[json.loads(l) for l in open(sys.argv[1])]
rows=[r for r in rows if "error" not in r]
hits=[r for r in rows if r.get("hit") and r.get("ball_out_exact") and r.get("paddle_vel")]
np.set_printoptions(precision=2,suppress=True)
for r in hits[:14]:
    vin=np.array(r["ball_in_exact"]); vp=np.array(r["paddle_vel"]); n=np.array(r["pad_normal"]); vout=np.array(r["ball_out_exact"])
    pred=ti.impact(vin,vp,n,1.0,0.0)
    print(r["seed"],"side",r["side"],"solved",r["solved"],"t",r["t_contact"],"landed",r.get("landed"),"miss",r["miss_dist"],"\n   vin",vin,"vp",vp,"n",n,"\n   vout",vout,"pred",pred,"|res|",np.linalg.norm(vout-pred).round(2), "speed in/out",np.linalg.norm(vin).round(2),np.linalg.norm(vout).round(2))
