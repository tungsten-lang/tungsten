# Baselines of metabench

Prior flip-graph programs run under the metabench contract (`bench/README.md`), on the same tasks, seeds, budgets and machine as
the metaflip walker: the Kauers-Moosbauer programs (`km2022`, `km2024`) and Perminov's `flip_graph` over Z2 (`tfg`).

| file | content |
| --- | --- |
| `PINS.md` | commits, licences, compiler, flags, build record |
| `DIFFERENCES.md` | what each program does: problem statement, moves, counting, reductions, restarts, randomness, output, cost per step |
| `build.sh` | out-of-tree build of the three executables from the pinned clones (Homebrew LLVM 23.1.0 with `libomp`) |
| `adapters/` | the three adapters, converters between MFW1 and the programs' formats, the instrumentation patches; `adapters/README.md` lists every parameter |
| `algos-baselines.tsv` | rows for `bench/algos.tsv` |
| `check-patches.sh`, `check-converters.sh` | the instrumentation leaves the search unchanged; the converters are exact |
| `pilot/` | the driver, job files and result tables of the pilot runs |

Quick start:

```
bench/baselines/build.sh                       # binaries in ~/.tungsten/metaflip/experiments/record-hunt-20260926/work/sota/build/bin
mkdir /tmp/run && cd /tmp/run
MB_TARGET=23 bench/baselines/adapters/tfg 3x3x3 1 10 /tmp/run   # TASK SEED BUDGET_CPU_S OUTDIR; writes result.json, scheme.mfw
bench/baselines/check-patches.sh && bench/baselines/check-converters.sh
```
