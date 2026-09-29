"""Render a soccer rollout at a chosen fps and gif stride.
usage: video.py <params> <seed> <controller> <seconds> <out.mp4> [gif] [fps] [gif_every] [gif_scale] [set k=v,...]"""
import os, sys
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
from myo_bridge import MyoSim
from tasks.myo_soccer import MyoSoccerTask
from render import Recorder
params = {}
for line in open(sys.argv[1]):
    p = line.split()
    if len(p) >= 2 and not line.startswith("#"):
        params[p[0]] = float(p[1])
if len(sys.argv) > 10:
    for kv in sys.argv[10].split(","):
        if "=" in kv:
            k, v = kv.split("="); params[k] = float(v)
seed, ctl, secs, mp4 = int(sys.argv[2]), sys.argv[3], float(sys.argv[4]), sys.argv[5]
gif = sys.argv[6] if len(sys.argv) > 6 else None
fps = int(sys.argv[7]) if len(sys.argv) > 7 else 30
every = int(sys.argv[8]) if len(sys.argv) > 8 else 2
scale = float(sys.argv[9]) if len(sys.argv) > 9 else 0.5
task = MyoSoccerTask()
sim = MyoSim(task, params=params, controller=os.path.abspath(ctl), seed=seed)
rec = Recorder(sim, fps=fps, scene_option=task.scene_option())
res = sim.run(secs, recorder=rec)
keys = ["time", "bal1_s", "bal_l_tot", "bal_s", "stand_time", "fallen", "goal", "strike_zone", "strike_zone_foot", "strike_medial_m", "ball_speed", "n_steps", "t_touch"]
print({k: res.get(k) for k in keys})
rec.write_mp4(mp4)
if gif:
    rec.write_gif(gif, scale=scale, every=every)
