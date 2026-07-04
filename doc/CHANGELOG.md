# Changelog

## 2026.07.04 — Public Preview

The first public release of Tungsten: an object-oriented language that reads
like pseudocode — no `end`, braces, or `return`; blocks close by dedent — and
compiles, through its own self-hosted compiler, to native binaries via LLVM
and to Metal GPU kernels via `@gpu fn`.

Highlights of this preview:

- **Self-hosted compiler** — `compiler/tungsten.w` compiles itself; every
  build proves the fixed point (stage 1 and stage 2 emit byte-identical
  LLVM IR).
- **Exact decimals by default** — `3.14` is a Decimal; floats are opt-in
  with `~3.14`. `0.1 + 0.2 == 0.3` is `true`.
- **Currency, units, and percentages as literals** — `$3.50 - 25¢`,
  `299_792_458 m/s`, `price - 15%` (units pipeline in active development on
  the compiled path).
- **Generics, monomorphized** — `Complex<f64>` stamps out a specialized
  class with native arithmetic; powers a hypercomplex numeric tower
  (Complex → Quaternion → Octonion → Sedenion → 256-dimensional algebras).
- **GPU in the language** — `@gpu fn` lowers to Metal Shading Language;
  Tensors share one allocation with Metal 4 `MTLTensor`s (zero-copy);
  single-head attention runs end-to-end on-device.
- **Floating-point math modes** — strict / precise / fast, with scoped
  `@strictmath` / `@fastmath` blocks and explicit `fma()`.
- **Pattern dispatch** — `case`/`when` plus the `recase` re-dispatch
  keyword; interned scrutinees compile to real LLVM switches.
- **REPL that plots** — braille-rendered curves in the terminal with live
  coefficient scrubbing.

Platforms: macOS (Apple silicon) and Linux, x86_64 + arm64.
Requires clang/LLVM; GPU features need macOS 26+.

## 0.1.0

## 0.0.1
