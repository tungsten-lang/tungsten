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
class Probe(tt_cmc.CMCSim):
    def tick(self):
        act,c=super().tick()
        if abs(self.d.time-0.40)<0.005 and not hasattr(self,"_probed"):
            self._probed=True
            m,d=self.m,self.d
            F=self.cmc.fold(d)
            mom=np.zeros((m.nu,m.nv)); mujoco.mju_sparse2dense(mom,d.actuator_moment,d.moment_rownnz,d.moment_rowadr,d.moment_colind)
            hand=[m.actuator(n).id for n in ("FDS5","FDS4","FDS3","FDS2","FDP5","FDP4","FDP3","FDP2","EDC5","EDC4","EDC3","EDC2","EDM","EIP","EPL","EPB","FPL","APL","OP")]
            armids=self.cmc.act_ids
            def tq(ids):
                f=d.actuator_force[ids]; return (F.T@(mom[ids].T@f))
            print("t=0.40 joint torques (N m) [elv_angle sh_elv sh_rot elbow pro_sup dev flex]")
            print("  arm muscles     ",tq(armids).round(2))
            print("  finger muscles  ",tq(hand).round(2))
            print("  hand activations (ctrl) mean %.2f max %.2f"%(d.ctrl[hand].mean(),d.ctrl[hand].max()))
            print("  joint angles",np.array([d.qpos[a] for a in self.cmc.qadr]).round(3))
            print("  qfrc_constraint (folded)",(F.T@d.qfrc_constraint).round(2))
        return act,c
sim=Probe(task,params=params,controller=ctl,seed=740000,plan=None)
r=sim.run(); print("steps",r["steps"],"time",r["time"],"hit",r["hit"])
