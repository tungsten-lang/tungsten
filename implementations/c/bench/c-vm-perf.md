# C VM perf ledger

Median and minimum timings for the same native, `-O0`-linked stage-1
self-compile used by `bin/tungsten build`:

```text
tungsten-c compiler/tungsten.w compile compiler/tungsten.w --out <fresh> \
  --native --runtime <content-addressed-runtime.a> --no-lto
```

`bench/c-vm-perf.sh` prepares the production stage0/runtime identity first and
uses fresh output and LLVM paths for every sample, so freshness checks cannot
turn later samples into no-ops. User time, cycles, and RSS below come from the
minimum-wallclock sample.

| date | label | wallclock | user | cycles | peak RSS |
|------|-------|-----------|------|--------|----------|
| 2026-07-11 | raw-tag equality, cached fast-mode dispatch, packed saved locals (N=3) | median 9.29s / min 9.22s | 8.57s | 29.54G | 2214 MB |

Direct production-path measurements before this optimization were about
9.4–10.1 seconds wallclock and 9.55 seconds of user CPU. Those runs predated
the repaired median/minimum ledger, so treat the comparison as directional;
the current row is the reproducible reference going forward.

## Earlier rows (deprecated)

These historical rows used older harnesses that either stopped after
parse/lowering or did not reproduce the current native stage-1 link. They are
retained as implementation history but are not comparable with the row above.

| date | label | wallclock | cycles | peak RSS |
|------|-------|-----------|--------|----------|
| 2026-05-07 01:40 | baseline (df87d56 + GC on) | 2.30s | 9.28G | 880 MB |
| 2026-05-07 01:40 | C1 GC-disabled default + bench harness | 2.01s | 8.08G | 1262 MB |
| 2026-05-07 02:02 | C2 foundation complete (helpers migration) | 1.97s | 8.08G | 1263 MB |
| 2026-05-07 02:05 | C3 precursor — 16B alignment | 1.93s | 8.08G | 1291 MB |
| 2026-05-07 02:30 | C3 precursor — `TcValue = WValue` | 0.24s | 0.83G | 329 MB |
| 2026-05-07 02:34 | C5 cleanup | 0.25s | 0.82G | 329 MB |
| 2026-05-07 02:50 | post-flip historical harness | 1.46s | 0.83G | 329 MB |
| 2026-05-07 04:16 | C9 runtime cache + `--no-lto` experiment | 0.44s | 0.83G | 329 MB |
