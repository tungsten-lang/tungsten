# Changelog

## Unreleased

- **`sleep()` works in compiled binaries** — bare `sleep(duration)` lowers
  to `__w_sleep`, which now exists in the runtime (Int/Float/Decimal
  seconds; `nil` blocks forever; returns the duration). Previously every
  program calling `sleep()` failed at link time with `___w_sleep` undefined.
- **`System` registered in the core auto table** — `System.cpu_count`,
  `System.executable_path`, etc. resolve in compiled programs instead of
  dying with "undefined method for nil".
- **`String#to_i` promotes past i64** — decimals outside the i64 range parse
  to bignums instead of silently saturating at `LLONG_MAX`/`LLONG_MIN`.
  Non-decimal bases keep the fixed-width parse; `String#to_i` still stops at
  underscores (unchanged).
- **Interpolation ruling: ESC-`[` never interpolates** — inside a string, a
  `[` immediately preceded by ESC (0x1B) is literal no matter how the ESC
  was produced (`\e`, `\u001b`, concatenation), so ANSI CSI sequences like `"\e[K"` can
  never be misread as interpolation. Brackets after any other character
  interpolate as before; `\[` remains the escaped-literal form. New specs:
  `spec/compiler/string_interp_esc_bracket_spec.w`,
  `spec/compiler/string_escape_backslash_spec.w`,
  `spec/core/{global_sleep,system_cpu_count,string_to_i_bignum}_spec.w`.

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
