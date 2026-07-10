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

## 2. Two engines: quick run vs compile

| Path | Command | Strength |
| ---- | ------- | -------- |
| Quick run / interpreter | `bin/tungsten file.w` | Fast edit cycle; great for tutorials |
| Native compile | `bin/tungsten -o out file.w` | Full language; production path |
| Ruby interpreter | `bin/tungsten --ruby file.w` | Bootstrap / fallback tree-walk |

**Constructs that currently need the compiled path** (or are incomplete under
quick run) include:

| Construct | Notes |
| --------- | ----- |
| `fn name(...)` | Pure / memoized functions |
| `@1` / `@2` arity args | With `-> name/N` |
| Standalone `ro :x` / `rw :x` | Constructor trailing `ro`/`rw` is the common path |
| Trait method dispatch | `is Trait` methods |
| `reduce(init, fn)` | Some collection folds |
| `StringBuffer.append` | Mutable string builder |

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
@gpu fn add_one(x ## f32[], y ## f32[], n ## i32)
  i ## i32 = gpu.thread_position_in_grid.x
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
bin/tungsten build           # stage 1 + stage 2, identical .ll required
bin/tungsten build --force   # ignore cached stage binaries
```

A green application program does not prove the compiler still fixed-points —
the build's stage1/stage2 IR check does.

---

## 13. Stdlib `auto` table

New files under `core/` are not visible until registered:

```tungsten
# in core/tungsten.w
auto :MyType, "my_type"
```

Forgetting this looks like a mysterious missing constant.

---

## Quick recovery checklist

| Symptom | Likely cause | Try |
| ------- | ------------ | --- |
| Syntax error at a surprising indent | Dedent / tabs | Spaces only; reindent |
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
