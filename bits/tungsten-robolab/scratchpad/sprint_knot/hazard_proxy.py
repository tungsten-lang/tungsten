"""hazard_proxy: DIAGNOSTIC. Per seed run 30 s; from the task's per-step record compute, over the window [t0, t1] (default 8-20 s of the
run, or up to the fall), gait-regularity statistics, and whether/when the run fell. Prints a table and the fall/no-fall means.
usage: env... hazard_proxy.py TASK PARAMS CONTROLLER SEEDS WORKERS [SECONDS]"""
import sys, os, multiprocessing as mp
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
import numpy as np
from practice import load_task, read_params
from bridge import Sim

def runs_of(mask, t, gap=0.02, minlen=0.03):
    out, a = [], None
    for k in range(len(t)):
        if mask[k] and a is None: a = k
        elif not mask[k] and a is not None:
            if out and t[a] - t[out[-1][1] - 1] < gap: out[-1] = (out[-1][0], k)
            else: out.append((a, k))
            a = None
    if a is not None: out.append((a, len(t)))
    return [(a, b) for a, b in out if t[b - 1] - t[a] >= minlen]

def one(job):
    task_name, params, ctl, seed, secs = job
    task = load_task(task_name); task.seed = seed
    sim = Sim(task, params=params, controller=ctl)
    m = sim.run(secs)
    r = np.array([(x[0], x[3], x[4], x[5], x[9], x[2]) for x in task.rec], float)  # t, lc, rc, torso pitch, right thigh, pelvis z
    t = r[:, 0]; rc = r[:, 2] > 0.5; lc = r[:, 1] > 0.5
    fell = bool(m["fell"]); tend = float(t[-1])
    t0, t1 = 8.0, min(20.0, tend - 0.3 if fell else 20.0)
    if t1 - t0 < 3.0:
        return seed, fell, tend, [float("nan")] * 6
    runs = [(a, b) for a, b in runs_of(rc, t) if t0 <= t[a] <= t1]
    if len(runs) < 5:
        return seed, fell, tend, [float("nan")] * 6
    tds = np.array([t[a] for a, _ in runs]); tcs = np.array([t[b - 1] - t[a] for a, b in runs])
    thtd = np.array([r[a, 4] for a, _ in runs])
    stride = np.diff(tds)
    w = (t >= t0) & (t <= t1)
    both_off = ~rc & ~lc
    iv = runs_of(both_off, t, gap=0.0, minlen=0.005)
    fl = np.array([t[b - 1] - t[a] for a, b in iv if t0 <= t[a] <= t1]) if iv else np.array([0.0])
    return seed, fell, tend, [float(np.std(stride)), float(np.std(tcs)), float(np.std(thtd)), float(np.std(r[w, 3])), float(np.min(fl)) if len(fl) else 0.0, float(np.max(r[w, 3]))]

if __name__ == "__main__":
    task_name, par, ctl, seeds, workers = sys.argv[1:6]
    secs = float(sys.argv[6]) if len(sys.argv) > 6 else 30.0
    params = read_params(par)
    jobs = [(task_name, params, ctl, int(s), secs) for s in seeds.split(",")]
    with mp.Pool(int(workers)) as pool:
        res = pool.map(one, jobs, chunksize=1)
    names = ["strideStd", "tcStd", "thTDstd", "pitchStd", "minFlight", "pitchMax"]
    print("seed fell tEnd " + " ".join(names))
    for s, f, te, v in res:
        print(s, int(f), round(te, 1), *[round(x, 4) for x in v])
    A = np.array([v for _, f, _, v in res if f and not np.isnan(v[0])]); B = np.array([v for _, f, _, v in res if not f and not np.isnan(v[0])])
    if len(A) and len(B):
        print("MEAN fell   ", *[round(float(x), 4) for x in A.mean(0)])
        print("MEAN survive", *[round(float(x), 4) for x in B.mean(0)])
