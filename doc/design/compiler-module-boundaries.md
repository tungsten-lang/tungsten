# Compiler module boundaries

The self-hosted compiler is organized as thin public entry modules plus worker
compile units. This reduces the amount of source invalidated by a local change
without changing any public function or class name.

| Entry module | Worker boundary |
| --- | --- |
| `lowering/literals.w` | generated unit IDs and dimension signatures, sharded independently from literal families |
| `emitter.w` | support and declarations, artifact assembly, exact-width BigInt seams, and three per-op instruction renderer groups |
| `interpreter.w` | runtime/evaluation, C-call compatibility, expressions, dispatch, and definitions/loading |
| `parser.w` | parser core, expression grammar, and declaration grammar |
| `lexer.w` | fast packed tokenizer, literal scanners, string/array scanners, and materialization |
| `metal_emitter.w` | schedule/layout transforms, shared MSL lowering, and secondary dialects |
| `tungsten_driver.w` | CLI orchestration, IR/GPU pipeline, native link/runtime pipeline, and compile-cache pipeline |

Worker files are capped at 1,800 lines by
`compiler/test/test_module_boundaries.sh`. Generated unit registries are
sharded too, so regenerating a table does not recreate a 5,400-line compile
unit.

`compiler/tungsten.w` and `compiler/repl.w` remain the thin image launchers.
They select the minimal or interactive dependency set, then load the shared
driver orchestrator; the worker split does not pull REPL or Metal code back
into the default compiler image.

The split is source-compatible. Parser, lexer, and interpreter workers reopen
their existing classes; emitter and driver workers retain the same top-level
function names. No call site needs to know which worker owns an implementation.

## Rebase validation — 2026-09-07

Validated against local main `99a2beaa`, then rebased onto `e3807ca8` after its
bits-build-only change landed during validation. That final replay does not
change compiler, Core, or runtime sources. The split retains main's optional
image launchers, current driver implementations, and language-neutral unit
registry.
All 652 moved interpreter, lexer, parser, driver, and GPU-emitter method bodies
are unchanged apart from ordinary comments and whitespace. Parameter type
declarations must move with their functions: the packed lexer annotations now
live in `lexer/fast64.w`, with a boundary regression check. The largest worker
is `emitter/artifact_bigint.w` at 1,741 lines.

Focused checks passed:

- Generated unit/WIRE tables, compiler-image boundaries, and worker line caps.
  All 5,388 unit ID/signature mappings match main's unsharded generator output.
- C fast-loader versus canonical-parser stage-1 LLVM byte identity, followed
  by the native BigInt/shift acid test.
- Native stage-1/stage-2 self-host LLVM byte identity under
  `--release --native --fast --no-debug`, with persistent Core caching disabled.
- Six parser/lexer specs: packed-token access, direct type lookup, LexChar
  storage, long tokens, and opaque heredocs; four unit fixtures: registry
  parity, dimensional algebra, conversion, and scientific units.
- Compile-profile and stable Core ABI contracts; byte-identical batch/solo IR
  for elementwise fusion, BigInt seams, rationals, and typed overload hosts.
- Native release BigInt seam checks; delegated interpreter hello/eval,
  closures, rescue, and recursion; CUDA and WGSL emitter specs through the
  rebuilt optional Metal image.

The full suite remains a CI responsibility.

## Measurements — 2026-09-07

Before is `99a2beaa`; after is the rebased split. Both native compiler binaries
were built with the same bootstrap compiler and runtime sources using
`--release --native --fast --no-debug` on an Apple M5 Max. Each measurement
starts a fresh compiler process and emits LLVM with those same flags plus
`--emit-ll`, excluding native code generation/linking. Runs alternate variants,
with one initial warmup and five measured samples per variant. Self-compilation
uses each variant's corresponding source tree; the unit fixture uses the
identical source path and Core tree for both variants, and its LLVM is
byte-identical.

| Workload | Main median | Split median | Change |
| --- | ---: | ---: | ---: |
| Self-emit, persistent frontend/Core caches disabled | 4.462 s | 4.991 s | +11.85% |
| Self-emit, persistent frontend/Core caches enabled | 2.845 s | 2.861 s | +0.54% |
| Unit-registry fixture, persistent caches disabled | 0.139 s | 0.159 s | +14.20% |

These are local measurements, not an idle-machine benchmark: unrelated Lean
jobs were active, but no other validation/build from this task ran during
timing. Warm self-emit is effectively tied; cold compilation shows a regression,
not a speed improvement. Smaller invalidation units and reviewable workers are
structural benefits, not evidence of lower end-to-end build time. Do not treat
the correctness gate as performance approval to land this branch.

A two-round cross-check swapped both compiler executables across both source
trees. The main compiler spent 0.630–0.782 s in cold load/parse; the split
compiler spent 1.056–1.136 s, including when reading main's unchanged source
tree. This points to a frontend execution regression in the produced compiler,
not simply extra file-loading work from the new layout. Both compilers emitted
byte-identical LLVM for the final split source tree. Investigating the compiled
frontend's code quality is the next performance gate before landing.

To reproduce cold self-emission, use separate cache/output paths for each
compiler and run from its source tree:

```sh
TUNGSTEN_INCREMENTAL=0 TUNGSTEN_CORE_DISK_CACHE=0 \
TUNGSTEN_FRONTEND_DISK_CACHE=0 TUNGSTEN_CACHE_DIR=/tmp/variant-cache \
TUNGSTEN_LL_PATH=/tmp/variant.ll /path/to/variant-compiler \
  compile compiler/tungsten.w --emit-ll --release --native --fast --no-debug
```

Set `TUNGSTEN_ROOT` and `BIT_HOME` to the matching source/Core and bits trees.
Enable both persistent caches for the warm run and prime them before recording
samples; do not compare a warm after-build against a cold baseline.
