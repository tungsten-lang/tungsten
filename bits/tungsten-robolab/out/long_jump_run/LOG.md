# long jump workstream log (round 2, continued 2026-09-29)

Running log. All state stays in the repo (out/long_jump_limits, out/long_jump_run, scratchpad/lj, params).

## 2026-09-29 01:20 start of the session

- machine is NOT idle: load average 50-60 on 18 cores (metaflip wide-rect-walk x12, Codex dribble pools). Throughput per worker ~0.4 core.
- there is no HANDOFF_20260929.md; state reconstructed from the files.
- bin/robolab_long_jump_run == bin/challengers/long_jump_run-b13 (cmp identical): the COM-gated landing latch (il_lz) is in b13.
- p95 "pn" family = take-off program started at the PENULTIMATE touchdown (ik_from 1, ik_n 18, ik_td 0.244): out/long_jump_run/p95pn_ik.txt; landing = out/long_jump_limits/land_p95pn3.txt (il_lz 0.8, snapshot of the search killed by the reboot).
  NOT in the arena yet (long_jump_p95 4.895 is params/long_jump_p95_ik3.txt, robust 3.924 is ik2d).
- land_p95pn3 marks on its 32 hand-overs (p95pn2h): 27 land 4.66-4.96; 3 roll over (idx 16 = s1009, 18 = s1010, 19 = s1010_v1: -4.5) and 2 are take-off fouls (idx 23 = s1012_v1, 27 = s3036_v1: toe 2-24 mm over the line, scored -1.0 by the landing search, not a landing problem).
  The three roll-overs are the hand-overs with the highest vx / lowest vz (s1009 6.31/2.49, s1010 6.27/2.49, s1010_v1 6.36/2.37).

## 2026-09-29 01:30 diagnosis of the roll-overs (playground/long_jump_diag.py, new)

Mechanism (hand-overs 16/18/19 of p95pn2h, land_p95pn3 program): the COM at the hand-over is ~0.09 m lower / vz ~0.2 m/s lower than the clean ones, so the ballistic time to land is 0.50-0.53 s instead of 0.56-0.61 s. The landing program is on a HAND-OVER clock (knots every 80 ms, the sand only re-syncs it), and its leg retraction ("hover the feet ~0.1 m above the sand until the reach") comes ~30-50 ms too late: the toes touch the sand at t=0.36-0.39 s with the COM still 1.0-1.06 m high and the legs hanging straight down, 0.1-0.2 m BEHIND the toes' x. Vault: Ly 0 -> 75-110 kg m2/s in 0.1 s, torso pitch passes pi = somersault. The clean landings (idx 0, 17) touch at 0.59-0.62 s with the COM at 0.4 m and the feet 0.6 m ahead.
Not a rotation-control problem: a timing problem of a fixed-time program.

Fix (opt-in, defaults bit-identical): the BALLISTIC-TIME CLOCK (`il_tg`, `il_zl`): before the sand the landing program time is il_tg minus the COM's ballistic time to fall to il_zl (a flight is ballistic whatever the limbs do), so tuck/reach are locked to the predicted landing; never runs backward; holds at il_ld; real time from il_ld after the sand. Python: LandingProgram(tab['tg'], tab['zl']) in long_jump_limits.py (`landing --tg`), skill: LongJumpRunSkill#il_apply, il_tg/il_zl params.

Scan with the UNRETRAINED land_p95pn3 program on the 32 hand-overs (playground/long_jump_diag.py --tgs):
  tg 0 (old clock): roll-overs 3 [16,18,19]; tg 0.50-0.55: 20-30 roll-overs (program too early); tg 0.57: 3; tg 0.58-0.66: 0 roll-overs, marks 4.6-4.98 (mean of the 30 legal 4.79); tg 0.68: marks -0.1; tg 0.70+: shorter marks. Plateau 0.58-0.66, centre 0.61.
  The two remaining -1.0 are TAKE-OFF fouls (toe 11 and 23 mm over the line in the noisy variants), not landings.
