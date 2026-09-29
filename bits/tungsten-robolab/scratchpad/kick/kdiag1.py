"""First diagnostic: the phase-1 champion in the P2 env at the exact P1 start (noise 0): timing, phases, contact."""
import sys, time
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/kick")
import numpy as np
import kcommon as K

t0 = time.time()
params = K.read_params(K.P1_PARAMS)
noise = float(sys.argv[1]) if len(sys.argv) > 1 else 0.0
seed = int(sys.argv[2]) if len(sys.argv) > 2 else 5000
K.ensure()
t1 = time.time()
sim = K.make_sim(params, K.P1_CTL, seed, dict(noise=noise, dx=0.0, dy=0.0))
t2 = time.time()
m = sim.run(6.0)
t3 = time.time()
print(f"ensure {t1-t0:.1f}s make_sim {t2-t1:.1f}s run {t3-t2:.1f}s steps {m['steps']} sim time {m['time']}")
keys = ["goal", "t_goal", "t_touch", "touch_body", "ball_speed", "ball_speed_max", "fallen", "t_fall", "cross_y", "cross_z", "launch_deg", "launch_elev_deg", "strike_zone", "strike_point_all", "keeper_policy", "keeper_y", "r_toe_ball_min"]
print({k: m.get(k) for k in keys})
print("events", m["events"])
tr = sim.task.tr
j = K.touch_index(sim)
print("touch index", j, "of", len(tr))
if j is not None:
    for r in tr[max(0, j - 30):j + 3]:
        d = r["toe_r"] - r["ball"]
        b = r["bof_r"] - r["ball"]
        print(f"t {r['t']:.2f} {r['lab']:8s} toe-ball {d[0]:+.3f} {d[1]:+.3f} {d[2]:+.3f} |bofoot-ball {b[0]:+.3f} {b[1]:+.3f} {b[2]:+.3f} vtoe {np.round(r['vtoe_r'],1)} ball {np.round(r['ball'],3)} pelvis {np.round(r['pelvis'],3)} yaw {r['yaw']:+.2f}")
