# Table tennis round 10 campaign log (agent T, started 2026-09-29)

Goal: raise `tt_p2_300` (MyoChallenge 2025 TT P2, seeds 98000-98299) above the champion's 33.0%.
Champion: bin/champions/tt_p2_300-20260927-194659 + params/myo_tt_p2_r5_bhprac.txt (round-5 A).
Every run below: exact command line, seeds, result, pid. State lives in the repo (scratchpad/tt, params/, out/).
Load on the machine: ~50-100 (18 cores); at most 3 rollout workers, one search at a time.

## 2026-09-29 harness

- playground/tt_fast.py: same episodes as the standard path, cheaper. Kinematics-only geometry sweep
  (mj_kinematics/comPos/tendon/transmission instead of mj_forward) + one env per worker process (re-seed + reset).
  `tt_fast.py check` on seeds 98000-98005 (champion): 6/6 episodes IDENTICAL (every metric), setup CPU 1.7 s -> 0.13 s
  per episode; wall per episode ~9 s -> ~3.5 s at load 50-100. Arena evaluation still uses the standard path.

## Baseline dataset (champion, fast path)

- `TT_ENV=P2 .venv-myo/bin/python playground/tt_eval.py --params params/myo_tt_p2_r5_bhprac.txt --controller bin/champions/tt_p2_300-20260927-194659 --seeds 710000:710600 --out out/tt_r10/champ_710000.jsonl --workers 3`  (pid 24841, started 02:21); resumable (finished seeds skipped).
- RESULT champion on 600 fresh serves 710000-710599 (fast path, 894 s wall, load 100+): solved 182/600 = 30.3%, hit 80.2%;
  forehand 110/290 (37.9%), backhand 72/310 (23.2%). Classes: below the ball 76, out/wide/long 217, own half 52, net 30, lateral 25.
  Per-episode metrics: out/tt_r10/champ_710000.jsonl (also under `git`-ignored out/).

## Analysis of the baseline (scratchpad/tt/an*.py, playground/tt_impact.py)

- Success is set by the serve's speed (initial speed quintiles: 50/44/24/13/7 % solved, hit rate flat 72-89 %) and contact time
  (t<0.51 s: 16 %, >0.55 s: 52 %). Fast serves are hit but returned too fast.
- The offline impact model (v_out = alpha vp + (1-mu)(v-alpha vp) - (1+e-mu)((v-alpha vp).n) n, e 0.95, alpha 0.9, mu 0.012) + ballistic flight
  (table halves, net at x=0 to z 0.9475, ball radius 0.02) predicts solved for 94 % of inlier hits (|resid| < 0.7 m/s, 2/3 of hits).
- Pad normal at contact vs the aim law's: pitch error mean -5/+5 deg (fh/bh), std 10 deg; yaw std 2.3 deg (fh). Pad velocity along the
  normal at contact: mean -0.43 (fh), +0.21 (bh) m/s, std 0.5; every velocity component std 0.55-0.63 m/s.
