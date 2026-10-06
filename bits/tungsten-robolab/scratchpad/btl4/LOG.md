# Dribble through the legs, round 4: the right return and the left second stroke (agent D3, 3 Oct 2026 onward)

Brief: `scratchpad/btl4/BRIEF.md`. Commands run from `bits/tungsten-robolab`. Big files in `out/btl4/` (git-ignored), params in
`scratchpad/btl4/params/`, tools in `scratchpad/btl4/`. All table-driven numbers below are ORACLE-class (open-loop tables that bypass
the reflex layer, plus a servo around them) unless a line says otherwise.

## Rules fixed before anything runs (copied from the brief)

- Metric: `btl_streak` (longest run of good passes in 15 s, task `playground/tasks/dribble_btl.py`), mean over starts, plus per-pass rates (`scratchpad/btl2/chain.py`).
- Seeds (new, nobody used them): SELECTION 10001-10128 (128 starts, every choice between candidates), CONFIRMATION 12001-12128 (check every candidate I intend to keep
  BEFORE adopting it), TEST C 11001-11064 and TEST D 11065-11128 (NOT run before the final candidate is fixed; each ONCE for the final candidate and ONCE for the baseline
  btl3-e + final_e.txt; if I look earlier I say so here).
- BASELINE = `bin/challengers/btl3-e` + `scratchpad/btl3/params/final_e.txt` (D2's candidate). Identity: it must reproduce D2's champion numbers (`arena.py recheck dribble_btl_streak_25` 2.72).
- PASS RULE: mean `btl_streak` >= 2.7 on TEST C and on TEST D each AND a paired improvement >= +0.35 over btl3-e + final_e.txt on the pooled 128 test starts (sign-flip p < 0.05).
  Stretch: mean >= 3.2, or a streak >= 4 on at least a third of the starts. An intermediate gain is a result.
- STOP RULE: if after about five hours of compute the selection-set mean is not >= +0.25 above btl3-e's on the same seeds AND confirmed on the confirmation set, stop and report what limits it.
- New skill keys are opt-in and neutral by default; btl3-e's params must replay bit-identically through the new build on seeds 601, 705, 716 (`scratchpad/btl/identity.py`) and the chain
  on 901-932 must still give what btl3-e gives.
- LESSON of D2: a first selection-set gain of +0.33 was mostly luck plus max-of-8 selection (+0.02..+0.06 on a second set): ALWAYS confirm on a second fresh set before believing a gain.
- Promote an arena champion only through `playground/arena.py eval <trial> --params ... --controller ... --task dribble_btl_v3 --promote` on the four dribble trials
  (`dribble_btl_streak_fresh32`, `dribble_btl_streak_25`, `dribble_btl_25`, `dribble_btl`) and only if it WINS by the arena's paired test; never hand-edit `champions.json` / `trials.json`.
  Freeze binaries as `bin/challengers/btl4-<tag>` before evaluating (evaluate the COPY); never change `btl2-b1..b12`, `btl3-*`, `pgP0LRz2.txt`, `final_e.txt`, A4's files or any champion.
- Machine: 18 cores shared; at most 6 rollout workers, `nice -n 10`; never kill processes that are not mine; no git state changes.
- Stall rule: no Bash call over 3 minutes; long jobs go in the background with log + pid files in `out/btl4/`.
- The host suspends at night: a clock jump on wake gets a CLOCK NOTE here (not a fault).

## Milestones

- [x] M1 baseline: btl3-e + final_e.txt on selection 10001-10128 (15 s): mean streak 2.555 and per-pass rates; identity check (`arena.py recheck dribble_btl_streak_25` 2.72: OK)
- [x] M2 opt-in keys built (energy blocks, reflex recover time, aim offsets, cock offsets, leg clearance, ...): only the leg clearance paid
- [x] M2b identity: bit-identical on 601 / 705 / 716 for every build, chain 901-932 identical (32 of 32 ties)
- [x] Selection-set decision vs the stop rule: +0.188 selection, +0.172 confirmation: the +0.25 margin is NOT reached (intermediate gain)
- [x] TEST C / TEST D (once each, final candidate and baseline): +0.062 / +0.172, pooled +0.117 (p 0.001); PASS RULE NOT MET
- [x] Arena: dribble_btl_streak_fresh32 promoted (+0.19, p 0.014), the other three not beaten; FINAL STATE below

## Log

- 17:39 START. Read BRIEF, btl3 BRIEF + LOG, btl2 LOG in full. Machine load 2.5 (5-min 5.3).
- 17:41 M1 BASELINE (btl3-e sha1 4c3cc60a... = `bin/robolab_dribble_btl` as it stands, + `scratchpad/btl3/params/final_e.txt`; SELECTION 10001-10128, 15 s, `chain.py`, 6 workers, log `out/btl4/base_sel.log`,
  per-start streaks `out/btl4/base_sel.streaks`, ORACLE-class: tables + servo): mean btl_streak **2.555** (streak 0 x2, 1 x19, 2 x36, 3 x49, 4 x21, 5 x1; >=1 126, >=2 107, >=3 71, >=4 22);
  per pass 1: 125/128 (98 %), 2: 107/127 (84 %), 3: 72/112 (64 %; bounces_or_wrong_hand 31, body 6, lost_after 3), 4: 23/81 (28 %), 5: 2/29 (7 %).
  THE NUMBER TO BEAT ON THE SELECTION SEEDS: 2.555 (stop rule: >= 2.805 after ~5 h and confirmed on 12001-12128). It reproduces D2 (2.50 on 128 test starts, 2.41 on 9001-9128).
  IDENTITY: `arena.py recheck dribble_btl_streak_25` (log `out/btl4/recheck_streak25.log`): stored 2.7200, now 2.7200 OK (the champion btl3-e + final_e reproduces through the arena's own path).
- 17:56 FIRST DIAGNOSIS (live traces of the baseline on the selection set, `out/btl4/live_base`, tools `scratchpad/btl4/an_stage2.py`, `an_stage3.py`):
  RIGHT RETURN (stage 2, n 109 with a trigger): ok 72 (66 %), body 19 (17 %: first contact the lead thigh / right thigh), no receive 13 (12 %, arrival beyond the left hand's reach y 0.44), no gate 2, lost after 3.
  By the incoming apex quintile (apex of the left return's rise): ok 6/22, 15/22, 18/21, 18/22, 15/22: the lowest quintile (apex < 0.648, 20 % of starts) succeeds 27 % (body 9, no receive 5) against 76 % elsewhere.
  Successful strokes: release (-1.84, 1.91, -3.51) sd (0.23, 0.16, 0.28), bounce (0.233, -0.022) sd (0.03, 0.035), arrival (-0.106, 0.326) sd (0.053, 0.041); body-hit strokes: release (-1.52, 1.58, -2.96) sd (0.32, 0.44, 0.86),
  bounce (0.238, -0.11) sd (0.12, 0.10), incoming crossing (0.429, -0.307) sd (0.109, 0.084) against ok (0.441, -0.255) sd (0.044, 0.042): the failures are scattered strokes from atypical incoming balls (corr(ok, incoming vy) +0.40, vz +0.39, vx +0.34, apex +0.31, y +0.38).
  LEFT SECOND STROKE (stage 3, A4's reflex x_* chunks): the left hand's x_recover (t_rec 0.265 s) starts at the right hand's release (the handoff); the strike latch (arrival < bl_lead 0.2146) has ALREADY fired when x_recover ends in 97 % of the starts
  (x_wait 6 +- 4 ms), so the swing starts at the end of the recovery, 60-120 ms before the touch (mean 112 ms; 31 of 112 starts never touch: swing 160-400 ms, apex 0.31, no gate). Pass 4 ok 30 % when the swing is 60-120 ms.
- 17:57 NEW OPT-IN KEYS `bl_trec` / `bt_trec` (duration of the x_recover chunk of a REFLEX-driven pass stroke, i.e. not a programmed stage; default t_rec): skill edit + build `bin/challengers/btl4-a` (sha1 c65b81d7...);
  identity: btl3-e vs btl4-a with final_e.txt bit-identical on seeds 601, 705, 716 (8 s). SCAN (selection 10001-10128, 6 s, baseline 2.555): bl_trec 0.20 / 0.15 / 0.12 / 0.09 / 0.06 -> 2.430 / 2.383 / 2.359 / 2.008 / 2.000
  (paired -0.125 / -0.172 / -0.195 / -0.547 / -0.555): pass 4 collapses 23/81 -> 5/82 -> 0/83: an EARLIER swing is worse. The reflex swing is tuned to start late (the swing's burst has to meet the ball), so the late start is not the fault: NEGATIVE RESULT (log `out/btl4/pool_trec1.log`).
- 18:00 SEED NOTE: D2's log says its dither identification of the right return used seeds 10001-10400 (a linear model that was NOT adopted, R^2 <= 0). So my selection seeds 10001-10128 are not 100 % virgin (no choice between candidates was ever made on them);
  the confirmation set 12001-12128 and TEST C / D 11001-11128 are untouched. All fits below use TRAINING seeds 13001-13840 (new), never the selection, confirmation or test seeds.
- 18:05-18:15 REPLAY TOOLS (`scratchpad/btl4/rlib.py`, `rec_train.py`; records `out/btl4/rec/rec_<seed>.pkl`, 840 closed-loop starts 13001-13840 of btl3-e + final_e with snapshots around every stage trigger): a replay of a stage from its trigger tick with the RECORDED
  activations (table + servo) reproduces the closed-loop ball path exactly (max deviation 0.0 on stages 1 and 2) in 0.016 s; additive offsets on the recorded activations = the table's change with the servo's contribution held fixed.
- 18:10 FEED-FORWARD LINEAR OUTCOME CORRECTION (replay, stage 2, `ffc1.py`, `ffc2.py`, smooth outcomes = pre-bounce velocity, extrapolated bounce position, 6 knots x 16 muscles offsets, delta 0.02): the outcome deviation is predictable from the 18 trigger features
  (held-out R^2: vz .77, bx .60, vx .39, by .30, vy .24), but the response of the outcomes to offsets is linear only below |offset| ~0.02: with mean sensitivities the corrected replays gain +4..6 of 89 proxy-ok starts; with PER-START sensitivities and perfect knowledge of the deviation
  (upper bound) the replayed outcome sd does not follow the linear prediction for |da| >= 0.03 (vx, vy -40 % at |da| 0.019, vz unchanged): outcome-directed linear control is not worth building (consistent with D2's identification failure). NEGATIVE.
- 18:15 REFLEX CMA of the left second stroke (practice, 14 bl_* keys, catch4 objective on training seeds 13001-13096): started 18:15, killed by me at 18:22 after generation 1 (CPU needed for the table fits; may be relaunched if time permits; no params produced).
- 18:20 THE DOMINANT SYSTEMATIC FAILURE SOURCE: INCOMING BALL ENERGY (`an_feat.py`, `fit_v.py --dry`, 840 training starts). Closed-loop pass success by decile of the predicted vertical speed vz_c at the ball's crossing of z 0.62 at the stage trigger:
  stage 1 (left return): 42 % / 71 % / 86 % / 94 % / 93 % / 96 % ... for the lowest decile(s) (vz_c < 1.39 / 1.51 / 1.57 / 1.61 ...) then 93-96 %; stage 2 (right return): 7 % / 19 % / 38 % / 62 % / 62 % / 68 % / 77 % / 65 % (vz_c < 0.64 / 1.01 / 1.15 / 1.23 / 1.30 / 1.36 / 1.51);
  stage 3: 0-2 % for the lowest two quintiles. Energy along the chain (vz_c at the stage triggers, sd in brackets): stage 0 2.23 (0.08), stage 1 1.64 (0.16), stage 2 1.22 (0.42), stage 3 0.97 (0.69): the energy decays and its scatter is amplified by the left return (0.16 -> 0.42).
  None of the tables has an energy feature (D2's apex shift moved the schedule position / clock linearly and did not help). New opt-in skill keys `pg_vn`, `pgvk<p>`, `pgvs<p>`, `pgv<p>_<m>_<k>`: a hinge feature uv = clip((knee - vz_c)/scale, 0, 2.5) times a block added to the table's knots; build `bin/challengers/btl4-b`, identity vs btl3-e with final_e bit-identical on 601 / 705 / 716 (8 s).
  Fit (`fit_v.py`: sep-CMA over the 272-dim block in the replay on the active starts, objective = failure-aware J of the replay summary; train / validation split of the active starts): stage 2 first (knee 1.35, scale 0.3, 491 of 840 starts active).
- 18:40 STAGE-2 ENERGY BLOCK (fit v2b: knee 1.35, scale 0.3, 491 active starts, 200 generations, replay objective J 4.37 -> 3.38 train, 6.00 -> 4.81 validation, but the proxy-ok count did not rise: 164 -> 135 train, 48 -> 49 validation): closed loop on the selection set
  (btl4-b + `scratchpad/btl4/params/v2b.txt`, 6 s): 2.516 against 2.555 (paired -0.039, se 0.041): NO GAIN (p3 69/112 vs 72/112, p4 21/79 vs 23/81). NEGATIVE: low incoming energy is a MARKER of a bad left return (atypical direction too: incoming vx, vy correlate with success),
  not something a block linear in vz_c can repair at the right hand. (Value functions of the delivered state, `valfn.py`: stage 2 success given the ball state at its trigger has held-out AUC only 0.74-0.77, stage 3 0.67-0.70: even a perfect delivery caps p3 near 0.75.)
- 18:46 AIM SCAN of the left second stroke (selection, 6 s; bl_ax 0.17 -> 0.10 / 0.14 / 0.21 / 0.25, bl_ay 0.27 -> 0.20 / 0.24 / 0.30 / 0.34): paired -0.07 / -0.09 / +0.05 / -0.09 / -0.13 / -0.11 / -0.01 / -0.03 (se 0.06-0.07), pass 4 swings 14..32 of ~80:
  bl_ax / bl_ay also move the left arm's pre-stage-1 posture (the meeting correction's palm tilt uses the aim), so they are NOT post-trigger-only: the upstream re-randomises (the system is chaotic: effects under ~0.1 need >= 500 starts to see). No gain; the baseline aim is at a local optimum.
  Clean (post-trigger-only) stage-3 knobs are bl_angl, bl_dzl, bl_sweep, bl_drv, bl_trec, t_push, t_carry, push_ease (they only shape the reflex swing / carry chunks).
- 18:50 STAGE-1 ENERGY BLOCK (fit v1a: knee 1.57, scale 0.12, 251 active starts = 30 %; objective with apex >= 0.72 (8 per m) and arrival vz >= 1.4 (3 per m)): J 4.99 -> 1.6 train, 4.23 -> 1.5 validation; proxy ok 85 -> 85 / 43 -> 41: it raises the delivered energy.
- 19:00 STAGE-1 ENERGY BLOCK closed loop (btl4-b + `params/v1a.txt`, selection 6 s): 2.586 against 2.555 (paired +0.031, se 0.048): no gain (p2 108/127, p3 76/121, p4 22/87). NEGATIVE.
- 19:03 RESET DRIBBLES (modes 7-9, `pool_mode8.log`, 15 s): `mode=8` (B B D: the right hand catches the left return and dribbles) with the tables for passes 0-1: pass 2 collapses to 16/127 (mean 1.10): the reflex catch-and-dribble of A4 cannot take the table-driven left return. The D-reset idea needs its own fitted stroke: out of reach. NEGATIVE.
- 19:07 JOINT RECOVER / LATCH SCAN of the left second stroke (`pool_trlead.log`; bl_trec 0.12 / 0.18 x bl_lead 0.07 / 0.09 / 0.11 / 0.13; clean, post-trigger only): mean 2.42 / 2.53 / 2.50 / 2.50 (trec 0.12) and 2.42 / 2.53 / 2.51 / 2.51 (trec 0.18) against 2.555: flat, p4 17-25 of ~80
  (lead 0.07: the latch decides the start and is too late: 17/80); the swing timing of the left second stroke is on a plateau. NEGATIVE.
- 19:10 STAGE-3 CMA (clean reflex keys bl_angl, bl_dzl, bl_sweep, bl_drv, bl_trec, bl_lead, t_push, t_carry, push_ease; objective catch4 on the 128 training starts whose pass 3 is ok): started 19:10, PAUSED (SIGSTOP of my own pids, `out/btl4/cma3.pids`) at 19:13 after generation 0 for the leg scans; resumed later if time permits.
- 19:12 NEW OPT-IN KEYS `ll_hip / ll_knee / ll_abd / lb_hip / lb_abd / lb_knee`, `ll_from`, `ll_n`, `ll_t0`, `ll_win`, `ll_ramp` (LEG CLEARANCE): after the release of passes ll_from .. ll_from + ll_n - 1 (default 3, 4: the right return and the left second stroke) the lead (and back) leg's hip / knee are shifted (contraction offsets, ramped,
  window 0.55 s after the release). Rationale: the body-hit failures (stage 2: 17 % of the right returns, mostly the lead thigh; pass 4: 13 %) are the ball clipping the thigh's underside at x 0..0.2, z 0.4-0.5 right after its bounce. Builds btl4-c (hip / knee) and btl4-d (+ abduction, back leg);
  identity vs btl3-e with final_e bit-identical on 601 / 705 / 716 (8 s), and the btl4-c reference chain on the 128 selection starts gives 2.555 with the same per-pass counts as btl3-e.
- 19:15 LEAD HIP FLEXION SCAN (selection 10001-10128, 6 s, clean: upstream stages identical; baseline 2.555): ll_hip +0.08 -> 2.641 (+0.086, se 0.047; p3 77/112, p4 29/84), +0.15 -> 2.633 (+0.078), +0.25 -> 2.656 (+0.102, se 0.051; p3 75, p4 32/86),
  -0.12 (the other direction) -> 2.539 (-0.016), +0.15 with knee +0.2 -> 2.648 (+0.094): a monotone dose response in the physically expected direction, about +5 points of pass 3 and +6-9 points of pass 4. FIRST POSITIVE LEAD; to be confirmed on 12001-12128 and a larger pooled set.
- 19:30 LEG CLEARANCE, POOLED 256 (selection 10001-10128 + training seeds 13001-13128, 6 s, paired SE ~0.027; baseline 2.531; the two halves agree): ll_hip 0.25 + ll_abd 0.10: 2.672 (+0.141; p3 136/225 -> 149, p4 49/160 -> 70/165);
  ll_hip 0.35 + ll_abd 0.10: 2.676 (+0.145; p4 72/166); ll_hip 0.40 + ll_abd 0.15: +0.133 (saturated); + ll_knee 0.3: +0.090 (worse); + lb_hip 0.15 (back leg hip): 2.684 (+0.152; p4 75/167); ll_win 0.8: identical to 0.55 (the next release ends the window);
  lb_abd +0.10 (back leg outward): +0.023 (worse); ll_abd -0.10: +0.047 (worse than +0.10: outward is right); ll_from 2 (the lift also covers the right return's STROKE): -0.125 (p3 107/236: the stage-2 table was fitted with the leg down); ll_from 1: -0.691 (the chain breaks).
  So the lift must start at the RELEASE of the right return (pass_no 3) and not before. The effect is physical: the lead thigh (and the gate) clear for the ball, p3 +6 points (66 %), p4 +12-14 points (31 -> 43-45 %).
- 19:33 CONFIRMATION of the leg clearance (confirmation set 12001-12128, 15 s, btl4-d): baseline btl3-e + final_e 2.547 (p3 68/116, p4 21/84); ll_hip 0.35 + ll_abd 0.10: **2.703, paired +0.156 (se 0.045)** (p3 79/116, p4 32/90);
  the same with lb_hip 0.15: 2.695 (+0.148). The gain reproduces on three independent sets (selection +0.133, training 13001-13128 +0.148, confirmation +0.156). The back leg adds nothing (dropped).
- 19:34 BODY-CONTACT CENSUS (`body_by_pass.py`, selection, 8 s; first non-hand contact per start by the pass whose flight it is; baseline -> lift): pass 3 (the right return) l_thigh 16 -> 9, l_shin 3 -> 3, r_forearm 10 -> 10, r_thigh 2 -> 2;
  pass 4 (the left second stroke) l_thigh 22 -> 12, l_shin 8 -> 4, r_thigh 10 -> 8, pelvis 2 -> 1; pass outcomes (given the previous pass ok): pass 3 ok 72 -> 77 of 107 (body 17 -> 10), pass 4 ok 22 -> 36 of ~75 (no gate 23 -> 15, body 12 -> 13, gate ok then fail 13 -> 9).
  The lift both clears the thigh and widens the gate (the lead leg's axis moves out and forward), so strokes that went down the lead leg's outer side now count as crossing between the legs.
- 19:45 PER-WINDOW SCAN (pooled 256, 6 s, base leg_a = hip 0.35 / abd 0.10 in both windows, paired se 0.01-0.02 because it is clean): window 2 (the left second stroke's flight, pass 4) hip 0.40 / abd 0.20: +0.023; 0.40 / 0.30: +0.027; hip 0.20 / abd 0.10: -0.023; hip rotation +-0.2 (window 2): +0.012 / +0.004; ll_rot +-0.2 (both windows): 0.000.
  Saturated near hip 0.35-0.40, abd 0.10 (pass 3) / 0.30 (pass 4). `params/leg_b.txt` = final_e + (ll_hip 0.35, ll_abd 0.10, ll_two 1, ll_hip1 0.40, ll_abd1 0.30).
- 19:50 CLEAN AIM OFFSETS on top of leg_b (`bl_dax / bl_day / bt_dax / bt_day`: aim offsets of the reflex strokes after the tables; pooled 256, 6 s; leg_b alone 2.703 = +0.172 over btl3-e's 2.531): bl_dax +0.06 / -0.06: +0.016 / -0.016 (se 0.021), bl_day +0.06 / -0.06: -0.008 / -0.059,
  bt_dax / bt_day +-0.06: 0.000..+0.004: the aim of the later strokes is at its optimum (flat); no change adopted.
- 19:55 BODY-HIT SOURCES OF THE LEFT RETURN (`body_hits2.py`, stage 1, selection baseline): 17 of 128 left returns (13 %) clip the lead thigh (9) or shin (6) in flight, 0.15-0.3 s after the release.
  A second clearance window for that flight (`l2_*` keys, builds btl4-g) fixes some of them (p2 214/255 -> 217-225 of 255) but DISTURBS THE RIGHT RETURN'S STROKE (the table of stage 2 starts only ~0.15 s after the left release and is fitted with the legs still):
  pooled 256 paired -0.18 .. -0.40 for every window (hip 0.15-0.40, abd 0.10-0.30, win 0.25-0.35; the 0.40 / 0.30 lift is the least harmful: p3 122/236). Any leg motion during a table stroke breaks it; the lift works because it starts AFTER the right return's release. NEGATIVE (l2 keys stay neutral).
- 20:07 TRUNK OFFSETS in the same windows (`lt_rot / lt_flex / lt_lat`, build btl4-h; identity bit-identical): scan started 20:09 (the stage-3 reflex CMA `cma4` is paused during scans, `out/btl4/cma4.pids`).
- 20:12 TRUNK OFFSETS (lt_rot +0.10 / -0.10 in the pass 3-4 windows, pooled 256 on leg_b 2.703): 2.504 / 2.602 (paired -0.199 / -0.102; p4 31 / 55 of ~165 against 75): the left second stroke is tuned to the lunge's twist, any trunk offset hurts; lt_flex / lt_lat not run. NEGATIVE.
- 20:16 STATIC LEAD LEG OFFSET FROM THE START (`ls_*`, build btl4-i; pooled 256 on final_e, 2.531): ls_hip 0.15 -> 1.266 (p1 212/256, p2 85/244), 0.25 -> 1.020: the stance is tuned to the millimetre (all tables were fitted with these legs): any STATIC change breaks the chain;
  only the DYNAMIC lift after the right return's release works. NEGATIVE (ls keys stay neutral); scan stopped after two configs.
- 20:20 STAGE-2 AIM RE-TUNE WITH THE LIFT ON (512 starts: selection + training 13001-13384, 6 s; leg_b 2.758): pgc2y -0.005 / -0.010: -0.084 / -0.184 (se 0.026 / 0.034); pgc2y +0.005: -0.086; pgc2x +0.005 / -0.005: -0.043 / -0.098: every neighbour is worse (a sharp optimum, 0.5 cm of schedule aim = 2 cm of arrival).
  The aim stays at D2's value.
- 20:30 STAGE-3 REFLEX CMA (cma4 on leg_b, 11 clean keys): paused and resumed three times for scans; after 3 generations best 17.992 against the start's 17.953 (noise level, ~7 min per generation): KILLED at 20:34; replaced by coordinate scans of the clean keys (cheaper).
- 20:40 BACK-LEG WINDOW-2 KEYS (lb_hip1 / lb_abd1 / lb_knee1, build btl4-j) AND LONGER WINDOWS on leg_b (pooled 256, paired se 0.004-0.017): lb_hip1 0.20: -0.004; lb_abd1 +0.10: +0.012; lb_abd1 -0.10: 0.000; both: +0.016; ll_n 3: +0.004: nothing worth adopting.
- 20:44 CLEAN LEFT-REFLEX KEYS ON TOP OF THE LIFT (pooled 256, leg_b 2.703): bl_sweep 0.19 / 0.27 (base 0.232): -0.078 / -0.051; bl_angl 1.15: -0.055 (the rest of the scan was stopped): the left reflex stroke sits on a sharp optimum of its clean keys (as D2 found); the stage-3 reflex CMA is dropped.
- 20:47 REMAINING STAGE-2 BODY FAILURES WITH THE LIFT (`body_hits2.py` on 128 selection starts, 12 body failures after the release): r_thigh 8, l_thigh 4: the back (right) thigh near the hip (x -0.13..0.05, z 0.24-0.5) is now the main obstacle of the right return;
  those are strokes that bounce toward the back leg (bounce y -0.1..-0.17), i.e. bad strokes; a back-leg window-1 raise is being scanned (lb_hip / lb_abd in the pass-3 window).
- 20:52 CANDIDATE FIXED (before any TEST run): controller `bin/challengers/btl4-final` (= btl4-j, sha1 b7a014b5..., built from the current `lib/robolab/skills/dribble_btl.w`) with `scratchpad/btl4/params/final_f.txt` = final_e + lead-leg clearance
  (`ll_hip 0.35, ll_abd 0.10` after the release of pass 3, `ll_two 1, ll_hip1 0.40, ll_abd1 0.30` after the release of pass 4; windows 0.55 s, ramp 0.08 s). ORACLE-class as before (tables + servo; the legs are open-loop offsets).
  IDENTITY: btl3-e + final_e.txt replays bit-identically through every build btl4-a .. btl4-j on seeds 601 / 705 / 716 (8 s), and the chain on 901-932 (15 s) gives the IDENTICAL per-start streaks for btl3-e and btl4-final with final_e.txt (mean 2.625 both, 32 of 32 ties).
  SELECTION 10001-10128 (15 s): baseline 2.555 -> candidate **2.742**, paired **+0.188** (se 0.044, sign-flip p 0.0001; better on 28, worse on 5, ties 95); passes 1-5 ok 98 / 84 / 69 / 48 / 7 % (baseline 98 / 84 / 64 / 28 / 7).
  CONFIRMATION 12001-12128 (15 s, a second fresh set): baseline 2.547 -> candidate **2.719**, paired **+0.172** (se 0.043, p 0.0001; better on 26, worse on 5); passes 98 / 85 / 67 / 39 / 0 % (baseline: p3 68/116, p4 21/84).
  The stop rule asks for +0.25 on selection AND confirmation: NOT reached (+0.19 / +0.17): an intermediate gain, reported as one. TEST C / TEST D (64 starts each) started 20:58, candidate and baseline once each.
- 20:56 TEST C / TEST D (each run ONCE for the final candidate btl4-final + final_f.txt and ONCE for the baseline btl3-e + final_e.txt; 15 s; first look at these seeds):
  TEST C 11001-11064: baseline 2.562 -> candidate 2.625, paired +0.062 (se 0.049, sign-flip p 0.17; better on 7, worse on 3, ties 54; passes 1-4 ok 61/55/37/11 -> 61/55/35/17 of 64/64/55/43);
  TEST D 11065-11128: baseline 2.531 -> candidate **2.703**, paired **+0.172** (se 0.052, p 0.0017; better on 12, worse on 1; passes 63/58/33/8 -> 63/58/36/14);
  POOLED C + D (128): baseline 2.547 -> candidate **2.664**, paired **+0.117** (se 0.036, sign-flip p 0.0012; better on 19, worse on 4, ties 105).
  PASS RULE NOT MET: mean >= 2.7 holds on TEST D only (2.703; TEST C 2.625), and the pooled paired gain is +0.117 against the required +0.35. The gain is real (p 0.001 on the test sets, p 0.0001 on selection and confirmation) but small:
  an INTERMEDIATE RESULT. Across all fresh sets the effect is +0.17 / +0.19 (confirmation / selection), +0.12 (TEST), +0.145 (training seeds, 6 s): about +0.15.
- 20:57 PASS 5 (the right hand's second reflex stroke): 0 of 36 passes ok when pass 4 was ok (live traces with the lift: gate ok then the left hand fails 14, no gate 14, body 7): the chain of streak-4 starts always ends there; that stroke is A4's reflex with apex 0.45 / vh 1.5.
- 20:57 ARENA (`arena.py eval <trial> --params scratchpad/btl4/params/final_f.txt --controller bin/challengers/btl4-final --task dribble_btl_v3 --workers 6 --promote`, one trial per call, logs `out/btl4/arena_*.log`):
  dribble_btl_streak_fresh32 (1101-1132): 2.5000 +- 0.47 vs the champion btl3-e 2.3125: +0.1875, sign-flip p 0.014 -> WON, PROMOTED (bin/champions/dribble_btl_streak_fresh32-20261003-205634; `arena.py recheck` reproduces 2.5000 exactly);
  dribble_btl_streak_25 (701-725): 2.7600 vs 2.7200: +0.04, p 0.486 -> does not beat (not promoted); dribble_btl_25 (btl_rate): 0.2520 vs 0.2560: -0.004, p 0.773 -> no; dribble_btl (10 starts): 0.2800 vs 0.2200 (btl2-b12): +0.06, p 0.133 -> no (10 seeds).
  (The arena trials are 10-32 starts: a +0.15 gain has a paired se of ~0.15-0.2 there, so only one of them reaches p < 0.05.)
- 20:59 SECOND-STROKE COCK OFFSETS (`bl_cksf / cksa / cksr / ckel / ckwf / ckwd`, `bl_ckr`, `bl_ckf`, build btl4-k, identity bit-identical): the table strokes cock differently from A4's reflex (stage-1 palm peak 0.919 m at 66 ms against 0.872 +- 0.085 at the reflex swing start;
  joint angles at the table's cock minus the reflex's: shoulder rotation +0.15, elbow +0.25, wrist flexion -0.22, wrist deviation +0.26, shoulder flexion / abduction +0.03): scanning half of those offsets during the left second stroke's recovery / wait / first 50 ms of the swing (pooled 256, 8 s).
- 21:08 COCK OFFSETS RESULT (pooled 256, 8 s, final_f 2.703): bl_ckel +0.12: -0.043; bl_ckwf -0.10: -0.016; bl_ckwd +0.12: +0.016; bl_cksr +0.08: -0.004; all four at half the table's difference: -0.016; bl_cksf +0.10 / -0.10: -0.105 / -0.051: no gain (the left reflex stroke is on a sharp optimum
  in the cock posture too). NEGATIVE (keys neutral).
- 21:09 EXTRA FRESH SET for the final numbers: seeds 14001-14256 (never used for anything), 15 s, baseline btl3-e + final_e once and candidate btl4-final + final_f once (`run_test.sh F`).
- 21:12 EXTRA FRESH SET RESULT (seeds 14001-14256, never used for anything before; 15 s, baseline once, candidate once): baseline 2.617 -> candidate **2.770**, paired **+0.152** (se 0.029, sign-flip p < 1e-4; better on 43, worse on 7, ties 206);
  passes 1-5 ok 252/228/139/50/1 of 256/256/238/170/54 -> 252/228/156/69/6 of 256/256/238/186/79 (p3 58 -> 66 %, p4 29 -> 37 %).
  ALL FRESH SETS (candidate minus baseline, 15 s): confirmation +0.172 (128 starts), TEST C +0.062 (64), TEST D +0.172 (64), extra +0.152 (256): 512 starts never used for a choice: **+0.148 +- 0.02**; selection (used to choose among leg settings) +0.188.
- 21:15 LIFT WINDOW / RAMP (pooled 256 on final_f 2.703): ll_win 0.35 / 0.42 / 0.50: -0.035 / -0.023 / +0.004; ll_ramp 0.05 / 0.12: +0.012 / 0.000; ll_t0 not run: the 0.55 s window and 0.08 s ramp stay.
- 21:25 RIGHT HAND'S CLEAN REFLEX KEYS (pass 5, pooled 256, 8 s): bt_sweep 0.20 / 0.30: 0.000 / -0.012; bt_angl 1.25: -0.004 (rest stopped): no effect (pass 5 is reached on ~30 % of the starts and succeeds on ~5 % whatever these keys say). NEGATIVE.
- 21:19 The source as it stands (header documented) builds the same binary as btl4-k (sha1 8ffcb613...); btl4-k + final_f gives identical streaks to btl4-final + final_f on the 128 selection starts (15 s): the final source and the evaluated candidate agree.

## FINAL STATE (3 Oct 2026, agent D3): an INTERMEDIATE GAIN of about +0.15, the PASS RULE IS NOT MET, the STOP RULE's +0.25 margin is NOT reached

**Candidate** (fixed 20:52, before any TEST run): controller `bin/challengers/btl4-final` (sha1 b7a014b5...; the current `lib/robolab/skills/dribble_btl.w` builds `btl4-k`, sha1 8ffcb613..., which gives identical streaks / activations under the same params,
`bin/robolab_dribble_btl` is that build) with `scratchpad/btl4/params/final_f.txt` = btl3-e's `final_e.txt` + LEAD-LEG CLEARANCE: after the release of the right return (pass 3) the lead leg's hip is flexed 0.35 rad and abducted 0.10 rad
(ramp 0.08 s, window 0.55 s), after the release of the left second stroke (pass 4) flexed 0.40 / abducted 0.30 (`ll_hip 0.35, ll_abd 0.10, ll_two 1, ll_hip1 0.40, ll_abd1 0.30`; contraction offsets on the stance track).
ORACLE-class as before (tables for the launch, the left return and the right return, the servo around them, A4's reflexes elsewhere; the legs are open-loop offsets).
Identity: btl3-e + final_e replays bit-identically through every new build on seeds 601 / 705 / 716 (8 s) and the chain on 901-932 (15 s) gives identical per-start streaks for btl3-e and btl4-final (mean 2.625, 32 of 32 ties).

| set (15 s, paired, sign-flip) | baseline btl3-e + final_e | candidate | difference |
| --- | --- | --- | --- |
| SELECTION 10001-10128 (used to choose among leg settings) | 2.555 | **2.742** | **+0.188** (se 0.044, p 0.0001) |
| CONFIRMATION 12001-12128 | 2.547 | **2.719** | **+0.172** (se 0.043, p 0.0001) |
| TEST C 11001-11064 (once each) | 2.562 | 2.625 | +0.062 (se 0.049, p 0.17) |
| TEST D 11065-11128 (once each) | 2.531 | **2.703** | **+0.172** (se 0.052, p 0.002) |
| TEST C + D pooled (128) | 2.547 | **2.664** | **+0.117** (se 0.036, p 0.0012; better on 19, worse on 4) |
| extra fresh 14001-14256 (256) | 2.617 | **2.770** | **+0.152** (se 0.029, p < 1e-4) |
| the 512 fresh starts never used for a choice (confirmation + TEST + extra) | | | **+0.148 +- 0.02** |
| arena dribble_btl_streak_fresh32 / streak_25 / btl_25 / btl (10 starts) | 2.3125 / 2.72 / 0.256 / 0.22 | 2.50 / 2.76 / 0.252 / 0.28 | +0.19 (p 0.014: PROMOTED) / +0.04 (0.49) / -0.004 (0.77) / +0.06 (0.13): not promoted |

PASS RULE: NOT MET (mean >= 2.7 on TEST D only: 2.703, TEST C 2.625; the pooled paired gain +0.117 against the required +0.35). Stretch (3.2 or a third of the starts at >= 4) not met. STOP RULE: +0.25 on selection and confirmation not reached (+0.188 / +0.172):
reported as an intermediate gain at about 3 h 50 min of the 5 h. Per pass (selection / confirmation / extra): launch 98 %, left return 84-89 %, right return 64 -> 69 / 68 -> 67 / 58 -> 66 %, left second stroke 28 -> 48 / 25 -> 39 / 29 -> 37 %, right second stroke 7 / 0 / 8 %.

**What produced the gain**: the ball that rises after a release clips the lead thigh (the right return: 17 % of the right returns, first contacts the lead thigh 16 and shin 3 of 128 starts; the left second stroke: ~13 %) or crosses outside the gate (28-32 % of the left second strokes): lifting and abducting the lead leg
AFTER the release opens the gap (the thigh's underside rises, the gate's lead end moves out): body failures of pass 3 17 -> 9 %, pass 4 `no gate` 32 -> 19 %, pass 4 ok 31 -> 46 % of its attempts (live traces, selection). Dose response: hip +0.08 / +0.15 / +0.25 / +0.35: +0.09 / +0.08 / +0.10 / +0.125 (selection), the other direction -0.016;
outward abduction helps (hip 0.25 with abd +0.10: +0.133, with -0.10: +0.047), the back leg, the knee, hip rotation, longer / shorter windows add nothing. It is clean: the stages before the release are untouched (identity), so its paired se is 0.02-0.03.

**What did NOT work** (all with numbers above; every key stays in the skill, neutral): (1) feed-forward linear outcome correction: the outcome deviation is predictable (held-out R^2 vz .77) but the outcomes respond linearly only below |offset| ~0.02 (replay, per-start sensitivities): +4..6 of 89 proxy-ok starts at best;
(2) an incoming-energy hinge block fitted in the replay for the right return (-0.04) and the left return (+0.03): low incoming energy is a marker of a bad upstream stroke, not a gain-schedulable variable (the success of the next stage given its input state has AUC only 0.74-0.77);
(3) the left second stroke's timing: an earlier swing (bl_trec 0.20 .. 0.06) collapses pass 4 (23 -> 5 -> 0 of ~80), the joint recover / latch scan, aim offsets, sweep, tilt, cock offsets, hand-key offsets are all flat or worse (a sharp optimum, D2's tuning holds);
(4) mode 8 (reset dribbles) breaks pass 2 (16 of 127); (5) ANY perturbation of a table stroke costs 0.04 .. 1.5: a static lead-leg offset (-1.3), a leg lift during the right return's stroke (-0.18 .. -0.40), trunk offsets (-0.1 .. -0.2), 0.5 cm of stage-2 aim (-0.04 .. -0.18);
(6) a joint CMA of the reflex keys was too slow (7 min / generation) and showed nothing in 3 generations; the right hand's later-stroke keys do nothing (pass 5 succeeds on ~5 %).

**What limits it now**: (a) the ENERGY decays along the chain and its scatter is amplified at the left return (predicted vertical speed at the crossing, stage 0 / 1 / 2 / 3: 2.23 (sd 0.08) / 1.64 (0.16) / 1.22 (0.42) / 0.97 (0.69) m/s); the success of a stage collapses where its input energy is low (stage 2: 7 / 19 / 38 / 62-77 % over the vz_c deciles)
and the left arm cannot add energy there (weak left returns have a 10 ms shorter contact); (b) the tables are tuned to the exact dynamics (any change before or during a table stroke re-rolls a chaotic stroke), so the 13 % of left returns that clip the lead thigh / shin 0.15-0.3 s after the release cannot be cleared by the leg (the right return's table starts ~0.15 s after the release);
(c) the two reflex strokes of the second cycle are weak (apex 0.45, release (0.5, -1.0, -1.9) m/s against the tables' (1.4, -1.7, -3.4)) and sit on sharp optima: pass 4 48 %, pass 5 ~5 %: the chain of every streak-4 start ends there. Next, in order: a table for the left second stroke fitted on the lifted-leg distribution
(the left arm is at the ready posture at its trigger when pass 3 was ok: wrist 0.81 +- 0.07, like stage 1; D's failure was the initialisation, start from the stage-1 table recentred and a hybrid start 0.1 s before the contact); a refit of the right return's table with the leg motion in the loop (opens the left-return flight clearance, +0.05);
a table for the right hand's second stroke once the left second stroke delivers more energy.

**Files**: skill `lib/robolab/skills/dribble_btl.w` (opt-in keys: `bl_trec / bt_trec`, `pg_vn / pgvk / pgvs / pgv*`, `ll_* / l2_* / ls_* / lb_* / lt_*`, `bl_dax / bl_day / bt_dax / bt_day`, `bl_ck*`, all neutral at their defaults); frozen builds `bin/challengers/btl4-a .. btl4-k`, `btl4-final`;
params `scratchpad/btl4/params/` (`final_f.txt` the candidate, `leg_a.txt`, `leg_b.txt`, `v1a.txt`, `v2b.txt`); tools `scratchpad/btl4/` (`rlib.py` replay with additive offsets, `fit_v.py`, `ffc1.py`, `ffc2.py`, `valfn.py`, `an_*.py`, `body_by_pass.py`, `scan_pool.py`, `run_test.sh`, `final_battery.sh`);
records and logs `out/btl4/` (840 closed-loop records `out/btl4/rec`, scans `pool_*.log`, TEST `test_*`, arena `arena_*.log`); arena champion `bin/champions/dribble_btl_streak_fresh32-20261003-205634` (+ `playground/arena/params/<same>.txt`, `recheck` reproduces 2.5000).
Nothing was committed or pushed. SEED NOTE: D2's dither identification (not adopted) had used 10001-10400, so the selection seeds are not 100 % virgin (no choice was ever made on them before); training seeds 13001-13840 and 14001-14256 were new.
