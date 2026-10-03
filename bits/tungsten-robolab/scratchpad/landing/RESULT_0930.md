# Verification of the landing candidate 2cce555da (branch robolab-land-tmp), 30 Sep 2026

Everything below ran from a FRESH worktree of exactly that commit (`/Users/erik/rl-verify-0930`), isolated with `BIT_HOME=<worktree>/bits` (the venvs and the compiler image are symlinks to the shared checkout; the built entries and the arena paths resolve inside the worktree; `arena.ROOT` is asserted equal to the worktree). Scripts: `verify_0930.sh` (builds), `verify_0930b.sh` with `replay_sprint.py` and `replay_soccer.py` (replays), `verify_0930c.sh` (table tennis). Logs: `verify_0930.log`, `verify_0930b.log`, `verify_0930c.log`.

| check | result |
| --- | --- |
| builds in the worktree: `myo_soccer_v4`, `run_gearx`, `myo_tt` | all exit 0 (`myo_soccer_v4` 72 s, `run_gearx` 46 s, `myo_tt` and its check under 4 min together; binaries of 5,652,232 and 5,333,216 bytes for the first two) |
| isolation: build manifests naming the shared tree | none |
| `py_compile` of the changed Python | ok |
| sprint, beyond-human champion (chain C, `params/run_gearx_v4_beyond_c.txt`), first 2 seeds x 30 s | 10.159 and 10.105 m/s = the recorded scores, to 1e-9 |
| sprint, P95 champion (`params/run_gearx_v4_p95_x5a.txt`), first 2 seeds x 30 s | 8.272 and 8.291 m/s = the recorded scores, to 1e-9 |
| soccer official champion H2b on the first 3 seeds of `soccer_single_leg_310_40` x 310 s | all 3 hold (score 1.0 each); every numeric metric of the row equals the recorded row of `scratchpad/soccer4/evals/bal1_300-soccer7-bh1-20260929-224305.json` |
| soccer old brake params (`bhold` off), starts 97100 and 97101 x 20 s | `stand_time`, `bal1_raw`, `time` equal Z's identity rows (`out/hazard/rows_id1.jsonl`, `idB`) |
| table tennis default path, `playground/tt_fast.py check`, 6 episodes | 0 differ (standard 9.8 s, fast 5.2 s) |
| backticked paths of `HANDOFF_20260929.md` | all present except the git-ignored caches `playground/cache/*` and, at that commit, the anatomy agent's then uncommitted files (`playground/calibrations/v5.json`, `v5b.json`, `scratchpad/anat5/LOG.md`), which the second candidate adds |

The first run of the replay stage (inside `verify_0930.sh`) failed because its code ran from heredocs: multiprocessing `spawn` re-imports `__main__` by path, every worker died with `FileNotFoundError: '<stdin>'`, and the pool parent respawned them forever. The replays were rewritten as guarded `.py` files and all passed.
