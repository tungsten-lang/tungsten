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
