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
