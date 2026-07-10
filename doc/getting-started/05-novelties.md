# 05 — Novelties

The surface forms that make Tungsten feel different from Python or Ruby —
compact, intentional, and easy to mistype until they click.

← [04 — Literals & units](04-literals-and-units.md) · [Index](README.md) · Next: [06 — Gotchas](06-gotchas.md) →

---

## 1. Blocks close by dedent

No `end`. No `}`. Indent starts a block; dedent ends it.

```tungsten
if ready
  << "go"
  do_work()
# ← this line's indent closed the if
```

Same rule for `->` method bodies, `while`, `case`, `+` class bodies, and
lambdas. **Consistent spaces matter.**

---

## 2. `<<` prints (and friends)

| Op | Role |
| -- | ---- |
| `<<` | puts (newline) |
| `<-` | print (no newline) |
| `<!` | raise |

```tungsten
<< "hello"
<- "partial "
<< "line"
<! "something went wrong"
```

There is no `print` / `puts` keyword in the usual style — the arrow ops are the
idiom.

---

## 3. `+` is class, `->` is method

```tungsten
+ Greeter
  -> new(@name) ro
  -> hi
    << "hi [@name]"
```

Contrast:

| Concept | Tungsten | Python | Ruby |
| ------- | -------- | ------ | ---- |
| Class | `+ Point` | `class Point:` | `class Point … end` |
| Method | `-> distance/1` | `def distance(self, other):` | `def distance(other) … end` |
| Print | `<< x` | `print(x)` | `puts x` |
| Block end | (dedent) | (dedent) | `end` |

---

## 4. String interpolation with `[ ]`

```tungsten
name = "Ada"
<< "hello [name], [2 * 21]"
# literal brackets: \[ \]
```

Not `#{…}`, not `f"{…}"`.

---

## 5. Pipeline map: `/method`

A slash **glued** to an identifier is a map stage, not division.

```tungsten
# Division: spaces, or a non-identifier right-hand side
<< 10 / 2                    # division
<< 10/2                      # also division (digit is not an ident start)

# Map stages — slash immediately followed by an identifier
<< [1, 2, 3]/sq             # each element .sq
# Prefix form also exists in pipeline contexts: /sq
```

Chained pipelines fuse in the compiler when possible:

```tungsten
# Conceptual shape (names depend on available methods / predicates)
# source /sq /select(:even?) :sum
```

Design consequence: `a/b` with two bare **identifiers** is a **map**, by design.
Write `a / b` when either side is a name and you mean divide.

---

## 6. Swap: `a <> b`

```tungsten
a = 1
b = 2
a <> b
<< a                         # => 2
<< b                         # => 1
```

Desugars to a multi-assign of `[b, a]` — no temporary in source.

---

## 7. `fn` — pure and memoized *(compiled)*

```tungsten
fn fib(n)
  if n <= 1
    n
  else
    fib(n - 1) + fib(n - 2)
```

`fn` tells the compiler the function is pure and eligible for automatic
memoization. Great for recursive combinatorics; use `-o` to compile.

Ordinary `->` functions are not auto-memoized.

---

## 8. Arity form and `@1`, `@2` *(compiled)*

```tungsten
-> add/2
  @1 + @2

-> distance/1
  # one argument; README-style math may use prime fields on that arg
```

`/N` is arity. Positional args are `@1` … `@N` when you skip names.

Constructor parameters still use `@field` binding:

```tungsten
-> new(@x, @y) ro            # fields, not arity slots
```

---

## 9. Prime notation and deltas

In binary methods, prime marks the *other* side's fields:

```tungsten
-> distance/1
  dx = x - x'                # self.x - other.x
  dy = y - y'
  (dx.sq + dy.sq).sqrt

# unicode form
-> distance/1
  √(Δx² + Δy²)
```

This is why the Point examples in the README look like notebook math.

---

## 10. Accessors without `attr_*`

```tungsten
+ Dog
  -> new(@name, @breed) rw   # generates readers + writers

+ Point
  -> new(@x, @y) ro          # readers only
```

Standalone `ro :name` / `rw :breed` also exist *(compiled)*.

---

## 11. Exact decimals by default; floats opt in

```tungsten
<< 0.1 + 0.2 == 0.3          # true
x = ~1.5                     # machine float
```

Scientific / GPU code uses `~` and typed arrays (`## f32[]`, etc.). Application
logic stays on Decimals until you choose otherwise.

---

## 12. Domain literals are syntax

Not shown again in full — but they are novelties relative to mainstream langs:

- `$3.50`, `25¢`, `15%`
- `5 kg`, `100 mph`, `1 acre | sqft`
- `2024-01-15`, `2024-01-15T14:30:00Z`
- `#FF0000` colors, `« ab cd »` bytes, IP/CIDR forms

See [04 — Literals & units](04-literals-and-units.md).

---

## 13. `@gpu fn` — GPU kernels in the same file

```tungsten
@gpu fn add_one(x ## f32[], y ## f32[], n ## i32)
  i ## i32 = gpu.thread_position_in_grid.x
  if i < n
    y[i] = x[i] + 1.0
```

`@gpu fn` lowers to Metal Shading Language (MSL) on Apple platforms (v0 is
MSL-only). It is a **subset** of the language — typed buffers, limited control
flow — not "any Tungsten on the GPU". Details and pitfalls:
[06 — Gotchas](06-gotchas.md).

---

## 14. Comparison cheat sheet

| Feature | Tungsten | Python | Ruby |
| ------- | -------- | ------ | ---- |
| Output | `<< x` | `print(x)` | `puts x` |
| Class | `+ Point` | `class Point:` | `class Point … end` |
| Method | `-> distance/1` | `def distance(self, other):` | `def distance(other)` |
| Map | `list/sq` or `list.map -> …` | `[x**2 for x in list]` | `list.map { … }` |
| Swap | `a <> b` | `a, b = b, a` | `a, b = b, a` |
| Interpolation | `"[name]"` | `f"{name}"` | `"#{name}"` |
| Block ending | (dedent) | (dedent) | `end` |

Token density is intentional: fewer tokens for humans and for LLMs. See
[`doc/examples/04-ai-native/`](../examples/04-ai-native/).

---

## Try it

```bash
bin/tungsten -e '<< [1, 2, 3]/sq'
bin/tungsten -e 'a = 1; b = 2; a <> b; << a'
bin/tungsten -e '<< "2+2=[2 + 2]"'
```

Next: **[06 — Gotchas](06-gotchas.md)**
