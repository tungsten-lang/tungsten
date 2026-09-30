# metabench and metascore

`metabench` runs randomized flip-graph searches under a uniform CPU budget and records one JSON line per run.
`metascore` turns those lines into tables, LaTeX fragments and pgfplots data. Both are Tungsten programs
(`tools/metabench.w`, `tools/metascore.w`; library in `lib/metaflip/bench/`); the raw data files are plain JSONL.

Contents: 1 objects, 2 files, 3 adapter contract, 4 records, 5 cost and budget of a run, 6 exactness gate, 7 metrics,
8 the metaflip algorithms and the walker switches, 9 commands, 10 the suite and its calibration, 11 extending, 12 tests.

## 1. Objects

| object | definition |
| --- | --- |
| task | `(id, n x m x p, start, target rank r*, tier)`; the search must reach rank `<= r*` over GF(2) |
| start | `standard` (the naive algorithm, rank `nmp`) or a named seed scheme from `seeds.tsv` |
| algorithm | an executable configuration with a unique name `algo/variant` (`algos.tsv`) |
| run | `(algorithm, task, seed)`: one single-threaded process tree; `seed = seed_base(task) + index` for every algorithm |
| budget `B` | CPU seconds of the tool process (user + system, measured by the harness) |
| hit | best rank `<= r*` reached within `B`, with a scheme that passes the independent exactness verifier |

A run without a hit within `B` is right-censored at `B`. Tiers: 0 smoke, 1 fast, 2 medium, 3 long (descent profile is the
main output), 4 improvement of a public scheme (start = the scheme, target = one term lower).

## 2. Files

All tables are tab separated with a header line; lines starting with `#` are comments.

`tasks.tsv`: `id n m p start target tier runs budget_cpu_s seed_base target_source calibration`.
`id` is `NxMxP` (start = the standard algorithm) or `NxMxP@seedname`. `runs` is N, the planned number of seeds; seed `i`
is `seed_base + i`. `calibration` is `pilot-YYYYMMDD` when the budget was set from pilot runs of `metaflip/V0` (section 10), else `uncalibrated`.
`targets.md` lists the sources of every target rank.

`seeds.tsv`: `name shape rank file sha256 source`; `file` is relative to this directory (or absolute).
The improvement seeds are public schemes reduced modulo 2 and stored as MFW1: Perminov, FastMatrixMultiplication (MIT) and
MerlijnW70, fmm-schemes (CC-BY-4.0); `strassen2` is the Kronecker square of the rank-7 scheme of 2x2x2.

`algos.tsv`: `algo command notes`. `command` is a shell command line; the harness substitutes `{bench}` (this directory),
`{task}`, `{seed}`, `{budget}` (decimal CPU seconds) and `{out}` (the run directory), each shell-quoted, and runs it under `sh`.

`verifiers.tsv`: `name command not_exact_marker` (section 6).

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
  algorithm for `standard` starts). stdout and stderr of the adapter go to `OUTDIR/stdout.log` and `OUTDIR/stderr.log`.
* The harness exports `MB_BENCH`, `MB_TASK`, `MB_N`, `MB_M`, `MB_P`, `MB_TARGET`, `MB_START`, `MB_START_FILE`,
  `MB_START_RANK`, `MB_SEED`, `MB_BUDGET_CPU_S`, `MB_OUT`, `MB_TOOL` (the metabench binary), `MB_WALKER` (the compiled walker), and
  `OMP_NUM_THREADS=1` (also `VECLIB_MAXIMUM_THREADS`, `OPENBLAS_NUM_THREADS`, `MKL_NUM_THREADS`).
  The same values are recoverable from `tasks.tsv` and the four arguments.
* The tool runs single-threaded, takes all of its randomness from `SEED`, and stops as soon as the best rank is `<= MB_TARGET`.
  It also stops on its own before `BUDGET_CPU_S` CPU seconds have passed.
* The timed section of the adapter is the tool process. The adapter runs it through `mb_measure REPORT CMD...`
  (`adapters/common.sh`), which starts `CMD` as a child of `$MB_TOOL exec`. That helper meters the CPU time of `CMD` and its
  descendants with `wait4`, kills the process group at `1.05 * budget + 0.05` CPU seconds, and writes the exact usage to `REPORT`.
  Everything else the adapter does (parsing logs, writing `result.json`) is not part of the cost of the run.