Files: bin/challengers/long_jump_run-b14 (skill with il_tg; b13 = the COM gate only), params/long_jump_p95pn_a.txt (= p95pn_ik + land_p95pn3, no il_tg yet).

## 2026-09-29 02:30 what the failures are (112 starts: 96 fresh seeds 7001-7096 + the 16 arena seeds), p95pn + ballistic-time clock

Full-rollout failure classes (tg 0.61-0.64): ~6 fell-in-run, 5-6 somersault, 3 foul of 112; legal mean 4.71-4.72 (!), mean over all 4.03-4.08.
 - 'fell-in-run' = 4 SCUFFS + 2 real run stumbles: the plant-side swing toe clears the runway by 1.2 cm in a healthy start (site z 0.032 vs 0.019 = on the ground) and drags for 0.1-0.15 s in a bad one; the plant-touchdown latch (force > 0.05 BW) fires on the scuff at 0.10 s (ideal touchdown 0.244 s), the program clock jumps ahead and runs the stance in the air.
   Fix: ik_fmin (latch needs >= 1.5 BW: a real plant reads 4 BW on its first tick, scuffs 0.2-0.94) + swing-foot clearance reflex (ik_clz, ik_kc_*).
 - somersault = WEAK TAKE-OFFS: vz 1.6-2.4 (typical 2.7-3.0), torso pitch at the penultimate touchdown 0.11-0.19 rad (typical 0.08+-0.03): harness regression vz = 3.05 - 3.98 x pitch. Short flights (0.37-0.6 s) land with the legs hanging.
 - fouls: upright starts (pitch 0.03-0.05), 1-4 cm over: a +0.05 m check-mark shift.
 - an il program trained on 32 hand-overs OVERFITS the clock: tg 0.70 -> 48 somersaults of 112 in full rollouts although the 32 training hand-overs still land (harness scan). Landing training needs many more hand-overs (mined: 161).
The harness (long_jump_limits.py handover) reproduces every failure class of the full rollouts (checked on 12 failing seeds).
Mining set: seeds 8001-8162 captured at the penultimate touchdown -> out/long_jump_limits/p95mn_s*_capture.npz (161), hand-over set p95mnh; features vs outcome in out/long_jump_run/mine_p95mn_tg61.txt.
Speed profile of the runner (skill j_run 1): 6.88 m/s at 37.5 m, 6.94 at 45 m, 6.95-6.96 at 55-60 m: a longer run-up adds ~0.06 m/s (~0.05 m); the p95 body's top speed is the limit.
New skill options (b16, all off by default, identity-checked vs b15): ik_fmin, ik_pr*/ik_kp_*/ik_kd_* (rotation feedback in the take-off), ik_clz/ik_clt/ik_kc_* (swing-foot clearance). New search: long_jump_limits.py robustfb (feedback residuals around the fixed take-off program, tail-weighted, held-out set).
b15 fixed: jump:takeoff was announced at the penultimate touchdown for ik_from 1 programs, so the task counted the penultimate stance's own 0.17 s flight as a take-off that landed short (the p95pn family never worked end to end before).

## 2026-09-29 02:55 weak take-offs: a one-sided pitch feedback on the free-leg hamstrings; the mirroring pitfall

