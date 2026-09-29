**Versions:** mujoco 3.6.0 (PyPI wheel, macOS arm64; the simulation study), myosuite 2.12.2, numpy 1.26.4, Python 3.12. The pure-MuJoCo reproduction below gives the same 859 / 651 NaN on the 3.2.7, 3.3.0, 3.6.0 and 3.14.0 (newest PyPI release on 9/29/2026) wheels, and the `engine_util_misc.c` wrap code is byte-identical on the `main` branch fetched the same day. Not filed anywhere: Erik decides.

### What happens

A spatial tendon that wraps a cylinder or sphere gets a NaN length, NaN moment arms and (through the muscle) a NaN force when its line only *grazes* the wrapping geom. In `src/engine/engine_util_misc.c` `mju_wrap` calls `wrap_circle`, which ends in

```c
static mjtNum length_circle(const mjtNum* p0, const mjtNum* p1, int ind, mjtNum radius) {
  mjtNum p0n[2] = {p0[0], p0[1]};
  mjtNum p1n[2] = {p1[0], p1[1]};
  mju_normalize(p0n, 2);
  mju_normalize(p1n, 2);
  mjtNum angle = mju_acos(mju_dot(p0n, p1n, 2));     // mju_acos is plain acos
  ...
```

`p0` and `p1` are the two tangent points of the wrap. When the tendon line just cuts the circle (relative margin `(r^2 - |nearest point|^2) / r^2` below about 6e-8, a tendon line within ~1 nm of the tangent for r = 25 mm) the two tangent points are less than about 2e-8 rad apart, `dot(p0n, p1n)` is `1 - 1e-16` in exact arithmetic and rounds to a value *above* 1.0 in roughly one case in ten (30 % right at the tangent, 0 % once the arc is beyond ~2e-8 rad), and `acos` returns NaN. `mju_wrap` then tests `if (wlen < 0) return -1;` which is false for NaN, so the NaN goes on into `wpnt`, `ten_length`, `ten_J`, the muscle force and `qacc`; `mj_checkAcc` reports "Nan, Inf or huge value in QACC at DOF n" (n is simply the first dof of the tree: the root's) and resets the data.

### Consequences (measured)

MyoSuite's `myoChallengeSoccerP2-v0` (myolegs, 290 muscles), a kicker holding a motionless one-leg stance: the swing leg's right rectus femoris (`recfem_r_tendon`, path pelvis site -> cylinder `KnExt_at_fem_r_wrap`, r = 0.025 m, with a sidesite -> patella) lies on the cylinder's tangent while the swing leg chatters (a period-2 limit cycle of the 100 Hz reflex loop: the swing ankle alternates by 4e-3 rad from one control step to the next, the hip by 1e-4 rad), so the line crosses the tangent tens of times a second, a few micrometres of tendon-line offset each way (whether the chatter is what puts the line on the tangent was not isolated: an open-loop replay with a damped swing ankle drifts away from it altogether). Every crossing has a small chance of landing in the NaN sliver.

- 7 of 120 arena runs of a 310 s one-leg hold (three controllers x 40 starts: 1, 1 and 5; six distinct starts, 89122 blows up identically under two of them) and validation start 91049 ended in this NaN: seeds 89106 (222.07 s), 89103 (255.55 s), 89130 (141.04 s), 89134 (134.21 s), 89135 (130.21 s), 89122 (15.81 s), 91049 (16.52 s). Five of them re-captured and analysed (91049, 89122, 89134, 89135, 89130) plus 89103 and 89106 (event times reproduced to the millisecond by the guarded reruns): always the same tendon (239, `recfem_r_tendon`), the wrap active, the margin between +2.6e-9 and +3.6e-8. Two (89103, 89130) landed on the state at a control-step boundary, which MyoSuite's observation mirror evaluates first: the controller then receives a NaN muscle length, answers with a NaN activation and MuJoCo prints "CTRL at ACTUATOR 239" and zeroes *all* controls (`mj_fwdActuation`) before the QACC reset.
- It is not specific to that muscle or to holds. The guarded arena runs (below) also caught `IL_L1_r_tendon` (iliocostalis, a trunk muscle wrapping the cylinder `back_cylinder_s`, r = 0.07 m) at t = 2.12 s of start 96029 under the lift entry: the official environment (`capture.py`, 6 s) gives "CTRL at ACTUATOR 24" then "QACC at DOF 6" at exactly 2.1200 s, wrap active by 5.5e-11 (a line closing on its tangent at 5.6e-3 per control step). The model has 68 cylinder or sphere wrap segments; 36 wrap all the time, 18 miss, 12 have an endpoint inside the circle, 2 use the `wrap_inside` path, and every one of them can meet the sliver when its line crosses the tangent.
- Each event ends the hold: `mj_checkAcc` calls `mj_resetData`, which puts the kicker back in the model's reference pose at the world origin, and it falls 0.2-0.4 s later.
- Start 91049, live run, t = 3-12 s: the tendon line is within 1e-3 (12 um) of the tangent in 71 % of the control steps, within 1e-4 (1.2 um) in 24 %, and crosses it 163 times in 9 s. Bit-exact replay of all 16 500 substeps: the wrap is active in 8103 of them, and exactly two substeps fall into the NaN sliver (t = 11.236 s, margin +2.7e-8, survived, and t = 16.517 s, +3.6e-8, NaN). In the other four captures the event was the only sliver visit of the 16-20 s window replayed (the nearest survived approaches were at margin 6.9e-8, 1.5e-7, 2.2e-7 and 4.8e-7).
- The NaN is produced by the position stage alone: at the failing substep `mj_fwdPosition` (kinematics + tendons, no solver, no contact, no actuator) already returns NaN for tendon 239. Halving the timestep, another solver, more iterations, elliptic cone, `impratio`, `noslip`, islands off, `implicitfast`, dense Jacobian, warmstart off, contacts off, the 215 N swing-shank/stance-thigh contact pair removed, extra swing-ankle damping: none changes the NaN at the failing state (table below); only changing the wrap geometry (cylinder radius +2.5e-8 m, -25 um, or 0) removes it.

Sweeping `hip_flexion_r` by +-2e-6 rad in steps of 1e-10 through the failing state (40 001 calls of `mj_fwdPosition`): 272 NaN points, all on the wrapping side with margins from +4.6e-11 to +5.5e-8, and the NaN rate follows the exact (60-digit) value of `1 - dot`:

| exact `1 - dot` | points | NaN | fraction |
| --- | --- | --- | --- |
| < 1e-17 | 431 | 127 | 0.29 |
| 1e-17 .. 3e-17 | 322 | 65 | 0.20 |
| 3e-17 .. 6e-17 | 319 | 43 | 0.13 |
| 6e-17 .. 1e-16 | 318 | 19 | 0.06 |
| 1e-16 .. 1.5e-16 | 316 | 10 | 0.03 |
| 1.5e-16 .. 2.5e-16 | 501 | 2 | 0.004 |
| > 2.5e-16 | 19 094 | 0 | 0 |
| (a port of the code picks the far tangent pair here; MuJoCo's near-coincident pair has 1 - dot < 4e-18) | 17 | 6 | 0.35 |
| no wrap (margin < 0) | 18 683 | 0 | 0 |

The same sweep through the failing states of 89134 and 89122 gives 280 and 292 NaN in 40 001 calls with the same curve (27 % / 20 % / 15 % / 7 % / 6 % ... below 1e-16, ~1 % at 2e-16, 0 above 2.5e-16; NaN margins up to +6.0e-8 and +4.8e-8): the rate depends on the rounding of the dot product, not on the geometry.

### Reproduction

Everything needed is in this directory (`playground/repros/`): `mujoco_wrap_nan_repro.py` (pure MuJoCo, any 3.x wheel: `python mujoco_wrap_nan_repro.py [sphere]`), `mujoco_wrap_nan_harness.c` (`clang -O2 mujoco_wrap_nan_harness.c -lm`), and, for the real simulation, `myosuite_soccer_wrap_nan_state.py` with `mujoco_wrap_nan_states/` (run with the MyoSuite venv: mujoco 3.6.0, myosuite 2.12.2). The study's tooling (captures, replays, bisect, arena trials) lives in `scratchpad/blowup/` and is not needed to reproduce.

Pure MuJoCo (no MyoSuite), `playground/repros/mujoco_wrap_nan_repro.py` (static cylinder, three sites, one tendon with a sidesite; the tendon line is swept across the tangent in 1e-13 m steps):

```
mujoco 3.6.0 (cylinder): the tendon line touches the cylinder at p1.x = 0.02536803166881501 (distance to axis 0.025 vs r 0.025)
8001 points (p1.x step 1e-13 m across the tangent): NaN 859, finite on the wrapping side 3142, finite on the non-wrapping side 4000
example k = 0: ten_length = nan ...
```

`python mujoco_wrap_nan_repro.py sphere` gives 651 NaN of 8001 (the sphere wrap goes through the same `wrap_circle`/`length_circle`). Both counts are identical on mujoco 3.2.7, 3.3.0, 3.6.0 and 3.14.0.

At source level, `playground/repros/mujoco_wrap_nan_harness.c` is the 3.6.0 `is_intersect` / `length_circle` / `wrap_circle` verbatim (compiled with `clang -O2`, arm64) fed with the failing substep's 2D inputs and 40 001 last-bit perturbations of them: 6834 NaN, every one of them a point where `dot > 1.0` before `acos`, and 0 NaN (40 001 finite) with the dot clamped.

From the real simulation, `playground/repros/myosuite_soccer_wrap_nan_state.py` loads a 7.5 KB saved MjData (the stepped data of `myoChallengeSoccerP2-v0`, seed 91049 at t = 16.51 s, plus the control of the next control step) and reproduces in about a second: "Nan, Inf or huge value in QACC at DOF 6" at the 8th substep (t = 16.517 s), NaN tendon 239 at the position stage, and no NaN after a 1e-10 rad nudge of the joint angles. Four more saved states (seeds 89122, 89130, 89134, 89135) sit beside it in `mujoco_wrap_nan_states/`. The two full-rollout captures of 91049 (`scratchpad/blowup/capture.py`, 16 s wall) are bit-identical over all 1651 control steps.

Single-change bisect from the saved states (`scratchpad/blowup/bisect_variants.py`; DIAGNOSTIC variants of a private copy of the model). Column A replays from t = 13.5 s (300 control steps earlier) with the recorded controls and the variant for the whole window: any change re-rolls the rounding, so "no warning" is expected and proves nothing. Column B applies the variant to the failing substep only (bit-exact state) and is the discriminating test:

| variant | A: blow-up in the window | B: tendon 239 NaN at the failing substep |
| --- | --- | --- |
| none | yes, 16.517 s | NaN |
| timestep 0.0005 | no | NaN |
| solver CG / PGS | no / no | NaN / NaN |
| Newton 500 iterations, tol 1e-12 | yes, 16.517 s | NaN |
| elliptic cone, impratio 10, noslip 10 | no | NaN |
| islands off, implicitfast, warmstart off | no | NaN |
| dense Jacobian | yes, 16.517 s | NaN |
| contacts off, tibia_r-femur_l pair removed or softened (solref 0.05, solimp 0.5/0.9, margin 2 mm) | no | NaN |
| muscle activation / deactivation time constants x2 | no | NaN |
| swing ankle damping + armature | no | NaN |
| recfem_r wrap without its sidesite | yes, 16.517 s (same trajectory) | NaN |
| wrap radius x(1 + 1e-6), x(1 - 1e-3), 0 | no | finite |

### A possible fix

One line in `length_circle` (and, if a NaN should never escape `mju_wrap` whatever produces it, one in `mju_wrap`):

```c
mjtNum angle = mju_acos(mju_clip(mju_dot(p0n, p1n, 2), -1, 1));   // rounding can put the dot of two unit vectors just above 1
...
if (wlen < 0 || mju_isBad(wlen)) return -1;                        // in mju_wrap: no wrap for a negative or NaN length
```

Clamping gives `angle = 0`, i.e. a wrap of zero arc length, continuous with the unwrapped tendon at the tangent to 1e-16. In the C harness the clamp turns the 6834 NaN of 40 001 into 0.

### Workaround in robolab

`playground/tasks/myo_soccer_ng.py` (labelled variant `nanguard`, used only by the `*_ng` arena trials): the stepped MjData advances through a guard that snapshots the integration state before every substep, calls `mj_step` exactly as MyoSuite does, and only if MuJoCo reset the data and a tendon length is NaN at the snapshot, redoes the substep from it after a deterministic nudge of the hinge/slide joint angles (1e-10 rad, growing x10 every three tries). The same NaN can reach the controller first through MyoSuite's sensor-synced mirror (`env.mj_data`), so the task checks the mirror after every control step. While no NaN occurs a rollout is bit-identical to the official environment's.

### Before / after in the arena

Same three controllers, same starts; the guarded runs are bit-identical to the official ones until a NaN (identity checked on 119 of 119 event-free hold20 starts and on every re-run of a failing 310 s start). Holds of five minutes on one leg, 40 fresh starts (seeds 89100-89139):

| entry | official (7 of 120 runs end in the NaN) | guarded |
| --- | --- | --- |
| round-5 lift | 34 / 40 (1 NaN) | 35 / 40 |
| round-6 set ramp | 38 / 40 (1 NaN) | 39 / 40 |
| ramp + shift capture-point brake | 35 / 40 (5 NaN) | 40 / 40 |

The other failures (lift: 89110, 89115, 89117, 89130, 89133; ramp: 89133) are real balance falls and reproduce identically. Twenty-second holds, 120 other fresh starts: lift 102, ramp 113, brake 118 of 120 (one NaN event each in the lift and brake runs, none in the ramp's; the lift's, a trunk tendon at 2.12 s, would officially have counted as a fall).

### Side note

`env.unwrapped.mj_data` (`MyoSim.d`) is not the stepped data: `Robot` owns its own `MjData` (sharing the `MjModel`) and steps that; `env.mj_data` is a mirror that `get_obs` re-syncs (time, qpos, qvel, act, then `mj_forward`) once per control step, with `ctrl = 0` and no solver warm start (the same two-`MjData` design as in `myosuite_relocate_issue.md`). Contact and constraint numbers read from `sim.d` are therefore recomputed from the state at the end of the last control step, not the step's own.