* Exit status 0 means the adapter ran to completion, hit or not; a killed or failing tool is reported by the adapter's status only when no result can be written. Any other status is an infrastructure error.
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
| `cpu_s_tool` | CPU seconds of the timed section (`MB_CPU_S` after `mb_measure`) |
| `instr_retired`, `cycles`, `max_rss_kb` | retired instructions and cycles of the tool process, peak resident set (`MB_INSTR`, `MB_CYCLES`, `MB_RSS_KB`) |
| `scheme_sha256` | SHA-256 of `scheme.mfw` |
| `tool`, `tool_version`, `notes` | provenance: executable, revision, and what a "move" is for this tool |

`adapters/common.sh` provides shell helpers: `mb_task_field ID FIELD`, `mb_seed_path NAME`, `mb_measure REPORT CMD...`
(sets `MB_CPU_S`, `MB_INSTR`, `MB_CYCLES`, `MB_RSS_KB`), and `mb_json_tail` (emits the measured fields as JSON members).
`adapters/metaflip` is the reference adapter.

The harness never trusts a tool for the cost of a run: CPU time comes from the resource usage of the process, the hit from the
exactness verifier. The tool supplies moves, trace and its own diagnostics.

## 4. Records

`metabench` appends one JSON object per run to `DIR/<algo>.<variant>.jsonl` (one file per experiment and algorithm;
`/` in the algorithm name becomes `.`). Schema 1:

| field | meaning |
| --- | --- |
| `schema`, `experiment`, `algo`, `variant`, `task`, `index`, `seed` | identity; `(experiment, algo, task, seed)` is the key |
| `status` | `ok`, or `error` with `error` set (infrastructure failure; excluded from all statistics) |
| `target_rank`, `start_rank`, `budget_cpu_s` | copied from the task (the budget after `--budget-scale`) |
| `hit` | the classification used by all statistics: tool claim, verified exact, scheme rank `<= target`, and `cpu_s_total <= budget_cpu_s` |
| `tool_hit`, `exact` | the tool's claim; the verifier's verdict (`null`: no scheme, or verification disabled) |
| `best_rank` | best rank reported by the tool (`null` if unreported) |
| `cpu_s_total` | CPU seconds of the timed section (the tool process and its descendants); the whole adapter tree when the adapter reports none |
| `cpu_s_tree` | CPU seconds of the whole adapter process tree (informational) |
| `cpu_s_to_hit` | `cpu_s_total` for a hit (the tool stops at the target), else `null` |
| `wall_s_total`, `load1` | wall-clock seconds; one-minute load average at job start |
| `proposals_total`, `proposals_to_hit`, `flips_total`, `flips_to_hit`, `trace` | as in `result.json` |
| `instr_retired`, `cycles`, `max_rss_kb` | as in `result.json` |
| `scheme_sha256`, `exit_code`, `signal`, `host`, `commit`, `tool` | provenance |

Runs are executed in a seeded random order: within each task, blocks (one per seed index) are shuffled and the algorithms
inside a block are shuffled, so background load reaches all algorithms alike. The order is a function of
`--order-seed` (default: a hash of the experiment name) and independent of what has finished, so a resumed experiment
continues the same order. Records are appended with one write each; a partial last line is ignored on the next load.

## 5. Cost and budget of a run

* The cost of a run is the CPU time of the tool process: user plus system, from `wait4`, in microseconds, including process
  start-up, reading the seed and the final self-check of the result. Wall time, adapter glue and verification are not counted.
  Retired instructions and cycles come from `proc_pid_rusage` of the exited tool process (macOS).
* A run is classified after the fact by its measured CPU time: `hit` requires `cpu_s_total <= B`. A tool that overshoots `B`
  while finding the target is censored; the rule is the same for every algorithm.
* Termination is enforced in four layers: the tool's own budget check, the `mb_measure` kill at `1.05 B + 0.05` CPU seconds,
  `ulimit -t ceil(B)+2` for the adapter tree, and a wall-clock fail-safe (`5 B + 120` seconds by default; `--wall-factor`, `--wall-slack`).
  The fail-safe kills the process group; a run killed by it is recorded with `status = error`, because its CPU budget was not exhausted.
* The process tree is one process group: `kill(-pgid)` reaches every descendant.

## 6. Exactness gate

