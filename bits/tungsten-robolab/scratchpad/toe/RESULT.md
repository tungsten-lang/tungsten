# The runner's commanded toe: does the toe-off keyframe's toe matter? (30 Sep 2026)

Erik's subset-keyframe example: "in the runner's toe-off keyframe, all we care about is that the toe extends." Cheapest candidate of the subset audit (`scratchpad/subsets/REPORT.md`, runner item 1), run as params only: `toe_sweep.py` (output `toe_sweep.log`, `toe_sweep.json`).

Set-up: the runner champion of Erik's keyframe set 3 (trial `run_natural_erik3_48`: `params/search/rn2_erik3_nohr.txt`, frozen controller `bin/challengers/rn2-kf3`, 48 perturbed standing starts 7301-7348, 30 s; metric kin_rms, lower is better; guard: no fall and speed in the 3-4 m/s band) with ONLY the commanded stance-foot toe of one keyframe changed in a copy of the params (`ref_<kf>_st_toe`; the frozen scoring keyframes are untouched). Nothing is written to the arena. The base variant reproduces `champions.json`'s 48 recorded scores exactly (identity check: YES). The score itself has no toe term (kin_rms has no toe group and event_rms excludes toes), so any effect is the toe acting through the dynamics.

| variant (commanded toe, deg; the sign of extension is negative) | starts passing the guard | kin_rms (mean over passing) | paired difference against base, starts both pass |
| --- | --- | --- | --- |
| base: td -14, ms 0, to -30 | 47 of 48 | 19.782 | - |
| toe-off -60 | 45 | 20.250 | +0.469 (worse), p 0.000 |
| toe-off -45 | 47 | 20.246 | +0.464 (worse), p 0.000 |
| toe-off -15 | 44 | 19.753 | -0.030, p 0.000 (3 more starts fail the guard) |
| toe-off 0 | 36 | 19.781 | -0.001, p 0.96 (11 more fail) |
| toe-off +10 | 34 | 19.774 | -0.009, p 0.09 (13 more fail) |
| touchdown toe 0 (was -14) | 47 | 19.932 | +0.150 (worse), p 0.000 |
| touchdown toe -30 | 47 | 19.986 | +0.204 (worse), p 0.000 |
| touchdown, mid-stance and toe-off toes all 0 | 35 | 19.920 | +0.138 (worse), p 0.000 (12 more fail) |

What it says:
- **Erik's reading is right for the toe-off keyframe, with one refinement.** What the toe-off toe has to do is EXTEND: commanded 0 or +10 deg (not extended) loses 11-13 of 48 starts to the guard (falls or out of the speed band), -15 loses 3, -30 (the champion's hand-set value) and -45 lose 1. The exact amount between about -30 and -45 barely matters (kin_rms +0.46 of 19.8, 2.3%, for -45; -60 gives the same, so the command probably saturates at the toe's joint limit). So the honest representation is not a point value but a one-sided constraint: "extend at least about 30 deg at toe-off".
- **The touchdown and mid-stance toes are nearly free.** Moving the touchdown toe by 14-16 deg either way changes kin_rms by 0.15-0.20 (about 1%) with no extra guard failures; they were placeholders (-14 and 0) and the champion was tuned around them, which is why both directions are slightly worse.
- **No performance gain from this sweep.** The best kin_rms (-15: 19.753) is 0.15% better but loses 3 guard starts, which the arena scores as failures; nothing here would be promoted.
- **For partial keyframes:** the concept fits the runner's toe, but only as "pinned, one-sided, with a wide band" at toe-off and "free" at the other two keyframes, and the expected gain is a cleaner description and a smaller search, not a faster runner. The controller-side `_free` flag therefore has low value for this champion (audit value 2); it stays unimplemented.

Reproduce: `.venv/bin/python scratchpad/toe/toe_sweep.py` from `bits/tungsten-robolab` (about six minutes with 6 workers).
