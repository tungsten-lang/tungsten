**Versions:** myosuite 2.12.2 (PyPI, and `main` at 9430099), mujoco 3.6.0, Python 3.12.

### What happens

`RelocateEnvV0.reset()` draws a goal pose into `mj_model.body_pos[goal_bid]` (the receptacle is a mocap body). `Robot.reset()` then calls `mujoco.mj_resetData(self.mj_model, self.mj_data)` on the **robot's own** `MjData`, so only that data gets the receptacle at the drawn pose. `env.mj_data` (which is also `obsd_mj_data`, since no separate observation model is given) is a different `MjData` object and is never reset, so its `mocap_pos` stays at the XML default `(0, -0.25, 0.9)`.

`get_obs_dict` and `get_reward_dict` read `env.mj_data`, so `goal_pos`, `pos_err` and `solved` all refer to a receptacle that never moves. The physics steps `robot.mj_data`, whose receptacle (a base and four walls, all with contype/conaffinity 1) sits at the random pose.

### Consequences (measured)

- The randomised `target_xyz_range` never reaches the observation or the reward: `obs_dict["goal_pos"]` is `[0, -0.25, 0.9]` for every seed.
- An invisible, collidable receptacle stands at a random place in the workspace. On `myoChallengeRelocateP2eval-v0`, seeds 0-299, the arm starts in contact with its walls in 87 of 300 episodes (29%); on `myoChallengeRelocateP2-v0`, 1 of 100. `env.mj_data` shows none of these contacts, and the `if self.mj_data.ncon > 0: self.reset(...)` re-draw at the end of `RelocateEnvV0.reset()` reads that data, so it never fires for them.

### Reproduction

```python
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
```

Output:

```
env.mj_data is env.robot.mj_data: False
0 drawn goal [ 0.073 -0.392  0.908] | env.mj_data mocap [ 0.   -0.25  0.9 ] | robot.mj_data mocap [ 0.073 -0.392  0.908]
1 drawn goal [-0.253 -0.497  1.029] | env.mj_data mocap [ 0.   -0.25  0.9 ] | robot.mj_data mocap [-0.253 -0.497  1.029]
2 drawn goal [-0.265 -0.381  1.063] | env.mj_data mocap [ 0.   -0.25  0.9 ] | robot.mj_data mocap [-0.265 -0.381  1.063]
starts touching the receptacle: 87 of 300 in robot.mj_data (the stepped data), 0 of 300 in env.mj_data
```

### A possible fix

Copy the mocap pose from the robot's data after the reset, in `MujocoEnv._reset`:

```python
self.robot.reset(reset_pos=qpos, reset_vel=qvel, seed=seed, **kwargs)
if self.mj_model.nmocap > 0:  # mocap poses come from the redrawn body_pos
    for d in {id(self.mj_data): self.mj_data, id(self.obsd_mj_data): self.obsd_mj_data}.values():
        d.mocap_pos[:] = self.robot.mj_data.mocap_pos
        d.mocap_quat[:] = self.robot.mj_data.mocap_quat
        mujoco.mj_forward(self.mj_model, d)
return self.get_obs()
```

With this patch, the mocap poses agree on all 300 seeds, `goal_pos` follows the drawn target, and the existing `ncon` re-draw in `RelocateEnvV0.reset()` now rejects the overlapping starts (0 of 300 start in contact). I did not check other environments with mocap bodies.

Side note: in `RelocateEnvV0`, `env.reset(seed=...)` does not reseed `env.np_random` (the goal and object are drawn before the seed is handled), so results differ between runs unless `env.unwrapped.seed(seed)` is called first, as above.
