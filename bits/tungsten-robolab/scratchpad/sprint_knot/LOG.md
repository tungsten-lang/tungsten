# Sprint on v4: campaign log (sprint agent, from 2026-09-29)

All campaign state lives in the repo (scratchpad/sprint_knot/, out/, params/). Never /private/tmp.

## 2026-09-29 01:15 start
- Machine NOT idle at start: load average ~50 on 18 cores (metaflip project_screen 8 workers, screen_public_ternary 12 jobs,
  mmc_gf2_seeds 4 jobs, Codex robolab dribble R11 3 workers). Wall-clock times below are inflated 2-3x; sim results are
  deterministic and unaffected. Using at most 4 workers per search, at most 2 searches at once.
- Read: README (touch-only sprint, RI, toward 10 m/s, round 3 v4), arena README, v4.json. HANDOFF_20260929.md does not exist.
- Trials sprint_top_speed_v4 / _v4_p95 / _v4_elite2 all hold seeded failing baselines (-1e9 on 12/12 seeds, seeds 221-232).
- Frozen controller: bin/challengers/run_ri-v4base (RunRISkill, built 9/28 15:52).

## Step 1: held-out check of v4r1 (seeds 51-62, 30 s, workers 4), then enter on sprint_top_speed_v4
- 01:15 v4r1 held-out (seeds 51-62, 30 s, run_v4, run_ri-v4base): 12/12 no fall; peak_speed_1s 4.645-4.657 on 10/12, but seeds 56 and 62
  fall to a slower attractor (steady 3.20, peak 3.856 / 4.073; contact 0.22 s, flight 0.06 s). Whole probe took 15 s wall
  (30 s sim = ~5 s wall even at load 50, so 1800-rollout searches take ~25 min, not hours).
- 01:16 ARENA sprint_top_speed_v4: v4r1 (params scratchpad/sprint_knot/v4r1.txt, controller run_ri-v4base) PROMOTED over the failing baseline
  (p 0.0005; 11 differing starts). Scores on seeds 221-232: 4.646 4.643 4.646 4.650 4.661 [226: FALL = -1e9] 4.637 4.666 4.641 4.648 4.645 4.650.
  mean of the 11 survivors 4.648 m/s = 56.7 % of the v4 average-body ceiling (8.2). Frozen: bin/champions/sprint_top_speed_v4-20260929-011607.
  One arena seed (226) falls, and held-out seeds 56/62 land in a slower attractor (3.86/4.07): the next stage must fix robustness
  as well as speed. Any better challenger must also survive seed 226.
- 01:35 diagnostics: scratchpad/sprint_knot/stridetab.py (per-stance table). v4r1 steady stance (seed 221, 20 s): contact 0.162 s, flight 0.149,
  thigh TD +0.276 / LO -0.456, knee TD 0.139 / max 0.142 (a straight-leg pogo), ankle TD 0.14 -> LO 0.67, vGRF mean 1.91 BW, PEAK 10.6 BW at 5 ms
  (impact: foot vz -2.3 m/s at touchdown, foot vx +0.38), braking = propulsion = 0.035 BW s, trunk pitch 0.49 -> 0.76 rad through the stance
  (lean param at its 0.4 bound). Ideal at 8 m/s: TD thigh +0.5, knee 0.5, contact 0.124.
- 01:35 LAUNCHED a1 (avg v4, objective 5 st_td 0.5, init v4r1, sep_cma 2400 rollouts, 4 seeds 31-34, risk 1.0, 20 s, sigma 0.04)
  and p1 (P95 v4, objective 2, init v4p_init = v3 P95 champion, 2400 rollouts, seeds None,31,32,33, risk 0.5, 20 s, sigma 0.06).
- (times above are +-10 min: the clock read 01:32 when the next lines were written) a1 (objective 5 from v4r1) was stuck: 350.1 -> 351.4 in 7 gens; killed.
  v4r1 is an isolated straight-leg 'pogo' basin: try.py shows that nearly any change breaks it (gate_push 1 falls, k_reach 0.4 -> 3.25 m/s, cv 0.1 falls,
  knots 1 falls, v_top/v_cap 8 changes nothing: speed is set by the gait mechanics, not the plan). stance table: 60 % of the vertical impulse is
  delivered in the first 35 ms by a rigid-leg COLLISION (10.6 BW spike, foot vz -2.3 m/s at touchdown).
