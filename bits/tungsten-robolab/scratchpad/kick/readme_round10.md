#### Soccer round 10: the closed-loop kick (9/29, agent P): no-go, and why

Asked for: the first real phase-2 goals from a closed-loop kick (a toe-to-ball servo in the last 100 ms on the phase-1 trajectory), grown stage by stage, with a
go/no-go after the noise ladder. **Verdict: no-go.** No closed loop on the phase-1 kick closes even the +-0.002 rad rung (29 % of held-out starts score, from
96 % without noise), no `soccer_p2` entry was made (0 / 100 goals for every controller, so nothing to promote), and the measurements below say why: the swing is not
where the noise is decided, and the kick's structure depends on a leg-on-leg contact no controller of this body can steer. Everything is in
`scratchpad/kick/LOG.md` (every run with its command line); tools and the skill are listed at the end.

**Three facts about the environment that change the target** (read from the MyoSuite source and checked on the model)

- *The goalkeeper is a decoy.* MyoSuite steps the physics on `robot.mj_data`; `env.mj_data` (what the bridge and the env's `step` read and write) is a mirror rebuilt from
  the sensors after every step. The keeper's mocap body is moved on the mirror only, so the OBSERVED keeper (random y; stationary / random / block_ball for 58 / 30 / 12
  of seeds 5000-5099) never touches the ball, while the PHYSICAL keeper stands still at (50, 0) with a 0.25 m capsule: a 12 m/s ball aimed at y = 0.0 comes back, y = +0.3
  is deflected, |y| >= 0.5 crosses clean. The scoring window is cross y in +-[0.5, 3.2], a launch angle of +-[2.9, 17.8] deg; the champion's two aims (y +1.1 / -1.8) sit in it.
  (Consequence for tooling: snapshots of the physics must read and write `robot.mj_data`; an open-loop replay from a saved state with the recorded activations is then
  bit-identical, and so is a fresh controller re-fed the recorded sensor lines: `scratchpad/kick/kreplay.py`.)
- *Coverage.* The official starts (seeds 5000-5099) are 0.15 / 0.3 / 0.5 / 0.75 / 1.0 m or less from the phase-1 stance for 2 / 6 / 20 / 42 / 77 of the 100; behind the
  stance by <= 0.3 m and |dy| <= 0.3 m: 10. A perfect kick that needs the phase-1 stance to +-0.3 m can score at most ~6-10 goals.
- *The kick needs ~+-2 cm laterally.* Champion, noise 0, root offsets (6 starts each): dx -0.02 / -0.05 m 6 / 6 and 6 / 6, -0.075 / -0.1 m 0 / 6 (the plant lands short and
  the run-up falls), +0.03 / +0.05 m 3 / 6 and 6 / 6; dy +0.02 m 3 / 6, -0.02 m 0 / 6 (a 11 m/s ball, then a fall), +-0.05 and +-0.075 m 0 / 6.

**The noise ladder** (full rollouts, official metric `goal`, held-out seeds 6000-6047, phase-1 champion `bin/champions/soccer_p1-20260926-151503`; noise scale x the P2 draw of
+-0.02 rad on every joint, root at the phase-1 stance; `scratchpad/kick/kltable.py`, `out/ladder_champion_48.json`)

| rung | noise | plant landed (swing reached) | touched | ball >= 8.5 m/s | inside the window | goals | fell before the touch | fell at all |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | none | 48 | 48 | 48 | 47 | 46 | 0 | 2 |
| 0.05 | +-0.001 rad | 48 | 48 | 39 | 27 | 18 | 0 | 27 |
| 0.1 | +-0.002 rad | 48 | 48 | 23 | 15 | 14 | 0 | 28 |
| 0.25 | +-0.005 rad | 48 | 41 | 9 | 6 | 8 | 5 | 36 |
| 0.5 | +-0.01 rad | 48 | 34 | 5 | 1 | 0 | 14 | 44 |
| 1.0 | +-0.02 rad (official noise, phase-1 position) | 47 | 28 | 3 | 1 | 0 | 20 | 46 |

Per stage, all of 48 held-out starts (seeds 6000-6047): the plant lands in every start at every rung, so the failure is not "the run-up falls before the kick" until +-0.005 rad; it is a kick
that happens and goes slow or sideways (mean ball speed 12.3 / 9.8 / 7.9 / 4.8 / 3.8 / 1.9 m/s) and a body that falls after it (27 of 48 at +-0.001 rad).

