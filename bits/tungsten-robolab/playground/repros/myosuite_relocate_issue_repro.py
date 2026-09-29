import gymnasium as gym, mujoco, myosuite

env = gym.make("myoChallengeRelocateP2eval-v0")
u = env.unwrapped
m = u.mj_model
gids = [g for g in range(m.ngeom) if m.geom_bodyid[g] == u.goal_bid]  # receptacle base + four walls

def touching(d):
    return any(d.contact[i].geom1 in gids or d.contact[i].geom2 in gids for i in range(d.ncon))

print("env.mj_data is env.robot.mj_data:", u.mj_data is u.robot.mj_data)
bad = bad_env = 0
for seed in range(300):
    u.seed(seed)          # reset(seed=...) does not reseed env.np_random, so seed explicitly
    env.reset()
    mujoco.mj_forward(m, u.robot.mj_data)
    mujoco.mj_forward(m, u.mj_data)
    bad += touching(u.robot.mj_data)
    bad_env += touching(u.mj_data)
    if seed < 3:
        print(seed, "drawn goal", m.body_pos[u.goal_bid].round(3),
              "| env.mj_data mocap", u.mj_data.mocap_pos[0].round(3),
              "| robot.mj_data mocap", u.robot.mj_data.mocap_pos[0].round(3))
print(f"starts touching the receptacle: {bad} of 300 in robot.mj_data (the stepped data), {bad_env} of 300 in env.mj_data")
