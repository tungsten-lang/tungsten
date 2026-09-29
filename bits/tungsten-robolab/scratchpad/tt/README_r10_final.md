### Table tennis: where P2 is lost, a bounce-tick artifact, and a screening design (round 10)

`skills/myo_tt_v11.w` (`MyoTTV11Skill < MyoTTV10Skill`, entry `lib/entry/myo_tt_v11.w`) adds the round-10 options, each off by default: `bk` (a guard for the
table-bounce tick), `kk` (a late pelvis kick, with the backhand's own `kk2_amp`, `kk2_k`, `kk2_v0`, `ns_k2`, `k_vpm2`), `ns_k` (aim pitch by serve speed), `pv` (a pelvis speed
governor), `qa` (a yaw-only forehand servo), `sg`. With every option off it plays the round-5 champion serve for serve (60 of 60 and 40 of 40 P2 serves identical on every metric,
`out/tt_r10/chk_r10i.jsonl`, `chk_r10j.jsonl`). The parent skill got two hooks (`plan_ball`, `height_ball`), one parameter (`bh_p_z`, the backhand's proportional height gain) and a
`bh_box_dx` that may be negative, all defaulting to the old behaviour. Round 10 measured why `tt_p2_300` sits at 33% before it tried to move it: 600 fresh serves of the champion, per-serve time
series, an offline model of the return, and a fixed-serve screening design.

**Result.** `tt_p2_300` rises from 33.0% to **40.0%** (120 of 300 serves; paired +0.070, p 0.002): the round-10 candidate c3 was promoted to champion (`bin/champions/tt_p2_300-20260929-101727`, `params/myo_tt_p2_r10_c3.txt`,
built from `bin/challengers/myo_tt_r10-n`). The forehand is the old champion's, serve for serve (60 of 156 = 38.5%); the backhand goes from 39 of 144 (27.1%) to 60 of 144 (41.7%). On 900 serves never used to tune anything the gain is
30.2% -> 37.7% (backhand 21.8% -> 35.9%; paired p 0.004 and < 0.0001 on the two blocks). `tt_p1` stays 100% (50 of 50); `tt_p2_backhand` goes from 22.9% to 35.9% (p 0.001, promoted there too). 90% is not within reach of this
arm (ceiling table below): the gain came from finding and removing a one-tick artifact in the servo at the table bounce, restoring the backhand's retreat on purpose, and re-tuning the backhand's swing gain, kick, servo and
posture together with a screening design on fixed serves; the forehand's response to the same treatment was flat.

**Tools** (`playground/`, all on a fast path that plays the same episodes as the standard one; `tt_fast.py check` compares them):

| tool | what it is |
| --- | --- |
| `tt_fast.py` | one env per worker process and a kinematics-only geometry sweep: setup CPU 1.7 s -> 0.13 s per episode, identical metrics |
| `tt_eval.py`, `tt_cmp.py`, `tt_summ.py` | resumable runs (JSON lines), the arena's paired sign-flip test plus the landing slack, per-side mechanics of a run |
| `tt_pools.py` | which seeds the side rule sends to each side (agrees with the controller on 600 of 600 seeds) |
| `tt_impact.py`, `tt_aimlaw.py`, `tt_ceiling.py` | the offline impact + flight model (predicts the outcome of 94% of clean hits), the aim law in Python, the success ceiling against execution noise |
| `tt_rsm.py`, `tt_rsm_run_params.py`, `tt_r10_compose.py` | a fixed-serve two-level random design regressed on the coded levels (main effects of 17 parameters from 33 runs), one run's parameter set, a candidate composed from a backhand and a forehand result |
| `tt_practice.py`, `tt_ilc.py`, `tt_cmc.py` | sep-CMA on common serves with a smooth score, the learned feed-forward on the fast path, a computed-muscle-control prototype |
| `tasks/myo_tt.py` | opt-in diagnostics only (`TT_SAVE_LOG`, `pelvis_vel`, `l8`, `pv`) |

**What the champion loses on** (600 fresh serves, seeds 710000-710599, none used before; `out/tt_r10/champ_710000.jsonl`):
solved 182 of 600 = 30.3% (forehand 110 of 290 = 37.9%, backhand 72 of 310 = 23.2%), hit 80.2%. Of the serves the pad meets, 62% still fail.

| serve speed quintile (m/s) | 3.7-4.7 | 4.7-5.2 | 5.2-5.7 | 5.7-6.1 | 6.1-7.2 |
| --- | --- | --- | --- | --- | --- |
| solved | 43% | 42% | 28% | 17% | 22% |
| hit | 70% | 85% | 86% | 79% | 81% |

| ball crosses the pad plane at y (m) | serves | hit | solved | solved given a hit |
| --- | --- | --- | --- | --- |
| below -0.8 (backhand) | 45 | 0.33 | 0.07 | 0.20 |
| -0.8 to -0.4 (backhand) | 102 | 0.81 | 0.15 | 0.18 |
| -0.4 to 0 (backhand) | 123 | 0.90 | 0.36 | 0.40 |
| 0 to 0.4 (forehand from 0.1) | 111 | 0.87 | 0.41 | 0.46 |
| 0.4 to 0.8 (forehand) | 120 | 0.91 | 0.44 | 0.49 |
| above 0.8 (forehand) | 99 | 0.67 | 0.22 | 0.33 |

- Fast serves are hit and come back too fast: a still pad returns ~0.95 of the ball's speed, and above ~5.5 m/s the set of pad pitches
  whose return clears the net and lands narrows to 8-13 degrees (25 degrees at 5 m/s). Success is 95-97% when the return's exit
  elevation is within 5 degrees of the centre of the feasible window and 55-60% at 5-15 degrees off; 31% of all hits have no
  feasible elevation at their exit speed and azimuth (68% of those leave at more than 25 degrees of azimuth: rim deflections).
- Failure classes (share of serves): forehand solved 37.9, no hit 19.3, net 16.2 (+2.8 rim), long 11.4, wide 6.2, rim-not-toward-net 4.1;
  backhand solved 23.2, no hit 20.3, wide 13.2, long 11.9, rim-not-toward-net 9.7, net 9.4, own half 4.8.
- Execution noise at contact (instrumented run, 150 serves, deterministic replay of the same serves): pad pitch 10 degrees (1 sigma) off the aim law's,
  yaw 2.3 (forehand) / 7.6 (backhand); pad velocity along its normal +0.4 +- 0.5 m/s forehand, -0.2 +- 0.5 backhand (the pelvis alone +0.54 +- 0.26 and
  -0.52 +- 0.31), every velocity component sd 0.55-0.63 m/s, changing 0.3-0.4 m/s rms over the last 30 ms; the forehand's ball meets the pad 5.4 (height) x
  2.6 (lateral) cm sd off centre, the median in-plane offset is 5-7 cm of a 9.3 cm radius (round 7's table: hits under 3 cm off solve 67%, 6-9 cm 31%, rim hits 5%).
- Serve features explain a lot of the face error and little of the height error. A linear map of the serve's launch state (where and when it crosses x = 1.8:
  t, y, z, vx, vy, vz) predicts the forehand's pitch error to the aim to R^2 0.76 (5-fold CV; 0.90 with the contact time; residual 4.9 of 9.9 degrees), the backhand's to 0.37,
  the forehand's ball-minus-pad height offset only to 0.05 (0.26-0.46 backhand): the arm's face is set by the serve, its height is not.

**The success ceiling against execution noise** (`tt_ceiling.py`; offline model, best plan per serve, the champion's own contact conditions):

| pitch sd | pad-velocity sd | yaw sd | P(lands given a sweet-area hit) | ceiling P(success) at position sd 5 / 3 / 2 cm |
| --- | --- | --- | --- | --- |
| 10 deg | 0.5 m/s | 2.5 deg | 0.59 | 0.45 / 0.58 / 0.59 |
| 6 | 0.35 | 2.5 | 0.78 | 0.59 / 0.76 / 0.78 |
| 4 | 0.25 | 2.0 | 0.91 | 0.70 / 0.90 / 0.91 |
| 3 | 0.2 | 1.5 | 0.98 | 0.75 / 0.96 / 0.97 |
| 2 | 0.12 | 1.0 | 1.00 | 0.76 / 0.98 / 1.00 |

The champion runs at about 10 degrees, 0.5 m/s and 5 cm: with a perfect plan its ceiling is ~45%, it plays 30-33%. 90% needs the face within 4 degrees,
the pad's velocity within 0.25 m/s and its place within 3 cm at once: three to four times quieter than this arm (round 9's live tracking gets the forehand's face to
2.8 degrees of its aim in one probe and loses the height, see below).

**A fast harness** (`tt_fast.py`): one env per worker process and a kinematics-only geometry sweep give bit-identical episodes at 0.13 s of setup instead of 1.7 s
(`tt_fast.py check`: identical on every metric). A job queue runs 120-300-serve screens in 2-5 minutes; every comparison below is paired on the same serves.

**What did not move the number** (champion binary and params unless noted; first 120 serves of the fixed pools or `710000:710120`; solved of 120 against the champion's on the same serves):

| variant | solved | what it showed |
| --- | --- | --- |
| pelvis speed governor `pv 2` (the slide reaches its goal at contact retreating at `0.47 (v - 4.83)` m/s) | 31 vs 34 | forehand pelvis velocity at contact right on average (0.41 +- 0.47 for a planned 0.40) with a larger spread; the parent's dispatch dropped the backhand's plan |
| `pv 2` on both sides (dispatch fixed, the slide coasts the last 20 ms) | 21 vs 34 | the pelvis now follows its plan (0.08 +- 0.23 forehand, 0.02 +- 0.15 backhand) but the arm adds +0.2 / +0.5 m/s: pad velocity 0.60 / 0.95 for a planned 0.44, returns too slow (exit 4.6 against 5.6 m/s, 41 net hits against 16), hit rate 0.73 against 0.80 |
| `pv 3` (predictive, arm velocity carried to contact) | 22 vs 34 | hit rate 0.56 (pad below the ball 17): the plane's accuracy is what a governor costs |
| late pelvis kick `kk` (default law), backhand pool | 28 vs 31 | exit speed normalised (6.05 +- 1.09 -> 5.08 +- 0.68 m/s), "long" 14 -> 1, but "net" 11 -> 31: exit elevation 23 +- 23 deg |
| `t_lock 0.10` (servo frozen earlier) | 29 vs 34 | forehand pad velocity noise barely lower (0.41 against 0.48 m/s), accuracy lost |
| no stroke (`d_push 0, drv_push 0`) | 34 vs 34 | identical serve for serve: the stroke fires at contact and does nothing |
| `t_servo 0.20` | 37 vs 34 | forehand returns better controlled, 11 pad-below-the-ball misses |
| forehand posture consolidated (the mean servo correction folded into the ready posture) | 29 | forehand pitch error to the aim +2.5 +- 4.1 (was -3.4 +- 8.9) but the ball is met above the pad |
| `hx_pad 1` / `hx_pad 0.5, z_bias -0.03` | 34 / 38 | height matching from the pad's measured height: no change / +3 (n.s.) |
| `x_hi 2.3 / 2.6` | 31 / 31 | the pad plane never goes past 2.3 |
| height / normal anticipation `g_ffz`, `g_ffn` | 26 / 29 | the pad ends 5 cm lower (contact height 1.148 against 1.197 m): consistent with `z_bias -0.0735` being a fudge for a servo that converges about half way |
| servo and aim from the ball's state at the goal plane `sg` | 27 | the moving-target hypothesis is not supported: the servo simply under-tracks (effective gain 0.25-0.4) |
| yaw-only forehand servo `qa 3` | 21 vs 54 (forehand pool) | the pitch servo helps; the pitch spread is not made by the servo |
| `qa 3` with the wrist raised (-0.65 / -0.45 / -0.25) | 24 / 2 / 0 of 120 | pitch sd 8.6 / 6.9 / 4.2 degrees but the pad ends 11 cm low (hit 0.75 / 0.51 / 0.19) |
| least-squares forehand postures from a finite-difference pose Jacobian (7 joints -> pitch, yaw, height) | 29% / 33% vs 45% (forehand pool) | the pose is reached (pitch -1.8, height +1.4 cm), the pitch sd stays 9 degrees: it is set by the wrist, not the servo |
| absolute far landing target, or the box 0.1-0.25 m deeper (forehand pool) | 54 vs 54, 49 vs 54 | the aim law's box is not what fails |
| side boundary `y_switch` 0.0 / 0.2 (300 serves) | 86 / 81 vs 84 | flat |
| backhand posture steps that remove its closed-face bias (pitch error +11.7 -> +4..+6 degrees as predicted) | 9 / 9 vs 16 of 60 | hit 0.87 -> 0.72-0.77: the swing's arrival and the pad's place move with the posture |
| servo start timed on the predicted contact (`ts_lead` 0.20 / 0.235 / 0.27 forehand, `bh_ts_lead` 0.20 / 0.23 / 0.26 backhand; 200 serves) | 64 / 74 / 74 vs 79; 55 / 62 / 65 vs 69 | the absolute `t_servo` is at least as good |
| contact-timed backhand swing `bh_lead` 0.42 / 0.47 / 0.52 on run 21's backhand (200 serves) | 1 / 8 / 16 vs 69 | the whole backhand set is tuned for the absolute timing |
| round-9 live tracking (`lt`) at its round-9 parameters | 5 / 12 vs 54 / 31 (fh / bh) | see below |

Computed muscle control (`tt_cmc.py`): MuJoCo's own muscle force model (gain and bias per fibre length and velocity) reproduces the model's actuator forces exactly; the arm's seven
joints have folded inertias 0.003-1.6 kg m^2 and torque capacities +-45-83 N m at the shoulder, +-7-13 N m at the forearm and wrist; a computed-torque law with a bounded
least-squares allocation over the 32 arm muscles saturates on a 0.5 rad move in 0.3 s (about 100 N m against ~50 at the shoulder) and leaves 0.4-0.6 rad errors on the wrist. Porting it
to the controller is days of work for a reflex-limited arm; the prototype is the record.

**A one-tick artifact at the table bounce (`bk`).** The skill logs its servo's aim every third tick (`aim:` rows). In 50 of 150 champion serves one row, at
the tick of the ball's table bounce, shows the height servo's error at -0.3 to -1.6 m and the aim normal's z at -0.45 to -0.75 (its neighbours: -0.1 and -0.1). Every serve has it; one
tick in three is logged. The table-contact flag is set for exactly one 10 ms tick, and on that tick the ball's velocity is mid-reversal (vertical -3.2, +1.4 and -2.8 m/s in three serves:
the sub-tick timing of the bounce). `before` sets `@bounced` and then predicts the crossing of the pad's plane from that velocity as a post-bounce state, so for one tick the predicted crossing height
and vertical speed are wrong by 0.3-1.6 m. The height servo (an integrator, k_z 11) and the normal servo take it in, and the height matching's `at_height` sends the pelvis's goal to the ball's own x.
`bk 1` replaces that tick's ball by the previous tick's, carried through the model's bounce (restitution 0.99); the parent skill got two hooks for it (`plan_ball`, `height_ball`, defaults
unchanged, checked serve for serve). Alone it is worth what its mechanism says, not more: paired on 150 champion serves it raises the hit rate 0.80 -> 0.867 and
solved 41 -> 45 (p 0.27); on the fixed forehand / backhand pools (120 serves each) the hit rate rises 0.90 -> 0.96 and 0.77 -> 0.81 while solved is 50 vs 54 and 34 vs 31. The joints move 0.01-0.03 rad and the pad 1.6 cm higher by contact. It also changes what the champion's
calibration means: the artifact had given the pelvis an accidental 0.2-0.3 m/s of retreat (forehand pad velocity along the normal +0.46 -> +0.27, backhand -0.16 -> -0.48 +- 0.35, exit speeds
+0.25-0.3 m/s), so the extra hits land out until the retreat is restored on purpose.

