"""Burst ablation: each burst group zeroed in turn, standing starts, report steady speed / falls / peak speed.
usage: ablate.py TASK PARAMS CONTROLLER SEEDS SECONDS"""
import json, os, sys, multiprocessing as mp
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
from probe import one
from practice import read_params
GROUPS = {
    "none": {},
    "stance push: gluteus": {"b_glut": 0.0},
    "stance push: hamstrings": {"b_ham": 0.0},
    "stance push: soleus": {"b_sol": 0.0},
    "stance push: gastrocnemius": {"b_gas": 0.0},
    "landing vasti pulse": {"b_vas": 0.0},
    "swing drive: iliopsoas": {"b_ilio": 0.0},
    "swing drive: rectus femoris": {"b_rf": 0.0},
    "heel tuck (knee flexors)": {"b_tuck": 0.0},
    "claw: hamstrings": {"b_claw": 0.0},
    "claw: gluteus": {"b_claw_g": 0.0},
    "pre-landing vasti + soleus": {"b_pre_vas": 0.0, "b_pre_sol": 0.0},
    "touch velocities (spline dwells)": {"w_st_hip": 0.0, "w_st_knee": 0.0, "w_st_ankle": 0.0, "w_sw_hip": 0.0, "w_sw_knee": 0.0, "w_sw_ankle": 0.0},
}
if __name__ == "__main__":
    task, par, ctl, seeds, secs = sys.argv[1], sys.argv[2], sys.argv[3], [int(x) for x in sys.argv[4].split(",")], float(sys.argv[5])
    base = read_params(par)
    jobs, keys = [], []
    for g, over in GROUPS.items():
        p = dict(base); p.update(over)
        for s in seeds:
            jobs.append((task, p, s, secs, None, {}, ctl)); keys.append(g)
    with mp.Pool(int(os.environ.get("WORKERS", "3"))) as pool:
        res = pool.map(one, jobs, chunksize=1)
    out = {}
    for g, m in zip(keys, res):
        out.setdefault(g, []).append(m)
    for g, ms in out.items():
        n = len(ms); falls = sum(1 for m in ms if m.get("fell"))
        ss = [m.get("steady_speed", 0.0) or 0.0 for m in ms]; pk = [m.get("peak_speed_1s", 0.0) or 0.0 for m in ms]
        tt = [m.get("time", 0.0) for m in ms]
        print(f"{g:34s} falls {falls}/{n}  steady {sum(ss)/n:5.2f}  peak {sum(pk)/n:5.2f}  time {sum(tt)/n:5.1f}")
