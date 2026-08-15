# 06 — Gotchas

Things that look fine, then surprise you. Read once; reopen when something is
slow, wrong, or "works in the README but not for me."

← [05 — Novelties](05-novelties.md) · [Index](README.md)

---

## 1. Default `Int` is a bignum — use `## i64` on hot paths

Tungsten's default integer is **arbitrary-precision**. Small values live in a
NaN-boxed 48-bit range (no heap). Cross that range — or do enough arithmetic
that intermediates overflow the small-int box — and every op becomes a heap
bignum helper.

In the type hierarchy, `Integer` is the generic exact-integer family, `Int`
selects Tungsten's auto-promoting policy, and `BigInt` is its heap
continuation. Use `is_a?(Integer)` for generic integer algorithms and
`is_a?(Int)` when the default promotion contract is required.

In a tight loop this shows up as:

- Sudden multi‑MB/s RSS growth (escaping bignum intermediates)
- Profiles dominated by `bigint_*` / `w_eq` / `w_add` / `w_mod`
- Correct code that is 10–18× slower than the fixed-width version

**Fix for performance-critical compiled code:** type hot scalars as fixed-width:

```tungsten
rng = base * 1009 + 12345 ## i64
ui = us[ti] ## i64
scan = 0 ## i64
rank = 0 ## i64
```

Rules of thumb (from
[tungsten-performance-engineering.md](../articles/tungsten-performance-engineering.md)):

1. Hot-loop scalars: `## i64` or `## u64`.
2. Profile the **native** binary (`sample`, etc.) — do not guess.
3. Typed array reads (`i64[]`) are already raw; the problem is often the
   untyped temporary you assign them into.

For everyday scripting, plain `Int` is fine and convenient. For search loops,
RNGs, checksums, and compilers — type the width.

---

## 2. One product engine, two workflows

| Path | Command | Strength |
| ---- | ------- | -------- |
| Cached WIRE run | `bin/tungsten file.w` | Full language with a cached output binary |
| Native compile | `bin/tungsten -o out file.w` | Full language; production path |
| Ruby interpreter | `bin/tungsten --ruby file.w` | Bootstrap / fallback tree-walk |

Quick run and native compile now share lexer, parser, lowering, WIRE, codegen,
and runtime semantics. Use `--ruby` only when debugging or changing the legacy
bootstrap interpreter; its remaining gaps do not define product behavior:

| Construct | Notes |
| --------- | ----- |
| Trait autoload | Local `trait` bodies work; some `is Trait` paths need autoload |
| `go` / channels | Basic `go` drains at end of program; channel fixtures may still diverge |
| Array `[]=` via alias | A few alias/subscript cases still differ from compiled |
| GPU / `@gpu fn` | Compile + Metal/CUDA path only |

When an example "doesn't work," try:

```bash
bin/tungsten -o /tmp/prog file.w && /tmp/prog
```

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

1. Check for **bignum** hot paths first (`## i64`) — that is the usual culprit.
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

- **Platform:** Metal path targets macOS (Apple silicon); needs a recent Metal
  toolchain. Not the Linux CPU path.
- **Subset:** v0 emits Metal Shading Language from a limited kernel dialect —
  typed arrays, simple control flow, GPU builtins. Full Tungsten (classes,
  Decimal money, traits, …) does **not** run on the GPU.
- **Types:** Prefer explicit `## f32`, `## i32`, buffer types; default `Int`
  thinking does not apply.
- **Dispatch:** Host/runtime Metal bridges compile and launch kernels; a bare
  `@gpu fn` without the supporting host call path will not "just run" like a
  CPU `->`.

See `compiler/lib/metal_emitter.w` and the CHANGELOG GPU notes for current
scope.

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

## 11. Interpreter vs compiler small divergences

Documented examples:

- **Date/time range checks:** interpreter validates calendar/clock fields more
  strictly; compiler may accept digit-shaped but invalid dates.
- **IPv6 forms:** some expanded/zone forms differ by engine.
- **Unit pipelines:** surface is real; compiled conversion is still maturing.

When writing tests that must match exactly, pin the engine (`-o` vs quick run)
the harness expects.

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
| Feature works in docs, fails quick run | Compiled-only construct | `bin/tungsten -o …` |
| Slow loop / growing RSS | Default `Int` bignums | `## i64` on hot vars |
| `a/b` not dividing | MAP lex | `a / b` with spaces |
| Money/float weirdness | Decimal vs `~` float | Pick one intentionally |
| Trait methods missing | Engine gap | Compile with `-o` |
| GPU kernel ignored / errors | Subset / platform | Metal host path; typed kernel body |

---

## Where to go next

- Revisit features: [Index](README.md)
- Dense reference: [TUNGSTEN_FOR_LLMs.md](../TUNGSTEN_FOR_LLMs.md)
- Value tags: [WVALUE.md](../WVALUE.md)
- Performance story: [tungsten-performance-engineering.md](../articles/tungsten-performance-engineering.md)
- Spec: [specification/](../specification/)
- Examples: [doc/examples/](../examples/)
