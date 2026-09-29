### Batting round 2 (29 Sep 2026): bat speed in robolab's own representation

Erik's goal is still "increase the bat speed". Round 1 (v6) raised it to 25.2 m/s with open-loop excitation programs (reflex gain 0,
ORACLE-class) and to 23.1 (grid) / 21.6 (24 held-out pitches) in robolab's own representation (11 quintic contraction knots per track
fitted to the programs' joint trajectories, reflexes on, `ri` 1). Round 2 works only in that representation and measures on pitches
nobody trained on. **Result: 26.5 m/s on 24 held-out pitches, 24 of 24 hit, bat_flow 2.32 (the v6 knots swing on the same pitches: 19.4 m/s, 20 of 24,
2.83), and 26.8 m/s on 48 pitches nobody looked at (v6 knots: 17.7, 36 of 48). That is above the open-loop oracle (25.2 / 25.2 on its own
trials, which an in-representation swing now holds: 26.7 on the 18 grid pitches, 26.9 on the 24 oracle-era held-out pitches).** The last 0.1-0.2 m/s
(S10 over S3) cost some ball quality (fair balls 143 of 162 against S3's 153), so S3 stays the swing to use when fair balls matter. On a
labelled 95th-percentile body (`ROBOLAB_PROFILE=p95`, its own arena trial) the same swing structure, retuned, reaches 32.4 m/s on 48 pitches nobody looked at (48 of 48 hit;
the MLB average is 32.0), at a cost in ball quality (fair 35-36 of 48; S9, a second retune that prices the aim harder, 37-44 of 48 at the same speed).

**Yardstick.** Three new arena trials (the ORACLE trials stay as they were):

| trial | pitches | seeded with |
| --- | --- | --- |
| `bat_power_fresh_rep` | 24 fresh continuous pitches, seeds 1100-1123 (`BAT_FRESH_PITCH`: the distribution of `bat_power_fresh`, new seeds) | the v6 knots swing: 19.44 m/s, 20/24 hits |
| `bat_power_fresh_rep_clean` | the same, guard `bat_flow` <= 3.0 on every pitch | the same swing: fails the guard (2 hits above 3.0, and the 4 misses) |
| `bat_power_fresh_rep_p95` | the same pitches, LABELLED BODY VARIANT: the athlete at `ROBOLAB_PROFILE=p95` | the athlete swing carried to that body and retuned once (S7): 27.12 m/s, 21/24 hits; now held by S8b (30.85, 23/24) |

Seed sets used, never mixed: arena 1100-1123 (and the old 1000-1023) only to score; practice 3000-3143 (S1: 16 maximin pitches, S2: 16 more,
S2c: 24 of them), 5000-5047 (taim calibration; P95 training), 7000-7323 (random practice), 8000-8015 (body sweep); validation 4000-4047 (looked at
during the work, as run); untouched final validation 6000-6047.

**Why the knots swing missed (the misses were not "1-3 cm").** A new task, `tasks/bat_rep.py` (every seed one fresh pitch, per-pitch aim
diagnostics: `aim_n_cm`, the ball's offset from the bat's swing plane at contact or closest approach, a hit needs |aim_n| < ~7 cm; `aim_s`,
where along the bat the ball is met), and a cheap evaluator, `playground/bat_rep.py` (4.3-4.6 s rollouts, a 2-4 worker pool; it reproduces
the arena scores exactly), showed on 144 fresh pitches (seeds 3000-3143) 115 hits and aim errors of -7 to -18 cm on the low pitches
(z < 0.68), +7 to +9 on the highest, -7 to -9 near (x 0.1, z 0.9). The error is not noise: with dz, dx the pitch's crossing minus the
location the inverse-squared-distance blend of the 6 grid programs stands for (sum_i w_i z_i, sum_i w_i x_i; the blend is exact at a
program's own pitch but has no slope there), aim_n = -3.2 + 152 dz + 35 dx cm (dz, dx in m; R2 0.88, residual 1.8 cm), against R2 0.28
for aim_n linear in the pitch itself. The knots swing hits where a program was optimised and misses between them.

**taim: a first-order correction of the blend** (`skills/bat_power.w`, `aim_correction`, opt-in; all gains 0 = the v6 swing exactly).
The v5 aim law's own sensitivity vectors (`k_z_u`, `k_x_u`: the joint change that moves the sweet spot 1 m up / out with the top hand on
the handle) are applied to the mismatch and added to every knot's angle, rate and acceleration through a quintic smoothstep ramp
(`taim_ramp` of the train): offset_j = taim_z k_z[j] (dz + taim_z0) + taim_x k_x[j] (dx + taim_x0). Two unit-gain probes on 48 pitches
(`scratchpad/bat/probe1.sh`, `an3.py`) measured the plane offset it moves as a nearly perfect linear response (R2 0.99): -59.4 cm per
m of dz per unit taim_z and -52.4 per m of dx per unit taim_x, so the gains that cancel the blend's 152 / 35 are taim_z 2.56, taim_x
0.68, and taim_z0 -0.021 m removes the 3.2 cm bias. Nothing else changed: on 48 pitches not used for the fit (seeds 4000-4047) the swing
hits 48 of 48 at 23.1 m/s (aim residual 1.2 cm), flow unchanged. (The arena's sign-flip test could not promote this fix: it turns 4 misses
into hits and moves the other 20 pitches by a few tenths, and with 4 dominating differences the smallest possible p is 2^-4; the entry
stands as a loss, p = 0.061, 22.98 m/s.)

**What limited the speed once the aim was right: the reflex layer's damping and the swing's timing.** Every parameter that changes the
drive or the damping shifts the aim by a few cm (train_drv 0.8 alone: 10 misses of 16), so a search on hit/miss sees a cliff.
`playground/bat_search.py` (S1, S2) therefore scored each candidate on the aim it would have after recalibration (per candidate, aim_n
regressed on (1, dz, dx) over its 16 pitches, the residual scored, the fit's own shift left to the taim gains, `scratchpad/bat/calibrate.py`,
a Newton step); the later searches (S2b, S2c, S3, S6-S9) are as-run (`playground/search.py bat_rep`): a hit scores its bat speed minus an aim-plane
margin (0.5 per cm of |aim_n| beyond 3), a contact-position margin (8 per m beyond 0.50-0.80 m along the bat) and, in S2c, a launch-angle
term (0.04 per degree of |launch - 20| beyond 10); a miss scores -5 - 100 x gap; minus 4 per unit of bat_flow beyond 2.5; the batch's worst
pitch weighted (mean - 0.25 (mean - min)); sep-CMA-ES from the taim swing over 23-32 tunables, 16-24 fresh training pitches at a time
(seeds 3000+, never an arena seed). What it found:

- **arm damping**: the arms' reflex velocity term (`arm_swing_kd`, 0.099) braked the swing: 0.03 alone is +1.2 m/s on 16 pitches, 0.0 (the
  box floor) adds another 0.5 on the pitches it still hits. The swing's speed is set by the excitation drive; the reflex is a position servo on
  the program's joint trajectory.
