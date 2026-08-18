# Embedded LLVM IR and assembly function bodies

A typed `fn` whose entire body is a single `ll <<~IR` or `asm <<~ASM`
call becomes that LLVM IR or AArch64 assembly verbatim. Heredocs lex as
raw text, so IR/asm brackets never interpolate. The form works at top
level and inside a class body (see "Class-scoped kernels" below).

```
fn add_n8(rp, ap, bp, n) (u64[] u64[] u64[] i64) i64
  asm <<~ASM
    cmn xzr, xzr
  1:
    ldp x4, x5, [x1], #32
    ...
    adcs x12, x4, x8
    ...
    cbnz x3, 1b
    cset x0, hs
    ret
  ASM
```

Why: LLVM cannot reconstruct multi-limb carry chains from portable code —
the vectorizer cannot touch a loop-carried carry, and the carry flag spills
across loop back-edges (LLVM issue #74493; unroll metadata only amortizes
it). Measured on the 64-limb add kernel (Apple M): portable `addcarry` loop
~3.1 cycles/limb, embedded `ll` with `i256` block adds ~1.5 c/l, embedded
`asm` ADCS chain ~1.0 c/l — matching the C runtime's hand-written kernels.

## Contract

- Top-level `fn` with a typed signature only. Parameters must be machine
  ints (`i64`/`u64`) or typed arrays; returns may also be `i128`/`u128`.
- `ll` bodies: emitted as the function's `define` body. Parameters are
  available by their source names (`%rp`, `%n`, …), all `i64`. Typed-array
  parameters arrive as the start-corrected element-0 data address
  (`inttoptr` to use). The body owns its control flow and must return the
  declared `i64` or `i128` LLVM type.
  Wide types (`i256` loads/adds) are legal and legalize into adds/adcs
  runs — the portable way to get carry chains without assembly.
- `asm` bodies: emitted as module-level assembly under the function's
  symbol. Parameters per AAPCS64 in `x0..x7` (arrays as data addresses),
  scalar return in `x0`; `i128`/`u128` follows AAPCS64 in `x0` (low) and
  `x1` (high). The body must `ret`. AArch64/Mach-O only today.
- Callers use the raw ABI: no boxing on either side. A declared `u64`
  return boxes unsigned.
- An `ll` body may contain `; tungsten:alwaysinline` or
  `; tungsten:noinline` to request that exact LLVM function attribute. The
  markers are mutually exclusive. Use `noinline` when an exact C port must
  preserve an intentional call boundary or keep a large fixed leaf out of
  its selector; do not use it as a substitute for measurement.
- Compile-only: no interpreter or stage-0 execution (same restriction as
  `mulhi`/`addcarry`). A class method whose body calls a kernel therefore
  needs a walker story (a C-delegation arm or an interpreter-reachable
  fallback path) before it can live in `core/`; the compiler's own
  sources must not use embedded bodies at all.
- The embedded text participates in the function's content hash
  (`content_hash.w`), so incremental caching and the compact `__wy_`
  symbol names stay correct.

## Class-scoped kernels

The same `fn` + heredoc shape inside a class body compiles to a
class-mangled raw-ABI kernel (`__w_<Class>_<name>__aN` symbol — kernels
in different classes never collide). A kernel:

- takes NO implicit `__self`; pass what it needs explicitly (machine
  ints, typed arrays, or `wvalue_bits`-derived addresses),
- never enters the method-dispatch tables — it is not a method, and
  dynamic dispatch cannot reach its raw ABI,
- is callable by bare name from sibling methods through the raw path.
  Single-definition kernels also register under their plain name (the
  same courtesy top-level typed fns get), so keep kernel names
  program-unique.

Sibling methods defined before the kernel in the class body still lower
their call sites correctly — class bodies participate in the raw-ABI
pre-registration walk.

Spec: `spec/compiler/embedded_ll_asm_spec.w` (top level),
`spec/compiler/embedded_class_kernel_spec.w` (class-scoped).
Benchmark: `benchmarks/limb_native/bench_embed.w` (three-way carry-chain
comparison, cross-checked limb-exact before timing).