**Restoring the retreat: a late pelvis kick (`kk`) and a screening design.** `kk` adds an acceleration along +x to the slide's command in the last `kk_t` 0.12 s, sized so the pad's
velocity along its normal reaches `kk_k (v - kk_v0)` (the ball's speed at the plane v), less the side's mean (`kk_m1`, `kk_m2`), times `kk_amp`; the aim law expects 0.9 of it. Its
parameters interact with the aim, the servo gains and the swing (`bh_gain` alone moves the backhand's hit rate from 0.80 to 0.53), and single-parameter screens on 120 serves cannot see
+-3 point effects, so `tt_rsm.py` runs one random two-level design over 17 parameters per side on the same 100 serves (32 runs + the baseline; a run's score is solved + 0.4 x the
landing margin, smooth, and common random numbers remove the serve-to-serve variance) and reads main effects off a regression. The first design's ranges were too wide (a corner
collapsed to 3% solved); the second (`rsm_bh3`: +-25% around the CMA-tuned backhand parameters, wide only on the new ones) gave:

| backhand factor (low / high) | effect on the score (t) | | backhand factor (low / high) | effect on the score (t) |
| --- | --- | --- | --- | --- |
| **`bh_gain` 0.92 / 1.05** | **-0.177 (-4.2)** | | `bh_dur` 0.42 / 0.47 | -0.039 (-0.9) |
| `kk_amp` 0 / 1 | +0.070 (1.8) | | `bh_p_n` 0 / 0.3 | +0.034 (0.8) |
| `kk_v0` 4.4 / 5.2 | +0.037 (1.0) | | `bh_k_n` 2.9 / 4.6 | +0.032 (0.8) |
| `kk_k` 0.3 / 0.7 | -0.033 (-0.8) | | `bh_k_z` 1.6 / 3.2 | -0.031 (-0.8) |
| `kk_m2` -0.65 / -0.3 | -0.021 (-0.6) | | `bh_dnz`, `box_x1`, `lc16`, `box_x0`, `bh_p_z`, `ns_k`, `bh_t_servo`, `k_vpm` | |t| < 0.6 |

The baseline (bk on, no kick) scored 0.442 (27% solved); the design's 32 runs 0.306 +- 0.115 (residual sd of the linear fit 0.086: the surface is peaked around the tuned centre, so
main effects say where to look, not how far to go). The best runs (0.58, 0.57, 0.56, 0.53) all have the kick on, `bh_gain` 0.92 and `bh_p_n` 0.3; three of the four also have the gentle law (`kk_k` 0.3, `kk_v0` 5.2).
Validation on 200 other backhand-pool serves (paired):

