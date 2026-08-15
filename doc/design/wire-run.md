# WIRE-backed `run`

`run FILE` and `-e CODE` now execute the same pipeline as a native build:

```text
source -> lexer -> parser -> lowering -> WIRE -> LLVM -> native runtime
```

The compiled compiler writes a stable per-source binary under the compiler
cache. The existing incremental manifest validates source, Core, compiler,
runtime, target, and codegen inputs, so repeated runs can reuse that binary.
Script arguments are passed through with shell-safe quoting and the child exit
status is preserved.

`--ruby` in the outer CLI (or `--interpret` when invoking the compiled compiler
directly) selects the legacy tree-walker. The REPL also retains it while its
incremental interaction model is redesigned. These are bootstrap and debugging
paths, not a second definition of product semantics.

This change deliberately does not delete `compiler/lib/interpreter.w`: the C
bootstrap, Ruby fallback, REPL, and differential tests still need it. The
parity suite names that leg explicitly so an ordinary `run` test does not
silently compare the compiled engine with itself.

## Benchmarking the transition

Use a compiler built from the branch and compare the two product entry points
on one deterministic source:

```sh
scripts/bench-wire-run.rb --compiler /path/to/tungsten-compiler
```

The harness first uses a different source to prime the native runtime archive.
It then reports this program's uncached WIRE lower/link time separately from
cache-hit `run`, checks exact stdout parity with `--interpret`, and collects at
least nine alternating warm samples per mode. This avoids presenting compiler
startup, first-ever runtime construction, and steady-state execution as one
number.
