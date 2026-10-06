# Brief: robolab progress page v29 (agent P9; read fully, then work)

You are agent P9 of the robolab campaign. Repo: /Users/erik/tungsten/bits/tungsten-robolab (all paths relative to it). Notes go in `scratchpad/progress29/` (your own directory); write `scratchpad/progress29/LOG.md` as a timestamped log, FIRST a skeleton, then one entry per finding.

## What and why

The progress page (`site/progress/build_progress.py` builds `site/progress/progress.html`; the last published version is v28 of 30 Sep, about 01:06) is Erik's results page. Bring it up to date with what was measured since: the arena champions changed after v28 for `long_jump_v4_beyond`, `long_jump_v4_beyond_robust`, `long_jump_v4_beyond_robust96`, `sprint_top_speed_v4_beyond_fresh128` and `sprint_top_speed_v4_beyond_fresh512` (see `playground/arena/champions.json`, field `time`), and several investigations ended. DO NOT PUBLISH anything: the page's owner account is an open decision of Erik's; your job is a rebuilt, verified `progress.html` (plus the updated `build_progress.py`) and a log.

## The rules of this page (Erik's, read `/Users/erik/.claude/projects/-Users-erik-tungsten/memory/feedback_progress_page_results_not_status.md` in full with the Read tool)

RESULTS, NOT STATUS. Every event shows its CURRENT BEST on the board tile and on its card (numbers from `champions.json` through `F()` / `V()`; re-audit every tile against `champions.json`), the dated "when / best / what changed" progression, before-to-now bars, and only the honesty labels that change how a number reads (`Tuned to one start`, `Labelled body variant` hatched bars, `Athlete body`, `Policy from Codex`). No goals, no agents, no "next", no arena mechanics or p-values, no second person. Keep the design, the funny old videos (hurdlers) and every `<video>` as `figure#v-<stem>` with its Copy link. Presentable prose: short, concrete, no research-log voice.

## What is new (read the sources; every number you add must be traced to one of them and the trace written in LOG.md)

1. LABELLED beyond-human long jump (the page has none yet): README "Long jump past the human record on a LABELLED beyond-human body with an unlimited run-up (30 Sep 2026, agent L3)" and its round 2 (agent L4, 1 Oct), `HANDOFF_20260929.md` goal-standing bullets, arena trials `long_jump_v4_beyond` (one start 10.848 m), `long_jump_v4_beyond_robust`, `long_jump_v4_beyond_robust96` (96 fresh starts: mean 7.075 m, 87 legal). The body is the invented stretch (strength x2.4, muscle speed x2.0, tendon x1.5, activation x0.8) with an unlimited run-up: it needs the hatched "Labelled body variant" treatment, and is never put on the human-body bars. No video exists on the page for it: look for a rendered mp4 under `out/` only to NAME it in the log (do not upload or embed anything).
2. Labelled beyond-human sprint: README "Sprinters on a beyond-human body (labelled), round 5" and "round 6 (3 Oct 2026, agent S6)"; trials `sprint_top_speed_v4_beyond*`. The v28 card says "10.15 m/s, 9 of 12 stay up"; the progression is now: round 4 chain C falls on about 30 % of fresh starts, round 5 chain F1 7.4 %, round 6 chain S6a 5.6 % (2280 fresh seeds), survivors at 10.11 m/s.
3. Heel recovery and the data-only anatomy (README "Heel recovery and the rectus femoris split (30 Sep)", validated `v5b` / `v5` results in `scratchpad/anat5/REPORT.md`): include only if it changed a best or a progression row of an existing event.
4. Table tennis: the best is unchanged (40 % on phase 2, was 33 %). The plane-hold investigation (README "Table tennis: does the paddle hold one plane? (30 Sep 2026)", `scratchpad/tt4/PLANE_NOTE.md`) is a research result and belongs in the README, not here, EXCEPT one short sentence on the table-tennis card if it changes how the 40 % reads (an ideal-everything oracle returns about 65 %, the 2025 winner 64 %).
5. Partial keyframes (`scratchpad/subsets/REPORT.md`) and the landing/size work are not results of an event: leave them out unless an event's progression row changed.

## Method and rules

- Work in `site/progress/build_progress.py`; regenerate with `python3 site/progress/build_progress.py`; `--publish` and `--mark-published` are NOT to be run. Do not edit `published.json`, `site/eids.txt`, any arena file, any `.w`, any params, or anything outside `site/progress/` and `scratchpad/progress29/`.
- Check the result: render with headless Chrome as in `/Users/erik/.claude/projects/-Users-erik-tungsten/memory/reference_headless_chrome_artifact_preview.md` (fresh port, prove the served page is the new one before judging; light AND dark theme through `data-theme`; desktop width and a 390 px iframe); read the screenshots with the Read tool; fix overflow, clipped text, label collisions, bars drawn to scale (every label names a value the chart reaches).
- Honesty: "labelled" wherever a beyond-human number appears; never compare it with a human-body number; no claim the sources do not make; if a source is ambiguous, leave the number out and say so in LOG.md.
- DO NOT touch git state. Nothing of yours runs in the background; no CPU-heavy work (the machine is shared). Python multiprocessing is not needed here.

## Rules for agents (earlier agents died or lost work here)

- STALL AVOIDANCE: a single tool call that stays silent for 10 minutes kills you; keep every Bash call under 3 minutes; keep your reasoning between calls to a few sentences. The host suspends for hours at night and freezes you with it: if your log notes a clock jump, that is why, not a fault.
- The harness refuses subagent writes of a file named REPORT.md: put the report in a "FINAL STATE" section of `scratchpad/progress29/LOG.md` and in your hand-back message (at most 15 lines: what changed on the page, every new number with its source, what you left out and why, how to publish when Erik decides: `build_progress.py --publish` prints the files map).
- Use the Read tool for reading; one combined grep beats five calls; write each file with one call; retry a call that fails with "auto mode classifier gave no verdict" once.
