
**Ideal-control ceiling, recomputed for this runner** (`long_jump_limits.py optimise`: open-loop excitations of all 32 muscles from the captured penultimate-touchdown state,
forward angular momentum at take-off <= -1.5 kg m2/s; ORACLE-class, one start). From the nominal start of the first approach (COM 6.59 m/s at the penultimate touchdown, 120k evaluations):
**5.219 m ballistic from the take-off foot** (vx 6.32, vz 3.10 m/s, 26.1 deg, contact 0.088 s, foot 0.17 m behind the line: 5.05 m from the line). Round 2's ceiling for the calibrated body was 4.89 m from a
6.37 m/s state, the v3 P95's 4.93 m from 6.8-6.9 m/s. The estimate moves by about +-0.2 m between neighbouring starts (the search plateaus): 5.03 (upright approach, other steering), 4.96 (natural run), 4.83 (trunk
forward), so read it as 5.0-5.2 m. Board-relative (foot held 3 cm behind the line) the same state gives 5.13 m from the line. What the ceiling depends on (same state, 60k evaluations from the same start;
`ROBOLAB_LJ_DV`, `ROBOLAB_LJ_FSCALE`): a body moving 0.4 / 0.8 m/s faster: 5.22 / 5.52 m (vs 5.03: +0.5 to +0.6 m per m/s); muscles 20 / 40 % stronger: 5.43 / 5.91 m (+0.39 / +0.88 m).

**Foot placement was the v4 jump's real problem.** Round 2's planner had `j_st_w` 0.09, i.e. no steering. The plant foot's offset from the line then was -1.01 x (the penultimate toe's gap error) - 0.02
(residual sd 0.036: the take-off program did not compensate), and the penultimate touchdown's position varies over a full step (1.6 m) from start to start: the stride pattern's phase at 44 m does (the k-th
touchdown's position has sd 0.4-0.7 m from the second step on; the first foot is left on 28 of 49 starts, right on 21). On 32 fresh starts that was 13 legal, mean 1.58 m. The hip-nudge steering
(`j_st_w` 0.5, `j_st_max` 0.25, `j_st_n` 5) holds the penultimate gap to sd 0.13-0.17 m; its price is a stumble in 1-3 % of starts. Two things about it: a request to LENGTHEN the next step comes out as a
shorter one (arena starts 404 and 416: plan 1.83 m against a stride of 1.65, step 1.45 m: a forward reach makes the foot touch down early), shortening works, so the starts that need lengthening ended with the
penultimate touchdown 0.2-0.5 m too far from the line and no program takes those; `j_st_rnd` 0.75 rounds the number of steps left up, so the plan shortens instead (gap errors on 80 starts -0.38..+0.18 against -0.34..+0.32).
Options that did not steer: hop height (`j_st_zk`), a speed clamp (`g2_v_cap` with `g2_k_brake`), gentler or longer horizons (`j_st_n` 7-10, caps 0.1-0.15), larger caps. Other steering settings give more invalid or
foul starts (125 captured approaches each, fixed program, legal mean: 3.5-3.7 m against 4.0 m for the chosen one).

**Take-off program (`j_ik` from the penultimate touchdown; `long_jump_limits.py robust`).** The program is trained over captured approach states (board-relative ballistic distance, fouls and invalid take-offs
penalised), and the gap knots let it place the plant foot whatever the penultimate gap: on 125 captured approaches its plant offset is -0.05 m with sd 0.05 against a gap sd of 0.15 (slope -0.04..-0.26, was -1).
Two lessons. (1) The approach decides whether one program is enough. With the natural run (torso servo only after the penultimate touchdown, 6.81 m/s over the last 5 m) 9 of 20 training starts were invalid:
all the fast ones (COM 6.9-7.1 m/s at the penultimate touchdown, gap 1.64-1.79 m: the plant comes 0.07 s early, the free leg is still down and its toes touch the runway 0.03-0.05 s after the take-off). With the upright final
approach (torso servo over the last 12.6 m, 6.60 m/s) all 20 were valid. The upright approach costs 0.2 m/s and is what a single program can be robust to. (2) Training on both plant sides (mirrored role tables) and on a
gap-stratified set (32 of the 125 approaches captured from seeds 8001-8128) took the held-out harness score to 86 valid of 93 (3 fouls), mean 4.39 m board-relative. The price of one program: on the nominal start it takes off with vz 2.4 m/s where
its own ideal has 3.1 (harness 4.13 m against 4.86 m), and the fast short-gap starts (gap 1.6-1.8 m, COM 6.7-6.9 m/s) get vz 1.4-1.8 m/s: keeping the foot behind the line from a short gap takes a shorter plant step. The harness predicts the
full rollouts start by start (the harness-invalid starts of the 16 arena starts are the fell-in-run ones; the valid ones jump within -0.1..+0.3 m of their harness distance).
What did not work: interpolating two ideals (nominal and short gap) into a linear-in-gap program (the short-gap ideal from the foot-based search put the foot 0.45 m over the line, the board-relative one stopped at 3.1 m); a swing-foot lag feedback by
greedy selection (the v3 recipe: the invalid count did not fall); a chunk take-off as a fallback for the invalid starts (1 of 12 legal).

**Landing.** The landing program (`il_*`, excitation knots on the ballistic-time clock `il_tg`) was learned on 62 hand-overs (32 starts and a variant each), then 30 generations over all 117 valid hand-overs of the captured approaches, both sides: the
chunk landing rolls over on every short-flight hand-over (vz 1.4-1.9 m/s), the table lands 114 of 117 of them (marks 4.2-4.9 m from the line in the harness). It took the legal count on 96 fresh starts from 60 to 72 (the take-off unchanged).
