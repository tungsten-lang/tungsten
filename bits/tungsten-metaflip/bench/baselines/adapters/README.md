# Baseline adapters

Three executables run the prior flip-graph programs under the metabench contract
(`bench/README.md`, section 3): `adapter TASK_ID SEED BUDGET_CPU_S OUTDIR`. Each runs one single-threaded search on the
task's start scheme (`OUTDIR/start.mfw`, provided by the harness; a standalone call creates the standard algorithm), stops at
`MB_TARGET` or when its own CPU budget is used, and writes `OUTDIR/result.json` and, on a hit, `OUTDIR/scheme.mfw`
(canonical MFW1, verified by the harness).

| adapter | program | source | licence |
| --- | --- | --- | --- |
| `km2022` | `flip` of *Flip graphs for matrix multiplication* (Kauers, Moosbauer 2022) | `jakobmoosbauer/flips`, `code/` | GPL-3 |
| `km2024` | updated `flip` with the plus transition of Arai et al. | `jakobmoosbauer/flips`, `updated_code/` | GPL-3 |
| `tfg` | `flip_graph` (`--ring Z2`) of `ternary_flip_graph` (Perminov) | `dronperminov/ternary_flip_graph` | MIT |

Exact commits, compiler and flags: `../PINS.md`. What the programs do differently: `../DIFFERENCES.md`.
Build: `../build.sh` (out of tree; the clones are not modified and no third-party source is stored in this repository).

## Files

| file | role |
| --- | --- |
| `km2022`, `km2024`, `tfg` | the adapters (POSIX `sh`) |
| `lib.sh` | shared code: contract parsing, seeds, CPU accounting, `result.json` |
| `mfw-lib.awk`, `mfw2exp.awk`, `exp2mfw.awk`, `mfw2tfg.awk`, `tfg2mfw.awk`, `std2mfw.awk` | scheme converters between MFW1 and the programs' text formats (awk; words of any width) |
| `patches/*.patch` | the instrumentation applied to the copies that `build.sh` compiles, with `patches/NOTICE.md` |

## Conversions

MFW1 stores `C` as `n x p`, bit `i*p+k`. Both programs store the third factor as `c[j][i]` of a `p x n` matrix, so the converters
transpose it. The `.exp` text of the Kauers-Moosbauer programs lists `(a11+a12)*(b21)*(c11+c21)` with one-digit indices, hence
dimensions up to 9, every factor within 64 bits (`n*m`, `m*p`, `n*p <= 64`) and a start rank of at most `n*m*p` (the programs
allocate that many terms). The `tfg` text lists the coefficients term by term; it handles factors up to 256 bits.
An adapter that cannot represent the task exits with status 2 and a message.

| adapter | tasks accepted |
| --- | --- |
| `km2022`, `km2024` | `NxMxP` and `NxMxP@seed` with `N, M, P <= 9`, `N*M`, `M*P`, `N*P <= 64` and a start rank of at most `N*M*P` |
| `tfg` | any shape with `N*M`, `M*P`, `N*P <= 256` and any start rank |

Exit status: 0 the adapter ran to completion (hit or not); 2 unsupported task or bad arguments; 3 program not built;
4 the program failed (its last stderr lines are in the message).

## Instrumentation

The unmodified programs print no progress, cannot be seeded from the command line (`km2022`), and do not stop at a target rank
within a round (`tfg`). The patches add, without touching the search: environment variables `KM_SEED`, `KM_TARGET_RANK`, `KM_CPU_BUDGET`
(`km2022`); `KM_TARGET_RANK`, `KM_CPU_BUDGET`, `KM_LOOP`, `KM_RESTART`, `KM_POOL` (`km2024`); `TFG_CPU_BUDGET` (`tfg`, whose `--target-rank`
and `--seed` are its own options); a counter of the steps taken; a line `KMTRACE` / `TFGTRACE` on stderr for every new best
rank, with the process CPU time, the number of steps and the rank; a final `KMDONE` / `TFGDONE` line; a CPU timer
(`setitimer(ITIMER_PROF)`) that prints `KMTIMEOUT` / `TFGTIMEOUT` with the same counters and exits with status 3; in `tfg`,
the early return from the round at the target rank and a count of the plus/split moves; in `km2022`, the output of the scheme
whenever the rank decreased; in `km2024`, `KM_LOOP=1`, which repeats the program inside the process with the seed
`SEED + 1000003 k` for walk `k` until the target or the budget (`km2022` starts one process per walk), and `KM_POOL=s`, the
pool method of the paper (Algorithm 2: pools of `s` schemes per rank, walks of one reduction from random members) with the
program's walk as subroutine. Equal seeds give equal trajectories with and without the patches, and the walks of `KM_LOOP`
equal the walks of separate processes (`../check-patches.sh`); `KM_POOL` is new driver code and is off by default.

