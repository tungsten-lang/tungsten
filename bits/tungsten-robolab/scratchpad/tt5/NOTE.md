# Table tennis: is a miss a timing problem? Slice the ball's path; then solve backwards (3 Oct 2026)

Erik's three messages (3 Oct): "for the ping pong, take a miss, then slice up the ball's path and hit the ball at each position in its path. see if we have a timing issue" / "for each position, we
could also test various angles, paddle orientations, speeds, etc" / "otherwise we could consider solving backwards". Everything below is a LABELLED DIAGNOSTIC ORACLE except the first table (the champion's
own stroke); none of it is comparable with the official trial. Tools in this directory; oracle modes `o4` (kinematic paddle), `o5` (ideal arm servo), `o6` (weld), `o7` (trunk lock), `o8` (shifted replay of a
recorded stroke) and the `orc_plan` / `orc_traj` task attributes (one serve, many plans) in `playground/tasks/myo_tt_oracle.py`; identity of the oracle-off path and of o5 re-checked after the edits (see the end).

## 1. What the champion's 200 serves are (plain stroke, sets A 98000-98099 + B 830000-830099)

77 solved (38.5 %), 100 TOUCHED BUT NOT RETURNED (50 %), 23 pure misses (11.5 %). The big loss is the quality of the contact, not reaching the ball.

## 2. The ball's path is a time axis: the champion's own stroke, shifted (`shift_replay.py`, `shift_summary.py`; real physics, mode o8)

The recorded pad trajectory of each serve (pad centre and normal at the 10 ms ticks; a touched serve is continued at constant velocity after its contact so the recoil does not leak) is replayed rigidly
delayed by -100 ... +100 ms against the SAME ball path: the pad meets the ball earlier or later along its path. 200 serves x 21 shifts = 4200 rollouts.
- Validity: the replay at shift 0 solves 56 of the 77 really solved serves, 6 of the 100 touched-not-returned, 0 of the 23 misses (31.0 % against 38.5 %: the rigid puppet has no grip compliance).
- Solved rate at one fixed shift for all serves: flat, 32 % from -30 to +10 ms (31.0 % at 0; best -20 ms 32.5 %): NO BIAS.
- Per serve (the set of shifts whose return is legal): solved serves have a window median 70 ms wide (p25 50, p75 105); the 100 touched-not-returned: a legal shift exists within +-100 ms on 57, the smallest |shift|
  needed median 30 ms (p75 40, p90 54), window width median 40 ms; legal within +-20 ms of the real timing on 25, +-30 on 37, +-50 on 51; the 23 misses: 9 have a window, needing a median 60 ms (3 within 30 ms).
- The timing error (centre of the window, 141 serves with one): median -5 ms, sd 40 ms = JITTER, not bias. It does not follow the ball: corr with the contact time 0.07, with the serve's vx / vz / vy
  +0.02 / +0.01 / +0.16, with the pelvis onset 0.08 (`timing_cause.py`).
- Headroom (replay units, deterministic: each serve moved a fraction f of the way to the centre of its own window): f 0 31.0 %, 0.25 34.5 %, 0.5 41.5 %, 0.75 48.0 %, 1.0 63.0 %; a controller that hits the centre
  with timing error sd j: j 0 63 %, 10 ms 55 %, 20 ms 47 %, 30 ms 40 %, 40 ms (today) 35 %, 60 ms 28 %.
- Without any window at all (orientation, velocity or position wrong at every shift): 43 of the 100 touched-not-returned and 14 of the 23 misses.

## 3. Hit the ball at every position, at many pad angles and speeds (`wall_sweep.py`, `wall_summary.py`; real physics, kinematic wall o4)

