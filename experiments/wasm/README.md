# Raw i64 WebAssembly prototype (item 27)

```sh
bin/tungsten wasm experiments/wasm/kernels.w --out build/kernels.wasm
```

The command emits `.wasm`, the extracted `.ll`, and a provenance/signature
`.json`. Node and browsers call exported i64 functions using JavaScript BigInt.
`--export name` may be repeated to select exports. LLVM clang and wasm-ld are
required; override discovery with `TUNGSTEN_WASM_CLANG` / `TUNGSTEN_WASM_LD`.

This uses the real Tungsten frontend and LLVM lowering. It resolves selected
functions through the compiler sidemap, checks their ABI and instruction
subset, adds export wrappers, and invokes LLVM's wasm32 backend and linker.
It is not a source-to-WASM transpiler or a second language implementation.

Version 1 supports unique top-level leaf functions with explicit i64 positional
parameters and raw i64 returns, local scalar slots, arithmetic, comparisons and
control flow. It rejects runtime calls, globals, arbitrary pointer accesses,
allocation beyond scalar locals, imported source modules, class methods,
dynamic dispatch and top-level execution. There is no WASI, GC, full WValue
runtime, f64 ABI, array ABI, exceptions, or cross-function calling yet.
Integer arithmetic follows raw machine-width semantics, not arbitrary-precision
Int. The linker must resolve every symbol; imports/stubs are never allowed to
hide missing runtime functionality.

WASM compilation uses `-O0` for now: the optimized sum recurrence introduced a
`__multi3` dependency through widened integer arithmetic. That optimization
must either be constrained or supplied with an audited compiler-rt implementation
before enabling optimized output. This prototype makes no performance claim.
Linear memory is bounded at 128 KiB, with no host imports.

`python3 scripts/test-wasm.py` runs 14 cases in native Tungsten and Node WASM
against an independent BigInt oracle, including signed overflow. It also checks
zero module imports and rejection of dynamic, effectful, floating ABI and
top-level forms. `result.json` identifies the tested tools/source/compiler/module.
See [LLVM's WebAssembly linker](https://lld.llvm.org/WebAssembly.html).
