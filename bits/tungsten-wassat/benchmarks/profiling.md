# Profiling Wassat

Use a frozen `--release` binary and record its source and compiler hashes.
For table-free runs, set `WASSAT_BACKDOOR_TABLES=0`.

For engine-only comparisons, build `prop_bench.w` with `--release` and use
`engine_pairs.py`. Its JSON manifest contains records such as
`{"name":"dense", "path":"/path/input.cnf", "conflicts":20000, "mode":"raw"}`.
It alternates binaries within each repetition, strips ambient `WASSAT_*`
settings, retains every run, and records binary/input hashes. `same_search`
requires identical verdict and search counters across both binaries and all
repetitions; a false value means timing includes a trajectory change.
Optional `seconds` and `ticks` fields set the benchmark's search limits
(`ticks` is in millions). The harness's `--timeout` bounds the entire child,
including parsing and loading; a timeout is saved before the harness fails.
Check each version's statuses and `all_solved`: a time ratio between a
completed solve and a capped UNKNOWN run is not a speed comparison.

```sh
python3 bits/tungsten-wassat/benchmarks/engine_pairs.py /tmp/corpus.json \
  --baseline /tmp/prop-before --candidate /tmp/prop-after \
  --reps 5 --out /tmp/engine-pairs.json
```

To isolate automatic dense-watch sizing in one binary, use that binary for
both arguments and add `--baseline-env WASSAT_WATCH_EXTRA=0`. This restores
the prior watch capacity on ordinary small/medium raw solvers; the Kissat
profile already reserves the larger pool. An explicit `WASSAT_WATCH_EXTRA`
percentage replaces automatic dense sizing. These are diagnostic controls,
not additional public solver modes. Run correctness/model/proof checks
separately: a fixed-budget timing run is not a proof of an UNSAT verdict.

`prop_bench.w` also accepts `WASSAT_BENCH_SAVED_POS=0/1` to isolate saved
clause-scan positions, independently of the other Kissat-profile settings.
Pass it through `--baseline-env` / `--candidate-env` with the same binary.
This is a benchmark fixture intervention only. It changes watch selection
and can dramatically change time to a verdict even when individual scans
get cheaper, so include fresh complete-solve cases as well as bounded runs.

For certificate formatting, `proof_bench.w` runs one raw solver and includes
sink flushes in `solve_us`. Its arguments are `input.cnf conflicts
wrat|dual|drat output-prefix [native|text]`. Build with `--release`, alternate
`native` and `text` runs of the same binary, and compare both search counters
and proof-file hashes. `text` restores the former WRAT formatting path in the
benchmark fixture; DRAT-only retains byte formatting in both modes as a
control. Parsing, loading, buffer allocation, and SAT model checking are
outside the timed interval. SAT models are checked against the original CNF.
The benchmark intentionally keeps partial SAT/UNKNOWN streams for comparison;
only independently checked, completed UNSAT streams are certificates. Use
the production CLI for normal proof publication and cleanup.

Build diagnostics:

```sh
TUNGSTEN_ALLOC_PROFILE=1 bin/tungsten -o /path/to/wassat-profile \
  --release --ast-stats bits/tungsten-wassat/bin/wassat.w
```

`--ast-stats` is a compiler flag. Save its `KINDCOUNT` lines once per build;
they count nodes in the loaded program parse tree, not CNF literals. Build-time
`TALLOC` lines describe the compiler process. Use a fresh `TUNGSTEN_CACHE_DIR`
when collecting build statistics and check that the output contains counts.

Solver diagnostics:

```sh
WASSAT_BACKDOOR_TABLES=0 WASSAT_PROFILE=1 \
  TUNGSTEN_ALLOC_PROFILE=1 TUNGSTEN_POOL_STATS=1 \
  /path/to/wassat-profile instance.cnf --fast
```

`WASSAT_PROFILE=1` writes phase times and per-arm counters to stderr after
workers join. Replaced arms are reported before their solver objects are
discarded. The reports include:

- Conflicts, decisions, propagated trail literals, restarts, database
  reductions, and live learned clauses.
- Phase snapshots, copied trail literals, and unchanged literals skipped;
  decision-spine snapshots, scanned levels, and unchanged levels skipped.
- Watch-pool rebuilds and rebuilt entries, block relocations and copied
  entries, pool-exhaustion events, and current pool usage/capacity.
- Clause-sharing exports, imports, drops and filtered clauses; shrinking and
  on-the-fly strengthening work; clause-arena usage/capacity.
- The existing SLS flip/repair counts and specialist-specific profile output.
- Exact circuit evaluation batches, represented input assignments, and
  word-level gate evaluations, attributed to XOR, AND, majority, selector,
  and generic fallback operations. Each word evaluates 64 assignments. The
  Gray-code counters include completed prefixes when a worker stops early;
  `complete=1` means exhaustive evaluation found no satisfying assignment.

Congruence timers include scratch preparation, extraction, and insertion of
new binary clauses. The substitution timer includes SCC discovery, rewriting,
watch repair, and enqueueing derived units when a rewrite occurs. These clocks
have millisecond resolution, so a small pass can legitimately report `0ms`.

