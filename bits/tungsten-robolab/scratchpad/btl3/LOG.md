# Dribble through the legs, round 3: a stroke with feedback (agent D2, 3 Oct 2026 onward)

Brief: `scratchpad/btl3/BRIEF.md`. Commands run from `bits/tungsten-robolab`. Big files in `out/btl3/` (git-ignored), params in
`scratchpad/btl3/params/`, tools in `scratchpad/btl3/`. All table-driven numbers below are ORACLE-class (open-loop tables that bypass
the reflex layer) unless a line says otherwise.

## Rules fixed before anything runs (copied from the brief)

- Metric: `btl_streak` (longest run of good passes in 15 s, task `playground/tasks/dribble_btl.py`), mean over starts, plus per-pass rates (`scratchpad/btl2/chain.py`).
- Seeds: SELECTION 2001-2128 (128 starts, every choice between candidates). TEST A 3001-3064, TEST B 3065-3128: NOT run before the final
  candidate is fixed; each ONCE for the final candidate and ONCE for the baseline (if I look earlier I say so here).
- PASS RULE: mean streak >= 2.6 on TEST A and on TEST B each AND a paired improvement >= +0.5 over the baseline champion on the pooled
  128 test starts (sign-flip p < 0.01). Stretch: mean >= 3.2, or a streak >= 4 on at least a quarter of the starts. An intermediate gain
  is a result.
- STOP RULE: if after about five hours of compute the selection-set mean is not >= +0.3 above the baseline champion's on the same seeds, stop and report what limits it.
- M1 STOP: if a correction at +60 ms removes less than a quarter of the scatter, or the oracle nudge lifts pass 3 by under 15 points, STOP and report (a result).
- New skill keys are opt-in and neutral by default; champion params must replay bit-identically through the new build on seeds 601, 705, 716
  (`scratchpad/btl/identity.py`) and the chain on 901-932 must still give 2.125.
- Promote an arena champion only through `playground/arena.py eval <trial> --params ... --controller ... --promote` on the four dribble trials
  and only if it WINS by the arena's paired test; never hand-edit `champions.json` / `trials.json`. Freeze binaries as `bin/challengers/btl3-<tag>`
  before evaluating. Never change `btl2-b1`..`b12`, `pgP0LRz2.txt`, A4's files, or any champion.
- Machine: 18 cores shared; at most 6 rollout workers, `nice -n 10`; never kill processes that are not mine; no git state changes.
- Stall rule: no Bash call over 3 minutes; long jobs go in the background with log + pid files in `out/btl3/`.

## Milestones

- [x] M1a baseline: champion on selection 2001-2128 (chain.py): 1.938
- [x] M1b feedback-payoff decision: R^2 data ambiguous, closed-loop servo test positive (pass 3 25 % -> 50-65 %)
- [x] M2 feedback stroke: tracking servo + aim + clock alignment (opt-in keys, identity checked)
- [x] Selection-set decision vs the stop rule: +0.55 on selection (6 s), far above +0.3
- [x] TEST A / TEST B (once each, final candidate and baseline): 2.422 / 2.578 against 2.047 / 2.141, PASS RULE not met
- [x] Arena promotion (3 of 4 trials won and promoted), FINAL STATE section written

## Log

