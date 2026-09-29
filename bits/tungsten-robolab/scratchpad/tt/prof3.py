import os, sys, time
os.environ["TT_ENV"]="P2"
sys.path.insert(0,"/Users/erik/tungsten/bits/tungsten-robolab/playground")
import warnings; warnings.filterwarnings("ignore")
import tt_fast
from tasks.myo_tt import MyoTTTask
params=tt_fast.read_params("/Users/erik/tungsten/bits/tungsten-robolab/params/myo_tt_p2_r5_bhprac.txt")
ctl="/Users/erik/tungsten/bits/tungsten-robolab/bin/champions/tt_p2_300-20260927-194659"
for i,seed in enumerate(range(98000,98006)):
    task=MyoTTTask()
    c0=time.process_time(); w0=time.time()
    sim=tt_fast.make_sim(task,params,seed,controller=ctl)
    c1=time.process_time(); w1=time.time()
    res=sim.run()
    c2=time.process_time(); w2=time.time()
    print(i,seed,"setup cpu %.2f wall %.2f | run cpu %.2f wall %.2f | steps %d solved %s"%(c1-c0,w1-w0,c2-c1,w2-w1,res["steps"],res["solved"]),flush=True)
