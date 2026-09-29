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
- 06:15 LEG SELECTOR (bsel) DROPPED: with the ramp params, validation 91000-91119 (20 s): left-first 112/120, right-first 112/120, both 106, left-only 6, right-only 6,
  neither 2 (oracle 118/120). At the shift start (the state at which next_leg decides) the rule "stand on the right leg when the left foot carries more load"
  (ld_l - ld_r > 0) picks the better leg on 10 of the 12 leg-specific starts (predicted 116/120), but on the TRAINING starts 90000-90119 (8 s scans, same params)
  it picks the better leg on only 6 of 10 (left-first 117/120, right-first 111/120, rule 115/120, i.e. worse than always-left). The validation fit was a
  chance fit among ~8 candidate features (bias, width, loads, foot yaws, cpo); no controller change made.
  All 25 failures in both scans (validation 14 + training 11) are in b_hold (2.6-4.1 s, i.e. 1-2 s after the lift, plus a few 5-9 s) or the shift of the other
  leg: a linear-instability-like outward roll that grows for ~1.3 s after the lift; nothing before the lift fails.
- 06:20 search M gen 7 (best score 14.703 against x0 14.216, both 0/24 failures on its training starts: the gain is mostly the leg-force penalty,
  172 N -> 94 N); the fails-per-24 signal is too rare to steer a 7 % failure rate. Snapshot scratchpad/soccer4/s9M_gen7.txt scanned on validation
  seeds 91000-91119 (20 s) against the ramp base 112/120: scan/val20_M7.out.
- 06:24 restored the previous session's scratchpad/soccer4/runM.sh from git (my 03:45 mistake had left it deleted from the working tree after I moved my own script to run9M.sh);
  sM.out (git-ignored *.out) stays lost, the old sM.txt / sM.txt.log are intact.
- 06:25 THE CAPTURE POINT AT THE LIFT PREDICTS THE HOLD (liftfeat data, ramp base, left leg, 240 starts = validation 91000-91119 + training 90000-90119): at the first b_lift
  tick the lateral capture point relative to the stance foot centre (cpo, outward +) is -1.2 cm +- 0.8 in the good holds and +0.8 cm in the 8 failing validation starts
  (z +7.5; training 3 failures +1.0 cm, z +5.4). By threshold: cpo <= 0 -> 0 failures in 212 lifts; cpo > 0 -> 11 of 28 fail; cpo > +0.5 cm -> 10 of 14; cpo > +1 cm -> 2 of 2.
  The lift latch only bounds |cp - target| < b_cp_tol (3.2 cm), symmetric. New opt-in V4 switch bcpo (b_cpo_max, default 0.0): the lift also waits (at most bc_tmax more
  seconds) for cp_lateral(f, st) < b_cpo_max. Default off: bit-identical. Frozen bin/challengers/soccer6-o (built 06:21). SDK spec 90 passed, 0 failed (06:20).
  Search M paused (SIGSTOP pid 11009 + children) and the M7 validation scan killed to free the CPU; test: the 28 affected starts + 8 unaffected controls, 20 s,
  scan/cpo_A_off (identity: bcpo off must equal the old base) and scan/cpo_B_0 (bcpo on).
- 06:27 bcpo RESULT (28 affected + 8 unaffected starts, 20 s, scan/cpo_A_off.json vs cpo_B_0.json, script cmpcpo.py): identity OK (bcpo off = the old base on all 36 seeds, bit for bit);
  bcpo on (b_cpo_max 0.0): fixed 0, BROKE 13, both ok 12 (the 8 unaffected + 4), both bad 11. Waiting for the capture point to come back inboard is FATAL: the 13 lifts that
  had survived now fall IN THE SHIFT at 2.2-3.1 s (swing foot lightly on the ground, cp outboard); the lift itself is what recovers them. The failing holds are shifts that OVER-shifted the COM:
  cpo at the lift is predicted by the state at the shift start (R2 0.63: stance width r -0.75, cpo0 +0.75, como0 +0.76; 46 starts flagged cover 10 of the 11 failures);
  all 28 outboard lifts have a stance narrower than 19 cm (the feed-forward b_shift_add = 0.187 rad pushes the COM the same way whatever the width).
  Next: bshc (V4, frozen bin/challengers/soccer6-p): a capture-point brake inside the shift (the stance hip's adduction down, the swing hip's up, bsh_k rad per m of cp excess beyond bsh_ref).
- 06:36 bshc (capture-point brake in the shift; 36 starts = 28 outboard lifts + 8 unaffected, 20 s; every unaffected start bit-identical): C1 (bsh_ref -0.005, k 2, lim 0.08) fixed 2, broke 0;
  C2 (ref -0.01, k 4, lim 0.10) fixed 7 of the 11 failing, broke 0 (both ok 25, both bad 4: 90012, 90042, 91067, 91076). Next: C3 (ref -0.01, k 8, lim 0.15), C4 (ref -0.02, k 8, lim 0.15),
  then 120 fresh starts (92000-92119, base vs best).
