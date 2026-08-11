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
  `xctrace export` and an XML collapse into folded stacks. The default mode
  reads the `kdebug-counters-with-time-sample` table (cumulative per-core
  counter snapshots, differenced between consecutive samples); `--counters`
  reads the `counters-profile` table, whose rows are **per-thread interval
  deltas** already differenced by Instruments at context-switch boundaries —
  each row's counts belong to that row's thread and stack, with no
  cross-thread double counting and no bleed-in from other processes.

Tungsten frames symbolize twice: `atos` maps addresses to symbols, and the
compiler-written sidemap (`<binary>.sidemap`, mapping deduplicated
`__wy_<hash>` bodies back to `Class#method` names) rewrites the folded text
itself, so every view — terminal, SVG, speedscope — shows real names.

## Counter mode (`--counters [SET]`, macOS)

Counter sets (each is a bundled tracetemplate; slot order = event order):

| set     | events |
|---------|--------|
| `rates` (default) | INST_ALL, CORE_ACTIVE_CYCLE, L1D_CACHE_MISS_LD, L1D_CACHE_MISS_ST, PL2_CACHE_MISS_LD, LD_SRC_MEMSYS_NONSPEC, L1D_TLB_MISS, L2_TLB_MISS_DATA |
| `cache` | INST_BRANCH, BRANCH_MISPRED_NONSPEC, L1D_CACHE_MISS_LD_NONSPEC, L1I_CACHE_MISS_DEMAND, PL2_CACHE_MISS_LD, L1D_TLB_MISS_NONSPEC, L1I_TLB_MISS_DEMAND, L2_TLB_MISS_DATA |
| `stalls` | ARM_STALL_FRONTEND, ARM_STALL_BACKEND, L2_TLB_MISS_INSTRUCTION |

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
  the kernel never time-multiplexes event sets.
- Event availability is per-chip (`/usr/share/kpep/*.plist`); the bundled
  sets are validated on M5 (as5-1) and use events present on M1-family
  and later.

## Regenerating the templates

`lib/xctrace/generate-templates.py` rebuilds the sibling
`.tracetemplate` files from `flame-counters.tracetemplate` (the
human-authored base) by swapping the PMC event list embedded in the
template's counters configuration:

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
