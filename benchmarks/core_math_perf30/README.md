# Core Math Perf30 Campaign

This directory contains focused, deterministic microbenchmarks for the Core
math performance campaign. Each retained optimization is measured immediately
before and after its source change with the same compiler, flags, workload, and
correctness checksum. Timings are diagnostic local wall-clock measurements;
the durable result ledger is `results.md`.

Compile a benchmark with:

```sh
bin/tungsten -o /tmp/core-math-perf30-NAME benchmarks/core_math_perf30/NAME.w
```

Run the resulting binary repeatedly and compare its `checksum` and elapsed
milliseconds.
