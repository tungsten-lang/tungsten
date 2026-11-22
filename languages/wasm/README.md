# WebAssembly engine (Tungsten)

The WebAssembly engine for Blade, the browser, written in Tungsten. Blade carries a copy in
`apps/blade/lib/blade/wasm/` (`tools/sync_blade.sh`); the JS API binding is Blade's own
`lib/blade/jswasm.w`.

| File | What |
|---|---|
| `types.w` | value types as integers, the process-wide canonical type registry (iso-recursive GC types), the decoded module |
| `reader.w` | binary decoder (WebAssembly 3.0 + threads) |
| `opcodes.w`, `wat.w` | instruction table and the text format: lexer, S-expressions, WAT → binary encoder |
| `compile.w`, `simd.w` | one-pass validator that compiles function bodies to register code |
| `validate.w` | module validation, constant expressions |
| `ops.w`, `interp.wt` → `interp.w` | internal opcodes and the typed interpreter loop (`tools/gen_interp.w` substitutes op numbers) |
| `kernels.w`, `simd_exec.w`, `atomic.w` | LLVM IR leaf kernels: float/bit ops, SIMD, atomics |
| `runtime.w` | store, instances, memories, tables, globals, instantiation, the driver and OP_EXT slow paths, exceptions |
| `gc.w` | structs, arrays, i31, casts |
| `jit.w` | the optimizing tier |
| `tools/` | `wast.w` spec-script runner, `run.w` / `probe.w`, `wpt/` WPT jsapi runner, `sync_blade.sh` |

Design:
- Register code. Every operand-stack height has a fixed frame slot, so a wasm instruction
  becomes one 3-address op on slots (`ADD32 d a b`). `local.get` and constants are deferred
  operands (no copies; immediate forms like `ADDI32`, `JLTSI32`), compares fuse with
  `br_if`/`if`, `local.set` retargets the producing op. Call arguments are already in the
  callee's frame (frames overlap), v128 takes two slots, references live in a parallel
  object stack at the same index.
- The interpreter loop is one typed function over `i64[]` slots and `u8[]` memory, with an
  explicit bounds check per access. It exits to the untyped driver for calls to imports,
  slow call_indirect, and `OP_EXT` (table ops, memory.grow, bulk segment ops, GC,
  exceptions, atomics, SIMD memory ops on other memories).
- Optimizing tier: each function's register code is translated to LLVM IR (one alloca per
  slot, mem2reg makes it SSA), compiled with clang -O2 on a background thread after
  instantiation, dlopen'ed, and swapped in by patching the function's `OP_ENTER` to `OP_JIT`.
  Calls the JIT does not handle go back into the driver through `w_closure_call_2`
  (an upcall). Without clang the engine stays in the interpreter.
- Floats travel as bit patterns; float ops are LLVM IR kernels (wasm semantics for
  min/max, nearest, trapping and saturating conversions); the JIT canonicalises float
  results so sNaN inputs give arithmetic NaNs.
- Shared memories are allocated at their maximum so their bytes never move.

Run the spec tests:

```sh
bin/tungsten -o /tmp/wast --release languages/wasm/tools/wast.w
/tmp/wast test/core/*.wast                  # interpreter
WASM_JIT_WAIT=1 /tmp/wast test/core/*.wast  # every module compiled before it runs
```
