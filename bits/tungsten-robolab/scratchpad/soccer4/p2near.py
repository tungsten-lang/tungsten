import os, sys, numpy as np
from myosuite.utils import gym
env = gym.make("myoChallengeSoccerP2-v0"); u = env.unwrapped
rows = []
for s in range(int(sys.argv[1]), int(sys.argv[2])):
    u.seed(s); env.reset(seed=s)
    q = u.mj_data.joint("root").qpos
    rows.append((s, float(q[0]), float(q[1])))
rows.sort(key=lambda r: np.hypot(39 - r[1], r[2]))
for r in rows[:int(sys.argv[3])]:
    print(r[0], round(r[1], 3), round(r[2], 3), round(float(np.hypot(39 - r[1], r[2])), 3))