- **timing**: the free swing (fire late so the ball has passed, `scratchpad/bat/freeswing.py`) peaks at 230 ms after the hips fire but the
  swing met the ball at 217 ms, 13 ms before its own peak, where the sweet spot still gains 0.13 m/s per ms. The search fires 11-15 ms
  earlier (`prog_trig` 0.230 -> 0.241-0.245), lets the knots read their targets 18-22 ms ahead of the drive (`train_lead`), and runs the train
  28 ms longer (`train_end`); after the program's own contact its table is the CMA rollout with the ball's impact in it, which the knots braked
  against, so `train_ext` carries the plan on at contact velocity instead. Contact now comes 225-230 ms after the hips fire, at the swing's peak.
- **the aim vectors run out of authority**: the search's calibrated-aim objective promised 26.85 m/s and flow 2.37 for the S2 swing; recalibrating
  its aim to zero cost 0.65 m/s and 0.4 flow and needed taim gains of 6.1 / 3.2 (the k vectors move the sweet spot in the vertical / lateral
  directions, the wrong ones for the offset a timing shift makes). Two swings then missed because the contact fell beyond the bat's tip.
  Hence the as-run objective with a contact-position margin.

**Ball quality is not free.** The S2b swing (26.4 m/s) launched the balls at a mean 49 deg (fair 29 of 48; the arena's bat_quality formula 0.21):
the speed was bought with a steeper uppercut, which nothing in the bat_power metric sees. S2c prices it (0.04 m/s per degree of |launch - 20|
beyond 10): 26.1 m/s, fair 46 of 48, launch 13 deg, quality 0.45. Both are in the arena (S2b held `bat_power_fresh_rep` for a while).

**Results.** Sweet-spot bat speed at contact, m/s (a miss scores 0), athlete body, athlete controller of each stage, as run, no recalibration.
Validation seeds 6000-6047 were untouched until the last step; 4000-4047 were used to pick between candidates.

| stage (what changed) | arena `bat_power_fresh_rep` (24) | validation 6000-6047: power, hits | bat_flow mean / max | plant -> hips fire | notes |
| --- | --- | --- | --- | --- | --- |
| v6 knots (seed) | 19.44, 20/24 | 17.70, 36/48 | 2.80 / 3.00 | 51 ms | 12 misses of 48 |
| + taim (aim correction) | 22.98, 24/24 (p 0.061: not promoted) | 23.14, 48/48 | 2.80 / 2.96 | 51 ms | |
| S1 (+ arm damping 0, fire earlier, train longer) | 25.71, 24/24 | 25.87, 48/48 | 2.63 / 2.97 | 46 ms | |
| S2b (+ targets lead the drive 18 ms, train_ext, ...) | 26.20, 24/24 | 26.45, 48/48 | 2.47 / 2.94 | 33 ms | launch 49 deg, quality 0.21 |
| S2c (+ launch term) | 25.96, 24/24 (below S2b: not promoted here; promoted on the four oracle-era trials) | 26.29, 48/48 | 2.37 / 2.72 | 18 ms | fair 43/48, quality 0.45 |
| S3 (+ drive time profile) | 26.40, 24/24 | 26.70, 48/48 | 2.37 / 2.70 | 18 ms | fair 44/48, quality 0.42 (the fair-ball-friendlier swing) |
| **S10 (+ leg / stride parameters, aim and launch priced harder)** | **26.50, 24/24** (champion) | **26.83, 48/48** | **2.34 / 2.66** | 18 ms | fair 44/48 (arena 22/24), quality 0.35 |

Same swings on the other sets (arena numbers, S10 / S3): `bat_power_fresh` (24 pitches, seeds 1000-1023) 26.86 / 26.67 against the ORACLE's 25.24 and the v6 knots' 21.57; `bat_power`
(the 18-pitch grid) 26.70 / 26.52 against 25.17 and 23.12; all hit, bat_flow 2.24-2.32. The four trials the oracle held (`bat_power`, `bat_power_clean`,
`bat_power_fresh`, `bat_power_fresh_clean`) are now held by this swing, and so are the two new ones: an in-representation controller, reflexes on, is above the open-loop ceiling
of round 1. The hitch guard twins pass on every pitch (max 2.66 against the 3.0 limit). S10 is the arena champion everywhere, but its lead over S3 is 0.10-0.18 m/s
(paired on the 48 untouched pitches: +0.13, better on 40 of 48; p < 1e-4) and its balls are worse: fair 143 of 162 over the five athlete sets against S3's 153 (grid 13 of 18 against 16, arena quality
0.35 / 0.41 / 0.18 against 0.42 / 0.44 / 0.28 on `fresh_rep` / `fresh` / the grid; the oracle's `bat_quality` champion, 0.42 on the grid, is not beaten by either). The launch angle is the
aim's: see the P95 section for why the launch scatters by +-26-30 deg whatever the price on it.

Per pitch, the arena's 24 pitches (`bat_power_fresh_rep`, seeds 1100-1123: release speed m/s, crossing x m from the plate centre, height m; sweet-spot bat speed at contact, m/s, of S10 (the
champion), of S3 and of the v6 knots swing on the same pitch; S10 hits all 24 at 25.35-27.25 m/s (mean 26.50), fouls 1121 and 1123; the four pitches the knots swing missed (1104, 1109, 1113, 1121, the low
ones) are hit at 26.3-27.3 by both):