(Development set, seeds 5000-5071, `kladder.py`: +-0.001 rad 38 / 72, +-0.002 rad 18 / 72.) On the official reset (`soccer_p2` seeds 5000-5099) the champion, whose default
`approach` walks quasi-static steps to the stance first, per stage: on its feet at 1.5 s 75 / 100 (median fall 1.68 s), run-up reached the swing 1, touched the ball 1, goal 0
(within 0.3 m of the stance: 6 / 6 up at 1.5 s, still 1 touch). Agent O's numbers for the other stages stand: plant from the right-leg hold best 4.3 of ~13, standing kick
1.7 m/s, coverage not started. Mine below.

**What limits the swing-phase closed loop** (each item is a measurement; the tools are in `scratchpad/kick/`)

- *Where the noise grows* (`kdiverge.py`, +-0.001 rad, distance to the noise-0 run of the same seed): joint vector 0.02 rad at 0.3 s, 0.04 at 1.0-1.3 s, 0.10 at the reach, 0.22-0.30
  at the plant, 0.68 at 2.0 s; the toe's lateral error 1.5 cm at the swing start, 7.4 cm (max 13.6) at the touch. The state at the swing start predicts the contact badly (ridge on 45
  features: contact y R2 0.3, ball speed 0.7; best single-feature AUC 0.72), yet the swing itself is smooth: +-0.005 rad of joint noise at the swing start moves the contact by
  0.5-0.9 cm (`klip.py`). The deviation is the large structured one (hip rotation -0.29 vs -0.71 rad) that the run-up leaves.
- *Oracle headroom* (`khead.py`, replays from the swing start on 48 noisy starts, champion 16 / 48 good): the best of 24 random +-10 % variants of 13 swing parameters, chosen per
  start, is good on 22 / 48. The failures are decided before the swing; no choice of swing parameters or feedback on them recovers most of them.
- *No authority in the aim servo.* The kicking hip's adduction sits on its 0.5236 rad limit from 1.87 s to the touch in every kick (the champion's `k_ky` servo drives it there:
  5x its gain changed nothing, as O found), and joint-offset targets on the hip rotation go through the reference length tables, which in the swing posture give the wrong sign
  (`rot_k` +0.3 moved the achieved rotation by -0.07 rad). In torque space (live moment arms, `kauth.py`: 20 N m for 80 ms about one joint of the kicking leg, spread over the muscles
  that cross it) the contact moves +-3-7 cm at best and the ball loses 1-4 m/s; plant-leg and trunk torques move it 1-3 cm.
- *The kick is guided by leg-on-leg contact.* Thigh-thigh and shank-shank contact of 1.3-2.6 kN in every phase-1 kick (14-25 ticks in the fast ones; the slow ones stay in contact 17-65 ticks and add foot-foot contact);
  with the model's 14 explicit contact pairs switched off (diagnostic, `KICK_NOLEGCOL=1`) the champion scores 0 / 16 at noise 0 (16 / 16 with them). Moving the plant foot 5-20 cm
  sideways (`plant_dy`), which would clear the legs, breaks the kick at noise 0: the run-up, plant and aim are co-tuned.
- *Which reset noise matters* (`kladder.py --groups`, +-0.002 rad on a subset of the 48 joints, 16 starts, goals): spine only 13, right leg only 5, left leg only 9; right hips 11, right knee
  13, right feet 13, right SLAVED KNEE JOINTS (the 8 equality-constrained translation/rotation/patella coordinates, given noise of their own = a constraint violation the solver removes
  with a jolt at t = 0) 7, left slaved knee joints 8. A long settle does not filter it (t_set 1.5 s: the joint-vector deviation is still 0.26 rad after 1.4 s at the official noise, the soft joints keep
  their angles, the COM is back within 2 cm), and the phase-1 run-up does not start from a settled stance (0 / 8 at noise 0).