- 11:47 M1a BASELINE (champion `bin/challengers/btl2-b12` + `scratchpad/btl2/params/pgP0LRz2.txt`; `bin/robolab_dribble_btl` is byte-identical to btl2-b12, sha1 9a3257b2...):
  SELECTION 2001-2128, 15 s, chain.py (log `out/btl3/baseline_sel.log`): mean btl_streak **1.938** (>=1 on 121, >=2 on 95, >=3 on 26, max 4 on 6); per pass
  1: 119/128 (93 %), 2: 97/127 (76 %), 3: 27/110 (25 %; 58 wrong hand / two bounces, 23 lost_after, 2 body), 4: 6/52 (12 %), 5: 0/7.
  (D's dev set 901-932 gave 2.125 and 42 % on pass 3; on 128 fresh starts pass 3 is 25 %.) THE NUMBER TO BEAT ON THE SELECTION SEEDS: 1.938 (stop rule: >= 2.238 after ~5 h).
  Note pass k's verdict includes the receiving hand's own next push landing a legal bounce ("continued"): pass 3 = the right return received by the left hand AND the left hand's
  second stroke (A4's reflex) landing a bounce, so the left second stroke limits pass 3 as well as pass 4.
  stage_stats (log `out/btl3/stage_stats_sel.log`): launch gate 128/128 arrival at the left (-0.119, 0.367) sd (0.030, 0.025); left return gate 117, no body 107, arrival at the right (0.433, -0.271) sd (0.074, 0.064);
  right return gate 97/107 but arrival at the left (-0.165, 0.378) sd (0.110, 0.146): the left hand receives only arrivals inside about x -0.22..-0.06, y 0.28..0.43.
- 12:00 M1b DATA (tools: `scratchpad/btl3/rec_live.py` closed-loop recorder of ball, palms, joints, contractions, hand-ball forces per 5 ms tick; `m1_analyze.py`, `m1_touch_geom.py`;
  traces `out/btl3/live_champ` = champion on 2001-2128, 6 s). Stage timeline (from the trigger = first g_run tick): touch 239 +- 3 ms (launch pass), 177 +- 8 ms (left return), 191 +- 13 ms (right return); contact 77 / 76 / 51 ms.
  Leave-one-out ridge R^2 of the pass's release velocity / arrival (n = 128 / 127 / 110, champion in the loop, unseen starts; vx vy vz arr_x arr_y):
    left return : ball crossing only .29 .05 .27 .05 -.04 | + arm q,qd at the trigger .61 .51 .70 .44 .27 | + live arm,palm at +60 ms .76 .53 .74 .39 .42 | at +120 ms .75 .50 .81 .34 .33
    right return: ball crossing only .21 -.07 .43 .01 -.01 | + arm at the trigger .28 .35 .71 .02 -.04 | + live arm,palm at +60 ms .31 .38 .82 .04 -.06 | at +120 ms .33 .43 .87 -.03 -.07
  The release velocity scatter on unseen starts is 2x D's in-sample one (left return sd 0.55 / 0.39 / 0.45 m/s, right return 0.4 / 0.8 / 0.6 incl. failures).
  Touch geometry (palm - ball offset at the first touch; sd 3.3 / 2.9 / 1.8 cm left return, 3.9 / 3.5 / 2.1 cm right return): from trigger arm state R^2 .51 .69 .61 (left) / .61 .32 .36 (right);
  with the live state at +60 ms .95 .92 .76 (left) / .78 .45 .40 (right): the OFFSET scatter is visible 100+ ms before the touch. The palm VELOCITY at touch (sd 0.3-0.9 m/s) is not (R^2 .1-.5 even at +150 ms): it follows the touch
  TIME (sd 8 / 13 ms; acceleration phase) - and the release velocity follows the palm velocity over the contact (R^2 of release v on the touch geometry .68 .53 .65 left, .2 .74 .70 right).
  Right-return failures (per-start table, `m1_stage2_table.py`): most failures have a normal release (|v| 4.0-4.6) but arrive at y >= 0.45 or x <= -0.25 (outside the left hand's reach); the arrival is NOT linearly predictable
  from anything at the trigger or +120 ms (R^2 ~0), while ~15 of 70 right returns are received and then lost by the left hand's own push.
  READING: the live state at +60 ms adds only 0.00-0.15 of the variance beyond the trigger-time arm state (which the champion's 5-feature schedule does not use in full: R^2 .5-.7 of the champion's own residual is linear in
  the 16 trigger features), so feedback alone is NOT obviously worth more than a richer feed-forward schedule; the total scatter predictable from the state at +60 ms is 40-80 % for the left return and 0-80 % for the right return.
  The brief's two stop tests are therefore ambiguous on the first; the second (oracle nudge, pass 3 +15 points) needs a closed-loop prototype: next.
- 12:10 M2 PROTOTYPE S1 (skill keys `pg_fb*`, build `bin/challengers/btl3-s1` / `btl3-s2`; identity: champion params replay bit-identically through btl3-s1 on 601, 705, 716 (8 s, `identity.py`), chain 901-932 (15 s) mean 2.125 as before):
  a TRACKING SERVO around the table. While a stage's program runs, the stroking arm's 16 muscles get the stage's NOMINAL contractions (conditional-mean trajectory given the schedule's own
  features ux, uy, z_i; tables `pgn / pgnx / pgny / pgnz`, fitted by ridge regression on champion closed-loop traces of 200 training starts 4001-4200, `fit_nominal.py`, params `params/nom_a.txt`) as reflex
  targets, gain `pg_fb` x `pg_fbs<stage>` x `pg_fbw<joint>`, ramped in over `pg_fbr`, damping about the nominal's own rate (`pg_fbv`, velocity reference); the table stays the drive (reflex gain was 0 before).
  First results (8 s chains on the 128 selection starts, baseline at 8 s = 1.938 exactly as at 15 s): ALL stages at 0.3: 1.805 (pass 3 25 -> 9 %), at 1.0: 1.055; velocity reference off: 0.531 (nominal motion braked).
  STAGE 0 ONLY (the launch pass; pg_fbs1 = pg_fbs2 = 0): gain 0.03: 2.008, 0.06: 2.164, 0.10: 2.148, 0.15: 2.266, 0.2: 2.109, 0.3: 1.672, 0.6: 1.312; gain 0.1 from t0 = 0: 2.258, from t0 = 0.1: 2.148.
  The launch servo tightens the chain downstream: pass 2 (left return) 76 -> 86-90 %, the right return's arrival sd (0.110, 0.146) -> (0.065, 0.081), >=3 on 26 -> 43 of 128 (max-of-8 selected on the selection set: expect ~0.1 optimism).
- 12:55 DEV2 CHECK (seeds 5001-5128, 8 s; a second set for checking choices, used only AFTER the selection-set scans; champion 2.102 there): stage-0 servo gain 0.06 / 0.10 / 0.15 (t0 = 0): 2.141 / 2.164 / 2.125,
  i.e. +0.02..+0.06 (pass 1 121 -> 125-126 of 128 as on the selection set, but pass 2 and >=3 do NOT improve: the selection-set gain of +0.2..+0.33 was mostly set luck plus max-of-8 selection (the champion is 1.938 on the
  selection set but 2.102 on dev2 and 2.125 on D's 901-932: the SE of a 128-start mean is ~0.07). From here: decisions on selection + dev2 pooled (256 starts), paired.
  Aim scan of the launch (champion, selection, stage_stats): pgc0x +0.01: arrival x -0.119 -> -0.084 (3.5 cm per cm of aim!), mean 1.758; -0.01: x -0.169, 1.555; pgc0y +0.01: y 0.367 -> 0.381, 1.906; -0.01: 1.789
  (champion 1.938): D's aims are at a local optimum, the launch is not a matter of aim.
  Next-stage success vs the previous stage's arrival (champion traces, `m1_sweetspot.py`): left return ok 93 / 84 % for crossing x in the middle / top tercile (-0.125..-0.105 / > -0.105) but 51 % below -0.125; 91 % for y < 0.374 but 49 % above;
  51 % for the lowest tercile of the incoming vertical speed (< 3.23 m/s) against 88 %: the tables work in a small window around the training centre, so stage outputs must be tight AND centred.
  Right return: ok 0 / 24 / 37 % over terciles of the incoming vertical speed (< 2.69 / 2.69-2.96 / > 2.96 m/s: the left return's energy), arrival means (-0.165, 0.378) selection and (-0.158, 0.408) dev2 against the left hand's sweet spot (-0.115, 0.36).
  Also built: static offset tables `pg_dt` / `pgdt<p>_<m>_<j>` (6 knots, 50 ms apart, additive drive) for closed-loop sensitivity identification (btl3-s3).
- 12:58 POOLED SCANS (selection 2001-2128 + dev2 5001-5128 = 256 starts, 6 s chains, champion build; `scan_pool.py`, paired SE vs the first config; log `out/btl3/pool_*.log`, streaks `out/btl3/pool_*_<i>.streaks`):
  AIM OF THE RIGHT RETURN (stage 2, pgc2x / pgc2y = the schedule centre; champion 0.4264 / -0.2705): ref 2.020 (se 0.054); x +0.02: 2.094 (+0.074); y -0.02: 2.168 (+0.148 se 0.046);
  x +0.02 & y -0.02: 1.961 (-0.059); x +0.01 & y -0.01: **2.191 (+0.172 se 0.049)** (pass 3 ok 95/221 = 43 % against 65/221 = 29 %); x +0.03 & y -0.03: 1.852 (-0.168). A narrow peak: ~4 cm of arrival per cm of aim.
  Failure anatomy of the right return (champion, selection, `m1_fail2.py`; n 110): 30 % the ball rises but the left hand never touches it before the 2nd bounce (arrival mean (-0.229, 0.452) sd (0.11, 0.09): overshoot beyond the left hand's reach),
  24 % ok, 21 % received then lost (the left hand's own reflex push fails), 12 % no gate, 9 % weak (apex < 0.58), 5 % body. Left return (n 127): 76 % ok, 13 % body, 8 % no gate.
  Tools: `rec_dither.py` (closed-loop excitation with pgdt offsets), `dlib.py` (per-stage features/outcomes; next-stage trigger state validated against the actual next g_run onset: 0 tick difference on 119 stages).
- 13:05 STAGE-1 AIM / LEAD SCANS on top of the stage-2 aim (pooled 256, 6 s): pgc1x -0.01 / +0.01: -0.059 / -0.098; pgc1y +0.01 / -0.01: -0.141 / -0.141; pg_lead 0.155: -0.316; 0.175: 0.730 (launch broken):
  stage 0-1 aims and the lead are at local optima (D's tuning); only the right return's aim was off. Base B = champion + pgc2x 0.43639, pgc2y -0.28047 (`params/base_b.txt`, 2.191 pooled vs 2.020).
  Feedforward energy gap of the right return: release v (-1.79, 1.70, -3.08) against the launch's (-1.84, 1.97, -3.54), its ball reaches the left hand with vertical speed 2.77 +- 0.32 m/s at the trigger (the launch's: 3.3) and the left table's
  inputs at received right returns are far from its schedule range (ball crossing sd 2.3 / 2.6 sigma, posture z mean -2.7 / -2.8 sigma): a cycled left table cannot take stage 3 as it is.
  Skill: added `pg_fk` predict-then-cancel feedback keys (decision times `pg_fd0..2`, tables `pgfw / pgfa / pgft / pgfg`; state now carries a live offset table), build `btl3-s4` (identity check pending).
  Started dither excitation of the right return on base B: seeds 10001-10400, sigma 0.06, `out/btl3/dith_s2`.
- 13:15 DITHER IDENTIFICATION OF THE RIGHT RETURN (400 starts, base B, N(0, 0.06) offsets on 16 muscles x 6 knots (50 ms apart) of the stage, `dither_fit.py`): 43 % of the 333 runs that reached the stage fail the gate or hit the body
  (17 % undithered): the stage is chaotic at the 0.06 activation level; the linear model y = a + S d (96 dims, ridge, leave-one-out) has R^2 <= 0 for every outcome (next-stage inputs, release velocity, arrival),
  and adding d to the live-state covariates does not beat the covariates alone (e.g. release vz .77 -> .67, next-stage vertical speed .49 -> .36). So the sensitivities needed for a predict-then-cancel gain matrix are not
  identifiable linearly from a few hundred runs (SE per entry ~ outcome scatter / (sigma sqrt(N)) ~ as large as the entries); the gain-matrix route (`pg_fk` keys, built but unused) is parked.
  Added the DESIGN-RANGE GATE (`pg_gfrom`, `pg_gu`, `pg_gz`, build btl3-s5): from pass p >= pg_gfrom a stage whose schedule features at the trigger (|ux|, |uy| > pg_gu or any |z_i| > pg_gz) are outside the table's range is not played: the reflex strokes that pass.
- 13:25 SERVO ON BASE B (pooled 256, 6 s, `scan_pool.py`, build btl3-s4, params `params/base_bn.txt` = champion + stage-2 aim (+0.01, -0.01) + nominal tables; log `out/btl3/pool_servoB.log`):
  ref (servo off) 2.191 | stage-0 servo gain 0.10: 2.359 (+0.168 se 0.072) | + stage-1 gain 0.025: 2.367 | + stage-2 gain 0.025 (stage 0 as before): 2.422 (+0.230) | + stage 1 and 2 at 0.025: **2.500 (+0.309 se 0.073)**
  (pass 1 253/256, pass 2 224/255 = 88 %, pass 3 126/234 = 54 %, pass 4 38/170 = 22 %; >=3 on 125, >=4 on 38 of 256; the original champion is 2.020 on the same 256: +0.48 so far) | stage 0 gain 0.1 with the servo ended at 200 ms: 2.402.
  The tracking servo that did nothing at stages 1-2 at gain 0.3 (all stages together) helps at gains an order of magnitude lower, together.
- 13:35 SERVO REFINEMENT + STAGE 3 (pooled 256, 6 s; builds btl3-s4 / s5): servo gain variants on base B all within 2.375..2.531 (noise +-0.07); working base D = base B + stage-0 gain 0.1, stage-1 0.025, stage-2 0.05, t0 = 0
  (`params/base_d.txt`, pooled 2.531 se 0.058, sets 2.492 / 2.570). Servo window ended at 200 ms: no gain (2.465); servo start at 30 ms: 2.375; stage-0 gain 0.15 / 0.07 (others fixed): 2.406 / 2.457.
  STAGE 3: cycling the left table for the left hand's second stroke (`pg_n 40, pg_per 2`): 2.367 (-0.164 se 0.035; pass 4 14/151 against 37/168 for the reflex); with the design-range gate at 2.0 sigma: 2.496 (pass 4 29/168),
  at 1.5 sigma: 2.512 (34/168): the table is no better than A4's reflex stroke even where its inputs are in range. Dropped.
  FAILURE ANATOMY with base D (selection set, 6 s): launch 99 % ok; left return 88 % (8 % body: ball clips a thigh/shin while rising after its bounce, 2 % lost_after, 2 % no gate);
  right return 54 % ok (body 16 %: l_thigh 13 / r_thigh 5 / l_shin 2 of 21, the rise passes under the lead thigh at (0.0..0.2, 0.1, 0.4..0.5); received-then-lost 12 %; no receive 12 %; no gate 6 %).
  The aim shift of the right return trades overshoot (champion: 30 % no-receive) for leg clips (5 % -> 16 %).
- 13:45 MORE CALIBRATIONS on base D (pooled 256; ref 2.531): posture-nominal shifts of the right return (pgzn2_i +- 0.5 sigma, i = wrist flexion, shoulder abduction, elbow): all worse (-0.098 .. -0.375), i.e. the tables are at a local optimum in their schedule centres except the
  stage-2 aim. ILC REFIT OF THE NOMINAL with the servo in the loop (200 training traces of base D, `fit_nominal.py`; conditional residual sd of the contractions 0.009/0.032 -> 0.006/0.022-0.029 (stages 0 / 1) and 0.050-0.062 -> 0.031-0.042 (stage 2):
  the servo cuts the trajectory scatter by 20-40 %): evaluated pooled it gives 2.449 (-0.08, noise) at the same gains, 2.363 at gain 0.15, 2.430 at 0.07: no gain from the refit, plateau 2.4-2.5.
  Built per-stage trigger lead `pg_lead<ordinal>` (btl3-s6); running joint-group and stage-2-lead scans.
- 13:50 GROUP / LEAD SCANS on base D (pooled 256 at 6 s, build btl3-s6; ref 2.531): stage-2 trigger lead 0.160 / 0.170 (champion 0.165): -0.262 / -0.383 (a 5 ms shift of the right return's start already costs 0.3: the tables are timed to the tick);
  servo switched off for one joint group (all stages): shoulder (flex, abd, rot) -0.324, elbow -0.215, wrist (flex, dev) -0.094, fingers -0.062: every group's servo helps, shoulder and elbow most.
  Stage 3 (left second stroke, A4's reflex) with base D, 87 attempts: ok 23, no gate 35, body 16, other 13; release v (0.52, -1.03, -1.85) sd (0.69, 0.94, 0.57) against the programmed left return's (1.44, -1.74, -3.36): too weak and too steep to cross the gate.
- 13:58 STAGE-3 REFLEX PARAMETERS (A4's left reflex stroke, the left hand's second stroke; only post-trigger params, so the upstream is unchanged and the paired SE is small), base D (ref 2.531), pooled 256, 6 s:
  bl_angl (tilt of the low end of the left pass stroke; 0.84) 1.05: 2.586 (+0.055 se 0.025), 1.25: 2.594 (+0.062 se 0.026; pass 3 145/234, pass 4 43/171); bl_sweep 0.32: -0.156; bl_drv 1.6: -0.086; bl_dzl 0.40: +0.008;
  joint weights of the servo (shoulder x2: -0.227, elbow x2: -0.047, shoulder+elbow x1.5: -0.070, wrist x0.5: -0.102): none better than 1.

- CLOCK NOTE (14:05): the entries from 'STAGE-1 AIM' on were first stamped with estimated times that ran ahead of the clock; they are corrected to the real clock (started 11:46; the 5-hour mark is ~16:45).
- 14:05 DEV3 VALIDATION (fresh seeds 6001-6128, never used for any choice; 15 s chains = the metric): champion (btl2-b12 + pgP0LRz2) mean 1.969 (>=2 99, >=3 27, max 5; passes 1-4 ok 120/128, 99/126, 29/107, 5/48);
  CANDIDATE final_a (`bin/challengers/btl3-final` = btl3-s6 + `scratchpad/btl3/params/final_a.txt` = champion + stage-2 aim shift + nominal tables + tracking servo gains (0.1, 0.025, 0.05) + bl_angl 1.25): mean **2.484**
  (>=2 110, >=3 56, max 5; passes 1-4 ok 124/128, 111/127, 56/114, 23/77): paired +0.516. ORACLE-class (tables) as before. The selection-based estimate (+0.57 pooled) was only slightly optimistic.
- 14:25 CLOCK ALIGNMENT (`pg_align`, `pg_acd`: the table clock starts at (lead - 0.0025) - (predicted time to the crossing at the trigger tick), removing the +-2.5 ms tick quantisation; builds btl3-s7/s8): pooled 256 (6 s): final_a 2.594, aligned 2.641 (+0.047 se 0.069),
  mean start 2.5 ms earlier (acd 0): 2.293; 0.0015: 2.539; 0.002: 2.578; 0.003: 2.602; 0.0035: 2.594; 0.005: 2.559: a sharp optimum at the champion's own timing. LATE SERVO GAIN (`pg_fbm` x gain from 150 / 200 ms on, build s9): 0: 2.598 / 2.613 (no change), 3x: 2.078 / 2.266, 6x: 1.840
  (the servo does its work in the approach; a stiff servo in the contact breaks the stroke). Dev3 (15 s): final_a 2.484 -> final_e (= final_a + pg_align 1, `params/final_e.txt`) **2.609** (>=2 107, >=3 71 of 128; passes 1-4 ok 124/128, 107/127, 73/113, 31/88), paired +0.125 (se 0.104) over final_a, +0.641 (se 0.101) over the champion.
  Incoming ball apex vs success (final_a, selection): left return ok 0.69 / 0.96 / 0.96 / 0.92 / 0.85 over apex quintiles 0.70-0.74 ... 0.78-0.84; RIGHT RETURN ok 0.12 / 0.32 / 0.73 / 0.80 / 0.77 over apex quintiles (0.42-0.66, 0.66-0.69, 0.69-0.71, 0.71-0.73, 0.73-0.80):
  the left return arrives with apex < 0.69 on 40 % of the starts and the right table, whose schedule does not see the apex, fails there (22 % ok against 77 %). Next: schedule the right return on the incoming apex.
- 14:43 APEX SCHEDULE (`pg_ap0 / pg_apx / pg_apy / pg_apt<stage>`: the incoming apex height moves the stage's schedule position and clock; build btl3-s10) for the right return, pooled 256 on final_e (ref 2.641): +-20 sigma/m: -0.30 / -0.47 (x), -0.50 / -0.35 (y);
  +-0.1 s/m: -0.11 / -0.17 (t); gentle +-4 sigma/m: -0.035 / -0.152 (x), -0.145 / -0.082 (y); +-0.04 s/m: -0.016 / -0.047 (t): a linear apex shift of the existing schedule does not help (the table needs a refit with the apex as a feature,
  not done); keys stay neutral. FINAL CANDIDATE FIXED (14:44): controller `bin/challengers/btl3-e` (= btl3-s10, built from the current source, identity vs btl2-b12 on champion params bit-identical on 601 / 705 / 716, 8 s) with
  `scratchpad/btl3/params/final_e.txt` = champion + stage-2 aim (pgc2x 0.43639, pgc2y -0.28047) + nominal tables `pgn*` (fit_nominal.py on 200 champion traces, seeds 4001-4200) + servo (pg_fb 0.1, pg_fbs1 0.25, pg_fbs2 0.5, t0 0) + bl_angl 1.25 + pg_align 1.
- 14:47 FINAL-CANDIDATE CHECKS: identity chain 901-932 (15 s) with the final build `btl3-e` and the champion params: mean 2.125 (>=1 31, >=2 24, >=3 11), the same as the champion's (and bit-identical activations on 601 / 705 / 716).
  DEV4 (fresh seeds 7001-7128, 15 s, never used for any choice): champion 1.953 (>=2 95, >=3 26; passes 1-4 ok 121/128, 95/126, 29/104, 7/54) -> final_e 2.398 (>=2 103, >=3 64; 121/128, 105/128, 64/112, 17/74): +0.445.
  Starting TEST A (3001-3064) and TEST B (3065-3128): candidate once each, baseline once each, 15 s, at 14:47 (nothing was run on these seeds before).
- 14:50 TEST A / TEST B (each run ONCE for the final candidate `btl3-e` + `final_e.txt` and ONCE for the baseline champion `btl2-b12` + `pgP0LRz2.txt`; 15 s chains; ORACLE-class: tables):
  TEST A (3001-3064): baseline 2.047 -> candidate **2.422** (+0.375 se 0.143, sign-flip p 0.007; >=2 52 -> 54, >=3 15 -> 30, max 4; passes 1-4 ok 63/64 51/63 17/58 2/25 -> 62/64 55/63 30/57 8/38).
  TEST B (3065-3128): baseline 2.141 -> candidate **2.578** (+0.438 se 0.139, p 0.002; >=3 17 -> 32; passes 63/64 54/64 18/55 3/28 -> 62/64 55/64 33/57 15/42).
  POOLED 128: 2.094 -> **2.500**, paired **+0.406** (se 0.099, sign-flip p 0.0001; better on 55 starts, worse on 26, tied on 47).
  PASS RULE: NOT MET (needs >= 2.6 on A and on B each: 2.422 and 2.578; and a pooled paired gain >= +0.5: +0.406). Stretch (3.2, or a streak >= 4 on a quarter of the starts) not met (streak 4 on 3 of 128 starts).
  A significant INTERMEDIATE GAIN (+0.41 over the champion on the two untouched test sets; +0.64 / +0.45 on dev3 / dev4, 15 s).
- 14:58 ARENA (`arena.py eval <trial> --params scratchpad/btl3/params/final_e.txt --controller bin/challengers/btl3-e --task dribble_btl_v3 --workers 6 --promote`, one trial per call):
  dribble_btl_streak_fresh32 (seeds 1101-1132) 2.3125 +- 0.41 vs champion 1.8438: +0.469, p 0.013 -> WON, promoted; dribble_btl_streak_25 (701-725) 2.72 +- 0.33 vs 2.12: +0.60, p 0.004 -> WON, promoted;
  dribble_btl_25 btl_rate 0.256 +- 0.034 vs 0.188: +0.068, p 0.007 -> WON, promoted; dribble_btl (10 starts) btl_rate 0.26 vs 0.22: +0.040, p 0.198 -> does not beat the champion (10 seeds), NOT promoted (its champion stays D's btl2-b12).
- 15:20 EXTRA FRESH CHECK (dev5, seeds 8001-8256, 15 s, 256 starts, never used for a choice): champion 2.023 -> candidate E **2.590** (+0.566 se 0.066, sign-flip p < 1e-4; passes 1-4 ok 246/256 205/254 57/223 11/103 -> 249/256 234/254 135/237 43/163).
  ALL FRESH SEEDS POOLED (TEST A + B, dev3, dev4, dev5 = 640 starts; dev3 was used once to confirm the clock alignment (final_a 2.484 vs final_e 2.609), TEST A / B, dev4, dev5 for nothing): champion **2.013** -> candidate **2.538**, paired **+0.525** (se 0.044, p < 1e-4);
  WITHOUT dev3 (TEST A + B, dev4, dev5 = 512 starts, never used for any choice): champion 2.023 -> candidate **2.520**, paired **+0.496** (se 0.049, p < 1e-4);
  P(streak >= 1, 2, 3, 4, 5) champion 0.96 / 0.79 / 0.22 / 0.04 / 0.00, candidate 0.98 / 0.86 / 0.52 / 0.18 / 0.00 (streak >= 4 on 113 of 640 starts against 27).
  Arena `recheck` of the three promoted champions reproduces them exactly (2.3125, 2.7200, 0.2560).
  Last cheap knobs (final_e, pooled 256, 6 s): per-muscle servo weights from the nominal's residual sd (gamma 0.5 / 1.0, 512 starts): -0.072 / -0.145 (code reverted: the source equals btl3-e again, sha1 4c3cc60a verified);
  recover duration t_rec 0.22 / 0.30: -0.379 / -0.246; hand_fb 0.8 / 1.1: -0.016 / -0.125: the rest of the chain sits at local optima of D's tuning.

- 15:34 PER-STAGE CLOCK OFFSETS (pg_acd<stage> +-1 ms on final_e, 512 starts: selection, dev2, dev3, dev4 at 6 s; ref 2.572): stage 0 +1 ms -0.008, -1 ms -0.057; stage 1 +1 ms -0.043; the remaining three configs were stopped (my own scan processes killed by pid, no stray jobs left): the candidate sits at a local optimum of the timing too. No further change to the candidate after the TEST runs.

## FINAL STATE (3 Oct 2026, agent D2): an INTERMEDIATE GAIN, the PASS RULE IS NOT MET

**Candidate** (fixed at 14:44, before any TEST run): controller `bin/challengers/btl3-e` (sha1 4c3cc60a..., byte-identical to `bin/robolab_dribble_btl` built from `lib/robolab/skills/dribble_btl.w` as it stands) with
`scratchpad/btl3/params/final_e.txt` (= champion `pgP0LRz2.txt` + stage-2 aim `pgc2x 0.43639, pgc2y -0.28047` + nominal-contraction tables `pgn*` + servo `pg_fb 0.1, pg_fbs1 0.25, pg_fbs2 0.5, pg_fbt0 0` + `bl_angl 1.25` + `pg_align 1`).
ORACLE-class: the launch, the left return and the right return are still open-loop muscle tables (the servo adds feedback on top of them); A4's reflexes drive everything else.

| set (15 s, paired, sign-flip) | champion | candidate | difference |
| --- | --- | --- | --- |
| TEST A 3001-3064 (run once) | 2.047 | **2.422** | +0.375 (se 0.143, p 0.007) |
| TEST B 3065-3128 (run once) | 2.141 | **2.578** | +0.438 (se 0.139, p 0.002) |
| TEST A + B pooled (128) | 2.094 | **2.500** | **+0.406** (se 0.099, p 0.0001) |
| dev3 6001-6128 (used once to confirm the clock alignment) / dev4 7001-7128 / dev5 8001-8256 (fresh) | 1.969 / 1.953 / 2.023 | 2.609 / 2.398 / 2.590 | +0.64 / +0.45 / +0.57 |
| all 640 fresh starts (TEST + dev3-5) | 2.013 | **2.538** | **+0.525** (se 0.044, p < 1e-4); streak >= 3 on 52 % (22 %), >= 4 on 18 % (4 %) |
| the 512 of them never used for a choice (TEST + dev4 + dev5) | 2.023 | **2.520** | **+0.496** (se 0.049, p < 1e-4) |
| arena dribble_btl_streak_fresh32 / streak_25 / btl_25 / btl (10 starts) | 1.844 / 2.12 / 0.188 / 0.22 | 2.3125 / 2.72 / 0.256 / 0.26 | +0.47 (p 0.013), +0.60 (0.004), +0.068 (0.007) PROMOTED; +0.04 (0.198) not promoted |

PASS RULE: TEST A 2.422 and TEST B 2.578 are below the 2.6 each, the pooled paired gain +0.406 is below +0.5 (the fresh-seed estimates +0.50 .. +0.53 sit right at it; the TEST pair drew 0.1 less): NOT MET. Stretch (3.2 / a quarter of starts at >= 4) not met.
Per pass on the fresh sets the chain is now launch 95-97 %, left return 82-92 %, right return 53-65 %, left second stroke (A4's reflex) 21-36 % (champion 94-98, 75-84, 26-33, 8-13 %); dev5, the largest set: 97 / 92 / 57 / 26 % against 96 / 81 / 26 / 11 %.

**What produced the gain** (pooled selection + dev2, 256 starts, 6 s, paired; champion 2.020):
1. the right return's aim (schedule centre pgc2x +0.01, pgc2y -0.01): 2.191 (+0.17; the closed-loop optimum differed from D's replay-fitted one: 30 % of right returns overshot beyond the left hand's reach; it trades them for leg clips);
2. THE FEEDBACK STROKE, a low-gain TRACKING SERVO around the table (`pg_fb*` keys): while a stage's program runs, the stroking arm's 16 muscles take the stage's nominal contractions as reflex targets
   (conditional-mean trajectory given the schedule's own features ux, uy, z_i, ridge fit on 200 closed-loop champion traces, `fit_nominal.py`) with damping about the nominal's own rate (velocity reference; without it the nominal motion is braked: 0.53);
   gains 0.1 (launch) / 0.025 (left return) / 0.05 (right return), i.e. an order of magnitude below the reflex gain, from the trigger to the contact: 2.191 -> 2.531 (+0.34). It cuts the conditional scatter of the contraction
   trajectories by 20-40 % (residual sd 0.009 / 0.032 / 0.050-0.062 -> 0.006 / 0.022-0.029 / 0.031-0.042 for the three stages) and the left return's release-velocity sd from (0.55, 0.39, 0.45) to (0.32, 0.33, 0.26) m/s;
3. `bl_angl` 1.25 (tilt of A4's left reflex stroke, now only the second left stroke): 2.594 (+0.06); 4. the table clock aligned to the ball's predicted crossing instead of the trigger tick (`pg_align`, removes +-2.5 ms of tick quantisation): 2.641 (+0.05; +0.125 on dev3).
(The selection-based estimates are optimistic by ~0.1: +0.62 pooled against +0.525 on fresh seeds.)

**What the data said about feedback (M1)** (`m1_*.py`, `rec_live.py`): the live arm / palm state at +60 ms explains 40-80 % of the release-velocity scatter of the left return (R^2 .76 .53 .74 for vx vy vz) but only 0.00-0.15 more than the arm state at the trigger,
and the right return's arrival is not linearly predictable from anything at the trigger or +120 ms (R^2 ~0); touch times scatter 8 / 13 ms (left / right return) against 3 ms for the launch. The brief's stop test (a correction at +60 ms removes < 1/4 of the scatter) was ambiguous, the
closed-loop test was not: pass 3 went from 25-29 % to 50-65 %. An OUTCOME-DIRECTED predict-then-cancel gain matrix (`pg_fk` keys, built, unused) is NOT identifiable: random activation offsets of sd 0.06 on 16 muscles x 6 knots break 43 % of the right returns
(17 % undithered) and the linear closed-loop sensitivity model has leave-one-out R^2 <= 0 on 400 starts. Gains of the servo >= 0.3, or a servo that stays stiff in the contact (3x from 150 ms: 2.08), destroy the chain.

**What did not work** (all pooled-256 paired unless stated): aims of the launch and left return, the trigger lead of any stage (+-5 ms: -0.26 .. -0.38), posture-nominal shifts of the right table (-0.1 .. -0.38), an ILC refit of the nominal with the servo in the loop (2.449 vs 2.531),
joint-group weights of the servo (all groups help; x2 on shoulder -0.23), per-muscle inverse-variance weights (-0.07 / -0.15), the incoming-apex schedule of the right table (+-4..20 sigma/m or +-0.04..0.1 s/m: all worse), a cycled left table for the left second stroke
(2.367, with the design-range gate 2.50: pass 4 no better than A4's reflex even where its inputs are in range), recover duration and hand feedback of the meeting correction, pg_dt dither identification.

**What limits it now** (failure anatomy, `m1_fail2.py`, `body_hits2.py`, `m1_sweetspot.py`): (1) the RIGHT RETURN depends on the incoming apex = the left return's energy: ok 12 / 32 / 73 / 80 / 77 % over apex quintiles (< 0.66 ... > 0.73 m), 40 % of the left returns arrive below 0.69 m, the left arm is at its
muscle / joint limit there (saturated drive) and the right table's schedule does not see the apex (a linear shift of its schedule does not help: it needs a refit with the apex as a feature); (2) 6-16 % of left and right returns clip the lead thigh (or shin) while rising after the bounce
(the aim shift trades overshoot for clips); (3) the LEFT SECOND STROKE is A4's reflex: release (0.5, -1.0, -1.9) m/s against (1.4, -1.7, -3.4) for the programmed return, 40 % of its passes miss the gate, and its table (a cycle of the left return's) is out of its design range
(ball crossing sd 2.3 / 2.6 sigma, posture z -2.7 sigma, 17 % less ball energy) so the chain ends near 3-4; (4) the stages are chaotic at the 0.05 activation level (tables timed to the tick: 5 ms costs 0.3), so feedback has to be low-gain and trajectory-based.
Next, in order of expected value: refit the right return (and the left second stroke as a table) with the incoming apex and velocity as schedule features, on records made with this servo in the loop (D's `oracle_gs.py` with a feature added; the replay needs the servo in Python);
an outcome-directed servo (palm-space rather than muscle-space targets) once a cheaper identification exists.

**Files**: skill `lib/robolab/skills/dribble_btl.w` (opt-in keys `pg_fb*` servo, `pg_align*`, `pg_lead<s>`, `pg_dt` / `pgdt`, `pg_fk` / `pgf*`, `pg_gfrom` / `pg_gu` / `pg_gz`, `pg_ap*`, all neutral by default: champion params replay bit-identically
through `btl3-e` on 601 / 705 / 716 (8 s) and give 2.125 on 901-932 (15 s)); tools and logs `scratchpad/btl3/` (`LOG.md`, `rec_live.py`, `fit_nominal.py`, `scan_pool.py`, `paired_test.py`, `m1_*.py`, `dither_fit.py`, ...); params `scratchpad/btl3/params/` (`final_e.txt` the candidate,
`base_b.txt` aim only, `nom_a.txt` nominal tables, `base_d.txt` / `final_a.txt` stages); frozen builds `bin/challengers/btl3-s1 .. s11` and `btl3-e`; arena champions `bin/champions/dribble_btl_streak_fresh32-20261003-144942`, `dribble_btl_streak_25-20261003-145805`,
`dribble_btl_25-20261003-145822` (+ `playground/arena/params/<same>.txt`); per-start streaks of every scan `out/btl3/pool_*.streaks`, fresh sets `out/btl3/{dev3,dev4,dev5,testA,testB}_{champ,e}.log`. Nothing was committed or pushed.