For every run with a hit claim (`--verify all`: every run with a scheme) the harness passes `scheme.mfw` to
`Verifier.exact?(bench, name, path, n, m, p)`. A backend is a row of `verifiers.tsv`: a command with `{scheme}`, `{shape}`,
`{n}`, `{m}`, `{p}`, `{bench}` that exits 0 when the scheme computes the tensor over GF(2); exit status 1 with `not_exact_marker`
in its output is the verdict "not exact"; anything else means the verifier could not decide (the run is recorded as an error).
The default backend is the dense Ruby oracle `tools/verify_tensor.rb`, independent of the searcher; select another with
`--verifier NAME` once a native port is listed. A hit whose scheme fails verification is recorded with `exact = false`
and does not count. The harness also requires the scheme's own rank to be `<= r*`. Such records must not occur.

## 7. Metrics

Per algorithm and task, with N runs, `k` hits, budget `B`, hit time `T_i` (CPU seconds), censored runs `T_i = infinity`:

1. **Success rate** `p = k/N` with the Wilson 95% score interval `(p + z^2/2N +- z sqrt(p(1-p)/N + z^2/4N^2)) / (1 + z^2/N)`, `z = 1.959963984540054`.
2. **ERT** (expected running time with restarts): `ERT = sum_i c_i / k`, infinite for `k = 0`, on four cost axes.
   CPU seconds: `c_i = T_i` for a hit and `B` for a censored run. Retired instructions, proposals, flips: `c_i` is the value at the hit
   for a hit (`instr_retired`, `proposals_to_hit`, `flips_to_hit`) and the total the tool reports for a censored run; an axis is undefined when some run lacks it.
   The 95% interval is the percentile bootstrap: `R` resamples of the N runs with replacement (default `R = 2000`,
   `--reps`), interval `[sorted[k], sorted[R-1-k]]` with `k = floor(R/40)`; replicates without a hit are infinite.
   The random generator is the 63-bit LCG of the walker, `s <- 6364136223846793005 s + 1442695040888963407 (mod 2^63)`,
   output `(s >> 32) & 0x7fffffff`, range reduction `(x * n) >> 31`. Each stream is seeded with FNV-1a (64 bit, folded to 62 bits)
   of `task TAB algorithm TAB axis`.
3. **Kaplan-Meier** estimate `S(t) = prod_{t_j <= t} (1 - d_j/n_j)` of the time to target, with censoring at `B` (a censoring at the time of an event
   stays in the risk set); `T_q = min { t : S(t) <= 1 - q/100 }` for q = 25, 50, 75 (undefined when the curve stays above).
4. **Descent profile**: `rank_i(t)` is the best rank of run `i` at CPU time `t` (from the trace; `r_0` before the first
   entry; a hit run without a final trace entry ends at `r*` at its hit time). Reported: median and quartiles over runs
   (linear interpolation between order statistics) at 49 log-spaced times over the last three decades before `B`
   (`t_g = B 10^(-3 + 3g/48)`), and **AUC** `= mean_i (1/ln 1000) integral_{B/1000}^{B} (rank_i(t) - r*) / (r_0 - r*) d ln t`
   (integrated exactly over the trace), lower is better (0: at the target from `B/1000` on; 1: never leaves the start).
5. **Throughput** in proposals and in accepted flips per CPU second (`sum counts / sum cpu_s_total` over the runs that report the count),
   and the cost to target on each axis; implementation speed and algorithmic efficiency are reported separately.
6. **Across tasks**: the Dolan-More performance profile on the CPU ERT, `rho_A(tau) = |{tasks : ERT_A <= tau min_B ERT_B}| / |tasks|`
   (tasks that nobody solves are left out; unsolved tasks count as infinite), the solved fraction, and the geometric mean of ERT ratios against a
   reference algorithm over the tasks both solve.
7. **Comparison of two algorithms** on one task: the ERT ratio `ERT_A / ERT_ref` (CPU axis) and the success-rate difference `p_A - p_ref`, both
   with 95% percentile bootstrap intervals in which the two arms are resampled independently (arms that share nonces share a trajectory prefix only
   until the switch changes the walk, so no pairing is assumed). A replicate ratio is `+infinity` when only A has no hit, `0` when only the
   reference has none, and dropped when neither has a hit; the interval uses the kept replicates and the count is reported.

`metascore summary --in DIR` writes, next to the printed tables:

* `--tsv FILE`: one row per (task, algorithm) with full-precision columns
  `task algo runs hits success success_lo success_hi ert_cpu_s ert_cpu_lo ert_cpu_hi ert_instr ert_proposals ert_flips t25_s t50_s t75_s proposals_per_s flips_per_s auc`.
