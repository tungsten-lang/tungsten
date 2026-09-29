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
