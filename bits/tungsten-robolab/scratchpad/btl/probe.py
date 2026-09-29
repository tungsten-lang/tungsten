import os, sys, time, json
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks")
os.environ["DRIBBLE_SEED"] = sys.argv[2] if len(sys.argv) > 2 else "0"
from bridge import Sim
from dribble_v3 import DribbleV3Task
params = {}
for line in open("params/dribble_v3_x2.txt"):
    p = line.split()
    if len(p) >= 2 and not line.startswith("#"): params[p[0]] = float(p[1])
params["mode"] = float(sys.argv[1])
t = DribbleV3Task()
sim = Sim(t, params=params)
t0 = time.time()
r = sim.run(float(sys.argv[3]) if len(sys.argv) > 3 else 15)
print("wall", round(time.time()-t0,1))
print({k: r[k] for k in ("dribbles","lost","moves","moves_consecutive","body_hits","controlled_s")})
for mv in t.moves: print(mv)
