"""knot_seeds: DIAGNOSTIC. Distil a running gait's own stance into RunKnotSkill knot values: run the gait, and over the right-foot stances
of the steady tail average, at touchdown / half stance / lift-off, the world thigh angle, knee, ankle and the hip / knee / ankle joint velocities.
Prints a params fragment (kn_td_*, kn_ms_*, kn_lo_*, kn_t_ms, kn_t_lo).
usage: env... knot_seeds.py TASK PARAMS CONTROLLER SEED SECONDS [TAIL]"""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(ROOT, "playground"))
import numpy as np
from practice import load_task, read_params
from bridge import Sim
from stridetab import Rec, runs_of

task_name, par, ctl, seed, secs = sys.argv[1:6]
tail = float(sys.argv[6]) if len(sys.argv) > 6 else 0.5
task = load_task(task_name); task.seed = None if seed in ("None", "none") else int(seed)
if os.environ.get("RUN_NATURAL_START") == "flying":
    task.fly_touch = 2.0
sim = Sim(task, params=read_params(par), controller=ctl)
rec = Rec(sim); rec.hook(task)
res = sim.run(float(secs), recorder=rec)
S = np.array(rec.steps); T = np.array(rec.ticks); t = S[:, 0]
print("run", {k: res.get(k) for k in ("time", "fell", "steady_speed", "peak_speed_1s")}, file=sys.stderr)
t_tail = t[-1] * (1 - tail)
runs = [(a, b) for a, b in runs_of(S[:, 4] > 0.01, t) if t[a] >= t_tail]
td, ms, lo, tms, tlo = [], [], [], [], []
for a, b in runs[1:]:
    ka = np.searchsorted(T[:, 0], t[a]); kb = max(np.searchsorted(T[:, 0], t[b - 1]), ka + 2); km = (ka + kb) // 2
    def st(k):
        return [T[k, 7], T[k, 10], T[k, 11], T[k, 15], T[k, 16], T[k, 17]]
    td.append(st(ka)); ms.append(st(km)); lo.append(st(kb))
    tms.append(T[km, 0] - T[ka, 0]); tlo.append(T[kb, 0] - T[km, 0])
td, ms, lo = np.mean(td, 0), np.mean(ms, 0), np.mean(lo, 0)
print(f"# knot seeds distilled from {par} ({len(runs) - 1} stances of the tail)")
for pre, v in (("kn_td", td), ("kn_ms", ms), ("kn_lo", lo)):
    print(f"{pre}_thigh {v[0]:.4f}\n{pre}_knee {v[1]:.4f}\n{pre}_ankle {v[2]:.4f}\n{pre}_whip {v[3]:.3f}\n{pre}_wknee {v[4]:.3f}\n{pre}_wankle {v[5]:.3f}")
print(f"kn_t_ms {np.mean(tms):.4f}\nkn_t_lo {np.mean(tlo):.4f}")
