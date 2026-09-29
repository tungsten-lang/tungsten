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
- 02:20 120 training seeds (90000-90119), 8 s, lift params, pass = standing to 8 s with >= 3 s on one leg (scratchpad/soccer4/cmp_scans.py):
  baseline 100/120 (83.3 %); b_g_set 2.0 (bgset) 80/120 (66.7 %, z -3.0: the 10-seed 8/10 was luck); **bramp b_t_ramp 0.2: 110/120
  (91.7 %, z +1.95, fixed 12 / broke 2)**. Seeds are partly persistent (not pure re-rolls). Retry+catch (bretry/bcout) rescued 0 of
  11 failing seeds (an outward roll runaway is lost by the time the swing foot is down: a second foot on the inner side does not
  stop an outward fall). cp_kh -6 vs -13.86 on 7 hold-failing + 6 passing training seeds (paired: pre-lift identical): 11/13, fixed 5
  of the 7 hold failures, broke none of the 6 controls.
- 02:22 failing shifts (90041, 90085, 89117): the COM drifts backward 0.1-0.6 m over ~2 s while both ankles sit at their dorsiflexion
  limit (+0.524) and the lateral shift stalls at 0.7/0.3 load; new opt-in switches dsx (double-support sagittal hip strategy) and dsi
  (lateral integral of the weight shift), controllers soccer6-f (dsx), soccer6-g (+dsi). Scans queued/running.
- 02:40 120 training seeds, 8 s (cmp_scans.py): baseline 100/120 (83.3 %); bramp b_t_ramp 0.2: 110 (91.7 %); **b_t_ramp 0.15: 113 (94.2 %, fixed 14, broke 1,
  z +2.66)**; b_t_ramp 0.2 + cp_kh -6: 108; dsx (k 3, lim 0.05): 100 (fixed 3 broke 3); dsx k 8 lim 0.04: 94 (worse). The set chunk's ramp
  from the reset posture (hip +0.15) to the stance (-0.26) wants to be FAST (0.45, 0.8 s were worse than 0.3). Queued b_t_ramp 0.1 and 0.05.
- 02:36 P2: p1trace/p1probe data: the phase-1 kick under joint noise x0.1 (+-0.002 rad): the plant lands 30 ms later, the snap fires
  at the same toe-ball distance (0.49-0.59 m) but the toe's LATERAL offset from the ball at the snap grows from 2 cm to 8-21 cm and
  the ball leaves at 2-7 m/s; k_ky (lateral aim servo) 1.24 -> 6 changes nothing. New V4 switches: sd (snap fired by toe-ball
  distance; likely inert: the distance is consistent), k6 (the routine's set/shift/lift/hold on the RIGHT leg -> the parent's reach,
  plant, kick; the hold is an attractor so the reach starts from a repeatable state). soccer6-i replays the balance routine and the
  phase-1 champion exactly (6/6 12.29 m/s at the exact start). k6 untuned: reach fails (falls 2.45 s at noise 0; hold reached in 6/6
  noise-1 seeds at 2.2-2.9 s).
- 02:54 start ramp sweep (120 training seeds, 8 s): b_t_ramp 0.3 83.3 % | 0.2 91.7 | 0.15 94.2 | 0.1 96.7 | 0.05 97.5 % (z +3.7, fixed 19 broke 2). Monotone:
  the faster the reset posture is replaced by the stance the better. NOTE the ramp change also shortens the set's minimum time by the
  same amount (the hold is b_t_set + ramp - 0.3): queued 0.05 + b_t_set 0.86 (total min set time kept at 0.61), 0.02 and 0.02 + b_t_set 0.89.
- 03:10 confound check (120 training seeds, 8 s): ramp 0.05 97.5 % | ramp 0.05 + b_t_set 0.86 (set min time kept) 95.0 % | ramp 0.02 97.5 % | ramp 0.02 + b_t_set 0.89
  93.3 %: the ramp is the main effect, a shorter total set adds ~2 %. Remaining failures with the fast ramp are all at ~2.5-3 s in
  b_down_l (lift falls caught by the put-down: 90012, 90042, 90100 at 0.05); the shift failures are gone.
  Arena: params/myo_soccer_single_leg_310_ramp.txt (lift params + bramp 1, b_t_ramp 0.05) + bin/challengers/soccer6-i evaluating on
  soccer_single_leg_310_40 since 02:55 (arena_310_40_ramp.out); the lift challenger's eval (02:13) is at 23/40 rollouts.
  Validation (fresh seeds 91000-91119, 20 s): scan/val20_ramp.out vs scan/val20_lift.out started 03:10.
