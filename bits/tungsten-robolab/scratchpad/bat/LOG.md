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
