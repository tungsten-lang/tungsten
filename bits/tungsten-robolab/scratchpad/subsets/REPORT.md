# Where subset keyframes would model the intent better: the six audits in one page (30 Sep 2026)

Erik (27 Sep, after the runner's toe-off example): "seems like we should be able to define a keyframe based on a subset of muscles/joints ... in the other trials, i'm sure there are subset keyframes that would better model what is needed or intended."

Six read-only audits (nothing was simulated, built or edited; every value/cost/risk below is the auditor's 1-5 judgement, and every A/B is a proposal, none was run): `audit_runner_sdk.md` (the runner, the sprinter, the SDK), `audit_bat.md`, `audit_dribble.md`, `audit_longjump_hurdles.md`, `audit_soccer_balance.md`, `audit_table_tennis.md`. Briefing: `BRIEF.md`.

## The short answer

- **Right for the runner, the balance hold, the bat's pre-swing chain, the dribble's end-of-stroke posture and the hurdle trail leg.** The runner's toe-off keyframe commands all 13 joints; the toe is commanded at -30 deg but scored nowhere (`kin_rms` has no toe group, `event_rms` excludes toes) and no toe-only ablation exists. The one-leg balance champion is already a subset in disguise (its `bhold` moves only the parked swing knee; the shift moves only the two hip adductions). The bat's `leglift` changes 8 of 27 joints, `plant` 4, and the trunk columns of three arm tables are dead data.
- **Mostly not applicable to the champions that score best.** The long jump's take-off and landing, the bat's swing and the dribble's strokes are dense open-loop muscle tables found by search (3040 and 4352 numbers for the jump; 11 quintic knots x 16 joints for the bat; three 16-muscle tables for the dribble). Their joints all move, there is no sparsity pressure in the search, and no per-joint ablation exists anywhere, so there is no evidence that any joint is "along for the ride". Freeing legs and trunk in the dribble is measurably worse: the closed loop differs from the arm-only replay by 4 cm and 0.25 m/s because the rest of the body reacts to the stroke.
- **Every hand-posed keyframe family is calibrated around a gap between the commanded and the reached posture** (table tennis: forearm rotation asked +1.17, reached +0.44; dribble: "aiming past the measured miss, since the arm lags its command"; runner: the swing knee target 143 deg is unreachable, the knee stays at 44-48 deg). So omitting a joint needs a re-practice of the parameters, not just an edit.

## What the SDK does with a joint that is left out (all six audits agree)

There are two meanings of "left out" today, and neither is "free":
- `Pose` (`contraction.w:136-169`): on a pair-per-joint body the joint holds the chunk's START command; on a MyoSuite body single-joint muscles hold the start command but two-joint muscles (rf, hamstrings, gastrocnemius) are computed with the left-out joint at its REFERENCE angle. So omitting a hip, knee or ankle silently re-commands the biarticular muscles; omitting a toe, elbow, arm or spine joint is a clean hold.
- `Chunk#to` (`chunk.w:223-224`): writes 0 for every unlisted muscle of the track's mask.
- After a reflex-gain-0 chunk the start command is the previous pose, not the measured posture, so "hold the measured posture" needs an explicit capture (untested).
- Expressible with no new API: a separate `Track` on a muscle mask (the dribble and bat already work this way), `Chunk#rate` zeros for an exact hold, `Chunk#stagger` for per-group timing, and run-time keyframing (`update_train` in the bat rewrites knots every 20 ms).
- A joint-level `free` for the runner needs a 6-line `pin`/`free`/`resolve_free` (sketched in `audit_runner_sdk.md` B5): resolution by phase share (chunks end on latches, not on time), cyclic, through the left-step mirror.

## Ranked experiments (value / cost / risk; cheapest first within a band)

| # | experiment | where | v / c / r |
| --- | --- | --- | --- |
| 1 | sweep `ref_to_st_toe` in the runner champion's params (tests the toe-off example directly; params only). **RUN 30 Sep** (`scratchpad/toe/RESULT.md`): the toe must extend (0 or +10 deg loses 11-13 of 48 starts to the guard) but -30 to -45 is equivalent; the touchdown and mid-stance toes are nearly free (about 1%); no score gain | runner | 2 / 1 / 1 |
| 2 | the bat's aim law: a third aim vector along the bat (vertical aim is a three-joint direction, spine flexion, top-wrist deviation, spine lateral; the gains had to grow 2.6 to 4.9 because the vectors run out of authority; "a better aim law" is the open lead in README and HANDOFF) | bat | 4 / 3 / 3 |
| 3 | dribble: a wait-posture tail after each muscle table that pins wrist flexion, shoulder abduction and elbow (the left hand's second stroke starts from a wrist-flexion scatter of sd 0.445); needs a hook that copies the measured contraction | dribble | 3 / 2 / 2 |
| 4 | bat: per-joint hold of the knots (top-hand wrist, left shoulder abduction first; spine lateral is expected to lose) and a `gather` 0.5 / 0.75 scan (no code) | bat | 3 / 2 / 3 and 2 / 1 / 1 |
| 5 | the Bolt sprint keyframes: hold elbows 90 and spine 4, toes free except at toe-off, drop the synthetic `drive_td` / `drive_to` (`ref_*` overrides) | runner | 3 / 2 / 2 |
| 6 | hurdles: the trail keyframe with the lead-leg joints held (the one place the intent is explicitly a subset, and where the 0.991 m attempt fails); expect a tie or loss | hurdles | 3 / 3 / 4 |
| 7 | table tennis: per-joint co-contraction (wrist only) in the backhand's ready chunk (`Pose#set(joint, q, stiff)` already takes it) and dropping the `stroke` keyframe (identical results with its push at 0) | table tennis | 3 / 1 / 3 and 1 / 1 / 1 |
| 8 | hygiene, no behaviour change: delete the dead tunables (sprint gait-1/2 keys bit-identical when forced to extremes; 92 of 111 `j_*` keys of the long-jump champion; about 21 of the bat champion's; a stripped long-jump file shrinks the next search from 111 to 19 tunables) | sprint, jump, bat | 1-2 / 1 / 1 |
| 9 | dribble: per-joint ablation of the three tables on the bit-exact replay (fingers first: the fact-check calls them "no measurable effect", yet the tables drive them) | dribble | 2 / 2 / 1 |

## Where the full-vector keyframe is right (leave as is)

The runner's gear strides (a gear is a knife edge: every one-at-a-time move of gear 5 falls; risk 5), the Bolt start keyframes (little data, nothing to free), the landing leg at touchdown (contact geometry), the dribble's lunge (an IK solution from foot xy, already a task-space subset) and trunk (spine 0.55 to 0.5 loses pass 1), and the kick (the leg-on-leg contact is needed: 0 of 16 without it, 16 of 16 with it; phase 2 fails on robustness, not on the pose). For the balance hold "free" must mean HOLD, never release: the parked shank presses on the stance thigh with 204-223 N and searching that load down cost 4-9 of 120 starts. The 14 sagittal channels of the Keyframe Bench cannot show the balance and kick families' frontal keyframes (adduction, subtalar).

## Elements that do nothing (drop candidates; all by reading, none tested)

The runner's `hr` (already dropped from both champions: it conflicts with toe-off, ankle -1.3 against +25 six percent apart) and `kl` (not in either champion's controller); the balance champion's `b_down` / `b_mid` / `b_end` (never run in a successful 310 s start); 24 of the 25 stance chunks built by the dribble champion; the jump's board / takeoff / hang..sit chunks (not entered by the newest champion); the table-tennis `stroke` keyframe.

## What this changes

The cheap, immediately useful items are 1, 5 and 8 (params only). The item with the most upside for a goal is the bat's aim law (2). The big structural item, a joint-level pin/free in the SDK, pays only for the runner and possibly the hurdles, and each use needs its parameters re-practised. For table tennis the useful idea is not a subset of joints but Erik's constant-plane stroke family (see `scratchpad/tt4/PLANE_NOTE.md`).
