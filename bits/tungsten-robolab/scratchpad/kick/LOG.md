# kick campaign log (agent P, 9/29): the closed-loop penalty kick for soccer_p2

All state lives in the repo: scratchpad/kick/ (tools, LOG.md), params/, out/ (nothing in /private/tmp).
Bulky dumps (ckpt/, out/, logs/) are git-ignored by scratchpad/kick/.gitignore; they are regenerable with the commands below.
Machine: 18 cores, load 70-130 from other sessions; at most 2 rollout workers, one search at a time.

## 0. The environment, read from the source (myosuite 2.12.2 soccer_v0.py, tasks/myo_soccer.py, arena/trials.json)

- soccer_p2 = `myoChallengeSoccerP2-v0`, 100 seeds 5000-5099, metric `goal` (1 when the ball centre passes x = 50 with |y| <= 3.3, 0 <= z <= 2.2 before
  the episode ends). Episode 10 s, control 100 Hz (10 physics steps of 1 ms), ends when the goal is scored, at 10 s, or when the pelvis falls below 0.2 m.
- Reset (`reset_type random`): the P1 key frame (root (39, 0), feet ~1.08 m behind the ball at (40, 0), ball radius 0.117 m, mass 0.45 kg)
  with the root moved x in [-1, 0], y in [-1, 1] and every one of 48 joints given uniform noise of +-0.02 rad. The ball is never randomised.
- **The goalkeeper is a decoy.** The env moves the keeper's mocap body on `env.mj_data`, but MyoSuite steps the physics on `robot.mj_data`
  (env.mj_data is a mirror rebuilt from the sensors after each step, `obsd_mj_data`), where the mocap keeper stays at its model default (50, 0, 0).
  So the OBSERVED keeper (random y, policy stationary 60 % / random 30 % / block_ball 10 %) never touches the ball; the PHYSICAL keeper is a fixed
  obstacle (capsule radius 0.25) at y = 0: a 12 m/s ball aimed at y = 0.0 bounces back at 48.9, y = +0.3 is deflected but crosses, |y| >= 0.5 crosses clean
  (probe in this log, 9/29 09:00). The scoring window is therefore cross_y in [+0.5, +3.2] or [-3.2, -0.5], i.e. a launch angle window of about
  +-(2.9 .. 17.8) deg from the ball at 10 m: +-7.5 deg around +-10.5 deg. The phase-1 champion's two aims (near post y -1.83, far post y +1.12) sit in it.
- Time needed after the touch: the ball needs ~0.93 s to arrive at 12 m/s (goal at 2.98 s for a touch at 2.05 s in the phase-1 kick) and ~1.15 s at 10 m/s;
  the kicker must not fall (pelvis < 0.2 m ends the episode) until then. Several noisy kicks are lost only to a fall 50-100 ms before the ball arrives.

## 1. Honest success criterion and the chain of sub-goals

Success = a `goal` (ball crosses the line inside the posts before the pelvis has fallen) on a soccer_p2 start, from the OFFICIAL reset (noise +-0.02 rad on
all joints, root anywhere in x [38, 39], y [-1, 1]), no oracle information (only what the skill's sensors give: joint angles, muscle state, foot/ball/hip
positions, contacts; the physical keeper at y = 0 is a known constant of the environment, not an observation).
Chain (each stage measured on its own, counts per stage in the final report):
 A. kick under noise: the phase-1 kick from its exact start with joint noise scaled 0 / 0.05 / 0.1 / 0.25 / 0.5 of the P2 draw (+-0.001, 0.002, 0.005, 0.01 rad)
    and root offsets (5-10 cm short / wide): the noise ladder. Metric: `kick_ok` (fast ball inside the window and the kicker up until it crosses).
 B. the plant (the swing foot lands beside the ball, 0.75 m ahead of the one-leg hold) from a noisy start.
 C. the approach: from the reset's position (0-1.4 m from the phase-1 stance) to the plant's start.
 D. coverage: all of the above from the official reset.
Go/no-go after A (about 3 hours of wall clock, i.e. by 11:45): if a closed loop cannot close the +-0.002 rad rung, stop and report what limits it.

## 2. Log (newest last). Every run has its exact command, seeds, result.

- 08:43 start. Read scratchpad/soccer4/LOG.md (agent O), README rounds 1-8, arena README, myo_soccer.py, myo_soccer.w (phase-1 skill), V4 headers.
- 08:55 tools built (scratchpad/kick/): `kcommon.py` (MyoSim subclass KMyoSim: per-tick sensor lines S, replies A and the physics state; KTask: per-step trace;
  a controllable reset = the official P2 draw with noise x scale and a root offset, as p1probe.py of agent O), `kladder.py` (noise ladder + dumps),
  `kprobe.py` (open-loop physics probes from a saved state, no controller process), `kauth.py` (authority map), `kseries.py`.
  FINDING: MyoSuite keeps the physics state in robot.mj_data; snapshot/restore must use it (env.mj_data is a mirror). With that, an open-loop replay from a
  saved state with the recorded activations reproduces the dump bit for bit (max deviation 0.0, checked on 2 runs).
- 09:00 baseline phase-1 champion (bin/champions/soccer_p1-20260926-151503, its params) in the P2 env from the exact P1 start,
  `kladder.py --noise 0,0.05,0.1,0.25 --seeds 5000:5008`: noise 0: 8/8 goals (12.0-12.6 m/s, touch 2.03-2.05 s, goal 2.98 s); noise 0.05 (+-0.001 rad): 4/8;
  noise 0.1 (+-0.002): 0/8; noise 0.25 (+-0.005): 0/8. Falls after the kick 4/8, 6/8, 8/8. Wall time: make_sim 2.4 s + 3 s rollout = 2 s.
