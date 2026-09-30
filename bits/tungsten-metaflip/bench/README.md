# metabench and metascore

`metabench` runs randomized flip-graph searches under a uniform CPU budget and records one JSON line per run.
`metascore` turns those lines into tables, LaTeX fragments and pgfplots data. Both are Tungsten programs
(`tools/metabench.w`, `tools/metascore.w`; library in `lib/metaflip/bench/`); the raw data files are plain JSONL.

## 1. Objects

| object | definition |
| --- | --- |
| task | `(id, n x m x p, start, target rank r*, tier)`; the search must reach rank `<= r*` over GF(2) |
| start | `standard` (the naive algorithm, rank `nmp`) or a named seed scheme from `seeds.tsv` |
| algorithm | an executable configuration with a unique name `algo/variant` (`algos.tsv`) |
| run | `(algorithm, task, seed)`: one single-threaded process tree; `seed = seed_base(task) + index` for every algorithm |
| budget `B` | CPU seconds of the process tree (user + system, measured by the harness) |
| hit | best rank `<= r*` reached within `B`, with a scheme that passes the independent exactness verifier |

A run that has no hit within `B` is right-censored at `B`.

## 2. Files

All files are tab separated; lines starting with `#` are comments.

`tasks.tsv` columns: `id n m p start target tier runs budget_cpu_s seed_base target_source calibration`.
`id` is `NxMxP` (start = standard algorithm) or `NxMxP@seedname` (start = the named seed).
`runs` is N, the planned number of seeds; `seed_base` makes seed `i` equal `seed_base + i`.
`calibration` is `pilot-YYYYMMDD` when the budget was set from pilot runs of `metaflip/V0`, else `uncalibrated`.

`seeds.tsv` columns: `name shape rank file sha256 source`. `file` is relative to this directory (or absolute).

`algos.tsv` columns: `algo command notes`. `command` is a shell command line; the harness substitutes
`{bench}` (this directory), `{task}`, `{seed}`, `{budget}` (decimal CPU seconds) and `{out}` (the run directory), each shell-quoted.
The command follows the adapter contract of section 3.

### MFW1 scheme files

```
MFW1 n m p rank
<u> <v> <w>          one line per term, three lowercase hexadecimal words without leading zeros
```

A term is `u (x) v (x) w`; the sum of the terms over GF(2) is the matrix-multiplication tensor of `A (n x m) * B (m x p) = C (n x p)`:
bit `i*m+j` of `u` is `A[i][j]`, bit `j*p+k` of `v` is `B[j][k]`, bit `i*p+k` of `w` is `C[i][k]`.
Canonical files list the terms in strictly increasing `(u, v, w)` order. The verifiers accept any order.

## 3. Adapter contract

An adapter is an executable invoked as

```
adapter TASK_ID SEED BUDGET_CPU_S OUTDIR
```

* `OUTDIR` exists and is the working directory. It contains `start.mfw`, the start scheme of the task (the naive
  algorithm for `standard` starts). stdout and stderr go to `OUTDIR/stdout.log` and `OUTDIR/stderr.log`.
* The harness exports `MB_BENCH`, `MB_TASK`, `MB_N`, `MB_M`, `MB_P`, `MB_TARGET`, `MB_START`, `MB_START_FILE`,
  `MB_START_RANK`, `MB_SEED`, `MB_BUDGET_CPU_S`, `MB_OUT`, and `OMP_NUM_THREADS=1` (also
  `VECLIB_MAXIMUM_THREADS`, `OPENBLAS_NUM_THREADS`, `MKL_NUM_THREADS`). The same values are recoverable from
  `tasks.tsv` and the four arguments.
* The tool runs single-threaded, takes all of its randomness from `SEED`, and stops as soon as the best rank is `<= MB_TARGET`.
  It also stops on its own before `BUDGET_CPU_S` CPU seconds have passed. The harness enforces the budget
  independently (section 5).
