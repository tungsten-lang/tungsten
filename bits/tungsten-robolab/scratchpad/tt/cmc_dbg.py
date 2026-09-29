import os, sys, json, warnings
warnings.filterwarnings("ignore")
os.environ["TT_ENV"]="P2"
sys.path.insert(0,"playground"); sys.path.insert(0,"playground/tasks")
import numpy as np, mujoco
import tt_fast
from tasks.myo_tt import MyoTTTask
import tt_cmc
params=tt_fast.read_params("params/myo_tt_p2_r5_bhprac.txt")
ctl=os.path.abspath("bin/champions/tt_p2_300-20260927-194659")
task=MyoTTTask()
sim=tt_cmc.CMCSim(task,params=params,controller=ctl,seed=740000,plan=None)
c=tt_cmc.ArmCMC(sim)
mujoco.mj_forward(sim.m,sim.d)
F=c.fold(sim.d)
mujoco.mj_fullM(sim.m,c.Mfull,sim.d.qM)
Maa=F.T@c.Mfull@F
print("Maa diag",np.diag(Maa).round(3))
print("bias_a",(F.T@sim.d.qfrc_bias).round(2))
print("passive_a",(F.T@sim.d.qfrc_passive).round(2))
g,b,R=c.muscle_terms(sim.d); R=R@F
print("gain range",g.min().round(1),g.max().round(1),"bias range",b.min().round(1),b.max().round(1))
G=R.T*g[None,:]
print("max torque per joint at full activation (sum of |G|):",np.abs(G).sum(1).round(1))
print("max signed torque +,- per joint:",np.clip(G,0,None).sum(1).round(1),np.clip(G,None,0).sum(1).round(1))
print("passive muscle torque R^T b:",(R.T@b).round(2))
print("moment arms R (m/rad) row norms:",np.abs(R).max(0).round(3))
