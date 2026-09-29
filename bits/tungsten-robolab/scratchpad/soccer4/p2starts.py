import os, sys, numpy as np
sys.path.insert(0, "playground")
from myosuite.utils import gym
env = gym.make("myoChallengeSoccerP2-v0"); u = env.unwrapped
out = []
for s in range(int(sys.argv[1]), int(sys.argv[2])):
    u.seed(s); env.reset(seed=s)
    q = u.mj_data.joint("root").qpos
    out.append((s, round(float(q[0]), 3), round(float(q[1]), 3), getattr(u.goalkeeper, "goalkeeper_policy", "?")))
xs = np.array([o[1] for o in out]); ys = np.array([o[2] for o in out])
print("x range", xs.min(), xs.max(), "y range", ys.min(), ys.max())
d = np.hypot(39 - xs, ys)
for thr in [0.1, 0.2, 0.3, 0.5, 0.75, 1.0, 1.5]:
    print(f"dist<{thr}: {np.mean(d < thr):.2f}")
print(out[:10])