- 03:07 P2 stage A (k6 + reach, noise 1, P1 position): the search (p2/A.txt, 4 min/generation) is at plant7 score 4.3 (of ~13); the reach never lands the
  left foot within its 1.2 s timeout: from the routine's centred right-leg hold the plant spot is 0.75 m ahead, and the parent's run-up
  gets there dynamically (COM leaning ahead at the lift: shift_x/d_go/x_step). A second search A2 (rk4 1: the routine's terms in the reach)
  runs in parallel (p2/A2.out).
- 03:42 VALIDATION (fresh seeds 91000-91119, 20 s, one-leg >= 15 s and standing): lift 105/120 (87.5 %), ramp 112/120 (93.3 %; fixed 13, broke 6, z +1.5).
  The training-set gain (83 -> 97.5 %) was inflated by selection; the honest gain is about +6 %. Ramp failures are now mostly
  lift falls caught by the put-down at ~3 s (6 of 8). Right leg first with the ramp: 111/120 (92.5 %, 8 s).
- 03:36 LATE FAILURE (lift challenger, seed 89106, arena rollout): a perfectly still one-leg hold (COP oscillation 1e-4 m for 200 s) ends
  suddenly at 222.3 s (swing foot touches down, then the kicker falls); no precursor in the stance-leg variables, the swing foot's
  yaw drifts +0.59..+0.62 rad. Contact log (contactlog.py) being checked for a swing-leg/stance-leg collision.
- 03:45 P2 stage A searches stopped (best plant7 4.3 after 13 generations: the reach never lands the left foot; the parent's reach needs
  the run-up's forward fall: COM 0.24 m ahead of the stance foot at the lift, 1 m/s forward and 0.86 m/s downward at the plant).
  Started balance search M (runM.sh): lift + hold parameters on the ramp base with the cp_wash washout structure (cp_khs starts equal
  to cp_kh so candidate 0 replays the ramp challenger), 7 s, 20 random training starts per generation, 43 tunables.
- 03:45 (mistake, recorded): my new balance search was first named "M" and OVERWROTE the previous session's scratchpad/soccer4/runM.sh and
  sM.out (the redirect truncated it; the old sM.txt, sM.txt.mean, sM.txt.log and M_init.txt are intact, mtime 9/28 07:33-07:36).
  This session's files carry a "9" prefix (run9M.sh, s9M.txt, ...).
- 03:55 FOUND (contact log): in EVERY hold the swing shank (tibia_r) presses on the stance thigh (femur_l) with ~200-230 N (legcontact.py, 12 seeds:
  190-230 N mean). The late failure of 89106 at 222.07 s is a MuJoCo instability ("WARNING: Nan, Inf or huge value in QACC at DOF 6")
  triggered by that stiff sustained contact, not a balance failure. Search M now adds a score penalty for mean inter-leg force above 40 N
  (--leg_w 0.004) so the swing posture can find a clearance; the official contact parameters are untouched.
- 04:03 ARENA soccer_single_leg_310_40: the lift challenger (bin/challengers/soccer5-lift + params/myo_soccer_single_leg_310_lift.txt) WINS:
  bal1_300 34/40 = 0.850 (ci 0.112, 6721 s) vs the champion 24/40 = 0.600: mean paired diff +0.25, p = 0.006 -> PROMOTED
  (bin/champions/soccer_single_leg_310_40-2026*, per-seed rows scratchpad/soccer4/evals/bal1_300-soccer5-lift-20260929-040311.json).
  Failures (6/40): 89106 (222 s, the MuJoCo blow-up), 89110, 89115, 89117, 89130, 89133 (the hold/lift/shift failures of the 20 s scan).
- 04:49 ARENA soccer_single_leg_310_40, the ramp challenger (bin/challengers/soccer6-i + params/myo_soccer_single_leg_310_ramp.txt): 38/40 hold 300 s
  (0.95, ci 0.068, 6820 s); vs the old champion (0.60) p < 0.001 (NOT promoted: the champion changed while it ran); re-run from the
  rollout cache against the promoted lift champion (0.85, 34/40): mean paired diff +0.10, p = 0.115 -> does not beat it.
  Against the lift champion it fixed 89106, 89110, 89115, 89117, 89130 (5), broke 89122 (falls at 16 s), 89133 fails in both
  (a 5-0 result would have been p = 0.031). Failures: 89122 (14.3 s one-leg, 16.1 s standing), 89133 (1.4 s).
- 04:50 pre-lift states of the persistently failing validation starts (liftfeat.py, ramp base, 120 starts): stance width at the lift
  16.4 cm against 20.4 cm (z -8.3), capture point 0.8 cm outboard of the stance foot against 1.2 cm inboard (z +12), stance load 0.665
  against 0.703. bwide (both hips abducted b_wide in the routine's stance) and sb_y -0.01 (lift target 1 cm more inboard) built/tried;
  sb_y -0.01 on 8 persistent failures + 8 controls: 12/16 (fixed 6, broke 2) vs 8/16; b_cp_tol 0.015: 7/16 (worse).
- 05:08 P2 standing kick (K4 search, k6_init-style params: the robust left stance with the P1 kick's swing, the plant leg kept on cp4 through the swing
  (k4_cp), feet 0.45 m behind the ball, noise 1, stage speed): 24 generations, best score 3.5 (ball ~1.7 m/s, no goal): the swing from the
  standing stance either misses or drops the body; stopped. A lean phase (k7) before the reach lands the foot on 1 of 6 seeds at best
  (A3: plant7 4.6 of ~13). No phase-2 goals.
- 05:15 sb_y -0.01 on all 120 validation starts (20 s): 82/120 (68 %) vs the ramp base 112/120: fixed 6, broke 36 (z -4.9): the 16-seed subset result (12/16) was regression
  to the mean; discarded. RIGHT LEG at 310 s: right-first (bc_first 1) with the ramp params on starts 89100-89107: 8/8 stand the whole
  310 s and hold the right leg for the metric's full 300 s (the scan printed BAD only because its criterion wanted 306 s and bal1_s is capped at 300).
- 05:20 swing-leg clearance: kinematically 0.1 rad more swing-hip abduction clears the stance thigh by 3.6 cm (clearance.py; -0.9 mm at the hold pose), but a swing-hip
  abductor drive (swabd, sw_drv_abd 0.15-0.5) leaves the contact force at 208-219 N, b_sw_add -0.1 gives 155 N, b_sw_knee 1.0 gives 140 N (holds 8/8 at 12 s),
  b_sw_knee <= 0.8 or b_sw_th >= 0.5 fall; the fyaw servo is not the cause (fyaw 0: 187 N). Search M (s9M.txt) continues with the force penalty (best 127 N at gen 2).
