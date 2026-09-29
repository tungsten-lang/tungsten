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