- *The falls after a good kick* (19 % of the +-0.001 rad kicks, 11 % at +-0.002) are a flight, not a loss of balance: 0.2 s after the touch both feet carry 0 % of the weight (straight plant leg,
  the follow-through's reaction; pelvis 1.00 -> 1.07 m, yaw swings -0.27 -> +0.56 -> +2.1 rad), the plant foot whips 0.7 m across, the landing is rotated. The single-leg routine's stance terms after
  the touch (`kr`: cp4 + twist-limited heading hold with the hold's parameters) take the noisy good-contact starts that stay up until the goal from 27 to 31 of 40 on the training set and from 18 to 19 of 27 on held-out ones (fixed 3, broke 2), but at noise 0 they
  break the champion's own follow-through: 6 / 12 goals instead of 12 / 12 (`kltable.py`, seeds 6000-6011). One-parameter scans of the follow-through, landing and plant-leg posture around it move the
  40-start score by at most +1, and a torque-space brake of the follow-through does nothing.
- *Landing the plant foot on the capture point* (`kp`, the plant stage: the reach lands its foot on a fixed spot beside the ball while the body is falling onto it): moving the landing spot by the COM's
  velocity times a gain (`kp_cpx` forward, `kp_cpy` sideways; full rollouts, held-out seeds 6000-6047, goals of 48 at noise 0 / 0.05 / 0.1 / 0.25): champion 46 / 18 / 14 / 8; `kp_cpx` -0.05: 47 / 29 / 11 / 3; -0.1:
  48 / 20 / 9 / 5; the sideways gain trades one side's lateral tolerance for the other's (`kp_cpy` -0.03: dy -0.02 m 6 / 6 but dy +0.02 m 0 / 6 and noise 0 3 / 6). A mixed picture within the sampling noise
  of 48 starts (the champion scores 38 / 72 at +-0.001 rad on the development seeds and 18 / 48 on the held-out ones), so not adopted.
- *The kc terms* (torque-space aim, heading, height and speed channels on the swing): one-at-a-time scans of ten gains by hand on 48 noisy starts (champion 16 / 48 good): +300 / -300 on the rotation
  channel 12 / 14, adduction 16 / 16 (pinned on its limit), velocity terms 9-17; sep-CMA over 40 swing, aim, recovery and kc parameters (`runE2.sh`, replays from the swing start) and over the 11 kc
  gains (`runE2b.sh`) stopped after one generation each: x0 stayed the best, and the headroom measurement above says why.
- *The standing kick* (wind-up on the plant leg, then a swing from rest; the state to start from would be repeatable): with the ball in front of the kicking foot the wound-back foot still ends 0.3 m LEFT of
  the ball's line, because the pelvis yaws -0.45 .. -1.1 rad on the plant foot during the wind-up (the plant hip's rotation hits its -0.7 stop; the known one-leg heading blocker, README round 3). A torque
  heading hold on the plant hip (clipped at the foot's ~50 N m grip) moves the yaw at the swing start from -0.56 to -0.45; kicks 0-2 m/s, 0 goals.

**What was built** (opt-in, the champion replays bit for bit with every switch off: checked on noisy dumps)

- `lib/robolab/skills/myo_kick.w` (+ `lib/entry/myo_kick.w`, `./build.sh myo_kick`; `MyoKickSkill < MyoSoccerV4Skill`): `kc` torque-space channels on the swing (kicking hip rotation / adduction from the toe's
  lateral error and velocity, plant-hip heading and adduction, knee and hip from the toe's height and speed against the practised path), `kr` (routine stance terms after the touch, plus a plant-leg posture
  and a torque brake for the follow-through), `kw` / `kt` (a standing kick's wind-up and swing as a joint torque servo of the kicking leg, and a torque heading hold), all through one generic torque channel
  (`kc_torque`: a joint torque spread over the muscles by their live moment arms, the way `Controller#split_torque` does with the geometry's). Params `params/myo_kick_base.txt` (champion + `kc 1`,
  `sense_arms 1`, gains 0), `params/myo_kick_kr0.txt`, `params/myo_kick_lab0.txt`; frozen `bin/challengers/kick-a0` ... `kick-a8`.
- The harness (`scratchpad/kick/`): `kcommon.py` (per-tick sensor lines, replies and physics state of a run; controllable reset: the P2 draw x a noise scale, joint groups, root offsets), `kladder.py` /
  `kltable.py` / `kstages.py` (ladders and stage counts), `kprobe.py` / `kauth.py` / `kfb.py` (open-loop physics probes and authority maps from a saved state), `kreplay.py` (a saved state restored, a
  fresh controller re-fed the recorded sensors, then live: identity check bit for bit; ~0.5 s per replay), `kbatch.py` / `kscan.py` / `ksearch.py` (batches, one-at-a-time scans and sep-CMA on replays,
  resumable), `khead.py`, `kdiverge.py`, `kpredict.py`, `kdiscrim.py`, `klip.py`.

**Next, if this line is continued** (none of it is a swing-phase feedback): a kick whose plant foot stands beside the ball, so the swing needs no leg-on-leg contact, re-optimised stage by stage from
checkpoints with the replay harness (swing from the plant, plant from the lift, ...); a torque-space stance and heading controller for the run-up in place of the offset servos (live moment arms are
the mechanism that works at the hip); and an approach, which needs a walking gait this body has not shown (the spine folds), since 0.3 m of coverage is at most 6-10 of the 100 starts.
