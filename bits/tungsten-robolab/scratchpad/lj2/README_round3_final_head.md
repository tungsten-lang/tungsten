### Long jump, round 3 (29 Sep): the two-gear runner, steered foot placement, a take-off program that survives a fresh start

Erik's goal: the best runner for the long jump, then beyond human ability, legality first (World Athletics TR 29-30). Body: v4 P95 (`ROBOLAB_CALIB=v4`, p95 profile),
the trials of round 2 (`long_jump_v4_p95`, `_robust` 16 starts, `_robust32` 32 fresh starts) plus the new `long_jump_v4_p95_robust96` (96 fresh starts, seeds 9033-9128).
The runner is part of the challenger, not of the trial. Label used throughout: ORACLE = open-loop excitation programs and near-open-loop knots (the take-off program's
reflex gain is 0.46 around its excitation table, the landing table's 0.14); one-start numbers are overfit to that start by construction; only the robust trials count as the jump.

**The runner.** The sprint agent's champion `sprint_top_speed_v4_p95` became RunGearSkill (`lib/robolab/skills/run_gear.w`, RunRI with gears: the stride is rebuilt from `g<k>_`
twins of every tunable the first flight after the filtered speed reaches `g<k>_v_on`). Frozen copies for the jump: `params/lj_runner_gear_v4_p95.txt` (= `run_gear_v4_p95_c.txt`,
29 Sep 05:37, 7.449 m/s peak, gears 2), `params/lj_runner_gear3_v4_p95.txt` (= `_e.txt`, 06:45, 7.862) and `params/lj_runner_gear4_v4_p95.txt` (= `_g.txt`, 07:53, 7.907).
Gears 1 and 2 are identical in all three files, and gear 3 needs the filtered speed to reach 7.0 m/s, which a 44 m run-up does not: the jump reaches 6.6-6.9 m/s at the
board (the sprint numbers are 20 s / 100 m speeds), and approach-only rollouts of the two- and three-gear params are identical start by start. The jump uses the two-gear file.

**Wiring.** `LongJumpRunSkill < RunGearSkill` (was RunRISkill). `add_jump_chunks(mv)` puts the take-off, ik, il and flight chunks on a movement; it is called from `start` and from a
`switch_gear` override, because a gear change builds a fresh stride movement (RunGearSkill#switch_gear) and swaps it under the track. Opt-in: the params-file switch `gears N`
(plus the `g<k>_` twins); without it the run is RunRISkill's exactly. Replays of every earlier champion with the rebuilt controller are per-seed identical to the stored scores:
`long_jump_p95` 5.1220, `long_jump_p95_robust` 4.6305 (16 starts), round 2's v4 one-start 4.945 and its 16-start params 2.1452. New opt-in skill options (defaults bit-identical):
`j_st_rnd` (rounding of the step count in the run-up plan), `j_st_up`, `j_st_zk`. Harness (`playground/long_jump_limits.py`): `robust` and `landing` train on both plant sides
(`side_perm` / `mirror_tab`), plus `ROBOLAB_LJ_BOARD` / `_TD` / `_MARGIN` / `_DV` / `_FSCALE` options (a board-relative ideal, a fixed plant-touchdown time, a foul margin,
a faster or stronger body); single-side runs are unchanged (checked against the HEAD version of the file).

**Speed at the board** (approach only, `j_run 1`, last 5 m before the check mark, 17 starts, no falls in any cell):

| check mark | RunRI (round 2's runner) | two-gear as frozen (switch 6.5 m/s) | two-gear, `g2_v_on` 5.0 |
| --- | --- | --- | --- |
| 30 m | 6.02 | 6.02 | 6.22 |
| 35 m | 6.28 | 6.28 | 6.48 |
| 40 m | 6.47 | 6.47 | 6.69 |
| 44 m | 6.59 | 6.62 | **6.83** |
| 45 m | 6.62 | 6.67 | 6.86 |

The frozen switch at 6.5 m/s comes at 40 m, so the two-gear runner is RunRI up to there. Moving it to 5.0 m/s gives +0.22 m/s (4.5: +0.03 more; 4.0: 3 falls in 8). Speed profile with it (5 m windows): 5.1 m/s at 15 m,
6.0 at 25, 6.6 at 35, 6.9 at 44, 7.05 at 50, 7.25 at 65: a longer run-up adds about 0.05 m/s per 5 m. What the jump does with it: the upright final approach that the take-off needs costs 0.2 m/s
(torso servo over the last 12.6 m: 6.61 m/s against 6.83 without), so the jump's last-5-m speed is 6.6 m/s.
