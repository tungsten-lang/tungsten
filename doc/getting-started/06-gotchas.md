# 06 — Gotchas

Things that look fine, then surprise you. Read once; reopen when something is
slow, wrong, or "works in the README but not for me."

← [05 — Novelties](05-novelties.md) · [Index](README.md)

---

## 1. Unspecified ints wrap at `i64`

Untyped decimal integer arithmetic is C-like wrapping i64 on every product
engine (`bin/tungsten file.w`, `-o`, and `run --interpret`). You do **not**
need `## i64` on an ordinary `rng = 1` loop for it to be a machine multiply.

`type(x)` still prints `Int` — that is the language class, not the machine
width. Arbitrary-precision is the *other* integer:

- literals bigger than i64 (`format == :dec_big`) and `## int` / `## bigint`
- `**` and untyped `1 << n` (the result may be a BigInt; typing those `:i64`
  wraps the shift)
- `Math.promote -> …` for a lexical promoting block
- `TUNGSTEN_INFER=boxed`, the reference oracle that keeps every untyped
  integer on the guarded promoting path

In the type hierarchy, `Integer` is the generic exact-integer family, `Int`
is the default class name, and `BigInt` is the heap continuation. Use
`is_a?(Integer)` for generic integer algorithms.

The remaining slow path is a **boxed `:int`** that still goes through guarded
i48 arithmetic and can allocate a BigInt. That is no longer the default for
untyped literals. `## i64` / `## u64` remain useful when you must pin a
machine width against a value that would otherwise stay `:int` (a `to_i` of
a huge string, a `## int` accumulator, a bigint `**`).

---

## 2. Compiled WIRE is the reference

| Path | Command | Role |
| ---- | ------- | ---- |
| Cached WIRE run | `bin/tungsten file.w` | Product: lower through WIRE, cache, run |
| Native compile | `bin/tungsten -o out file.w` | Same semantics, explicit binary |
| Tree-walk | `bin/tungsten run --interpret` | Same language; evaluates the AST (must match WIRE) |
| Ruby | `bin/tungsten --ruby file.w` | Full second implementation |

Quick run and `-o` share lexer, parser, lowering, WIRE, codegen, and runtime
semantics. The self-hosted interpreter is a tree-walk of the same AST and is
kept in lockstep with that semantics. `@gpu fn` is a separate kernel dialect
(Metal/CUDA/WGSL), not a second CPU language.

The C VM in `implementations/c` bootstraps the self-hosted compiler. It is
not a full language implementation. `implementations/ruby` is.

Agent-oriented summary: [TUNGSTEN_FOR_LLMs.md](../TUNGSTEN_FOR_LLMs.md)
(section **Engines**).

---

## 3. `/map` is not division

```tungsten
a / b                        # division (spaces)
a/b                          # MAP stage — identifier after /
[1, 2, 3]/sq                # map .sq over the array
10/2                         # division (digit is not an ident start)
n/2                          # MAP if `2…` were an ident — prefer `n / 2`
```

Lexer rule: `/` immediately followed by an **identifier start** is the **MAP**
operator. Always space division when the right-hand side is a bare name:
`total / count`.

---

## 3½. `[` interpolates — except right after ESC

`[expr]` inside a double-quoted string interpolates. Two exceptions:

```tungsten
<< "value: [x]"              # interpolates x
<< "\[x]"                    # escaped: literal [x]
<< "\e[K"                    # literal — [ after ESC never interpolates
<< "\e[48;2;[r];[g];[b]m"    # ANSI prefix literal, [r]/[g]/[b] interpolate
```

Ruling (2026-07-22): a `[` **immediately preceded by ESC (0x1B)** never
starts interpolation, however the ESC was produced (`\e`, `\u001b`, concatenation). ANSI
CSI sequences are safe to write naturally. A `[` after any other character
interpolates when its content parses as an expression; `\[` stays the
explicit escaped-literal form. Guarded by
`spec/compiler/string_interp_esc_bracket_spec.w`.

---

## 4. `0.1` is Decimal; floats need `~`

```tungsten
<< 0.1 + 0.2 == 0.3          # true
<< ~0.1 + ~0.2               # float semantics
```

Mixing Decimal and Float without intent is a common source of type/print
surprises. For numerics and GPU buffers, opt into `~` and/or `## f32` /
`## f64` explicitly.

---

## 5. Date literals vs subtraction

```tungsten
d = 2024-01-15               # Date (no spaces around -)
n = 2024 - 01 - 15           # integer subtraction
```

The date scanner requires hyphens **adjacent** to the digits.

---

## 6. `#` comments vs `#FF0000` colors

`#` starts a comment, **unless** it is a hex color of length 3, 4, 6, or 8:

```tungsten
# this is a comment
c = #FF0000                  # Color red
#FF                          # comment (too short to be a color)
```

---

## 7. `TUNGSTEN_FREE` and apparent "leaks"

By default the compiler inserts `free` for non-escaping heap values
(`TUNGSTEN_FREE` on).

```bash
TUNGSTEN_FREE=0 bin/tungsten -o out file.w   # disable free insertion
```

If you see RSS climb:

1. Check for a boxed `:int` / BigInt path (`## int`, `**`, huge `to_i`) — not
   ordinary untyped i64 arithmetic.
2. Then consider whether values escape in a way that disables free insertion.
3. Only then turn `TUNGSTEN_FREE` as a diagnostic.

---

## 8. GPU is a subset (`@gpu fn`)

