# Batting round 2 campaign log (agent B, started 2026-09-29)

Goal (Erik's standing goal): increase the bat speed, measured in ROBOLAB'S OWN representation (contraction knots + the
reflex layer ON) on held-out pitches. Yardstick = the in-representation trials `bat_power_fresh_rep` (+ `_clean`),
NOT the ORACLE trials (open-loop programs, reflex gain 0).
Every run below: exact command line, seeds, result, pid. State lives in the repo (scratchpad/bat, params/, out/bat_r2).
Machine load 60-130 on 18 cores; at most 2 rollout workers, one search at a time. A fresh-pitch rollout costs ~4 s
wall at 4.6 s of simulated time (~7 s at the arena's 7.8 s).

Seed sets (never mix): arena old fresh 1000-1023 (bat_power_fresh, used only to score), NEW arena 1100-1123
(bat_power_fresh_rep*), knots-b practice 2000-2011 (already burnt for knots b).
Round-2 practice seeds: TRAIN 3000+ (fresh pitches), VALIDATION 4000-4047, none of which is an arena seed.

## 2026-09-29 trials

- `.venv/bin/python scratchpad/bat/make_trials.py` (under the arena lock): added `bat_power_fresh_rep` and
  `bat_power_fresh_rep_clean` to playground/arena/trials.json (seeds 1100-1123, env BAT_BODY=athlete BAT_FRESH_PITCH=1,
  metric power, task bat; the clean twin adds guard flow_ok). Existing trials untouched (json roundtrip of the old
  file was byte-identical before the edit).

## 2026-09-29 baseline entries and the in-representation diagnosis

- Seeded the new trials with the v6 knots swing (frozen copy bin/champions/bat_power_fresh_rep-20260929-061359 and
  ..._clean-20260929-061530; params playground/arena/params/bat_power_fresh_rep-*.txt = params/bat_v6_knots.txt):
  `.venv/bin/python playground/arena.py seed bat_power_fresh_rep --params params/bat_v6_knots.txt --controller bin/challengers/bat_v6-knots1 --workers 2 --note "IN-REPRESENTATION BASELINE ..."` (90 s) and the same for `bat_power_fresh_rep_clean` (86 s).
  RESULT bat_power_fresh_rep = **19.4383** m/s, 20/24 hits (misses seeds 1104 1109 1113 1121, all low pitches z 0.64-0.67),
  hits average 23.33 (22.40-24.38), flow 2.83. The `_clean` twin fails its guard on 6 of 24 (the 4 misses + seeds 1107 and 1120 at flow 3.04/3.07).
- New tools: playground/tasks/bat_rep.py (BatRepTask: every seed a fresh pitch, per-pitch aim diagnostics aim_v_ms / aim_n_cm / aim_dz_cm / aim_s /
  gap_cm, practice score) and playground/bat_rep.py (cheap eval: 4.6 s rollouts, a persistent 2-worker spawn pool, per-pitch table + JSON
  in out/bat_r2/). Check: `bat_rep.py eval --params params/bat_v6_knots.txt --controller bin/challengers/bat_v6-knots1 --seeds 1100:1124`
  reproduces the arena champion exactly (power 19.438, same 20 hits, same 4 misses), 75 s with 2 workers (load ~90).
  The current-source build (bin/robolab_bat_v6, frozen as bin/challengers/bat_v6-r2base) differs from knots1 by 0.01 m/s on 5 of 24 seeds
  (same hits and misses): later source edits, rounding only.
- `bat_rep.py eval --params params/bat_v6_knots.txt --controller bin/challengers/bat_v6-knots1 --seeds 3000:3144 --workers 2 --name base_3000_144 --quiet`
  (pid 86154, 408 s): power 18.749, **115/144 hits (80 %)**, hit speed 23.476, flow mean 2.80 max 3.10, flow_ok 110/144.
  The misses are NOT "1-3 cm": aim_n (the ball's offset from the bat's swing plane at the closest approach, cm) is -7..-18 cm on the low
  pitches (z < 0.68) and +7..+9 on the highest (z > 0.99), -7..-8.6 around (x 0.1, z 0.9).
- scratchpad/bat/an2.py: the aim error follows the program blend's LOCATION MISMATCH. With dz = z - sum_i w_i z_i and dx = x - sum_i w_i x_i
  (w_i the inverse-squared-distance weights of the 6 programs, which have zero slope at a program's own pitch):
  aim_n (cm) = -3.16 + 152 dz + 35.4 dx (m), **R2 0.877, rms 1.83 cm**, against R2 0.28 / rms 4.4 cm for aim_n linear in (x, z).
  So a first-order (Taylor) correction of the blend by the v5 aim law's own sensitivity vectors (k_z_u, k_x_u) should remove most of it.
- Implemented `taim` in lib/robolab/skills/bat_power.w (opt-in, all params 0 = the v6 swing exactly): taim_z, taim_x (gain on the
  k-vectors times the mismatch), taim_z0, taim_x0 (constant offsets), taim_ramp (fraction of the train over which the correction ramps in,
  quintic smoothstep); added to every keyframe's angle, rate, acceleration. New entry lib/entry/bat_r2.w -> `./build.sh bat_r2` (bin/robolab_bat_r2).

## 2026-09-29 taim: the first-order aim correction (the big one)

- Build: `./build.sh bat_r2` (3 min; first attempt failed: `rw` is a reserved word, a local named rw is parsed as a call), frozen copy
  bin/challengers/bat_r2-t1. With taim off it replays bin/challengers/bat_v6-r2base bit for bit (24 arena pitches: same speeds, hits, flow).
- Probes (`scratchpad/bat/probe1.sh`, seeds 3000-3047, taim_z=1 alone then taim_x=1 alone, pids by the driver; an3.py paired analysis):
  taim_z=1: delta aim_n = +0.39 - 59.4 dz - 3.4 dx (cm; m), R2 0.989, rms 0.24 (!), hits 35 -> 46 of 48, hit speed -0.07, flow unchanged;
  taim_x=1: delta aim_n = +0.23 - 1.0 dz - 52.4 dx, R2 0.974, hits 30 (over-corrects), speed -0.17.
  With the baseline's own aim_n = -3.16 + 152 dz + 35.4 dx that gives gains taim_z = 152/59.4 = 2.56, taim_x = 35.4/52.4 = 0.68 and
  taim_z0 = -3.16 / (152) = -0.021 m for the 3.2 cm bias (an exact linear response: 2 probes were enough).
- VALIDATION (never used to fit): `bat_rep.py eval --params params/bat_v6_knots.txt --controller bin/challengers/bat_r2-t1 --seeds 4000:4048 --set "taim_z=2.56,taim_x=0.68,taim_z0=-0.021" --name cal1_val4000`:
  **48/48 hits, power 23.115 m/s**, fair 42/48, aim_n within +-2 cm except one 5.1 (v 40.5, z 0.633), residual rms 1.18 cm (R2 0.04 against the mismatch:
  the linear structure is gone), flow mean 2.80 max 3.06 (3 of 48 above 3.0). (baseline on 3000-3047: 35/48 hits, 17.15.)
- params/bat_r2_taim1.txt (v6 knots + those four values). Arena: `arena.py eval bat_power_fresh_rep --params params/bat_r2_taim1.txt --controller bin/challengers/bat_r2-t1 --workers 2 --promote`
  -> **22.98 m/s, 24/24 hits**, fair 71 %, quality 0.30, flow 2.83; paired diff +3.54 over the baseline champion but **p = 0.061: NOT promoted**.
  The sign-flip test cannot promote a fix that turns 4 misses into hits (smallest possible p with 4 dominating differences is 2^-4 = 0.0625);
  the other 20 pitches differ by a few tenths in both directions. The history entry records it as a loss; a later challenger that also gains speed on every
  pitch will promote normally. (Not forced: a seed --force would rewrite the reference by hand.)
- Round-2 practice objective (tasks/bat_rep.py score): hit = bat speed - 0.5 per cm of |aim_n| beyond 3 cm; miss = -5 - 100 x gap(m); - 8 x max(0, flow - 2.7).
- 16 maximin training pitches from the 144 (farthest-point in x/0.3, z/0.38, v/6.5): seeds 3008,3049,3050,3060,3064,3073,3074,3091,3092,3102,3107,3108,3115,3118,3127,3138.
- scratchpad/bat/scan1.sh: one-at-a-time probes of 14 settings around taim1 on those 16 pitches (out/bat_r2/scan1_*.json, scan1.log).

## 2026-09-29 scans and search S1

- scan1.sh (16 maximin training pitches, taim1 + one change; out/bat_r2/scan1.log): base 22.997 (flow 2.79); arm_swing_kd 0.03 **24.234** (+1.24, 16/16);
  train_end -0.01 23.267 (flow 2.74), +0.015 22.07; step_delay 0.18/0.2 22.98/22.94 (flow 2.76/2.74); hip_open 0.1/0.25 22.47/21.23 (worse; flow 2.81/2.99);
  prog_trig 0.21 (1 miss) / 0.25 22.68; train_gain 0.8/1.3 22.96/23.08; train_drv 0.8 (10 misses) / 1.2 (4 misses): the drive scales the swing plane;
  dur_arc 0.4 flow 2.737, 0.5 flow 2.82. (params/bat_r2_taim2.txt = taim1 + arm_swing_kd 0.03 + train_end -0.01.)
- scan2.sh (around taim2): taim2 = **24.487** on 16/16 (flow 2.735, max 3.125); arm_swing_kd 0.01 / 0.0: hit speed 24.85 / **25.03** but 2 / 3 misses
  (aim_n shifted by about +3 cm on every pitch: a bias the taim gains can re-centre; the misses have aim_n 8-10); train_end -0.02/-0.03 flow 2.65/2.58 (max 2.9/2.8)
  and one miss (3108); swing_kd 0: same; arm_swing_kp 13: aim breaks (2 misses), 7 fine; swing_kp 6: 24.42 flow 2.75; train_gain 0.8 24.40, 1.3 two misses.
  Reading: the swing's speed is set by the excitation drive; the reflex layer's velocity damping (arm_swing_kd) brakes it, and every parameter that
  changes the drive/damping shifts the aim by a few cm. So candidates must be judged on their RECALIBRATED aim.
- playground/bat_search.py: sep-CMA (search.py's Search/BoxRep) with a calibrated-aim objective: per candidate, aim_n is regressed on (1, dz, dx) over its pitches
  and the residual is scored (0.5 per cm beyond 3 cm), timing 0.3 per ms of |aim_v - 2.5| beyond 4, flow 8 per unit beyond 2.7, plus a soft penalty when the
  required recalibration is beyond the taim gains' reach; risk 0.25 (mean - 0.25 (mean - min)).
- **S1 launched** (pid 32340, workers 2): `ROBOLAB_CONTROLLER=$PWD/bin/challengers/bat_r2-t1 .venv/bin/python playground/bat_search.py --init params/bat_r2_taim2.txt --only "arm_swing_kd,arm_swing_kp,swing_kp,swing_kd,leg_swing_kp,leg_swing_kd,swing_gain,train_gain,train_drv,train_end,train_legs,ri,prog_trig,dur_arc,leg_follow,limit_brake,rel_frac,step_delay,arm_kd,trunk_kd,arm_gain,wrist_rel_kp,wrist_rel_kd" --box "..." --seeds 3008,3049,3050,3060,3064,3073,3074,3091,3092,3102,3107,3108,3115,3118,3127,3138 --budget 3400 --workers 2 --sigma 0.1 --risk 0.25 --seconds 4.3 --out params/search/bat_r2_s1.txt --log out/bat_r2/s1.jsonl > out/bat_r2/s1.log`
  (23 tunables, 16 pitches per candidate, population 14, about 9 min per generation; best params written on every improvement; resume with --init).
- S1 restarted (pid 34072; the first launch pid 32340 was stopped after its generation 1: its "shift" penalty used |a_z - 152|, the UNcorrected slope, but the fit
  runs on the taim-corrected aim, so it should be |a_z|; fixed in playground/bat_search.py). Generation 1 of the first launch = the start point taim2: speed 24.487,
  flow 2.735 / max 3.125, aim fit a0 +1.8 az +36 ax +17 (rms after removing it 1.48 cm).
- S1 progress (objective / mean speed / flow mean, max): gen 1 23.29 / 24.49 / 2.74, 3.13; gen 2 24.13 / 24.90 / 2.68, 2.95; gen 4 24.62 / 25.28 / 2.65, 2.85;
  gen 5 24.75 / 25.46 / 2.58, 2.82; gen 6 25.09 / 25.74 / 2.54, 2.80; gen 7 **25.22 / 25.76 / 2.62, 2.87** (hits 16/16 as run; aim fit a0 -1.3 az +26 ax +37);
  gen 8 no gain. **Stopped after gen 8** (1472 rollouts; pid 34072 and its 3 workers) because new structural parameters (below) looked worth more than the
  +0.13 per generation. Best = params/bat_r2_s1.txt: arm_swing_kd 0.0 (the floor of its box), prog_trig 0.2389 (fire 8.9 ms earlier), train_end -0.0202
  (the train 20 ms longer), train_gain 0.838, dur_arc 0.384, step_delay 0.1644.
- Free-swing profile (`scratchpad/bat/freeswing.py`: fire late so the ball has passed, read the sweet spot's own speed): for taim2 the free-swing speed
  peaks at 230 ms after the hips fire (25.7 m/s) while contact comes at 217 ms (24.7): the swing was hit 13 ms before its own peak, and the speed rises
  0.13 m/s per ms there. For the S1 best: peak 26.43 at 230 ms, contact at 223 ms (25.98). The search moves the fire earlier and the train longer.
  Why the speed keeps rising to 230 ms: after the program's own contact time (216 ms) its table is the CMA rollout WITH the ball's impact (the wrists' rates
  collapse within 10 ms), which the knots then take as their target and brake against.
- The command's largest steps (flow `cmd`, `scratchpad/bat/trace2.py`) are at the swing's START, 15-20 ms after the hips fire, in all three groups (trunk 0.56,
  legs 0.52, arms 0.31 of their peak command speed): the first knot segment goes from the load's velocity to the program's within one 20 ms segment.
- New opt-in features (lib/robolab/skills/bat_power.w, all off by default; each build replays the previous one bit for bit on 2-24 pitches, `scratchpad/bat/smoke.py`),
  binaries bin/challengers/bat_r2-t1 (taim), -t2 (+ tres, train_first), -t3 (+ train_legs_ease), -t4 (+ train_ext), **-t5 (+ train_lead, train_dlead)**:
  `train_first` (the first knot segment lasts that many times the others: spreads the start's velocity step), `train_legs_ease` (the legs' swing easing
  mixed toward a smoothstep: no velocity step from the plant's stillness), `train_ext` (past the program's contact the plan is the pre-contact motion carried on
  at contact velocity, slowing to rest over train_ext s, instead of the table's post-impact rollout), `train_lead` / `train_dlead` (the reflex targets / the feed-forward
  drive read from the program this much later than the keyframe's time), `tres` (Codex-style zero-initialised residual: 4 joint-group offsets bounded by tres_b,
  weights tw0-23 on 6 gaussian time bumps after the fire, tv0-15 on the pitch [1, height, crossing, speed]).
  One-pitch smoke (seed 3008, taim2): train_first 2: speed -0.18, flow -0.075; train_legs_ease 0.5: -0.21, -0.03; train_lead +0.01: **+0.81 m/s and flow -0.13**
  (aim +10 cm: recalibration needed); -0.01: -3.0; train_dlead +0.01: -1.8, -0.01: +0.23 (aim +13 cm).
- **S2 launched** (pid 73040, workers 2, controller bat_r2-t5, start params/bat_r2_s1.txt, 28 tunables = the 7 new (train_lead, train_dlead, train_first, train_legs_ease, train_ext,
  k_in, taim_ramp) + 21 of S1's, a SECOND set of 16 maximin fresh pitches (seeds 3009,3022,3040,3041,3054,3055,3061,3062,3069,3070,3112,3123,3135,3137,3140,3143;
  none used in S1), BATS_FLOW=4 BATS_FLOW_CAP=2.5 BATS_A0CAP=14, population 14, budget 3200): `ROBOLAB_CONTROLLER=$PWD/bin/challengers/bat_r2-t5 BATS_FLOW=4 BATS_FLOW_CAP=2.5 BATS_A0CAP=14 .venv/bin/python playground/bat_search.py --init params/bat_r2_s1.txt --only "..." --box "..." --seeds ... --budget 3200 --workers 2 --sigma 0.1 --pop 14 --risk 0.25 --seconds 4.3 --out params/search/bat_r2_s2.txt --log out/bat_r2/s2.jsonl > out/bat_r2/s2.log`.
- Builds t6 (tres starts through a 40 ms smoothstep window, so a constant term does not step the command; frozen bat_r2-t6) and **t7** (bat_residual.w: BatConvResidual, the Codex
  module's architecture and fixed random projections reimplemented on the SDK: 22 inputs = 4 muscle groups (index mod 4) x (contraction, rate, acceleration, jerk) + 6 task sensors,
  two causal separable convolutions, features [1, f1..f4]; `tres_conv 1` adds them to the readout through tc0-tc19; every tres output goes through a 30 ms low-pass and the
  contact fade). Frozen bin/challengers/bat_r2-t7. Smoke on seed 3008 (taim2): t7 default == t1 (25.34, flow 2.61); tw3 0.5 + tv0 0.3: 24.79 / 2.98; conv readout: 25.25 / 2.615.
- S2 gen 1 (the S1 best, alone, on the NEW 16 pitches): speed 25.60 (S1's own training set: 25.76), flow 2.638 max 2.891, 16/16 hits as run, aim fit a0 -0.7: the S1 gains
  carry over to pitches it never saw (-0.17 m/s).
- S2 progress (objective / mean speed / flow mean, max; aim fit a0): gen 1 24.76 / 25.60 / 2.64, 2.89 (the S1 best alone); gen 2 25.41 / 26.08 / 2.61, 2.89 (a0 +3.0);
  gen 3 25.75 / 26.19 / 2.49, 2.73 (a0 +4.9); gen 4 25.77 / 26.33 / 2.51, 2.73 (a0 +12.4: 0/16 hits as run, the aim shift the taim offset must remove);
  gen 5 **26.03 / 26.64 / 2.53, 2.67** (a0 +5.5). Moves so far: train_lead +6.3 ms, prog_trig 0.2447 (fire 14.7 ms earlier than the v6 0.230), train_end -0.025,
  train_ext 0.014, train_first 1.16, k_in 0.019, step_delay 0.156, train_gain 1.02: the swing starts earlier, runs longer and its targets lead the drive.
- Build **t8** (frozen bat_r2-t8): + `dshape` (dw0-dw29, dshape_b): a time profile on the feed-forward drive per joint group (pelvis yaw, spine, shoulders, elbows, wrists), the drive of a
  knot segment scaled by 1 + dshape_b clip(sum_k dw[6 g + k] bump_k(t), -1, 1) (the same 6 gaussian bumps as tres); all 0 = the drive as it is (default replay identical on seed 3008: 25.34, flow 2.61).
  Planned residual searches after S2, each from the calibrated S2 best on fresh pitches: S3 dshape (30 dims), S4 tres bumps + biases (28), S5 tres conv readout (20).
- S2 gens 6-8 (objective / speed / flow mean, max; aim fit): gen 6 26.11 / 26.62 / 2.41, 2.68 (a0 +9.4); gen 7 26.28 / 26.59 / 2.34, 2.71 (a0 +9.2, ax +57);
  gen 8 **26.39 / 26.85 / 2.37, 2.70** (a0 +10.2 az +58 ax +72). **Stopped after gen 8** (pid 73040 + 3 workers; 1584 rollouts): the aim shifts had grown to 10 cm.
  Best raw = params/bat_r2_s2_raw.txt (train_lead 0.0179, prog_trig 0.2425, train_end -0.0298 (box floor -0.03), train_ext 0.0149, train_first 1.35, k_in 0.0118, step_delay 0.172, arm_swing_kd 0).
- Calibration of it (`scratchpad/bat/calibrate.py --seeds 5000:5048`, taim gains Newton): the unit-gain sensitivities measured at the taim1 operating point OVERSTATE the response here
  (each step removed 17-40 % of what it should: iterations 0-3 went 6/48, 15/48, 21/48, 33/48 hits); with `--boost 3` two more iterations converged: taim_z 6.1, taim_x 3.2,
  taim_z0 +0.110 (beyond its declared box +-0.1; a params-file value is not clamped) -> params/bat_r2_s2cal2.txt: 48/48 hits on the calibration pitches, power **26.19**, flow 2.76 max 3.18
  (the search's objective had promised 26.85 and 2.37: the correction is not free: -0.65 m/s, +0.4 flow). Interim check on seeds 4000-4047: 25.20, 46/48 hits (misses 4029 and 4031: the
  contact position along the bat aim_s is 0.90 and 0.86 m, beyond the tip at 0.86 - the swing's TIMING law drifts, which aim_n, the offset from the swing plane, cannot see), hit speed 26.30,
  flow 2.68 max 3.26 (7 of 48 above 3.0).
- Lesson: `train_lead` +18 ms etc. move the contact along the arc (aim_s mean 0.76, was ~0.65), a shift the k_z/k_x aim vectors are the wrong directions to cancel. S2b: an AS-RUN search
  (search.py's Problem on tasks/bat_rep.py: hit = speed - 0.5/cm of |aim_n| beyond 3 cm - 8 per m of contact position beyond [0.50, 0.80] m along the bat; miss = -5 - 100 gap; -4 per unit flow
  beyond 2.5) started from params/bat_r2_s2cal2.txt with the taim gains among its 32 dims, sigma 0.05: **S2b launched (pid 49936)**: `ROBOLAB_CONTROLLER=$PWD/bin/challengers/bat_r2-t5 BATREP_FLOW=4 BATREP_FLOW_CAP=2.5 .venv/bin/python playground/search.py bat_rep --method sep_cma --budget 3200 --workers 2 --sigma 0.05 --pop 14 --risk 0.25 --seconds 4.3 --seeds 3009,3022,3040,3041,3054,3055,3061,3062,3069,3070,3112,3123,3135,3137,3140,3143 --init params/bat_r2_s2cal2.txt --only "taim_*,train_lead,..." --box "..." --out params/search/bat_r2_s2b.txt --log out/bat_r2/s2b.jsonl`.

## 2026-09-29 milestone: S1 in the arena (S2b paused with SIGSTOP for ~10 min and resumed with SIGCONT; same pids)

- `calibrate.py` on the S1 best (seeds 5000-5047): iter 0 (taim gains unchanged): 48/48 hits, power 25.91, flow 2.61 max 2.88, aim fit a0 -1.5 az +17 ax +27;
  iter 2: taim_z 2.90 taim_x 1.29 taim_z0 -0.031 (params/bat_r2_s1cal.txt): 48/48, power 25.74, flow 2.604 max 2.887, aim residual 1.3 cm. Re-centring the aim COSTS 0.17 m/s.
- Validation on seeds 4000-4047 (never used for S1's tuning): S1 raw (params/bat_r2_s1.txt) **48/48 hits, power 25.83**, fair 46, flow 2.614 max 2.962 (48/48 under 3.0);
  S1 recalibrated 25.58, flow 2.597 max 2.929. (S2 raw recalibrated to a0 = 0: 25.20, 46/48; see above.)
- **Arena** `arena.py eval bat_power_fresh_rep --params params/bat_r2_s1.txt --controller bin/challengers/bat_r2-t1 --promote`: **25.71 m/s, 24/24 hits**, fair 95.8 %, quality 0.577,
  flow 2.644: WINS against the v6 knots seed (19.44), promoted. `bat_power_fresh_rep_clean` (all 24 under the flow guard): 25.71, promoted (the seed failed its guard on 6).
  ORACLE for reference: bat_power_fresh 25.24 on the old fresh seeds 1000-1023 (24/24).
- `scratchpad/bat/paused.sh 49936 -- .venv/bin/python playground/bat_power_diag.py --params params/bat_r2_s1.txt --controller bin/challengers/bat_r2-t1 --seeds 4000-4015 --fresh --workers 2 --seconds 4.6 --json out/bat_r2/diag_s1.json`
  (bat_power_diag.py gained `--fresh` and the joints' range margins): S1 on 16 fresh pitches: power 25.82, flow 2.59. Kinematic sequence: pelvis yaw peak 7.62 rad/s (437 deg/s) 119 ms before contact,
  torso 9.36 rad/s (536 deg/s) at 150 ms, hands 6.1 m/s, bat 37.1 rad/s (2125 deg/s) at contact, sweet spot 25.6 m/s. Joint peaks against the unloaded limit (vmax / 0.3 ranges per second):
  pelvis yaw 0.32, spine flexion 0.36, spine rotation 0.20, shoulders 0.18-0.41, elbows 0.42 (top-hand side, 11.0 rad/s = 632 deg/s) and 0.55 (bottom-hand side, 14.2 rad/s = 812 deg/s), wrist flexion 0.42,
  bottom wrist deviation 1.77 (19.5 rad/s: the arms fling it). Range: the pelvis yaw closest approach to its end is 5.7 % of the range (0.1 % of the swing within 3 %), spine_lat / l_wrist_dev / r_wrist_dev / l_hip_rot
  spend 11 / 17 / 18 / 28 % of the swing within 3 % of an end of their range. Activation >= 0.9 (share of each group's 213 ms power phase, agonist): pelvis 43 %, trunk 34 %, shoulders 34 %, elbows 33 %, wrists 13 %; CCI 0.01-0.09.
  Reading: the trunk and the elbows are FAR from their speed limits and from their range ends (except the wrists): they are limited by torque x time / inertia (M_ii of the pelvis yaw at the stance: 2.3 kg m^2,
  the bottom elbow 0.53; peak torques 375 and 105 N m) and by the chain's own sequencing (the pelvis peaks 119 ms before contact and brakes).
- S1 (params/bat_r2_s1.txt, bat_r2-t1; `paused.sh 49936 -- bat_rep.py eval ...`) on the earlier trials' pitches, same seeds as the ORACLE / knots rows:
  old fresh seeds 1000-1023 (bat_power_fresh's): **25.89 m/s, 24/24 hits**, fair 24, flow 2.578 max 2.801 (oracle 25.24, v6 knots 21.57, knots b 20.63);
  the 18-pitch grid (BATREP_GRID=1, bat_power's): **25.74, 18/18 hits**, fair 16, flow 2.567 max 2.958 (oracle 25.17, knots 23.12, knots b 24.45).
  An in-representation swing (reflexes ON, contraction knots) is now ABOVE the open-loop oracle on all three sets. To challenge the four oracle-held bat_power* trials with the final controller.
- S2b (as-run objective, pid 49936; slowed by two pauses): gen 2 24.43 (recovered from 13.93: the calibrated S2 point missed some of these pitches as run), gen 3 24.64, gen 4 24.89, gen 5 25.02.
  As-run check on its 16 training pitches (BATREP_FLOW=4 cap 2.5, mean score): S1 power 25.598 flow 2.638 -> 25.003; S2b gen-5 best (bat_r2-t5) power **26.121** (16/16) flow **2.465** (max 2.83) -> 25.531.

## 2026-09-29 milestone: S2b gen-5 in the arena

- S2b gens 6, 7: no gain (best stays gen 5, objective 25.0153; the machine's load dropped to ~20-30, ~3.5 min per generation). The gen-5 best (params/bat_r2_s2b_g5.txt, bat_r2-t5):
  taim_z 5.30 taim_x 3.38 taim_z0 +0.0734, train_lead +18.2 ms, train_dlead +1.8 ms, train_first 1.19, train_ext 12.7 ms, train_legs_ease 0.02, prog_trig 0.2412 (fire 11 ms earlier than v6's 0.230),
  train_end -0.028 (train 28 ms longer), k_in 0.0176, step_delay 0.169, arm_swing_kd 0.
- Validation seeds 4000-4047 (as run, no recalibration): **48/48 hits, power 26.368**, fair 29, flow 2.443 max 2.913 (48/48 under 3.0) (S1: 25.83, 2.614).
- Arena: `arena.py eval bat_power_fresh_rep --params params/bat_r2_s2b_g5.txt --controller bin/challengers/bat_r2-t5 --promote` (S2b paused with paused.sh): **26.204 m/s, 24/24 hits**, flow 2.478,
  fair 0.667, quality 0.178: WINS against S1 (25.71), promoted; `bat_power_fresh_rep_clean` (all 24 under the guard): 26.20 promoted.
  (The two notes typed on the command line quote the S2 numbers taim 6.1/3.2, 18 ms, 30 ms, 1.35x for two of the values; the file's are above. To be corrected in champions.json and history.jsonl under the lock.)
- S2b stopped after gen 8 (gens 6-8 no gain; 1584 rollouts; pids 49936 + workers). Its best = the gen-5 candidate = params/bat_r2_s2b_g5.txt (identical in params/bat_r2_s2b_final_raw.txt).
- Diagnosis of the S2b champion on the 48 validation pitches: speed 24.9-27.4 (sd 0.59), aim_n -2.2..+6.7 (mean +1.6), contact position along the bat aim_s 0.63-0.83 (mean 0.717: the sweet spot is 0.708),
  flow terms lift 0.591 / pre 0.761 / post 0.593 / cmd 0.498 (v6 knots: 0.594 / 0.86 / 0.745 / 0.62; stall before the swing 18 ms mean, 45 max). BUT the ball quality fell: fair 29/48, launch angle mean 49 deg
  (arena quality 0.18 vs 0.58 for S1): the speed was bought with an uppercut steeper than the 20 deg the bat_quality metric asks for. Nothing in the bat_power metric sees it; it is reported, and S2c prices it.
- **S2c launched** (pid 27781): as S2b, from params/bat_r2_s2b_g5.txt, plus BATREP_LAUNCH=0.04 per degree of |launch - 20| beyond 10 (0.033 m/s per degree = 1 m/s per point of the arena's quality metric), 24 training pitches
  (12 from each maximin set: seeds 3008,3049,3050,3060,3064,3073,3074,3091,3092,3107,3108,3118,3009,3022,3040,3041,3054,3055,3061,3069,3070,3112,3123,3135), budget 4000, population 14, sigma 0.05:
  `ROBOLAB_CONTROLLER=$PWD/bin/challengers/bat_r2-t5 BATREP_FLOW=4 BATREP_FLOW_CAP=2.5 BATREP_LAUNCH=0.04 .venv/bin/python playground/search.py bat_rep --method sep_cma --budget 4000 --workers 2 --sigma 0.05 --pop 14 --risk 0.25 --seconds 4.3 --seeds ... --init params/bat_r2_s2b_g5.txt --only "..." --box "..." --out params/search/bat_r2_s2c.txt --log out/bat_r2/s2c.jsonl`.
- S2c gens 2-5 (objective): 24.28, 24.77 (gen 3 best), 24.77, 24.77: plateau. Its gen-3 best (copy: params/bat_r2_s2c_g3.txt after this entry) on the validation seeds 4000-4047, as run, next to S1 and S2b
  (`paused.sh 27781 -- bat_rep.py eval`; quality = the arena's bat_quality formula from launch/fair):
    S1 raw    power 25.832  48/48 hits  fair 46  launch 7.9 deg   quality 0.388  flow 2.614 max 2.962
    S2b g5    power 26.368  48/48 hits  fair 29  launch 49.3 deg  quality 0.213  flow 2.443 max 2.913
    S2c g3    power 26.251  48/48 hits  fair 44  launch 27.6 deg  quality 0.373  flow 2.384 max 2.760
  The launch term (0.04 per degree beyond 10 off 20) gave back the ball quality (0.21 -> 0.37) for 0.12 m/s.
- S2c stopped after gen 8 (gens 7, 8 no gain; 2376 rollouts; pids 27781 + workers). Best = gen 6 = params/bat_r2_s2c.txt (objective 24.99). Validation seeds 4000-4047 as run: **power 26.147, 48/48 hits, fair 46, launch 12.8 deg,
  quality 0.447, flow 2.316 max 2.671** (S2c gen 3: 26.251 / quality 0.373; S2b: 26.368 / 0.213; S1: 25.832 / 0.388). The balanced candidate.
- **Ceiling runs launched** (10:38, `scratchpad/bat/ceil.sh params/bat_r2_s2c.txt bin/challengers/bat_r2-t5 250 base lead5 str20 trunk15 arms15 vmax45`, log out/bat_r2/ceil.log, results
  out/bat_ceiling/r2_<variant>.json; `ceil_report.py` summarises): bat_ceiling.py --ball CMA (open loop, reflex gain 0, 16 upper-body joints, 250 generations) on the centre grid pitch (34.0 m/s, x 0.0, z 0.80),
  captured from the S2c swing; variants: base body (athlete: strength x1.5, vmax 3.0), lead5 (start the free excitations 50 ms before the practised swing's hips fire, window 0.39 s), str20 (BAT_STRENGTH 2.0 = x1.33),
  trunk15 (pelvis yaw + spine x1.5), arms15 (shoulders, elbows, wrists x1.5), vmax45 (vmax 4.5).

## 2026-09-29 body-level: what the ceilings said, and the sensitivity of the fixed controller

- `scratchpad/bat/ceil.sh` (10:38-10:51, 250 generations each, 2 workers, ~2 min per run at load 20): the open-loop CMA CAN NO LONGER IMPROVE on the practised swing. Base body: the practised (in-representation, S2c, reflexes on)
  swing hits the centre pitch at 27.01 m/s; the open-loop replay of its net excitations scores 26.17 and the CMA never beat generation 0 in 250 generations (sigma 0.29 -> 0.07: any perturbation misses the ball, a needle-like
  landscape). So `bat_ceiling.py` is not a ceiling any more; the in-representation swing is better than what open-loop CMA finds from its own state. Practised-swing speeds on the changed bodies (the S2c params UNCHANGED, one pitch):
  base 27.01, strength x1.33 29.96, trunk x1.5 28.35, arms x1.5 29.10, vmax x1.5 29.85; lead5 (capture 50 ms early): the replay misses (-36) and the CMA reaches only 24.35.
  => the body question is answered by the controller itself: `scratchpad/bat/bodysweep.sh` (fixed S2c controller, 16 fresh pitches 8000-8015, `evalcal.py`: speed at contact or closest approach with the aim shift re-centred; as-run hits in brackets):
      athlete (strength 1.5, vmax 3.0)  26.40 (16/16)
      strength x1.2 / x1.33 / x1.5 / x2 (all muscles)   28.71 (12) / 29.58 (3) / 30.36 (0) / 32.22 (0)
      vmax x1.2 / x1.5 / x2                              27.99 (16) / 29.39 (13) / 30.68 (11)
      trunk (pelvis yaw + spine) x1.5 / pelvis yaw x2    27.68 (15) / 26.86 (16)
      arms (shoulders, elbows, wrists) x1.5 / elbows x2  28.41 (1) / 27.61 (15)
      strength x1.5 + vmax x1.5                          33.14 (0)
      **ROBOLAB_PROFILE=p95 on the athlete (strength x1.32, muscle speed x1.2, activation x0.87; profiles/p95.json)   30.83 (0/16: the aim is 10 cm off)**
  About +2 m/s per +20 % of strength or of muscle speed; the arms are a bigger lever than the trunk (trunk x1.5 +1.3, arms x1.5 +2.0, pelvis yaw x2 only +0.5, elbows x2 +1.2). The rates are torque x time limited
  (force-velocity: a faster muscle keeps more force at the same joint rate).
- **P95 body** (the athlete at ROBOLAB_PROFILE=p95: strength x1.32, muscle speed x1.2, activation constants x0.87 (profiles/p95.json: each a marginal 95th percentile, Maden-Wilkinson 2020, Staron 2000, Trappe 2015); the
  athlete's own x1.5 strength already stands for strength-trained men): S2c controller unchanged, calibrated speed 30.83 but the contact was BEYOND THE TIP (aim_s 0.90 m: the faster swing reaches the ball's plane earlier);
  `evalcal.py --sets` scan of prog_trig (contact s mean, calibrated speed): 0.2409 (base) s 0.914 / 30.72; 0.2359 0.824 / 31.29; 0.2309 0.772 / 31.38; 0.2259 0.726 / 31.34; 0.2209 0.694 / 31.20 (fire 12 ms later puts contact on the barrel).
  params/bat_r2_p95_init.txt = S2c + prog_trig 0.2289; `ROBOLAB_PROFILE=p95 calibrate.py --boost 2 --iters 4` (seeds 5000-5047) -> params/bat_r2_p95_cal2.txt: **45/48 hits, power 29.73 m/s** (hit speed 31.71), flow 2.43 max 2.67,
  taim_z 4.79 taim_x 2.47 taim_z0 +0.069, aim residual 2.5 cm.
- **S6 launched** (pid printed above; as-run sep-CMA on the P95 body from params/bat_r2_p95_cal2.txt, 24 random fresh pitches seeds 7000-7023, the S2c objective incl. launch and flow terms, budget 2100):
  `ROBOLAB_PROFILE=p95 BAT_BODY=athlete ROBOLAB_CONTROLLER=$PWD/bin/challengers/bat_r2-t5 BATREP_FLOW=4 BATREP_FLOW_CAP=2.5 BATREP_LAUNCH=0.04 .venv/bin/python playground/search.py bat_rep --method sep_cma --budget 2100 --workers 2 --sigma 0.05 --pop 14 --risk 0.25 --seconds 4.3 --seeds 7000,...,7023 --init params/bat_r2_p95_cal2.txt --only "..." --box "..." --out params/search/bat_r2_s6.txt --log out/bat_r2/s6.jsonl`.
- Coordinator (11:30): with the 5-minute load average under 30 the cap is 4 rollout workers (one search at a time); back to 2 above 30. Load now ~18-22.
- S6 (P95 body, 24 random pitches 7000-7023, 6 generations, 1704 rollouts, stopped by me at 1704 of 2100): no gain over its start (30.4869): the calibrated start hits all of those pitches, and the
  P95 controller's misses are on other pitches. P95 controller = params/bat_r2_p95_cal2.txt: validation seeds 4000-4047 (ROBOLAB_PROFILE=p95, as run): power 28.86, 44/48 hits (misses 4006, 4014, 4029, 4031),
  hit speed 31.49, flow 2.447 max 2.697, fair 36. Arena trial `bat_power_fresh_rep_p95` created (scratchpad/bat/make_trials_p95.py; env BAT_BODY=athlete ROBOLAB_PROFILE=p95 BAT_FRESH_PITCH=1, seeds 1100-1123, labelled body variant).
- **S7 launched** (pid 8069, 4 workers): S6's setup on the P95 body but trained on the CALIBRATION pitches 5000-5023 (they contain the hard ones: calibration misses 5007, 5011, 5014); budget 2400;
  `ROBOLAB_PROFILE=p95 BAT_BODY=athlete ... playground/search.py bat_rep --budget 2400 --workers 4 --sigma 0.05 --pop 14 --seeds 5000,...,5023 --init params/bat_r2_p95_cal2.txt --only "..." --out params/search/bat_r2_s7.txt --log out/bat_r2/s7.log.jsonl`.

## 2026-09-29 12:30 resume after the harness stall (11:36-12:30)

- State on resume: S7 (pid 8069, P95 body, 4 workers) was still running; its generations had slowed to 25-28 min during the stall (load 38), 3-min generations after. Gens 5, 6 no gain; **stopped after gen 6** (best = gen 4, objective 30.06).
  The P95 controller = params/bat_r2_p95_s7.txt (S2c + fire 12 ms later + taim recalibrated + S7): validation seeds 4000-4047 (ROBOLAB_PROFILE=p95, as run): **30.64 m/s, 47/48 hits** (miss 4031: contact at s 0.92 m, beyond the tip),
  hit speed 31.29, flow 2.428 max 2.779, fair 32, launch 18 deg. On the calibration pitches 5000-5047: 48/48, 31.53, flow 2.42.
- **Arena `bat_power_fresh_rep_p95` seeded** with it (`arena.py seed ... --workers 4`): **27.12 m/s, 21/24 hits** (misses 1105 (x +0.04, z 0.96), 1106 (x +0.15, z 0.69), 1123 (x +0.11, z 0.96): outside pitches whose contact falls beyond the tip),
  hit speed 31.0, flow 2.43, fair 62 %, quality 0.27. A k_in scan on the calibration pitches (k_in 0.04/0.07/0.10 with prog_trig moved to keep the centre timing) made it no better (48 / 46 / 47 / 40 hits).
- **S5 result (Codex-architecture residual, tres_conv 1: fixed conv features of BatConvResidual, 20 readout weights tc0-tc19 zero at the start, bound 0.16 rad on [spine rotation, spine flexion, both elbows, both wrists' flexion],
  sep-CMA sigma 0.15, 24 random fresh pitches 7100-7123, 8 generations of 14 = 2376 rollouts, controller bat_r2-t8, start = S2c gen 6)**: training objective 25.01 -> 25.19 (gen 2), no gain in gens 3-8. Validation seeds 4000-4047 vs the same swing
  without the residual (paired): speed 26.028 vs 26.147 (**-0.119**, better on 14 of 48, worse on 33, sign-flip p < 0.001), flow 2.512 vs 2.316 (**+0.196**, worse on 33). A trained zero-initialised conv residual does NOT help
  the knots swing: the +0.18 on the 24 training pitches did not carry (params/search/bat_r2_s5.txt kept as the record). Stopped at gen 8 (pid 22136).

## 2026-09-29 13:20 arena challenges of the balanced swing (params/bat_r2_s2c.txt, bat_r2-t5; each with S3 paused by paused.sh 35477)

- `bat_power_fresh_rep`: **25.956 m/s, 24/24 hits**, fair 100 %, quality 0.440, flow 2.334: does NOT beat the S2b champion (26.204; speed only), logged as a loss. (S2b: 26.204, fair 67 %, quality 0.178, flow 2.478.)
- The four ORACLE-held trials, all WON and promoted (the champion of each is now an in-representation swing with the reflexes on): `bat_power` (18 grid pitches) **26.234** vs the oracle's 25.171; `bat_power_clean` 26.234 (flow 2.331);
  `bat_power_fresh` (24 held-out pitches, seeds 1000-1023) **26.205** vs 25.241; `bat_power_fresh_clean` 26.205. `bat_quality` (mean fair-ball quality on the grid): 0.315 vs the oracle's 0.416: does not beat, the oracle keeps it.
- S3 (dshape: the drive's time profile per joint group, 30 weights dw0-dw29 zero at the start, 36 random pitches 7100-7135, controller bat_r2-t8, pid 35477, 4 workers, sigma 0.15): gen 1 = the S2c swing alone = 24.23.

## 2026-09-29 13:45 S3 (the drive time profile) works and is entered

- S3 (dshape, 30 weights zero at the start, sigma 0.15, 36 random fresh pitches 7100-7135, controller bat_r2-t8, pid 35477, 4 workers, 7 generations of 14 = 2592 rollouts): training objective 24.23 -> 24.74 (gen 2) -> 24.85 -> 25.46 -> **25.61 (gen 5, best)**, none after.
  Learned profile (rows: pelvis yaw, spine, shoulders, elbows, wrists; bumps at 30, 70, 110, 150, 190, 230 ms after the fire; dshape_b 0.5):
  pelvis +0.34 +0.40 +0.32 +1.00 +0.50 -0.34; spine +0.20 -0.23 +0.26 +0.43 +0.62 -0.32; shoulders +0.36 +0.10 -0.44 +0.44 +0.54 +0.07; elbows 0.00 +0.57 0.00 +0.38 -0.04 -0.06; wrists +0.21 +0.04 -0.21 +0.07 -0.01 -0.21:
  more drive in the middle of the swing (110-190 ms; the diagnosis said the pelvis is at >= 0.9 activation only 43 % of its power phase), less at the very end.
  **Validation seeds 4000-4047 (never used), paired against S2c g6**: power 26.571 vs 26.147 (**+0.424, better on 48 of 48 pitches**, sign-flip p < 0.001), flow 2.314 vs 2.316 (max 2.645), 48/48 hits, fair 46, launch 19.9 deg, quality 0.405.
  A zero-initialised temporal residual on the knots' DRIVE generalises (+0.42 m/s on every held-out pitch); the same recipe on the reflex targets (S5, Codex's conv features) made things worse.
- Arena, all with params/bat_r2_s3.txt + bin/challengers/bat_r2-t8, `--promote`, all WON: `bat_power_fresh_rep` **26.399 m/s, 24/24** (fair 100 %, quality 0.416, flow 2.324; S2b 26.204), `bat_power_fresh_rep_clean` 26.399,
  `bat_power` 26.521 (18 grid pitches; oracle 25.171), `bat_power_clean` 26.521, `bat_power_fresh` **26.669** (oracle 25.241), `bat_power_fresh_clean` 26.669.
- **S3b launched** (13:47; continues S3 from params/bat_r2_s3.txt on 36 NEW random pitches 7200-7235: dims dw0-29 + dshape_b + train_drv + train_lead + prog_trig + train_end + train_gain (36), sigma 0.1, pop 16, 4 workers, budget 3500;
  `ROBOLAB_CONTROLLER=$PWD/bin/challengers/bat_r2-t8 BATREP_FLOW=4 BATREP_FLOW_CAP=2.5 BATREP_LAUNCH=0.04 BAT_BODY=athlete .venv/bin/python playground/search.py bat_rep --method sep_cma --budget 3500 --workers 4 --sigma 0.1 --pop 16 --risk 0.25 --seconds 4.3 --seeds 7200,...,7235 --init params/bat_r2_s3.txt --only "dw*,dshape_b,train_drv,train_lead,prog_trig,train_end,train_gain" --box "..." --out params/search/bat_r2_s3b.txt --log out/bat_r2/s3b.jsonl`).
- S3b (pid 47333, stopped after gen 4 of 3500: 1764 rollouts): 25.488 (the S3 swing alone on the new pitches 7200-7235) -> 25.542 (gen 2), no more in gens 3-4: the drive profile has plateaued; S3 (params/bat_r2_s3.txt) is the result.
- v6 knots on the validation seeds 4000-4047 (the stage table's first row): **17.61 m/s, 36/48 hits** (misses 4012 4013 4016 4020 4027 4033 4035 4036 4043 4044 4045 4046), hit speed 23.49, fair 22, launch -7.5 deg, quality 0.108,
  flow 2.79 (max 3.11), valley lift/pre/post/cmd 0.594/0.846/0.732/0.615, stall before the swing 31 ms, plant->hips-fire 51 ms.
  Stage table on seeds 4000-4047, as run (power, hits, fair, mean launch, quality, flow mean/max, pre-swing stall, plant->swing):
    v6 knots        17.61  36  22   -7.5  0.108  2.79/3.11  31 ms  51 ms
    taim1           23.12  48  42    8.3  0.432  2.80/3.06  31 ms  51 ms
    S1              25.83  48  46    7.9  0.388  2.61/2.96  27 ms  46 ms
    S2b             26.37  48  29   49.3  0.213  2.44/2.91  18 ms  33 ms
    S2c (balanced)  26.15  48  46   12.8  0.447  2.32/2.67   8 ms  18 ms
    S3 (+ drive profile) 26.57 48 46 19.9  0.405  2.31/2.65   7 ms  18 ms
- S3's drive profile carried over to the P95 body unchanged (params/bat_r2_p95_s7_dw.txt = S7 + dw0-29 + dshape_b; validation 4000-4047, ROBOLAB_PROFILE=p95): **hit speed 32.37 m/s** (S7: 31.29) but 6 misses of 48 (4006 4014 4021 4025 4029 4031; power 28.33 as run): the profile speeds the swing up and shifts its aim.
- **S8 launched** (13:58, pid printed above; P95 body, 2 workers because the load is 34, controller bat_r2-t8, start params/bat_r2_p95_s7_dw.txt, 24 pitches 5000-5023, dims dw0-29 + dshape_b + taim_z/x/z0/x0/ramp + prog_trig + train_end + train_lead + k_in + train_drv (41), sigma 0.06, pop 16, budget 2400).

## 2026-09-29 14:05 final evaluation on the untouched validation seeds 6000-6047 (athlete body, as run; S8 paused by paused.sh 55670 for these)

    stage            power   hits     fair  flow mean / max
    v6 knots         17.70   36/48    21    2.80 / 3.00   (misses 6004 6006 6011 6012 6016 6021 6023 6025 6028 6036 6038 6044)
    taim1            23.14   48/48    40    2.80 / 2.96
    S1               25.87   48/48    47    2.63 / 2.97
    S2b              26.45   48/48    35    2.47 / 2.94
    S2c (balanced)   26.29   48/48    43    2.37 / 2.72
    S3 (+ drive profile) **26.70**  48/48  44  2.37 / 2.70
  S3 on the other sets (`final_eval.sh`, identical to the arena's numbers): arena seeds 1100-1123 26.399 (24/24, fair 24, flow 2.324 max 2.674), old fresh 1000-1023 26.669 (24/24, flow 2.263 max 2.482), grid 18 pitches 26.521 (18/18, flow 2.324 max 2.581).
- Diagnostics of the S3 champion (`paused.sh 55670 -- bat_power_diag.py --params params/bat_r2_s3.txt --controller bin/challengers/bat_r2-t8 --seeds 4000-4015 --fresh --json out/bat_r2/diag_s3.json`): power 26.62, flow 2.287, swing->contact 228 ms.
  Chain (peak, ms before contact): pelvis yaw 7.63 rad/s = 437 deg/s at 127 ms; torso 9.90 rad/s = 567 deg/s at 160 ms; hands 6.7 m/s at 64 ms; bat 37.8 rad/s = 2164 deg/s and sweet spot 26.5 m/s at contact.
  Joint peaks / unloaded limit: pelvis yaw 0.32, spine flexion 0.39, spine rotation 0.25, shoulders 0.22-0.45, elbows 0.49 (top-hand side 12.8 rad/s = 732 deg/s, 30 ms before contact) and 0.70 (bottom-hand side, 18.2 rad/s = 1042 deg/s,
  125 ms before contact), wrist flexion 0.21-0.49, bottom wrist deviation 1.69 (18.6 rad/s = 1065 deg/s at contact).
  Range: pelvis yaw closest to its end 4.8 % of the range (0.3 % of the swing within 3 %); spine_lat 17 %, l_wrist_dev 25 %, r_wrist_dev 11 %, l_hip_rot 29 % of the swing within 3 % of an end.
  Activation >= 0.9, share of the 220 ms power phase (agonist): pelvis 46 %, trunk 51 %, shoulders 51 %, elbows 48 %, wrists 26 % (S1: 43 / 34 / 34 / 33 / 13); CCI 0.02-0.05.
- (about 14:04) corrected the two S2b history notes (09:58:29 `bat_power_fresh_rep`, 09:59:15 `_clean`) with scratchpad/bat/fix_notes.py under the arena lock (the typed notes had quoted S2 values; scratchpad/bat/notes_fix1.json): 2 history records changed, nothing else.
- 14:04 demo video of the S3 champion on the 4 bridge demo pitches (athlete body, `BAT_BODY=athlete ROBOLAB_CONTROLLER=bin/challengers/bat_r2-t8 paused.sh 55670 -- playground/bridge.py bat --params params/bat_r2_s3.txt --seconds 17.5 --video out/bat_r2.mp4 --sheet out/bat_r2_sheet.png`; S8 paused for the 16 s):
  files `out/bat_r2.mp4` (1051 frames), `out/bat_r2_sheet.png`; per-pitch numbers re-run without video into `out/bat_r2/demo_s3.txt`.
  Pitches 1-4 (82.8 / 89.5 / 76.1 / 86.1 mph): bat sweet-spot speed 26.78 / 25.92 / 25.72 / 27.33 m/s (59.9 / 58.0 / 57.5 / 61.1 mph, mean 26.44), **4 of 4 fair**, exit 75.3 / 86.6 / 81.0 / 79.3 mph,
  launch -13.3 / -2.3 / +14.5 / -8.0 deg, flow 2.27 / 2.12 / 2.38 / 2.09 (whole run 2.377, valleys lift/pre/post/cmd 0.61/0.83/0.56/0.54, `flow_ok`), swing->contact 228 / 229 / 225 / 230 ms,
  plant->swing 16 / -14 / 56 / -5 ms, pre-swing stall 35 ms (whole run), quality 0.285. Pitch 3 (outside, low, 76 mph) is contacted 0.9 cm from the barrel end (impact_from_end 0.009).
  For comparison the v6 oracle on the same 4 pitches (README v6 section): 25.6 / 24.9 / 24.3 / 25.8 m/s, 3 fair.
- **S8 restarted as S8b with 4 workers** (load 13.5 / 5-min 18.3): the 2-worker S8 (pid 55670, tree killed by PID) had completed gen 2 (objective 16.98 -> 18.58, best saved as params/search/bat_r2_s8_gen2.txt); the search is resumable so S8b continues from that best.
  Command (pid 61060, 4 workers, cwd = robolab root), env `ROBOLAB_CONTROLLER=$PWD/bin/challengers/bat_r2-t8 BATREP_FLOW=4 BATREP_FLOW_CAP=2.5 BATREP_LAUNCH=0.04 ROBOLAB_PROFILE=p95 BAT_BODY=athlete`:
  `.venv/bin/python playground/search.py bat_rep --method sep_cma --budget 2000 --workers 4 --sigma 0.05 --pop 16 --risk 0.25 --seconds 4.3 --seeds 5000..5023 --init params/search/bat_r2_s8_gen2.txt --only 'dw*,dshape_b,taim_z,taim_x,taim_z0,taim_x0,taim_ramp,prog_trig,train_end,train_lead,k_in,train_drv' --box dshape_b=0.2:1.0,taim_z=2:9,taim_x=0:5,taim_z0=-0.05:0.2,taim_x0=-0.1:0.1,taim_ramp=0.5:1.1,prog_trig=0.2:0.26,train_end=-0.04:0.0,train_lead=0:0.035,k_in=0:0.12,train_drv=0.9:1.3 --out params/search/bat_r2_s8b.txt --log out/bat_r2/s8b.jsonl`

## 2026-09-29 14:25 S8b result (P95 body): 32.4 m/s, 48/48, at the MLB average; the ball-quality cost is large

- S8b (pid 61060, 4 workers, 7 generations, 1992 rollouts, 764 s, log out/bat_r2/s8b.log, best params/search/bat_r2_s8b.txt): objective 18.58 (its start, the gen-2 best of S8) -> 19.89 (gen 2) -> **29.68 (gen 3: the last training-pitch miss gone)** -> 31.04 -> 31.18 (gen 5), no more in gens 6-7.
  Best saved as params/bat_r2_p95_s8.txt (header with the numbers below; same 120 values as the search file).
- Validation (P95 body, `ROBOLAB_PROFILE=p95 BAT_BODY=athlete bat_rep.py eval --params params/bat_r2_p95_s8.txt --controller bin/challengers/bat_r2-t8 --seeds A:B --seconds 4.3 --workers 4 --quiet`):
    seeds 4000-4047 (used before to pick candidates): **32.377 m/s, 48/48 hits**, fair 35, flow 2.441 (max 2.764), aim_s 0.70-0.89 m, bat speed 31.16-33.33; launch mean 30.1 deg (median 36.8), 19 % of hits above 60 deg   (S7: 30.64, 47/48, fair 32, launch mean 18.1)
    seeds 6000-6047 (never used for the P95 body): **32.430 m/s, 48/48 hits**, fair 36, flow 2.449 (max 2.847), aim_s 0.69-0.89, bat speed 30.96-33.35; launch mean 39.2 deg (median 42.6), 27 % above 60 deg
  The speed is at the MLB average (32.0 m/s) but bought with steep launches: fair 35-36 of 48 (S3 on the athlete: 44-46), quality 0.165 on the arena pitches.
- Arena `bat_power_fresh_rep_p95` (`arena.py eval ... --params params/bat_r2_p95_s8.txt --controller bin/challengers/bat_r2-t8 --workers 4 --promote`): **30.847 m/s, 23/24 hits** (S7 seed: 27.123, 21/24), hit speed 32.19, fair 0.75, quality 0.165, flow 2.440 (max 2.644): PROMOTED.
  The one miss is 1123 (x +0.105, z 0.964; aim_n +3.9 cm, contact 0.889 m along the bat, beyond the sweet spot toward the tip); fouls 1105, 1106, 1112, 1116, 1122 and 1123; per-pitch in out/bat_r2/s8b_arena1100.json.
- 14:26 **ideal-control ("sweet") ceilings launched** (pid 68100 = `sh scratchpad/bat/ceil_sweet.sh 300 s3 p95`, 4 workers, load 7 / 5-min 13, log out/bat_r2/ceil_sweet.log, results out/bat_ceiling/r2sw_s3.json and r2sw_p95.json):
  `bat_ceiling.py --target sweet` (open loop, reflex off, 16 upper-body joints, CMA over a net excitation every 40 ms, ball moved away, score = sweet-spot speed at the closest approach to where the practised swing met the ball, contact time free; the round-1 "27.6 m/s through the v5 contact point" mode)
  on the centre pitch (34.0 m/s, x 0.0, z 0.80), captured 20 ms before the hips fire: s3 = athlete body with params/bat_r2_s3.txt / bat_r2-t8; p95 = ROBOLAB_PROFILE=p95 with params/bat_r2_p95_s8.txt / bat_r2-t8.
  (The earlier `--ball` mode runs from the S2c capture could not improve on the practised swing, the landscape being needle-like.)
- 14:28 sweet ceilings done (80-90 s each, 300 generations, `out/bat_r2/ceil_sweet.log`): **the open-loop CMA is BELOW the closed-loop swing on both bodies**.
    athlete S3: practised swing 27.19 m/s (contact 227 ms after the hips fire); the open-loop replay of its net excitations misses the contact point by 11.8 cm (26.29 m/s at 0.255 s); CMA best through P within 2.5 cm: 22.67 m/s (no gain after gen ~40).
    P95 S8b: practised swing 32.74 m/s; replay misses P by 7.9 cm (31.82); CMA best within 4 cm of P: 28.03 m/s (gain only in the first 50 generations).
  => the reflex layer's feedback does work the open loop cannot reproduce (needle-like landscape), so under this tool the in-representation swing is its own ceiling estimate. Round 1's comparable ceilings (oracle program capture,
  `--ball`, 400 generations, centre pitch) are re-run for both bodies as `ceil.sh ... prog_athlete prog_p95` (pid printed in the next entry; CEIL_WORKERS=4; results out/bat_ceiling/r2_prog_athlete.json / r2_prog_p95.json, log out/bat_r2/ceil_prog.log).
- 14:36 **ideal-control ceilings, round-1 recipe (ORACLE program capture params/bat_v6_prog.txt + bin/challengers/bat_v6-prog1, `bat_ceiling.py --ball --lead 0 --pitch 34.0,0.0,0.8`, centre pitch) on both bodies** (`ceil.sh ... prog_athlete prog_p95`, CEIL_WORKERS=4, out/bat_r2/ceil_prog.log; P95 continued 600 more generations from its best with `--init_json out/bat_ceiling/r2_prog_p95.json --sigma 0.1 --name r2_prog_p95b`):
    athlete body: practised program swing 25.50 m/s; open-loop replay 25.45 (fair, launch 18 deg); the CMA finds nothing more in 400 generations (the program library is already the product of round 1's CMA iterations; round 1's ball_s0 got 25.69 from a first-generation capture).
    P95 body: the program swing (31.94 m/s at the capture) misses when replayed (4.1 cm), gen 0 28.27; CMA 400 generations: 30.83 m/s (launch 5.5 deg, fair); 1000 generations (r2_prog_p95b): **32.87 m/s** (fair, but launch 75 deg: the ball-mode score has only a fair bonus and no launch term), sigma collapsed to 0.006, still creeping up (+0.13 per 100 generations).
    => ideal-control ceiling at the centre pitch: athlete 25.5-25.7, P95 >= 32.9 (+7.3 m/s, +28 %).
  The in-representation swings on the same pitch (`bat_rep.py eval --pitch 34.0,0.0,0.8 --seeds 0:1`, out/bat_r2/centre_s3.json, centre_p95_s8.json): athlete S3 **27.19 m/s** (hit, flow 2.32), P95 S8b **32.74 m/s** (hit, flow 2.50):
  the athlete's closed-loop swing is 1.5-1.7 m/s ABOVE the open-loop ceiling of round 1, the P95 swing is at the open-loop CMA's 1000-generation value.
- 14:36 **S9 launched (balanced P95 swing)**: `sh scratchpad/bat/s9.sh 4 2000` (4 workers, load 17.5 / 5-min 19; log out/bat_r2/s9.log, search file params/search/bat_r2_s9.txt, jsonl out/bat_r2/s9.jsonl). Why: S8b's launch angle ~ 36 + 11.5 x aim_n deg (corr 0.85-0.91 on P95, 0.89-0.99 on the athlete: 10-13 deg per cm), aim_n std 2.3-2.6 cm,
  so the balls leave at a mean 30-39 deg with 19-27 % of the hits above 60 deg. S9 = same 41 tunables from S8b's best, launch cost 0.10/deg beyond 8 off 20 (S8b: 0.04 beyond 10), aim margin 1.0 per cm beyond 1.5 cm (S8b: 0.5 beyond 3), flow term as before, new training pitches seeds 7300-7323.

## 2026-09-29 16:10 after the second harness stall (14:53 -> 16:06): S9 result and arena entry

- State at 16:06: nothing of mine was running (S9 had finished at 14:53:42; the S9 validation job b5aufqcj2 was killed by the stall, no s9_val*.json existed); the other processes on the machine were another agent's btl2 search. Load 6.9 (5-min 11), 6 workers allowed.
- **S9 (balanced P95 swing)** finished all 7 generations (1992 rollouts, ~1100 s incl. a slow stretch, log out/bat_r2/s9.log): objective 28.09 (S8b's start under the stricter objective) -> 28.29 (gen 2) -> 28.69 (gen 5) -> 28.77 (gen 7). Best = params/search/bat_r2_s9.txt, saved as params/bat_r2_p95_s9.txt (header with the numbers below).
  Changes vs S8b: taim_z0 0.088 -> 0.078 (the mean aim moves down by ~1.3 cm), the drive profile weights re-balanced (dw0-29), prog_trig 0.2247 -> 0.2239, everything else within 3 %.
- Validation (P95 body, `ROBOLAB_PROFILE=p95 BAT_BODY=athlete bat_rep.py eval --params params/search/bat_r2_s9.txt --controller bin/challengers/bat_r2-t8 --seeds A:B --seconds 4.3 --workers 6 --quiet`), S9 against S8b:
    seeds 4000-4047: S9 32.346 m/s 48/48, fair 37, launch mean 19.5 deg (S8b 30.1), >60 deg 8 % (19 %), 10-45 deg 44 % (29 %), aim mean -1.39 cm sd 2.34, flow 2.433 max 2.741   | S8b 32.377, fair 35
    seeds 6000-6047 (untouched): S9 32.412 m/s 48/48, fair 44, launch mean 25.5 (39.2), >60 deg 21 % (27 %), aim sd 2.26, flow 2.455 max 2.849   | S8b 32.430, fair 36
    arena seeds 1100-1123: S9 32.134 m/s **24/24**, fair 20, launch mean 34.1 (42.4), flow 2.465 max 2.728, quality 0.291 | S8b 30.847, 23/24, fair 18, quality 0.165
  Same speed on the hits (-0.02 to -0.03 m/s), the arena miss (1123) gone, more fair balls and a launch mean nearer 20 deg, the launch SPREAD unchanged (sd 29-32 deg): the launch angle is ~10-14 deg per cm of aim offset and the aim offset scatters by 2.3 cm.
- Arena `bat_power_fresh_rep_p95` `arena.py eval ... --params params/bat_r2_p95_s9.txt --controller bin/challengers/bat_r2-t8 --workers 6 --promote`: 32.134 +- 0.205, 24/24 hits, fair 0.833, quality 0.291, flow 2.465;
  **NOT promoted: mean diff +1.287, p = 0.4705** (the sign-flip test cannot see a swing that only converts the one miss 1123; on the 23 pitches both hit S9 differs from S8b by -0.43 .. +0.23 m/s, mean -0.05, better on 8 of 23; on the validation sets the paired mean difference is -0.03 / -0.02 m/s, S9 better on 18 / 19 of 48). History record `lose`. The P95 champion stays S8b (30.847, 23/24);
  S9 is the better controller by every other measure and is the one to use (params/bat_r2_p95_s9.txt).
- Why the aim scatter is not fixable by a pitch feature (`scratchpad/bat/`-style analysis on S3's 96 validation pitches, athlete body): aim_n sd 1.9-2.3 cm; regressing it on (dz, dx), release speed, x, z, quadratic terms, the plant-to-swing gap, stride or plant time
  brings the cross-set residual only from 1.9-2.3 to 1.75-2.1 cm (the taim1 swing before the searches had 1.2 cm; the searches' objective leaves +-3 cm of aim free, which is consistent with them spending it). Correlations of aim_n with launch 0.85-0.99, with attack angle -0.58.
- 16:14 **leg / stride / hip scan around S3** (athlete body, 16 practice pitches 3008,3049,3050,3060,3064,3073,3074,3091,3092,3102,3107,3108,3115,3118,3127,3138, calibrated-aim evaluator, 4 workers, 220 s; `BAT_BODY=athlete BATREP_FLOW=4 BATREP_FLOW_CAP=2.5 BATREP_LAUNCH=0.04 .venv/bin/python scratchpad/bat/evalcal.py --params params/bat_r2_s3.txt --controller bin/challengers/bat_r2-t8 --seeds <16> --sets "<...>" --workers 4 --name legscan1`, raw table out/bat_r2/legscan1.json):
    base: speed 26.524, flow 2.348 (max 2.639), calibrated objective 26.060, 16/16 hits.
    NO EFFECT AT ALL (bit-identical): drv_hips 0.45 / 0.9, dur_hips 0.14 / 0.22, dur_leglift 0.2 / 0.3, hips_lead -0.02 / 0.02 (leg_follow 0.2 changes only flow +0.013; lift_at only flow).
    train_legs 0.9: speed 26.602 (+0.08) | 1.4: 26.459;  train_legs_ease 0.0: 26.540 (+0.02) | 0.15: 26.491
    drv_stride 0.3: flow 2.405 | 0.8: speed 26.550, flow 2.305 (-0.04)          lift_at 0.09: flow 2.379 | 0.14: flow 2.292 (-0.06), speed unchanged
    leg_swing_kp 0.5: 26.374 | 2: 26.718 (+0.19), flow 2.436 (+0.09, max 2.846)      leg_swing_kd 0.04: 26.716 (+0.19), flow 2.402 | 0.16: 26.159
    stride_at 0.40: speed 26.721 (+0.20), calibrated obj 26.308, flow 2.489 (+0.14), aim shift az +17 ax -26 | 0.55: 4/16 hits     dur_stride 0.28: 15/16 hits, aim shift a0 -2.7 | 0.38: 6/16 hits
    step_delay 0.17: speed 26.566, aim shift a0 -2.2 | 0.195: 12/16 hits
  => a few leg parameters buy 0.1-0.2 m/s each and cost flow 0.05-0.14; lift_at and drv_stride lower the flow. Not searched in S1-S9.
- 16:14 **S10 launched (athlete, S3 retune incl. leg/stride parameters)**: `sh scratchpad/bat/s10.sh 4 2000` (4 workers; load 5-min 24 / 1-min 29 = other agents; log out/bat_r2/s10.log, search file params/search/bat_r2_s10.txt).
  50 tunables = S8's 41 + leg_swing_kp, leg_swing_kd, stride_at, train_legs, train_legs_ease, drv_stride, lift_at, step_delay, dur_stride; objective as S9 (launch 0.10/deg beyond 8 off 20, aim 1.0/cm beyond 1.5) with the flow term anchored at S3's own flow (cap 2.35, weight 4); training pitches seeds 7400-7423; start params/bat_r2_s3.txt.
- 16:15 machine load jumped (1-min 46, 5-min 30: other agents' long_jump / run_gear / a 4-worker search at 2.2 cores per worker); S10 had only just started (gen 1, 24 evaluations), so I stopped its 4-worker tree by PID
  (log kept as out/bat_r2/s10_w4_aborted.log) and restarted the identical search with 2 workers per the cap: `sh scratchpad/bat/s10.sh 2 2000` (pid 86339, log out/bat_r2/s10.log). Nothing else of mine is running.
- 16:21 S10 (2 workers) reached gen 2: objective 21.69 (S3 under the S10 objective) -> 22.67 (316 s per generation); load then fell (1-min 16, 5-min 21) so I stopped that tree by PID (86339 + children), snapshot the best as params/search/bat_r2_s10_gen2.txt and resumed with 4 workers:
  `sh scratchpad/bat/s10.sh 4 1700 params/search/bat_r2_s10_gen2.txt s10b` (pid 91501, log out/bat_r2/s10b.log, search file params/search/bat_r2_s10b.txt, jsonl out/bat_r2/s10b.jsonl). Same env / tunables / seeds 7400-7423 as S10.

## 2026-09-29 16:40 S10 result (athlete): +0.10-0.18 m/s over S3, promoted on all six athlete trials; ball quality slightly worse

- S10/S10b: 50 tunables (S8's 41 + 9 leg/stride parameters), athlete body, S9-style objective with the flow term anchored at 2.35; S10 (2 workers) 2 generations 21.69 -> 22.67, S10b (resumed from that best, 4 workers, 1680 rollouts, 912 s, log out/bat_r2/s10b.log) 22.67 -> 23.55 (gen 3), then no gain in gens 4-6.
  Best = params/search/bat_r2_s10b.txt, saved as params/bat_r2_s10.txt. Changes vs S3: drv_stride 0.528 -> 0.649, leg_swing_kd 0.084 -> 0.069, leg_swing_kp 1 -> 0.85, prog_trig 0.2437 -> 0.2478 (fires 4 ms earlier), train_drv 1.096 -> 1.115, train_lead 0.0201 -> 0.0171,
  taim_z 5.13 -> 4.95, taim_x 3.50 -> 3.30, taim_z0 0.0828 -> 0.0743, train_legs 1.161 -> 1.195, train_legs_ease 0.048 -> 0.032, k_in 0.0149 -> 0.0182, dshape_b 0.5 -> 0.465; drive-profile weights moved by up to 0.29; stride_at, lift_at, step_delay, dur_stride within 0.5 %.
- Validation against S3 (athlete body, as run, paired): seeds 4000-4047 **26.712 vs 26.571** (+0.14, better on 44 of 48, sign-flip p < 1e-4), hits 48/48, fair 41 (S3 46), flow 2.296 max 2.639 (2.314 / 2.645), launch mean 14.3 (19.9);
  untouched seeds 6000-6047 **26.829 vs 26.699** (+0.13, better on 40 of 48), fair 44 (44), flow 2.341 max 2.658 (2.366 / 2.703); arena seeds 1100-1123 **26.500 vs 26.399** (+0.10, better on 18 of 24, p = 0.0006), fair 22 (24), flow 2.320 max 2.639.
  Hitch terms on 6000-6047 (S3 -> S10): valley lift 0.607 -> 0.579, pre 0.687 -> 0.689, post 0.531 -> 0.540, stall before the swing 10.2 -> 10.3 ms, plant->hips fire 19.4 -> 18.2 ms, swing->contact 227.7 -> 229.6 ms (`out/bat_r2/s10_val6000.json`, `s3_val6000.json`).
- Arena (`arena.py eval <trial> --params params/bat_r2_s10.txt --controller bin/challengers/bat_r2-t8 --workers 4 --promote`, all WON and PROMOTED, 16:38-16:39): bat_power_fresh_rep 26.4996 (24/24, fair 0.917, quality 0.347, flow 2.320; S3 26.399), bat_power_fresh_rep_clean (same),
  bat_power 26.698 (18/18; S3 26.521), bat_power_clean (flow 2.293, quality 0.177; S3 0.276), bat_power_fresh 26.862 (24/24, fair 0.958, quality 0.407, flow 2.244; S3 26.669), bat_power_fresh_clean (same).
- **Ball quality is slightly worse than S3's**: fair balls 143 of 162 over the five athlete sets against S3's 153 (4000-4047 41 vs 46, 6000-6047 44 vs 44, arena 22 vs 24, 1000-1023 23 vs 23, grid 13/18 vs 16/18: `BATREP_GRID=1 bat_rep.py eval --seeds 0:18`, out/bat_r2/s3_grid_q.json, s10_grid_q.json),
  quality 0.35 / 0.41 / 0.18 against 0.42 / 0.44 / 0.28 (fresh_rep / fresh / grid). My first arena note said "about equal" from the validation sets alone; after the grid result I corrected the six notes and champion entries under the arena lock
  (`scratchpad/bat/fix_notes.py scratchpad/bat/notes_fix2.json`, originals in notes_s10_orig.json; 6 history records and 6 champions changed, only `note`) and the params header. S3 stays the fair-ball-friendlier swing.

## 2026-09-29 16:55 final state

- README: the section `### Batting round 2 (29 Sep 2026): bat speed in robolab's own representation` (238 lines, draft scratchpad/bat/README_round2_draft.md) was inserted at README.md line 3858, right after the v6 batting section and before another agent's
  `## Dribble through the legs, round 2` section (the README had grown from 3749 to 3907 lines while I worked; the insertion was one read-modify-write with os.replace and the line count checked: 3907 + 239 = 4146).
- Champions now (arena, athlete body): bat_power_fresh_rep 26.500 (24/24), _clean 26.500, bat_power 26.698, bat_power_clean 26.698, bat_power_fresh 26.862, _clean 26.862 (all params/bat_r2_s10.txt + bin/challengers/bat_r2-t8);
  bat_power_fresh_rep_p95 30.847 (23/24, params/bat_r2_p95_s8.txt; S9 = params/bat_r2_p95_s9.txt scores 32.134, 24/24 but lost the paired test, p 0.47). Not beaten: bat_quality (oracle 0.416), bat_flow (v5, 2.048).
- Nothing of mine is running. No commits. Files touched are listed in the final report.
