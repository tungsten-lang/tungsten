# C VM perf ledger

Best-of-N timings for `tungsten-c compile compiler/tungsten.w --out … --release`,
i.e. the same stage-1 invocation `bin/tungsten build` runs. Captured by
`bench/c-vm-perf.sh`. Numbers should track the `built  stage1 <ms>` line in
build output.

`cycles elapsed` from `/usr/bin/time -l` is parent-process only; child clang
invocations (codegen + link) don't roll up. So wallclock and user time
include the children but cycles doesn't, which is why the ratios diverge.

| date | label | wallclock | user | cycles | peak RSS |
|------|-------|-----------|------|--------|----------|
| 2026-05-07 02:50 | post-flip current (corrected harness, best of 15) | 1.46s | 1.34s | 0.83G | 329 MB |

## Earlier rows (deprecated)

The rows below ran from `implementations/c/` with no `--out`/`--release`,
so the compiler bailed at the `resolve_runtime_dir` ccall after only
parsing + lowering. Wallclock undercounted by ~6× vs the build path
because no clang children ran. Kept for historical reference; do not
compare to the corrected row above.

| date | label | wallclock | cycles | peak RSS |
|------|-------|-----------|--------|----------|
| 2026-05-07 01:40 | baseline (df87d56 + GC on) | 2.30s | 9.28G | 880 MB |
| 2026-05-07 01:40 | C1 GC-disabled default + bench harness | 2.01s | 8.08G | 1262 MB |
| 2026-05-07 02:02 | C2 foundation complete (helpers migration) | 1.97s | 8.08G | 1263 MB |
| 2026-05-07 02:05 | C3 precursor — 16B alignment | 1.93s | 8.08G | 1291 MB |
| 2026-05-07 02:30 | C3 typedef flip — TcValue = WValue (NaN-boxed uint64_t) | 0.24s | 0.83G | 329 MB |
| 2026-05-07 02:34 | C5 cleanup (post-flip) | 0.25s | 0.82G | 329 MB |

## What the typedef flip actually delivered

Parent-only cycles (the bytecode dispatch loop work) dropped 9.28 G →
0.83 G, an 11× win on what the C VM itself does — the figure that
matters when comparing the C VM to other interpreters. But the
user-visible build time at stage 1 is dominated by the clang
sub-process, so the headline `built  stage1 <ms>` line moves much
less. Track both: bench cycles for VM-internal optimization work,
and the build's stage-1 wallclock for end-to-end user impact.
| 2026-05-07 04:16 | C9 build-runtime cache + --no-lto for stage 1/2 | 0.44s | 0.83G | 329 MB |
