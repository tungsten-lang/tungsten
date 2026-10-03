# Agent L3: a long jump past the human record on the LABELLED beyond-human body with an unlimited run-up (30 Sep 2026)

Written by the main session from L3's hand-back (the harness refused L3's own write of this file; its full log with every command is `LOG.md`, ending in a "FINAL STATE" section) and from the checks listed under "Verified by the main session". Every number is for the labelled beyond-human body (`playground/profiles/beyond.json`: strength x2.4, muscle speed x2.0, tendon stiffness x1.5, activation x0.8, on the average 1.75 m / 67.5 kg skeleton; an invented stretch, not a human profile), an unlimited run-up (check marks 150-151 m, a 14 m sand pit). NONE of it is comparable with the human-body long-jump trials, whose best is 5.209 m on one start and about 4.0 m mean on 480 fresh starts.

## Result in four lines

- M1 (the run-up) PASS: 13 of 16 perturbed starts reach the line at 9.5 m/s or more over the last 5 m (rule: 8 of 16).
- M2 (one start) PASS: official 10.848 m, legal, against the human record of 8.95 m. Oracle-class (an open-loop 32-muscle excitation program), overfit to that start by construction.
- M3 (robustness), one take-off program for every start: 96 fresh starts never used: mean 5.644 m, 69 of 96 legal (71.9%), legal median 7.89 m, best 9.28 m; 8 legal jumps (8.3% of starts) exceed 8.95 m. 16 perturbed starts (901-916): mean 5.660 m, 12 legal, best 8.59 m.
- The mean is below the record; the one-start demonstration and the 8% of fresh starts above it are what "exceed human ability" has at present.

## What was built

- `lib/robolab/skills/long_jump_run_x.w`, entry `lib/entry/long_jump_run_x.w`: `LongJumpRunXSkill < RunGearXSkill`, a copy of `long_jump_run.w` with only the class line changed. (A subclass of `LongJumpRunSkill` ran the chunk jump bit-identically but crashed the ideal take-off program with "expected int, got singleton"; it crashed even on the human champion; a hazard of subclassing a class with conditionally assigned ivars in compiled Tungsten, so the jump class is kept a leaf.) `long_jump_run.w`, `run_gear.w`, `run_gearx.w` are untouched.
- Frozen controller `bin/challengers/long_jump_run_x-l3b`. Tasks `playground/tasks/long_jump_v4_beyond.py` (check mark 150 m, pit 14 m) and `long_jump_v4_beyond_a.py` (check mark 151.025 m). The profile is set in the class because `LongJumpP95Task` hard-codes `profile = "p95"` and an explicit profile beats `ROBOLAB_PROFILE`: the environment variable alone builds the P95 body.
- Params `params/long_jump_beyond_nom1.txt`, `nom2.txt`, `nom3_yk.txt`, `rob1.txt`. Arena trials (added under the arena lock, each seeded with a baseline and promoted by a paired test): `long_jump_v4_beyond` (one start: 0 to 10.848 m), `long_jump_v4_beyond_robust` (seeds 901-916: 2.116 to 5.660 m, p 0.010), `long_jump_v4_beyond_robust96` (seeds 10001-10096: 0.547 to 5.644 m, p < 0.001).
- Tools: `ljx.py` (ideal search with a plant-force cap, yielding-knee and board terms), `ljx_robust.py` (the robust stage), the drivers and helpers in this directory. Videos (git-ignored): `out/lj3/beyond_nom2.mp4` (one start), `out/lj3/beyond_rob1_s10001.mp4` (robust, official 9.047 m).

## M1, M2, M3 in detail

- M1: chain C (`params/run_gearx_v4_beyond_c.txt`), 150 m, approach only, seeds 601-616: 13 of 16 pass; starts 604 and 606 fell (14.1 s, 12.7 s); 614 reached 9.449; v5 over the 14 that reached the line: mean 9.907, sd 0.177, max 10.104. Chain D: 14 of 16. Chain C at 175 m: 12 of 16. Without steering the last touchdown is 1.44 +- 0.46 m short of the line (the stride phase is spread over one 2.26 m step). Chain C falls on the nominal start at 19.9 s, so the one-start design uses chain D.
- M2, the headline: take-off vx 9.04 m/s, vz 5.17 m/s (29.8 deg), contact 0.072 s, flight 1.20 s, foot 0.29 m behind the line, speed over the last 5 m 10.11 m/s; the mark is the pelvis (the jumper falls back after landing). The full rollout reproduces the harness's ideal to the digit. Pipeline: board scan, capture at the penultimate touchdown, sep-CMA ideal, distil, landing table.