* Exit status 0 means the adapter ran to completion, hit or not. Any other status is an infrastructure error.
* The adapter writes `OUTDIR/result.json` (fields below) and, when the target was reached, `OUTDIR/scheme.mfw`.
  A scheme for runs that did not reach the target is welcome (the best scheme found); the harness verifies whatever it finds.

`result.json` is one JSON object. Every field except `hit` and `best_rank` is optional; use `null` for what the tool cannot report.

| field | meaning |
| --- | --- |
| `hit` | the tool's claim: best rank `<= MB_TARGET` (the harness re-verifies) |
| `best_rank` | best rank reached |
| `proposals_total`, `proposals_to_hit` | attempted moves (a candidate flip or split that was considered), whole run / up to the hit |
| `flips_total`, `flips_to_hit` | accepted moves: edges traversed in the flip graph |
| `trace` | `[[cpu_s, proposals, flips, rank], ...]`: the first time each new best rank was reached, strictly decreasing `rank`, non-decreasing time; `cpu_s` is the tool's own process-CPU clock counted from process start |
| `scheme_sha256` | SHA-256 of `scheme.mfw` |
| `instr_retired`, `cycles`, `max_rss_kb` | the tool process's retired instructions, cycles and peak resident set (see `adapters/common.sh`, `mb_measure`) |
| `tool`, `tool_version`, `notes` | provenance: executable, revision, and what a "move" is for this tool |

`adapters/common.sh` provides shell helpers: `mb_task_field ID FIELD`, `mb_seed_path NAME`, `mb_measure LOG CMD...`
(runs `CMD` as the direct child of `/usr/bin/time -l` and sets `MB_INSTR`, `MB_CYCLES`, `MB_RSS_KB`),
and `mb_json_tail` (emits the measured fields as JSON members).

The harness never trusts a tool for the cost of a run: CPU time comes from the resource usage of the process tree,
the hit from the exactness verifier. The tool supplies moves, trace, instruction counts and its own diagnostics.

## 4. Records

`metabench` appends one JSON object per run to `DIR/<algo>.<variant>.jsonl` (one file per experiment and algorithm;
`/` in the algorithm name becomes `.`). Schema 1:

| field | meaning |
| --- | --- |
| `schema`, `experiment`, `algo`, `variant`, `task`, `index`, `seed` | identity; `(experiment, algo, task, seed)` is the key |
| `status` | `ok`, or `error` with `error` set (infrastructure failure; excluded from all statistics) |
| `target_rank`, `start_rank`, `budget_cpu_s` | copied from the task |
| `hit` | the classification used by all statistics: tool claim, verified exact, and `cpu_s_to_hit <= budget_cpu_s` |
| `tool_hit`, `exact` | the tool's claim; the verifier's verdict (`null`: no scheme, or verification disabled) |
| `best_rank` | best rank reported by the tool (`null` if unreported) |
| `cpu_s_total`, `cpu_s_user`, `cpu_s_sys` | harness-measured resource usage of the process tree |
| `cpu_s_to_hit` | `cpu_s_total` for a hit (the tool stops at the target), else `null` |
| `wall_s_total`, `load1` | wall-clock seconds; one-minute load average at job start |
| `proposals_total`, `proposals_to_hit`, `flips_total`, `flips_to_hit`, `trace` | as in `result.json` |
| `instr_retired`, `cycles`, `max_rss_kb` | as in `result.json` |
| `scheme_sha256`, `exit_code`, `signal`, `host`, `commit`, `tool` | provenance |

Runs are executed in a seeded random order: within each task, blocks `(seed index)` are shuffled and the algorithms
inside a block are shuffled, so background load reaches all algorithms alike. The order is a function of
`--order-seed` (default: a hash of the experiment name), and a resumed experiment continues the same order.

## 5. Budget and censoring

* A run is classified after the fact by its measured CPU time: `hit` requires `cpu_s_total <= B`. A tool that
  overshoots `B` while finding the target is censored; the rule is the same for every algorithm.
* Termination is enforced in three layers: the tool's own budget check, `ulimit -t ceil(B)+2` (kernel), and a wall-clock
  fail-safe (`5 B + 120` seconds). The fail-safe kills the process group. A run killed by it is recorded with
  `status = error`, because its CPU budget was not exhausted.
