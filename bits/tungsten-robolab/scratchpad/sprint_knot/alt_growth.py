"""alt_growth: DIAGNOSTIC. Per seed: the alternation (period-2) amplitude of the stride sequence, from the task's per-step record:
the aerial gaps g_k between successive steps (neither foot down) -> a_k = (-1)^k (g_k - g_{k-1})/2 and the same for stance durations, RMS over
3 s windows from 6 s on, and the fall time. A flip (period-doubling) instability shows as a growing RMS before a fall.
usage: env... alt_growth.py TASK PARAMS CONTROLLER SEEDS WORKERS [SECONDS]"""
import sys, os, multiprocessing as mp
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
import numpy as np
from practice import load_task, read_params
from bridge import Sim

def runs_of(mask, t, gap=0.0, minlen=0.005):
    out, a = [], None
    for k in range(len(t)):
        if mask[k] and a is None: a = k
        elif not mask[k] and a is not None:
            if gap and out and t[a] - t[out[-1][1] - 1] < gap: out[-1] = (out[-1][0], k)
            else: out.append((a, k))
            a = None
    if a is not None: out.append((a, len(t)))
    return [(a, b) for a, b in out if t[b - 1] - t[a] >= minlen]

def one(job):
    task_name, params, ctl, seed, secs = job
    task = load_task(task_name); task.seed = seed
    sim = Sim(task, params=params, controller=ctl)
    m = sim.run(secs)
    r = np.array([(x[0], x[3], x[4]) for x in task.rec], float)
    t = r[:, 0]; lc = r[:, 1] > 0.5; rc = r[:, 2] > 0.5
    fell = bool(m["fell"]); tend = float(t[-1])
    both_off = ~lc & ~rc
    iv = [(t[a], t[b - 1]) for a, b in runs_of(both_off, t, 0.0, 0.01)]
    gaps = np.array([b - a for a, b in iv]); tg = np.array([a for a, b in iv])
    # alternation amplitude a_k = (g_k - g_{k-1})/2, windowed RMS
    out = []
    if len(gaps) > 8:
        alt = np.abs(np.diff(gaps)) / 2.0; ta = tg[1:]
        for w0 in (6.0, 9.0, 12.0, 15.0, 18.0, 21.0, 24.0, 27.0):
            sel = (ta >= w0) & (ta < w0 + 3.0) & (ta < tend - 0.3)
            out.append(float(np.sqrt(np.mean(alt[sel] ** 2))) if sel.sum() >= 3 else float("nan"))
    else:
        out = [float("nan")] * 8
    return seed, fell, tend, out

if __name__ == "__main__":
    task_name, par, ctl, seeds, workers = sys.argv[1:6]
    secs = float(sys.argv[6]) if len(sys.argv) > 6 else 30.0
    params = read_params(par)
    jobs = [(task_name, params, ctl, int(s), secs) for s in seeds.split(",")]
    with mp.Pool(int(workers)) as pool:
        res = pool.map(one, jobs, chunksize=1)
    print("seed fell tEnd | alt RMS (ms) in 3 s windows from 6,9,12,...,27 s")
    for s, f, te, v in res:
        print("%3d %d %5.1f |" % (s, int(f), te), " ".join("  nan" if np.isnan(x) else "%5.1f" % (1000 * x) for x in v))
