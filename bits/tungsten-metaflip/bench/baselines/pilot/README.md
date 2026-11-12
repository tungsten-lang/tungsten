# Pilot runs of the baselines

Scripts and results of the pilot in which each baseline runs from the standard algorithm through its adapter, as metabench calls
it (`bench/README.md`, section 3), before the harness existed. The definitive measurements are the `metabench` experiments.

| script | role |
| --- | --- |
| `job.sh ROOT ALGO TASK TARGET SEED BUDGET [VAR=VALUE ...]` | one run: writes `start.mfw`, exports the `MB_*` variables, runs `adapters/ALGO`, measures the CPU time of the process tree with `times`, verifies `scheme.mfw` with `tools/verify_tensor.rb`, writes `row.tsv` |
| `run.sh ROOT JOBS [PARALLEL]` | the jobs of a file (one `ALGO TASK TARGET SEED BUDGET [VAR=VALUE ...]` per line) in a seeded shuffled order, at most `PARALLEL` (default 4) at a time; collects `ROOT/rows.tsv` |
| `summarize.sh ROWS.tsv...` | per (label, task): runs, hits, exact schemes, medians over the hits, expected running time |

Columns of `rows.tsv`: `label` (adapter plus settings), `task`, `seed`, `budget` (CPU seconds), `target`, `status`, `hit`,
`best_rank`, `tool_cpu_to_hit` (the program's own clock at the hit, seconds), `flips_to_hit`, `proposals_to_hit`, `flips_total`,
`tree_cpu` (user + system of the adapter and everything it started, seconds), `wall_s`, `exact` (verifier verdict on `scheme.mfw`),
`instr_retired` (of the program), `walks` (programs started). `summarize.sh` reports `ert_cpu_s = sum(min(T, B)) / hits` with `T`
the tool clock.

Commands (`jobs/` holds the job files; `ROOT` is `~/.tungsten/metaflip/experiments/record-hunt-20260926/work/sota/pilot`; results:
`results/`):

```
pilot/run.sh $ROOT/A    pilot/jobs/A.txt 4     # 2x2x2, 2x2x3, 2x3x3, 3x3x3; seeds 1..10; 3 programs; budget 180 s
pilot/run.sh $ROOT/B    pilot/jobs/B.txt 4     # 3x3x4 (budget 600 s) and 4x4x4 (1800 s); seeds 1..3; 3 programs
pilot/run.sh $ROOT/S1   pilot/jobs/S1.txt 4    # 3x3x3, seeds 1..40, path length and runner count sweeps, budget 60 s
pilot/run.sh $ROOT/S2   pilot/jobs/S2.txt 4    # 3x3x4, seeds 1..10, the same sweeps, budget 300 s
pilot/run.sh $ROOT/S3   pilot/jobs/S3.txt 4    # 4x4x4, seeds 1..3, path length (km2024) and runner count (tfg) sweeps, budget 600 s
pilot/run.sh $ROOT/C    pilot/jobs/C.txt 4     # the ten tier-1 tasks, seeds 1..3, budget 90 s
pilot/summarize.sh $ROOT/A/rows.tsv
```
