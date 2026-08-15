# WIRE-backed `run`

`run FILE` and `-e CODE` now execute the same pipeline as a native build:

```text
source -> lexer -> parser -> lowering -> WIRE -> LLVM -> native runtime
```

The compiled compiler writes a stable per-source binary under the compiler
cache. The existing incremental manifest validates source, Core, compiler,
runtime, target, and codegen inputs, so repeated runs can reuse that binary.

Concurrency and process mechanics:

- Builds are serialized per cache binary by a mkdir lock and land in a
  sibling `.stage` file, then rename onto the final name. A rename swaps the
  directory entry, so an already-running instance keeps its old inode — a
  concurrent `run` of the same script can never truncate a binary that is
  executing (an in-place rewrite is a SIGKILL on macOS via code-sign
  invalidation).
- A warm run never rewrites the published binary: when the incremental
  manifest is current and the sibling `.id` stamp matches, the existing
  inode is exec'd as-is. macOS validates a binary's code signature on the
  first exec of fresh file content (~200ms); an already-validated inode
  re-execs in ~4ms, so skipping the install is what keeps warm runs fast.
- The child is spawned directly from argv (`__w_run_argv`, mirrored in the
  stage-0 VM): no shell, no quoting, no job-control chatter on stderr. Its
  exact exit code is preserved; a signal death maps to the shell convention
  128+signal. The child inherits the process group, so Ctrl-C behaves like
  the old in-process interpreter.
- `-e` diagnostics report `(eval)`: the materialized cache file keeps its
  real path for reading and cache identity, but the path handed to lowering
  (and so embedded in runtime error output) is aliased.
- Each `run` kicks the shared cache GC (`bin/commands/cache_gc.sh`, daily,
  age-based) in the background, so run-cache binaries and eval sources stay
  bounded even for users who never `build`. `bin/tungsten cleanup` forces a
  sweep immediately.

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
