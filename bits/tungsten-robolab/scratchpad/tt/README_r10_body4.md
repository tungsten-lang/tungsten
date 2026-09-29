**Three more screens for the backhand.** Stage 2 (`rsm_bh4`: 16 factors within +-10-40% around run 21, fresh serves bh[400:500], 13 of 28 runs done) found run 21 at a local peak in those directions: it scored 0.501 (28%) and only
one of 13 design runs beat it. Stage 3 (`rsm_bh5`: the eight posture parameters, the slide offset, lateral trim, grip and two swing offsets, 20 runs on the same fresh serves; baseline 0.501, design mean 0.400) read: `bh_dz_hit` (the
contact height offset, -0.03 / +0.03) -0.139 (t -2.7), `bh_elbow` (1.98 / 2.04) +0.129 (2.4), `bh_dev` (-0.11 / -0.04) +0.082 (1.6), `bh_dd_push` +0.088 (1.4), `bh_trunk_ar` +0.063 (1.4), the rest |t| < 1. On the 200 validation serves
its linear half step (`bh_elbow` 2.025, `bh_dev` -0.0575, `bh_dz_hit` -0.015, `bh_dd_push` +0.01: four parameters moved by 0.01-0.03) solved 79 (39.5%) against run 21's 69 (p 0.043), the full step 80, and the two best design runs 58 and 54:
again the linear step generalised and the winning design runs did not. Stage 4 (`rsm_bh6`: the backhand's own dynamics not yet screened, co-contraction, postural tone, the slide's fly-by, a swing shift, a later contact plane and the lateral trim, plus
refreshers of the kick, gain and servo values, 14 factors, 24 runs on fresh serves bh[500:600]; baseline 0.577, design mean 0.513, residual sd 0.053) read: `bh_dt_swing` -0.092 (t -3.1), `bh_gain` (0.91 / 0.94) -0.063 (-2.2), `bh_pel_fly`
(0 / 0.6: the backhand's fly-by slide) +0.071 (2.1), `bh_dx_hi` -0.070 (-2.0), `lc24` +0.048 (1.7), `ns_k2` +0.050 (1.5). This time the top design runs replicated: on the 200 validation serves runs 7 and 18 solved 91 and 95 against
c3's 79, and on 196 backhand serves nobody had used (`bh[600:796]`) the round-5 champion solved 44 (22.4%), c3 72 (36.7%), the consensus of runs 7 and 18 (c4) 88 (44.9%), run 18 93 (47.4%, +10.7 points over c3, p 0.006), run 7 80. Run 18 =
the fly-by slide at 0.6, `bh_gain` 0.91, `bh_stiff` 0.13, kick 1.2 with `kk_m2` -0.55, `bh_p_n` 0.2, `bh_dnz` -0.05, `k_vpm2` 0.7, `lc24` -0.02. Its backhands on those 196 serves (round-5 champion / c3 / run 18):
exit speed 5.93 +- 0.85 / 5.43 +- 0.69 / 4.99 +- 0.57 m/s (5 m/s is where the feasible elevation window is widest), exit elevation 18 +- 25 / 29 +- 18 / 24 +- 15 degrees, ball-minus-pad height offset sd 5.5 / 4.4 / 3.3 cm,
pad pitch sd 9.9 / 7.6 / 5.9 degrees, hit rate 0.80 / 0.89 / 0.90.

**The forehand's design was flat** (`rsm_fh3`, narrower still: baseline 41% solved, the 32 runs averaged 0.616 against 0.663): with the kick on the forehand loses (16 runs with the kick off: 41.2% solved, hit 0.92; 16 with it on: 33.9%),
because its pad already retreats (+0.27 m/s once the artifact is gone). Effects (t): `kk_m1` -3.6, `t_lock` (0.02 / 0.035) -2.5, `kk_amp` -2.4, `lc0` (the forehand's height target, -0.02 / +0.02) -2.3, `t_servo` (0.26 / 0.30) +2.2,
`kk_v0` -2.2, `p_z` -1.8, `box_x1` +1.4. The best design runs did not generalise (run 16: 48% in-sample, 37.0% of 200 new serves against the champion's 39.5%); the linear step (kick off, `t_servo` 0.30, `lc0` -0.02, `p_z` 0,
`box_x1` -0.65, `t_lock` 0.02) did on those 200 (90 solved, +5.5 points, p 0.097) and then did not on the two fresh blocks below (forehand 118 against 110 of 290 and 52 against 58 of 134): by speed it is far better on the slowest
fifth of serves (0.78 against 0.49) and worse on the middle (0.34 against 0.53, 0.23 against 0.39). The forehand's change is worth nothing measurable, so the candidates below leave the forehand alone. A last forehand screen (`rsm_fh5`, r10-p) added the forehand's arm reflex gain (`fh_gain`, the analogue of `bh_gain`),
its seven posture parameters, servo timing and gains and the lateral trim (15 factors, 24 runs on fresh serves fh[400:500]) around the champion's forehand: the design averaged 0.274 against the champion's 0.623 and its best run scored 0.615;
`fh_gain` alone (0.88 / 1.10) read +0.236 (t 9.9) and scanning it on 200 forehand serves nobody had used solved 80 / 85 / 76 / 68 / 60 at 0.97 / 1.00 / 1.03 / 1.06 / 1.10: the champion's forehand sits on a sharp optimum of every
parameter screened, which is why only the backhand moved.

**Candidates**, each a parameter file for the frozen `bin/challengers/myo_tt_r10-n`, paired against the round-5 champion on two blocks of fresh serves (none used to tune anything):
- c1 (`params/myo_tt_p2_r10_c1.txt`): the backhand of run 21 (its kick, aim and swing values under the backhand's own names `kk2_amp`, `kk2_k`, `kk2_v0`, `ns_k2`, `k_vpm2`, `bh_box_dx`) + the forehand's linear step, `bk 1`.
- c2 (`params/myo_tt_p2_r10_c2.txt`): the same backhand and the champion's forehand exactly (`bk 2`: the bounce-tick guard on the backhand only; 30 of 30 forehand serves identical to the champion's on every metric). A candidate that is
  the champion wherever it has no gain has no flips there, so the arena's paired sign-flip test has less noise.
- **c3** (`params/myo_tt_p2_r10_c3.txt`): c2 + the stage-3 half step. This is the promoted champion.
- c5 (`params/myo_tt_p2_r10_c5.txt`): c3 + stage 4's run 18. Best on fresh serves; not promoted (the arena's 300 seeds cannot tell it from c3).

| | champion | c1 | c3 | c5 |
| --- | --- | --- | --- | --- |
| 710000-710599: solved | 182 (30.3%) | 213 (35.5%), p 0.013 | 208 (34.7%), +0.043 +- 0.016, p 0.004 | **237 (39.5%)**, +0.092 +- 0.017, p < 0.0001 (flips 83 / 28) |
| 710000-710599: forehand / backhand of 290 / 310 | 110 / 72 | 118 / 95 | 110 / 98 | 110 / 127 |
| 720000-720299: solved | 90 (30.0%) | 110 (36.7%), p 0.017 | 131 (43.7%), +0.137 +- 0.024, p < 0.0001 | **131 (43.7%)**, +0.137 +- 0.023, p < 0.0001 |
| 720000-720299: forehand / backhand of 134 / 166 | 58 / 32 | 52 / 58 | 58 / 73 | 58 / 73 |
| both blocks: solved | 272 of 900 (30.2%) | 323 (35.9%) | 339 (37.7%) | **368 (40.9%)** |
| both blocks: backhand | 104 of 476 (21.8%) | 153 (32.1%) | 171 (35.9%) | **200 (42.0%)** |
| 196 backhand serves nobody had used | 44 (22.4%) | | 72 (36.7%) | **93 (47.4%)** |
| `tt_p2_300` (arena, 300 serves) | 99 (33.0%) | 106 (35.3%), +0.023, p 0.26 | **120 (40.0%), +0.070, p 0.002: promoted** | 121 (40.3%) against c3: +0.003, p 0.51 |
| `tt_p2_300` forehand / backhand of 156 / 144 | 60 / 39 | | 60 / 60 | |
| `tt_p2_backhand` (131 serves) | 22.9% | 35.9%, +0.130, p 0.001 | 35.9%, +0.130, p 0.001: promoted | 41.2%, +0.053 against c3, p 0.17 |
| `tt_p2` (the old 100-serve trial) | 36.0% | | 39.0%, +0.030, p 0.30 | 44.0%, +0.080, p 0.040: promoted there |
| `tt_p1` (50 serves, the P1 params) | 100% | | 100% | |

Pooled over the 900 fresh serves (paired): c3 against the round-5 champion +0.074 +- 0.013 (flips 108 / 41), c5 against the champion +0.107 +- 0.014 (131 / 35), c5 against c3 +0.032 +- 0.013 (p 0.0066; flips 80 / 51). On 200
more backhand serves nobody had used (pool 750000) the champion solved 46 (23.0%), c3 82 (41.0%), c5 92 (46.0%). A fifth backhand screen around c5 (`rsm_bh7`, +-0.02-0.3 along stage 4's directions) found nothing better: its linear step, half step
and two best runs scored 81, 92, 73 and 82 there.

The arena's 300 seeds flatter the round-5 champion (33.0% against its 30.3% and 30.0% on the fresh blocks, its backhand 27.1% against 21.8%), which is why c1's +5.2 points on 600 fresh serves showed as +2.3 there;
c3's forehand is the champion's, so its 60 of 156 is the same 60 and the whole gain is the backhand's 39 -> 60 of 144. c3 and c5 score alike in the arena (120 and 121) and on block 2 (131 and 131), and differ by 29 serves on block 1 and by 21 of 196 backhands on the never-used serves: the arena, with 300
serves and about +-7 wins of noise on the backhand alone, cannot separate a 6-point backhand difference. The backhand's gain on the validation serves (+10 points for run 21) held on
the fresh blocks: a design run picked from 32 is still a winner, but not a fluke. By serve speed (backhands of both blocks, 476 serves): solved 0.38 / 0.31 / 0.23 / 0.14 / 0.03 for the champion against 0.48 / 0.45 / 0.23 / 0.21 / 0.24 for c1
over the speed quintiles: the kick makes the fastest fifth returnable (0.03 -> 0.24) and does nothing for the middle. Where the backhand still fails (share of its hits that do not land, c1): wide 18%, long 13%, both 7%, net or short 17%:
the lateral spread of its landings is 0.8 m sd (the table is 1.52 m wide) and the exit elevation spread 18 degrees.
