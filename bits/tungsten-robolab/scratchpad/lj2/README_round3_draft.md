### Long jump, round 3 (29 Sep): the two-gear runner under the jump (DRAFT, filled in as results come)

**Goal** (Erik): the best runner for the long jump, then beyond human ability; legality first (TR 29-30). Body: v4 P95 (`ROBOLAB_CALIB=v4`,
p95 profile). The sprint agent's champion `sprint_top_speed_v4_p95` became RunGearSkill (`lib/robolab/skills/run_gear.w`: RunRI with a second gear,
frozen params `params/lj_runner_gear_v4_p95.txt` = `params/run_gear_v4_p95_c.txt` of 29 Sep 05:37; the three-gear `run_gear_v4_p95_e.txt` of 06:45 has
identical gears 1 and 2, gear 3 starts at 7.0 m/s and is never reached in 44 m).

**Wiring.** `LongJumpRunSkill < RunGearSkill` (was RunRISkill); `add_jump_chunks(mv)` puts the jump's chunks on a movement, called from `start` and from a
`switch_gear` override, because a gear change builds a fresh stride movement (RunGearSkill#switch_gear) and swaps it under the track. Opt-in: the
params-file switch `gears 2` (+ the `g2_` twins); without it the run is RunRISkill's exactly. Checked bit-identical on the stored champions' seeds
with build c1 (`bin/challengers/long_jump_run-c1`): `long_jump_v4_p95` 4.945, `long_jump_p95` 5.122, `long_jump_p95_robust` 4.6305 (16), `long_jump_v4_p95_robust`
2.1452 (16): every per-seed score equal.

**The runner at the board.**
The sprint trial's 7.45 m/s (7.86 with three gears) is a 20 s / 100 m speed; the jump's run-up is 44 m. Approach-only rollouts (`j_run 1`, 44 m check mark, the last 5 m
before the mark, 8-17 starts, 0 falls unless stated):

| runner at the jump's scale | v5 (last 5 m, m/s) |
| --- | --- |
| RunRI of the v4 champion (p2a, what round 2 used) | 6.6 |
| two-gear runner as frozen (switch at 6.5 m/s: comes at 40 m) | 6.60 |
| `g2_v_on` 6.0 / 5.5 / 5.0 / 4.5 / 4.0 / 3.5 | 6.73 / 6.78 / 6.82 / 6.85 / 6.84 (3 falls in 8) / 6.84 (1 fall in 8) |
| the three-gear params (gear 3 from 7.0 m/s) | identical to the two-gear ones at 44 m, start by start |

`g2_v_on 5.0` is the setting (+0.22 m/s; 4.5 and lower add nothing or fall). Speed profile with it (5 m windows centred there): 5.1 m/s at 15 m, 6.0 at 25, 6.6 at 35,
6.8 at 40, 6.9 at 44, 6.95 at 45, 7.05 at 50, 7.15 at 55, 7.25 at 65, 7.29 at 75.
The upright final approach costs speed (j_fin_dlean over the last 12.6 m): 6.61 / 6.70 / 6.77 / 6.83 m/s for -0.495 / -0.3 / -0.15 / 0; a shorter stretch (j_fin_d 12.6 / 9 / 6 / 3 m at -0.495)
gives 6.60 / 6.70 / 6.77 / 6.81 m/s with the trunk at the penultimate touchdown at -0.06 / -0.05 / +0.01 / +0.05 rad.

**Foot placement was the v4 jump's real problem.** With the round 2 planner (`j_st_w` 0.09, i.e. no steering) the plant foot's offset from the line was
-1.01 x (the penultimate toe's gap error) - 0.02 (residual sd 0.036: the take-off program did not compensate), and the penultimate touchdown's position varies
over a full step (1.6 m) from start to start, because the stride pattern's phase at 44 m does (the k-th touchdown's position has sd 0.4-0.7 m from the second step
on, 1.0 m at the 20th; the first foot is left on 28 of 49 starts, right on 21). Result on 32 fresh starts: 13 legal, mean 1.58 m. The hip-nudge steering
(`j_st_w` 0.5-0.6, `j_st_max` 0.25-0.3, `j_st_n` 5-6) holds the penultimate toe to sd 0.12-0.16 m and the chunk take-off's plant offset to -0.05 +- 0.07 m.
Its price is a stumble in 1-3% of starts (a short step, then a lengthening request, then a swing-foot double contact); hop-height steering (`j_st_zk`) does not steer at all.

**Ideal-control ceiling, recomputed for this runner** (`long_jump_limits.py optimise`, open-loop excitations of all 32 muscles from the captured penultimate-touchdown
state, forward angular momentum at take-off <= -1.5 kg m2/s, 120k evaluations; ORACLE-class, one start): 5.219 m ballistic from the take-off foot for the nominal
start of the A1 approach (COM 6.59 m/s at the penultimate touchdown; take-off vx 6.32, vz 3.10 m/s, 26.1 deg, contact 0.088 s; the foot 0.17 m behind the line, so 5.05 m from
the line). Round 2's calibrated-body ceiling was 4.89 m from a 6.37 m/s state and the v3 P95's 4.93 m from 6.8-6.9 m/s. The ceiling depends on the state by about +-0.2 m
between neighbouring starts (the search plateaus; the same approach with the other steering settings reached 5.03-5.04), so treat it as 5.0-5.2 m.
The distilled program (`out/long_jump_limits/ik_gp.txt`) run closed-loop on the nominal start (skill build c2): **5.065 m official**, promoted on `long_jump_v4_p95`.

**Two approaches, one take-off program (robust stage).** The take-off program (`j_ik`, from the penultimate touchdown) is trained over captured approach states
(`long_jump_limits.py robust`: 20 starts of one plant side, board-relative ballistic distance, fouls and invalid take-offs penalised). It was tried on two approaches:
- F3, the natural run (the upright torso shift only after the penultimate touchdown, last 5 m 6.81 m/s): 11 of 20 training starts valid, 9 INVALID. Every invalid one is a free-foot touch of the
  runway 0.03-0.05 s after the take-off, and all of them are the fast starts (COM 6.9-7.1 m/s at the penultimate touchdown, gap 1.64-1.79 m: the plant comes 0.07 s early and the free leg is still down).
- A, the upright final approach over the last 12.6 m (v5 6.60 m/s): 20 of 20 valid, 0 fouls, board-relative distance 4.02 m mean (3.81 min), foot 0.052 +- 0.041 m behind the line
  although the penultimate gap has sd 0.166 (the program compensates: plant offset = -0.22 x gap error).
The upright approach costs 0.2 m/s and is what a single take-off program can be robust to.

**Steering (`j_st_*`) works one way.** A request to lengthen the next step comes out as a shorter one (traces of arena starts 404 and 416: plan 1.83 m against a stride of 1.65, step 1.45 m):
a forward reach makes the foot touch down early. Shortening works. The starts that need lengthening end with the penultimate touchdown 0.2-0.5 m too far from the line,
and no single take-off program takes those (foot 1.8 m behind the line, or a runway touch after take-off). `j_st_rnd` (new, default 0.5 = the old rounding) rounds the number of
steps left toward 1.0, so the plan shortens instead: penultimate gap errors on 80 starts -0.34..+0.32 (0.5), -0.38..+0.18 (0.75), -0.44..+0.11 (1.0). 0.75 is used.
Other options that did not steer: hop-height (`j_st_zk`), a speed clamp (`g2_v_cap` with `g2_k_brake`), longer or gentler horizons (`j_st_n` 7-10), larger caps.
The hip-nudge steering leaves a pen-gap sd of 0.13-0.17 m; the take-off program has to absorb it.