- Feasible pad-pitch interval (the pitches whose return lands) has median width 14 deg (5..28), shrinking with ball speed
  (25 deg at <5.2 m/s, 8 deg at >6.5). Adding a retreat delta (pad velocity along the ball's travel) widens it:
  best delta* = 0.47 (v - 4.83) m/s, same on both sides. Monte Carlo with the champion's own noise: P(success|hit) 0.41 (pad still, best yaw)
  -> 0.55 (delta per serve), and 0.74 if the pitch were also placed optimally.

## Instrumented champion run (time series for pad-velocity analysis)

- `TT_ENV=P2 TT_SAVE_LOG=out/tt_r10/champ_logs .venv-myo/bin/python playground/tt_eval.py --params params/myo_tt_p2_r5_bhprac.txt --controller bin/champions/tt_p2_300-20260927-194659 --seeds 710000:710150 --out out/tt_r10/champ_710000_inst.jsonl --workers 3` pid 48905 started 02:38. tasks/myo_tt.py got an opt-in TT_SAVE_LOG (per-episode npz: log rows L, servo-joint q/qd + pelvis slides X, aim rows) and a `pelvis_vel` metric (read-only; the standard path is unchanged).

## Pad velocity sources (instrumented champion run, 150 serves, out/tt_r10/champ_logs/*.npz; an15/an16)

- Deterministic (identical to the uninstrumented run for all 150 seeds). Pad velocity at contact: std 0.51 / 0.62 / 0.52 m/s (x/y/z);
  it changes by 0.3-0.4 m/s rms over the last 30 ms (acceleration 10-20 m/s^2), so it cannot be predicted from 50 ms earlier.
- Along the pad axis (+x oriented, + = retreating): forehand pad +0.39 +- 0.48 = pelvis +0.54 +- 0.26 + arm/trunk -0.16 +- 0.42;
  backhand pad -0.21 +- 0.47 = pelvis -0.52 +- 0.31 (ADVANCING toward the net at contact) + arm +0.31 +- 0.33.
- The fore-aft slide rings around contact: pelvis vx swings +1.0 -> -0.86 m/s within the last 50 ms on many backhands
  (minimum-jerk to rest 80 ms before contact, goal re-planned every tick, servo overshoot).
- Built lib/robolab/skills/myo_tt_v11.w (`pv`: pelvis fore-aft slide reaches its goal AT contact at a retreat speed
  u = pv_k (|v| - pv_v0) + pv_u0, coasting the last pv_tmin; aim law expects pv_g u) + lib/entry/myo_tt_v11.w;
  `./build.sh myo_tt_v11` (7.5 min wall under load), frozen copy bin/challengers/myo_tt_r10-a.

## v11 first test (pelvis governor on the champion's params)

- `TT_ENV=P2 TT_SAVE_LOG=out/tt_r10/v11a_logs .venv-myo/bin/python playground/tt_eval.py --params params/myo_tt_p2_r5_bhprac.txt --controller bin/challengers/myo_tt_r10-a --set pv=1,lt_arms=0 --seeds 710000:710090 --out out/tt_r10/v11a_pv1_710000.jsonl --workers 3` (pid 90215)
- RESULT 24/90 vs champion 25/90 (paired diff -0.011 +- 0.040, p 0.71; fh 13/40 vs 16/40, bh 11/50 vs 9/50).
  The pelvis does NOT follow the planned terminal velocity: fh pelvis vx at contact 1.07 +- 0.36 (planned 0.43 mean; baseline 0.43), bh -0.38 +- 0.35
  (baseline -0.56); r(pelvis vx, planned u) 0.6 / 0.5. The fore-aft path is a forward excursion then a violent reversal in the last 0.1 s:
  the height-matching goal gx moves late (zt depends on the planned lateral slide via hx_sag: 15 cm of zt = 75 ms = 0.4 m of goal x).
  Pad velocity noise along the axis stays 0.55-0.58 m/s.
- Offline sensitivity (an22): the retreat law's gain depends on pad-velocity noise: P(success|hit) still-pad -> linear retreat law:
  sd 0.7: .335 -> .367; 0.5: .373 -> .451; 0.35: .397 -> .521; 0.2: .426 -> .614; 0.1: .430 -> .659. The noise, not the law, is the blocker.
- Arm joint speeds at contact (median |qd|, rad/s): elv_angle 1.5, shoulder_elv 1.9, shoulder_rot 0.5, elbow 0.4, pro_sup 0.6, dev 0.2, flex 0.8:
  the arm is far from still at contact (relative pad velocity along the axis: sd 0.42 fh / 0.33 bh).
- Batch 1 (pid see out/tt_r10/batch1.out): champion params with t_lock 0.10 / no stroke (d_push 0, drv_push 0) / both, seeds 710000:710120,
  to measure how the arm's activity near contact changes the pad-velocity noise.

## Batch 1 results (champion params, seeds 710000:710120, TT_SAVE_LOG; scratchpad/tt/batch1.sh)

- `t_lock=0.10`: 29/120 vs champion 34/120 (diff -0.042 +- 0.036, p 0.92; fh 14/48 vs 20/48). Pad velocity along the axis: fh 0.09 +- 0.41 (champion 0.39 +- 0.48),
  bh -0.01 +- 0.47 (-0.21 +- 0.47): locking the servo earlier barely reduces the noise and loses accuracy. Arm part (pad minus pelvis): sd 0.38 / 0.29.
- `d_push=0, drv_push=0` (no stroke): 34/120, IDENTICAL outcomes to the champion (slack diff +0.001): the stroke (fires 30 ms before contact) does nothing.
  (batch1's third variant was killed by PID 36771.)
- Regression of the reached pad pitch on the serve's features (5-fold CV): forehand R2 0.80 (residual 4.6 of 10.2 deg), backhand 0.15 (residual 9.0 of 9.8).
  The forehand's pitch/yaw/pad z/pad x are all linear in (contact time, crossing z): pad z R2 0.79, pad x 0.87. Pad pose over time (forehand, 52 serves):
  at the ready posture t=0.20-0.27 s pitch -22/-21 deg (sd 3-4), pad z 1.31-1.32 (sd 1-2 cm); at contact pitch -11 (sd 9.9), pad z 1.23 (sd 7 cm):
  the servo (0.28 s -> contact) creates the spread (contact pitch uncorrelated with pitch at 0.27: r -0.03).
- tasks/myo_tt.py: `l8` (lock-time report) is now recorded in the metrics.
- batch2 (v11b = lib/skills/myo_tt_v11.w with pv 2, frozen bin/challengers/myo_tt_r10-b): `--set pv=2,lt_arms=0` and `pv=2,pv_max=0,lt_arms=0`,
  seeds 710000:710120 (pid 47153 script, 47181 python).

## Batch 2 (v11b, r10-b) and the fixed-pitch design ceiling

- vb_pv2 (`pv=2`, tmin 0.06): 31/120 vs champion 34/120 (diff -0.025 +- 0.049, p 0.75). Forehand pelvis vx at contact 0.41 +- 0.47 (planned mean 0.40: the mean is
  now right, the spread grew), pad along axis 0.54 +- 0.66; backhand pelvis vx -0.25 +- 0.29 (planned +0.45): the parent's dispatch drops the backhand's
  min-jerk slide for the critically damped reference in the last 0.18 s (plan[0] - slide_margin <= 0.1), so pv_drive never ran there.
- vb_pv2_u0 (`pv=2,pv_max=0`): 27/120 (fh 18/48, bh 9/72). Forehand pelvis vx 0.13 +- 0.37 for a target 0 (reference terminal-velocity error with tmin 0.06:
  sim_ref.py: rms 0.26 m/s at 0.06, 0.085 at 0.02, 0.05 at 0.01).
- Fix (v11c = r10-c): `drive_pelvis` override runs pv_drive on both sides from the first plan to contact; pv_tmin default 0.02; backhand y falls back to the critically damped
  reference when tg <= 0.1 (as the parent). Also `pv:` lock report (planned u, reference q-velocity, q, time to go, goal q).
- Servo state at the last aim (forehand): height error eh = plan z + z_bias - pad z is -0.081 +- 0.049 m (backhand -0.054 +- 0.056): the pad ends 5-8 cm above its
  target (the servo under-tracks: effective gain << k_z 11); ball-minus-pad-centre z offset at contact +0.046 (fh) / +0.044 (bh) m, sd 0.055; in-plane contact offset median
  5.4 / 6.7 cm; hits >= 10 cm off-centre (rim): 12 % of forehand hits (18 % solved), 21 % of backhand hits (4 % solved).
- Failure decomposition of all 600 serves: forehand solved 37.9, no hit 19.3, net 16.2 (+2.8 rim), long 11.4, wide 6.2, rim-not-toward-net 4.1;
  backhand solved 23.2, no hit 20.3, long 11.9, rim-not-toward-net 9.7, net 9.4, wide 13.2, own half 4.8 (+ small).
- Fixed-pitch design (an33.py): forehand, best retreat + yaw per serve at a FIXED pad pitch (deg; 0 = vertical face, - = open): P(success|hit) with pitch sd 4, yaw 2.5,
  pad-velocity sd 0.3: -21: 0.57, -16: 0.68, -11: 0.78, -6: 0.87, -1: 0.92, +4: 0.84; with sd 10 / 0.5: -21 0.34, -11 0.54, -6 0.64, -1 0.64. The champion's forehand sits at
  -21 deg at the ready posture (wflex -0.769, the search box's bound) and reaches -11 +- 10 at contact; the best pitch under a retreat law is about -1..-6 deg.

## Batch 2b: v11c (r10-c) pv=2 both sides, tmin 0.02, arm means 0 (vc_pv2, 120 serves)

- 21/120 vs champion 34/120 (-0.108 +- 0.046, p 0.995 worse; hit 0.733 vs 0.800). Pelvis now follows the plan (vx - planned u: fh +0.08 +- 0.23, bh +0.02 +- 0.15;
  r 0.76 / 0.88), but the pad's velocity along the axis at contact is 0.60 +- 0.65 (fh) and 0.95 +- 0.50 (bh) against a planned 0.44: the arm adds ~+0.2 / +0.49, and in
  the champion the backhand pad moved at -0.21: the retreat law overshoots (mean exit speed 4.60 vs 5.63; hits into the net 41 vs 16 of 120, long 6 vs 13).
  Needs pv_arm1/2 (arm mean) calibration, or a pad-velocity-based aim; also the open-loop goal (pad plane = pelvis + fixed offset) loses the champion's closed-loop plane
  tracking (pelvis retreats to cancel the arm's forward reach), hit rate -7 points.
- job queue: scratchpad/tt/qd.py + jobs.jsonl (daemon pid see out/tt_r10/qd.out, waits for queue1.sh pid 68293). Queue1 = vc_pv2, batch3 (v_ffz, v_ffzn, v_consol, v_tservo20),
  v_zb03_600; then jobs.jsonl: v_wf55/40/25 (forehand ready wrist flexion), v_hxpad05/10/10_xhi22.

## Batch 3 (champion binary, params only; seeds 710000:710120; playground/tt_summ.py summaries)

- v_ffz (`g_ffz=1,ff_z=1.32,ff_n=(0.91,0.21,-0.36)`, height anticipation from the first plan): 26/120 (fh 12/48 vs 20; bh unchanged). Pad ends lower (z at contact 1.148 vs 1.197): worse.
- v_ffzn (+ `g_ffn=1`, normal anticipation): 29/120 (fh 15/48). Forehand pitch error to the aim improves (+2.0 +- 7.1 vs -3.4 +- 8.9 deg) but the ball meets the pad 7.9 cm above its
  centre (champion 4.4): the anticipation lowers the pad; would need z_bias re-centring.
- Forehand pose time course (champion; 63 serves): pitch -34 (0.1 s), -22.6 (0.2), -21 (0.3), -16.8 +- 7.5 (0.4), -15.5 +- 10.5 (0.45), -10 +- 12 (contact): the
  spread is created in the last 0.15 s by the servo's late sweep (face rate 70 +- 55 deg/s at contact). Backhand: yaw +59 (0.2 s) -> -70 (0.3) -> -22 (0.4) -> -5 +- 14 (contact),
  pitch -8 -> -15 -> -19 -> +1.5 +- 12.8, face rates 103 +- 120 / 58 +- 77 deg/s at contact: an overshoot-and-return transient, phase-dependent.
- Success by crossing y (at x = 1.75): far left (< -0.5, n 95) 8 % solved (18 % pad below the ball), y 0.3..0.5 (n 67) 61 %, far right (> 0.5, n 129) 33 % (21 % below the ball).
- v11d (r10-d): pv 3 (predictive pelvis: arm-relative velocity carried to contact; pelvis terminal velocity so the PAD's velocity along its normal is u).

## Batch 3/4 results (120 serves 710000:710120 each; paired vs champion 34/120; tt_summ.py / an38-40)

| variant (champion binary, params only) | solved | fh | bh | note |
| --- | --- | --- | --- | --- |
| `t_servo=0.20` | 37 | 23/48 | 14/72 | fh returns better controlled (out 5 vs 14) but 11 pad-below-the-ball misses (8); ball-pad z at contact +1.6 +- 3.2 cm (champion -0.5 +- 5.1) |
| consolidated forehand ready posture (mean q_corr folded into elv,sh_elv,elbow,pro_sup,wflex,dev) | 29 | 15/48 | 14/72 | forehand pitch error to the aim +2.5 +- 4.1 deg (champion -3.4 +- 8.9), exit elevation sd 17 (31), exit speed sd 0.69 (0.99); more misses below (14 vs 8) |
| consolidated + z_bias -0.01 | 31 | 11/48 | **20/72** | backhand alone +6 from the shared z_bias: below 3 vs 6, own half 6 vs 8, net 2 vs 5 |
| consolidated + z_bias -0.04 | 30 | 15/48 | 15/72 | |
| `hx_pad=1, z_bias=0` (pelvis matches the pad's measured height) | 34 | 17/48 | 17/72 | no change in the below-ball misses (fh 11) |
| `g_ffz=1` / `g_ffz=1,g_ffn=1` (anticipation) | 26 / 29 | 12 / 15 | 14 / 14 | pad ends too low; pitch error improves (+2.0 +- 7.1) |
| `t_lock=0.10` | 29 | 14/48 | 15/72 | |

- The true ball-minus-pad z at contact (log rows) is -0.5 +- 5.1 cm for the champion's forehand hits (the metrics' `ball_pos_out` is the exit position and overstates it by ~4 cm).
- Below-the-ball misses are marginal: the ball passes 11-15 cm above the pad centre (median 12.2 fh / 13.4 bh; pad radius 9.3 + ball 2).
- Pad height dynamics (consolidated posture, forehand): pad z 1.233 (0.2 s, sd 0.8 cm) -> 1.193 (0.27) -> 1.104 (0.35) -> 1.085 (0.42, sd 5.6) -> 1.190 (contact, sd 6.4):
  the servo drives the pad below its target and it comes back. Hypothesis: the servo's height target uses the ball's height at the plane the pad has NOW; the pelvis is
  still sliding fore-aft (-1 m/s) when the servo starts, so the target slides 5-15 cm and the integral servo chases and overshoots. v11e option `sg` (r10-e):
  servo and aim law from the ball's state at the goal plane.

## Ceiling table (playground/tt_ceiling.py on champ_710000.jsonl, 50 hits; offline model, best plan per serve)

| pitch sd | pad-velocity sd | yaw sd | P(land given a sweet-area hit) | ceiling P(success) at position sd 5 / 3 / 2 cm |
| --- | --- | --- | --- | --- |
| 10 deg | 0.5 m/s | 2.5 deg | 0.59 | 0.45 / 0.58 / 0.59 |
| 6 | 0.35 | 2.5 | 0.78 | 0.59 / 0.76 / 0.78 |
| 4 | 0.25 | 2.0 | 0.91 | 0.70 / 0.90 / 0.91 |
| 3 | 0.2 | 1.5 | 0.98 | 0.75 / 0.96 / 0.97 |
| 2 | 0.12 | 1.0 | 1.00 | 0.76 / 0.98 / 1.00 |

(P(ball within 8.5 cm of the pad centre): position sd per axis 6 cm 0.63, 5 cm 0.76, 4 cm 0.90, 3 cm 0.98.) The champion runs at about 10 deg / 0.5 m/s / 5 cm: its ceiling with a perfect
plan is ~45 %, it plays 30-33 %. 90 % needs pitch <= 4 deg, pad velocity <= 0.25 m/s and position <= 3 cm at once (3-4x quieter than this arm).
- Tools written: playground/tt_fast.py, tt_eval.py, tt_cmp.py, tt_summ.py, tt_impact.py, tt_aimlaw.py, tt_pools.py (side pools; classification agrees with the controller's side on
  600/600 seeds: out/tt_r10/pools_740000.json fh 704 / bh 796 of 1500), tt_ilc.py (lff ILC), tt_practice.py (sep-CMA, common serves, smooth score), tt_ceiling.py.

## Batch 5 (04:00): sg, pv3, qa, and the forehand pool baseline

- `ve_sg` (r10-e, servo/aim from the goal plane): 27/120 (fh 10/48): worse; with t_servo 0.20: 24/120, forehand hit 0.44 (23 pad-below-the-ball misses). Moving-target hypothesis
  NOT supported (the servo's target averages 1.20 m with sd 10 cm ACROSS serves and stays put over 0.30-0.48 s; the pad stays 7-11 cm above it: the servo under-tracks, effective
  gain 0.25-0.4). The ball's crossing height at the pad plane varies +-10 cm across serves because 29 % of serves have xh > x_hi 2.0 (ball 6 cm low there) and 24 % xh < x_lo 1.45
  (ball 7+ cm high); extending x_hi (2.3, 2.6) does nothing (identical 31/120: the plane never goes past 2.3).
- `vd_pv3` (r10-d, predictive pelvis + arm compensation): 22/120; forehand pad axis velocity +1.00 +- 0.42 (planned 0.44: the arm-compensation loop over-corrects through the
  trunk's lag), backhand +0.50 +- 0.47 (planned 0.46) but hit rate 0.556 (pad-below-the-ball 17, above 8): the pelvis's plane accuracy suffers (pv 2 and 3 cost 7-20 points of hits).
- Forehand pool (first 120 fh seeds of pools_740000.json): the champion solves 54/120 = 45.0 % (hit 0.90; pitch -9.1 +- 10.2 deg, err to aim -2.4 +- 9.8).
- `qa=3` (r10-f: forehand servo turns the face in yaw only) with the consolidated posture and a raised wrist: wflex -0.65: 24/120, pitch -5.8 +- 8.6; -0.45: 2/120, pitch -4.4 +- 6.9;
  -0.25: 0/120, pitch -3.2 +- 4.2 deg and exit elevation 33 +- 10 (quiet), but hit rate 0.19: the pad ends 11 cm too low (dz +11 cm): the wrist also lowers the pad. The face
  is steady when the servo leaves the pitch alone; the height has to come back through the shoulder/elbow (identification runs id_*: finite-difference Jacobian of the
  contact pose over the 7 ready parameters, 60 forehand serves each, r10-f).
- Offline: with the champion's natural pad velocity (0.4 +- 0.5 m/s, no velocity law), P(land | hit) for a FIXED forehand pitch: sd 4 deg: -11: 0.47, -5: 0.53, -2: 0.58, +1: 0.58;
  sd 10: -11: 0.43, -2: 0.48. The quiet pitch alone is worth ~+0.1 P|hit; with the velocity law it is 0.87-0.92 (an33).
- v11g (r10-g): `kk` late pelvis kick (command-level extra acceleration in the last kk_t 0.12 s, riding on set_pelvis, aim law expects kk_g of it), `qa`, `sg`, `pv 1-3`.

## Batch 6 (05:00): kick on the backhand pool, quiet-forehand posture identification, RSM

- BH pool (first 120 backhand-side seeds): champion 31/120 = 25.8 % (hit 0.767, exit speed 6.05 +- 1.09, "long" 14, "net" 11). `kk=1` (r10-g late pelvis kick, default law): 28/120: mean pad
  axis velocity -0.16 -> +0.27, exit speed 5.08 +- 0.68 (normalised as designed), "long" 14 -> 1 but "net" 11 -> 31 (exit elevation 23 +- 23 deg: 28 % of returns under the ~8 deg the
  window needs at 5 m/s): the returns need a more open face. bh_wflex 0.35/0.45/0.55 with kk: 14/9/11 solved; bh_wflex 0.45 alone: 9 (the backhand posture is very sensitive);
  trunk_fe -0.08 with kk: 1/120 (hit 0.33, the pad leaves its place).
- Exit-window analysis (an45.py, champion, 333 hits with an exit window): success is 95-97 % when the exit elevation is within +-5 deg of the feasible window's centre, 55-60 % at 5-15,
  lower beyond; window width 24 deg (fh) / 15 (bh) median; exit elevation minus centre: fh +8.6 +- 13.6, bh -5.3 +- 18.4. 31 % of all hits have NO feasible elevation at their
  exit speed and azimuth (148 of 481): 68 % of those leave at |azimuth| > 25 deg (rim/edge deflections), the rest are speed extremes. Rim hits (>= 10 cm off the pad's centre): fh 12 %, bh 21 %.
- LS posture identification (7 ready parameters, qa=3, 60 fh serves each): per +0.1 rad at wflex -0.65: pitch/yaw/pad z = elv -2.5/+0.4/+0.005, sh_elv +2.6/+1.1/-0.011 (raising
  the shoulder LOWERS the pad), sh_rot -0.7/-0.5/0, elbow -4.9/+1.8/+0.026, pro_sup 0, dev -4.9/+2.3/+0.006, wflex +1.9/+4.8/-0.013. The bounded LS candidates reach the pose
  (fh_c1 pitch -1.8, dz +1.4 cm) but the pitch sd stays 9 deg and success falls to 29 / 33 % (champion 45 % on this pool): the sd of the pitch depends on the wrist, not the servo:
  8.9-9.8 deg at wflex -0.71..-0.55, 6.9 at -0.45, 4.2 at -0.25 (but at -0.25 the yaw is 28 deg (aim ~12) and the pad 11 cm low: 17 % hits).
- tt_rsm.py: fixed-serve two-level random design (32 runs x 100 serves + baseline) regressed on coded levels; rsm_run1.sh runs it for the backhand then the forehand pool
  (factors: kick law, servo start/gains, per-side centring via lc, aim box, grip/gain). Logs out/tt_r10/rsm_bh1.log, rsm_fh1.log.

## Batch 7 (05:00): quiet-forehand posture attempts, far-target aim, CMC probe

- `qa=3` alone (champion posture, r10-f): 21/120 = 17.5 % against 54/120 = 45.0 % (pitch -15.4 +- 12.2 deg): the pitch servo helps; the pitch spread is not made by the servo.
- LS posture at wflex -0.25 (second Jacobian id2_*, per +0.1 rad: elbow pad z +0.029/pitch -3.1/yaw +1.0; sh_elv z -0.012/pitch +2.0; dev pitch -2.3/yaw +1.3; elv pitch -2.5; sh_rot yaw -0.7;
  trunk_ar +-0.1: yaw +-3.5, pitch +2.3/-3.1): candidates fh_q4 / fh_q5 miss (0 solved; pad 8.6 cm too low, hit 0.43/0.58): the linear model does not extrapolate over 0.2-0.4 rad. Dead end.
- `land_pull=1, land_x=-1.0` (absolute far target, champion binary, fh pool): 54/120 = 45.0 %, identical count to the champion.
- CMC prototype (playground/tt_cmc.py): muscle force model (mju_muscleGain/Bias) reproduces actuator_force exactly; the model has nv 70; arm joint inertias (folded) elv_angle 1.59,
  shoulder_elv 1.39, shoulder_rot 0.051, elbow 0.064, pro_sup 0.004, deviation 0.003, flexion 0.004 kg m^2; torque capacities at full activation +-45-55 (elv, sh_elv), +-70-83 (sh_rot),
  +-45-58 (elbow), +-7-13 N m (forearm and wrist); gravity 7.9 N m (sh_elv). At t = 0.40 s of a champion forehand the finger tendons pull the wrist flexion with -5.06 N m and the arm muscles
  balance +5.04. A first computed-torque + bounded-LS tracker (kp 400, min-jerk 0.3 s) saturates (allocation residuals 100-250 N m: a 0.5 rad move in 0.3 s needs ~100 N m at the shoulder,
  about twice its capacity) and leaves 0.4-0.6 rad errors on the wrist joints. Not pursued further (porting the dynamics and the allocation to the Tungsten controller is days of work);
  the numbers above are the record.
- v11i (r10-i) adds `ns_k`/`ns_v0` (aim pitch by serve speed). rsm_run1.sh (pid 34741): tt_rsm.py design on the fixed first 100 backhand-pool serves, then forehand-pool (r10-i, 16 factors, 32 runs each).

## 05:10 r10-i built; identity check; y_switch 0.0

- `./build.sh myo_tt_v11` (r10-i: ns_k/ns_v0 added) finished 05:03, frozen as bin/challengers/myo_tt_r10-i.
- Bit-identity check (job chk_r10i, `TT_ENV=P2 .venv-myo/bin/python playground/tt_eval.py --params params/myo_tt_p2_r5_bhprac.txt --controller bin/challengers/myo_tt_r10-i --seeds 710000:710060 --out out/tt_r10/chk_r10i.jsonl --workers 3`, all v11 options off):
  60/60 episodes identical to the champion's baseline rows on every metric except the diagnostics added after the baseline (`pelvis_vel`, `l8`, `pv`, `feat`).
- v_ysw00 (champion binary, `--set y_switch=0.0`, seeds 710000:710300): 86/300 vs champion 84/300 (diff +0.007 +- 0.007, p 0.31; 4 flips): the side boundary between 0.0 and 0.1 is flat.

## 05:35 Servo bounce-tick artifact (found from the every-third-tick aim log), bk option

- The aim log (`aim:` rows every third tick) shows, in 50 of 150 champion serves, one row at the tick of the table bounce with the servo's height error eh = -0.3 .. -1.6 m
  and the aim normal's z = -0.45 .. -0.75 (neighbours: eh -0.1, nz -0.1). Cause: on the tick the table-contact flag is first set the ball's velocity is mid-reversal (vz -3.24 / +1.38 / -2.78
  m/s in three serves: the bounce's sub-tick timing), `before` sets `@bounced` first and then predicts the plane crossing from that velocity as a post-bounce state
  (MyoTTBall.intercept with bounced = true), so the plan's crossing height and vz for ONE tick are off by 0.3-1.6 m; the servo (an integrator on eh and the normal) and the
  height matching's at_height (pelvis goal to the ball's own x) both consume it. Present in every serve (1/3 of serves show it at the sampled tick).
- Fix (`bk 1`, v11): on that tick the plan and the height matching's ball are the previous tick's state carried through the model's bounce (e 0.99), less one tick.
  The parent got two hooks (`plan_ball(p, v, f)`, `height_ball(p, v, zt)`; default = the old expressions; r10-j with bk 0 replays the champion on 40/40 serves: chk_r10j) and `bh_p_z`
  (backhand proportional height gain; default 0 = the old hard-coded 0; r10-k).
- r10-j `bk=1`, champion params, first 120 serves of each side pool (pools_740000.json):
  forehand 50/120 vs champion 54 (p 0.81; hit 0.900 -> 0.958, pad-below-ball misses 11 -> 4, ball-minus-pad z at contact +4.2 -> +1.8 cm, pad velocity along the normal +0.46 -> +0.27, exit speed 5.18 -> 5.42);
  backhand 34/120 vs champion 31 (p 0.32; hit 0.767 -> 0.808, pad velocity along the normal -0.16 -> -0.48 +- 0.35 (was +-0.46), exit speed 6.05 -> 6.36).
  So the guard raises the hit rate 4-6 points on both sides and the extra hits land out: the artifact had been giving the pelvis an accidental retreat (0.2-0.3 m/s) that slowed the returns;
  the champion's calibration (z_bias, retreat, aim) was practised around it.
- Also measured: a linear map of the serve's launch state (crossing t, y, z, vx, vy, vz at x = 1.8) predicts the forehand's face-pitch error to the aim to R2 0.76 (CV; residual 4.9 of 9.9 deg;
  0.90 with the contact time), the backhand's only 0.37 (residual 8.5 of 10.7 deg); the ball-pad height offset at contact is unpredictable on the forehand (R2 0.05; sd 5.4 cm), 0.26-0.46 on the backhand.
  (an50/an51/an52 in scratchpad/tt.)
- rsm_run1.sh (pid 34741) killed while it only waited; the RSM is redone on the bk regime (r10-k).

## 06:15 Live tracking (round 9 `lt`) re-examined with the fast harness, and set aside

- r10-j (bk 0) with the round-9 live-tracking params (`params/myo_tt_p2_r9_lt_fh.txt` / `_lt_bh.txt`), first 120 serves of each side pool (jobs lt_fh120 / lt_bh120):
  forehand 5/120 solved, hit 0.358: the face FOLLOWS the aim (pitch error to the aim -0.2 +- 2.8 deg against the champion's -2.4 +- 9.8) but the pad is 20-40 cm too high all the way in
  (servo error eh -0.25..-0.45 m from t 0.31 s: ready pad z 1.358 +- 0.029 against a ball crossing at 1.21) and 86 % of the misses are "pad above the ball"; backhand 12/120, hit 0.642
  (pitch error +3.5 +- 7.9 against +5.8 +- 11.8).
- z_bias -0.14 / -0.18 / -0.22 on that forehand: hit 0.375 / 0.425 / 0.442, solved 4 / 6 / 9 of 120. Servo gain probes (z_bias -0.05): k_z 12: 10/120 (hit 0.44); k_z 20: 1/120 (hit 0.47, pad-below 23);
  t_servo 0.15 with k_z 12 / 20: hit 0.50 / 0.59 but 2 / 1 solved: the fast servo moves the pad at contact (pad velocity along the normal -0.3 +- 0.9..1.0 m/s, exit speed sd 1.8).
- LS posture identification in the lt regime (id3_*: +0.1 rad on each of the 7 forehand posture parameters, 60 serves each, ready pose at t = 0.25 s; per +0.1 rad pitch / yaw deg, pad z m):
  elv -1.5/-1.1/0.000, sh_elv -0.3/0.0/0.018, sh_rot 2.6/4.3/-0.003, elbow -3.9/1.2/0.027, pro_sup 1.3/0.1/0.001, dev -5.6/3.3/0.011, wflex -1.7/4.3/0.002.
  One LS step to (pitch -4.5, yaw 15.3, z 1.21) (lt1: sh_elv 0.70 -> 0.43, elbow 1.28 -> 0.95, small others): ready pose (-6.8, 18.6, 1.189), hit rate 0.30 -> 0.83, but 1/60 solved: 47 of the 50
  hits went out (67 % wide: exit y-velocity -1.5 +- 1.7 m/s, the face yaw 4.5 +- 5.1 deg past the aim where the champion's forehand yaw follows to 0.3 +- 2.4). The lt regime needs the aim law re-calibrated as well
  (yaw follow, e_pad, the pad-velocity expectation) and its servo re-tuned: round 9's conclusion stands. Not pursued further in round 10.

## 06:20 Backhand posture LS (bk + kk regime), and the RSM restarted on narrower ranges

- Backhand contact-time errors in the bk=1, kk=1 (kk_m2 -0.48) regime on the first 60 backhand-pool serves (bhid_b0; TT_SAVE_LOG; r10-k): pitch error to the aim +11.7 +- 11.6 deg (the face 11.7 deg more
  closed than its aim: the champion regime's +5.4), yaw error +1.2 +- 6.4, ball-minus-pad z +3.1 cm, hit 0.867, solved 16/60. Jacobian by finite differences (+0.06 rad on each of the 8 backhand posture
  parameters, 60 serves each; per +0.1 rad pitch err / yaw err / dz (cm)): bh_elv -0.6/-0.5/-0.2, bh_sh_elv -3.7/0.0/+0.8, bh_sh_rot 0/0/0, bh_elbow -4.0/-4.5/-2.2, bh_pro_sup -0.3/0/0, bh_dev -3.6/-2.3/-1.4,
  bh_wflex +1.9/+2.2/+0.3 (solved -22 points: very sensitive), bh_trunk_ar +0.6/+0.6/+0.1. LS steps (side_solve.py; targets pitch error +6 / +3, yaw 0, dz +1 cm; no wflex; max step 0.15): realised pitch change -4.9 / -7.5 deg
  (predicted -5.7 / -8.7: the linear model holds) but hit 0.867 -> 0.767 / 0.717 and solved 16 -> 9 / 9 of 60: removing the face's closed bias moves the swing's arrival and the pad's place. Not adopted.
- Contact time is not a separate driver: within speed terciles, success by early/late contact is flat (backhand 0.54 / 0.24 / 0.12 by speed tercile of hits; forehand 0.64 / 0.37 / 0.41).
- rsm_bh2 (wide ranges) killed after its second run (corner 0: 3 % solved, hit 0.77); rsm_bh3 = same design with narrower ranges on the CMA-tuned backhand parameters (out/tt_r10/rsm_bh3, rsm_run3.sh, seed 21):
  baseline (bk 1, kk_amp 0) 27 % solved, hit 0.82, score 0.442; run 0 25 %.

## 07:15 Backhand RSM (rsm_bh3) and its validation on independent serves

- `bash scratchpad/tt/rsm_run3.sh` (r10-k, champion params + `bk=1,kk=1,kk_amp=0,kk_m1=0.27,kk_m2=-0.48,lc=1,lt_arms=0`, seed 21, 17 factors, 32 runs + baseline, the first 100 backhand-pool serves, 3 workers, 06:07-07:00):
  baseline (bk 1, no kick) score 0.442 solved 27 % hit 0.82; the 32 design runs: mean 0.306, sd 0.115, best 0.581 (run 21: 35 %); residual sd of the linear fit 0.086 (strongly nonlinear).
  Main effects (score, +-se, t): **bh_gain (0.92 -> 1.05) -0.177 +- 0.042 (t -4.2)** (hit 0.80 at 0.92 against 0.53 at 1.05 over the 16 runs each), kk_amp (0 -> 1) +0.070 (t 1.8),
  kk_v0 +0.037, kk_k -0.033, bh_dur -0.039, bh_p_n +0.034, bh_k_z -0.031, bh_k_n +0.032, the rest |t| < 0.8.
  The three best runs (21, 27, 11) and run 5 share kk_amp 1, kk_k 0.3, kk_v0 5.2, bh_gain 0.92, bh_p_n 0.3.
- Validation on 200 other backhand-pool serves (pool bh[100:300], seeds in scratchpad/tt/bh_val200.txt; scratchpad/tt/bhval1.sh; frozen r10-k for the challengers):
  | run | solved | hit | vs champion (paired) |
  | --- | --- | --- | --- |
  | champion (bin/champions/tt_p2_300-...) | 49/200 = 24.5 % | 0.81 | |
  | bk only (`bk=1`) | 50/200 = 25.0 % | 0.87 | |
  | C1 = bk + kk_amp 1, kk_k 0.3, kk_v0 5.2, bh_gain 0.92, bh_p_n 0.3 | 62/200 = 31.0 % | 0.82 | +0.065 +- 0.039, p 0.065 |
  | C2 = C1 with bh_gain 0.88 | 38/200 = 19.0 % | 0.80 | -0.055, p 0.96 (the gain has a peak near 0.92-0.95) |
  | **RSM run 21 exactly** (params/myo_tt_p2_r10_bh_run21.txt) | **69/200 = 34.5 %** | 0.83 | **+0.100 +- 0.038, p 0.0073** (flips 40 / 20) |
- Run 21's levels: kk_amp 1, kk_k 0.3, kk_v0 5.2, kk_m2 -0.65, bh_t_servo 0.30, lc16 -0.03, bh_k_z 1.6, bh_k_n 2.9, bh_p_z 0, bh_p_n 0.3, bh_dnz -0.03, box_x0 -1.3, box_x1 -0.8, bh_gain 0.92, bh_dur 0.47,
  ns_k +0.05, k_vpm 0.5.
- Forehand RSM (rsm_fh3, narrower ranges, seed 22) started 07:15 (scratchpad/tt/rsm_run5.sh).

## 08:10 Forehand RSM (rsm_fh3)

- `bash scratchpad/tt/rsm_run5.sh` (r10-k, champion params + `bk=1,kk=1,kk_amp=0,kk_m1=0.27,kk_m2=-0.48,lc=1,lt_arms=0`, seed 22, 17 factors on narrower ranges, 32 runs + baseline, the first 100 forehand-pool serves, 07:15-08:07):
  baseline (bk 1, no kick) score 0.663, 41 % solved, hit 0.96; design runs mean 0.616 sd 0.097, best 0.750 (run 16: 48 %), residual sd of the linear fit 0.061.
  Main effects (score, t): kk_m1 (0.1 -> 0.4) -0.106 (-3.6), t_lock (0.02 -> 0.035) -0.067 (-2.5), kk_amp (0 -> 1) -0.069 (-2.4), lc0 (-0.02 -> 0.02) -0.073 (-2.3), t_servo (0.26 -> 0.30) +0.059 (2.2),
  kk_v0 (4.8 -> 5.4) -0.054 (-2.2), p_z (0 -> 0.3) -0.056 (-1.8), box_x1 (-0.75 -> -0.65) +0.038 (1.4), the rest |t| < 1.
  The forehand does NOT want the kick: the 16 runs with the kick off average 0.657 (41.2 % solved, hit 0.92), the 16 with it on 0.575 (33.9 %); within the kick-on half a bigger kick (low kk_v0, low kk_m1) is better.
  Best runs: 16 (0.750), 1 (0.727), 8 (0.706), 29 (0.701). Linear step (min_t 1): kick off, t_servo 0.30, lc0 -0.02, p_z 0, box_x1 -0.65, t_lock 0.02 (params/myo_tt_p2_r10_fh_step1.txt; half step: _step05).
- Validation on 200 other forehand-pool serves (fh[100:300]) running: scratchpad/tt/fhval1.sh (champion, bk only, step1, step05, runs 16 and 1; frozen r10-n).
- r10-k -> r10-l (side-specific kick: kk2_amp/kk2_k/kk2_v0) -> r10-m (ns_k2, k_vpm2, bh_box_dx may be negative; 30/30 serves identical to r10-k on run-21 params) -> r10-n (`bk` 2 = backhand only, 3 = forehand only).
  playground/tt_r10_compose.py builds a candidate from a backhand RSM run and a forehand run/step file (the backhand's values go to its own names).

## 08:35 Forehand validation on 200 independent serves (pool fh[100:300]; scratchpad/tt/fhval1.sh; r10-n)

| run | solved of 200 | hit | vs champion (paired) |
| --- | --- | --- | --- |
| champion | 79 (39.5 %) | 0.840 | |
| bk only | 85 (42.5 %) | 0.905 | +0.030, p 0.26 |
| **linear step (step1: kick off, t_servo 0.30, lc0 -0.02, p_z 0, box_x1 -0.65, t_lock 0.02)** | **90 (45.0 %)** | 0.910 | +0.055 +- 0.039, p 0.097 |
| half step | 89 (44.5 %) | 0.920 | +0.050, p 0.12 |
| best design run 16 (in-sample 48 %) | 74 (37.0 %) | 0.905 | -0.025 (winner's curse) |
| design run 1 (in-sample 46 %) | 80 (40.0 %) | 0.915 | +0.005 |

- The forehand's design surface is flat (in-sample gains are winner's curse); the linear step generalises (+5.5 points, +2.5 over bk alone); the backhand's best design run generalised (+10 points), its consensus C1 less (+6.5).
- Candidate c1 = backhand run 21 (its own names) + forehand step1, `bk 1`: params/myo_tt_p2_r10_c1.txt (playground/tt_r10_compose.py). Mixed-pool run mix_c1 (710000:710600) started 08:32.

## 08:55 Candidate c1 on 600 fresh serves and the arena

- mix_c1 (`scratchpad/tt/mixval.sh mix_c1 params/myo_tt_p2_r10_c1.txt`: `TT_ENV=P2 .venv-myo/bin/python playground/tt_eval.py --params params/myo_tt_p2_r10_c1.txt --controller bin/challengers/myo_tt_r10-n --seeds 710000:710600 --workers 3`),
  paired against champ_710000: solved 213/600 = 35.5 % against 182 = 30.3 % (+0.052 +- 0.022, p 0.0132; flips 107 / 76), hit 0.858 against 0.802, forehand 118/290 = 40.7 % (+0.028, p 0.23; hit 0.807 -> 0.921),
  backhand 95/310 = 30.6 % (+0.074, p 0.010). By crossing y: gains at -0.8..-0.4 (0.15 -> 0.29), -0.4..0 (0.36 -> 0.46) and > 0.8 (0.22 -> 0.30); < -0.8 worse (0.07 -> 0.02, hit 0.33 -> 0.20).
  The forehand's extra hits are mostly rim hits (in-plane offset >= 9 cm: 17 % of its hits against 9 %, solved 7 %).
- tt_fast.py check on c1 (98000-98005): 6/6 identical to the standard path.
- BH stage 2 (rsm_bh4: 16 factors around run 21, fresh serves bh[400:500], 28 runs planned) stopped after 13 design runs: the baseline (run 21) scored 0.501 (28 %) and only run 9 (0.535) beat it: run 21 sits at a local peak.
- Arena: `.venv-myo/bin/python playground/arena.py eval tt_p2_300 --params params/myo_tt_p2_r10_c1.txt --controller /Users/erik/tungsten/bits/tungsten-robolab/bin/challengers/myo_tt_r10-n --note "..." --promote`
  started 08:55 (log out/tt_r10/arena_tt_p2_300_c1.log; pid 96596). The champion on these seeds: 99/300 = 33.0 % (forehand 60/156 = 38.5 %, backhand 39/144 = 27.1 % by the side rule; out/tt_r10/pools_98000.json).

## 09:03 Arena result for c1

- `arena.py eval tt_p2_300 --params params/myo_tt_p2_r10_c1.txt --controller .../bin/challengers/myo_tt_r10-n --promote` (427 s): **tt_p2_300 = 0.3533 +- 0.0542 (106/300)** against the champion's 0.3300 (99/300):
  mean paired diff +0.0233, p = 0.257: "does not beat champion", NOT promoted (history line written by the arena). The champion's rate on these seeds (33.0 %) is 2.7 points above its 30.3 % / 30.0 % on the two fresh blocks
  (710000:710600, 720000:720300), c1's (35.3 %) is at its fresh-block rate (35.5 %), so the arena's 300 seeds favour the champion by chance or by the selection that promoted it.
- Next: mix2_c1 (720000:720300, c1 against the champion's 90/300), tt_p1 with the round-10 binary and P1 params, tt_p2_backhand with c1 (reported only): scratchpad/tt/final_checks1.sh (started 09:04).

## 09:15 Final checks of c1, and c2 (backhand of c1, forehand = the champion's)

- mix2_c1 (720000:720300, second fresh block): c1 110/300 = 36.7 % against the champion's 90/300 = 30.0 % (+0.067 +- 0.030, p 0.0174; flips 51 / 31), hit 0.88 against 0.81; forehand 38.8 % against 43.3 % (-0.045, p 0.86),
  backhand 34.9 % against 19.3 % (+0.157, p < 0.001).
- Over both blocks (900 serves): c1 323 (35.9 %) against 272 (30.2 %); backhand 153/476 = 32.1 % against 104/476 = 21.8 % (+10.3 points), forehand 170/424 = 40.1 % against 168/424 = 39.6 % (+0.5: the forehand's bk + step is neutral).
- arena tt_p1 with the round-10 binary and params/myo_tt.txt: 50/50 = 100 % (no regression). arena tt_p2_backhand (131 serves) with c1: 35.9 % +- 8.3 against the champion's 22.9 %: WINS (+0.130, p 0.001); run without --promote.
- c2 = params/myo_tt_p2_r10_c2.txt (playground/tt_r10_compose.py --bh out/tt_r10/rsm_bh3:21 --set bk=2): the backhand of run 21 and the champion's forehand exactly (`bk 2` guards the bounce tick on the backhand only; the forehand's
  kick amplitude, ns_k, k_vpm, box, servo and lock values are the champion's): 30/30 forehand serves identical to the champion's on every metric (chk_c2fh). Rationale: the forehand change is worth nothing measurable, and a
  candidate identical to the champion wherever it has no gain has fewer flips, so the paired sign-flip test has less noise. Blocks running: scratchpad/tt/c2_blocks.sh (mix_c2, mix2_c2), 09:15.

## 09:20 c2 on both fresh blocks (identical forehand, backhand of run 21)

- mix_c2 (710000:710600): 206/600 = 34.3 % against the champion's 182 (30.3 %): +0.040 +- 0.016, p 0.0069 (flips 56 / 32); forehand identical (0.379, +0.000), backhand 31.0 % against 23.2 % (+0.077, p 0.007); hit 0.803 (0.802).
- mix2_c2 (720000:720300): 117/300 = 39.0 % against 90 (30.0 %): +0.090 +- 0.021, p < 0.0001 (flips 35 / 8); forehand identical, backhand 35.5 % against 19.3 % (+0.163).
- Together 323/900 = 35.9 % against 272/900 = 30.2 % (+5.7 points), all of it from the backhand: 155/476 = 32.6 % against 104/476 = 21.8 % (+10.7 points). r10-o adds `ts_lead` / `bh_ts_lead` (servo start timed on the predicted contact);
  scans scratchpad/tt/tsl.sh (forehand ts_lead 0.20 / 0.235 / 0.27 on fh_val200, backhand bh_ts_lead 0.20 / 0.23 / 0.26 on bh_val200, c2 params) started 09:20.

## 09:35 Contact-timed starts do not help; y_switch with c2

- Servo start timed on the predicted contact (r10-o, params c2, 200 independent pool serves each): forehand `ts_lead` 0.20 / 0.235 / 0.27: 64 / 74 / 74 solved against the champion's 79 (p 0.986 / 0.82 / 0.85 for "not better");
  backhand `bh_ts_lead` 0.20 / 0.23 / 0.26: 55 / 62 / 65 against run 21's 69 (all worse). The absolute t_servo / bh_t_servo are at least as good.
- Contact-timed backhand swing `bh_lead` (round 5's option) on run 21's backhand: 0.42 / 0.47 / 0.52: 1 / 8 / 16 of 200 solved against 69 (the whole backhand set is tuned for the absolute timing).
- y_switch 0.25 / 0.4 with c2 on 710000:710600 (paired against mix_c2): scratchpad/tt/ysw.sh, started 09:35.

## 10:07 Backhand stage 3 (posture, offsets, grip; rsm_bh5) and c3

- rsm_bh5 (`scratchpad/tt/rsm_run7.sh`: params c2, r10-o, 11 factors around run 21 (bh_elv, bh_sh_elv, bh_elbow, bh_dev, bh_wflex, bh_trunk_ar, bh_off, bh_y_trim, bh_grip, bh_dz_hit, bh_dd_push), 20 runs + baseline,
  fresh backhand serves bh[400:500]): baseline (run 21) 0.501 (28 %); design mean 0.400 sd 0.088, best 0.571 (run 15, 35 %); residual sd 0.080. Effects (score, t): bh_dz_hit (-0.03 / +0.03) -0.139 (-2.7),
  bh_elbow (1.98 / 2.04) +0.129 (2.4), bh_dev (-0.11 / -0.04) +0.082 (1.6), bh_dd_push +0.088 (1.4), bh_trunk_ar +0.063 (1.4), bh_elv -0.050 (-0.9), bh_y_trim -0.043 (-0.9), the rest |t| < 0.6.
- Validation on bh[100:300] (200 serves; champion 49, run 21 69): linear step (min_t 1.4: bh_elbow 2.04, bh_dev -0.04, bh_dz_hit -0.03, bh_dd_push +0.03) 80/200 = 40.0 % (+0.055 over run 21, p 0.078; +0.155 over the champion, p 0.0001);
  half step 79/200 = 39.5 % (+0.050 over run 21, p 0.043); design runs 15 and 9: 58 and 54 (worse than run 21: winner's curse again). params/myo_tt_p2_r10_bh5_{step1,step05,run15,run9}.txt
- c3 = c2 + the half step: params/myo_tt_p2_r10_c3.txt (bh_elbow 2.025, bh_dev -0.0575, bh_dz_hit -0.015, bh_dd_push 0.01). Blocks: scratchpad/tt/c3_blocks.sh (mix_c3, mix2_c3), started 10:07.
- FH stage B (rsm_fh5, rsm_run8.sh: forehand posture / servo / lateral trim, 14 factors, 24 runs on fh[400:500]) was started and paused for this validation; resume with scratchpad/tt/rsm_run8.sh.

## 10:13 c3 on both fresh blocks; arena attempt 2

- mix_c3 (710000:710600): 208/600 = 34.7 % against the champion's 182: +0.043 +- 0.016, p 0.0038 (flips 58 / 32); backhand 31.6 % (98/310) against 23.2 %; forehand identical. against c2: +0.003 (p 0.45).
- mix2_c3 (720000:720300): 131/300 = 43.7 % against 90: +0.137 +- 0.024, p < 0.0001 (flips 50 / 9); backhand 44.0 % (73/166) against 19.3 %; against c2 (117): +0.047, p 0.009.
- Both blocks: 339/900 = 37.7 % against 272 (30.2 %); backhand 171/476 = 35.9 % against 104 (21.8 %) (c2: 155, 32.6 %).
- Arena, attempt 2 (c3, frozen r10-n, --promote): started 10:13, log out/tt_r10/arena_tt_p2_300_c3.log.

## 10:17 ARENA: c3 WINS and is promoted

- `arena.py eval tt_p2_300 --params params/myo_tt_p2_r10_c3.txt --controller .../bin/challengers/myo_tt_r10-n --promote` (231 s): **tt_p2_300 = 0.4000 +- 0.0555 (120/300)** against the champion's 0.3300 (99/300):
  mean paired diff +0.0700, **p = 0.002**, "challenger WINS champion", **promoted to champion** (bin/champions/tt_p2_300-20260929-101727, params playground/arena/params/tt_p2_300-20260929-101727.txt = params/myo_tt_p2_r10_c3.txt).
  By the side rule on these seeds (out/tt_r10/pools_98000.json: 156 forehand, 144 backhand): forehand 60/156 = 38.5 % (the champion's forehand, unchanged) and backhand 60/144 = 41.7 % (the old champion 39/144 = 27.1 %).
- tt_p1 with the promoted champion binary and params/myo_tt.txt: 50/50 = 100 % (no regression). tt_p2_backhand (131 serves) with c3: 35.9 % +- 8.3 against 22.9 %: WINS (+0.130, p 0.001), promoted on that trial too
  (same 47/131 as c1's).
- Attempt 1 (c1: backhand of run 21 + the forehand step, `bk 1`) had scored 35.3 % (106/300, +0.023, p 0.257, not promoted); attempt 2 is c3 (the champion's forehand exactly, the backhand re-tuned in three stages).
- Stage 4 (backhand dynamics: rsm_bh6, scratchpad/tt/rsm_run9.sh, around c3, fresh block bh[500:600]) restarted 10:20.

## 10:25 README section written

- README.md: "Table tennis: where P2 is lost, a bounce-tick artifact, and a screening design (round 10)" inserted before the Relocate section (assembled by scratchpad/tt/assemble_readme.py from scratchpad/tt/README_r10_*.md and
  r10_result.txt / r10_arena.txt; re-run it to replace the section in place). Copy of the README with it: scratchpad/tt/backup/README.md.20260929_1025.
- r10-p = r10-n + `fh_gain` (a reflex gain multiplier on the forehand's four arm chunks, default 1.0 = the old behaviour; the forehand analogue of bh_gain). Frozen bin/challengers/myo_tt_r10-p.
- Queue: backhand stage 4 (rsm_run9.sh, running since 10:21), then forehand stage B with fh_gain (rsm_run8.sh).

## 10:38 Backhand stage 4 (rsm_bh6: dynamics around c3)

- rsm_bh6 (`scratchpad/tt/rsm_run9.sh`: params c3, r10-o, 14 factors (bh_stiff, bh_ki, bh_pel_fly, bh_dt_swing, bh_dx_hi, lc24, kk2_amp, kk_m2, bh_t_servo, bh_gain, bh_p_n, bh_dnz, k_vpm2, ns_k2), 24 runs + baseline,
  fresh backhand serves bh[500:600]): baseline (c3) 0.577 (35 %); design mean 0.513 sd 0.087, best 0.703 (run 7, 43 %), residual sd 0.053. Effects (score, t): bh_dt_swing (0 / 0.05) -0.092 (-3.1), bh_gain (0.91 / 0.94) -0.063 (-2.2),
  bh_pel_fly (0 / 0.6) +0.071 (2.1), bh_dx_hi (0 / 0.1) -0.070 (-2.0), lc24 (-0.02 / +0.02) +0.048 (1.7), ns_k2 (0.02 / 0.08) +0.050 (1.5), bh_stiff (0.09 / 0.13) +0.034 (1.2), the rest |t| < 1.2.
  Note: tt_rsm.py's step moves each factor from the MIDDLE of its range, so for factors whose baseline is a range end (bh_dt_swing, bh_dx_hi at 0) its half step is not a half step; the "half" candidate is built by hand
  (params/myo_tt_p2_r10_bh6_half.txt).
- Validation on bh[100:300] (c3's backhand: 79/200; champion 49): scratchpad/tt/bhval4.sh (step1, step05, run7, run18) and bhval4b.sh (half), started 10:38.
- The forehand stage B (rsm_run8.sh) is paused; its design directory out/tt_r10/rsm_fh5 was removed before it produced runs.

## 10:45 Stage-4 validation (bh[100:300]; c3's backhand 79/200, champion 49)

| candidate | solved of 200 | vs c3 (paired) |
| --- | --- | --- |
| linear step (min_t 1.4: pel_fly 0.6, lc24 +0.02, bh_gain 0.91, ns_k2 0.08) | 82 | +0.015, p 0.37 |
| tt_rsm step at 0.5 (moves dt_swing, dx_hi off their 0 baselines) | 79 | 0 |
| hand half step (pel_fly 0.3, lc24 0.01, gain 0.915, ns_k2 0.065) | 79 | 0 |
| design run 7 (in-sample 43 %) | 91 | +0.060, p 0.095 |
| **design run 18** (in-sample 41 %) | **95 (47.5 %)** | **+0.080, p 0.033** |

- The best four design runs share bh_pel_fly 0.6 (the backhand's fly-by slide), bh_gain 0.91, bh_dt_swing 0; runs 7 and 18 also bh_stiff 0.13, kk2_amp 1.2, kk_m2 -0.55, bh_p_n 0.2, bh_dnz -0.05, k_vpm2 0.7, lc24 -0.02.
  c4 = params/myo_tt_p2_r10_c4.txt: c3 with those shared values (bh_t_servo 0.30, ns_k2 0.05 averaged).
- Five candidates were looked at on bh[100:300]; to choose without that selection bias: scratchpad/tt/bhval5.sh on 196 never-used backhand serves bh[600:796] (c3, c4, run 18, run 7, the round-5 champion), started 10:44.

## 10:56 Fresh backhand serves bh[600:796] (196, never used), and arena attempt 3 (c5)

| run | solved of 196 | hit | vs champion (paired) | vs c3 |
| --- | --- | --- | --- | --- |
| round-5 champion | 44 (22.4 %) | 0.80 | | |
| c3 | 72 (36.7 %) | 0.89 | +0.143 +- 0.042, p 0.0005 | |
| c4 (stage-4 consensus of runs 7 and 18) | 88 (44.9 %) | 0.89 | +0.224, p < 0.0001 | +0.082, p 0.024 |
| **stage-4 design run 18** | **93 (47.4 %)** | 0.90 | +0.250, p < 0.0001 | +0.107 +- 0.041, p 0.006 |
| stage-4 design run 7 | 80 (40.8 %) | 0.89 | +0.184 | +0.041, p 0.17 |

- c5 = the champion's forehand (bk 2) + run 18's backhand on top of c3: params/myo_tt_p2_r10_c5.txt. r10-n and r10-o play c5 identically (40/40 serves).
- Arena attempt 3: `arena.py eval tt_p2_300 --params params/myo_tt_p2_r10_c5.txt --controller .../myo_tt_r10-o --promote` (205 s): 0.4033 +- 0.0556 (121/300) against the champion c3's 0.4000 (120): +0.0033, p 0.51: not promoted.
  The arena's backhand serves have the pool's crossing distribution (13 % beyond -0.8), so it is chance: c3 and the round-5 champion both scored ~5 points above their fresh-block backhand rates on those 144 serves.
- c5 on the two 900-serve blocks: scratchpad/tt/mixval.sh mix_c5, c5_block2.sh (mix2_c5), started 10:55.

## 11:00 c5 on the two fresh blocks

- mix_c5 (710000:710600): 237/600 = 39.5 % against the round-5 champion's 182 (30.3 %): +0.092 +- 0.017, p < 0.0001 (flips 83 / 28); backhand 127/310 = 41.0 % against 23.2 %, forehand identical; against c3 (208): +0.048, p 0.0009.
- mix2_c5 (720000:720300): 131/300 = 43.7 % against 90 (30.0 %): +0.137, p < 0.0001; backhand 73/166 = 44.0 %; the same 131 as c3 (flips 23 / 23).
- Both blocks: c5 368/900 = 40.9 % against the champion's 272 (30.2 %) and c3's 339 (37.7 %); backhand 200/476 = 42.0 % against 104 (21.8 %) and c3's 171 (35.9 %).
- Backhand stage 5 (rsm_bh7: scratchpad/tt/rsm_run10.sh, 14 factors along stage 4's directions around c5, fresh block bh[300:400], 24 runs) started 11:00.

## 11:20 Backhand stage 5 (rsm_bh7: further along stage 4's directions around c5)

- rsm_bh7 (`scratchpad/tt/rsm_run10.sh`: params c5, r10-n, 14 factors, 24 runs + baseline, fresh block bh[300:400]): baseline (c5) 0.624 (37 %); design mean 0.479 sd 0.106; best 0.665 (run 1, 42 %); residual sd 0.057.
  Effects (score, t): bh_pel_fly (0.4 / 1.0) +0.144 (2.9), lc24 (-0.04 / 0) +0.099 (2.6), bh_gain (0.89 / 0.93) -0.089 (-2.5), bh_t_servo (0.29 / 0.34) +0.086 (2.7), bh_dnz (-0.08 / -0.02) +0.070 (1.9), kk2_amp (1 / 1.4) -0.059 (-1.8),
  bh_p_n +0.046 (1.1), the rest |t| < 1. c5 is near a local optimum (only run 1 beat the baseline by more than 0.04).
- Validation on 200 backhand serves nobody has used (bh750[0:200] of out/tt_r10/pools_750000.json: seeds 750000-751499, forehand 717 / backhand 783): scratchpad/tt/bhval6.sh (c5, step1, step05, run 1, run 5, champion, c3), started 11:19.
  params/myo_tt_p2_r10_bh7_{step1,step05,run1,run5}.txt.

## 11:29 Stage-5 validation on never-used serves (bh750[0:200]) and the forehand stage B

| run | solved of 200 | hit | paired |
| --- | --- | --- | --- |
| round-5 champion | 46 (23.0 %) | 0.795 | |
| c3 | 82 (41.0 %) | 0.850 | +0.180 +- 0.037 over the champion |
| **c5** | **92 (46.0 %)** | 0.900 | +0.230 +- 0.043 over the champion, +0.050 (p 0.12) over c3 |
| stage-5 linear step (full) | 81 | 0.800 | -0.055 against c5 |
| stage-5 step at 0.5 | 92 | 0.860 | 0.000 |
| stage-5 run 1 (in-sample 42 %) / run 5 | 73 / 82 | 0.78 / 0.785 | -0.095 / -0.050 |

- c5's backhand: 44.9-47.4 % on three independent sets (196 + 200 + the 476 backhands of the two blocks: 42.0 %); stage 5 found no better point: c5 is a local optimum of the backhand screens.
- Forehand stage B (rsm_fh5: `scratchpad/tt/rsm_run8.sh`, r10-p with `fh_gain`, 15 factors incl. posture, servo timing and lateral trim, 24 runs on fresh forehand serves fh[400:500], params c3 = the champion's forehand) started 11:29.

- Pooled over the 900 fresh serves (out/tt_r10/{champ,c3,c5}_900.jsonl; tt_cmp.py paired): champion -> c3 +0.074 +- 0.013 (flips 108 / 41); champion -> c5 +0.107 +- 0.014 (131 / 35); c3 -> c5 +0.032 +- 0.013, p 0.0066 (80 / 51).
- 11:31 coordinator: the worker cap is now 4 while the 5-minute load average is under 30 (2 above 30), one search at a time; the forehand stage B (3 workers) plus one side job of 1 worker respect it. r10-p (fh_gain default) replays the round-5 champion's forehand on 30/30 serves.
- 11:36 tt_p2_backhand with c5 (1 worker, --promote): 0.4122 (54/131) against the promoted c3's 0.3588: +0.053, p 0.173, not promoted.
- 11:49 5-minute load 33.6 (above 30): the forehand stage B restarted with 2 workers (resumable design, 17 of 24 design runs done).

## 12:55 Close of the campaign

- Forehand stage B (rsm_fh5, r10-p, 15 factors incl. fh_gain; 24 runs on fh[400:500]): baseline (the champion's forehand) 0.623 (39 %), design mean 0.274 sd 0.163, best design run 0.615: every corner worse. fh_gain (0.88 / 1.10) +0.236 (t 9.9) by the linear model, but the scan on 200
  unused forehand serves (fh750[0:200], champion 85): fh_gain 0.97 / 1.03 / 1.06 / 1.10 -> 80 / 76 / 68 / 60: the champion's forehand is at a sharp optimum. (scratchpad/tt/fhg.sh)
- Final state of the arena: tt_p2_300 champion = c3 (bin/champions/tt_p2_300-20260929-101727, params/myo_tt_p2_r10_c3.txt) at 40.0 % (120/300; the round-5 champion 33.0 %); tt_p2_backhand champion = c3 (35.9 %); tt_p1 100 %.
  Best controller on fresh serves: c5 (params/myo_tt_p2_r10_c5.txt, frozen bin/challengers/myo_tt_r10-n): 40.9 % of 900 fresh serves against c3's 37.7 % and the round-5 champion's 30.2 %; not promoted (arena 121 against 120, p 0.51).
- Load policy applied: <= 3 workers while the 5-minute load average was under 30 (the coordinator allowed 4 at 11:30), 2 above 30; one search at a time; leftover own waiters stopped by task id.
- README: the round-10 section is in place before the Relocate section (assemble_readme.py replaces it in place).
- 12:50 the old 100-serve trial tt_p2 (97000-97099; champion round-5 approach A, 36.0 %): c3 39.0 % (+0.030, p 0.30), c5 44.0 % (+0.080, p 0.040: wins); c5 promoted there (arena `--promote`; frozen copy of r10-n under bin/champions/tt_p2-...).