| variant, same start | official |
| --- | --- |
| plant-force cap 8 BW (12 ms average; achieved 10.1) | 9.981 |
| cap 12 BW | 10.338 |
| cap 20 BW (the rule fixed before the runs: 2.4 x an 8 BW human plant peak) | 10.734 (10.848 with a landing table) |
| no cap (29 BW over 12 ms) | 11.346 |
| yielding knee, 12 deg at peak force | 11.386 |
| yielding knee, 20 deg at peak force, 12 ms force 14 BW | 10.807 (with its landing table) |

- Caveat on the first take-off, now answered: it was a locked-knee strut held by the joint limit (plant force 28 BW instantaneous). A yielding-knee ideal does as well (10.6 against 10.5 m from the line, 14 BW over 12 ms), so the strut is not required; the force cap is not what limits the jump either (the 8 BW design gives 9.98 m).
- What-ifs on the same state (ideal re-optimised): strength x1.3 (about P95) 8.4 m, x1.8 9.2 m, x2.4 10.5 m (about 0.5 m per 0.1 of the strength factor); approach speed about 1.1 m per m/s, a 7.5 m/s approach (what a 44 m run-up gives this runner) about 7.95 m, so the 150 m run-up is worth about 2.8 m. The jump is speed-limited: at P95-level strength the same 10 m/s approach still gives 8.4 m.
- M3: the robust program is chain D with the steering planner (a hip nudge), one take-off program for both plant sides with gap knots trained on 52 captured states, and a landing table on 101 hand-overs; also oracle-class. 96 fresh starts: failures are 17 run falls or steering stumbles (10009, 10016, 10025, 10038, 10042, 10044, 10047, 10051, 10060-10063, 10070, 10078, 10080, 10088, 10095), 1 collapsed take-off (10064), 7 fouls (6 of them 0.05-0.13 m over the line) and 2 somersaults. Selection set 7001-7096: mean 5.46 m, 69.8% legal. The one-start program on the same starts: 2.116 m (901-916; 4 of 16 legal, two of them above 8.95 m) and 0.547 m (fresh 96).

## What limits the robust jump

- One fixed program against per-state programs: the per-state ideals reach 9.8-10.1 m on 5 of 6 probed starts but are idiosyncratic (the cross-application matrix scores -25 to +6 off the diagonal); one program gives a legal median of about 7.9 m. The plant knee angle at touchdown decides the outcome (correlation -0.83 with the distance).
- The runner: 10.9% of starts fall before the line without steering (chain D, 128 seeds), steering adds about 8% stumbles; steering variants gave no gain. Foot placement sd 0.14 m gives about 7% fouls; a check-mark shift and a program-only gap shift both made it worse because the landing table is tied to the take-off states.
- Landing: the backward rotation ends with the jumper sitting down. A robust program from the yielding-knee base stalled (mean 3.45 over the 52 training states at 572k of 1.2M simulations, against 6.2 for the locked-knee base at 600k).

## Next (L3's list)

A take-off with feedback on the plant-leg geometry (knee and foot placement at touchdown) to close the gap from about 7.9 m to about 10 m; a fall-free runner and steering without stumbles (worth about +0.6 m of mean each); feet-first landing and recovery; a robust program from the yielding-knee base; per-start check marks.

## Verified by the main session (30 Sep, after the hand-back)

- `arena.py recheck long_jump_v4_beyond long_jump_v4_beyond_robust long_jump_v4_beyond_robust96`: stored and recomputed means identical per seed (10.8480; 5.6600; 5.6438), all "OK".
- The human-body champion's frozen params through BOTH its stock frozen controller and the new `long_jump_run_x-l3b` give 5.209 m = the recorded score (`identity_human.py`): the new skill changes nothing for the human-body jump.
- `git diff` of `long_jump_run.w`, `run_gear.w`, `run_gearx.w` is empty.
- RETRACTION of my earlier probe `probe_beyond_unretuned.txt` (the champion "falls on the beyond-human body"): it did not test that body (see the note at the top of that file). The valid statement is the arena seed row of `long_jump_v4_beyond`: the human-body champion replayed on the labelled beyond-human body scores 0 m.