```
seed  v     x      z     S10    S3     v6 knots | seed  v     x      z     S10    S3     v6 knots
1100 38.4 +0.134 0.813  26.15  25.97  23.71    | 1112 34.3 +0.116 0.764  26.02  26.08  23.31
1101 38.4 +0.056 0.980  26.28  26.08  22.99    | 1113 37.6 -0.088 0.668  27.25  27.32   MISS
1102 38.0 -0.064 0.896  26.71  26.71  23.82    | 1114 37.8 -0.143 0.766  27.19  27.04  24.38
1103 36.7 +0.062 0.704  26.08  26.11  23.58    | 1115 35.1 -0.058 0.978  26.72  26.70  23.04
1104 37.7 +0.000 0.648  26.47  26.51   MISS    | 1116 35.7 +0.137 0.915  26.21  26.15  22.60
1105 36.2 +0.042 0.960  26.53  26.41  23.05    | 1117 34.3 +0.065 0.894  27.13  26.95  23.10
1106 35.8 +0.147 0.686  25.35  25.32  22.75    | 1118 37.8 +0.115 0.867  26.30  26.19  23.28
1107 34.7 -0.062 0.865  26.93  26.86  23.77    | 1119 36.3 +0.064 0.723  25.94  26.05  23.76
1108 40.1 +0.000 0.852  27.11  26.80  23.64    | 1120 34.2 -0.116 0.968  26.98  26.70  22.72
1109 35.7 +0.023 0.640  26.43  26.32   MISS    | 1121 36.5 -0.010 0.674  26.61  26.50   MISS
1110 35.0 -0.039 0.866  27.06  26.86  23.55    | 1122 34.2 +0.133 0.709  25.86  25.74  23.57
1111 38.3 +0.129 0.700  25.96  25.73  23.50    | 1123 35.0 +0.105 0.964  26.72  26.47  22.40
```

