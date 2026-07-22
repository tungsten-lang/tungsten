# Changelog

## Unreleased

- **Machine-int annotated params materialize as raw entry slots** — a
  parameter reassigned anywhere in its body with `## i64/u64` now gets a
  raw machine slot at function ENTRY (the representation a local gets from
  `y = x ## u64`): full-width reads, native 2^64 wrap on UNANNOTATED
  arithmetic reassigns in the same chain (previously those promoted to
  bignums while identical local chains wrapped), and no mid-branch
  retype. Captured and signature-typed params are unaffected.
- **`size`/`length` reachable through dynamic dispatch on String/Symbol** —
  untyped receivers (`f(s).size()`, chained `.to_s().size()` in
  interpolation) previously died with "undefined method 'size' for
  String": the type-class cascade misses core String/Symbol source
  methods (pre-existing gap; other source methods like `reverse` remain
  dynamically unreachable — documented in runtime.c).

- **Annotated reassign of a boxed variable is full-width correct** — a
  `## i64/u64` reassign of an existing parameter or boxed local (e.g.
  inside one branch of an `if`, or an unconditional chain like
  xorshift64* through a parameter) no longer retypes it to a raw machine
  slot; the RHS keeps wrapping semantics but the result is boxed back and
  the variable is classified `:bigint` so subsequent machine-context reads
  take the full-width unbox. Previously post-merge reads mixed NaN-boxed
  and raw bits (silent wrong values at call boundaries), and — even
  unconditionally — values past 2^48 read back through the 48-bit nanunbox
  shortcut were truncated to garbage.
- **begin/rescue is a value expression in compiled code** — in value
  position (method tail, case/if arm, assignment rhs) it now produces the
  taken arm's last expression; both arms previously reached callers as
  nil. `ensure` still runs for effect only. Matches the interpreter.
- **Fused machine-int subscript reads AND writes** — `x = arr[i] ## u64`
  and `arr[i] = x` (machine-int x) on untyped `:var` receivers lower to
  raw runtime reads/writes for typed integer arrays: zero heap boxing
  (previously one dead bignum box per read AND per write past 2^48 — the
  chessbot 1 GB/s leak). Every other receiver keeps byte-identical
  dynamic dispatch.
- **u64×u64 multiply confirmed raw** — annotated u64 multiplies lower to a
  raw wrapping `mul` in all positions; pinned by spec with xorshift64*
  reference vectors.
- Wide-arity (16-param) direct functions with in-body calls pinned by
  spec; dynamic method dispatch keeps its documented 8-argument limit
  (loud error, never corruption).

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
