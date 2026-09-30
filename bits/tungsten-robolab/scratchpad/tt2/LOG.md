# Table tennis, labelled BEYOND-HUMAN ARM go/no-go (agent T2, started 2026-09-29 22:53)

Goal: a cheap, honest go/no-go on whether a LABELLED BEYOND-HUMAN ARM (the official MyoSuite table-tennis P2 body, every muscle stronger
and faster, nothing else changed) removes the execution-noise limit that caps the official arm's phase-2 success near 45 % (agent T, scratchpad/tt/LOG.md).
EVERYTHING here is about a BEYOND-HUMAN ARM: an invented stretch, not a human profile, never comparable with tt_p1 / tt_p2 / tt_p2_300 / tt_p2_backhand.
Rules: the official champion (bin/champions/tt_p2_300-20260929-101727 = bin/challengers/myo_tt_r10-n, params/myo_tt_p2_r10_c3.txt) and every official trial are NOT touched;
no git commits; at most 3 rollout workers, one search at a time, nice -n 10 for long jobs; state in the repo (scratchpad/tt2, params/, out/tt2).

## Log
- 22:53-22:59 read HANDOFF_20260929.md, scratchpad/sprint4/LOG.md, playground/profiles/beyond.json, README round 8, scratchpad/tt/LOG.md (agent T), tasks/myo_tt.py, tasks/myo_soccer_ng.py, myo_bridge.py, tt_fast.py, tt_eval.py, arena.py.
  Read-only probe of the compiled official P2 model (scratchpad/tt2/probe_model.py, nothing scored): env.mj_model IS robot.mj_model (one MjModel; the env's mj_data is a separate mirror, the Robot steps its own MjData);
  nu 275 = 273 muscle actuators (dyntype MUSCLE, gaintype/biastype MUSCLE, gainprm == biasprm on columns 0..8) + pelvis_x, pelvis_y (position servos kp 3500, dyntype none);
  the muscles' force is resolved in the compiled gainprm[2] (4.79-2150.7 N; no -1 left), vmax gainprm[6] is 1.5 or 10, dynprm[0] 0.010/0.015 s, dynprm[1] 0.040/0.050 s, no forcelimit; integrator Euler, dt 0.002, 5 substeps per action.
- 22:59 STEP 1a: THE RULE, THE LADDER, THE GO/NO-GO CRITERION AND THE MEASURES ARE FIXED: playground/profiles/myo_beyond_arm.json (created 22:59; before any rollout on any rung).
  Ladder (strength, speed, activation): rung 1 (2.0, 1.7, 0.8), rung 2 (2.4, 2.0, 0.8), rung 3 (3.0, 2.4, 0.8); rung 0 = official. GO iff the unchanged champion at the best rung (most solved of the 100 serves 98000-98099, tie -> smaller rung) solves >= 55/100
  OR pitch sigma < 6 deg AND pad-velocity sigma < 0.35 m/s AND place error < 4 cm (definitions in the file). NO-GO otherwise. If GO: the SMALLEST rung clearing it by itself.
- 23:00-23:03 STEP 1b built: playground/tasks/myo_tt_beyond.py (subclass of MyoTTTask; env var MYO_TT_BEYOND = rung; 0/unset = the official env id and class; rungs 1-3 register `myoChallengeTableTennis<P>Beyond<r>-v0`,
  an env subclass whose `_setup` scales the 273 muscle actuators of the shared MjModel (gainprm/biasprm[2] x strength, gainprm/biasprm[6] x speed, dynprm[0], dynprm[1] x activation) BEFORE the Robot is built; the multipliers are read from
  playground/profiles/myo_beyond_arm.json; metrics beyond_rung / beyond_f0_ratio / beyond_vmax_ratio / beyond_tau_ratio only at rungs > 0),
  playground/tt_fast.py: opt-in `TT_TASK` env var (names a module of tasks/ whose TASK subclasses MyoTTTask; default myo_tt = unchanged behaviour), scratchpad/tt2/{identity.py,smoke_env.py,noise.py,probe_model.py}.
  smoke_env.py (rung 2): the beyond env's compiled model differs from the official compile in exactly actuator_gainprm, actuator_biasprm, actuator_dynprm (F0 x2.4 on all 273 muscles, vmax x2.0 both columns, tau_act and tau_deact x0.8, the two pelvis actuators identical); env.robot.mj_model is env.mj_model.
- 23:03 IDENTITY AT RUNG 0 (`TT_ENV=P2 .venv-myo/bin/python scratchpad/tt2/identity.py --params params/myo_tt_p2_r10_c3.txt --controller bin/challengers/myo_tt_r10-n --seeds 98000..98005`, log out/tt2/identity_rung0.log):
  6/6 serves IDENTICAL on every metric key, official task vs myo_tt_beyond rung 0 (standard path), and beyond rung 0 standard vs fast path (tt_fast, TT_TASK=myo_tt_beyond). 0 differ. (solved 1,0,0,0,0,0 on these six.)
- 23:04 rung-2 fast-vs-standard check (`MYO_TT_BEYOND=2 ... identity.py --seeds 98000..98003`, out/tt2/identity_rung2.log): 4/4 IDENTICAL, audit [rung 2, F0 x2.4, vmax x2.0, tau x0.8].
- 23:04 STEP 2a launched: scratchpad/tt2/run_a.sh (pid in out/tt2/run_a.pid; progress out/tt2/run_a.progress): the UNCHANGED champion (bin/challengers/myo_tt_r10-n, params/myo_tt_p2_r10_c3.txt) on serves 98000-98099, rungs 1, 2, 3 then 0 (yardstick),
  each: `TT_ENV=P2 TT_TASK=myo_tt_beyond MYO_TT_BEYOND=$r TT_SAVE_LOG=out/tt2/logs_r$r nice -n 10 .venv-myo/bin/python playground/tt_eval.py --params params/myo_tt_p2_r10_c3.txt --controller bin/challengers/myo_tt_r10-n --seeds 98000:98100 --out out/tt2/champ_r$r_98000.jsonl --workers 3`.
- 23:06 seed ledger (T2): arena 98000-98299 (trial seeds; the first 100 98000-98099 are step 2a's; the official champion solves 43 of them, 120 of the 300 in the arena); follow-ratio probe serves 810000-810199; tuning training seeds 820000+ (never the arena's, never agent T's blocks 710000/720000/740000/750000);
  fresh finals 900000-900299 (nobody has used them; only finalists are ever evaluated there, once per finalist).
- 23:05-23:07 STEP 2a RESULTS (unchanged champion, 100 arena serves 98000-98099, fast path; scratchpad/tt2/run_a.sh; data out/tt2/champ_r{0,1,2,3}_98000.jsonl, logs out/tt2/logs_r*/):
  | rung (strength, speed, activation) | solved | hit | classes |
  | 0 official (yardstick) | 43/100 | 91 | solved 43, hit out 37, hit own half 6, hit net 5, miss below 4, miss lateral 2, miss within 10 cm 2, miss above 1 |
  | 1 (2.0, 1.7, 0.8) LABELLED BEYOND-HUMAN ARM | 0/100 | 23 | miss lateral 35, miss pad above 32, miss pad below 10, hit out 21, hit own half 2 |
  | 2 (2.4, 2.0, 0.8) LABELLED BEYOND-HUMAN ARM | 0/100 | 0 | miss lateral 47, miss pad above 45, miss pad below 7, miss within 10 cm 1 |
  | 3 (3.0, 2.4, 0.8) LABELLED BEYOND-HUMAN ARM | 0/100 | 2 | miss lateral 93, miss pad below 2, miss pad above 2, miss within 10 cm 1, hit out 2 |
  The rung-0 run reproduces the arena's recorded scores of the tt_p2_300 champion on the same 100 seeds serve for serve (43 solved, 0 seeds differ): the pipeline is the arena's.
  No MuJoCo instability warnings (MUJOCO_LOG.TXT untouched since 13:44). MuJoCo did not blow up; the arm is simply driven wrongly: the paddle leaves the palm (palm_err_max median 1.9 m at rung 1; rung 2 and 3 lose the paddle at about 0.25-0.3 s on
  every serve looked at, during the servo's sweep into the hitting posture).
- 23:08 STEP 2b (noise decomposition, scratchpad/tt2/noise.py, out/tt2/noise_r*.json; definitions in the rule file):
  official yardstick (rung 0, 91 hits): pitch sigma 11.0 deg (fh 8.6, bh 9.1; agent T: about 10), pad-velocity sigma 0.497 m/s (agent T: 0.51/0.62/0.52 per axis), place error 4.28 cm per axis (median distance 5.3 cm; agent T: about 5 cm);
  the reached-vs-asked ready posture reproduces agent T's (forehand: forearm rotation asked 1.20 reaches 0.445, shoulder rotation asked -1.29 reaches -0.78, plane of elevation asked 0.36 reaches 0.98).
  rung 1 (23 hits): pitch sigma 22.4 deg (fh 29.7, bh 9.6), pad-velocity sigma 0.578 m/s, place error 5.51 cm (39% of hits beyond 8.5 cm), forehand wrist flexion at its limit on 7 of 7 hits; rung 2: no hit; rung 3: 2 hits (14.5 deg, 0.18 m/s from two hits, 7.1 cm).
- 23:10 GO / NO-GO (rule of 22:59): best rung = rung 1 (all rungs 0 solved; tie -> the smaller). solved 0 < 55, and the noise measures at rung 1 (22.4 deg, 0.58 m/s, 5.5 cm) are outside their limits (6 deg, 0.35 m/s, 4 cm): **NO-GO**.
  Written into playground/profiles/myo_beyond_arm.json `decision`. The verdict is about the UNCHANGED champion: it fails outright on the stronger arm; the noise numbers at rung 1 come from 23 hits of an arm that loses the paddle, so they are not a measure of the arm's precision.
- 23:10 POST-VERDICT DIAGNOSTICS (never change the verdict; LABELLED BEYOND-HUMAN ARM what-ifs; the ladder is untouched; tasks/myo_tt_beyond.py got rung 9 = MYO_TT_BEYOND_DIAG "strength,speed,activation" at 23:12, added AFTER the verdict).
  D1 code-path check (`MYO_TT_BEYOND=9 MYO_TT_BEYOND_DIAG=1,1,1 ... identity.py --seeds 98000..98005`, out/tt2/identity_unit.log): the env subclass path with unit multipliers is IDENTICAL to the official task on every metric on 6/6 serves (standard and fast path): the failure at rungs 1-3 comes from the multipliers, not from the mechanism.
  D3 one factor at a time on the 100 arena serves, unchanged champion (scratchpad/tt2/run_diag.sh, list scratchpad/tt2/diag_list.txt: s2 = strength 2.0 alone, v17 = speed 1.7 alone, a08 = activation 0.8 alone, s15 = strength 1.5 alone, s12 = strength 1.2 alone), progress out/tt2/run_diag.progress.
- 23:35 D3 RESULTS (post-verdict, unchanged champion, 100 arena serves 98000-98099, LABELLED BEYOND-HUMAN ARM one-factor what-ifs; official = 43 solved / 91 hit; out/tt2/diag_*_98000.jsonl; the s15 run took 21 min of wall (machine stall, load 28), not a different result):
  | what-if (strength, speed, activation) | solved | hit | main classes |
  | strength 2.0 alone (2.0, 1, 1) | 0 | 10 | miss pad above 47, miss lateral 32, hit out 10, miss within 10 cm 10 |
  | speed 1.7 alone (1, 1.7, 1) | 6 | 69 | hit out 47, miss pad below 14, miss lateral 11, hit own half 9, hit net 7 |
  | activation 0.8 alone (1, 1, 0.8) | 16 | 67 | hit out 43, miss pad below 29, hit own half 7 (forehand 13 of 46 solved, backhand 3 of 54) |
  | strength 1.5 alone (1.5, 1, 1) | 0 | 42 | hit out 41, miss lateral 35, pad below 11 |
  | strength 1.2 alone (1.2, 1, 1) | 7 | 42 | miss pad below 54, hit out 31 (forehand 7 of 46, backhand 0 of 54) |
  So EVERY single change of the arm's muscles costs the champion most of its serves: +20 % strength alone 43 -> 7, activation x0.8 alone 43 -> 16, speed x1.7 alone 43 -> 6. The champion's motor program is tuned to the official arm's exact response (agent T found sharp optima: fh_gain 0.97 / 1.03 / 1.06 -> 80 / 76 / 68 of 200);
  the gate "the unchanged champion on a modified arm" therefore measures the controller's brittleness, not the arm's precision.
- 23:36 D2 (post-verdict; scratchpad/tt2/run_stale.sh, diag_stale.py: the controller is told the OFFICIAL peak forces, i.e. a stale MFORCE and normalised-force input, on rung 1 and on strength 1.2 alone): rung 1 0 solved / 23 hit, strength 1.2 alone 7 solved / 42 hit,
  and 0 of 100 episodes differ in ANY metric from the informed runs: the champion ignores MFORCE and the normalised force (its feed-forward param `ff` is 0 and its reflex uses none), so telling the controller the arm's own peak forces (what tasks/myo_tt_beyond.py does) is not a choice that matters.
- 23:38 ASKED vs REACHED ready posture (scratchpad/tt2/posture_ready.py 27 0 1 2 3: row 27 = t 0.28 s, just before the servo starts at 0.277 s, all serves, champion params; commanded -> reached mean, rungs 0 / 1 / 2 / 3):
  forehand forearm rotation (pro_sup, asked +1.20): 0.28 / 0.32 / 0.35 / 0.34; shoulder rotation (asked -1.29): -0.87 / -0.82 / -0.83 / -0.78; plane of elevation (asked +0.36): 0.55 / 0.71 / 0.76 / 0.79;
  backhand forearm rotation (asked +0.89): 0.27 / 0.33 / 0.31 / 0.27; shoulder rotation (asked +1.28): 0.04 / 0.12 / 0.15 / 0.16; plane of elevation (asked -1.23): +0.41 / +0.48 / +0.51 / +0.53 (the sign is wrong on every arm).
  A muscle that is 2-3x stronger and faster does NOT bring the arm closer to the commanded posture: the forearm turn follows 0.23-0.29 of what is asked on every rung (official 0.23). The commanded-vs-reached gap is set by the controller's command mapping (contraction targets from its additive
  length model, saturated co-contraction: effort_act 0.6 = mean squared activation of all 273 muscles at the ready posture on every rung), not by strength, which multiplies agonist and antagonist alike and leaves the equilibrium where it was.
  At contact, on the hits that exist: rung 0 (n 91 hits) forehand forearm turn asked 1.20 reached 0.445; rung 1 (7 forehand hits) 0.496; backhand asked 0.89 reached 0.356 (rung 0) / 0.466 (rung 1).
- Not measured: agent T's face-follow probe (ft_amp / ft_yaw slope of the reached pad normal on an aimed trim) on the beyond arm: it needs a controller that holds the paddle (the champion's paddle ends more than 0.5 m from the palm on 85 of 100 serves at rung 1, 100 at rung 2, 98 at rung 3).
- 23:42 PADDLE LOSS (from palm_err_max = the largest paddle-to-palm distance of an episode; paddle > 0.5 m from the palm at some time, of 100 serves): official 9, rung 1 85, rung 2 100, rung 3 98; strength 1.2 alone 54, activation 0.8 alone 34, speed 1.7 alone 21.
  The paddle is held only by the hand's contacts; the champion's grip is tuned to the official strength, and it is already lost on 9 % of official serves. Per muscle group what-ifs at rung 1's multipliers (2.0, 1.7, 0.8), post-verdict, LABELLED: arm = the 32 ARM_MUSCLES of tasks/myo_tt.py, hand = the 31 finger and thumb muscles, trunk = the other 210
  (MYO_TT_BEYOND_GROUP in rung 9 of the module; scratchpad/tt2/run_diag.sh scratchpad/tt2/diag_list2.txt: g_arm, g_hand, g_trunk).
- 23:42 PER-GROUP RESULTS (rung 1's multipliers 2.0 / 1.7 / 0.8 on ONE muscle group, unchanged champion, 100 arena serves; official 43 solved / 91 hit / paddle lost on 9):
  | group scaled | muscles | solved | hit | paddle > 0.5 m from the palm |
  | arm (ARM_MUSCLES) | 32 | 0 | 10 | 100 of 100 (miss lateral 60, pad below 25) |
  | hand (fingers and thumb) | 31 | 0 | 44 | 1 of 100 (hit out 42, miss lateral 40, pad above 12) |
  | trunk | 210 | 21 | 79 | 13 of 100 (hit out 51, pad below 16) |
  Every group's scaling breaks the champion: the stronger, faster ARM alone flings the paddle out of the hand on every serve (the swing accelerates about 2x; the official swing already loses the paddle on 9 % of serves), stronger fingers alone keep the paddle
  but move it in the hand (44 % hit, none solved), a stronger trunk alone halves the solved count. There is no single piece to leave alone: the champion's motor program is a whole-body tuning to the official strength.
- 23:44 PELVIS SHARE OF THE PAD-VELOCITY NOISE on the official run (scratchpad/tt2/pelvis_part.py, rung 0, 91 hits; velocity along the pad axis at contact): pad 0.21 +- 0.49 = pelvis part 0.31 +- 0.42 (fh 0.34, bh 0.28) + arm/trunk part -0.10 +- 0.25 (fh 0.32, bh 0.17).
  The pelvis slides (two position actuators, unchanged by every rung) carry most of the along-axis velocity spread; a muscle-only variant cannot change that part, so even a perfect beyond-human arm leaves a pad-velocity sigma near the pelvis's 0.28-0.34 m/s unless the pelvis plan is also improved (agent T's pv attempts made it worse).

## FINAL STATE (2026-09-29 23:45)
- VERDICT: NO-GO by the rule of 22:59 (unchanged champion: 0 of 100 at rungs 1, 2, 3; best rung = rung 1 by the tie rule; rung 1's noise measures 22.4 deg / 0.58 m/s / 5.5 cm against limits 6 deg / 0.35 m/s / 4 cm, measured on 23 hits of an arm that loses the paddle).
  The verdict is about the UNCHANGED champion, which does not survive ANY change of its arm's muscles (+20 % strength alone: 43 -> 7 of 100). It is not evidence about what a controller tuned for a stronger arm could reach. Nothing was tuned; no arena trial was registered
  (tt_p2_300_beyond / tt_p2_backhand_beyond were only to be created on GO); no official trial, champion or param file was touched.
- What the data does say about the original question: the commanded ready posture is NOT reached better by a stronger, faster arm (forehand forearm turn asked 1.20 rad reaches 0.28 / 0.32 / 0.35 / 0.34 at 0.28 s on rungs 0 / 1 / 2 / 3), so strength alone does not remove the
  face-follow limit; a re-tune would have to change the command mapping (contraction targets, co-contraction), and the pelvis's share of the pad-velocity spread is untouched by any muscle scaling.
- If the campaign wants the physical question answered anyway: a NEW pre-registered gate is needed, "re-tuned champion on the arm" (e.g. rung 1, the smallest: restore the hit rate from 23 % on training serves 820000+ with the round-10 screening recipe and then measure the three noise sigmas),
  and a grip retune first (the paddle is lost on 85-100 % of serves at rungs 1-3); hours, not minutes, and with the caveats above.
- Files created: playground/profiles/myo_beyond_arm.json (rule, ladder, criterion, measures, decision), playground/tasks/myo_tt_beyond.py (the task), scratchpad/tt2/{LOG.md, identity.py, smoke_env.py, probe_model.py, noise.py, posture_ready.py, pelvis_part.py, mech1.py, names.py, diag_stale.py,
  run_a.sh, run_diag.sh, run_stale.sh, diag_list.txt, diag_list2.txt, results/}; out/tt2/ (git-ignored scratch: per-episode logs). Edited: playground/tt_fast.py (opt-in TT_TASK env var; default unchanged, `tt_fast.py check` 3/3 identical after the edit).
- No process of mine is running. Wall: 22:53 start, 23:09 verdict, 23:45 end of diagnostics.
