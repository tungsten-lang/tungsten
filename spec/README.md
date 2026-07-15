# Spec Layout

Runnable Tungsten specs use the `*_spec.w` suffix. Keep files self-checking:
they should print failures clearly and exit nonzero when a guarded behavior
breaks.

- `compiler/` - compiler and lowering regressions. Includes emit-only GPU
  dialect checks (e.g. `gpu_cuda_emit_spec.w`), which need no hardware.
- `core/` - language, core runtime, and standard-library regressions.
  Language smoke specs (`basics_`, `control_flow_`, `classes_`,
  `arrays_hashes_`) run in the default compiled set. Heavier runtime specs
  (ByteArray, mmap) need `RUN_CORE_SPECS=1`. `metal_*_spec.w` specs require
  Apple Metal and are opt-in in the shell runner.
- `interpreter/` - specs that must run through `bin/tungsten run`.
- `numeric/` - numeric tower and floating-point behavior specs.
- `repl/` - PTY/system specs for the compiled REPL.
- `fixtures/` - sample programs and legacy expression fixtures. These are not
  discovered as runnable specs.

Run the default self-checking set with:

```sh
make specs
```

Set `RUN_CORE_SPECS=1` to include core runtime specs, `RUN_METAL_SPECS=1` to
include Metal specs, and `RUN_REPL_SPECS=1` to include the PTY REPL scrub test.

CUDA emit (`spec/compiler/gpu_cuda_emit_spec.w`) is included in the default
set: the harness sets `TUNGSTEN_GPU_DIALECTS=cuda` at compile time and the
binary only greps the sibling `.cu` for markers (`__global__`, `threadIdx`,
…). No CUDA toolkit or GPU is required.

### Packed-token parser regression

`compiler/parser_packed_token_access_spec.w` covers both numeric forms seen by
the parser after Array storage: small packed values materialize as `Integer`,
while the signed lexical-token tag materializes as `BigInt`. It also checks
`tok_equal?` success, content mismatch, and length mismatch after one shared
numeric-to-i64 normalization.

The equality decode was retained after a clean balanced 5+5 release self-host
series on 2026-07-14. Median load+parse fell from 6.762s to 6.248s (0.924,
four of five matched-pair wins), median user CPU fell from 8.330s to 8.010s
(0.962, four of five wins), and all 12 warm/timed LLVM outputs were byte-for-
byte identical (13,523,095 bytes; SHA-256 `3a5e00f099be1a79b...`).

A second clean balanced 5+5 series moved the three decoders to top-level direct
helpers while retaining `Parser#tok_type`, `#tok_off`, and `#tok_len` as public
wrappers. Wire IR replaced 125 cached parser-method dispatch sites (117 type,
8 offset) with direct calls. Aggregate wall time was 0.949× baseline and user
CPU was 0.962×, with five of five matched-pair wins for both; aggregate total
compile time was 0.907×. Load+parse improved in four of five pairs with a 0.956
paired-median ratio. Its unpaired median reversed because the old samples had
an unusually favorable position mix, so retention used the predeclared paired
ordering plus aggregate sums rather than that noisy unpaired statistic. All 12
LLVM outputs were again byte-identical to the baseline above.