The slowest pitches are the outside ones (S3: x > 0.1: 25.3-26.5; S10 25.4-26.7): the contact moves toward the bat's tip (0.48 m along the bat per m of x) and the sweet spot has less speed there (the speed falls 4.4 m/s per m of x,
correlation -0.82; it does not depend on the pitch's release speed).

**The pre-swing pause and the hitches** (Erik's complaint: a stop before and after contact). The bat_flow score is the sum of the deepest dip of the
measured contraction speed lift -> plant, plant -> contact and contact -> +0.8 s, plus the worst command hold or step; means over 48 pitches:

| stage | valley lift | valley pre | valley post | command | stall before the swing | plant -> hips fire | flow |
| --- | --- | --- | --- | --- | --- | --- | --- |
| v6 knots | 0.594 | 0.846 | 0.732 | 0.615 | 31 ms | 51 ms | 2.79 |
| S1 | 0.591 | 0.814 | 0.649 | 0.560 | 27 ms | 46 ms | 2.61 |
| S2b | 0.591 | 0.761 | 0.593 | 0.498 | 18 ms | 33 ms | 2.44 |
| S2c / S3 | 0.607 | 0.685-0.688 | 0.526-0.531 | 0.493 | 7-8 ms | 18 ms | 2.31-2.32 |
| S10 | 0.579 | 0.688 | 0.534 | 0.495 | 8 ms | 17 ms | 2.30 |

The pause between the plant and the hips firing fell from 51 to 17-18 ms (the step landing later, `step_delay`, took the v5 swing from 115 to 50 ms; firing
earlier takes it to 18) and its stall in the measured speed from 31 to 7 ms; the largest command steps of the v6 knots swing were at the START of the swing
(15-20 ms after the fire: the first knot segment goes from the load's velocity to the program's within 20 ms), which the earlier, longer swing softens.
The v5 champion's flow is 2.05, so a lift -> plant dip of 0.58-0.61 (the leg lift's apex) remains: the lift and stride parameters were searched only in S10 (below), which took the lift valley from 0.607 to 0.579.

**A zero-initialised temporal residual on the knots (the Codex recipe).** The recipe is a fixed causal-convolution feature map with a small zero-initialised
readout trained by ES on fresh random pitches, judged on held-out ones. Three tries on the S2c swing, each starting from exactly the controller (all
weights 0), trained by as-run sep-CMA on fresh random pitches and judged on the 48 validation pitches, paired:

- **Codex's own architecture** (`bat_residual.w`: its two convolutions and fixed projections reimplemented; 20 readout weights `tc0-tc19`; outputs bounded 0.16 rad
  on the spine rotation and flexion, both elbows and both wrists' flexion, added to the reflex TARGET): the training objective gained 0.18 in one
  generation and nothing more in eight; held out it is worse: -0.12 m/s (better on 14 of 48 pitches, worse on 33, p < 0.001) and +0.20 bat_flow.
