"""foot_geom.py PARAMS CTL SEED T...: world geometry of the left foot / shank / pelvis at the given times (labelled beyond-human body)."""
import math, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
os.environ["ROBOLAB_CALIB"] = "v4"; os.environ["ROBOLAB_PROFILE"] = "beyond"; os.environ["ROBOLAB_PROFILE_PARTS"] = "strength,speed,tendon,activation"
sys.path.insert(0, os.path.join(ROOT, "playground"))
import mujoco, numpy as np
from practice import load_task, read_params
from bridge import Sim
args=[a for a in sys.argv[1:] if not a.startswith("--")]
opts={a.split("=")[0]:a.split("=",1)[1] for a in sys.argv[1:] if a.startswith("--") and "=" in a}
params=read_params(args[0]); ctl=args[1]; seed=int(args[2]); times=[float(x) for x in args[3:]]
for kv in opts.get("--set","").split(","):
    if kv: k,v=kv.split("="); params[k]=float(v)
class R:
    def __init__(s): s.i=0
    def maybe_capture(s, sim):
        d,m=sim.d,sim.m
        if s.i>=len(times) or d.time<times[s.i]: return
        s.i+=1
        pid=m.body("pelvis").id
        def pitch(b):
            R_=d.xmat[m.body(b).id].reshape(3,3); return math.degrees(math.atan2(R_[0,2],R_[2,2]))  # tilt of the body's z axis toward +x
        fg=m.geom("l_foot").id
        # foot box corners in world
        R_=d.geom_xmat[fg].reshape(3,3); c=d.geom_xpos[fg]; sz=m.geom_size[fg]
        corners=[]
        for sx in (-1,1):
            for sz_ in (-1,1):
                p=c+R_@np.array([sx*sz[0],0,sz_*sz[2]]); corners.append(p)
        low=min(corners,key=lambda p:p[2]); 
        heel=min([p for p in corners if p[0]<c[0]], key=lambda p:p[2]); toe=min([p for p in corners if p[0]>c[0]], key=lambda p:p[2])
        ank=d.body("l_foot").xpos; knee=d.body("l_shin").xpos
        com=float(d.subtree_com[pid][0])
        print("t=%.2f foot pitch %+.1f deg (z-axis tilt, + = toes DOWN?) shin pitch %+.1f thigh %+.1f pelvis %+.1f torso %+.1f | ankle x=%+.3f z=%.3f; heel corner x=%+.3f z=%.3f; toe corner x=%+.3f z=%.3f | COM-ankle %+.3f COM-heel %+.3f"%(
            d.time,pitch("l_foot"),pitch("l_shin"),pitch("l_thigh"),pitch("pelvis"),pitch("torso"),ank[0]-(-50),ank[2],heel[0]-(-50),heel[2],toe[0]-(-50),toe[2],com-ank[0],com-heel[0]))
t=load_task("run_v4"); t.seed=seed
sim=Sim(t,params=params,controller=os.path.abspath(ctl))
r=R(); res=sim.run(max(times)+0.05,recorder=r)
print("fell",res.get("fell"),res.get("time"))