- 06:40 bshc dose-response on the 36 starts (28 outboard lifts, 11 of them failing in the base, + 8 unaffected): C1 (ref -0.005, k 2) fixed 2 broke 0; C2 (ref -0.01, k 4, lim 0.10) 7/0;
  C3 (ref -0.01, k 8, lim 0.15) 9/1 (90088 broke); C4 (ref -0.02, k 8, lim 0.15) fixed 11 of 11, broke 0, all 36 starts stand 20 s. The monotone dose-response says the effect is real, but the
  config was chosen on these 36. Fresh test: seeds 92000-92119, 20 s, base vs C4 (scan/fresh20_base.json, scan/fresh20_C4.json).
- 06:41 search M stopped (kill -9 of pid 11009 and its workers; it had been SIGSTOPped since 06:19): last complete generation 7 (best score 14.703 vs x0 14.216, leg force 94 N against ~200 N); snapshot s9M_gen7.txt,
  state s9M.txt.state.npz (resumable with run9M.sh). Its params were not validated (the CPU went to the bcpo/bshc tests).
- 06:56 FRESH TEST of bshc C4 (seeds 92000-92119, 20 s, controller soccer6-p, ramp params): base 117/120 (a lucky set: 97.5 %), C4 119/120: fixed 3 (92044, 92053, 92100: all three base failures,
  holds falling at 2.5-3.7 s), broke 1 (92027, 2.7 s); one-sided sign test p = 0.31 (only 4 changed starts). Params file params/myo_soccer_single_leg_310_shc.txt (ramp + bshc 1, bsh_ref -0.02, bsh_k 8, bsh_lim 0.15).
  ARENA soccer_single_leg_310_40 challenger #3 started 06:56 (bin/challengers/soccer6-p; rollouts cached; output scratchpad/soccer4/arena_310_40_shc.out; --promote if p < 0.05 vs the lift champion).