- 09:10-09:30 DIAGNOSIS of the phase-1 kick under noise (tools kdiverge.py, kauth.py, klip.py, kpredict.py, kdiscrim.py; 144 dumps = noise 0.05 and 0.1 x seeds 5000-5071 in ckpt/p1base):
  * Where the noise grows (kdiverge.py, noise 0.05, distance to the noise-0 run of the same seed, medians): joint vector 0.02 rad at 0.3 s, 0.04 at 1.0-1.3 s,
    0.10 at the reach (1.4 s), 0.22-0.30 at the plant/swing start (1.7-1.8 s), 0.53 at 1.9 s, 0.68 at 2.0 s; the toe's distance to nominal 3 mm (1.3 s), 1.5-2.7 cm
    (plant), 5.7 cm (1.9 s), 19 cm (2.0 s); toe y 1.5 cm at the swing start, 7.4 cm at 2.0 s (max 13.6). So the run-up turns +-0.001 rad into a 0.2-0.3 rad joint-space
    deviation (mostly hip rotations and the feet's yaw: the stance foot pivots on its toes) and the swing then turns 2.5 cm into ~19 cm.
  * The swing is NOT chaotic in its own state: klip.py (open-loop replays from the swing start with +-eps random joint noise on 15 joints): contact y changes by 0.5-0.9 cm at
    eps 0.005 rad, 1.4-2.8 cm at 0.02 rad (launch +-2-7 deg). The variation comes from the LARGE structured deviations at the swing start (hip rotation -0.29 vs -0.71 rad).
  * The 45 features of the swing-start state predict the outcome badly (kpredict.py, ridge CV): contact y R2 0.3, ball speed R2 0.7; the best single-feature AUC of good vs bad
    kicks is 0.72 (kdiscrim.py). No simple threshold on the sensed state at the plant tells a good kick from a bad one.
  * AUTHORITY (kauth.py: a torque burst of 20 N m for 80 ms about one joint, as muscle drive by the live moment arms, added to the recorded activations of the nominal swing):
    contact y moves by +-3-7 cm at best (kicking hip rotation and adduction, onset 0.08-0.14 s after the swing start), and the ball loses 1-4 m/s and the launch moves 3-17 deg
    with it; plant-leg and trunk torques move y by 1-3 cm. The kicking hip's ADDUCTION sits on its limit (+0.5236) from 1.87 s to the contact in the nominal AND the noisy kicks:
    the aim servo (k_ky) on the adduction offset has no authority; the hip rotation offset goes through the reference slopes and moves the achieved angle the wrong way (rot_k +0.3: -0.07 rad).
  * INTER-LEG CONTACT in EVERY kick: femur_r-femur_l and tibia_r-tibia_l, 14-25 ticks at 1.3-2.0 kN peak (t = 1.8 s), also in the fast kicks; the slow ones add calcn_r-calcn_l
    and 50-65 ticks. The plant foot sits on the ball's line (heel (39.64, -0.03)) and the kicking leg wraps around it. Shifting the plant target sideways (plant_dy 0.065 -> 0.12,
    0.18, 0.25, with or without kick_dy) destroys the kick even at noise 0: the run-up, plant and aim are co-tuned.
  * Failure classes of the noisy dumps replayed from the swing start (kbatch.py; ok = speed > 8.5 m/s, |cross y| in [0.5, 3.2], up until the ball crosses): noise 0.05: ok 37/72
    (goal 37, good kick then fell 14, slow 10, no crossing 5, dead zone 3, wide 3); noise 0.1: ok 17/72 (slow 31, good kick fell 8, wide 7, no touch 4); noise 0.25: 0/8.
    Slow = a late or slow foot (1.7-5 m/s at the touch, touch at 2.1-2.6 s: the leg stalls against the plant leg) or a fast foot that glances (contact y -0.14).
  * The falls after a good kick happen in the `land` chunk 0.3-0.9 s after the touch: the follow-through leg (9 m/s at the touch) swings the pelvis yaw from -0.3 to +1.25 rad
    and the COM 0.6-0.9 m to the left of the plant foot before the kicking foot can land; the ball needs 0.93 s (12 m/s) to 1.15 s (10 m/s), the kicker is down at 0.7-0.95 s.
- 09:12 E1 started (scratchpad/kick/runE1.sh, pid in pids/E1.pid): sep-CMA over the 15 post-touch parameters (follow, land, recover) from the touch checkpoints of the 40 noisy dumps
  (noise 0.05 and 0.1, seeds 5000-5047) whose own contact was good; x0 = the P1 champion params: 27/40 stay up until the goal; 3.5 min per generation. Held out: seeds 5048-5071.
- 09:29 new skill lib/robolab/skills/myo_kick.w (MyoKickSkill < MyoSoccerV4Skill, entry lib/entry/myo_kick.w, ./build.sh myo_kick, 59 s): master switch `kc`; torque-space channels
  (live moment arms of `sense_arms`) for the swing's lateral aim (kicking hip rotation/adduction), the plant hip's heading and the knee. Frozen bin/challengers/kick-a0.
  Identity check: with kc off it replays the P1 champion's dumps bit for bit (replay_bad 0, identical speed/touch/fall on 5 dumps).
