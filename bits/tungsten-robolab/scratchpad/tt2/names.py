import os, sys
os.environ.setdefault("TT_ENV", "P2")
sys.path.insert(0, "playground")
import warnings; warnings.filterwarnings("ignore")
import mujoco, numpy as np
from myosuite.utils import gym
m = gym.make("myoChallengeTableTennisP2-v0").unwrapped.mj_model
names = [m.actuator(i).name for i in range(m.nu)]
from tasks.myo_tt import MyoTTTask
arm = set(MyoTTTask.ARM_MUSCLES)
print(len(names), "actuators; ARM_MUSCLES present:", sum(1 for n in names if n in arm))
rest = [n for n in names if n not in arm]
import re
# group by prefix
from collections import Counter
pre = Counter(re.split(r"[_0-9]", n)[0] for n in rest)
print(sorted(pre.items(), key=lambda x: -x[1]))
print("rest names sample:", rest[:400])
