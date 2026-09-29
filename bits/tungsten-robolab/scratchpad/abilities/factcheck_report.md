# Fact-check: scratchpad/abilities/build_progress_v1.py

Checked 29 Sep 2026, 01:25 to 02:10 EDT. Only this file was written.

Sources used: README.md, SOTA.md, playground/SEARCH.md, playground/arena/{champions.json, history.jsonl,
trials.json, README.md}, playground/calibrations/v4.json, playground/profiles/*.json, the agents' logs
(scratchpad/sprint_knot/LOG.md, scratchpad/soccer4/LOG.md, out/long_jump_run/LOG.md), out/*_metrics.json and the
render log, the Codex chat (~/.tungsten/chats/robolab.txt) and Codex worktree docs, git branch state, and four
primary papers (Europe PMC / NCBI E-utilities).

Conventions: `Lnnn` = line in build_progress_v1.py. README/SEARCH/SOTA line numbers are those of the working tree
at check time (README.md gained 4 layout lines at 126-129 at 01:37; cited numbers include them). History entries
are cited by their `time` field (local, EDT). Verdicts: OK, WRONG, IMPRECISE, UNSOURCED.

`site/progress/build_progress.py` (mtime 01:51) is a newer copy of the generator that already fixes many of these
items. Section 16 lists what it fixed and what is still present there.

## 0. Scoreboard

Hand-written claims are counted as distinct factual statements (a table row counts once). OK means it matches a
repo source; external literature was checked only where section 17 says so.

| area | checked | OK | flagged |
|---|---|---|---|
| natural running | 16 | 11 | 5 |
| sprint, bodies, ceilings | 21 | 12 | 9 |
| sprint from blocks, touch-only | 12 | 8 | 4 |
| long jump, standing jump | 19 | 15 | 4 |
| hurdles | 6 | 5 | 1 |
| bat | 18 | 12 | 6 |
| dribble | 15 | 8 | 7 |
| table tennis | 16 | 10 | 6 |
| balance, soccer | 20 | 11 | 9 |
| MyoChallenge cards (relocate, chase, walk, baoding, die, bimanual) | 17 | 12 | 5 |
| Codex section | 9 | 7 | 2 |
| working, waiting, requests, page meta | 10 | 7 | 3 |
| pmndrs | 9 | 9 | 0 |
| **hand-written total** | **188** | **127** | **61** |
| `V()`/`F()` values (28 champion keys, all checked) | 28 | 26 | 2 (both blocks) |

## 1. Top items to fix before publishing v1

1. L357/L505: blocks time prints as 83333339.49 s (fall sentinel in the mean). Correct 6.72 s. WRONG.
2. L389/L419/L497/L636: "first v4 runner 4.64, not entered". It was entered at 01:16 at 4.65 m/s. WRONG.
3. L406/L588: "2023 winner scored 32%". It was the 2025 winner. WRONG.
4. L495/L420/L614-617: v3 ceilings "under 6 / 8.5 / 8.3" are the superseded round-2 numbers. WRONG.
5. L367/L599: chase "0.564 (winner 0.666)" compares our phase 1 with the winner's phase-2 score. WRONG.
6. L488: mocap "before" is 11.0 deg, not 11.2. WRONG.
7. L589: "abdominal passive pull alone is 207 N.m". 207 is all muscles; rectus abdominis is 138. WRONG.
8. L361/L383/L546-547: the bat numbers are on the "athlete" body (strength x1.5, pivot root); "50-65% of MLB rates",
   "1,070 deg/s" and "50-80 ms" are each off. IMPRECISE.
9. L395/L526/L637: "about 4 of 32 roll over". Source says 3 roll-overs plus 2 fouls, on a program not in the arena. IMPRECISE.
10. L701: "Only the first row was run here so far". Rows 1, 2 and 4 were run. WRONG.
11. L601: walk "0.46 m at 1.2-1.4 m/s". The 0.46 m gait walks about 1.45-1.5 m/s. WRONG.
12. L426: "(Bolt 12.26)". The cited paper gives 12.34. WRONG.
13. L616: old elite profile has hip extensors x1.6, not x1.5. WRONG.
14. L645: "1,631 files, 13 MB" was true for the first snapshot commit only. Branch is now 1,708 files, 40 MB raw, 17 MB
    compressed. IMPRECISE (stale).

## 2. Page-level and board

- **L24 "29 Sep 2026, 1 am" and the "Restarted 1 am" rows. IMPRECISE (stale).** At 01:53 the sprint agent had
  entered the v4 runner (01:16), the soccer agent had created `soccer_single_leg_310_40` (01:16, seeding still running,
  pid 64333) and the long-jump agent had diagnosed the roll-overs (01:30). Re-stamp the page.
- **L686 "81 trials, each on fixed held-out starts, and a challenger takes over only when it wins a paired test".
  IMPRECISE.** playground/arena/README.md:21-22: deterministic trials (fewer than 5 seeds) "promote on any strict
  gain". The one-start trials (long_jump_p95, long_jump_elite, long_jump_elite2, long_jump_v2, bat, hurdle) are
  such trials, and the one-start 4.895 m start is the nominal start its take-off was designed from (history
  2026-09-28 06:43:28: "ideal from this runner's own approach state"). trials.json now defines 82 trials; 81 have a
  champion. Suggested: "82 trials (81 with a champion) on fixed starts. Stochastic trials are decided by a paired
  sign-flip test (p < 0.05); one-start trials promote on any strict gain."
- **L686 "Every score comes from the ... arena". IMPRECISE.** Supporting numbers come from other runs: dribble
  92/42/54% (no persisted source), "14 to 4 falls" (SEARCH.md validation seeds), soccer "0 of 30" and
  "67% within 3 cm" (agent validation sets), TT tracking error 0.80 to 0.21 rad (README round 9 screens).
- Board tiles: 11 of 16 OK. Flagged and detailed below: L355 natural running, L357 blocks, L361 bat (body not
  stated), L362 dribble, L367 chase.

## 3. Natural running (16 checked, 11 OK, 5 flagged)

- **L355/L485/L654 "7.3 deg from human running" with a Champion chip. IMPRECISE.** 7.29 is the mean of the 11 starts
  that stay up; 1 of the 12 arena starts falls (start 411), for both the old (9.13) and the new runner. The champion
  score 83333340.02 is 1 sentinel plus 11 x 7.29 (history 2026-09-27 21:37:48; SEARCH.md:1041 "1/12 (the same
  start, 411), 7.29, all 11 landed starts better"). On the 48 fresh starts the new runner falls 13 times against 17
  for the old one (7.22 deg on the 35 that stay up, p 0.1665, not promoted; history 22:32:17 `run_natural_48`
  lose), so `run_natural_48` is still held by the round-1 runner. Body is the v2 body (trials.json). Suggested:
  "7.3 deg from human running on the 12-start trial (v2 body): 11 of 12 starts stay up. On 48 fresh starts it falls
  on 13 (the old runner 17), 7.2 deg on the rest; not significant."
- **L485 "the sprint gait is 25 deg". UNSOURCED.** No file gives 25 deg for the sprint gait against the literature
  curves. Nearest: `sprint_bolt_form` champion 26.7 deg (README:830), which is error against Bolt's max-velocity
  keyframes, and `run_natural_fast` 15.7 deg (README:925). Drop it or cite it.
- **L488 "17 falls, 11.2 deg" (mocap, before). WRONG.** History 2026-09-27 22:33:11 (seeded `run_natural_mocap_48`):
  mean 354166673.78 = 17 sentinels plus 31 survivors at 11.01 deg. Correct: "17 falls, 11.0 deg". The "after"
  (11 falls, 10.09 deg, p 0.0498) is right.
- **L485/L489/L663 "dropping the 30% keyframe cut falls from 9 to 1 in 48 starts". IMPRECISE.** The 9-fall "before"
  is the P7 knot-residual runner (17.56 deg). The 1-fall "after" is a different runner (rn2 keyframe-chunk runner
  s3c without the heel-rise keyframe, 19.78 deg). On the same runner: s3c 6 falls with the keyframe, 1 without;
  the knot residual 9 falls with it, 14 without (SEARCH.md:1147-1153, 1168-1173; history 2026-09-28 01:00:28 lose,
  01:02:11 promoted). Suggested: "Against your set 3, the keyframe-chunk runner falls on 1 of 48 fresh starts
  without the 30% keyframe (6 with it), with the pose 2.2 deg further from your set."
- **L490 "cut falls from 14 to 4 in 48 held-out starts". IMPRECISE.** 14 to 4 is the best of seven probe checkpoints
  on validation seeds 7101-7148; the final checkpoint fell 7/48 (SEARCH.md:1011, 1031-1035). On the 48 fresh arena
  starts the same runner falls 11 against 17 (history 22:34:10). Suggested: "14 to 4 (best checkpoint; 7 for the
  last) of 48 validation starts".

## 4. Sprint, bodies, ceilings (21 checked, 12 OK, 9 flagged)

- **L389/L419/L497/L636 "first average-body runner at 4.64 m/s", "not yet entered", "No v4 sprinter is entered yet",
  "Enter it"; L491 chip "v4 body pending". WRONG (stale).** champions.json `sprint_top_speed_v4`, promoted
  2026-09-29 01:16:07, p 0.0005 against the seeded failing baseline. Mean over the 11 passing starts is 4.6485 =
  4.65 (seed 226 falls; summary.mean is -83333329.07). Frozen: bin/champions/sprint_top_speed_v4-20260929-011607.
  scratchpad/sprint_knot/LOG.md 01:16. 4.65/8.2 = 57% of its ceiling. `_v4_p95` and `_v4_elite2` still hold failing
  baselines. Suggested: "The first v4 runner (average body) is in the arena at 4.65 m/s on 11 of 12 starts, 57% of
  its 8.2 ceiling; the 95th-percentile and elite v4 bodies have none yet."
- **L495, L420 tip, L614-L617 "torso free ceiling 8.5 m/s on the old body", "average body cannot pass about 6 m/s",
  "under 6 m/s on v3", "8.5 m/s on v3", "8.3 on v3". WRONG (superseded).** README:1017-1028 ("Correction
  (round 3)") says the round-2 values ("below ~6", 8.45-8.53, ~8.3) came from single chains from poor solutions.
  Current values: pitch-free chains README:1010-1015 average 7.0 (fit 7.22-7.35), P95 8.5-9.0 (fit 9.05-9.42),
  elite2 8.5 (fit 8.33-9.26). The same-probe comparison with v4's 8.2/10.45/9.28 is README:1194-1196 and v4.json
  "validation": v3 = 6.89 / 9.69 / 8.5. Suggested Bodies column: "6.89 on v3", "9.69 on v3", "8.5 on v3, 9.28 on v4".
  The calibration story still holds: 6.89 is below untrained men's 7.8.
- **L494 "opposing muscles switched off (reciprocal inhibition)". IMPRECISE.** README:949-956: RI scales an
  antagonist by 1 - k x drive of its agonist; the champion uses k = 0.5, so it halves them at full drive.
  **"without it the gait falls within 5 seconds". IMPRECISE:** README:963 "falls in 4.4-5.6 s". The "+0.12 m/s on
  every start" is right (README:962, 12/12).
- **L391/L500 "10 m/s needs 96% of the v4 ceiling". IMPRECISE.** True only for the 95th-percentile body
  (10/10.45 = 95.7%). The average (8.2) and elite2 (9.28) ceilings are below 10.
- **L424 "Untrained men 7.8 ... (Lazarczuk 2025; Clark et al. 2020)". IMPRECISE.** Lazarczuk et al. 2025 (Scand J Med
  Sci Sports) is 15 recreationally active people, 4 of them women, radar, 7.77 +- 0.86 m/s (checked in PMC12552802).
  Clark, Meng & Stearne 2020 (8.23) is the slower half of 20 active males (v4.json:55). Suggested label:
  "Recreationally active adults".
- **L426 "(Bolt 12.26)". WRONG.** README:1132 and v4.json:104 cite "Krzysztof & Mero 2013 (PMC3661886)", which is
  Mackala & Mero 2013 (bolt_keyframes.json `corrections_to_brief`). That paper gives 12.34 m/s (60-80 m; abstract
  "12.05-12.34 m/s" in 10 m sections); a text search of its full text finds neither 12.26 nor 11.80. The project's own
  bolt_keyframes.json (published.berlin_2009_100m) lists 12.32-12.42. Suggested: "(Bolt 12.34, Mackala & Mero 2013)".
  The "2009 finalists 11.80" figure could not be verified from that paper.
- **L616 Bodies, "Elite, old profile: Hip extensors x1.5". WRONG.** playground/profiles/elite.json and
  README:402-406: hip extensors x1.6 (hamstrings x1.55). x1.5 is the literature-checked value that elite2 uses.
- **L700 "Every result names its body". IMPRECISE.** The bat (athlete body), dribble (pivot body) and standing jump
  (planar body) results do not name theirs; see sections 8 and 9.
- Chart L418-L426 (technically true): each v3 bar carries a v4 ceiling, disclosed in L428. Against v3 ceilings the
  ratios are 5.05/6.89 = 73%, 7.02/9.69 = 72%, 6.56/8.5 = 77%, not 5.05/8.2 = 62%.

## 5. Sprint from blocks, touch-only (12 checked, 8 OK, 4 flagged)

- **L357, L505 "30 m in 83333339.49 s", "100 m in 83333350.83 s". WRONG.** `V()` reads summary.mean; one of 12 seeds
  falls (score 1e9). champions.json sprint_blocks_30 scores contain one 1000000000.0, as does sprint_blocks_100.
  Correct: 6.72 s and 19.08 s (means of the 11 finishers: 6.717, 19.084); README:828-829 "6.72 ... 11/12", "19.08".
  These are the only two of the 28 V()/F() keys affected.
- **L504 "Fifteen keyframes of Bolt's mechanics ... measured from footage". IMPRECISE.** bolt_keyframes.json has 15
  events, but `set` is the 2018 World Indoor finalists' literature set (footage set pose "unreliable", README:757-758),
  and s3_td, s3_to, drive_td, drive_to are "NOT MEASURED" (interpolated). 10 are measured (rear_exit, block_exit,
  s1, s2, four max-velocity events). Suggested (as the site version does): "Keyframes measured from side-view
  footage of Bolt at block exit, the first steps and the max-velocity cycle; the set is the 2018 World Indoor
  finalists' mean and steps 3-10 are interpolated."
- **L357 chip Champion with "30 m in 6.72 s" (technically true, misleading).** That is 1.8x Bolt's 3.78 s at 30 m and
  the 100 m is 19.08 against 9.58 (README:845-847: "~5 s slower than [recreational sprinters] and ~2x Bolt's time"),
  on 11 of 12 starts, on the 95th-percentile body only. The board tile has no Bolt reference.
- **L666 "Bolt's mechanics from blocks: Done: 30 m in 6.72 s". IMPRECISE.** Same issue; "Done" is generous.

## 6. Long jump, standing jump (19 checked, 15 OK, 4 flagged)

- **L395, L526, L637 "About 4 of 32 approaches still roll over on landing" / "plateaued with about 4 of 32
  roll-overs". IMPRECISE/UNSOURCED.** out/long_jump_run/LOG.md 01:20: of 32 captured hand-overs of the not-yet-entered
  "pn" program, 27 land 4.66-4.96 m, **3 roll over and 2 are take-off fouls** (not landings). The landing search
  log (mean 3.565, min -4.538) matches 3 x -4.5, 2 x -1.0. The arena champions have no such failures:
  `long_jump_p95_robust` scores 3.16-4.33 m on all 16 starts with `failed` 0. At 01:30 the same log diagnoses
  the roll-overs as a timing problem of a fixed-time landing program; a ballistic-time clock scan gives 0 roll-overs on
  the 30 legal hand-overs (marks 4.6-4.98 m). "Diagnose the roll-overs" is therefore already done. Suggested:
  "In the landing search, 3 of 30 captured take-offs roll over (a timing problem, diagnosed 01:30)."
- **L436/L520/L523 the 95th-percentile row: 16-start bar 3.92 with ceiling 4.93 and "this runner's own approach
  (7.0 m/s)". IMPRECISE.** The 16-start champion (3.9243, promoted 2026-09-28 05:23:17) uses the 6.94 m/s runner, whose
  own ideal take-off ceiling is 4.61 m (04:29:04 note). The 4.93 m ceiling and 7.02 m/s runner belong to the
  one-start champion (4.895, 06:43:28). Five 7.02 m/s challengers lost the 16-start trial (06:43:27, 07:47:50,
  08:23:58, 08:58:47, 13:56:57; p 0.07-0.59). Same pattern for "Elite, old profile": one-start 4.075 is the
  ideal-control controller, the 16-start 3.66 is the older robust practice (the ideal-control challenger lost 2.63,
  05:52:22). L516 "The run-up is the sprint champion itself" is true only for the one-start champion. Suggested: show the
  4.61 ceiling for the 16-start bar, or label the two bars as different runners.
- **L395/L526 "passing 4.95 needs a faster runner" / "the only way". IMPRECISE.** 4.93 is a ballistic ideal take-off
  ceiling from one approach state, not a bound on the official mark; the 01:30 landing scan already shows marks up to
  4.98 m on individual hand-overs (mean of the 30 legal 4.79).
- **L443 "run-up 8.9 m/s" for the high-school row. IMPRECISE.** README:533: the 8.89 +- 0.58 m/s run-up is Bayraktar &
  Cilli 2018 (jumpers aged 14-28, 6.30 +- 0.71 m), not the Oregon qualifiers.
- Not said: the champion's rendered jump ends in a flip. out/long_jump_v5_p95_metrics.json: flipped true, rebound true,
  clean_landing false, recovered false, final pelvis z 0.13 m; the mark is the left foot (legal under TR 29.9). The
  older v4 videos show the same.
- Not said: standing jump has no human reference on the page (SOTA.md:97: Ashby & Delp 2006, 2.00 m arms free, 1.60 m
  restricted; Ong 2016, 2.27 m; robot record 4.83 m, SOTA.md:229).
- Not said: "1.315 m with 32 of 32 landing" is at the arena's 3 s horizon. Codex's fresh 64 starts: our P6 is 64/64
  legal at 3 s and 0/64 at 8 s (chat 06:05Z and 07:27Z); Codex's R7 1.3397 m "beats the three-second robustness
  frontier, not the longer-recovery champion" (57/64 legal at 8 s; chat 07:52Z).
- Date nit (Codex row 1, L625): "run 28 Sep"; arena history says 2026-09-27 23:16:05 local. Site version already says 27 Sep.

## 7. Hurdles (6 checked, 5 OK, 1 flagged)

- **L658 request "Hurdles at high-school height" answered with "0.762 m: 4 of 8 clear hurdle 1". IMPRECISE.** README:645
  and L535: the high-school boys' height is 0.991 m (39 in). 0.762 m (30 in) is the curriculum's lowest step
  (README:658). At 0.991 m nothing clears: "the lead leg clears and the trail leg catches" (README:725) and
  `hurdle_hs` holds only the failing baseline (0 cleared). Suggested: "At 0.991 m: falls at the first hurdle. At 0.762 m:
  clears hurdle 1 on 4 of 8 starts."

## 8. Bat (18 checked, 12 OK, 6 flagged)

- **L361/L380/L453-L461 body not stated. IMPRECISE (high).** All bat trials run `BAT_BODY=athlete` (trials.json env;
  README:2700): base HumanoidBuilder with strength x1.5 and every muscle's vmax raised to 3.0 L0/s, on a pivot root
  with a muscle-driven yaw hinge and slide, "no whole-body balance" (playground/tasks/bat.py:25-36, 112-115). The
  human-calibrated V2 body at strength 1.0 has champion `bat_power_human` = 10.27 m/s. The MLB comparison (32 m/s)
  is made with the athlete body. Name it on the board, chart and card.
- **L383, L547 "Trunk and arms turn at 50-65% of MLB rates". IMPRECISE.** README:2791-2796 gives pelvis 425-427 vs 714
  deg/s (60%), upper torso 479-533 vs 937 (51-57%), but top-arm elbow extension 591-604 vs 1539 (Dowling & Fleisig 2016)
  = 38-39%. The README's own sentence "trunk and arms stay at 50-65%" does not hold for the arms. Suggested: "Trunk
  turns at 51-60% of MLB rates, elbow extension at 38-39%."
- **L546 "The wrist runs at 1,070 deg/s, the same as college hitters (1,093)". IMPRECISE.** 1,069 is the open-loop
  program's wrist; the reflex-on knots swing (the 21 m/s one) reaches 930 (README:2794). Flynn et al. 2021: 1093 +- 354
  deg/s is the nondominant (lower) hand, full swing, all fingers on (checked in PMC8671670 Table 3).
- **L547 "The reflex-on swing pauses 50-80 ms before the swing (the earlier one paused 19 ms)". IMPRECISE.** README:2756
  says "cut the pre-swing stall from 115 to 50 ms" (knots bullet). The arena `bat_flow` report `flow_stall_ms_pre`
  (mean over 18 pitches): v5 19.2, Codex 48.3, v6 knots 30.3, knots b 28.3, open-loop program 55.3 ms; one rendered
  pitch shows 55 (render_latest.log). Nothing gives 80. The 19 ms is right.
- **L458 "Optimised on 6 of the 18 grid pitch locations" and L547 "so it is not tuned to the 18 test pitches".
  IMPRECISE.** README:2779: "The programs saw 6 of the 18 grid pitches (the 6 locations at 76 mph)"; the other 12
  share those locations at 83 and 91 mph. So 6 of the 18 test pitches were training pitches; the 24 fresh pitches are
  held out (trials.json bat_power_fresh).
- **L655 request "Batter hitch: Fixed". IMPRECISE.** True for the 13.9 m/s v5 swing (bat_flow 2.05 champion). The 21 m/s
  knots swing has a pre-swing pause again (bat_flow 2.77 on the 18 grid pitches against 2.05; the guard-clean fresh
  trial "fails (2/24)", README:2766; shortening the pause is the remaining work, as the L553 "Next" says). The cause
  "wrist and pelvis hitting joint limits" matches the v5 `limit_brake` fix for the post-contact stall.
- Also L361/L383: "21 m/s" is 21.57 (rounds to 22) and "was 13.8" is 13.86; use 21.6 and 13.9.
- Technically true: the 21.57 knots swing lost the arena (history 2026-09-28 01:23:39, p 1.0) to the ORACLE
  open-loop program, which holds `bat_power` and `bat_power_fresh`. The page labels the oracle "ceiling study"
  correctly, but the reflex-on bar is not a champion of any trial.

## 9. Dribble (15 checked, 8 OK, 7 flagged)

- **L362, L384, L559 "3 through-the-legs passes in a row", "3 legal passes in a row on an unseen start", "The longest
  streak is 3". IMPRECISE.** The rendered video does show 3/3 in a row (frame HUD: "through the legs 3/3, in a row 3
  (best 3)" at t = 3.60 s). But on the arena's 25 fresh starts `dribble_btl_streak_25` scores are [0,2,1,2,0,1,1,1,1,1,
  2,0,1,1,0,2,2,2,2,1,2,2,1,2,2]: maximum 2, mean 1.28, and no start reaches 3 good passes in 15 s on
  `dribble_btl_25` (all scores 0.0-0.2). The 3 appears to come from seeds scanned outside the arena
  (scratchpad/btl/streakseed.py prints the top seeds by streak; the arena note says "first streaks of 3"). Suggested
  (as the site version does): "a streak of 3 on 1-2 of 32 fresh starts; mean longest streak 1.28".
- **L384, L559 "First pass 92%, return 42%, 54% of passes overall" of "24 fresh starts". UNSOURCED.** No persisted file
  produces them (no 24-start trial exists; arena starts are 10 and 25). Nearest arena data: `dribble_btl_streak_25`
  gives at least one good pass on 21/25 (84%) and two in a row on 11/25 (44%). The site version restates them as
  "22 (92%), 10 (42%), 33 of 61 passes (54%) on 24 fresh 8 s runs"; that arithmetic is consistent but needs its output
  saved.
- **L562 "(good passes per attempt) 0.104". IMPRECISE.** btl_rate = good BTLs / max(attempts + uncharged loss, 10)
  over 15 s (trials.json `dribble_btl`); with about 2 attempts per run the floor of 10 dominates. Per attempt it is
  1.04/2.16 = 48%; per run it is about 1.0 good pass in 15 s. Say "good passes per max(attempts, 10)".
- **L387 "arms lag the plan by 5-10 cm". UNSOURCED.** No file gives it.
- **L656 "Fingers built, no measurable effect". UNSOURCED/IMPRECISE.** Codex's finger diagnostic (chat 15:33Z): nonzero
  probes change MCP/PIP measured motion; it is "an untrained integration result, not a technique improvement". The v3
  fingered crossover lost 4.28 vs 3.72 (p 0.145; history 2026-09-27 11:02:36). "No evidence of a gain" is the accurate wording.
- Body not stated: the through-the-legs demo runs on the v3 body ("pivot muscle humanoid" in the video HUD), a stationary
  dribble on a pivot root (playground/tasks/dribble.py docstring); the Codex crossovers run on the v1 body with rigid
  paddle hands. Neither is named.
- The other eight dribble claims check out (including "0 of 35", the 7.52 against 3.72 table row and the "replay 3x
  slower" caption, which I confirmed on video frames).

## 10. Table tennis (16 checked, 10 OK, 6 flagged)

- **L399, L571 "The paddle face follows only about 40% of an aimed change". IMPRECISE.** README:2289-2290 (round 7): the
  forehand's pitch follows 0.37-0.42 (yaw 0.8-1.0). Round-8 probe (README:2392, 2455-2456): forehand yaw 0.66 / pitch
  0.53, backhand 0.13 / 0.28. The mean of those four is 0.40. Suggested (as the site version does): "53-66% on the forehand,
  13-28% on the backhand".
- **L398/L473 "Best after the challenge 80.3, Post-challenge result on the same task". IMPRECISE.** SOTA.md:55: Diff-Muscle
  (Zhao et al., arXiv 2603.08617, Mar 2026), a **preprint**, "success 80.3%" with up to 14 dual-agent rally exchanges and
  the same 2 pelvis actuators. Say "preprint" and cite.
- **L574 "90% is far above anything reached on this task". IMPRECISE.** The page's own chart lists 80.3%; 90% is 10 points
  above it, and 26 above the challenge winner (64%).
- **L572 "best chop is the backhand at a -4 deg face on a 40 deg downward path". IMPRECISE.** README:2211: commanded
  "60 / 40" (60 deg open face, 40 deg down); reached face -4, reached path -33. Site version words it correctly.
- **L659 "the chop and flick now work at real speed". IMPRECISE.** README:2239: the flick's pad reaches only 1.3-1.5 m/s
  (max 1.9), "little muscle behind it"; chop pad speed 2.6-2.7 m/s. "None reliably lands" is right (flick 0 of 20).
- **L567 caption "Five consecutive returns by the phase-2 champion". Technically true, misleading.** README:2082-2086:
  five consecutive arena serves (seeds 98045-98049), each solved. The champion solves 33%, so this is a chosen streak
  of independent serves, not a rally. Say "five solved serves in a row".
- The other ten table-tennis claims check out (rates, tips, the 1.20 to 0.44 rad and 0.80 to 0.21 rad numbers, the
  contact-centring figures, the chop geometry); the 64% winner is in the reference audit below.

## 11. Balance and soccer (20 checked, 11 OK, 9 flagged)

- **L406, L588 "2023 winner 32%". WRONG.** README:1264 "the 2025 winner's 32%"; SOTA.md:52: Servette MyoClub, 2025
  (NeurIPS 2025 "Towards Human Athletic Intelligence"). 2023 was Relocate and Chase Tag (SOTA.md:50). The old 26 Sep
  progress artifact says "(2025)".
- **L589 "the abdominal muscle's passive pull alone is 207 N.m". WRONG.** Re-running scratchpad/soccer4/trunkcap.py
  (upright lumbar, flex_extension 0.0): passive torque of all muscles = 207.0 N.m, of which rectus abdominis = 138.0
  N.m; extensor capacity at full activation = 196.0 N.m. The "84-123%" (README:1558-1560) is passive pull plus the upper
  body's weight over extensor capacity and is right. Suggested: "the abdominal muscle's passive pull plus the upper
  body's weight need 84-123% of the back extensors' capacity" (the site version's wording).
- **L581 "The 3 s trial went from 1.96 to 3.08 s". IMPRECISE.** `soccer_single_leg` gives each leg up to 3 s, 6 s in all,
  on 40 starts (trials.json; README:1452 "s per leg, max 6"). 3.08 is out of 6 (right leg 0.18 to 0.63 s, README:1532,
  so the left leg is about 2.45 s). 1.96 was the round-3 champion. Suggested: "the short trial (up to 3 s on each leg, 6 s in all)".
- **L582 "the standing foot does not spin". IMPRECISE.** README:1410-1417: within 0.02 rad in the hold; but in the failing
  lifts "the stance foot spins 0.3-0.4 rad" (README:1522-1525).
- **L582 "the gluteal moment arm ranges from -29 to +37 N.m per unit activation". IMPRECISE.** README:1421: it is glmed1's
  rotation torque per activation (glmax1/2: -58 to +23), a torque, not a moment arm.
- **L403, L582 "Every failure happens at the lift" / "All remaining failures are at the lift". IMPRECISE (superseded).** README:1522
  says it for the 20-start trial. scratchpad/soccer4/LOG.md 01:22-01:27, new 40 seeds: 5 fail within 20 s; 89117 in
  the lift (2.6 s), 89130 in the set/shift (1.5 s), and 89110, 89115, 89133 in the hold after the lift (6.7, 6.9,
  3.2 s); 89110 and 89115 are diagnosed as a yaw limit cycle then frontal-plane runaway. HANDOFF (section 2) already
  says "at or just after the lift".
- **L584, L638 Next: "A 40-start version of the 310 s trial". IMPRECISE (stale).** `soccer_single_leg_310_40` exists
  (trials.json; added 01:16, seeds 89100-89139); its seeding is still running (`arena.py seed`, pid 64333), so no champion yet.
- **L588 "Phase 2 starts up to 1 m away". IMPRECISE.** README:1535: 0.02-1.4 m from the phase-1 stance (20% within 0.5
  m, 77% within 1 m). Site version says 0.02 to 1.4 m.
- **L589 "tuned over seven stages". UNSOURCED.** README says the phase-1 kick is "a trajectory from its key-frame start"
  (README:1540) and lists rounds, not seven stages.
- The other eleven balance/soccer claims check out (12 of 20, 15 of 20 with p 0.226, the 96 s to 300 s centring
  result, the 298 s video, phase 1 and phase 2 counts, 0 of 30, 84-123%, the spine fold within 0.5 s).

## 12. MyoChallenge cards (17 checked, 12 OK, 5 flagged)

- **L367, L599 "Phase 1 0.564 (winner 0.666)". WRONG comparison.** README:1642 and 1708: GaitNet's 0.666 was "on the final
  (P2-style) evaluation"; SOTA.md:50 lists it in the "Phase-2 winner" column. Like-for-like is our phase 2: 0.16 (chase_p2,
  trial "winner 0.666"). Suggested: "Phase 1 0.564; phase 2 0.16 against the 2023 winner's 0.666".
- **L605 die: "Removes 0.39 rad ... (was 0.19) ... The winner scores 0.13". IMPRECISE (mixed metrics).** The 0.13 is the
  co-winners' solve rate (die_p2 trial "success (co-winners 0.13)"; SOTA.md:49: IARAI-JKU 0.13, pkumarl 0.12);
  robolab's solve rate is 0 of 100 (`die_p2` 0.0). 0.39 rad is `die_p2_progress`. Suggested: "no full solves (0 of 100)
  against the winners' 0.13; progress 0.39 rad, was 0.19".
- **L601 walk "0.46 m at 1.2-1.4 m/s". WRONG.** champions.json `walk_stride` note: "longer steps but ~1.45-1.5 m/s at every
  v_des"; README:1705-1706. 1.20-1.42 m/s is the round-1 0.33-0.36 m gait (README:1634). Suggested: "0.46 m steps at about
  1.45 m/s".
- **L601 "Standing pushes of 60-80 N are survived". IMPRECISE (minor).** README:1640: quiet stance survives 2-4 of 4 pushes at
  60-80 N, not 100 N; while walking, pushes of 50 N and above fell it (README:1639).
- **L607 "The prosthetic hand stalls about 6 cm below the handover point". UNSOURCED.** Nearest: "palm +-6 cm" limit cycle when
  held out (lib/robolab/skills/myo_bimanual_v4.w header); champion min_goal_dist 0.41 m; note says the prosthesis
  "mostly ... presses against the held box, not yet a grip".
- The other twelve claims check out (relocate 0.257 from 0.210 on the same trial, the invisible-receptacle finding and
  the "not comparable to 0.343" caveat, baoding, die progress 0.39 from 0.19, bimanual 0.63).

## 13. Codex section, working now, waiting, requests (19 checked, 14 OK, 5 flagged)

- **L701 "Only the first row was run here so far". WRONG.** Rows 1, 2 (7.52) and 4 (14.72) were entered and promoted here
  on 27 Sep 23:16-23:19 (history: search_jump_legal 1.363, bat_power 14.72, dribble_crossover_25 7.52); the same jump
  binary scored on the robust trial (3 of 32 fell, 23:16:11) lost, and Codex's own robust 1.2722 policy was deliberately
  not run (chat 03:30Z). Not yet run: robustness R7 1.3397 and crossovers R9 9.08. L644 already says "the same way as
  the first three". Suggested: "Rows 1, 2 (7.52) and 4 were run here; the newer R7 and R9 champions have not been."
- **L645 "1,631 files, 13 MB". IMPRECISE (stale).** True for the first snapshot commit 473edd633: 1,631 files, 13.0 MB
  compressed (34.7 MB raw). The branch now has 3 commits: 1,708 files, 40.1 MB raw, 17.1 MB compressed; largest file
  1.97 MB. Site version says "about 1,700 files, 40 MB".
- The other fourteen claims check out. Worth knowing because they are links and paths: HANDOFF_20260929.md now
  exists (created 01:35); the two compiler branches match their commits (1f3812daf, c33027cd4 incl. the
  use-after-free); yaks.app robolab v9 went live 2026-09-28T01:05Z = 27 Sep 21:05 EDT, so "last refreshed 27 Sep"
  is right in local time; the Keyframe Bench link opens (a public artifact created outside the current organization,
  i.e. the previous account; readable, not editable from here).

## 14. Bodies (folded into section 4)

Flagged there: ceilings column, elite-old x1.5, "every result names its body". The other four rows' claims (average,
95th percentile multipliers, elite2 "every part cited", the v4 changes) match README:275-278 and v4.json.

## 15. pmndrs (9 checked, 9 OK)

All numbers, the "instructions per call" unit (= the "instr x" column) and the file path match
benchmarks/pmndrs_math/RESULTS.md:15-42 and the open-issues list (RESULTS.md:86-87, the 1 KB-per-draw leak).

## 16. Status in site/progress/build_progress.py (mtime 01:51)

Fixed there: sentinel (F() now averages passing rollouts), v4 runner entered at 4.65, v3 ceilings 6.89/9.69/8.5, TT
follow ratios 53-66% / 13-28%, "3 of 30" roll-overs, 0.02-1.4 m, 207 N.m removed, elite-old x1.6, mocap 11.0, set-3 "2.2
deg further", blocks chip "About 2x Bolt's time" and rewritten keyframe sentence, bat pause "115 to 50 ms", requests rows
for bat hitch, blocks, TT strokes and dribble, "3 s on each leg, at most 6", "Champion here (run 27 Sep)", branch
size.

Still present there (line numbers in that file):
- soccer "2023 winner" (439, 621)
- Codex "Only the first row was run here so far" (759)
- chase "(winner 0.666)" (400, 632)
- die "The winner scores 0.13" (638)
- bat "50-65% of MLB rates" (416, 580), wrist "1,070" (579), body not named
- "Hurdles at high-school height" answered with 0.762 m (691)
- "(Bolt 12.26)" (459) and "Untrained men" label
- caption "Five consecutive returns" (600)
- "which is the only way to pass the untrained man's 4.95 m" (559): the LOG behind the new "3 of 30" sentence has marks
  up to 4.96 (and 4.98 in the 01:30 scan), so "needs a faster runner" is not established; the sentence's "4.6 to
  4.95 m" should read 4.66 to 4.96
- "cut the falls from 9 to 1" across different runners (516)
- 80.3% without "preprint" (431, 503); "90% is far above anything reached" (607)
- 16-start bar 3.92 next to the 4.93 ceiling; champion video ends in a flip

New site-version claims that check out: 13 vs 17 falls at 7.2 deg (48 starts), 8 and 7 of 48 held-out falls, 3.3 steps/s
of 1.7 m against 4.5 of 2.4-2.7 m, "4 to 6 s behind a recreational sprinter", reaction 0.237 s, 0.46 m at 1.44 m/s /
1.2-1.5 m/s, "1 fall, 19.78" plus "2.2 deg further", about 1,700 files / 40 MB, pause 115 to 50 ms.

The HANDOFF_20260929.md section 2 repeats "2023 winner 32%" and "about 4 of 32 approaches roll over"; the same
corrections apply there.

## 17. Reference audit (source map)

| reference on the page | source (file:line) | citation | verdict |
|---|---|---|---|
| Bolt 3.78 s at 30 m, 9.58 s | README:828-829, 845; bolt_keyframes.json published.berlin_2009_100m | Mackala & Mero 2013 Table 3b (3.78 at 30 m, checked) | OK |
| MLB about 32 m/s, 72 mph | SOTA.md:294; README:2702 | Savant / NBC 2024: 71.5 mph = 32.0 m/s, 6 in from tip | OK |
| untrained men 7.8 (7.3-8.3) | README:1129; v4.json:55 | Lazarczuk 2025 (7.77 +- 0.86, mixed group, checked); Clark, Meng & Stearne 2020 (8.23, slower half of 20 active males, not checked) | IMPRECISE label |
| trained sprinters 9.9 +- 0.46 | README:1131; v4.json:93 | Miyashiro et al. 2019 (79 sprinters, 1.75 m, 66.6 kg, 40-50 m: checked) | OK |
| elite 11.5-12.3; 2009 finalists 11.80; Bolt 12.26 | README:1132; v4.json:104 | "Krzysztof & Mero 2013" = Mackala & Mero 2013: Bolt 12.34 (60-80 m); a text search finds no 12.26 and no 11.80 | Bolt value WRONG; 11.80 unverified |
| untrained 4.95 +- 0.55 m, women 3.57 +- 0.54 | README:532 | Romdhani et al. 2026, Sports 14(5):193 (MDPI blocked; not checked) | OK per repo |
| high school 6.07-6.65 m | README:533 | OSAA 2026 standards (4-year mean of 4th place); run-up 8.89 from Bayraktar & Cilli 2018 | OK / run-up IMPRECISE |
| NCAA D1 finals medians 7.56-7.75 m | README:534 | NCAA results 2023-25, derived (D) | OK per repo |
| world record 8.95 m, run-up 11.0 m/s | README:535; SOTA.md:287 | Powell 1991; Fukashiro & Wakayama 1992 via Shimizu 2018 | OK |
| TT winner 64% | SOTA.md:52; README:1848 | MyoChallenge 2025 phase 2 (ActingAI) | OK |
| TT 80.3% after the challenge | SOTA.md:55 | Diff-Muscle, Zhao et al., arXiv 2603.08617, Mar 2026, preprint | IMPRECISE (no "preprint") |
| soccer winner 32% | SOTA.md:52; README:1264 | 2025 (Servette MyoClub), phase 2 | page says 2023: WRONG |
| chase winner 0.666 | SOTA.md:50; README:1642, 1708 | 2023 GaitNet (SNU), final / phase-2 evaluation | compared with our P1: WRONG |
| baoding winner 0.55 | SOTA.md:49 | 2022 stiff_fingers (Mathis lab), phase 2 | OK |
| die winner 0.13 | SOTA.md:49 | 2022 IARAI-JKU 0.13, pkumarl 0.12, solve rate | metric mismatch |
| relocate winner 0.343 | SOTA.md:50; README:2678 | 2023 Lattice, challenge evaluation | OK (page says not comparable) |
| college wrist 1,093 deg/s | README:2730 | Flynn et al. 2021, lower hand, full swing, 1093 +- 354 (checked, PMC8671670 Table 3) | OK; our 1,070 is the oracle |
| MLB pelvis 714, upper torso 937 | README:2702 | Welch et al. 1995 (714 hip, 937 shoulder segment; checked) | OK |

## 18. Not said on the page, but a reader would expect

- Bodies: bat = athlete body (x1.5 strength, vmax 3.0 L0/s, pivot root, no balance); dribble = stationary pivot body
  (v1 paddle hands for crossovers, v3 fingered body for through-the-legs); standing jump = planar body; TT = official env
  with 2 non-muscle pelvis actuators (the winner too, SOTA.md:52).
- New champion not in the narrative: `sprint_top_speed_v4` (see section 4). Newer candidates in the sprint log
  (P95 v4 7.049 m/s crouched bounce; average v4 5.67 at gen 9) are not in the arena yet.
- `run_natural_48` is still held by the round-1 runner; the "Champion" chip on natural running refers to the 12-start trial.
- bat_power / bat_power_fresh are ORACLE-labelled trials that the reflex-on knots cannot beat; the human-body bat champion
  is 10.27 m/s.
- The hurdle trials at 0.838, 0.914 and 0.991 m hold only failing baselines (0 cleared).
- `long_jump_p95_robust` has 0 failed starts of 16 (3.16-4.33 m); the roll-overs discussed are a different program.
- Codex's fresh-start results: our P6 robust jump is 0/64 legal at 8 s; Codex's own 8 s legality is 55-62/64
  (rounds 5-8, chat).

## 19. Technically true but likely to mislead

- Champion chip on sprint from blocks (1.8x Bolt at 30 m, 2.0x at 100 m, 11 of 12 starts, one body) and on natural
  running (1 of 12 falls; 13 of 48 on fresh starts).
- Board dribble tile "3 passes in a row" (best of a seed scan; arena mean streak 1.28, max 2 of 25).
- Bat 21 m/s against MLB 32 m/s on a x1.5-strength pivot-root body, with a non-champion bar.
- Chase tile (phase 1 against a phase-2 winner) and die line (progress in rad against a solve rate).
- Long-jump 4.895 m: the start its take-off was designed from, and the video ends in a flip; 3.92 m is a different runner.
- TT video "five consecutive returns" (chosen streak at a 33% solve rate).
- The "Scored" chip has the same green styling as "Champion" (CHIP "scored" maps to class "done") on tasks where robolab is
  far from the winner: baoding 0.115 against 0.55, chase phase 2 0.16 against 0.666.
- Chart legend "Robolab best" covers the old v5 baseline (13.86) and Codex's swing (14.79) in the bat chart.

## 20. Verification log

- Parsed champions.json for fall sentinels in every V()/F() key used (28 keys): only sprint_blocks_30/100 affected.
- Traced every "before" and "now" through history.jsonl (bat, run_natural*, long_jump*, search_jump*, soccer_single_leg*,
  dribble*, walk_stride, relocate_p2eval*, die/bimanual/baoding/chase) with survivor means recomputed from the score lists.
- Re-ran scratchpad/soccer4/trunkcap.py (read-only) for the 207 N.m claim.
- git: robolab-campaign-2026-09 file count, raw and compressed size (first commit and now); the two compiler-fix commit
  messages; yaks.app robolab versions; Artifact list and read of the Keyframe Bench and progress artifacts.
- Extracted frames of out/dribble_btl.mp4 (HUD counter, "replay 3x slower") and read out/long_jump_v5_p95_metrics.json.
- External: Europe PMC / E-utilities for Mackala & Mero 2013, Miyashiro et al. 2019, Lazarczuk et al. 2025, Flynn et al.
  2021; web search for Welch et al. 1995. Not reachable: Romdhani et al. 2026 (MDPI 403), Clark et al. 2020, OSAA/NCAA tables.
- Not reproducible from files: dribble 92/42/54%, "streak of 3 on 1-2 of 32", "5-10 cm arm lag", "6 cm below", "sprint gait 25 deg".