- 07:00 identity: soccer6-p with bshc off replays the old ramp base bit for bit (8 validation starts incl. failing ones). Full validation scan of C4 (91000-91119, 20 s) vs val20_ramp (112/120) running (scan/val20_C4.json).
- 07:13 VALIDATION of bshc C4 (91000-91119, 20 s, same controller with the brake off = 112/120): 119/120: fixed 8 (91012, 91044, 91061, 91067, 91076, 91077, 91087, 91095: all falls at 2.9-3.8 s in the hold, one at 9.0 s),
  broke 1 (91049: falls at 16.9 s in b_hold_l); one-sided sign test p = 0.0195. Fresh (92000-92119): 3 fixed / 1 broke (p 0.31). Pooled (validation + fresh, the brake's setting was picked on the affected
  36 starts of the validation and training sets): fixed 11, broke 2. No start fails before 16 s in either set any more except 92027 (2.7 s); the remaining failure class is the SLOW one
  (a hold that ends 14-17 s in: 91049 here, 89122 in the trial's ramp entry).
- 07:22 THE LATE FAILURES ARE THE SIMULATOR (all three): 91049 under bshc C4 stands motionless from 4.6 s (roll -0.056, cp 0.000 cm, loads 1.00 / 0.00, no velocity) and MuJoCo reports
  "Nan, Inf or huge value in QACC at DOF 6. The simulation is unstable. Time = 16.5170" (its fall at 16.86 s follows); the trial's ramp entry 89122 (15.811 s) and the lift entry 89106 (222.068 s)
  carry the same warning in their arena logs. contactlog.py on 91049: tibia_r - femur_l in contact at dist -1.1 mm with 219-221 N as a steady period-5-step pattern (no growth) up to 16.51 s, then the blow-up
  without a precursor. Nothing is left to balance: after bshc the failing class is this contact. Clearance search C started (run9C.sh -> s9C.txt): sep-CMA on 12 swing-leg / stance-posture parameters, score = hold - 0.02 per N of mean inter-leg force.
- 07:31 ARENA soccer_single_leg_310_40, shc entry, partial (12 of 40 rollouts done, scratchpad/soccer4/evalstatus.py): 11 hold 300 s; 89103 FELL AT 255.75 S: MUJOCO_LOG.TXT has
  "Nan, Inf or huge value in CTRL at ACTUATOR 239 (recfem_r) ... Time = 255.5500" and "QACC at DOF 6 ... Time = 255.5500": the same blow-up (4th case: 89106 @222 s, 89122 @15.8 s, 91049 @16.5 s, 89103 @255.6 s).
  89103 passes for the promoted lift champion, so this entry can be at best 6 fixed / 1 broke = p ~ 0.06 against it: NOT promotable however the other 28 go. The blow-up (about 1 start in 40 per entry)
  is now the wall between 38-39 / 40 and a promotion. Search C restarted at nice 0 (a nice-10 search starves at load 120): run9C.sh -> s9C2.txt (5 s rollouts, 4 starts, pop 8, leg_w 0.03).
  DOF 6 = the root's first free-joint DOF; timestep 0.001, Newton solver, 100 iterations, pyramidal cone; actuator 239 = recfem_r (its control goes NaN after the state does).
- 07:38 ARENA shc entry STOPPED at 17/40 (rollouts cached; resumable with the same command): 15 hold 300 s; 89103 falls at 255.75 s (blow-up 255.55 s) and 89122 at 16.15 s
  (bal1 14.33: bit-identical to the ramp entry, the blow-up at 15.811 s again; the brake never acted on that start). Two breaks against the lift champion (both hold 300 s there) make the best
  case 6 fixed / 2 broke = p 0.145: the entry cannot be promoted, so its remaining ~50 min of CPU go to the blow-up fix instead.
  Clearance search C2 (s9C2.txt, 5 s, 4 starts): gen 8 leg force 3.5 N (1 of 4 fell), typical best 30-50 N with contact in 100 % of the steps (legforce.py, 6 starts: 51-60 N).
- 07:47 clearance searches C2 (18 gens, best 11.30, force 25 N on its 4 training starts) and C3 (5 gens, best 10.70, force 10 N on 6) stopped; legforce.py on 8 unseen starts: the C3 snapshot falls on 4 of 8 (all 4 with no inter-leg
  contact fell within 4.5 s, the 4 with contact 44-73 N stand 12 s: winner's curse on 6 training starts, and possibly the leg contact is holding the hold up), the C2 snapshot (52-60 N, contact in 100 % of steps) 1 of 6.
  Validation scans (91000-91119, 20 s) of the C2 best (s9C2_best.txt) and the search-M gen-7 best with the brake (s9M_gen7_shc.txt) against the brake base's 119/120: scan/val20_C2best.json, scan/val20_Mshc.json.
- 08:00 VALIDATION of the low-force candidates (91000-91119, 20 s) against the brake base (119/120): C2 best (force 25 N on training starts) 111/120 (fixed 91049, broke 9, all in the hold at 4-10 s);
  M gen-7 + brake 116/120 (fixed 91049, broke 4). Less inter-leg contact = a less stable hold: the leg contact is holding the hold up (or the searches trade robustness for force on 4-24 starts); both fix the
  91049 blow-up start, so the contact is the blow-up's cause, but a clearance that keeps the hold needs a search with many starts per candidate (>= 16) and a re-evaluated elite. Not entered.
  ARENA shc entry RESUMED 08:00 (arena_310_40_shc_b.out; 17 rollouts come from the cache): it will complete the 40 starts for the record (the best case against the lift champion is p ~ 0.145, so no promotion).
- 08:05 the blow-up is chaotic: start 91049 with the brake params, hold parameters shifted by 0.002 rad (b_sw_add +-0.002, b_sw_th +0.002, b_sw_knee +0.002): 4 of 4 hold 30 s with no blow-up at 16.5 s.
  Re-entering near-identical variants of the same controller until one draws no blow-up would p-hack the arena (its p assumes one challenger), so no lottery entries; the fix is the contact, and
  the contact is load-bearing (the low-force candidates lose 4-9 of 120 validation starts).
- 08:12 ARENA shc entry, 25 of 40 done at 08:03: 22 hold 300 s; the failures 89103 (255.55 s), 89122 (15.8 s) and 89130 (141.04 s) are ALL MuJoCo blow-ups (MUJOCO_LOG.TXT: QACC at DOF 6 / CTRL at actuator 239 at exactly those times).
  Blow-up anatomy (blowwarn.py, a mujoco user-warning callback that dumps the state inside the failing mj_step; start 91049, brake params, 16.517 s): the leg contact r_tibia1_col [tibia_r] - l_femur2_col [femur_l]
  221 N at 1.07 mm penetration, the stance foot 125 + 119 N, 13 contacts (15 in the steps before); |qacc|max alternates 5-9 / 83-90 from control step to control step, all of it in ankle_angle_r (the SWING ankle).
  chatter.py (qacc RMS over 5-9 s of the hold): swing ankle_angle_r 61.6 rad/s^2 and subtalar_r 13.7 at k_leg 30; the rest of the body <= 2.5. Against the leg reflex gain: k_leg 45 60, 30 62, 28 38, 26 14, 24 11, 22 6.8, 20 none
  (top joint dof2 2.4); kd_leg 0.2: 83 (lag-1 autocorrelation -0.73: a period-2 limit cycle of the 100 Hz reflex loop); kd_leg 0.05 and 0 fall at 3 s and 1.8 s. legforce.py at k_leg 20: contact force 132-145 N (215 N at 30) but 2 of 8 starts fall.
  So every hold carries a swing-ankle limit cycle (the reflex loop at the control rate) on top of a 215 N leg contact (40 of 40 validation starts: mean force 215 N, contact 100 % of the steps); the blow-ups need one or both.
  A causal test needs a blow-up RATE (about 1 start in 40 at 310 s) on each arm: not reachable in this session.
- 08:26 RIGHT LEG FIRST with the brake (validation 91000-91119, 20 s): base 112/120 -> 119/120 (fixed 8, broke 1; p 0.02): bshc works on either leg.
- 08:26 BUT THE BRAKE RAISES THE BLOW-UP HAZARD AT 310 S. Arena shc entry, 31 of 40 done: 26 hold 300 s; the five failures 89103 (255.6 s), 89122 (15.8 s, bit-identical to the ramp entry), 89130 (141.0 s),
  89134 (134.2 s), 89135 (130.2 s) are all MuJoCo blow-ups (QACC at DOF 6, MUJOCO_LOG.TXT). The ramp entry (same params without the brake) held 89103, 89130, 89134, 89135 for 300 s; the ramp params on the
  new binary soccer6-p and on the old soccer6-i are bit-identical for 89130/89134/89135 at 145 s (bal1 143.12 / 143.49 / 143.03 both), so the binary is not the cause: with bshc on, 4 of 4 starts that the ramp held
  now blow up at 130-255 s (5 of 31 against 1 of 40 in each of the ramp and lift entries: Poisson p ~ 0.001). The contact force does not tell them apart (215-220 N, dmin -1.1 mm, 10 starts), nor does the swing-ankle
  chatter (ramp and brake rms 45-62 on 6 starts, identical where the brake never acted). Cause not found; traces of 89134 (brake vs ramp, every 5 s to 136 s) started 08:22.
- 08:33 the two long traces of 89134 (5 s samples to 136 s; shc blows up at 134.2 s, the ramp run holds): both are the same motionless posture (roll -0.056, pelvis yaw 0.350, foot yaw -0.087 / -0.089, cp 0.000, loads 1.00 / 0.00,
  pelvis height 0.94, no drift in 130 s): a rare numerical event in a static hold, not a state that the brake changed. A common hazard of ~6 % per 310 s run (7 blow-ups in 111 arena runs) fits the entries
  (lift 1/40, ramp 1/40, brake 5/31 has Poisson p ~ 0.07 against it), so "the brake raises the hazard" is NOT established; the ramp's and lift's clean sweeps may be lucky draws.
  Accelerated test (12 starts x 60 s with the swing-ankle chatter at its worst, kd_leg 0.2, rms 83): 0 blow-ups (one early fall at 2.4 s). No dose-response seen; the chatter is not shown to matter. Stopped the other two arms.
- 08:38 ARENA soccer_single_leg_310_40, shift-brake entry FINAL (2326 s of the resumed run; per-seed rows scratchpad/soccer4/evals/bal1_300-soccer6-p-20260929-083736.json): bal1_300 = 0.875 +- 0.104, 35 / 40 hold 300 s
  against the champion's 34 / 40 (lift): fixed 5 (89106, 89110, 89115, 89117, 89133), broke 4 (89103, 89122, 89134, 89135), both fail 89130; mean paired diff +0.025, p = 0.514: NOT promoted.
  The 5 failures (89103 255.8 s, 89122 16.1 s, 89130 141.2 s, 89134 134.6 s, 89135 130.6 s) are all MuJoCo blow-ups; the entry's early falls are gone (no fall before 16 s except the identical 89122 blow-up).
  Board: soccer_single_leg_310_40 champion = the round-5 lift (34 / 40); history.jsonl has the three challenges. recheck soccer_single_leg 3.0793 OK, soccer_p1 1.0000 OK (08:36); SDK spec 90 passed 0 failed (06:20).
- 08:45 HANDBACK STATE. Arena soccer_single_leg_310_40: champion = round-5 lift 34 / 40 (promoted 04:03, p 0.006, over the round-4 24 / 40); ramp challenger 38 / 40 (p 0.115, not promoted); brake challenger 35 / 40
  (p 0.514, not promoted). No process of mine is running (search M, clearance searches C2/C3, the scans and the arena resume are finished or stopped; orphaned workers of the SIGSTOPped search M killed 08:39).
  Open: (1) the blow-up (7 of 120 arena runs; motionless holds; leg contact 215 N and a swing-ankle limit cycle are the only anomalies found, neither shown causal); (2) a trial that can certify a gain
  (the lift champion's 6 falls are the whole room; one blow-up among the 34 kept starts loses it); (3) phase 2: no goals, no soccer_p2 entry; coverage not started.
