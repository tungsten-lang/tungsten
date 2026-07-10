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