## Result fields

`trace` is `[cpu_s, proposals, flips, rank]` for each new best rank, `cpu_s` counted from the start of the adapter's first program
run. `scheme.mfw` is also written for a run that missed the target when a finished walk (`km2022`, `km2024`) or a saved
improvement (`tfg`) has the reported best rank. The program runs through `mb_measure` of `adapters/common.sh`; `cpu_s_tool`,
`instr_retired`, `cycles` and `max_rss_kb` are the sums over its runs (maximum for the resident set). What a proposal and a flip are for each program is stated in `notes` and in `../DIFFERENCES.md`.
The adapters read `MB_TARGET` (`TARGET_RANK` outside the harness), `MB_START_FILE`, `MB_N`, `MB_M`, `MB_P` and `MB_START_RANK` when set.
The CPU still available to the program is the budget minus the CPU that the harness's meter reports for the program runs so far
(`cpu_s_tool`, which prices the run when present) and 10 ms for the program's shutdown; without the meter it is the budget minus the
CPU time of the whole adapter process tree so far (`times`) and a reserve of `30 ms + 0.2 ms * rank` for the conversion after a hit.

## Parameters

Every parameter is an environment variable with the program's own default; `algos.tsv` can set them per variant, for example
`KM_PATH=10000000 {bench}/baselines/adapters/km2022 {task} {seed} {budget} {out}`.

| variable | meaning | default | source of the default |
| --- | --- | --- | --- |
| `KM_PATH` | path length limit per reduction | 1000000 | `code/README.md` example; paper Sect. 5 (`l = 10^6`); Sect. 4 uses `10^7` for single walks on 3x3x3 |
| `KM_TRIES` (`km2022`) | 1: keep reducing until one path fails; 0: one path per process | 1 | `code/README.md` (`restart = 1`) |
| `KM_CONTINUE` (`km2024`) | same, the program's `restart` argument | 1 | as above |
| `KM_SPLIT` (`km2024`) | one plus transition before the walk (needs rank < `n*m*p`) | 1 (0 with `KM_POOL`) | `updated_code/README.md` |
| `KM_POOL` (`km2024`) | pool size `s` of Algorithm 2 of the paper, 0: independent walks; implies `KM_CONTINUE=0` | 0 | paper Sect. 5 uses `s = 20000` with `l = 10^6` |
| `KM_SPLIT_DISTANCE` (`km2024`) | random flips after the split | 10 | the program's default (`main_mm.cpp:30`) |
| `KM_RESTART` | after a failed walk: `start` (again from the start scheme) or `best` (from where the walk ended) | `start` | paper Sect. 4: independent walks from the standard algorithm |
| `TFG_COUNT` | runners | 128 | the tool's default (`flip_graph.cpp:200`); its README examples use 128 |
| `TFG_FLIP_ITERATIONS` | iterations per runner and round | 1M | tool default |
| `TFG_MIN_PLUS`, `TFG_MAX_PLUS` | period range of the plus/split move, in flips | 5K, 100K | tool default |
| `TFG_PLUS_DIFF` | plus/split only below best + this | 4 | tool default |
| `TFG_RESET` | iterations without a new best before a reset | 10B | tool default |
| `TFG_COPY_BEST` | probability that a runner adopts a new best | 0.5 | tool default |
| `TFG_MAX_IMPROVEMENTS` | size of the reset pool | 10 | tool default |
| `TFG_REDUCE_PROB`, `TFG_SANDWICH_PROB` | full reduction scan, sandwiching, per flip | 0, 0 | tool default |
| `TFG_NO_VERIFY` | skip the Brent-equation check of the start scheme | 0 | tool default |
| `KM_BIN`, `TFG_BIN`, `MB_SOTA_BIN` | program paths | `build/bin` of `../build.sh` | |

Walk `k` of a run uses the program seed `SEED + 1000003 k` (reduced to `1 .. 2^31-2`); walk 0 uses `SEED`. `tfg` runs one process
with `--seed SEED`, `--ring Z2`, `--threads 1` and `--top-count 1` (the number of runners shown in the per-round table; the best runner
is the same for every value).
