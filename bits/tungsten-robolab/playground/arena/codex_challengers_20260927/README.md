# Codex challenger arena ledger (27-29 Sep 2026)

The record of the isolated arena that Codex's challenger campaign ran in its
worktree (`/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/`,
branch `codex/robolab-challengers`, never committed there). That arena shared
the first 185 rows of `playground/arena/history.jsonl` and then diverged. It is
a record, not part of the live board: `playground/arena.py` never reads this
directory, and the live `playground/arena/champions.json` and
`playground/arena/history.jsonl` are unchanged by it.

- `playground/arena/codex_challengers_20260927/history.jsonl`: its 98 rows
  after the split (64 lose, 24 win, 9 promoted, 1 seeded), verbatim.
- `playground/arena/codex_challengers_20260927/champions.json`: its final
  champions for the five trials it promoted (`bat_power`,
  `dribble_crossover_25`, `gpt_jump_stable6`, `search_jump_legal`,
  `search_jump_robust_legal`), verbatim. Their `frozen_params` are committed in
  `playground/arena/params/`; their `frozen_controller` binaries exist only in
  that worktree's `bin/champions/`.

The live board imported the winners separately, against its own incumbents
(`params/codex/`, controllers `bin/challengers/codex-*`; see
`HANDOFF_20260929.md`, section 6). `gpt_jump_stable6` is defined in
`playground/arena/trials.json` but has no live champion. The campaign report is
`GPT_CHALLENGERS_20260927.md`.