| backhand run | solved of 200 | hit | vs champion |
| --- | --- | --- | --- |
| champion | 49 (24.5%) | 0.81 | |
| `bk` only | 50 (25.0%) | 0.87 | |
| consensus of the top runs (K1) | 62 (31.0%) | 0.82 | +0.065 +- 0.039, p 0.065 |
| K1 with `bh_gain` 0.88 | 38 (19.0%) | 0.80 | -0.055, p 0.96 |
| **design run 21** (`params/myo_tt_p2_r10_bh_run21.txt`) | **69 (34.5%)** | 0.83 | **+0.100 +- 0.038, p 0.007** |

Run 21's backhands: exit speed 5.42 +- 0.67 m/s (champion 5.85 +- 0.88), exit elevation 25 +- 17 degrees (16 +- 23), ball-minus-pad height offset sd 4.5 cm (6.0), yaw error to the aim
5.1 degrees (6.7), pad velocity along the normal -0.10 +- 0.48; the gain is in the crossings between y -0.8 and -0.25 (solved 0.16 -> 0.43 and 0.20 -> 0.38; the far-left serves stay out of reach).

**Two more screens for the backhand.** Stage 2 (`rsm_bh4`: 16 factors within +-10-40% around run 21, fresh serves bh[400:500], 13 of 28 runs done) found run 21 at a local peak in those directions: it scored 0.501 (28%) and only
one of 13 design runs beat it. Stage 3 (`rsm_bh5`: the eight posture parameters, the slide offset, lateral trim, grip and two swing offsets, 20 runs on the same fresh serves; baseline 0.501, design mean 0.400) read: `bh_dz_hit` (the
contact height offset, -0.03 / +0.03) -0.139 (t -2.7), `bh_elbow` (1.98 / 2.04) +0.129 (2.4), `bh_dev` (-0.11 / -0.04) +0.082 (1.6), `bh_dd_push` +0.088 (1.4), `bh_trunk_ar` +0.063 (1.4), the rest |t| < 1. On the 200 validation serves
its linear half step (`bh_elbow` 2.025, `bh_dev` -0.0575, `bh_dz_hit` -0.015, `bh_dd_push` +0.01: four parameters moved by 0.01-0.03) solved 79 (39.5%) against run 21's 69 (p 0.043), the full step 80, and the two best design runs 58 and 54:
again the linear step generalised and the winning design runs did not.

