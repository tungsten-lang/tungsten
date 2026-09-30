### Sprinters on a beyond-human body (labelled) (29 Sep, round 4)

**BEYOND-HUMAN, not a human profile.** Round 3 ended at 8.407 m/s on the labelled elite-sprinter body (68 % of its 12.36 ceiling, 8/12 arena starts fall-free) and named what was left: the start and gears 1-4 were never
re-searched on the stronger body. This round asks the honest open-ended question for the control plane: on a clearly invented body **chosen up front**, can the same runner family (`RunGearXSkill`, the gears, the
mean-of-seeds search) be tuned to a fall-free standing-start peak speed above 10 m/s, and what did that body need? **Everything below is a labelled body variant (`playground/profiles/beyond.json`, trial
`sprint_top_speed_v4_beyond`): BEYOND-HUMAN. It is not a claim about human sprinting and is never to be compared with the average, P95, elite2 or sprinter trials.** Run-by-run log with every command line:
`scratchpad/sprint4/LOG.md`.

**The body** (rule and ladder written 2026-09-29 21:18 before any runner, replay or ceiling ran on it; the pick made at 21:52 from two measured ceilings; `changes` in the file is empty). The sprinter profile scaled UP by
round numbers, the smallest step whose ideal-control ceiling is above 14.5 m/s (so that 10 m/s is about 70 % of it; the ladder had no finer step). **The multipliers are an invented stretch**: no measurement or literature
value stands behind strength x2.4 or speed x2.0 on top of a model whose peak forces are already 1.4-2.9x young men's voluntary maxima.

| body | strength | muscle speed | tendon | activation | ideal-control ceiling (t_sw 0.35) |
| --- | --- | --- | --- | --- | --- |
| average | 1.0 | 1.0 | 1.0 | 1.0 | 8.20 m/s |
| P95 | x1.32 | x1.2 | x1.5 | x0.87 | 10.45 |
| sprinter (labelled, round 3) | x1.55 | x1.45 | x1.5 | x0.8 | 12.36 |
| ladder step 1 (measured, not used) | x2.0 | x1.7 | x1.5 | x0.8 | 13.51 (13.09-13.94) |
| **beyond = ladder step 2 (BEYOND-HUMAN)** | **x2.4** | **x2.0** | x1.5 | x0.8 | **16.32 (14.99-16.69 for t_sw 0.37-0.33)** |

Ceiling recipe = the sprinter's (`scratchpad/sprint_knot/ceiling_probe.py`, pitch-free, v4 anatomy, four muscle parts, one sparse chain at 1 m/s from the sprinter's 10 m/s solution, `--cycle 0`, two restarts per speed;
`budget_ceiling.py` at t_sw 0.35), so it carries the usual +-0.5-0.7 m/s. Step 1 gave 13.51 < 14.5 and step 2 16.32 > 14.5, so the rule picked step 2 (step 3, x3.0 / x2.4, was never needed or computed). 10 m/s is 61 % of the
beyond body's ceiling. Budgets per speed (best penalised stance budget, s): step 2: 10 m/s 0.580, 12: 0.481, 14: 0.408, 15: 0.370, 16: 0.367, 17: 0.314, 18: 0.280; the ideal at 16 m/s: contact 0.061 s, aerial 0.157 s, step
3.49 m at 4.59/s, peak vertical force 5.0 BW. Data `out/sprint_limits/probe_v4b_beyondc{1,2}_s1_v*`.
