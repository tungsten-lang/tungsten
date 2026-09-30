
**Porting the runner** (each row is a run in `scratchpad/sprint4/LOG.md`; standing starts are the arena's 221-232, 30 s; flying starts are snapshots of the chain's own running on THIS body; every BEYOND-HUMAN number):

| stage | what it is | result |
| --- | --- | --- |
| replay of round 3's sprinter chain (`run_gearx_v4_sprinter_g5a`) | the entered chain of the sprinter body, unchanged | **0/12**: all fall in the start (2.2-6.4 s), the trunk pitching 0.56 -> 0.69 -> 0.86 rad in the first strides; one-number levers (lean, lean_acc, accel, torso_kp, drives x0.5-0.7, start drives) do not fix it |
| start ES `sa` (gear 1 only, 27 generations, 4 014 rollouts, 10 min) | `hsearch --agg meanall` over the 100 gear-1 tunables from standing starts 31-42, 7 s | lean 0.19 -> 0.02 (the sprinter lever, found by the search); 12 s: 11/12; 30 s: 0/12 (falls 15-27 s after a steady 8.4-8.5 m/s: ONE searched gear already equals the sprinter chain's speed) |
| gear 2 ES `gb` (40 generations, 3 019 rollouts, 16 min) | gear 2 = a copy of gear 1, flying starts from 10 entry + edge-of-instability snapshots (7.2-8.6 m/s), 14 s | 21 unseen snapshots, 24 s: 17/21 survive, **peak 9.87 m/s**; chain 1+2 on the arena starts: 9/12, peaks 9.81-9.88 (9.855) |
| gear 3 ES `gc`/`gd`/`ge` | gear 3 = a copy of gear 2, flying starts from the top of chain 1+2 (9.3-9.9 m/s), 16 s | with the plan caps at their boxes (v_top 9.75, v_cap 10.0) chain 1+2+3: 10/12, peaks 9.82-10.005 (9.924); with the caps raised (v_top 11, v_cap 11.5) peak 10.2 |
| final chain | start (`lean_acc` 0, `lean` 0.06) + gear 2 (`g2_v_on` 7.6) + gear 3 (`g3_v_on` 9.4, caps 11 / 11.5) | see the arena table |

*The finding that mattered: the speed-plan caps bound the top gear.* The gear searches had pushed `v_cap` to 10.0 (its box top) and `v_top` to 9.75: above `v_cap` the landing foot moves forward (speed brake, `k_brake`), and `v_top` sets the drive scale
(`s = drv_floor + (1 - drv_floor) v_des / v_top + k_vd (v_des - v)`), so no chain could exceed ~10 m/s however well its stride was tuned. Widening the two boxes to 8-14 and starting gear 3 at 11.0 / 11.5 moved the same gait from 9.94 to 10.23 m/s
(lab, 14 top-speed snapshots). Every earlier runner box (2.5-10.0) was set on bodies that never reached them.

*What the search needed here that round 3 did not have:* (1) an aggregate that lets a search climb out of a failing incumbent (`hsearch --agg meanall`, opt-in: the mean over ALL seeds, falls do not stop a candidate, so the number of survivors moves the score; the `--agg mean` of round 2
needs an incumbent that already survives every seed); (2) edge-of-instability snapshots (states taken 2 s before a fall) as training states, so 10-16 s rollouts see the trunk drift that only shows after 15-25 s of running; (3) gear twins frozen explicitly (`freeze_twins.py`), so a
search of one gear cannot move another through the fallback; (4) a pruning bound `HSEARCH_UB` above the best possible per-seed score (a bound of 350 under an incumbent scoring 351 pruned every candidate for 15 minutes).