* `--md FILE`: the same tables in Markdown.
* `--latex DIR`: booktabs `tabular` fragments to `\input`: `summary.tex` (all tasks, `\midrule` between tasks) and `summary_<task>.tex`
  (algorithm, N, hits, success rate with its Wilson interval, ERT in CPU seconds with its bootstrap interval, ERT in Mflips and Mproposals, Kaplan-Meier `T_50`,
  Mflips per CPU second), and `ablation.tex` (each algorithm against the reference: hits of both, success-rate difference in percentage points, ERT ratio,
  each with its 95% interval). Numbers are in math mode with `{,}` thousands separators; the `summary_<task>` name replaces `@` by `_at_`.
* `--data DIR`: pgfplots data files with a header line of column names: `descent_<algo>_<task>.dat` (`t median q25 q75`, rank against CPU seconds),
  `survival_<algo>_<task>.dat` (`t survival`, a step function for `const plot`), `profile_<algo>.dat` (`tau rho`, the performance profile as a step function).
  `<algo>` has `/` replaced by `.`.

Every number is a function of the JSONL files and of `--reps`: `metascore summary --in DIR` reproduces the tables.

## 8. The metaflip algorithms and the walker switches

`metaflip/V0` is the wide directed walker as the record hunt ran it. `tools/wide_rect_walk.w` exposes its ablation switches; every default equals the
campaign behaviour, and a run without options is byte-identical to the walker before the switches existed (`PORT-REPORT-eval.md` lists the evidence).

| switch | values | default | effect |
| --- | --- | --- | --- |
| `--proposal` | `directed`, `uniform` | `directed` | legal-bucket proposals (a uniform legal bucket, a member, an equal-factor partner), or a uniform term, position and partner as the packed fleet walker draws them; a draw without a partner is a void proposal |
| `--guard` | `nonbacktracking`, `none`, `tabu` | `nonbacktracking` | reject a proposal that returns to the current or previous state; no guard; also reject a hit in a direct-mapped history (`--history N`, a power of two, default 4096) |
| `--split-period` | `P >= 0` | `2000` | rank-raising split every `P` proposals (0: never) |
| `--split-stall` | `R >= 0` | `256` | split, and forget the history, after `R` consecutive rejections (0: never) |
| `--split-no-pair` | `on`, `off` | `on` | split when no legal pair exists |
| `--slack` | `K >= 0` | `8` | a split needs rank `< best + K` (0: never split) |
| `--restart` | `X >= 0` | `0` | restart from the seed every `X` proposals, keeping the random stream and the best scheme (0: one walk) |
| `--target` | `R` | none | stop as soon as the best rank is `<= R` |
| `--trace` | flag | off | print `TRACE rank= proposals= flips= cpu_ms=` at each new best rank |
| `--json` | flag | off | print a one-line JSON summary (rank, proposals, flips, CPU, SHA-256, switches) |
| `--cpu-budget` | seconds | none | stop when the process has used that much CPU (`STEPS` may be `unlimited`) |

`proposals` counts attempted moves (the campaign's unit); `flips` counts accepted ones (edges traversed in the flip graph, the unit of the flip-graph
literature). The uniform proposal distribution with `--guard none --split-stall 0 --split-no-pair off` makes the same decisions as the packed
fleet walker `ffws_work`, bit for bit (`spec/bench_walker_test.w`); with the default guard and triggers it isolates the proposal distribution alone.

Variants in `algos.tsv` (one factor at a time from `V0`): `uniform`; `guard-none`, `guard-tabu`; `split-p500`, `split-p8000` (period);
`split-nopair` (only when no legal pair exists), `split-nostall` (without the 256-rejection trigger), `split-never`; `slack-0`, `slack-2`, `slack-4`, `slack-16`;
`restart-100k`, `restart-1M`.

## 9. Commands

The tools compile on first use (about 30 s) into `$MB_BUILD` (default `~/.tungsten/metaflip/bench-bin`) with the compiler `$TUNGSTEN` (else `tungsten` on the `PATH`):

```
bench/metabench list                       tasks, algorithms, seeds
bench/metabench validate                   consistency of the tables (seed hashes, targets below starts, adapter placeholders)
bench/metabench run --experiment NAME --algo A[,A2] --tasks tier1|tier2|tier3|tier4|all|ID[,ID] --n N --jobs J
                 [--budget-scale X] [--out DIR] [--verifier NAME] [--verify hits|all|none] [--order-seed S]
                 [--retry-errors] [--keep-runs] [--dry-run] [--wall-factor F] [--wall-slack S] [--compiler PATH]
bench/metabench verify --scheme FILE --shape NxMxP [--verifier NAME]
bench/metabench exec [--report FILE] [--kill-after CPU_S] -- COMMAND [ARG...]
bench/metascore summary --in DIR|FILE[,...] [--experiment NAME] [--reference ALGO] [--reps R] [--unverified]
                 [--tsv FILE] [--md FILE] [--latex DIR] [--data DIR] [--points G] [--decades D]
```