* The process tree is one process group: `kill(-pgid)` reaches every descendant.

## 6. Exactness gate

For every run with a hit (`--verify all`: every run with a scheme) the harness passes `scheme.mfw` to
`Verifier.exact?(path, n, m, p)`. The verifier backends are listed in `verifiers.tsv` (`name command`), selected with
`--verifier NAME`. The default backend is the dense Ruby oracle `tools/verify_tensor.rb`; a hit whose scheme
fails verification is recorded with `exact = false` and does not count. Such records must not occur.

## 7. Metrics

Per algorithm and task, with N runs, `k` hits, budget `B`, hit time `T_i` (CPU seconds), censored runs `T_i = infinity`:

1. **Success rate** `p = k/N` with the Wilson 95% score interval `(p + z^2/2N +- z sqrt(p(1-p)/N + z^2/4N^2)) / (1 + z^2/N)`, `z = 1.959964`.
2. **ERT** (expected running time with restarts): `ERT = sum_i min(T_i, B) / k`, infinite for `k = 0`. Cost axes:
   CPU seconds; retired instructions; proposals; accepted flips. On the non-CPU axes a censored run contributes the
   total the tool reports for that run. The 95% interval is the percentile bootstrap: `R >= 2000` resamples of the N runs
   with replacement, interval `[sorted[floor(0.025 R)], sorted[R-1-floor(0.025 R)]]`, replicates without a hit are infinite.
   The random generator is the 63-bit LCG `s <- 6364136223846793005 s + 1442695040888963407 (mod 2^63)`, output
   `(s >> 32) & 0x7fffffff`, range reduction `(x * n) >> 31`, seeded per (task, algorithm) from the run seeds.
3. **Kaplan-Meier** estimate `S(t) = prod_{t_j <= t} (1 - d_j/n_j)` of the time to target, with censoring at `B`;
   `T_q = min { t : S(t) <= 1 - q/100 }` for q = 25, 50, 75 (undefined when the curve stays above).
4. **Descent profile**: `rank_i(t)` is the best rank of run `i` at CPU time `t` (from the trace; `r_0` before the first
   entry). Reported: median and quartiles over runs at log-spaced times in `[t_0, B]`, and
   **AUC** `= mean_i  (1/ln(B/t_0)) integral_{t_0}^{B} (rank_i(t) - r*) / (r_0 - r*) d ln t`, lower is better (0: at the target from `t_0` on; 1: never leaves the start).
5. **Throughput** in proposals and in accepted flips per CPU second (`sum counts / sum cpu_s_total`), and the cost to target on
   each axis; implementation speed and algorithmic efficiency are reported separately.
6. **Across tasks**: the Dolan-More performance profile on ERT, `rho_A(tau) = |{tasks : ERT_A <= tau min_B ERT_B}| / |tasks|`
   (unsolved tasks count as infinite), the solved fraction, and the geometric mean of ERT ratios against a reference algorithm
   over the tasks both solve.
7. **Comparison of two algorithms** on one task: the ERT ratio `ERT_A / ERT_ref` and the success-rate difference, both
   with 95% percentile bootstrap intervals in which the two arms are resampled independently.

## 8. Commands

```
metabench list   [--bench DIR]                        tasks, algorithms, seeds
metabench run    --experiment NAME --algo A[,A2] --tasks tier1|tier2|tier3|ID[,ID] --n N --jobs J
                 [--budget-scale X] [--out DIR] [--verifier NAME] [--verify hits|all|none] [--order-seed S]
metabench verify --scheme FILE --shape NxMxP          run the exactness verifier on one file
metascore summary --in DIR|FILE... [--reference ALGO] [--tsv FILE] [--md FILE] [--latex DIR] [--data DIR]
```

`--out` defaults to `~/.tungsten/metaflip/experiments/record-hunt-20260926/work/eval/NAME/`. Runs are resumable:
a finished `(experiment, algo, task, seed)` row is skipped on the next invocation.