- **the same readout on a temporal basis** (`tres`: 6 gaussian bumps after the fire plus the pitch): not run to a result (the drive profile below was ahead).
- **the readout on the feed-forward DRIVE instead of the targets** (`dshape`: the drive of each joint group scaled by 1 +- 0.5 times a function of time since the
  hips fire, 30 weights `dw0-dw29` on 6 gaussian bumps, 36 random fresh training pitches, 7 generations of 14): the objective gained 1.4; held out **+0.42 m/s on
  all 48 pitches** (26.57 against 26.15, p < 0.001) at unchanged bat_flow (2.31): a hit at 110-190 ms is worth more drive (the pelvis' factor rises to 1.5 at 150 ms,
  the spine's and shoulders' too), the last 40 ms about 15 % less. A second search continuing it on new pitches found nothing more (+0.05).
  So the drive, not the reflex target, is where a learned time-varying correction pays on this controller; feedback features (Codex's) did not.

**Leg and stride parameters (S10).** A one-at-a-time scan around S3 (16 practice pitches, calibrated-aim evaluator, `evalcal.py --sets`, 29 settings) showed that `drv_hips`, `dur_hips`,
`dur_leglift` and `hips_lead` do not change a single bit of the run (the train swing replaces the tracks they parametrise), `leg_follow` and `lift_at` change only the flow, and the rest buy 0.1-0.2 m/s
each at a flow cost or move the aim by centimetres: `leg_swing_kp` 2 +0.19 m/s (flow +0.09), `leg_swing_kd` 0.04 +0.19 (+0.05), `stride_at` 0.40 +0.20 (+0.14, aim shifted), `train_legs` 0.9 +0.08,
`drv_stride` 0.8 (flow -0.04), `lift_at` 0.14 (flow -0.06 for nothing else), `dur_stride`, `step_delay` and `stride_at` 0.55 break the aim. S10 searched them together with the P95 retune's 41 tunables
(50 in all, 24 new training pitches, the aim margin and the launch cost as in S9, the flow term anchored at S3's own 2.35): one generation at two workers, then five with four (about 1,700 rollouts), from 21.7 to 23.6 in
the objective. Held out (paired against S3, as run): **+0.14 m/s on 4000-4047 (better on 44 of 48), +0.13 on the untouched 6000-6047 (40 of 48), +0.10 on the arena's pitches (18 of 24; p 0.0006)**,
the lift valley 0.607 -> 0.579 and bat_flow 2.31 -> 2.30 (4000-4047); what it moved: `drv_stride` 0.53 -> 0.65, `leg_swing_kd` 0.084 -> 0.069, `leg_swing_kp` 1 -> 0.85, the fire 4 ms earlier
(`prog_trig` 0.2437 -> 0.2478), the drive profile by up to 0.29. It is the champion of all six athlete trials, and the balls are worse (above).

**What limits the trunk and the elbows** (`playground/bat_power_diag.py --fresh`, S3, 16 fresh pitches; earlier rows of the round-1 tables are v5 / oracle):
pelvis yaw peaks at 7.6 rad/s (437 deg/s; MLB 714) 127 ms before contact, the torso at 9.9 rad/s (567 deg/s; MLB 937) 160 ms before, the top-arm elbow at 12.8 rad/s
(732 deg/s) and the bottom-arm elbow at 18.2 rad/s (1042 deg/s; pros 1539, Dowling & Fleisig 2016), the bottom wrist at 18.6 rad/s (1065 deg/s; college 1093 +- 354),
the bat at 37.8 rad/s (2164 deg/s). Against each joint's unloaded limit (vmax / 0.3 ranges per second): pelvis yaw 0.32, spine 0.25-0.39, shoulders 0.22-0.45, elbows
0.49 and 0.70 - none is near its speed limit, and none but the wrists is near an end of its range (pelvis yaw stops 4.8 % of its range from the end, 0.3 % of the
swing within 3 %; the wrist deviations spend 11-25 % of it within 3 % of an end). They are limited by torque x time / inertia and by the chain's sequencing:
the pelvis yaw's effective inertia in the start posture is 2.3 kg m^2 (its muscles peak at 375 N m), the bottom elbow's 0.53 (105 N m), and the prime movers are at
>= 0.9 activation for only 46 % (pelvis), 51 % (trunk, shoulders), 48 % (elbows) and 26 % (wrists) of the 220 ms power phase (S1: 43 / 34 / 34 / 33 / 13),
co-contraction 0.02-0.05. The drive profile added sustained drive and 0.4 m/s; the rest is what a torque and a 0.23 s swing allow. The S10 swing gives the same picture (16 fresh pitches:
pelvis yaw 7.70 rad/s at 127 ms before contact, torso 9.89 at 161 ms, bottom elbow 17.7, top elbow 12.6, bat 37.96 rad/s; prime movers at >= 0.9 for 45 % (pelvis), 47 % (trunk), 32 % (shoulders),
24 % (elbows), 14 % (wrists) of the phase, 49-50 % for the instantaneous agonist of trunk, shoulders and elbows, 21 % for the wrists' (`out/bat_r2/diag_s10.json`).

**Would a body change matter? Yes: about +2 m/s per +20 % of strength or of muscle speed, and a labelled P95 body reaches the MLB average.**
The ideal-control ceiling (`bat_ceiling.py --ball`, round 1's recipe: CMA over open-loop excitations of the 16 upper-body joints, captured from the ORACLE program's swing,
the 34 m/s centre pitch, `scratchpad/bat/ceil.sh ... prog_athlete prog_p95`) is 25.5 m/s for the athlete (the program library is already round 1's CMA optimum: no gain in 400
generations; round 1's own run found 25.69) and **at least 32.9 for the P95 body** (400 generations 30.8, 1000 generations 32.9 at a 75 deg popup, still creeping up:
the ball-mode score has no launch term). The in-representation swings on the same pitch: athlete S3 27.2, P95 S8b 32.7. So the closed-loop athlete swing is 1.5 m/s ABOVE round 1's
open-loop ceiling, and the tool cannot be used as a ceiling for it any more: started from the S2c or S3 swing's own state the open-loop CMA never gets back to the swing (its replay of the
net excitations misses the contact point by 8-12 cm; through that point it reaches 22.7 m/s against the swing's 27.2 on the athlete, 28.0 against 32.7 on P95, `--target sweet`,
`scratchpad/bat/ceil_sweet.sh`): the reflex layer's feedback does work the open loop cannot reproduce. The body question is therefore answered by the controller itself:
the S2c controller, unchanged, on the athlete body with one change (16 fresh pitches 8000-8015, `scratchpad/bat/bodysweep.sh`; bat speed at contact or closest
approach with the aim shift re-centred, which the swing needs after a body change; as-run hits in brackets):

| body | bat speed, m/s |
| --- | --- |
| athlete (strength x1.5, vmax 3.0) | 26.40 (16/16) |
| pelvis yaw x2 / trunk (pelvis yaw + spine) x1.5 | 26.86 (16) / 27.68 (15) |
| elbows x2 / arms (shoulders, elbows, wrists) x1.5 | 27.61 (15) / 28.41 (1) |
| all strength x1.2 / x1.33 / x1.5 / x2 | 28.71 (12) / 29.58 (3) / 30.36 (0) / 32.22 (0) |
| muscle speed (vmax) x1.2 / x1.5 / x2 | 27.99 (16) / 29.39 (13) / 30.68 (11) |
| strength x1.5 and vmax x1.5 | 33.14 (0) |
| **ROBOLAB_PROFILE=p95: strength x1.32, speed x1.2, activation x0.87** | **30.83 (0)** |

The arms are a bigger lever than the trunk (the wrist whip carries the speed), and the speed of the fibres matters as much as their force (a faster muscle keeps
more force at the same joint rate). `ROBOLAB_PROFILE=p95` (playground/profiles/p95.json: each multiplier a marginal 95th percentile of healthy young men, with sources; the athlete's
own x1.5 already stands for strength-trained men, x1.58 in Maden-Wilkinson et al. 2020) is the honest, literature-backed body change; it is labelled, opt-in and its own arena trial,
`bat_power_fresh_rep_p95`, never to be compared with the athlete trials. The athlete swing does not carry over as it is: the faster swing reaches the ball's plane earlier and met it
beyond the tip (contact position 0.90 m along a 0.86 m bat), so it needs its fire 12 ms later (`prog_trig`), the taim gains recalibrated (`calibrate.py`, 45 of 48 hits at 29.7) and a search.
S7 (an as-run sep-CMA on this body with the S2c objective) gave 30.64 m/s, 47 of 48 on the validation pitches, arena 27.12 (21/24); carrying the athlete's drive profile over and retuning it
with 41 tunables (S8/S8b, 24 training pitches, seeds 5000-5023) gave `params/bat_r2_p95_s8.txt`: **32.38 m/s, 48/48 hits on seeds 4000-4047 and 32.43 m/s, 48/48 on the untouched 6000-6047**
(bat speeds 31.0-33.4, bat_flow 2.44-2.45, max 2.85), **30.85 m/s, 23/24 on the arena's 24 pitches** (hit speed 32.2; the miss is 1123, the outside high pitch, contact 0.89 m along the bat;
bat_flow 2.44, max 2.64). The price is ball quality: fair 35-36 of 48 (athlete S3: 44-46), mean launch 30-39 deg, 19-27 % of the hits launched above 60 deg (arena quality 0.17).
The launch angle is a straight line in the aim: launch = 31-39 + 10-14 x aim_n deg (aim_n, the ball's offset from the swing plane in cm; correlation 0.85-0.99 on
the validation sets, both bodies), and aim_n has a spread of 1.9-2.6 cm even after the aim correction, so the launch angle scatters by 26-33 deg (1 sd) whatever its mean:
the price on the launch acts on its mean (S8b's 30-42 deg against S9's 19-34 deg below), its spread is the aim's. S9 (S8b's best, the same 41 tunables, 24 new training pitches, seeds 7300-7323,
the launch cost raised to 0.10 per degree beyond 8 off 20 and the aim margin to 1.0 per cm beyond 1.5) keeps the speed and gives part of the ball quality back: `params/bat_r2_p95_s9.txt`,
**32.35 m/s, 48/48 hits (fair 37) on 4000-4047, 32.41 m/s, 48/48 (fair 44) on the untouched 6000-6047 and 32.13 m/s, 24/24 (fair 20, quality 0.29) on the arena's pitches**, mean launch
19.5-34 deg, 8-21 % of the hits above 60 deg, bat_flow 2.43-2.47 (max 2.85); the aim's mean moved 1.3 cm down, its spread stayed at 2.3 cm. S9 is NOT the arena's champion: against S8b its
paired test is p = 0.47 (on the 23 pitches both hit it differs by -0.05 m/s, -0.43 .. +0.23; it only converts the one miss), so `bat_power_fresh_rep_p95` is held by S8b (30.85, 23/24); S9 is the P95
controller to use.
The body sweep's hooks are env vars of `tasks/bat.py` (BAT_STRENGTH, BAT_VMAX, BAT_GROUP_STRENGTH, BAT_GROUP_VMAX; defaults change nothing).