```tungsten
## f32[]: x
## f32[]: y
## i32: n
@gpu fn add_one(x, y, n)
  i = gpu.thread_position_in_grid.x ## i32
  if i < n
    y[i] = x[i] + 1.0
```

Gotchas:

- **Platform:** Metal on macOS (Apple silicon); CUDA and WGSL sidecars from
  the same kernel AST. Not a Linux CPU fallback for `@gpu fn`.
- **Subset:** a limited kernel dialect — typed arrays, simple control flow,
  GPU builtins. Full Tungsten (classes, Decimal money, traits, …) does
  **not** run on the GPU.
- **Types:** Prefer explicit `## f32`, `## i32`, buffer types; wrapping `Int`
  thinking does not apply.
- **Dispatch:** Host/runtime bridges compile and launch kernels; a bare
  `@gpu fn` without the supporting host call path will not "just run" like a
  CPU `->`.

See `compiler/lib/metal_emitter.w`, `doc/gpu-cuda.md`, and `doc/gpu-portable.md`.

---

## 9. Indentation and tabs

Dedent is structural. Mixed tabs/spaces, or editors that reindent differently
than 2 spaces, produce baffling parse errors. Use spaces; match neighbors.

---

## 10. Last expression is the return value

```tungsten
-> square(n)
  n * n                      # returned

-> greet(name)
  << "hi [name]"             # prints; return value is whatever << yields
```

People coming from languages with mandatory `return` either over-return or
accidentally return a print result. Be deliberate about the last expression.

---

## 11. Interpreter vs compiler remaining divergences

`bin/tungsten file.w`, `-o`, and `run --interpret` are the same language.
`<<` prints `#to_s` (so `<< nil` is a blank line, and arrays of strings are
`[a, b]`, not inspect-quoted). Remaining splits live in `spec/parity/` —
mostly compile-time vs run-time arity errors, error-message shape, and
generic class names (`type(Box<Integer>)` is `Box` interpreted and
`Box$Integer` compiled). Dates, ranges, IPv6, and `|` unit conversion agree:

- **Dates:** invalid calendar/clock fields are rejected. Compiled literals
  fail at lowering (`E_LOWER_DATE_*` / `E_LOWER_TIME_*`); `Date.parse` and
  interp literals go through `w_date_parse`, which uses the same checks as
  `Date.new`.
- **IPv6:** both engines share the lexer (`::`-compressed literals, no zone
  id) and `w_ipv6_from_string`. Print is always expanded
  (`2001:db8:0:0:0:0:0:1`). Expanded input and `%zone` are not literals on
  either engine; `IPv6.parse` accepts the 8-group form and rejects zones.
- **Unit pipelines:** `| km` / `| cm(2)` call `w_quantity_pipe` on both
  engines.

The ledger is `spec/parity/DIVERGENCES.md`.

---

## 12. Self-host / bootstrap when hacking the compiler

If you change `compiler/`:

```bash
bin/tungsten bootstrap       # fresh clone: stage 0, runtime, stage 1, then full build
bin/tungsten build           # existing compiler: stage 1 + stage 2
bin/tungsten build --force   # ignore cached build artifacts
```

Bootstrap hands its runtime and stage-1 artifacts to `build`; the chained build
must reuse that exact matching profile rather than compiling them a second time.
A green application program does not prove the compiler still fixed-points —
the stage-1/stage-2 byte-identity check does.

---

## 13. Stdlib `auto` table

New files under `core/` are not visible until registered:

```tungsten
# in core/tungsten.w
auto :MyType, "my_type"
```

Forgetting this looks like a mysterious missing constant.

---

## PascalCase is not a variable name

Identifiers with an uppercase letter followed later by a lowercase letter
(`FooBar`, `Wit`, `WIT_keys`) parse as **class references**, not variables.
Assigning to them raises `E_PARSE_INVALID_ASSIGN_TARGET`.

```tungsten
# bad — class_ref
WIT_keys = [1, 2, 3]

# good — SCREAMING_SNAKE or snake_case
WIT_KEYS = [1, 2, 3]
wit_keys = [1, 2, 3]
GOOD_7 = [1, 5]          # digits are fine in SCREAMING_SNAKE
```

---

## Quick recovery checklist

| Symptom | Likely cause | Try |
| ------- | ------------ | --- |
| Syntax error at a surprising indent | Dedent / tabs | Spaces only; reindent |
| `Invalid assignment target` on `Foo=…` | PascalCase → class_ref | Use `snake_case` or `SCREAMING_SNAKE` |
| Feature works in docs, fails quick run | Remaining parity split | `spec/parity/DIVERGENCES.md` |
| Slow loop / growing RSS | Boxed `:int` / BigInt (`## int`, `**`, huge `to_i`) | Keep untyped i64; annotate only when you mean it |
| `a/b` not dividing | MAP lex | `a / b` with spaces |
| Money/float weirdness | Decimal vs `~` float | Pick one intentionally |
| GPU kernel ignored / errors | Subset / platform | Typed kernel body; Metal/CUDA/WGSL host path |

---

## Where to go next

- Revisit features: [Index](README.md)
- Dense reference: [TUNGSTEN_FOR_LLMs.md](../TUNGSTEN_FOR_LLMs.md)
- Value tags: [WVALUE.md](../WVALUE.md)
- Performance story: [tungsten-performance-engineering.md](../articles/tungsten-performance-engineering.md)
- Spec: [specification/](../specification/)
- Examples: [doc/examples/](../examples/)
