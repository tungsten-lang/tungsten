"""pitchmax: DIAGNOSTIC. Per seed: fell?, fall time, max torso pitch after 5 s, time the pitch first exceeded 0.6 / 0.8, tail regularity.
usage: env... pitchmax.py TASK PARAMS CONTROLLER SEEDS SECONDS WORKERS"""
import sys, os, math, multiprocessing as mp
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
import numpy as np
from practice import load_task, read_params
from bridge import Sim

class R:
    def __init__(s): s.t = []; s.p = []
    def maybe_capture(s, sim):
        d = sim.d; tor = d.body("torso").xmat.reshape(3, 3)[:, 2]
        s.t.append(d.time); s.p.append(math.atan2(tor[0], tor[2]))

def one(job):
    task_name, params, ctl, seed, secs = job
    task = load_task(task_name); task.seed = seed
    sim = Sim(task, params=params, controller=ctl); r = R()
    m = sim.run(secs, recorder=r)
    t = np.array(r.t); p = np.array(r.p)
    late = t > 5.0
    pm = float(np.max(np.abs(p[late]))) if late.any() else 0.0
    def first(th):
        k = np.nonzero((np.abs(p) > th) & late)[0]
        return float(t[k[0]]) if len(k) else -1.0
    # pitch std over the last 5 s that survived
    tail = t > t[-1] - 5.0
    return seed, bool(m["fell"]), round(float(t[-1]), 1), round(pm, 2), first(0.6), first(0.8), round(float(np.std(p[tail])), 3), round(float(np.mean(p[tail])), 3)

if __name__ == "__main__":
    task_name, par, ctl, seeds, secs, workers = sys.argv[1:7]
    params = read_params(par)
    jobs = [(task_name, params, ctl, int(s), float(secs)) for s in seeds.split(",")]
    with mp.Pool(int(workers)) as pool:
        res = pool.map(one, jobs, chunksize=1)
    print("seed fell tEnd maxPitch t>0.6 t>0.8 tailStd tailMean")
    for r in res:
        print(*r)