Inprocessing reports include per-round changes in forced units, failed probes,
lifted literals, equivalences, vivified/subsumed/strengthened clauses, and
watch rebuilds. Parked substituted variables are excluded from forced-unit
counts. `inprocess_work` gives cumulative cancellations, SCC work, charged
subsumption scan work, and cleaned literals. Subsumption candidate visits are
budgeted separately from index construction; length-based scan charges can
exceed the number of words inspected before an early exit. These counters
are work measures, not wall-time limits.

`race.stop answer_to_last_arm_ms` is the difference between the earliest
winning worker completion timestamp and the last worker completion timestamp,
reported after joins. It has millisecond resolution and measures the worker
completion tail, not the whole process exit latency. Cancellation checks run
at safe boundaries: unfinished probes are discarded, while a started clause
rewrite or required watch repair finishes before return.

For a controlled maintenance-only cancellation test, build
`benchmarks/inprocess_cancel_bench.w` with `--release`, then pass an input CNF,
pass mask, delay in milliseconds, and arm count. A delay of `-1` measures
uninterrupted work; a nonnegative delay publishes a synthetic win after the
start barrier. `tail_us` ends at maintenance return, before fingerprinting.
It must not be presented as a full-solve timing.

Counters are cumulative for each solver object, including input loading and
earlier scout slices. A scout and its continuation are snapshots of the same
work: do not add them together. `propagated` counts dequeued trail literals,
including retries after pool exhaustion; it is not a count of examined watch
entries. Rebuilt/copied entries count writes into the watch pool, not bytes.
The new pool counters use native integers owned by each arm and update only
on maintenance paths, with no atomics or per-literal instrumentation.

Phase and spine counters also use native integers in the existing per-arm
state buffer. Snapshot reuse extends only an uninterrupted descent; conflicts,
restarts, reductions, phase changes, and speculative lookahead invalidate the
saved prefixes. Skipped counts measure work the full-copy implementation would
have repeated, not allocations or bytes freed.

An arm's `ms` describes its latest search slice; `race_ms` sums the timed race
calls across rounds (including rendering for preprocessing arms). Arithmetic
node counts are emitted for every recognized attempt, including a search
that reaches its node limit without a verdict.
Circuit gate work is derived from completed batch ranges and cone lengths
after workers join, without adding counting operations inside gate loops.
The opcode totals partition this same work; they count gate evaluations,
not the individual bitwise operations or clause scans inside each gate.

`circuit.kernel` attributes repeated Gray-update word evaluations to the
normalized kernels (including NAND, bit-clear, OR-not, OR, and NOR). It excludes
the first full-graph batch per worker, which remains in `circuit.ops`. These
are word-gate evaluations, not hardware instruction counts.

`analysis mark_bytes` reports the byte payload of the per-variable analysis
mark table. The table holds only marks 0 through 4 and uses one byte per
variable across minimization, shrinking, assumption cores, and proof hints.
`analysis reason_bytes` reports the signed 32-bit reason array payload,
including the unused variable-zero slot. Clause indices already occupy a
signed i32 cell in compact headers and a signed high word in packed binary
entries; insertion and flat loading reject indices outside that range. The -1
sentinel remains signed, and global proof IDs retain their 64-bit storage.

`analysis arena_used` and `arena_capacity` use logical cells: n literals plus
one header per record, preserving the learning/compaction budget from the
previous i64 representation. `arena_cells` is the physical i32 cursor: n
literals plus two header cells per record. Allocated backing has
`arena_capacity + clause_capacity` i32 cells, so changing clause-table capacity
also reserves header space. Compaction copied-cell counters count physical
cells, not bytes; use the element width when comparing representations.

`phases payload_bytes` sums the saved, target, and best phase tables plus
allocated probing and vivification phase backups. These polarity buffers use
one signed byte per variable for values -1, 0, and 1.

Runtime `TALLOC` lines count five instrumented allocation categories: BigInt
arenas, new arrays, aligned arrays, array growth, and hashes. Byte totals are
instrumentation estimates, not peak memory or all malloc traffic: some array
constructors account for eight bytes per element regardless of element width,
and the hash counter accounts for the header without its backing storage. The dump
runs at normal process exit and is unavailable after SIGKILL. For a timed-out
case, a separately labelled finite `--conflicts` prefix can provide counters;
do not report missing counters as zero.

`TUNGSTEN_POOL_STATS=1` reports hits, misses and drops for instrumented
recycle pools, including automatically recycled eligible object shells.
It does not fully count ordinary empty-array pool pops, per-site `## reuse`
slots or the uninitialized-array parking slot. Zero counters alone therefore
do not prove that every allocation is fresh. Record these alongside source
and generated-code inspection. Per-arm buffers retained across conflicts
are manual storage reuse even when they never enter a runtime pool.

Keep sampled/allocation-instrumented diagnostics separate from speed tests.
Compare matched release binaries serially with `TUNGSTEN_ALLOC_PROFILE=0` and
`TUNGSTEN_POOL_STATS=0`, check SAT models against every original clause, and
retain repeated timings and both binaries. An UNSAT verdict needs its own
proof or clearly labelled published-result agreement.
