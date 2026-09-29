# Sprint round 2 (agent S2): the extended-stance gear from flying starts (v4 P95)

Started 2026-09-29 (clock in this file = the machine's `date`). All state in the repo (scratchpad/sprint2/, params/, out/), never /private/tmp.
Rules: frozen champion params/run_gear_v4_p95_g.txt and bin/challengers/run_gear-v4c are NOT touched (long jump reads them). New params under new names.
Env for everything on P95: ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation (file scratchpad/sprint2/env.sh).
Go / no-go after ~2 h of wall clock.

## Log
- 16:08 read README (Sprinters on v4), sprint_knot/LOG.md, run_gear.w/run_knot.w/run_ri.w/run.w, hsearch.py, sprint_limits header. Champion replay on the 12 arena
  starts with `probe.py run_v4 params/run_gear_v4_p95_g.txt --controller bin/challengers/run_gear-v4c --seeds 221..232`: 7.924 7.92 7.9 7.93 7.812 7.916 7.931 7.914 7.887 7.921 7.905 7.929, 12/12 (exact).
- 16:13 tools written: scratchpad/sprint2/lab.py (flying-start lab: per-stance table, --stab = DIAGNOSTIC ideal external trunk torque, not an actuator), snap.py (snapshot sets),
  mkgear.py (params files for gear K), env.sh. Snapshots of the four-gear champion (standing starts, t 20-29 s, one per run, `snap.py ... --t0 20 --t1 29`):
  TRAIN playground/cache/sprint_touch_run_v4_p95j.npz (seeds 31-50, 19 snapshots 7.61-7.97 m/s; use ROBOLAB_SNAP=run_v4_p95j),
  VALID playground/cache/sprint_touch_run_v4_p95k.npz (seeds 141-184, 42 snapshots 7.85-7.97, unseen, pick 11).
- 16:16 CONTROL (gear 5 = gear 4 values, `mkgear.py --gears 5 --fly`, scratchpad/sprint2/g5_control_fly.txt; lab.py 24 s, seeds 0-18 of p95j): 3/19 fall at 1.7-2.6 s (entry transient of the flying start,
  seeds 2, 13, 15), 16 survive with peak 7.937 (7.920-7.956). Stance of the crouched champion at 7.9 (lab table, 16 survivors): contact 0.100, flight 0.139, step 1.91 m, thigh TD +0.56 / LO -0.41, knee TD 0.655 /
  max 0.71, mean/peak vGRF 2.37/4.1 BW, torso pitch 0.15 at TD, rock over the stance +0.015 rad (no trunk problem at all in the crouched gait).
- 16:17 the whole extended-mode gait (p1_snap1 as gear 5, g5_ext_all_fly.txt) falls in 1.2-1.4 s from every 7.9 m/s snapshot (8/8). With the DIAGNOSTIC ideal trunk torque (kp 2000, kd 100, limit 100/300/1000 N m,
  held at the snapshot's pitch) it still falls (2.9-5.4 s): the trunk is not its only problem at 7.9 m/s.
- 16:18 DIAGNOSTIC control + ideal trunk torque (limit 300 N m, seeds 0,1,3,4, 12 s): holding the trunk at 0.20 rad -> peak 8.00-8.06 (+0.1); at 0.30 rad -> 8.05-8.2 (3/4 survive; entry transient);
  at 0.10 or >= 0.40 rad it breaks. So an ideal trunk stabiliser is worth about +0.1..+0.25 m/s to the crouched stride before any re-tuning.
- 16:38 KEY LAB FINDINGS (no search yet): (1) one-at-a-time moves of the champion's gear (scan.py, 4 flying seeds): the stride is a knife edge (k_reach, psi_reach, a_reach, d_push, cv, psi_v: 4/4 fall);
  moves that survive leave th_lo at -0.38..-0.42 and kn_td 0.62-0.74: the lift-off thigh is kinematic (tc 0.1 s x v = 0.79 m of contact length), not a commanded value.
  (2) MORPH of the leg-geometry tunables from the champion's gear 4 to p1_snap1 (morph.py, alpha 0..1, no re-tuning): peak 7.93 / 7.83 / 7.75 / 7.69 / 7.65 / 7.50 / 7.49 for alpha 0 / .1 / .2 / .3 / .5 / .75 / 1;
  kn_td 0.654 -> 0.558, kn_max 0.70 -> 0.84, tc 0.100 -> 0.122, flight 0.139 -> 0.161, peak vGRF stays 4.0-4.2 BW, mean 2.28-2.41 BW, trunk rock 0.016 -> 0.21 rad. With the DIAGNOSTIC ideal trunk torque (300 N m, kp 2000,
  kd 100, LPF reference) the rock is 0.014-0.02 and the speeds are 8.04 / 7.93 / 7.82 / 7.83 / 7.73 / 7.61 / 7.25 with more falls: the trunk is worth ~+0.1 m/s to the crouched stride and does NOT rescue the extended one.
  (3) alpha 0.75 + ideal trunk torque, per-stance table: intermittent EXTENDED strides (tc 0.104, flight 0.152-0.169, step 2.05 m, th_td +0.44, th_lo -0.44..-0.50, kn_td 0.51, kn_max 0.65-0.71, peak vGRF only 3.5-3.7 BW)
  appear and each is followed by a bad stride (knee collapse kn_max 1.2-1.8, tc 0.14-0.20): the extended stride is not a stable period-1 orbit of this controller; the steady state it settles in is tc 0.12, flight 0.15, th_lo -0.22, 6.9 m/s.
- 16:38 new files: playground/tasks/sprint_touch_v4x.py (objective 6 = pace + ideal-stance shaping; env ROBOLAB_TRUNK_STAB kp,kd,limit[,mode] = DIAGNOSTIC ideal external trunk torque), scratchpad/sprint2/es.sh (ES launcher on the g5 twins),
  g5_morph030_fly.txt / g5_morph050_fly.txt (morph starts).
- 16:38 LAUNCHED e1: ES (hsearch, 4 workers) on the g5 twins from g5_morph050_fly.txt, task sprint_touch_v4x objective 6 (shaping st_ktd 0.55 st_td 0.5 st_lo -0.55 st_kmax 0.75, weights 40), 24 s flying rollouts,
  19 p95j seeds (hard first: 15,13,2,0,1,3,4,5,6,7,8,9,10,11,12,14,16,17,18), budget 2400 rollouts, sigma 0.02, ROBOLAB_SNAP=run_v4_p95j, controller bin/challengers/run_gear-v4c. Out: scratchpad/sprint2/e1.{txt,log,jsonl,npz,pid}.
- 16:42 load average went to 52 (5-min 33): stopped e1 (gen 3, best -349.5) and resumed as e1b with 2 workers from e1.txt (same seeds/attrs/budget 2400, sigma 0.02). Monitor task btbyvsv84 was on e1.log (stale).