- Hand-set probe on 161 mined starts (harness, all with the plant latch ik_fmin 1.5): ONE gain, kp +6..16 on F_ham (the pen/free leg's hamstrings) times the torso pitch error against the program's own average pitch trajectory, one-sided (only a forward lean beyond the average): vz<2.4 starts 10 -> 1, mean 4.10 -> 4.19, worst-10% 1.17 -> 1.80. Two-sided the same gain HURTS (upright starts lose vz). Skill option ik_fbclip 1 (b18).
- The plant latch alone (ik_fmin 1.5) removes every scuff failure in the harness (invalid 3 -> 0 on the mined set).
- PITFALL found and fixed: the take-off tables are BY ROLE (T_ = plant-side leg, F_ = free leg). 4 of 161 mined starts take off with the LEFT foot; a search that reads the tables with the first capture's side mirrors them wrongly for those starts (they showed up as 'invalid' in fbg1 and in my first probes). greedyfb now builds tables and gain vectors per capture side (plant_bases, role_vec). The earlier 'robust' stage (ik programs) had the same single-side limitation but its training sets were all one side.
- landing (il) sync clock on the average body (p50wh, land_p50w2): the 4 roll-overs are NOT fixed by the clock at tg 0.38-0.55 (zl 0.35): a different mechanism there; p50 deprioritised.
- elite2: champion low arena starts are 607 (vz 1.87, flight 0.42 s -> 2.78 m) and 609 (take-off foot 0.51 m behind the line -> 3.65).
- ik3 (long_jump_p95 champion, 4.895) hand-over: T_go 0.679; single-start il search started (land_p95k3.txt) to see whether a landing program trained on that ONE start beats the chunk landing's 4.895 (deterministic trial, any strict gain promotes; label: overfit to one start).

## 2026-09-29 03:25 take-off feedback: promising but fragile; landing retrain on the mined hand-overs first

- Full rollouts, 112 starts (7001-7096 + arena 401-416), b18, task long_jump_p95g (check mark +0.05):
    p95pn_a + tg 0.61 (no latch)            : 97 legal, mean 4.078 (delta 0), legal mean 4.708
    + latch 1.5 + F_ham kp 8 one-sided      : 102 legal, mean 4.243, legal mean 4.659 (delta 0.05 costs 0.05 m); 0 fouls; 7 somersault, 3 fell-in-run
  Every somersault has take-off L > 1.7 kg m2/s (or pitch >= 0.24 rad); the legal jumps have L -5.8 +- 2.0, pitch 0.07 +- 0.07: the F_ham feedback lifts vz but turns the lean-forward starts into FORWARD-rotating take-offs that the landing cannot save.
- Harness on 316 mined starts: the swing (plant-side) foot 0.5-0.7 m behind the COM at the penultimate touchdown (a late stride phase, ~10% of starts) is the weak/failing class. F_ham kp 8 on them gives L +2..+23 and one start with vz -0.1: the feedback must be BOUNDED (clip the error) and constrained (L <= -1.5, pitch <= 0.25 penalties in the search: --lmax -1.5 --lw 0.3 --pmax 0.25 --pw 3): greedy fbg4 then still picks F_ham 8 and arm gains, held-out has a catastrophic start (-15). Parked.
- Current baseline for the landing: take-off = p95pn_ik.txt + ik_fmin 1.5 (out/long_jump_run/p95pn_latch.txt). Old landing (land_p95pn3, tg 0.61) on 316 mined hand-overs (harness): 18 roll-overs of 299 (6.0%), mean mark of legal 4.717.
- Landing search land_p95mn2 (log out/long_jump_limits/land_p95mn2.log): 121 training hand-overs of p95mnh3 (31 hard + 90 random; the other 78 held out as p95mnh3_lval), sync clock tg 0.61, time-to-strike reflex (--clearance), rotation feedback, tail risk (worst 5%), --ignore-foul, pop 16, init land_p95pn3.
- Hand-set time-to-strike reflex (hip+knee flexors + ankle dorsiflexors, ctau .15-.25 s) rescues 2 of the 5 weak hand-overs of the fresh validation set in the harness.
- Elite2 mining captures running (prefix e2m, seeds 8001-8160).

## 2026-09-29 03:30 ARENA: long_jump_p95 (one start) 4.895 -> 4.958 m (promoted)

params/long_jump_p95_ik9.txt = params/long_jump_p95_ik3.txt (the champion's take-off program) + out/long_jump_limits/land_p95k3.txt (a landing program learned for the nominal start's hand-over: 5 hand-overs = nominal + 4 execution-noise variants, ballistic-time clock il_tg 0.679, 20 generations / 2700 sims, snapshot land_p95k3_g20.txt), controller bin/challengers/long_jump_run-b19c (skill b19: il_tg clock). Official 4.958 m (effective 5.041), take-off vx 5.887 vz 3.001, foot 0.072 m behind the line. ORACLE-class (il excitation table), overfit to one start by construction. Run continues (land_p95k3b.txt) in case it goes higher.
Honest baselines on FRESH starts (96 seeds 7001-7096, never used in practice): the p95 robust champion (ik2d, arena 3.924 on 401-416) scores 3.266 m (90 legal); elite2 champion (arena 3.936) 3.177 m on 80 fresh+arena seeds (69 legal; 5 landed short, 6 fouled). Elite2: a +0.04 m check mark alone lifts it to 3.369 (74 legal); the plant latch changes nothing there (no scuffs).

## 2026-09-29 04:05 ARENA: p95 robust trials

Package C0 = params/long_jump_p95_pn1.txt: take-off params/out/long_jump_run/p95pn_ik.txt (penultimate-touchdown ik program) + ik_fmin 1.5 + land_p95pn3 landing + il_tg 0.61 / il_zl 0.4439 + check mark +0.05 (j_board_shift 1.06, ik_gap0 2.0188, task long_jump_p95g), controller bin/challengers/long_jump_run-b20p.
- long_jump_p95_robust (16 arena starts): 3.924 -> 4.6305 (+0.706, p 0.000, 16/16 legal, diffs +0.32..+1.43): PROMOTED.
- long_jump_p95_robust32 (NEW trial, 32 fresh starts 9001-9032, seeded with the old champion: 3.4445): 4.546 (31/32 legal; 9009 fails), +1.10, p 0.000: PROMOTED.
- Fresh 96 (7001-7096): 87 legal, mean 4.231 (6 somersault, 3 fell-in-run); old champion 3.266 there.
Feedback variants (F_ham pitch feedback, swing-lag feedback) trade weak take-offs for forward-rotating ones; not used in C0. Landing reflex search (landingfb) running: 13 -> 8 roll-overs of the 56 hardest hand-overs, held-out 5 -> 4 of 75.

## 2026-09-29 04:50 ARENA summary and the pn2 package

- long_jump_p95_robust96 (NEW trial, 96 fresh starts 9033-9128, seeded with pn1: 4.0838): pn2 (params/long_jump_p95_pn2.txt = pn1 + swing-foot LAG feedback: kf on free-leg hamstrings +5, free shoulder flexors -5, plant ankle plantar-flexor -5, plant hip extensor -5, plant toe -5; ik_fbmax 0.15; found by greedy forward selection in the harness on 119 mined approaches, penalties L <= -1.5, pitch <= 0.25, vz >= 2.55) 4.3173, +0.2335, p 0.003: PROMOTED. On the other 96 fresh starts (7001-7096): pn1 4.231 (87 legal), pn2 4.476 (92 legal). On the arena 16: pn2 4.376 (15/16), pn1 4.630 (16/16); on fresh 32: 4.555 vs 4.546. The 16-start trials keep pn1.
- long_jump_elite2_robust32 (NEW, fresh 32): 3.0105 -> 3.5915 (+0.581, p 0.001) with a gentle run-up steering (j_st_w 0.3; 0.6 makes the runner fall, 0.2-0.3 lifts the fresh mean ~0.3 m) and the check mark +0.04 m (long_jump_elite2b): PROMOTED. On the 16 arena starts it scores 3.68 < 3.936 (not promoted): the champion's 16 fixed starts are all legal by luck.
- Harness vs full rollout: not exact (take-off vx, vz differ by 0.2-0.4 m/s per start for base AND feedback programs, e.g. 9034 vz 2.85 vs 2.59); use the harness to screen, full rollouts to decide.
- Roll-over rates on fresh starts (somersaults / starts): old champion 2/96; pn1 6/96 (7xxx) + 9/96 (9xxx) + 1/48; pn2 2/96 + 5/96 + 2/48. The pn family lands 4.3-4.6 m but rolls over on 4-7% of fresh starts; the old champion's 3.3-3.4 m rolls over on 2%.

## 2026-09-29 04:45 single start: 4.895 -> 4.958 -> 5.100 -> 5.122 m

long_jump_p95 promoted three times with landing programs learned for the nominal start's hand-over (land_p95k3.txt gen 20 = 4.958; land_p95k3b gen 80 = 5.100, params/long_jump_p95_ik10.txt, -b20s; gen 90 = 5.122, params/long_jump_p95_ik11.txt, -b20t). The mark is the left foot; the jumper tumbles in the pit but no rule is broken. Overfit to one start by construction (5 hand-overs); resume file out/long_jump_limits/land_p95k3b.txt (search stopped at gen 90 to stay within 2 searches at a time).
Other results today: average body (p50) champion on 48 fresh+arena starts 1.86 (3 fouls): no failure problem there, the body is the limit. SDK spec 90 passed 0 failed. Elite2 champion params reproduce the stored per-seed scores with skill b20 (defaults bit-identical).
Running: land_p95c1 (full-dim landing on the C1 take-off's hand-overs, marks), fbg7 (greedy: pitch feedback with a 15/rad penalty on take-off pitch > 0.2, init fbg6).

## 2026-09-29 05:30 v4 family started (sprint_top_speed_v4_p95 promoted: 7.00 m/s peak, 10/12)

- Runner through the long jump skill (j_run 1, task long_jump_v4_p95): 6.39 m/s at 37.5 m, 6.66 at 45, 6.84 at 55 (v3 p95: 6.88 at 37.5): the v4 P95 gait accelerates slower; check mark 44 m (task long_jump_v4_p95b).
- New tasks long_jump_v4_p95 / _p95b / long_jump_v4_elite2 (HumanoidV4Builder), new trials long_jump_v4_p95, _p95_robust, _elite2, _elite2_robust (env ROBOLAB_CALIB=v4), seeded with the default chunk jump (0, 0, 0, 0.45).
- Ideal-control ceiling of the v4 P95 runner from its own plant-flight state (long_jump_limits.py optimise, board 44 m, 60k evals): 4.89 m with L <= -1.5 (vx 6.14, vz 2.89, contact 0.096 s, L -9.9); unconstrained the search found 4.55 (L +9); v3 p95: 4.93.
- Pipeline on that state: capture (the same approach params as the run: v3 p95 j_* with steering off) -> optimise -> distil -> robust on the single capture (gap knots ZEROED: with one capture they are untrained noise; the first attempt with them gave 3.2 m) -> full rollout: 4.632 m official on the nominal start (ballistic 4.79, vz 2.95): long_jump_v4_p95 PROMOTED (0 -> 4.632), params/long_jump_v4_p95_ik1.txt, controller -b20v, task long_jump_v4_p95b.
- Not robust: foot placement relative to the line has sd 0.47 m on 32 fresh starts (v3 p95: 0.05) with steering 0.2 (mean -0.17, min -0.93, max +0.46): 15 of 32 foul; the run-up planner (j_st_*, j_pl_*, j_aim) is v3's and untuned for the crouched high-cadence gait. Ballistic distance from the board on the legal starts is fine (eff 4.17 mean). Next: practice the planner params with long_jump_run_practice.py (official score, robust seeds), then a landing table and a robust take-off as for v3.

## 2026-09-29 05:55 v4 robust (provisional) and wrap-up state

- Planner practice for the v4 P95 jump (14 tunables j_aim, j_win, j_st_*, j_pn_*, j_fin_*, j_leg_len; official score; 12 starts; out/long_jump_run/v4plan_*): objective plateaued after 3 generations (1.35); gen-9 params: fresh-32 2.85 (25 legal, legal mean 3.65), foot 0.66 m behind the line on average, sd 0.52. Stopped. Entered as params/long_jump_v4_p95_ik2.txt (-b20w): long_jump_v4_p95_robust32 (new) 0 -> 2.851, long_jump_v4_p95_robust 0 -> 2.145, both promoted against the failing baselines; labelled provisional.
- Needed for a real v4 family: `robust` over many captured v4 approaches (gap knots), a landing table on many hand-overs (a single-start table is running: land_v4q), a planner that places the foot (the v3 planner has sd 0.05, this gait 0.5).

## 2026-09-29 05:50 ARENA: long_jump_v4_p95 (one start) 4.632 -> 4.901 m (promoted)

params/long_jump_v4_p95_ik3.txt = params/long_jump_v4_p95_ik1.txt (the take-off program distilled from the v4 P95 runner's own plant-flight state) + the gen-30 snapshot of the single-start landing search land_v4q (out/long_jump_limits/land_v4q.txt: 34 knots at 0.08 s, 1 hand-over of the nominal start + execution-noise variants of it, il_tg 0.645), controller bin/challengers/long_jump_run-b20x, task long_jump_v4_p95b (44.0 m check mark). Full rollout: official 4.901 m, effective 5.004, vx 5.955, vz 2.947, flight 0.819 s, no somersault, no foul (foot 0.071 m behind the line). The mark is the PELVIS (the jumper lands on the feet and sits down behind them; nearest_mark_by 'pelvis'); the first promotion note said "feet" and was corrected in champions.json / history.jsonl under arena.locked(). Video out/long_jump_v5_v4p95.*. ORACLE-class and one start by construction (open-loop landing table); not a robust v4 result: the v4 family still fouls or lands short on fresh starts (foot placement sd 0.5 m).
Stale waiters (fb1 greedy, v4 planner practice) were stopped; only land_v4q is left running.

## 2026-09-29 06:00 ARENA: long_jump_v4_p95 (one start) 4.901 -> 4.945 m (promoted), search stopped

params/long_jump_v4_p95_ik5.txt = params/long_jump_v4_p95_ik1.txt + the generation-50 snapshot of land_v4q (out/long_jump_limits/land_v4q_g50.txt; harness best 4.905 / mean 4.919 / min 4.872 over the 5 hand-overs, 6750 simulations; gen 40 = 4.935 in a full rollout, gen 30 = 4.901). Full rollout: official 4.945 m (effective 5.048 from the take-off foot, which is 0.103 m behind the line), flight 0.812 s, pelvis marks, no somersault. Video out/long_jump_v5_v4p95.*. The search (PID 54452) was stopped by me; no long-jump job of mine is running.
Note on the earlier README wording: "feet 0.1 m farther" for the v4 one-start mark was a misreading of effective (from the take-off foot) against official (from the line); removed.
Final checks: arena.py recheck of long_jump_p95 (5.1220), long_jump_v4_p95 (4.9010 at the time), long_jump_p95_robust (4.6305), long_jump_elite2_robust (3.9358): all OK, no drift; SDK spec 90 passed, 0 failed; bin/robolab_long_jump_run is byte-identical to the frozen b20 (and b20x).
v4 params files: params/long_jump_v4_p95_ik1.txt (take-off only, 4.632 with the chunk landing), _ik2 (planner practice, robust provisional), _ik3 (+ landing gen 30, 4.901), _ik4 (+ gen 40, 4.935; not entered), _ik5 (+ gen 50, 4.945, champion). Landing snapshots out/long_jump_limits/land_v4q_g50.txt (and _g40; the gen-30 copy is scratchpad/lj/land_v4q_g30.txt).
Not done in round 2 (see the README "What is next"): a robust stage over the 159 mined elite2 plant-flight states (e2m) with gap knots and a landing table on their hand-overs (the elite2_robust 16-start champion of 28 Sep, 3.936, stands); a v4 family that places the take-off foot within 0.05 m of the line; a faster run-up (7.3 m/s for 5.5 m).
