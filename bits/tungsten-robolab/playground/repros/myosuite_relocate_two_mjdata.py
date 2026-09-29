"""MyoSuite 2.12.2: the Relocate physics steps a receptacle that the observation does not show.

Run with the MyoSuite venv:  .venv-myo/bin/python playground/repros/myosuite_relocate_two_mjdata.py

RelocateEnvV0.reset() draws a random goal pose into mj_model.body_pos[goal_bid]. Robot.reset() then calls
mj_resetData on the ROBOT's own MjData, which takes the receptacle's (mocap) pose from the new body_pos.
env.mj_data (which is also obsd_mj_data, the data that get_obs_dict and the reward read) is never reset, so its
mocap_pos keeps the XML default (0, -0.25, 0.9). The receptacle has collision-enabled base and wall geoms, so the
physics collides with a receptacle at a random pose while the observation and the reward see one at a fixed pose.
"""
import sys

import gymnasium as gym
import mujoco
import numpy as np

import myosuite  # noqa: F401  (registers the environments)

ENV = sys.argv[1] if len(sys.argv) > 1 else "myoChallengeRelocateP2eval-v0"
N = int(sys.argv[2]) if len(sys.argv) > 2 else 40

env = gym.make(ENV)
u = env.unwrapped
m = u.mj_model
gids = [g for g in range(m.ngeom) if m.geom_bodyid[g] == u.goal_bid]  # base + four walls of the receptacle
print(f"myosuite {myosuite.__version__}, mujoco {mujoco.__version__}, {ENV}")
print("env.mj_data is robot.mj_data:", u.mj_data is u.robot.mj_data, "| same MjModel:", u.mj_model is u.robot.mj_model)


def receptacle_contacts(d):
    return sum(1 for i in range(d.ncon) if d.contact[i].geom1 in gids or d.contact[i].geom2 in gids)


print("\nseed  drawn goal (model.body_pos)   env.mj_data mocap_pos   robot.mj_data mocap_pos   "
      "receptacle contacts at t=0 (env / robot)")
bad = 0
for seed in range(N):
    u.seed(seed)  # reset(seed=...) does not reseed the env's np_random, so seed it explicitly
    env.reset()
    d_env, d_robot = u.mj_data, u.robot.mj_data
    mujoco.mj_forward(m, d_env)
    mujoco.mj_forward(m, d_robot)
    c_env, c_robot = receptacle_contacts(d_env), receptacle_contacts(d_robot)
    bad += c_robot > 0
    if seed < 6:
        print(f"{seed:4d}  {np.round(m.body_pos[u.goal_bid], 3)}   {np.round(d_env.mocap_pos[0], 3)}   "
              f"{np.round(d_robot.mocap_pos[0], 3)}   {c_env} / {c_robot}")
print(f"\nseeds where the arm starts in contact with the physics receptacle: {bad} of {N} "
      f"(observed data shows none of them)")
