# Spec Layout

Runnable Tungsten specs use the `*_spec.w` suffix. Keep files self-checking:
they should print failures clearly and exit nonzero when a guarded behavior
breaks.

- `compiler/` - compiler and lowering regressions.
- `core/` - core runtime and standard-library regressions. `metal_*_spec.w`
  specs require Apple Metal and are opt-in in the shell runner.
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
