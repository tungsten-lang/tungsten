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
