# Profiling Wassat

Use a frozen `--release` binary and record its source and compiler hashes.
For table-free runs, set `WASSAT_BACKDOOR_TABLES=0`.

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
