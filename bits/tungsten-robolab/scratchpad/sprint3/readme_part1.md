### Sprinters on a stronger body (labelled) (29 Sep, round 3)

Round 2 ended at 8.276 m/s on P95 (79 % of its 10.45 ceiling) and named the one honest route left to 10 m/s: a stronger, **labelled** body, the move that took the bat from 26.5 to 32.4 m/s.
This round defines that body from the literature, computes its ideal-control ceiling, ports the five-gear runner to it and enters a new arena trial. **Everything below is a labelled body
variant (`playground/profiles/sprinter.json`, trial `sprint_top_speed_v4_sprinter`): never compare it with the average, P95 or elite2 trials.** Log of every run with its command line:
`scratchpad/sprint3/LOG.md`.

**The body** (fixed 2026-09-29 18:28, before any runner, replay or ceiling was run on it; `changes` in the file is empty). The same v4 anatomy and the average 1.75 m / 67.5 kg skeleton,
so lengths and masses stay comparable; the rule was the middle of the ranges the literature gives, not their top:

| part | P95 | elite2 | **sprinter** | status |
| --- | --- | --- | --- | --- |
| strength (peak force per kg, every muscle) | x1.32 | hip ext. 1.5, ham 1.4, vasti 1.1, plantarflexors 1.05-1.1, dorsiflexors 1.0 | **x1.55** | literature for hip extensors and hamstrings (Miller 2021 x1.4-1.6 per kg; Handsfield 2017); **chosen stretch** for knee and ankle extensors (strength-trained men x1.58, Maden-Wilkinson 2020; sprinters only x1.07-1.26 vasti, x1.09-1.18 plantarflexors) and every other muscle |
| muscle speed (fibre mix x fascicle length) | x1.2 | x1.3 | **x1.45** | derived: fibre mix x1.23-1.31 (Trappe 2015) times fascicles +12-24 % (Abe 2000, Kumagai 2000) = 1.3-1.5, the middle taken |
| tendon stiffness | x1.5 | Achilles 1.3, quadriceps 1.0 | **x1.5** (P95's) | unchanged on purpose: the sprinter differs from P95 in strength x1.17, speed x1.21, activation x0.92 only; the quadriceps value is P95's, not a sprinter's (Kubo: sprinters' knee tendons are more compliant) |
| activation time constants | x0.87 | 1.0 | **x0.8** | **unverified stretch** (fibre-mix inference gives 0.87-0.89; Tillin 2010's faster neural force onset has no place else in the model); the v4 screen says it barely matters |
| anthropometry | 1.0 | not applied | 1.0 | `ROBOLAB_PROFILE_PARTS=all` builds the same XML as the four muscle parts (checked byte-identical) |

The bat's athlete body is strength x1.5 on every muscle and a uniform fibre speed of 3.0 L0/s on the v1 placeholder body (not comparable with the v2+ speed multipliers); this body's x1.55 sits
on top of the model's peak forces, which are already 1.4-2.9x young men's voluntary maxima (`calibrations/v4.json`), so it is stronger than any measured person in the knee and ankle
extensors, the groups the ceiling is most sensitive to. A result on this body says what a runner could do if a body really had these muscles, not what any person does.

**The ideal-control ceiling of the sprinter (step 2): 12.36 m/s** (stance-budget ceiling at t_sw 0.35 s, 12.01-12.71 for t_sw 0.37-0.33; the margin chain is positive to 12.0 and its line
fits 12.75). Same recipe and measure as the other bodies (`scratchpad/sprint_knot/ceiling_probe.py`, pitch-free, v4 anatomy, default four muscle parts; `budget_ceiling.py v4b_sprinter`),
with one difference in effort: **one sparse chain** (1 m/s spacing from 10 m/s, warm-started from P95's 10 m/s solution, no joint stance-plus-swing refinement, two restarts per speed)
plus the dense points at 8-9.5 m/s of two earlier chains that an external load spike made too slow to finish. The estimate carries the usual +-0.5-0.7 m/s.

| body | average | P95 | elite2 | **sprinter** |
| --- | --- | --- | --- | --- |
| ideal-control ceiling, m/s | 8.20 | 10.45 | 9.28 | **12.36** |
| best runner so far, m/s (share) | 6.170 (75 %) | 8.276 (79 %) | 6.78 (73 %) | see below |

The ideal stance at the ceiling (best stance budget of the sprinter's chains): at 12.0 m/s contact 0.066 s, aerial 0.154 s, step 2.64 m at 4.54 /s, mean / peak vertical force 3.34 / 4.72 BW,
thigh +0.38 at touchdown / -0.73 at lift-off, touchdown knee 0.60, touchdown ankle -0.37 (dorsiflexed, as P95's -0.43), trunk excursion 0.05 rad. At 10 m/s (the
sprinter's ideal is far from its limit there): contact 0.085 s, aerial 0.225 s, step 3.10 m, 3.65 / 5.25 BW. 10 m/s is 81 % of the sprinter's ceiling; round 2's P95 runner reached 79 % of P95's.
