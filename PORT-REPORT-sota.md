# PORT-REPORT-sota: baselines for metabench (agent E2)

Branch `port/sota` (from `metaflip-tungsten-port`), worktree `/Users/erik/tungsten-mf-port-sota`. Nothing merged or pushed;
`/Users/erik/tungsten` untouched.

@@RESULT_SUMMARY@@

## 1. Files added

All under `bits/tungsten-metaflip/bench/baselines/` unless stated.

| file | content |
| --- | --- |
| `PINS.md` | commits, compiler, flags, build record, patch check |
| `DIFFERENCES.md` | catalogue of the four programs (metaflip, km2022, km2024, tfg): problem statement, moves, counting, reductions, restarts, randomness, output, cost per step, with `file:line` citations |
| `build.sh` | out-of-tree build of the three executables from the pinned clones |
| `check-patches.sh`, `check-converters.sh` | patched and unpatched programs follow equal trajectories; the converters are exact |
| `algos-baselines.tsv` | rows for `bench/algos.tsv` |
| `adapters/{km2022,km2024,tfg}` | the three adapters (POSIX sh), `adapters/lib.sh` shared code, `adapters/README.md` |
| `adapters/{mfw-lib,mfw2exp,exp2mfw,mfw2tfg,tfg2mfw,std2mfw}.awk` | scheme converters (words of any width) |
| `adapters/patches/{km2022,km2024,tfg}-instrumentation.patch`, `NOTICE.md` | the instrumentation, with the upstream licences |
| `pilot/{job.sh,run.sh,summarize.sh,README.md}`, `pilot/jobs/`, `pilot/results/` | the pilot driver, job files and the result tables |
| `../../../../PORT-REPORT-sota.md` | this report |

@@BODY@@