7 serves (2 misses, 4 touched-not-returned, 1 solved), slices every 40 ms where the ball is at x 1.3-2.6 m, a rigid pad exactly on the ball, pitch -30..40 and yaw -30..30 (10 degree grid) x retreat speed 0 / 1 / 2 m/s:
8568 rollouts, 73 return legally (0.9 %). At a slice about 3 of the 56 orientation cells are legal at speed 0 (a few at 1 m/s, none at 2 m/s): the pad has to be within about +-7 degrees of ONE angle, which moves
along the path and from serve to serve ((+10, 0) ... (-20, +20) pitch, yaw). The champion's own pad at the slice nearest its contact is 2-16 degrees (typically about 10) from the nearest legal cell and 4-7 cm off the
ball; 15-42 degrees off on the orientation-type serve 98001. The impact model (E 0.95, MU 0.012, ALPHA 0.9) agrees with the physics at the cell level with 46 % precision and 75 % recall (10 degree grid: edge effects).
Serve 98067 (a miss) is not a free path after tick 52: the ball hits the champion's body there and rises to 2.8 m (slices after it are meaningless).

## 4. Solving backwards (`backward_plan.py`, `backward_summary.py`; ideal-arm oracle, the best configuration of the PLANE_NOTE ladder)

Plan from the legal return back to the arm: for each serve, 11 slices of the ball's free path around the champion's own contact time (+-100 ms), the impact model gives the legal contact states (pad pitch / yaw on a 1
degree grid, retreat speed 0 or 1 m/s) scored by the landing margin (cushion to the net and table edges); three candidates per slice (best margin at 0 m/s, best margin at 1 m/s, the margin >= 0.15 cell nearest the
champion's own orientation) = about 25 plans per serve, each executed by o1 settled pelvis + o5 time-to-go servo with the arm muscles off + o6 weld + o7 trunk lock, which reports the pad error at the planned contact.
A selection that never looks at the outcome: among the candidates the servo REACHED (pad error <= 1.5 cm and <= 2.5 degrees) the best margin (R2).

| plan | validation 98030-98099 (70) | set B 830000-830099 (100) |
| --- | --- | --- |
| one fixed plan of the earlier ladder (bn0.1: margin >= 0.1, nearest the champion's normal), same servo | 47 = 67 % | 63 = 63 % |
| R1 best margin, no reachability test | 29 = 41 % | 43 = 43 % |
| **R2 backward plan: reached, then best margin** | **59 = 84 %** (touched 70 of 70) | **85 = 85 %** (touched 97) |
| R3 smallest servo error, ignoring the margin | 51 = 73 % | 77 = 77 % |
| R4 hindsight: a solved candidate exists | 65 = 93 % | 93 = 93 % |

A reached candidate is solved 83-84 % of the time, and 90-96 % when its margin is at least 0.4 m (51-70 % below 0.2 m: the old plans sat at the edge of the legal region). The chosen contact times scatter +-35 ms around the
champion's own (median +20 ms): the plan picks WHERE on the path to meet the ball by what the arm can reach, not a fixed plane.
Conditions (an oracle): the ball path is known exactly, the arm is an ideal servo, pelvis settled and trunk locked from foreknowledge, the paddle welded, and the reachability test is a dry run of the servo
(a real planner needs kinematics for it).

## 5. How much of the backward plan survives a realistic execution (same sweep, same selection rule R2; `backward_plan.py` with other modes / configs, `backward_rerun.py`)

- Determinism: re-running the plans R2 picked reproduces 59 of 70 and 85 of 100 exactly.
- Noise in the planner's knowledge of the ball (position error 1 / 2 cm and velocity error 0.1 / 0.2 m/s per axis, one draw per serve; the TRUE ball still arrives where it arrives): R2 87 % / 88 % (1 cm, 0.1) and
  86 % / 86 % (2 cm, 0.2) on validation / set B: no loss (a 3 cm, 0.3 m/s level was started and stopped to free the machine).
- A HAND-HELD paddle (no weld; the champion's grip) under the same aggressive servo (start at 0.15 s, arm muscles off): the plans R2 had picked with the weld give 34 % / 37 % (touched 44 % / 55 %), with the searched
  grip 29 % / 32 %; with candidates and reachability REDONE for the hand-held paddle R2 gives 39 % / 53 % (hindsight 43 % / 56 %; only 30 of 70 and 57 of 100 serves have a candidate the servo reaches with the paddle
  still in the hand); a reached candidate is solved 78-83 % of the time (97 % at a margin of 0.6 m or more). The servo's accelerations shake a hand-held paddle off its plan: the grip is NOT irrelevant once the pad
  is asked to accelerate that hard (the 2 Oct grasp test used the gentler decelerating servo with the champion's pelvis, 1.5-2 g of pad acceleration, and found 163 of 163 contacts retained).
- Servo bandwidth (the computed-torque PD natural frequency o2_omega, 150 rad/s by default; the plans R2 had picked at 150, NOT re-selected): 150 -> 84 % / 85 %, 100 -> 79 % / 75 %, 60 -> 36 % / 38 %, 30 -> 16 % / 14 %.
  The plans need an arm that tracks at about 100 rad/s or better (time constant 10 ms); muscles are far slower, so a real execution must anticipate (feed-forward with the muscle dynamics) rather than correct.

## 6. The torque the servo uses, and the backward plan under muscle-sized torque caps

The servo behind the 84-85 % runs at its 500 N m clip on both shoulder joints (peak median 500, RMS about 300 N m on elv_angle / shoulder_elv; shoulder_rot 467 / 88; elbow 129 / 22; the wrist joints 13-36). The arm muscles'
maximum ISOMETRIC torques (sum of F0 x moment arm over the muscles pulling that way, reset posture, no force-length-velocity): elv_angle +73 / -112, shoulder_elv +108 / -71, shoulder_rot +79 / -100, elbow +53 / -66,
pro_sup +11 / -15, deviation +14 / -26, flexion +23 / -28 N m. So the uncapped oracle is a planning ceiling with an arm 5-7 times stronger than the real one. The sweep re-done with per-joint caps (new oracle option
`o2_taumax_j`), candidates and reachability redone under each cap, R2:

| execution | validation (70) | set B (100) | hindsight (val / B) |
| --- | --- | --- | --- |
| weld, torque clip 500 (the first table) | 84 % | 85 % | 93 / 93 % |
| weld, caps 90 / 90 / 90 / 60 / 13 / 20 / 25 N m (about the isometric capacities) | 76 % (53) | 77 % (76 of 99) | 86 / 90 % |
| weld, caps 55 / 55 / 55 / 35 / 8 / 12 / 15 N m (about 60 % of them) | 67 % (47) | 73 % (73) | 84 / 80 % |
| HAND-HELD paddle, torque clip 500 | 39 % (27) | 53 % (53) | 43 / 56 % |
| HAND-HELD paddle, caps 90 / 90 / 90 / 60 / 13 / 20 / 25 | 34 % (24) | 49 % (49) | 43 / 56 % |

Reading: the plan-selection gain survives muscle-sized torque limits (77 % at the isometric capacities, 67-73 % at 60 % of them, against 63-67 % for the single fixed plan with an UNLIMITED servo); what it does not survive
is the hand: with the paddle in the hand only 30 of 70 and 54 of 100 serves have any candidate the servo reaches (the paddle leaves its plan under the servo's accelerations), and the torque cap changes nothing there.
The limit has moved from "the plan" to "the hold": a rigid hold is worth 25-40 points, and a muscle-level execution (activation dynamics, redundancy) has not been tested at all.

## 7. What it means (3 Oct)

1. The champion's 38.5 % is not mostly a reach problem (23 of 200 serves are pure misses); it is the quality of the contact: position (cm), angle (+-7 degrees), speed and TIMING (+-30 ms) all at once, and the champion's
   timing jitter (sd 40 ms) alone costs about 25-30 points at equal everything else.
2. The earlier ladder's "about 65 % for an ideal-everything oracle" (PLANE_NOTE items 7-8) was a property of ONE plan per serve sitting at the edge of the legal region (margin 0.1-0.2 m); choosing the contact state
   backwards from the legal set (where along the path, which angle, which speed) with a reachability test gives 84-85 % with the same servo (hindsight 93 %), 67-77 % under muscle-sized torque limits.
3. The binding constraints of a real controller are the paddle hold under acceleration (hand-held 39-53 %) and the arm's tracking bandwidth (about 100 rad/s needed; muscles are far slower), not the plan.
4. Next, if table tennis is continued: (a) an acceleration-limited backward planner (the reachability test as kinematics + a bound on pad acceleration, so that plans exist that the hand can hold), (b) the grip search
   with the backward-plan servo as its stress test (it found +10 points only against the gentle servo), (c) a muscle-level realisation of the servo (static optimisation of the activations with the muscles' own
   dynamics and a feed-forward torque profile), then (d) the real skill: replace the champion's fixed contact plane by the backward selection.

## 8. Integrity of the oracle module after the o4-o8 / `orc_plan` / `orc_traj` / `o2_taumax_j` edits (all opt-in)

`scratchpad/tt3/identity.py` with the switch off: 6 of 6 serves identical to the official task (standard and fast paths); mode o5 alone reproduces its earlier validation numbers exactly (58 contacts, 26 solved, 1.07 cm, 3.51 deg,
0.59 m/s); the plans R2 picked re-run under the same configuration reproduce 59 of 70 and 85 of 100 exactly. Files: `shift_replay.py`, `shift_summary.py`, `timing_cause.py`, `miss_spacetime.py`, `slice_model.py`, `wall_sweep.py`,
`wall_summary.py`, `backward_plan.py`, `backward_summary.py`, `backward_rerun.py` (data and logs in `out/tt5/`, git-ignored).

## 9. Why the hand-held paddle is lost, and the retention-aware backward plan (3 Oct, later; `hand_diag.py`, `joint_rerun.py`, `accel_select.py`, oracle modes o9 and `o5_minjerk`)

- The loss is ACCELERATION. The 170 plans R2 picked, run hand-held under the pad-space servo (start 0.15 s, caps at the isometric capacities): the paddle left the hand (palm-to-paddle distance above 0.3 m) in 95, median at 0.27 s,
  long before any contact; palm peak acceleration before the loss median 358 m/s^2 (palm speed 9.7 m/s) against 132 m/s^2 (3.8 m/s) in the 75 runs that kept it; kept in 100 % of the runs with peak palm acceleration up to
  80 m/s^2, 97 % up to 120, 91 % up to 200, 13 % above 200. Grip drive 0.5 / 1.0 / 2.0 changes nothing (33-40 % solved); an all-fingers-maxed grip keeps the paddle more often (touched 40 / 66 instead of 31 / 55) but returns only 3-4 %.
- A min-jerk pad-space approach (`o5_minjerk`) does not help (hand-held 33 % / 49 %): the DLS tracking of the moving target is itself jerky. A JOINT-space min-jerk move (`o9`: from the champion's own arm posture at t_start
  to the joint configuration the welded dry run of the same plan ended in, computed-torque PD with the reference acceleration as feed-forward), then the pad-space servo for the last 0.10-0.15 s, welded: 63 % / 72 %
  (dry run 74 % / 75 %); hand-held, plans as R2 picked them: 24-30 % (start 0.04 s: 1-5 %, the grip has not closed; 0.08: 7-12 %; 0.11-0.15: 27-30 %; 0.20-0.25: 14-25 %).
- What predicts the loss is the move the plan asks for: A = max_j 5.77 |dq_j| / T^2 (the min-jerk joint acceleration, T the joint-space window, about 0.19-0.28 s). Hand-held, the plans R2 had picked ranked by A:
  A 28-92 rad/s^2: paddle kept in 95 %, solved 90 %; 92-223: 43 % / 20 %; 234-390: 10 % / 5 %; above 399: 2 % / 0 %.
- RETENTION-AWARE selection (R5: among the welded-sweep candidates the servo reached, with A <= A_max, the best margin; start 0.12 s, blend 0.10, lead 0.05; 3290 candidate runs, still pad only), hand-held:
  A_max 40 rad/s^2: 52 of 170 serves have such a plan, solved 62 % of them (paddle lost in 1); A_max 60: 74 serves, 54 % (10 lost); A_max 90: 100 serves, 38 % (35 lost); A_max 130: 129 serves, 29 % (64 lost);
  the serves without a gentle plan fail (1-5 % solved, the paddle lost in almost all).
- A controller that used the gentle backward plan where one exists and the champion's own stroke elsewhere would solve 44-46 % of the validation serves (champion 42.9 %) and 39 % of set B (34.0 %): +1 to +5 points.
- Reading: with the champion's start posture, stance and grip, the hand can only hold plans that need joint accelerations of about 40-60 rad/s^2 (palm 130 m/s^2), and such plans exist for only 30-45 % of the serves; the
  planner's freedom was the contact state (where on the path, which angle). The untried freedom is the STANCE and the READY POSTURE (where the pelvis stands, where the arm waits), which set how far the arm must travel,
  and the grip (a firm grip that does not change the pad's orientation). Next: backward planning that includes the pelvis target (the dry-run sweep with a pelvis offset per candidate), then a grip search with
  retention at 60-100 rad/s^2 as its stress test.

## 10. Stance in the plan, and a faster grip: neither frees the hand-held plan (3 Oct, evening; `backward_plan.py --stance`, `accel_select.py --tag`, `joint_rerun.py --stance --set`)

- STANCE (candidates carry the pelvis target = the champion's contact stance moved with the pad's horizontal displacement, slides = minus the world pelvis position; pelvis settled relative to the plan's contact time, `o1_plan_time`):
  welded dry run (caps at the isometric capacities, still pad) R2 67 % / 67 % against 74 % / 75 % without the stance (hindsight 87 / 88 %); the number of serves with a retention-feasible reached plan barely moves
  (A <= 40 rad/s^2: 56 serves against 52; <= 60: 75 against 73; <= 90: 87 against 84). Hand-held (joint-space min-jerk + pad refinement, start 0.12 s): on the feasible serves 35 % solved at A <= 40 (60 serves, the paddle
  lost in 3; the welded dry run solved 50 of them) against 62 % without the stance; 30 % at A <= 60 and 90. The pelvis carries the pad but the palm still feels the pelvis's acceleration (a 0.3-0.5 m slide in 0.2-0.3 s is
  70 m/s^2), so the retention budget is the palm's TOTAL acceleration and the stance moves load from the arm to the pelvis instead of removing it.
- A faster, stronger grip (grip_ramp 0.02, grip_drive 0.5) with an earlier start (0.08 / 0.04 s) on the A <= 90 plans: solved 6-13 %, the paddle lost in 44-70 of 70 / 100 (against 23 % and 43 / 57 at 0.12 s with the champion's grip):
  the paddle is not held firmly at that time whatever the finger command (it starts in the hand's reset grasp).
- Reading: with the champion's hand and grasp, the paddle can be moved with a palm acceleration of at most about 130 m/s^2 in total, which leaves gentle legal plans for 30-45 % of the serves, and neither the stance nor the
  grip timing found in these scans changes that. A better hand-held result needs either a grasp that holds at 30-40 g (the 2 Oct grip search stressed 1.5-2 g) or a controller that spends the whole ball flight (0.5-0.6 s)
  on a gentle move, i.e. starts it earlier with a firm grip, i.e. the same grasp problem again.

## 11. Grip search under the backward-plan servo (3 Oct, night; `grip_search_bwd.py`, rules fixed in its docstring before the run): NEGATIVE

Separable CMA-ES over the twelve grip parameters (the 2 Oct search's), 12 candidates x 20 generations (about 33 minutes), objective = the share of 57 TRAINING plans solved hand-held (o1 + o5 pad-space servo + o7, torque caps
at the isometric capacities, the plans R2 picked in the welded caps sweep) plus 0.25 x the share touched; 113 plans held out. Pre-registered pass rule: the best grip solves at least 55 % of the held-out plans AND keeps the
paddle in the hand (palm_err_max below 0.3 m) on at least 70 %. Result, held-out, run once: champion grip 33 of 113 solved (29 %), paddle kept 41 (36 %); best grip 37 solved (33 %), kept 42 (37 %). NOT MET: no grip of this family holds
the paddle under the backward plans' accelerations (training best 25 of 57 against the champion grip's 21; the search never left the champion's neighbourhood in what mattered). With section 10 this closes the hand-held route
within the current hand model and finger-activation control: the plan ceiling is 76-85 % (rigid paddle), the hand-held result is 29-37 % whatever the grip, stance or servo shape tried, and only plans a gentle move can reach
(30-45 % of the serves) are held.

## 12. A DIRECTIONAL retention model (3 Oct, night; `gentle_sweep.py`, `retention_select.py`, oracle retention measures `ret_lat / ret_ax / ret_n / ret_tot`): the prediction does not transfer

- Where the hold fails (170 hand-held runs under the pad-space servo): the palm's acceleration ACROSS the paddle in its plane (the direction that twists it about the handle axis) separates lost from kept best: threshold 80 m/s^2,
  95 % accuracy (along the long axis 120 m/s^2, 88 %; along the normal 115, 84 %; total 240, 94 %); logistic coefficients 6.98 (across) / 1.59 (normal) / 0.28 (axial); the kept share is 100 % below 30 m/s^2 of it, 98 % below 60,
  90 % below 100, 78 % below 150, 57 % below 250.
- The gentle execution (joint-space min-jerk + pad-space refinement) as a WELDED dry run of every still-pad candidate (3290 runs, start 0.12 s, blend 0.10, lead 0.05, torque caps at the isometric capacities) gives each
  candidate's pad error and its retention measures; R6 = among the reachable candidates with ret_lat <= LAT (and ret_ax <= 120, ret_n <= 115) the best margin: 79 / 89 / 98 / 116 / 134 of 170 serves have a reachable and retained
  candidate at LAT 40 / 60 / 80 / 100 / 140.
- Hand-held, the SAME gentle move on the R6 plans: solved 16 of 70 and 21 of 100 at LAT 60, 80 and 100 alike (23 % / 21 %), the paddle left the hand in 34-58 runs. The WELDED prediction does not transfer: the measured hand-held
  peak palm acceleration across the paddle is 113 m/s^2 in the lost runs and 36 in the kept, the welded prediction 69 and 29 (ratio median 1.43, correlation 0.20); the loss time has median 0.55 s (p10 0.32, p90 0.82), partly after
  the contact. Bounding the pad-space correction's speed (o5_step_clip 0.01-0.04 rad per tick) makes it worse (4-21 % solved): the hybrid needs its corrections to reach the plan, and the corrections of a slipping paddle load
  the hold further.
- Reading: the weld removes exactly what makes the hand-held plan fail (the paddle's own motion in the hand and the servo's reaction to it), so a dry run in the weld cannot select what the hand holds. A retention model would have to be
  learned from hand-held runs of the SAME execution (a few thousand rollouts: cheap), and the achievable ceiling stays near the 29-37 % found, because the loss is a grip-mechanics limit (a cylindrical handle held by friction
  cannot resist the twist of a lateral acceleration above about 80 m/s^2) that no finger activation tried changes.
