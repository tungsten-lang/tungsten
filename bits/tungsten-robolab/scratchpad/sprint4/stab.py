"""stab.py: per-stance table (time, speed, contact, flight, step, thigh/knee at touchdown, force, pitch) of one rollout on the
CURRENT body (env from scratchpad/sprint3/env.sh); wraps scratchpad/sprint2/lab.py's recorder.
  . scratchpad/sprint3/env.sh; .venv/bin/python scratchpad/sprint3/stab.py PARAMS CONTROLLER SEED SECONDS [--task run_v4] [--start standing|flying] [--every 1] [--set k=v,...]
Set ROBOLAB_SNAP for flying starts. Prints one row per right-foot stance, and the fall time.
"""
import argparse, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "scratchpad", "sprint2"))
sys.path.insert(0, os.path.join(ROOT, "playground"))
sys.path.insert(0, os.path.join(ROOT, "scratchpad", "sprint_knot"))
import numpy as np
import lab
import stridetab as st
from practice import load_task, read_params
from bridge import Sim

ap = argparse.ArgumentParser()
ap.add_argument("params"); ap.add_argument("controller"); ap.add_argument("seed"); ap.add_argument("seconds", type=float)
ap.add_argument("--task", default="run_v4"); ap.add_argument("--start", default="standing"); ap.add_argument("--every", type=int, default=1)
ap.add_argument("--set", default=""); ap.add_argument("--attrs", default="")
a = ap.parse_args()
p = read_params(a.params)
for kv in a.set.split(","):
    if kv:
        k, v = kv.split("="); p[k] = float(v)
task = load_task(a.task)
for kv in a.attrs.split(","):
    if kv:
        k, v = kv.split("="); setattr(task, k, float(v))
if a.start != "standing":
    task.start = a.start
task.seed = None if a.seed in ("None", "none") else int(a.seed)
sim = Sim(task, params=dict(p), controller=a.controller)
rec = st.Rec(sim); rec.hook(task)
res = sim.run(a.seconds, recorder=rec)
print("fell", res.get("fell"), "t", res.get("time"), "peak", res.get("peak_speed_1s"), "steady", res.get("steady_speed"))
# per-stance rows over the whole run: reuse lab.stance_table with tail=1.0 (all stances)
tab = lab.stance_table(rec, res, 1.0)
rows = tab.get("_rows") or []
S = np.array(rec.steps); T = np.array(rec.ticks)
print("   t      v     tc   flight  step  th_td  th_lo  kn_td kn_max  fz_mean fz_peak pitch_td pitch_lo  vz_lo")
# time of each row: recompute the touchdown time by matching the order of right-foot contacts
t = S[:, 0]; contact = S[:, 4] > 0.01
runs = [(x, y) for x, y in st.runs_of(contact, t)]
tds = [t[x] for x, y in runs][1:]
for i, r in enumerate(rows):
    if i % a.every:
        continue
    tt = tds[i] if i < len(tds) else float("nan")
    print(f"{tt:6.2f} {r['v']:6.2f} {r['tc']:6.3f} {r['flight']:6.3f} {r['step']:5.2f} {r['th_td']:6.2f} {r['th_lo']:6.2f} {r['kn_td']:6.2f} {r['kn_max']:6.2f} {r['fz_mean']:7.2f} {r['fz_peak']:7.2f} {r['pitch_td']:7.2f} {r['pitch_lo']:7.2f} {r['vz_lo']:6.2f}")
