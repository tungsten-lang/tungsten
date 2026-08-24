# tungsten-flame

Flame-graph profiler for Tungsten programs and arbitrary processes.

```
bin/tungsten flame file.w                 # compile with frame pointers, profile, report
bin/tungsten flame -- ./bin/some-binary   # profile an external command
bin/tungsten flame --counters file.w      # PMC counter mode (macOS): IPC + miss rates
```

## How it samples

- **Linux** — `perf record -g --call-graph fp`, collapsed via `perf script`.
- **macOS** — `xctrace record` with a bundled Instruments tracetemplate that
  programs Apple Silicon PMC events (`lib/xctrace/*.tracetemplate`), then
  `xctrace export` and an XML collapse into folded stacks. Sampling is
  PMI-driven (every 250K occurrences of the template's first event) rather
  than wall-timer: ~1ms timer windows span whole phase cycles of the
  profiled program and smear every metric toward the time distribution.
  The default mode reads the `kdebug-counters-with-pmi-sample` table
  (cumulative per-core counter snapshots, differenced between consecutive
  samples on the same core); `--counters` reads the `counters-profile`
  table, whose rows are **per-thread interval deltas** already differenced
  by Instruments at context-switch boundaries — each row's counts belong to
  that row's thread and stack, with no cross-thread double counting and no
  bleed-in from other processes. PMI sampling exports ~50-100K XML rows/s
  per busy core, so PMC recordings are capped at 3s (the rates converge
  within a couple of seconds). When the trace carries no counters table
  (Developer mode off — `sudo DevToolsSecurity -enable` — or an event the
  chip lacks), the sampler falls back to the stock Time Profiler template:
  stacks only, no PMC metrics.

Tungsten frames symbolize twice: `atos` maps addresses to symbols, and the
compiler-written sidemap (`<binary>.sidemap`, mapping deduplicated
`__wy_<hash>` bodies back to `Class#method` names) rewrites the folded text
itself, so every view — terminal, SVG, speedscope — shows real names.

## Counter mode (`--counters [SET]`, macOS)

Counter sets (each is a bundled tracetemplate; slot order = event order).
Event names differ per chip generation, so each metric has candidates in
preference order and the generator keeps the first one the host's kpep
defines (the one actually recorded is in the template's `.events`
manifest); a metric with no event on the chip drops its slot:

| set     | metrics (candidate events) |
|---------|--------|
| `rates` (default) | instructions (INST_ALL), cycles (CORE_ACTIVE_CYCLE), L1-dcache-load-misses (L1D_CACHE_MISS_LD), L1-dcache-store-misses (L1D_CACHE_MISS_ST), LLC-load-misses (PL2_CACHE_MISS_LD, else MMU_TABLE_WALK_DATA), memsys-loads (LD_SRC_MEMSYS_NONSPEC), dTLB-misses (L1D_TLB_MISS), L2-TLB-data-misses (L2_TLB_MISS_DATA) |
| `cache` | branches (INST_BRANCH), branch-misses (BRANCH_MISPRED_NONSPEC, else ARM_BR_MIS_PRED), L1-dcache-load-misses (L1D_CACHE_MISS_LD_NONSPEC, else L1D_CACHE_MISS_LD), L1-icache-misses (L1I_CACHE_MISS_DEMAND), LLC-load-misses (PL2_CACHE_MISS_LD, else MMU_TABLE_WALK_DATA), dTLB-misses (L1D_TLB_MISS_NONSPEC, else L1D_TLB_MISS), iTLB-misses (L1I_TLB_MISS_DEMAND), L2-TLB-data-misses (L2_TLB_MISS_DATA) |
| `stalls` | frontend-stall-cycles (ARM_STALL_FRONTEND, else MAP_DISPATCH_BUBBLE), backend-stall-cycles (ARM_STALL_BACKEND, else MAP_STALL), L2-TLB-instr-misses (L2_TLB_MISS_INSTRUCTION) |

The `rates` set records instructions and cycles **next to** the miss events,
attributed to the same stacks, which is what makes normalized output
possible: the run closes with a per-function table of IPC and
misses-per-kilo-instruction (MPKI) — raw counts say where events happened,
rates say which code is cache-hostile independent of how hot it is.

Example — profile a bignum multiply benchmark:

```
$ bin/tungsten flame --counters -d 10 -- \
    benchmarks/big_math/bench_big_math --bench-tungsten-sweep mul 1024 3 2000

  Top Functions (cycles)     ...per-metric sections...

  Counter rates (per function, self counts)
  function                              inst%    IPC  L1d-ld/KI  L1d-st/KI ...
  __w_bn_mul_toom2                       41.2   6.71       3.10       2.84
  ...
  (all sampled)                         100.0   5.60       3.89       3.49
```

Notes:

- Counter deltas are attributed to sampled stacks; totals are a sampled
  subset of the process's execution (steady-state kernels dominate, so
  rates are representative; absolute totals are not the point).
- The templates stay inside Apple Silicon's 8-configurable-PMC budget, so
  the kernel never time-multiplexes event sets: events carry a
  `counters_mask` restricting which physical counters they may occupy, and
  the generator schedules them scarcest-first, falling through to a
  metric's next candidate when its first one cannot fit.
- Event availability is per-chip (`/usr/share/kpep/*.plist`); the
  generator reads the host chip's table, so the checked-in templates
  record whatever the machine they were generated on supports (currently
  as3 / M3: no PL2_*, LD_SRC_MEMSYS_* or ARM_STALL_* events). Regenerate
  on a different chip to pick up its events.
- Recordings are capped at 3s (see "How it samples").

## Regenerating the templates

`lib/xctrace/generate-templates.py` rebuilds the `.tracetemplate` files
(including `flame-counters.tracetemplate` itself, the human-authored base
whose outer structure is preserved) by swapping the PMC event list embedded
in the template's counters configuration, and writes a sibling `.events`
manifest per template — one `label<TAB>event` line per slot, in slot order —
which `Sampler.counter_labels` reads at runtime so the reported metric
labels always match the template's slots:

```
/usr/bin/python3 bits/tungsten-flame/lib/xctrace/generate-templates.py
```

Add a new set there (and to `Sampler.counter_set_info`) to record a
different event mix.

## Other modes

Pure folded-text transforms (no profiling): `--diff`, `--hot`,
`--collapse-sample`, `--collapse-dtrace`, `--trace-event`, `--grep`,
`--prune`, `--subtree`, `--threshold`, `--rewrite`, `--split`, `--root`,
`--collapse-recursion`. Exports: `-o` (SVG), `--speedscope`. See
`man/flame.5.wd` for the full option list.

## Tests

```
bin/tungsten bits/tungsten-flame/spec/parsing_spec.w
bin/tungsten bits/tungsten-flame/spec/counter_rates_spec.w
```
