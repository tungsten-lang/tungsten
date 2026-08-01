# Embedded LLVM IR and assembly function bodies

A top-level typed `fn` whose entire body is a single `ll <<~IR` or
`asm <<~ASM` call becomes that LLVM IR or AArch64 assembly verbatim.
Heredocs lex as raw text, so IR/asm brackets never interpolate.

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
  ints (`i64`/`u64`) or typed arrays.
- `ll` bodies: emitted as the function's `define` body. Parameters are
  available by their source names (`%rp`, `%n`, …), all `i64`. Typed-array
  parameters arrive as the start-corrected element-0 data address
  (`inttoptr` to use). The body owns its control flow and must `ret i64`.
  Wide types (`i256` loads/adds) are legal and legalize into adds/adcs
  runs — the portable way to get carry chains without assembly.
- `asm` bodies: emitted as module-level assembly under the function's
  symbol. Parameters per AAPCS64 in `x0..x7` (arrays as data addresses),
  return in `x0`, body must `ret`. AArch64/Mach-O only today.
- Callers use the raw ABI: no boxing on either side. A declared `u64`
  return boxes unsigned.
- Compile-only: no interpreter or stage-0 execution (same restriction as
  `mulhi`/`addcarry`). Do not use in `core/` or the compiler itself.
- The embedded text participates in the function's content hash
  (`content_hash.w`), so incremental caching and the compact `__wy_`
  symbol names stay correct.

Spec: `spec/compiler/embedded_ll_asm_spec.w`.
Benchmark: `benchmarks/limb_native/bench_embed.w` (three-way carry-chain
comparison, cross-checked limb-exact before timing).