- p1 (P95 v4 from the v3 P95 champion) meanwhile found a smooth bent-knee gait: at 1500 rollouts peak 6.60 m/s steady 6.46, contact 0.124 flight 0.146,
  TD thigh 0.54 knee 0.55 (ideal 0.47/0.54), LO thigh -0.35, peak vGRF 3.8 BW, effort 0.24 (63 % of the P95 ceiling 10.45).
  p1's params on the AVERAGE v4 body: peak 4.92 but falls 2/3, bent-knee. => a2 = average body from p1_snap1.txt (objective 2, 2400 rollouts, sigma 0.06).
- built run_knot with opt-in fly_entry (flying start without knots; default identical: knots 0 + fly_entry 0 reproduces run_ri-v4base exactly);
  frozen bin/challengers/run_knot-v4b. sprint_touch_v4.py: snap = ROBOLAB_SNAP env (default run_v4 unchanged).
- 01:52 p1 DONE (2400 rollouts, 29 min): P95 v4 peak 7.049 steady 7.01 (20 s, 4 rollouts: None,31-33). NEW GAIT MODE: crouched high-cadence bounce
  (step 4.0/s, contact 0.108, flight 0.054, TD knee 0.83, knee max 1.0, torso upright 0.11 rad, irregular stride std 0.076 s, scuffs 4/s): 67 % of the P95 ceiling.
  The earlier p1 snapshot (gen 25, 6.60 m/s) was the ideal-like extended-knee mode: TD thigh 0.54 knee 0.55 (ideal 0.47/0.54), knee max 0.75, LO knee 0.21.
  Saved: p1_snap1.txt (6.60, ideal-like), p1_final.txt (7.05, crouched).
  a2 (avg from p1_snap1) at gen 9: peak 5.67 steady 5.61 (69 % of 8.2) vs v4r1 4.65 => the P95-derived basin is better for the avg body too.
  try.py on p1_snap1: drv_hip 0.6 no effect; torso_kp 0.6 +; ri 0.7 falls, ri 0 -0.4; drv_ham<1 falls; stiff_up 0.3 worse.
  Added playground/search.py --box name=lo:hi (opt-in) since t_push_max, k_land, t_land, hip_lead, g_kl, torso_kp, vz_push, a_push, k_late sit on their bounds.
- 01:53 LAUNCHED p2 = robust stage of p1_final (30 s x 6 seeds 31-36, risk 1.0, sigma 0.025, 1800 rollouts).
- 02:20 sep-CMA stalls on fragile optima: a2 flat at 459.5 from gen 9 to 27, p2 640.6 -> 645. sens.py on p1_final (crouched P95 gait): a 4 %-of-box move
  of 41/188 single parameters makes seed 31 FALL (knife edge); held-out check of p1_final: 17/24 seeds survive 30 s (falls at 3.8-7.7 s and 27-29 s).
  Diagnosis: sigma 0.04 in 94 dims = 0.4 L2 step, far above the ~4 % safe move of ~40 critical parameters, and CMA's CSA never shrinks sigma on repeated failure.
  => NEW playground/hsearch.py (own tool, opt-in): successive-seed pruning (min-over-seeds scoring: a candidate below the incumbent after seed 1 is never run on the others,
  3-5x more generations per rollout), methods es ((1+lambda) sparse-mutation ES with success-rate sigma) and sep_cma with restarts around the incumbent; --archive for a
  validation pass (scratchpad/sprint_knot/select.py: top archive entries on 12 fresh seeds, ranked by falls then mean peak).
  Killed p2 (sep_cma robust, best 645.13, saved p2_snap.txt); h2 = hsearch ES from p2_snap (30 s x seeds 31-36, sigma 0.02, lam 24, budget 2400).
  Also: try.py knot stance seeded from the v4 P95 ideal (9 m/s) on the 6.6 m/s extended gait falls (TD knee comes out 0.81 not 0.54): knots do not work out of the box on v4 either.
  NOTE zsh: unquoted $FILES does not word-split (screen.py got one file name); use arrays.