`--out` defaults to `~/.tungsten/metaflip/experiments/record-hunt-20260926/work/eval/NAME/`; it holds `<algo>.<variant>.jsonl`, `schemes/` (the scheme of every hit),
`bin/` (the walker, built once per source state), `runs/` (scratch directories, removed after a clean run unless `--keep-runs`) and `invocations.log`.
Runs are resumable: a finished `(experiment, algo, task, seed)` row is skipped on the next invocation; `--n` may grow between invocations.
`--jobs` is the number of concurrent runs (default 4). Hits count in `metascore` only when the verifier approved them (`--unverified` also counts hits without a verdict).
Running the `.w` files with `bin/tungsten FILE ...` needs a bare `--` before the options; the launchers avoid that.

Reproduce a table from the raw records:

```
bench/metabench run --experiment pilot-tier1 --algo metaflip/V0 --tasks tier1 --n 20 --jobs 4
bench/metascore summary --in ~/.tungsten/metaflip/experiments/record-hunt-20260926/work/eval/pilot-tier1 \
    --tsv bench/summaries/pilot-tier1.tsv --md bench/summaries/pilot-tier1.md
```

## 10. The suite and its calibration

Budgets of tier 1 come from a pilot of `metaflip/V0` (20 seeds per task, `pilot-20260930`): a budget is at least ten times the pilot median and at least twice the pilot maximum, rounded. `N` is the planned number of seeds.

| task | target | pilot hits | median CPU s | max CPU s | budget CPU s | N |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 3x3x3 | 23 | 20 of 20 | 0.018 | 0.040 | 1 | 100 |
| 2x3x4 | 20 | 20 of 20 | 0.037 | 0.111 | 2 | 100 |
| 2x4x4 | 26 | 20 of 20 | 0.57 | 1.46 | 10 | 100 |
| 3x3x4 | 29 | 18 of 20 (5 s budget) | 2.4 | 5.0 | 30 | 60 |
| 3x3x5 | 36 | 20 of 20 | 1.8 | 12.8 | 60 | 60 |
| 2x3x5 | 25 | 20 of 20 | 5.2 | 29.7 | 120 | 60 |

These six tasks are the **ablation suite** (`--tasks 2x3x4,2x4x4,3x3x3,3x3x4,3x3x5,2x3x5`). The tasks 2x2x3, 2x2x4 and 2x3x3 are solved in milliseconds (20 of 20 pilot hits, median at most 0.01 s) and serve as smoke tests;
2x4x5 has a median of 187 s (10 of 12 pilot runs hit within 800 s) and is kept as a long task; tiers 2 and 3 (from 3x4x4 on) and the improvement tasks of tier 4 keep the placeholder budgets marked `uncalibrated`.
Comparisons with the prior programs on the three hardest tasks use `--budget-scale 5` and 30 seeds, because the prior programs need more time there; budgets are identical for all algorithms of one experiment.

## 11. Extending

* **A task**: add a row to `tasks.tsv` (a fresh `seed_base`, leaving room for `runs` seeds) and, for a named start, a row and a file to `seeds.tsv`;
  `bench/metabench validate` checks the tables.
* **An algorithm**: write an adapter following section 3 (start from `adapters/metaflip`), add a row to `algos.tsv`. Adapters for external tools change nothing in
  the tool's search logic; instrumentation patches (stop at the target, report best-rank events with move counts) are kept as small diffs next to the adapter.
  Report every difference in the problem statement (coefficient ring and lifting, start scheme, reduction checks, restart rules, path lengths, what a move is).
* **A verifier**: add a row to `verifiers.tsv` and select it with `--verifier`.

## 12. Tests

`spec/bench_stats_test.w` (statistics against the independent Python reference, `spec/bench_stats_reference.py`, fixture `spec/fixtures/bench/stats_cases.tsv`),
`spec/bench_score_test.w`, `spec/bench_record_test.w`, `spec/bench_exec_test.w`, `spec/bench_walker_test.w`, `spec/bench_runner_test.w` (end to end with a fake adapter).
