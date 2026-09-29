import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
from practice import load_task, read_params
from bridge import Sim
import numpy as np
class R:
    def __init__(s): s.rows=[]
    def maybe_capture(s, sim):
        m,d=sim.m,sim.d; ct=sim.contacts(); pid=m.body("pelvis").id
        s.rows.append((d.time, ct["r_foot"], d.body("r_foot").xpos[0]-d.subtree_com[pid][0], d.subtree_linvel[pid][2], d.subtree_linvel[pid][0], d.body("pelvis").xpos[2], d.subtree_com[pid][2]))
args = sys.argv[1:]
task, par = args[0], args[1]; ctl = args[2] if len(args) > 2 else None
t=load_task(task); t.seed=None
sim=Sim(t, params=read_params(par) if par != "-" else {}, controller=ctl); r=R(); res=sim.run(float(os.environ.get("SECS", "12")), recorder=r)
A=np.array(r.rows); on=A[:,1]>0.05; T0=float(os.environ.get("T0", "6"))
idx=[k for k in range(1,len(A)) if on[k] and not on[k-1] and A[k,0]>T0]
offs=[k for k in range(1,len(A)) if (not on[k]) and on[k-1] and A[k,0]>T0]
print(task, res.get("time"), "TD foot-COM x %.3f vz %.2f vx %.2f pelvis_z %.3f com_z %.3f" % tuple(np.mean(A[idx][:, [2,3,4,5,6]],axis=0)),
      "| TO foot-COM x %.3f vz %.2f" % tuple(np.mean(A[offs][:, [2,3]],axis=0)))