**The forehand's design was flat** (`rsm_fh3`, narrower still: baseline 41% solved, the 32 runs averaged 0.616 against 0.663): with the kick on the forehand loses (16 runs with the kick off: 41.2% solved, hit 0.92; 16 with it on: 33.9%),
because its pad already retreats (+0.27 m/s once the artifact is gone). Effects (t): `kk_m1` -3.6, `t_lock` (0.02 / 0.035) -2.5, `kk_amp` -2.4, `lc0` (the forehand's height target, -0.02 / +0.02) -2.3, `t_servo` (0.26 / 0.30) +2.2,
`kk_v0` -2.2, `p_z` -1.8, `box_x1` +1.4. The best design runs did not generalise (run 16: 48% in-sample, 37.0% of 200 new serves against the champion's 39.5%); the linear step (kick off, `t_servo` 0.30, `lc0` -0.02, `p_z` 0,
`box_x1` -0.65, `t_lock` 0.02) did on those 200 (90 solved, +5.5 points, p 0.097) and then did not on the two fresh blocks below (forehand 118 against 110 of 290 and 52 against 58 of 134): by speed it is far better on the slowest
fifth of serves (0.78 against 0.49) and worse on the middle (0.34 against 0.53, 0.23 against 0.39). The forehand's change is worth nothing measurable, so the final candidate leaves the forehand alone.

**Candidates**, each a parameter file for the frozen `bin/challengers/myo_tt_r10-n`, paired against the round-5 champion on two blocks of fresh serves (none used to tune anything):
- c1 (`params/myo_tt_p2_r10_c1.txt`): the backhand of run 21 (its kick, aim and swing values under the backhand's own names `kk2_amp`, `kk2_k`, `kk2_v0`, `ns_k2`, `k_vpm2`, `bh_box_dx`) + the forehand's linear step, `bk 1`.
- c2 (`params/myo_tt_p2_r10_c2.txt`): the same backhand and the champion's forehand exactly (`bk 2`: the bounce-tick guard on the backhand only; 30 of 30 forehand serves identical to the champion's on every metric). A candidate that is
  the champion wherever it has no gain has no flips there, so the arena's paired sign-flip test has less noise.
- **c3** (`params/myo_tt_p2_r10_c3.txt`): c2 + the stage-3 half step. This is the promoted champion.

| | champion | c1 | c2 | c3 |
| --- | --- | --- | --- | --- |
| 710000-710599: solved | 182 (30.3%) | 213 (35.5%), p 0.013 | 206 (34.3%), p 0.007 | **208 (34.7%)**, +0.043 +- 0.016, **p 0.004** (flips 58 / 32) |
| 710000-710599: forehand / backhand of 290 / 310 | 110 / 72 | 118 / 95 | 110 / 96 | 110 / 98 |
| 720000-720299: solved | 90 (30.0%) | 110 (36.7%), p 0.017 | 117 (39.0%), p < 0.0001 | **131 (43.7%)**, +0.137 +- 0.024, **p < 0.0001** (flips 50 / 9) |
| 720000-720299: forehand / backhand of 134 / 166 | 58 / 32 | 52 / 58 | 58 / 59 | 58 / 73 |
| both blocks: solved | 272 of 900 (30.2%) | 323 (35.9%) | 323 (35.9%) | **339 (37.7%)** |
| both blocks: backhand | 104 of 476 (21.8%) | 153 (32.1%) | 155 (32.6%) | **171 (35.9%)** |
| `tt_p2_300` (arena, 300 serves) | 99 (33.0%) | 106 (35.3%), +0.023, p 0.26 | not run | **120 (40.0%), +0.070, p 0.002: promoted** |
| `tt_p2_300` forehand / backhand of 156 / 144 | 60 / 39 | | | 60 / 60 |
| `tt_p2_backhand` (131 serves) | 22.9% | 35.9%, +0.130, p 0.001 | | 35.9%, +0.130, p 0.001: promoted |
| `tt_p1` (50 serves, the P1 params) | 100% | | | 100% |

The arena's 300 seeds flatter the round-5 champion (33.0% against its 30.3% and 30.0% on the fresh blocks, its backhand 27.1% against 21.8%), which is why c1's +5.2 points on 600 fresh serves showed as +2.3 there;
c3's forehand is the champion's, so its 60 of 156 is the same 60 and the whole gain is the backhand's 39 -> 60 of 144. The backhand's gain on the validation serves (+10 points for run 21) held on the fresh blocks: a design run
picked from 32 is still a winner, but not a fluke. By serve speed (backhands of both blocks, 476 serves): solved 0.38 / 0.31 / 0.23 / 0.14 / 0.03 for the champion against 0.48 / 0.45 / 0.23 / 0.21 / 0.24 for c1 over the speed
quintiles: the kick makes the fastest fifth returnable (0.03 -> 0.24) and does nothing for the middle. Where the backhand still fails (share of its hits that do not land, c1): wide 18%, long 13%, both 7%, net or short 17%: the lateral
spread of its landings is 0.8 m sd (the table is 1.52 m wide) and the exit elevation spread 18 degrees.

**Round 9's live tracking, re-examined on the fast path.** With the round-9 parameters (`lt 1`) on the first 120 serves of each side pool, the forehand's face follows its aim (pitch error to the aim
-0.2 +- 2.8 degrees against the champion's -2.4 +- 9.8) and the forehand solves 5 of 120: the ready posture puts the pad at 1.36 m against a ball crossing at 1.21 (the servo error stays at -0.25 to -0.45 m from 0.31 s on) and
86% of the misses pass over the pad. A finite-difference pose Jacobian of the seven forehand posture parameters (ready pose at 0.25 s, per +0.1 rad: elbow pitch -3.9 degrees / pad +2.7 cm, `sh_elv` +1.8 cm,
`dev` -5.6 degrees, `sh_rot` yaw +4.3 degrees) and one least-squares step to the aim's mean pose raised the forehand's hit rate from 0.30 to 0.83 at once, and 1 of 60 serves solved: the returns went wide
(exit y-velocity -1.5 +- 1.7 m/s, the face's yaw 4.5 +- 5.1 degrees past the aim where the champion's forehand yaw follows to 0.3 +- 2.4). Faster height servos (`k_z` 12-20, `t_servo` 0.15) raise the hit rate to 0.5-0.6 and solve 1-2 of
120: the pad is still moving at contact (pad velocity along the normal -0.3 +- 1.0 m/s, exit speed sd 1.8). The live-tracked arm needs its aim law re-calibrated (yaw follow, restitution, the pad-velocity expectation) and its servo
re-tuned together; that is round 9's conclusion and it stands.

**Where it stands.** `tt_p2_300` 40.0% (120 of 300, promoted; 33.0% before round 10; the winner scored 64%). The round-5 champion's failures were the arm's: the face is 10 degrees (1 sigma) off the aim law's normal on both sides, the pad's velocity along it wanders 0.5 m/s, the ball meets the pad 5 cm off its
centre, and the success ceiling of a perfect plan at that noise is ~45% (table above). Every plan-level change (pelvis governor, kick, aim biases, boxes, servo timing and gains) moves the count by less than the noise except the two
that change what the arm does: removing the artifact that kicked the servo at the bounce (worth hits, not landings, until the retreat is put back on purpose) and re-tuning the backhand's kick, swing gain and servo together on a fixed
set of serves. Blockers, in order: (1) face authority: the forehand's wrist sits at its extension limit, the pitch servo's follow ratio is 0.4-0.5 and the pitch error is 76% predictable from the serve, i.e. systematic, but
posture changes that remove it move the pad's place (the backhand's hit rate fell 0.87 -> 0.72-0.77 for a 5-8 degree change of its bias); (2) the pad's velocity (0.5 m/s: the arm alone 0.33-0.42) which decides the return's speed and which the
fast half of the serves need to retreat from; (3) the slide's reach for the far-left serves (the pelvis actuator's step response, kp 3500 N/m against 1000 N s/m of damping, ctrl limited to +-1 m, gets it to ~0.85 m in 0.5 s: 7% of serves cross beyond -0.8 m and are hit 33% of the time); (4) rim hits (12% forehand, 21% backhand).
A controller that follows its aim to 4 degrees, 0.25 m/s and 3 cm would reach 70-90% (table above). For reference the challenge's winner scored 64% and the best reported result is 80.3% (Diff-Muscle, arXiv 2603.08617).

