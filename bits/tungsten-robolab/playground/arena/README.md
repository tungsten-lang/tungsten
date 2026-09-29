# Arena: champions and challengers

`trials.json` defines each trial (task, metric, held-out seeds, env vars).
`champions.json` holds the current champion per trial (frozen binary under
`bin/champions/`, params under `params/`, per-seed scores). `history.jsonl`
logs every challenge.

    # robolab bodies use .venv, MyoSuite trials use .venv-myo
    .venv/bin/python playground/arena.py board
    .venv-myo/bin/python playground/arena.py eval tt_p2 --params params/x.txt --controller bin/robolab_myo_tt --note "spin model" --promote

Rules for challengers:

- Evaluate a *copy* of your binary (`cp bin/robolab_x bin/challengers/x-<tag>`),
  never a binary you are still rebuilding: a rollout that runs a half-edited
  controller scores the wrong program, and a promotion freezes whatever the
  path holds at the end of the run.
- A new trial is a new entry in `trials.json` (fixed seeds, fixed env). Never
  change an existing trial's seeds, env or metric: the champion's scores were
  taken on them. Make a new trial instead (e.g. `hurdle_hs` beside `hurdle`).
- Deterministic trials (fewer than 5 seeds) promote on any strict gain; stochastic
  trials need p < 0.05 on the paired sign-flip test.
- `champions.json` and `history.jsonl` are written under a file lock
  (`arena/.lock`); a promotion is refused as stale if the champion changed
  while the challenger was being evaluated — re-run it against the new one.
- Give a trial enough starts to detect the gain you care about. The sign-flip
  test only counts starts where champion and challenger differ: with k such
  starts the smallest possible p is 2^-k, so a challenger that only rescues
  2 falls on an 8-start trial cannot win (p >= 0.25). `search_jump_robust`
  (32 starts, larger perturbation) exists for exactly that reason.
