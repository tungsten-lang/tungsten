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
- (time correction: the E1 entry above says 09:12; the real times, from `date`: E1 started 09:26 and was stopped at 09:34 after 2 generations to free the workers
  (state kept in out/E1.txt.state.pkl, resumable: `scratchpad/kick/runE1.sh`; generation 1: best 30/40 stay up vs 27/40 for the champion's recovery).)
- 09:34 dumps with the arm sensors: `kladder.py --controller bin/challengers/kick-a1 --params params/myo_kick_base.txt --noise 0.05,0.1 --seeds 5000:5072 --dump ckpt/kbase --tag kbase`
  (params/myo_kick_base.txt = the P1 champion's params + `kc 1` + `sense_arms 1`, kc gains 0): identical to the champion (noise 0: 8/8 seeds bit-identical speed, touch time and
  crossing); full rollouts: noise 0.05 goals 38/72, noise 0.1 goals 18/72 (the champion's own dumps: 37/72 and 17/72 replayed from the swing start).
- 09:37 MISTAKE (recorded): kscan.py had no `if __name__ == "__main__"` guard, so multiprocessing (spawn) re-ran the script in every worker: a spawn storm (23 MB of
  tracebacks in the task output) until I killed the tree (pid 2340 and its children, own PIDs only; the .venv-myo workers of agent K's arena_ng.py were not touched). Every
  script that opens a Pool now has the guard.
- 09:48 hand scan of the kc terms on replays (kick-a1, dumps kbase, noise 0.05 and 0.1 seeds 5000-5023 = 48 packs, from the swing start; scratchpad/kick/logs/scan1.log),
  ok = fast (>8.5 m/s), inside the window, up until the ball crosses: baseline (all gains 0) 16/48; kc_rk +300 12, -300 14 (torque on the kicking hip's rotation per metre of toe
  lateral error); kc_ak +-300 16 and 16 (the adduction is on its limit: no effect); kc_rv +30 11, -30 9; kc_av +30 9, -30 17. No channel helps by hand; the torque bursts trade
  ball speed for direction (kauth.py). 22 s per candidate for 48 packs on 2 workers.
- 09:50 (all times below from `date`) hand-scan, headroom oracle, noise-source experiments (kladder --groups, kick-a1, noise scale 0.1, 16 seeds, full rollouts):
  * headroom (khead.py, replays from the swing start, 48 noisy packs, the champion 16/48 ok): 24 random variants (+-10 % of the range on 13 swing parameters); per pack
    the best of the 24 is ok in 22/48 packs (mean best score 12.3 vs 9.7), the best single variant 16/48. So even an oracle that picks the swing parameters per start
    gains 6 packs of 48: the failures are decided before the swing.
  * which reset noise matters (noise scale 0.1 on a subset of the 48 `myo_joints`, others exact; goals/16): spine and trunk joints only 13, right leg only 5, left leg only 9;
    right hips 11, right knee angle 13, right ankle+subtalar+mtp 13, right KNEE COUPLED JOINTS (the 8 slaved translation/rotation/patella joints `knee_angle_r_*`) 7;
    left hips 8, left knee 12, left knee coupled joints 8, left feet 12; all joints but the hips 4, all but the knee coupled joints 5 (but 11 m/s balls: 12/16 fall after the kick),
    knee main + feet + trunk only 12. The noise on the slaved knee joints (an equality-constrained coordinate given +-0.02 m/rad on its own: a constraint violation the solver
    removes with a jolt at t = 0) is the worst single group, then the hips.
  * settling does not filter the reset noise (t_set 1.5 s, kick-a4, noise 0.25 / 1.0 vs 0, dumps ckpt/settle): the joint-vector deviation stays 0.07-0.11 rad (0.25) and 0.26 rad
    (noise 1.0) after 1.0-1.4 s of standing (the soft joints - hip rotations, subtalar - keep their noisy angles), while the pelvis and the COM are back within 1-2 cm.
    A settled stance does not start the phase-1 kick (0/8 at noise 0: the run-up is tuned to the key frame's first 0.4 s).
  * the phase-1 kick needs the inter-leg contact: with the model's 14 explicit contact pairs (thigh-thigh, shank-shank, ...) switched off (pair_margin -1000, diagnostic only,
    KICK_NOLEGCOL=1) the champion scores 0/16 at noise 0 (ball 2 m/s, every start falls); with them, 16/16. The swing wraps around the plant leg with 1.3-2.6 kN.
  * official soccer_p2 seeds 5000-5099 (out/p2_starts_5000_5099.json): root offset from the P1 stance: within 0.15 m 2/100, 0.3 m 6, 0.5 m 20, 0.75 m 42, 1.0 m 77, all within 1.5 m;
    behind by <= 0.3 m and |dy| <= 0.3 m: 10/100; <= 0.5 and <= 0.5: 21/100. Keeper policies 58 stationary / 30 random / 12 block_ball (all decoys, see section 0).
- 10:27 KR: after the touch the kicker balances on the plant foot with the single-leg routine's terms (V4 cp4 + tlh, hold parameters of params/myo_soccer_single_leg_310_ramp.txt,
  MyoKickSkill switch `kr`, params/myo_kick_kr0.txt, binary bin/challengers/kick-a5): on the 40 noisy dumps with a good contact (0.05 and 0.1, seeds 5000-5047), replays from the touch:
  the champion's follow-through 27/40 stay up until the goal, kr 31/40 (untuned). E1k (runE1k.sh) tunes kr's and the landing chunks' parameters (28) on the same 40.
- 10:41 quick torque-space standing-kick probes in the lab (feet 0.35 m behind the ball, ball in front of the kicking foot; MyoKickSkill kw/kt): the wound-back foot ends 0.3 m LEFT of
  the ball's line because the pelvis yaws -0.45..-1.1 rad on the plant foot during the wind-up (the plant hip's rotation hits its -0.7 stop; the known one-leg heading blocker);
  a torque heading hold on the plant hip (kt_yk, clipped at the foot's ~50 N m grip) only takes the yaw at the swing start from -0.56 to -0.45; kicks 0-2 m/s.
- 10:42 post-kick falls, kr on (replays from the touch, seeds 5016/5013/5031, kbase dumps): the falls happen because the body LEAVES THE GROUND: at +0.20 s after the touch both feet carry 0.00
  of the body weight (the plant leg is straight, ks_dz 0.796 of a 0.795 m leg, with the follow-through's reaction: pelvis 1.00 -> 1.07 m, yaw swings -0.27 -> +0.56 -> +2.1 rad), flight until
  +0.55 s, the plant foot whips 0.7 m across to y -0.54, the landing is rotated and the COM is 0.3-0.9 m left of the plant foot. Single-parameter scans of the recovery around kr
  (40 good-contact packs, replays from the touch, x0 31/40): drv_post 0.6/0.4/0.2/0 -> 31/31/30/29 (kr off: 24/18/16, replay-mismatch rows, invalid); kr_dz (post-touch plant leg height,
  kick-a7) 0.796/0.75/0.7/0.65/0.6 -> 31/28/24/24/24; drv_brake 0.5/0.8/1.0 -> 31/27/27; t_follow 0.15/0.3 -> 27/32; th_fol 0.1/-0.4 -> 29/27; knee_fol 0.5/1.8 -> 26/26; th_land -0.1/0.6 ->
  28/31; torque-space brake of the follow-through (kr_bk/kr_bkk on the hip flexion / knee velocity, kick-a8) 0-25 -> 29-32. Nothing beyond +1 of 40: the recovery is at a flat local optimum.
  E1k (sep-CMA over 28 recovery/stance parameters of kr, runE1k.sh) stopped after 3 generations (x0 31/40 stayed the best; 3 min per generation).
- 10:51 HELD-OUT check of kr (untuned, hold parameters as they are; seeds 5048-5071, both noise levels, good-contact packs = 27 of 48): champion follow-through 18/27 stay up to the goal, kr 19/27
  (paired: fixed 3, broke 2). Pooled with the training packs +5 of 67 (7 %): a structural but small gain, not significant.
- 10:52 FINAL LADDER started (runFinalLadder.sh, out/ladder_final.json, logs/final_ladder.log): champion vs kick-a8 + params/myo_kick_kr0.txt, seeds 6000-6011 (held out), rungs 0/0.05/0.1/0.25/0.5,
  offsets dx -0.05/-0.1, dy +-0.1 at noise 0, and the official P2 reset on seeds 5000-5099.
- 10:57 FINAL LADDER, champion (full rollouts, official metric, held-out seeds 6000-6047, scratchpad/kick/kltable.py, out/ladder_champion_48.json): goals/48 at noise 0 46, 0.05 (+-0.001 rad) 18,
  0.1 (+-0.002) 14, 0.25 (+-0.005) 8, 0.5 (+-0.01) 0, 1.0 (official +-0.02, P1 position) 0; falls 2/27/28/36/44/46; ball 12.3/9.8/7.9/4.8/3.8/1.9 m/s. Offsets at noise 0 (6 starts, out/offsets_champion.json):
  dx -0.02 6/6, -0.05 6/6, -0.075 0/6, -0.1 0/6, +0.03 3/6, +0.05 6/6; dy +0.02 3/6, -0.02 0/6, +-0.05 0/6, +-0.075 0/6. Official soccer_p2 reset, seeds 5000-5099 (kstages.py): up at 1.5 s 75/100
  (median fall 1.68 s, 10th-90th percentile 1.43-1.97 s), run-up reached the swing 1, touched the ball 1, goal 0; last phase reached: the quasi-static approach's steps (l_settle 29, l_reach 19, r_settle 13,
  r_reach 11, l_shift 10, ...).
- 10:57 FINAL LADDER, kr (bin/challengers/kick-a8 + params/myo_kick_kr0.txt, seeds 6000-6011, out/ladder_final.json): noise 0 goals 6/12 (the champion 12/12: kr breaks the nominal follow-through, 6 falls),
  0.05 3/12 (3), 0.1 3/12 (3), 0.25 3/12 (4), 0.5 1/12 (0), official reset 0/100. REJECTED: kr is not an improvement.
- 11:02 E2b started (runE2b.sh: sep-CMA over the 11 kc gains, x0 = 0, kr off, replays from the swing start, noisy dumps 0.05/0.1 seeds 5000-5023 = 48 packs; base 16/48).
- 11:06 KP (capture-point placement of the plant step, MyoKickSkill `kp`, kp_cpx/kp_cpy, kick-a9; full rollouts): 6 starts per cell at noise 0 / 0.05 and offsets dy +-0.02, +-0.05, dx -0.075: kp_cpy +0.1/+0.2 break noise 0 (0/6);
  kp_cpy -0.03/-0.05/-0.07/-0.1: dy -0.02 m 6/6, 3/6, 3/6, 6/6 (champion 0/6) but dy +0.02 m 0/6 (champion 3/6) and noise 0 3/6, 0/6, 3/6, 3/6; kp_cpx +0.03 / -0.05 keep noise 0 at 6/6.
  48 held-out seeds (6000-6047) at noise 0 / 0.05 / 0.1 / 0.25: kp_cpx -0.05 47 / 29 / 11 / 3 (champion 46 / 18 / 14 / 8), kp_cpx -0.1 48 / 20 / 9 / 5. Mixed and within sampling noise: not adopted.
- 11:22 E2b (kc gains) and E2 (40 parameters) each stopped after ONE generation (x0 = 16/48 was the best in both; 4-5 min per generation): the hand scans and the headroom oracle already said the swing-phase terms do not
  have the room; the remaining time went to the final tables.
- 11:24 ARENA (for the record): `playground/arena.py eval soccer_p2 --params params/myo_kick_base.txt --controller bin/challengers/kick-a9 --workers 2` (MyoKickSkill with every closed-loop switch off = the champion's
  behaviour): goal 0.0000 over 100 seeds (85 s); does not beat the champion (0.0000, p = 1.000); not promoted. history.jsonl has the challenge. No soccer_p2 goal from any controller of this round.
- 11:26 GO/NO-GO (gate 11:43, 2 h 43 min after the start): NO-GO. Stage A (kick under noise) is not closed by any closed loop tried: the champion's own ladder is 46 / 18 / 14 / 8 / 0 / 0 goals of 48 at
  noise 0 / +-0.001 / +-0.002 / +-0.005 / +-0.01 / +-0.02 rad; the variants (kc terms, kr recovery, kp placement) are within the sampling noise of it or worse at noise 0; the oracle headroom for any choice of swing parameters
  per start is +6 of 48; the kick depends on leg-on-leg contact; the standing kick is blocked by the one-leg heading. Stages B (plant beside the ball from a hold) and C (approach) were not attacked beyond the kp probe
  and the coverage count (0.3 m of the phase-1 stance = 6 of 100 starts). No process of mine is running at the end (E1k, E2, E2b killed, the ladders finished).
- HANDBACK STATE. Files: lib/robolab/skills/myo_kick.w, lib/entry/myo_kick.w (MyoKickSkill; switches kc, kr, kp, kw, kt; every switch off = the champion bit for bit), params/myo_kick_base.txt, myo_kick_kr0.txt, myo_kick_lab0.txt,
  bin/challengers/kick-a0 ... kick-a9 (a9 = the current bin/robolab_myo_kick), scratchpad/kick/*.py (harness), README "Soccer round 10". Bulky dumps (ckpt/, out/, logs/) are git-ignored and regenerable
  with kladder.py --dump (ckpt/p1base: champion, ckpt/kbase: kick-a1 + params/myo_kick_base.txt, both noise 0.05 and 0.1 seeds 5000-5071 plus noise 0 seeds 5000-5007).
- 11:27 params/myo_kick_kp1.txt written (base + kp 1, kp_cpx -0.05; the best rung-0.05 variant, mixed, not adopted).
