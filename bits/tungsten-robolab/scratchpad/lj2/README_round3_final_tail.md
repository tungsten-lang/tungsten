
**Arena** (all promotions paired; `long_jump_v4_p95_robust96` is new: 96 fresh starts, seeds 9033-9128, seeded with round 2's champion). ORACLE-class programs throughout:

| trial | body | before | champion now | verdict |
| --- | --- | --- | --- | --- |
| `long_jump_v4_p95` (1 start) | v4 P95 | 4.945 m | **5.209 m** (feet mark, ballistic 5.035, foot 0.07 m behind the line) | promoted three times: 5.065 (this start's ideal-control program, chunk landing: head mark), 5.166 (+ a learned landing table), 5.209 (a board-relative ideal, chunk landing); overfit to the start by construction |
| `long_jump_v4_p95_robust` (16) | v4 P95 | 2.145 m (9 legal) | **3.412 m**, 12 of 16 legal (`params/long_jump_v4_gear_final1.txt`) | +1.27, p = 0.047 |
| `long_jump_v4_p95_robust32` (32 fresh) | v4 P95 | 2.851 m (25 legal) | **4.501 m**, 31 of 32 legal (`final1`) | 3.923 (milestone M1, p = 0.005), then 4.501 (+0.58, p = 0.002) |
| `long_jump_v4_p95_robust96` (96 fresh, new) | v4 P95 | 2.536 m (baseline) | **3.724 m**, 77 of 96 legal (`params/long_jump_v4_gear_final2.txt`) | 3.471 (M1, p < 0.001), then 3.724 (+0.25, p = 0.039); `final1` scored 3.659 there (p = 0.14) |

Controller for all of them: `bin/challengers/long_jump_run-c3` (skill build c3; the arena froze copies under `bin/champions/`). `arena.py recheck` reproduces every long-jump champion, per seed, with its frozen binary.

**Per start** (official mark in m; a failed jump scores 0; the class of each failure). `final1`, the 16 arena starts (12 legal, mean 3.412; mean of the legal 4.549, 4.10-4.84):
401 4.25; 402 4.68; 403 4.59; 404 fell in the run; 405 4.84; 406 4.53; 407 somersault; 408 4.77; 409 foul (27 mm); 410 4.61; 411 4.75; 412 4.10; 413 4.48; 414 4.63; 415 4.35; 416 somersault.
`final1`, the 32 fresh starts (31 legal, mean 4.501; legal mean 4.646, 3.91-4.86): 9001 4.38; 9002 4.50; 9003 4.84; 9004 4.79; 9005 4.74; 9006 4.37; 9007 4.46; 9008 4.68; 9009 4.86; 9010 somersault; 9011 4.85; 9012 4.74; 9013 4.62;
9014 4.58; 9015 4.85; 9016 4.69; 9017 4.60; 9018 4.86; 9019 4.75; 9020 4.80; 9021 4.07; 9022 4.54; 9023 4.75; 9024 4.82; 9025 4.58; 9026 4.82; 9027 4.58; 9028 4.65; 9029 3.91; 9030 4.81; 9031 4.72; 9032 4.81.
The 96 fresh starts with `final2` (seeds 9033-9128): 77 legal, mean 3.724, legal mean 4.643; failures: 11 fell in the run, 6 somersaults, 2 fouls. Every start of `final1` on the 16, 32 and 96 is in `out/long_jump_run/round3_final1_per_start.txt`.
More fresh starts (`final1` with the 0.03 shift; the aim shift of `final2` was chosen on the first set, the others were not used in the choice): seeds 7001-7096: 3.726 m (79 legal: fell in run 12, somersault 4, foul 1) with `final1`, 3.958 (83 legal) with `final2`;
seeds 9129-9224: 4.050 (84 legal: fell 7, foul 2, somersault 3) with `final1`, **4.230 (87 legal: fell 6, somersault 3; legal median 4.70 m, 10th percentile 4.30, best 4.90)** with `final2`.
`final2` pooled over the 336 starts above: 3.97 m (`final1`: 3.86).

**What limits the jump, and what would change it.**
- *Speed at the board.* The jump reaches 6.6 m/s over the last 5 m (6.83 m/s if it did not have to straighten up). Each 1 m/s is worth 0.5-0.6 m of ballistic distance at the ceiling (the what-ifs above; round 2's fit says
  D = 0.88 v t_air + 0.52 m), so the 7.3 m/s that 5.5 m needs is 0.7 m/s away, and the 8.2-9.0 m/s of the high-school state level (6.07-6.65 m) is 1.6-2.4 m/s away. A longer run-up helps slowly: the runner adds
  about 0.05 m/s per 5 m (7.05 m/s at 50 m, 7.25 at 65 m), i.e. +0.03 m of jump per 5 m; the runway rule allows 45 m. The sprint agent's later gears (7.86 / 7.91 m/s) start at 7.0 m/s and are never used in 44 m; what would move the
  jump is a gear for the 3-7 m/s range (an acceleration gear), not a fourth gear.
- *The approach state.* The steered penultimate touchdown has a gap sd of 0.15 m; the starts with a late stride phase (COM low, trunk forward, swing foot far behind; step lengths of 1.0-1.4 m where the run has 1.5 m; five of the
  eight invalid captured approaches have their last three steering nudges pinned at the 0.25 m cap) cannot take off with any program: they are the 6-11 % of fresh starts (per 96) that fall in the run (the same starts do not fall in an unsteered
  approach, and a chunk take-off saves 1 of 12 of them). More steering authority (caps 0.30-0.40), other gains, rounding 0.9-1.0 all make it worse.
- *One program for all starts.* On the nominal start the robust program takes off with vz 2.4 m/s where its own ideal has 3.1 (harness 4.13 against 4.86 m); the short-gap fast starts get vz 1.4-1.8. The legal jumps of the 336 starts above
  are 4.07-4.90 m, median 4.66-4.70 m; the ideal for one start is 5.0-5.2 m. Per-gap programs (two tables selected by the gap) would be the next step.
- *Take-off and landing.* Contact 0.09-0.11 s. The robust take-offs leave at 18-21 deg with vz 2.1-2.4 m/s on average (harness range 1.4-2.8), the one-start jumps at 26-29 deg with vz 3.0-3.3 (a human jumper: 20-23 deg, 3.0-3.7 m/s). The landing marks 0.12-0.17 m beyond the ballistic point on the one-start jumps; the table removes most somersaults of the robust ones.
- *Body.* At the ceiling a 20 % stronger body jumps 0.4 m farther and a 40 % stronger one 0.9 m (at the same 6.6 m/s): strength and speed are worth about the same per percent, and neither reaches 6 m.

**Against humans** (men; sources as in round 1):

| level | distance | this model |
| --- | --- | --- |
| untrained man | 4.95 +- 0.55 m | one start (ORACLE, overfit): 5.209 m = 105 %; robust: the legal jumps of fresh starts have median 4.66-4.70 m (94-95 %) but 9-20 % of starts fail (14 % pooled), so the mean over 96 fresh starts is 3.7-4.2 m (75-85 %) |
| high-school state qualifying | 6.07-6.65 m from 8.9 m/s | not reached: 6.1 m needs 8.2-9.0 m/s at the board, the model has 6.6-6.9 |
| NCAA D1 finals median, world record | 7.56-7.75 m, 8.95 m | not reached |

The jump does not go beyond human ability. The best one-start jump is 0.26 m past the untrained man's mean (0.5 sd); the honest robust number is the untrained man's mean (94-95 %) when a start succeeds, and about 1 start in 7 fails. The ceiling for this
body at this speed is 5.0-5.2 m; getting past 5.5 m robustly needs about 0.7 m/s more at the board (or 20 % more strength plus 0.3 m/s), the high-school level needs the speed of a trained jumper.

**What worked:** the gear switch at 5.0 m/s (+0.22 m/s); hip-nudge steering with the plan rounded toward shortening; training the take-off program on both plant sides over a gap-stratified set of captured approaches (mirrored role tables);
the landing table on 117 hand-overs; the check-mark and aim shifts (chosen on unused seeds: 3.15 -> 3.96 m on seeds 7001-7096, of which the aim part alone +0.18 m on the unused 9129-9224); the board-relative ideal for the one-start trial. **What did not:** the natural (non-upright) run for one program (9 of 20
training starts invalid), hop-height steering, speed clamp, more steering authority or other rounding, interpolating two ideals into a linear-in-gap program, greedy swing-foot lag feedback, a chunk take-off fallback, a learned landing table on the board-relative one-start
program (5.167 against the chunk landing's 5.209), the strength what-if through `ROBOLAB_LJ_STRENGTH` (the v4 jump tasks ignore it).

**Files.** Skill `lib/robolab/skills/long_jump_run.w` (+ `lib/entry/long_jump_run.w`), harness `playground/long_jump_limits.py`. Params: runners `params/lj_runner_gear_v4_p95.txt`, `lj_runner_gear3_v4_p95.txt`, `lj_runner_gear4_v4_p95.txt`;
one start `params/long_jump_v4_gear_nom1.txt` (5.065), `_nom2.txt` (5.166), `_nom3.txt` (5.209, champion), `_nom4.txt` (5.167); robust `params/long_jump_v4_gear_a4_m1.txt` (milestone), `_a4_l60.txt`, `_a4_l2.txt`, `_final1.txt` (16 and 32 champion),
`_final2.txt` (96 champion). Pieces: take-off `out/long_jump_limits/rob_a4_final.txt`, landing `scratchpad/lj2/land_a4b_g30.txt`, approach `scratchpad/lj2/A4c.txt`; ideals `out/long_jump_limits/gp_nom_ideal.json`, `gp_nom_bd.json`, `lean_*_ideal.json`, `am_nom_*.json`.
Log with every command: `scratchpad/lj2/LOG.md`; scripts in `scratchpad/lj2/` (`runup.py`, `ikgap.py`, `harness_eval.py`, `eval_all.sh`, `assemble.py`, `capture_set.sh`, `post_robust.sh`, `rob_*.sh`, `land_*.sh`, `whatif*.sh`).

```sh
./build.sh long_jump_run && cp bin/robolab_long_jump_run bin/challengers/long_jump_run-c3
scratchpad/lj2/capture_set.sh scratchpad/lj2/A4c.txt a4 bin/challengers/long_jump_run-c3 8001 8128 4        # penultimate-touchdown states of 128 starts
scratchpad/lj2/rob_a4.sh                                                                                       # robust take-off program over 32 of them (both plant sides)
VARIANTS=1 RECSEED=8039 scratchpad/lj2/post_robust.sh a4 && scratchpad/lj2/land_a4.sh                            # hand-overs, chunk landing record, landing table
.venv/bin/python scratchpad/lj2/assemble.py params/x.txt scratchpad/lj2/A4c.txt out/long_jump_limits/rob_a4_final.txt scratchpad/lj2/land_a4b_g30.txt j_board_shift=1.04 ik_gap0=1.876777
.venv/bin/python playground/arena.py eval long_jump_v4_p95_robust96 --params params/long_jump_v4_gear_final2.txt --controller bin/challengers/long_jump_run-c3 --task long_jump_v4_p95b --workers 4
```