```sh
./build.sh myo_tt_v11                         # round-10 build (every option off = the round-5 champion serve for serve); frozen copies bin/challengers/myo_tt_r10-a ... -n
TT_ENV=P2 .venv-myo/bin/python playground/tt_eval.py --params params/myo_tt_p2_r10_c1.txt --controller bin/challengers/myo_tt_r10-n \
  --seeds 710000:710600 --out out/tt_r10/mix_c1.jsonl --workers 3          # 600 fresh serves
.venv-myo/bin/python playground/tt_cmp.py out/tt_r10/champ_710000.jsonl out/tt_r10/mix_c1.jsonl                     # paired against the champion's baseline
.venv-myo/bin/python playground/tt_rsm.py design --params params/myo_tt_p2_r5_bhprac.txt --controller bin/challengers/myo_tt_r10-k --pool bh --n 100 --runs 32 \
  --set "bk=1,kk=1,kk_amp=0,kk_m1=0.27,kk_m2=-0.48,lc=1,lt_arms=0" --out out/tt_r10/rsm_bh3 --factors "kk_amp:0:1,...,bh_gain:0.92:1.05,..."   # scratchpad/tt/rsm_run3.sh
.venv-myo/bin/python playground/tt_rsm.py analyze --out out/tt_r10/rsm_bh3
.venv-myo/bin/python playground/arena.py eval tt_p2_300 --params params/myo_tt_p2_r10_c1.txt --controller bin/challengers/myo_tt_r10-n --note "round 10 ..." --promote
```

Campaign log with every command line, pid and result: `scratchpad/tt/LOG.md`; outputs `out/tt_r10/`; analysis scripts `scratchpad/tt/an*.py`.
