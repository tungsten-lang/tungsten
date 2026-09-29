# long jump round 3 (agent L2, from 2026-09-29 06:15): the two-gear runner under the jump

Goal (Erik): use the best runner for the long jump and then exceed human ability. Legality first (World Athletics TR 29-30).
Label: open-loop tables / near-open-loop knots are ORACLE-class; one-start numbers are overfit; only the robust trials count.
All state in the repo: this log, params/, out/long_jump_limits/, out/long_jump_run/, scratchpad/lj2/. No git commits.

## 2026-09-29 06:15 start of the session

- machine load average 75-90 on 18 cores (other agents: sprint S, soccer O, tt T, bat, dribble, Codex). At most 2 rollout workers of mine at once.
- one full rollout of the v4 one-start champion (44 m run-up + jump) takes 3 s wall even at this load: 16 starts ~ 30 s at 2 workers, 96 starts ~ 2.5 min.
- replay check with a frozen controller, before any edit (long_jump_eval.py, seed None, task long_jump_v4_p95b, params long_jump_v4_p95_ik5, controller long_jump_run-b20x): official 4.945 m (matches the arena).
- runner to use: sprint_top_speed_v4_p95 champion RunGearSkill, params/run_gear_v4_p95_c.txt (g2p_snap1 as a standing-start two-gear controller, switch 6.5 m/s; arena 7.449 +- 0.013 m/s, 12/12; 2/40 falls on unseen seeds),
  source run_gear.w (RunGearSkill < RunKnotSkill < RunRISkill; Track#set_movement in controller.w, all uncommitted edits of the sprint agent S: read only).
  Frozen copy for the jump: params/lj_runner_gear_v4_p95.txt (cp of params/run_gear_v4_p95_c.txt, 2026-09-29 06:20).
- bin/robolab_long_jump_run was rebuilt at 06:04 by someone else (5400296 bytes; b20x is 5400264): always evaluate frozen copies, never that path.

## 2026-09-29 06:22 wiring: LongJumpRunSkill < RunGearSkill (build c1)

- lib/robolab/skills/long_jump_run.w: `+ LongJumpRunSkill < RunGearSkill` (was RunRISkill); the jump's chunks moved into `add_jump_chunks(mv)`, called from `start` and from a new
  `switch_gear(f, ctl, k)` override (RunGearSkill#switch_gear builds a fresh stride Movement and swaps it under the track: the take-off/ik/il/flight chunks must be added to the new one).
  Opt-in: the params-file switch `gears 2` (+ g2_ twins) of RunGearSkill; without it RunGear = RunKnot = RunRI exactly. lib/entry/long_jump_run.w: + use robolab/tcn, run_knot, run_gear.
- build c1 = ./build.sh long_jump_run at 06:20 (2 min), frozen bin/challengers/long_jump_run-c1. Source md5 at the build: run_gear.w 0d11e656, run_knot.w b40bf033, run_ri.w 8b544539, run.w 301be092, controller.w ac3ba216, long_jump_run.w 11ea4dd3.
  (run_gear/run_knot/run_ri/controller are the sprint agent's uncommitted files; a later change of theirs changes what a rebuild means, the frozen copies do not change.)
- exactness of c1 vs the stored champion scores (scratchpad/lj2/replays_c1.sh; per-seed scores identical, 0 DIFF): long_jump_v4_p95 4.945 (ik5), long_jump_p95 5.122 (ik11),
  long_jump_p95_robust 4.6305 on 16 (pn1), long_jump_v4_p95_robust 2.1452 on 16 (ik2). Old params replay exactly with the RunGear base class.

## 2026-09-29 06:50 what the two-gear runner does at the board, and why the old v4 planner fouled

Runner at the jump's scale (j_run 1 = approach only, 44 m check mark, 8 starts None + 401-407; scratchpad/lj2/runup.py, speedprofile.py):
- params/lj_runner_gear_v4_p95.txt as it is (gear switch at 6.5 m/s): the switch comes at ~40 m, so the jump sees the OLD runner: 6.70 m/s at 44 m (5 m window), v5 (last 5 m) 6.60. The 7.45 m/s of the sprint trial needs 20 s and 100 m; at 44 m the two-gear runner is the same as RunRI.
- g2_v_on scan (v5 mean of 8 starts, falls): 6.5 -> 6.60 (0), 6.0 -> 6.73 (0), 5.5 -> 6.78 (0), 5.0 -> 6.82 (0), 4.5 -> 6.85 (0), 4.0 -> 6.84 (3 falls), 3.5 -> 6.84 (1 fall). Chosen: g2_v_on 5.0 (+0.22 m/s at the board, no falls on 8; hazard to be checked on more starts). With 5.0: 6.79 at 40 m, 6.92 at 44 m, 6.95 at 45 m, 7.05 at 50 m, 7.15 at 55 m, 7.25 at 65 m (speed over a 5 m window centred there).
- the jump's own run-up modifications (upright final approach j_fin_*: torso target shift over the last 12 m, servo x3.7) cost ~0.2 m/s: full jump rollouts show speed_5m 6.55-6.78.
- old v4 params (ik2, planner of the p2a run) on the gear runner (g_ik2_v50, 32 fresh starts 9001-9032): 13/32 legal, mean 1.58 m; plant foot offset sd 0.31 (range -1.03..+0.5).
- FOOT PLACEMENT (scratchpad/lj2/ikgap.py, phase*.py): the plant foot's offset from the line = -1.01 x (penultimate toe's gap error) - 0.02, residual sd 0.036: the take-off program (gap knots zeroed in ik1) does not compensate, so the penultimate placement IS the placement.
  The stride pattern's phase at the board varies over a full step (1.6 m) across starts: the k-th touchdown's position has sd 0.4-0.7 m from the 2nd step on (the start: first foot l 28 / r 21 of 49, first push time sd 0.3 s), 1.0 m at the 20th.
  The v4 practice (ik2) had j_st_w 0.09 (no steering): the window rule then turns the phase spread into the offset spread. With steering j_st_w 0.6, j_st_max 0.3, j_st_n 6 on the gear runner the penultimate gap error sd falls 0.306 -> 0.106 m and the plant offset sd to 0.146 (the chunk take-off: offsets -0.23..+0.10 on 32 starts). j_st_w 1.5 does not help more (offset sd 0.38, 2 starts break).
- A1 (scratchpad/lj2/A1.txt) = runner (lj_runner_gear_v4_p95, g2_v_on 5.0) + ik2's j_* + j_st_w 0.6 j_st_max 0.3 j_st_n 6, j_ik 0: chunk jump on 32 fresh starts: 18 legal, mean 1.76 (chunk take-off vz 1-2 m/s; fouls of 0.01-0.04 m, 8 somersaults); the foot is placed.

## 2026-09-29 06:55 ideal-control ceiling, nominal start of A1 (running)

capture gp_nom (long_jump_limits.py capture long_jump_v4_p95b --params scratchpad/lj2/A1.txt --controller bin/challengers/long_jump_run-c1 --name gp_nom --from pen; env ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=p95 ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation):
 chunk take-off official 3.296 (vx 5.535 vz 1.764); harness replay reproduces it (vx 5.532 vz 1.772).
optimise gp_nom --evals 120000 --workers 2 --lmax=-1.5 --tag ideal --init out/long_jump_limits/p95pn_s0_ideal.json (v3 p95 pn optimum as the start), pid in scratchpad/lj2/gp_nom_ideal.pid, log out/long_jump_limits/gp_nom_ideal.log, ~92 evals/s.

## 2026-09-29 07:10 IDEAL-CONTROL CEILING, gear runner (A1 approach, nominal start), from the penultimate touchdown

`long_jump_limits.py optimise gp_nom --evals 120000 --workers 2 --lmax=-1.5 --tag ideal --init out/long_jump_limits/p95pn_s0_ideal.json` (pid 9xxxx, 1147 s, ~105 evals/s; still improving at the end: 4.89 at 32k, 5.007 at 51k, 5.13 at 72k, 5.219 at 120k):
 D 5.219 m ballistic from the take-off foot (COM x - foot front at take-off + vx t_air); take-off vx 6.316, vz 3.101 (26.1 deg), contact 0.088 s, L -4.6 kg m2/s, torso pitch 0.115 rad, plant touchdown 0.272 s after the pen touchdown, foot 0.172 m behind the line -> 5.05 m from the line.
 pen-touchdown state: COM speed 6.59 m/s, torso -0.10 rad. Old v4 ceiling (p2a runner, 6.37 m/s at the pen state): 4.89 m; v3 p95 (6.8-6.9 m/s): 4.90-4.93 m. ORACLE-class number (open-loop 32-muscle excitations, one start).
distilled: out/long_jump_limits/ik_gp.txt (ik_from 1). Captures for the robust stage: gp_s8001-8064 (A1 approach, seeds 8001-8064, out/long_jump_limits/gp_s*_capture.npz).

## 2026-09-29 07:30 the three-gear runner (coordinator's note 10:47Z): no change at a 44 m check mark

- Frozen copy of the sprint agent's three-gear P95 champion: params/lj_runner_gear3_v4_p95.txt = params/run_gear_v4_p95_e.txt (29 Sep 06:45, md5 cb5739d6, gears 3, g2_v_on 6.5, g3_v_on 7.0, controller lineage bin/challengers/run_gear-v4c).
  Its gears 1 and 2 are IDENTICAL to params/run_gear_v4_p95_c.txt (diff of every non-g3 key: only `gears 3.0` differs); gear 3 needs the filtered speed to reach 7.0 m/s.
- The jump's run-up reaches 6.6-6.9 m/s at 44 m (the 7.45 / 7.86 m/s of the sprint trial are the 20 s / 100 m speeds), so gear 3 never engages: approach-only rollouts (A1 = the jump's approach settings, g2_v_on 5.0, c2 controller, 17 starts None + 401-416)
  give IDENTICAL per-seed v5 and arrival times with the two-gear and the three-gear params (scratchpad/lj2/cmp3_A1.txt vs cmp3_A1_g3.txt; v5 mean 6.604, sd 0.036, min 6.532, max 6.677, 0 falls).
  So the captures and the 5.219 m ceiling above stand for the three-gear runner too; no recapture needed. The jump keeps the TWO-gear file (`gears 2`): with a lower g2_v_on the filtered speed can touch 7.0 m/s in the last strides
  (instantaneous 7.0 at x = 44) and a gear-3 change there would land in the middle of the take-off planning.
- The capture step is parameterised on the runner file: scratchpad/lj2/mkparams.py <runner.txt> <jump/planner.txt> <out.txt> [k=v ...] builds the approach params (A1 = params/lj_runner_gear_v4_p95.txt + ik2's j_* + g2_v_on 5.0 + steering);
  a new runner (a 4th gear, or an acceleration gear) = rebuild A1 with the new file, then capture (long_jump_limits.py capture ... --seeds 8001-8064 --from pen) and rerun the ideal / robust / landing scripts (scratchpad/lj2/run_pipeline.sh, once written).
- What WOULD move the board speed: gears below 6.5 m/s (the switch point and an acceleration gear), not gears above 7.0. Lowering g2_v_on 6.5 -> 5.0 already gives +0.22 m/s at 44 m (table above).

## 2026-09-29 07:55 steering, hop-height steering, upright final approach (run-up design for the jump; 16-96 starts each)

- Hip-nudge steering scan on 96 training seeds 8001-8096 (scratchpad/lj2/scan_steer.sh, ikgap.py: A1ik = A1 + the nominal ideal's take-off program; "failed" = no penultimate/plant reached, i.e. a fall or no take-off):
  (w 0.6, max 0.3, n 6): 3 failed, penultimate gap error sd 0.120 | (0.5, 0.25, 5): 1 failed, sd 0.164 | (0.8, 0.2, 4): 1 failed, sd 0.107 (mean +0.275) | 64-seed runs: (0.4, 0.3, 6) 1 failed sd 0.188; (0.6, 0.2, 6) 3 failed sd 0.167.
  The failures are a stumble in the last strides: a swing-foot double contact (0.37 m step 0.12 s after the previous touchdown, seeds 8018, 8047), the sequence short step -> lengthening request -> scuff; the base run (j_run 1, no steering) falls 1 of 64 (8045).
  Chosen for now: j_st_w 0.5, j_st_max 0.25, j_st_n 5 (A2 params).
- Hop-height steering (new skill option j_st_zk in c2, off by default: the hop-height loop's reference moved by zk x the planned step change): NO steering effect (zk 1 or 2 with the hip nudge off: gap error sd 0.48, as unsteered; zk 1 + hip 0.3: sd 0.215, 1 failed of 64).
  Documented negative result; the option stays in the skill (default off, bit-identical).
- g2_z_ref (gear-2 hop-height reference, bound 0.8): v5 at 44 m 6.830 / 6.841 / 6.863 / 6.866 / 6.860 for 0.80 / 0.84 / 0.88 / 0.92 / 0.96 (16 starts, 0 falls): +0.035 only. (An 8-start window measurement of step length / speed had suggested +0.38 m/s; it was window noise.)
- Upright final approach (j_fin_dlean, over the last 12.6 m; A1 = -0.495, kp x3.6): v5 at 44 m = 6.609 (-0.495) / 6.701 (-0.3) / 6.772 (-0.15) / 6.827 (0.0); j_fin_kp 1 costs nothing extra to the speed. Full upright costs 0.22 m/s (~0.15 m of jump).
  Nominal pen state by setting (torso pitch, COM speed): -0.495: -0.06 rad, 6.57 m/s | -0.25: +0.05, 6.69 | 0.0: +0.13, 6.75 (chunk take-off: 3.01 / 0.0 fall-in-landing / 2.46 m).
  Ideal-control ceilings of the three states at equal effort: scratchpad/lj2/lean_ideal.sh (60k evals each, init gp_nom_ideal): out/long_jump_limits/lean_*_ideal.{log,json}.

## 2026-09-29 08:20 lean comparison (ideal-control ceilings of the nominal pen state, 120k evals each, lmax -1.5) and the final-approach choice

States (A2 steering 0.5/0.25/5): lean_m495 (dlean -0.495 over 12.6 m: pen torso -0.06, 6.57 m/s), lean_m250 (-0.25: +0.05, 6.69), lean_z000 (0.0: +0.13, 6.75).
 ideal D from the foot / toe behind the line / from the line: m495 5.033 / 0.254 / 4.78 (the init's own score: no improvement in 60k evals), m250 5.043 / 0.217 / 4.83 (climbed from 4.24), z000 4.831 / 0.283 / 4.55 (from 4.5).
 Both stage-2 continuations (60k more) found nothing: these searches plateau (the ideal is rugged: gp_nom, a nearly identical state of the 0.6/0.3/6 steering, reached 5.219; noise of the ceiling estimate ~0.2 m).
Shorter upright stretch (j_fin_d, dlean -0.495): v5 6.60 / 6.70 / 6.77 / 6.81 for 12.6 / 9 / 6 / 3 m; pen torso -0.06 / -0.05 / +0.01 / +0.05 (states findist_*). With j_fin_d 3 the upright shift acts only after the pen touchdown (w > 0 within 3 - 1.11 = 1.9 m of the line),
 i.e. not at all in an ik_from 1 jump: F3 = the natural approach with a slightly steadier trunk at the pen touchdown.
CHOICE: F3 = A3 (scratchpad/lj2/A3.txt: runner + ik2 j_* + g2_v_on 5.0 + steering 0.5/0.25/5 + j_fin_d 3), v5 6.81 vs 6.60 (A1); captures f3_nom, f3_s8001-8064 (capture_set.sh), ideal of f3_nom from two inits (f3_ideal.sh).

## 2026-09-29 08:30 the sprint agent's final runner (four gears, coordinator's note): same conclusion

- Frozen copy: params/lj_runner_gear4_v4_p95.txt = params/run_gear_v4_p95_g.txt (29 Sep 07:53, md5 e20f78c4; gears 4, switches 6.5 / 7.0 / 7.7 m/s; sprint trial 7.907 +- 0.019 m/s). Gears 1 and 2 are again IDENTICAL to params/run_gear_v4_p95_c.txt
  (diff of every non-g3/g4 key: only `gears 4.0` differs). The jump's run-up (44 m, 6.6-6.9 m/s at the board) never reaches gear 3 (7.0 m/s); the jump keeps the two-gear file (params/lj_runner_gear_v4_p95.txt).
- Provenance of everything computed so far: captures gp_* / lean_* / findist_* / f3_* and the ideal-control ceilings (gp_nom_ideal 5.219, lean_*_ideal) all come from the two-gear file params/lj_runner_gear_v4_p95.txt (= run_gear_v4_p95_c.txt) with g2_v_on 5.0;
  their approach is identical with the three- and four-gear files (gear 3 never engages). The approach params files are scratchpad/lj2/A1.txt (steering 0.6/0.3/6, j_fin_d 12.6), A2_*.txt (steering 0.5/0.25/5, lean variants), A3.txt (= F3).

## 2026-09-29 08:48 ARENA: long_jump_v4_p95 (one start) 4.945 -> 5.065 m (promoted)

params/long_jump_v4_gear_nom1.txt (= scratchpad/lj2/A1.txt: two-gear runner g2_v_on 5.0 + ik2's j_* + steering 0.6/0.3/6, plus out/long_jump_limits/ik_gp.txt: the distilled take-off program of the nominal start's ideal, ik_from 1) with controller bin/challengers/long_jump_run-c2, task long_jump_v4_p95b:
official 5.065 m (effective 5.262 from the foot, ballistic 5.049), take-off vx 6.177 vz 3.030 (26.1 deg), contact 0.094 s, foot 0.197 m behind the line, speed_5m 6.583, chunk landing (no landing program). ORACLE-class, one start.
Note the program transfers between similar states of the SAME approach (gp_s8003 4.96, gp_s8006 4.88 in the harness) but not to F3's (faster, trunk +0.05..+0.1) states (mostly invalid): every approach change needs its own program.

## 2026-09-29 08:50 robust stage B (F3 approach: j_fin_d 3, steering 0.5/0.25/5, v5 6.81)

F3 nominal ideal (60k evals from the m250 optimum, lmax -1.5): D 4.957 from the foot (vx 6.274, vz 2.981, contact 0.088, toe 0.183 behind the line -> 4.775 from the line); distilled out/long_jump_limits/ik_f3.txt.
Applied as it is to the other F3 training states in the harness: 11 of 23 valid (the rest: a runway touch after the take-off), D_board 4.3-4.7 -> the robust stage has to make the program tolerant (the A1 program on the A1 states: 17 of 24 valid, D_board 4.7-5.0 mostly).
Launched: scratchpad/lj2/rob_f3.sh = long_jump_limits.py robust out/long_jump_limits/ik_f3.txt --captures <f3_nom + 19 plant-l captures of seeds 8003-8032> --nk 19 --evals 300000 --workers 2 --sigma 0.04 --g0 0.3 --lmax=-1.5 --out out/long_jump_limits/rob_f3.txt (log rob_f3.log; robust needs same-plant-side captures: it reads the tables by the first capture's side).

## 2026-09-29 08:58 robust stage A queued (A2_m495 approach: steering 0.5/0.25/5, j_fin_d 12.6 dlean -0.495, v5 6.60)

Captures am_nom (= lean_m495) + am_s8001-8064 (63 states; only seed 8045 has no plant flight: the runner's own fall, as in j_run; the steering 0.5/0.25/5 adds no falls here); programs: ik_am.txt = distil of lean_m495_ideal (5.033).
Nominal programs on the am training states in the harness (20 starts): ik_gp 13 valid (mean D_board of the valid 4.53), ik_am 13 valid (4.57).
scratchpad/lj2/rob_am.sh waits for rob_f3.done, then robust ik_am.txt over am_nom + 19 plant-l captures (same options as B). Compare A (6.60 m/s) and B (F3, 6.81 m/s) by the harness score on held-out captures (am_val / f3_val) and then by full rollouts.

## 2026-09-29 09:05 new arena trial long_jump_v4_p95_robust96

scratchpad/lj2/add_trial.py (under the arena lock; nothing existing touched): long_jump_v4_p95_robust96 = long_jump_v4_p95_robust32's scene, rules, body and metric on 96 fresh starts (seeds 9033-9128, the v3 robust96 seeds), task long_jump_v4_p95b.
Seeded with the round 2 champion of the 32-start trial (params/long_jump_v4_p95_ik2.txt, controller long_jump_run-b20w): 2.5355 +- 0.369 m on 96 starts (failed 33 %; foot offset -0.43 m, speed_5m 6.34).
The eval rows of every trial I run are in scratchpad/lj2/eval_*.txt (long_jump_eval.py, per-start lines with the failure class).

## 2026-09-29 09:40 robust stages A and B: the more upright approach is the controllable one

Steering scans on the F3 states (ikgap.py, 64 starts, un-robust ik_f3 program, penultimate gap error rel. to 1.817): (0.5, 0.25, 5): sd 0.15-0.16; (0.5, 0.4, 5): sd 0.136, a uniform spread -0.09..+0.39; (0.5, 0.25, 7): sd 0.22 (2 outliers); gentle long horizons (0.8, 0.12, 10): sd 0.26, 2 failed; (1.2, 0.1, 10): sd 0.31, 10 failed.
 Moving the planner's target gap (j_board_shift 1.37 / 0.92 -> target 1.85 / 2.30) moves the mean gap (1.78 / 2.19) and leaves the spread (sd 0.15 / 0.20). A speed clamp (g2_v_cap 6.8-6.9 with g2_k_brake 1-2) does nothing to the v5 spread (sd 0.05 -> 0.04).
 The floor is ~0.13 m of pen-gap sd: the take-off program has to absorb +-0.25 m.
ROBUST B (F3 approach, rob_f3: 20 plant-l starts, 296k sims, 27 min): 11 of 20 valid at D_board 3.7-4.3, 9 INVALID. whyall.py: every invalid start is a free-foot ('r_toes') touch of the runway 0.03-0.05 s after the take-off (program time 0.39-0.42 s), all of them the FAST starts
 (pen COM speed 6.9-7.1, gap error -0.3: gap 1.64-1.79, pen->plant flight ~0.07 s shorter): with the plant early the free leg has not swung up. Best objective -1.86 (mean 0.39, min -4.11). The un-robust programs do the same (A1 program on A1 states 17/24 valid, F3 program on F3 states 11/23).
ROBUST A (am approach = A2_m495: upright final approach over 12.6 m, v5 6.60; rob_am, 20 plant-l starts): at generation 320: best 3.910, mean 4.014, MIN 3.806: ALL 20 valid (board-relative ballistic distance 3.8-4.0+ on every training start).
 => the faster, less upright states (F3: +0.2 m/s at the board) break a single take-off program; the upright approach (torso -0.05 at the penultimate touchdown, free foot higher) is what a program can be robust to. Speed is traded for controllability: A is the working family.

## 2026-09-29 09:50 what the robust program gives, and the price of robustness

robust A stopped at generation 350 of ~580 (best flat since 310; snapshot out/long_jump_limits/rob_am_g340.txt = rob_am.txt): scripts harness_eval.py on its 20 training starts: 20 valid, 0 fouls, D_board mean 4.02 (min 3.81), foot offset -0.052 +- 0.041 (the program compensates the pen gap: slope -0.22, was -1.0; the pen gap sd is 0.166).
 BUT the take-off is a compromise: on the NOMINAL start it gives vz 2.40 / vx 6.07 (D_board 4.13) where its own ideal has vz 3.10 / vx 6.3 (5.05); the short-gap fast starts (gap 1.6-1.7, vx 6.7-6.8) get vz 1.4-1.6 (D_board 3.8-3.9): keeping the foot behind the line with a shorter plant step costs vertical velocity.
 The program's gap dependence is linear (e0 + gap_err x e1 on the excitation knots, the contraction targets do not depend on the gap) and was searched from the nominal ideal by CMA in 1800 dims: it found the foot-placement compensation but not the per-state ideals.
 NEXT: ideal-control programs for the fast end (am_s8010, gap 1.59) and other gaps, then an initial e0 / e1 interpolated between them (a linear-in-gap program that starts near both ideals), then robust from there. Ideal for am_s8010 running (init lean_m495_ideal, 100k evals, log am_s8010_ideal.log).

## 2026-09-29 10:05 full rollouts of robust A: the failures are the landing, gap outliers and a few mm of foul; steering asymmetry; j_st_rnd

Full rollouts of params/long_jump_v4_gear_am_r1.txt (A2_m495 approach + rob_am_g340, chunk landing; c2) with scratchpad/lj2/eval_all.sh: 16 arena starts: 4 legal, mean 1.00; 32 fresh: 17 legal, mean 2.08; 96 fresh: 48 legal, mean 1.93 (scratchpad/lj2/eval_am_r1_*.txt).
 Failure classes (16 starts): 5 somersault (short flights vz 1.6-2.4 with the chunk landing, as in round 2: the landing program is what saves them), 3 fouls of 2-19 mm (a 0.05 m check-mark shift), 3 fell-in-run, 2 far misses (foot 1.8 m behind the line).
 The harness on the same starts' captured states (ar_*, harness_eval.py) predicts every one of them: the far misses and the runway-after-take-off invalids are the starts whose penultimate gap is OUTSIDE the trained range (2.18-2.49 vs a training range 1.6-2.08); on the 44 held-out captures of the 63 (both plant sides) the program is valid on 42 (D_board mean 4.08, 3 fouls).
 Steering asymmetry (dbg traces of seeds 416, 404): a request to LENGTHEN the next step (plan 1.83 vs stride 1.65) comes out as a SHORT step (1.45): a forward reach makes the foot touch down early. Shortening works. So the starts that need lengthening end with a penultimate gap 0.2-0.5 m too FAR: the outliers.
 New skill option j_st_rnd (c3, default 0.5 = the rounding of the step count to the nearest, bit-identical): toward 1.0 the plan shortens instead of lengthens. Penultimate gap errors on 80 starts (8001-8064 + 401-416): rnd 0.5: -0.34..+0.32, 0.75: -0.38..+0.18, 1.0: -0.44..+0.11.
 Chosen j_st_rnd 0.75 (A4 = A2_m495 + j_st_rnd 0.75, scratchpad/lj2/A4.txt): the far outliers disappear, the near side (gap 1.55) is what a program handles (vz 1.4-1.6).
 The fast-state ideal (am_s8010, gap 1.59, td constrained to 0.268, D from the foot) put the foot 0.45 m PAST the line: board-relative ideals now (ROBOLAB_LJ_BOARD=1, foul margin 4 cm) for the nominal and the fast start: scratchpad/lj2/ideal_board.sh.

## 2026-09-29 10:25 board-relative ideals; robust stage A4 (two plant sides, gap-stratified)

Board-relative ideals (ROBOLAB_LJ_BOARD=1, plant touchdown held at 0.268 s, foul margin 4 cm; out/long_jump_limits/am_nom_bd.json, am_s8010_bd.json): nominal start (gap 2.05): D 4.954 from the foot, foot 0.093 behind the line -> 4.861 from the line
 (vx 5.99, vz 3.17, 27.9 deg, contact 0.092 s, L -3.3; before, foot mode: 4.78 from the line); the fast short-gap start (gap 1.59): a poor optimum, D 3.10 (vz 0.7): keeping the foot behind the line from a 1.59 m gap is a different take-off (a normal step) and the search from the foot-mode init
 did not find it. So the two-ideal interpolation is not usable as it stands (needs a good ideal at the short-gap end); NOT pursued further for now.
A4 captures (A4.txt = A2_m495 + j_st_rnd 0.75, controller c3, seeds 8001-8128): 125 states (3 no-plant: 8045, 8103, 8104): penultimate gap mean 1.891 sd 0.159, range 1.52-2.27, 93% within 1.55-2.15 (histogram 0.1 bins from 1.4: 0 3 15 23 14 36 25 6 3).
Harness patched for training on both plant sides (side_perm / mirror_tab in long_jump_limits.py: robust and landing read the role tables mirrored for the other side; default single-side behaviour identical) and for board-relative ideals (ROBOLAB_LJ_BOARD/TD/TDW/MARGIN).
robust stage A4: scratchpad/lj2/rob_a4.sh = robust rob_am_g340.txt --init rob_am_g340.txt --captures <32 gap-stratified a4 states: 26 plant-l, 6 plant-r, gaps 1.52-2.01 ...> --nk 19 --evals 400000 --sigma 0.03 --risk 0.3 --lmax=-1.5 (out rob_a4.txt, log rob_a4.log).

## 2026-09-29 10:55 robust A4 done; full rollouts with the chunk landing; landing search started

robust A4 (rob_a4.sh, 400k sims, 480 generations, 31 min; out/long_jump_limits/rob_a4_final.txt): 31 of the 32 training starts valid (board-relative distance 3.7-4.7, mean of the valid 4.34; plant offset -0.03, slope on the pen gap -0.04: the gap is compensated), 1 invalid (a free-toe touch of the runway after the take-off).
 Held-out harness (93 captures of the same seeds set, both plant sides; harness_a4_val.txt): 86 valid, 3 fouls, D_board mean of the valid 4.39, min 3.58; the 7 invalid: 3 near extremes (gap 1.64-1.76) and 4 far outliers (2.16-2.27).
 The harness predicts the full rollouts start by start (arena seeds 401-416 with the A4 approach: the 4 harness-invalid starts are the 4 fell-in-run starts, the valid ones jump within -0.1..+0.3 m of D_board).
Full rollouts of params/long_jump_v4_gear_a4_r1.txt (A4 approach + rob_a4_final, chunk landing, c3): 16 arena starts: 7 legal (foul 3, somersault 2, fell-in-run 4), mean 1.97, legal mean 4.51;
 32 fresh: 21 legal (foul 2, somersault 7, fell 1, short 1), mean 2.95; 96 fresh: 60 legal (fell-in-run 9, foul 8, somersault 18, short 1), mean 2.81, mean of the legal 4.49.
 The somersaults are the chunk landing on the short flights (short-gap fast starts: vz 1.5-1.9); the fell-in-run are the harness-invalid class (free toes touching the runway after the take-off); the fouls are mm-scale.
landing search: scratchpad/lj2/land_a4.sh: 62 hand-overs (hoa4r: the 32 training starts + 1 execution-noise variant each; post_robust.sh a4 with VARIANTS=1 RECSEED=8039), the recorded chunk landing of seed 8039 (sand 0.584 s after the hand-over) as the base, tg 0.60, lz 0.8, h 0.08, nk 34,
 tail 10 %, jitter, 300k sims. The chunk landing as the start rolls over on all 26 hand-overs of the short-gap starts (-4.6) and lands the others 4.2-4.9.

## 2026-09-29 12:35 (resumed after the watchdog stall of ~11:36-12:14; everything below was checked against the files)

State found: landing search land_a4.sh (pid 88001, --handover hoa4s, 2 workers) still alive, gen 60 at 4249 s (the stall cost ~35 min of its wall time; best 2.897, mean 4.401, min -4.617); snapshot out/long_jump_limits/land_a4.txt (12:15).
Milestone promotions made just before the stall (arena history 11:41-11:48; params/long_jump_v4_gear_a4_m1.txt = scratchpad/lj2/A4c.txt (clean approach params) + rob_a4_final.txt + the generation-40 landing snapshot, controller bin/challengers/long_jump_run-c3):
 - long_jump_v4_p95_robust32: 2.851 -> 3.9231 m (+1.072, p 0.005), 27 of 32 legal (foul 2, fell-in-run 2, somersault 1), mean of the legal 4.65: PROMOTED.
 - long_jump_v4_p95_robust96 (new trial, seeded 2.5355): 3.4708 m (+0.935, p 0.0005), 72 of 96 legal (fell-in-run 9, foul 8, somersault 7), mean of the legal 4.62: PROMOTED.
 - long_jump_v4_p95_robust (16 arena starts): 2.3146 vs the champion's 2.1452 (p 0.41): NOT promoted (8 of 16 legal: foul 3, somersault 1, fell-in-run 4).
 (before that, the same take-off with the chunk landing: 16: 1.97 (7 legal), 32: 2.95 (21), 96: 2.81 (60); the landing table lifted the legal count on the 96 from 60 to 72 and the mean from 2.81 to 3.46.)
Exactness re-checked with the current build (c3, source md5 a40a3113) after every skill and harness edit of the session, per-seed equal to the stored scores: long_jump_p95 (ik11) 5.1220, long_jump_p95_robust (pn1, 16 starts) 4.6305, long_jump_v4_p95 (nom1) 5.0650,
 long_jump_v4_p95_robust32 (a4_m1) 3.9231, and the round-2 v4 params ik5 4.945 (one start) and ik2 2.1452 (16 starts). The harness patch (mixed plant sides in robust / landing; board-relative ideal; td constraint; margin; DV) is in place and BIT-IDENTICAL to HEAD for single-side inputs:
 robust x0 scores [4.74, -1.17, 4.58] and landing x0 [4.81 4.8 4.78 4.54 4.63] equal in both versions (checked with a HEAD copy of the file).
Worker cap now 4 while the 5-min load is under 30 (coordinator, 11:37 and 12:14): 5-min load 25.7 at 12:33.

## 2026-09-29 12:50 landing converged; full rollouts with the generation-60 snapshot

Landing search land_a4 (62 hand-overs) stopped by me (pid 88001) after generation 60-63: the snapshot at gen 60 lands 60 of the 62 hand-overs at 4.28-4.91 m from the line (harness); the two that roll over are the extreme short-gap start a4_s8124 (gap 1.52, vz 1.4) and its variant.
Full rollouts with it (params/long_jump_v4_gear_a4_l60.txt = A4c + rob_a4_final + scratchpad/lj2/land_a4_g60.txt; c3): 16 arena starts 2.323 (8 legal; foul 3, somersault 1, fell-in-run 4), 32 fresh 3.934 (27 legal), 96 fresh 3.483 (72 legal; fell-in-run 9, foul 8, somersault 7), mean of the legal 4.65:
identical counts to generation 40 (2.309 / 3.913 / 3.463): the landing is done; what is left is (1) the fell-in-run class (9 %, the take-off's invalid states: late stride phase, trunk forward, free foot behind), (2) mm-scale fouls (8 %), (3) somersaults after weak short flights (7 %).

## 2026-09-29 13:10 check mark, greedy feedback, one-start landing

Check-mark shift (j_board_shift -d, ik_gap0 +d: the planner aims d further back, the program sees the same gap error), params a4_l60 on the UNUSED seeds 7001-7096: d 0: 3.150 (66 legal), 0.02: 3.488 (74; foul 4, somersault 6, fell-in-run 12), 0.03: 3.625 (77), 0.04: 3.495 (74; foul 0, somersault 12, fell 10), 0.05: 3.411 (72). Plateau 0.02-0.05, peak 0.03: d = 0.03 (j_board_shift 1.08, ik_gap0 1.876777).
Greedy swing-foot lag feedback (greedyfb --channels kf on the a4 captures, 94 train / 31 held out; out/long_jump_limits/fb_a4.txt): NOT adopted: the harness objective's weak-take-off penalty (vzmin 2.55) is v3's and the A family's vz is 1.5-2.4; the invalid count did not fall (train 3 -> 5, held out 2 -> 2).
The harness-invalid class (8 of 125 a4 captures): no cheap detector: swing toe height at the penultimate touchdown does not separate them; 5 of 8 are 'late stride phase' states (COM 0.905-0.926 m vs 0.985, trunk +0.07..+0.19 rad, swing foot 0.52-0.62 m behind the COM), 3 are far gaps (2.16-2.27).
One-start landing: hand-overs of the nom1 take-off program (nominal + 4 execution-noise variants, D_board 4.79-4.89, vz 2.95-3.13; out/long_jump_limits/hogp_handover.npz), the recorded chunk landing (sand 0.716 s after the hand-over; official 5.065, the HEAD marks, the jumper falls back) as the base;
 scratchpad/lj2/land_gp1.sh: landing search, tg 0.73, nk 34, h 0.08, 4 workers (5-min load 24), 25k sims -> out/long_jump_limits/land_gp1.txt.
