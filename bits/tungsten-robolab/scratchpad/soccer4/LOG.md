# soccer4 campaign log (9/29 continuation)

All campaign state lives in the repo: scratchpad/soccer4/, params/, out/. Nothing in /private/tmp.

- 01:16 9/29 restart after the 9/28 18:10 reboot. Nothing of mine running. The machine is NOT idle now (load avg ~50-58 on 18
  cores: codex/other agents run dribble + sprint + metaflip jobs), so wall times run 2-3x slower than the 9/28 logs.
- 01:16 added trial soccer_single_leg_310_40 (arena lock, scratchpad/soccer4/add_trial_310_40.py): seeds 89100-89139, the
  soccer_single_leg_310 env/metric/report, "seconds" 310. Seeding it with the soccer_single_leg_310 champion
  (bin/champions/soccer_single_leg_310-20260928-025604 + its params; == soccer4-bal300 + params/myo_soccer_single_leg_310_cp4.txt):
  scratchpad/soccer4/arena_310_40_seed.out, pid in scratchpad/soccer4/pids/seed310_40.pid.
- 01:22 failscan.py (20 s per seed, per-seed phase log) on the 40 new seeds 89100-89139 with the lift challenger
  (bin/challengers/soccer5-lift + params/myo_soccer_single_leg_310_lift.txt): 35/40 hold >= 20 s (scan/lift_89100.out).
  The 5 that fail: 89110 (hold falls at 6.7 s), 89115 (6.9 s), 89117 (lift falls at 2.6 s), 89130 (set/shift falls at 1.5 s),
  89133 (hold falls at 3.2 s). The champion's 20-start rate was 12/20, so the 40-start trial should separate them.
- 01:27 diagnosis of the late-hold falls (89110, 89115; traces scratchpad/soccer4/tr/lift_*.json): the pelvis yaw sits at the
  stance hip's external stop (-0.7 rad to the foot) in EVERY seed after the lift (89000 too, that seed holds); in the failing
  holds the yaw goes into a 0.75 s limit cycle (-1.18 <-> -0.46) and then the frontal plane runs away: capture point +0.03..+0.04
  beyond the 2.1 cm sole limit, cp4's hip strategy abducts (cp_kh -13.9), pelvis roll climbs 0.1 -> 0.9 with the hip at -0.9
  (its abduction limit), cpo -> 1.3 m. The round-4 sign of the hip strategy (throw the trunk into the fall) helps the fast
  transient but is positive feedback for a slow outward drift (the trunk lean moves the COM the same way).
- 01:30 running ablations on the 5 failing + 5 passing seeds: scan/variants1.sh (cp_kh 0 / -6 / +6, sb_kha 4) then variants2.sh
  (tl_kp 0 / 10, tl_wfoot 1, tl_kp+tl_kd 0).
- 01:47 ablations (10 seeds: 5 failing + 5 passing of the lift challenger, 20 s): base 5/10; cp_kh -6 7/10; cp_kh 0 6/10; cp_kh +6 2/10
  (the round-4 hip-strategy sign is right for the transient, its size -13.9 is too big for slow drifts); tl_kp 0 or 10, tl_wfoot 1,
  tl_kp+tl_kd 0: 3-4/10 (the heading hold matters); sb_kha inert (cp4 zeroes the round-3 sb_kax/sb_kst/sb_kha/sb_ki);
  bramp (slower set ramp 0.8 / 1.2 s) 4/10, 3/10 (WORSE: the tuned 0.3 s lurch is part of the routine; falls at 0.4-1.5 s);
  bfore (fore-aft readiness) inert: 89117's fore-aft drift (COM 0.19 m behind the left foot) does not recover by waiting.
- 01:50 code (opt-in, bit-identical replay verified on 89117): lib/robolab/skills/myo_soccer_v4.w gained bramp/b_t_ramp, bgset/b_g_set,
  bfore/b_fx_tol, cp_more/cp_ksw/cp_klb (backup of the pre-edit files in scratchpad/soccer4/backup/). Controllers frozen as
  bin/challengers/soccer6-a (bramp, bfore, cp_more) and soccer6-b (+ bgset).
- 01:50 training scan of the lift challenger on fresh seeds 90000-90119 (12 s): scan/train_lift.out (the hard-seed pool for search5.py).
  Rule for the balance work from here on: choose variants on training seeds (90000+), never on the trial seeds 89000-89139.
- 01:58 KEY FINDINGS (10 diagnostic seeds, 20 s): bgset (b_g_set 1.5 / 2.0) 8/10, bramp 0.2 8/10, bramp 0.45 5/10, cp_more (ksw 3, klb 3) 5/10, cp_klb 4 + cp_kh -6 2/10.
  Each variant "fixes" a different 3 of the 5 failing seeds and breaks none of the 5 passing: consistent with the outcomes being
  chaotic re-rolls of one ~15 % per-attempt failure probability (any change of the first 0.3 s re-draws which seeds fail), NOT with
  hard seeds. So hard-seed mixing is pointless; need many seeds per variant or a dense stability proxy.
  Training scan (seeds 90000-90119, 12 s, lift challenger): 99/120 hold (82.5 %); fails by last phase: hold 12, shift 7, lift 2.
- 02:00 P2 probe (scratchpad/soccer4/p1probe.py; NOTE the env keeps its own copy of the reset state: patch _get_reset_state): the phase-1
  champion in the P2 env at the exact P1 posture and position scores 6/6 (12.3 m/s); joint noise x0.05 (+-0.001 rad) 4/8, x0.1 0/8,
  x0.5 (+-0.01 rad) 0/6; position offsets with no noise: dx -0.05 goal, dx -0.1 or dy +0.1 fall at 0.9 s (its approach turns on).
  The phase-1 kick is a knife-edge trajectory; phase 2 needs a closed-loop kick built on robust stances.
- 01:57 CHAMPION SEEDED on soccer_single_leg_310_40: 24/40 hold 300 s (0.60, ci 0.154; the same 60 % as on the 20-start trial); frozen
  bin/champions/soccer_single_leg_310_40-20260929-015724. The lift challenger's evaluation (arena_cached.py, --promote) started 02:13:
  scratchpad/soccer4/arena_310_40_lift.out (per-seed rows go to scratchpad/soccer4/evals/).
- 02:12 right leg first (bc_first 1, lift params, 40 training seeds, 12 s): 31/40 (77.5 %) vs left first 82.5 % (99/120): the routine
  holds the right leg about as well as the left, so the stork blocker of phase 2 was the parent's run-up shift/lift, not the leg.
- 02:14 features (scan/feat_90200.json, 120 seeds): fail predictors in the first 2 s: roll_max AUC 0.79 (0.84 for early falls), foot yaw
  drift 0.85 (early), yaw_max 0.73-0.80, min foot load in the set 0.80 (inverted). Base pass 105/120.