**What did not work / caveats.** `hip_open` (v5) lowers the speed and worsens the flow; `train_drv` +-20 % breaks the aim (10 and 4 misses of 16); the calibrated-aim objective was
optimistic (26.85 promised, 26.19 after recalibration, 2 misses on 48 pitches) when the search wandered far; `train_lead` and the earlier fire move the contact toward the bat's tip (misses
at 0.86-0.92 m), which is why the later searches carry a contact-position margin; the conv residual on the reflex targets hurt; S2b's steep uppercut; the fast S2b swing does not
generalise its quality. **Ball quality is the open problem**: the launch angle is 10-14 deg per cm of the ball's offset from the swing plane, and that offset scatters by 1.9-2.6 cm after the aim
correction (1.2 cm right after taim, before the searches, whose objectives leave +-3 cm free) and is not explained by the pitch (regressed on the release speed, the location, the blend's
mismatch, quadratics of them, the plant-to-swing gap: the residual on the other validation set falls from 1.9-2.3 only to 1.75-2.1 cm), so the launch angle scatters by 26-33 deg (1 sd), fair balls
are 88-95 % and the quality 0.18-0.45, whatever the price on the launch. The arena's paired test cannot see a swing that only converts one miss (S9 against S8b: p 0.47). The 4-pitch demo is
kind to S3 (4 of 4 fair) and unkind to S10 (`out/bat_r2_s10.mp4`, `out/bat_r2_s10_sheet.png`: 27.0, 26.3, 25.9, 27.4 m/s, 2 of 4 fair, both grounders; the fouls are the 76 mph outside pitch, met
1.4 cm beyond the bat's end, and a grounder at -30 deg). Not done: a new program library optimised for the longer swing (the CMA ceiling cannot find one from this state), the `tres` bumps on the reflex targets, a
better aim law (the source of the scatter), the P95 body with the leg parameters.

**Files.** Controller features (all opt-in, the v6 params replay exactly; each build was checked bit for bit against the last): `lib/robolab/skills/bat_power.w`
(taim `taim_z/x/z0/x0/ramp`; `train_first`, `train_legs_ease`, `train_ext`, `train_lead`, `train_dlead`; `dshape`/`dw0-29`; `tres`/`tw`/`tv`/`tc`),
`lib/robolab/skills/bat_residual.w` (`BatConvResidual`), entry `lib/entry/bat_r2.w` -> `./build.sh bat_r2` (`bin/robolab_bat_r2`; frozen copies
`bin/challengers/bat_r2-t1` .. `-t8`: t1 taim, t5 adds the train_* timing features, t8 everything). Tools: `playground/tasks/bat_rep.py`, `playground/bat_rep.py`,
`playground/bat_search.py`, `playground/bat_power_diag.py` (`--fresh`, joint range margins), `playground/tasks/bat.py` (body env hooks). Log and scripts: `scratchpad/bat/`
(`LOG.md` has every run with its command line, seeds, result and pid). Params: `params/bat_r2_taim1.txt` (first fix), `bat_r2_s1.txt`, `bat_r2_s2b_g5.txt` (fastest, steep uppercut),
`bat_r2_s2c.txt`, `bat_r2_s3.txt` (fair-ball-friendlier), **`bat_r2_s10.txt` (fastest; champion of the six athlete trials)**, P95 body (labelled): `bat_r2_p95_s7.txt`, `bat_r2_p95_s8.txt` (arena champion of `bat_power_fresh_rep_p95`), **`bat_r2_p95_s9.txt` (the one to use)**;
searches in `params/search/bat_r2_s*.txt`. Evaluations in `out/bat_r2/`, ideal-control runs in `out/bat_ceiling/r2*_*.json`; scripts `scratchpad/bat/ceil.sh` (`--ball` ceilings, variants `prog_athlete`, `prog_p95`),
`ceil_sweet.sh` (`--target sweet`), `bodysweep.sh`, `s9.sh`, `s10.sh` (resumable: `s10.sh 4 1700 params/search/bat_r2_s10_gen2.txt s10b`).

Video: `out/bat_r2.mp4` and `out/bat_r2_sheet.png` (S3, reflexes on, on the 4 bridge demo pitches of 82.8, 89.5, 76.1 and 86.1 mph: 26.8, 25.9, 25.7 and
27.3 m/s, 59.9-61.1 mph, all 4 fair, bat_flow 2.09-2.38, 225-230 ms from the hips firing to contact; the v6 oracle on the same pitches: 25.6, 24.9, 24.3, 25.8 m/s, 3 fair;
the 76 mph outside pitch is met 0.9 cm from the barrel's end); S10 on the same pitches, `out/bat_r2_s10.mp4` / `out/bat_r2_s10_sheet.png`: 27.0, 26.3, 25.9, 27.4 m/s but 2 of 4 fair.

```sh
.venv/bin/python playground/bat_rep.py eval --params params/bat_r2_s10.txt --controller bin/challengers/bat_r2-t8 --seeds 1100:1124      # = the arena, 25 s
.venv/bin/python scratchpad/bat/calibrate.py --params P --controller C --seeds 5000:5048 --iters 3 --boost 2 --out params/x.txt           # taim gains after a change
ROBOLAB_CONTROLLER=$PWD/bin/challengers/bat_r2-t8 BATREP_FLOW=4 BATREP_FLOW_CAP=2.5 BATREP_LAUNCH=0.04 .venv/bin/python playground/search.py bat_rep \
    --method sep_cma --budget 2600 --workers 4 --sigma 0.15 --pop 14 --risk 0.25 --seconds 4.3 --seeds 7100,7101,... --init params/bat_r2_s2c.txt --only "dw*" --out params/x.txt
BAT_BODY=athlete ROBOLAB_PROFILE=p95 .venv/bin/python playground/bat_rep.py eval ...                                                        # the labelled P95 body
```
