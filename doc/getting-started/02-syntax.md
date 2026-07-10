# 02 — Syntax

Variables, control flow, functions, strings, and collections — the everyday
surface of Tungsten.

← [01 — Hello](01-hello.md) · [Index](README.md) · Next: [03 — OOP](03-oop.md) →

---

## Variables and types

No keyword for assignment. Names are bound with `=`.

```tungsten
name = "Tungsten"
version = 1
pi = 3.14159          # exact Decimal (not a float)
active = true
nothing = nil

<< "Language: [name]"
<< "Version: [version]"
<< "Pi: [pi]"
<< "Active: [active]"
```

```bash
bin/tungsten doc/examples/01-basics/variables.w
```

### Built-in values you'll use constantly

| Kind | Examples | Notes |
| ---- | -------- | ----- |
| Int | `42`, `0xFF`, `0b1010`, `1_000_000` | Arbitrary precision by default |
| Decimal | `3.14`, `0.1` | Bare fractions are **exact** |
| Float | `~3.14` | Machine float is opt-in with `~` |
| String | `"hello"` | Interpolation: `"[expr]"` |
| Bool | `true`, `false` | Only `nil` and `false` are falsey |
| Nil | `nil` | |
| Symbol | `:name` | Interned name |
| Array | `[1, 2, 3]` | |
| Hash | `{name: "Alice", age: 30}` | |
| Range | `1..10`, `1...10` | Inclusive `..` / exclusive `...` |

Important: `0.1 + 0.2 == 0.3` is **true** because bare decimals are exact
`Decimal` values, not IEEE floats. Use `~` when you want machine floating point.

---

## Strings

```tungsten
size = "little"
<< "Mary had a [size] lamb."

# Escape a bracket so it is not interpolated
<< "literal \[brackets\]"

# UTF-8 works in source
<< "héllo wörld"
```

```bash
bin/tungsten doc/examples/rosetta_code/string_interpolation.w
```

---

## Functions

Methods and top-level functions use `->`:

```tungsten
-> greet(name)
  << "Hello, [name]!"

greet("world")

-> square(n)
  n * n                     # last expression is the return value

<< square(5)                # => 25
```

There is no `return` required for normal returns — the value of the last
expression in the body is returned. (Explicit early-exit forms exist; for
day-to-day code, rely on the last expression.)

### Lambdas

```tungsten
double = ->(x) x * 2
<< double.call(21)          # => 42

# Or pass the lambda straight to a higher-order method
<< [1, 2, 3].map ->(x) x * 2
```

Blocks can bind an implicit `item`:

```tungsten
<< [1, 2, 3].map -> item ** 2
```

### Pure / memoized functions *(compiled)*

```tungsten
fn fib(n)
  if n <= 1
    n
  else
    fib(n - 1) + fib(n - 2)

<< fib(10)                  # => 55
```

`fn` marks a pure function the compiler may auto-memoize. Prefer the compiled
path for programs that use `fn`:

```bash
bin/tungsten -o /tmp/fib your_fib.w && /tmp/fib
```

### Arity shorthand *(compiled)*

```tungsten
-> add/2
  @1 + @2

<< add(3, 4)                # => 7
```

`/2` means "two arguments"; inside the body they are `@1`, `@2`, ….

---

## Control flow

Blocks close by **dedent** — indent in, dedent out. No `end`, no `}`.

### if / elsif / else

```tungsten
x = 7

if x > 10
  << "big"
elsif x > 5
  << "medium"
else
  << "small"

# Suffix form
<< "positive" if x > 0
```

### while / until

```tungsten
i = 1024
while i > 0
  << i
  i /= 2

i = 1024
until i <= 0
  << i
  i /= 2

# Suffix form
i = 1024
<< i /= 2 while i > 0
```

```bash
bin/tungsten doc/examples/rosetta_code/loops/while.w
```

### each and ranges

Tungsten favors iterator-style loops:

```tungsten
(1..5).each ->(i)
  << i

list = [1, 2, 3]
list.each ->(i)
  << i

5.times ->(i)
  << i
```

```bash
bin/tungsten doc/examples/rosetta_code/loops/foreach.w
bin/tungsten doc/examples/rosetta_code/loops/for.w
```

### case / when

```tungsten
value = 2
case value
  when 1
    << "one"
  when 2, 3
    << "two or three"
  else
    << "other"

# Guard form (no scrutinee expression)
y = 7
case
when y > 10
  << "big"
when y > 5
  << "medium"
else
  << "small"
```

---

## Arrays

```tungsten
numbers = [5, 3, 1, 4, 2]

<< numbers.join(", ")
<< numbers.sort
<< numbers.sum
<< numbers.min
<< numbers.max
<< numbers.size

doubled = numbers.map ->(x) x * 2
evens = numbers.select ->(x) x % 2 == 0

# reduce is available on the compiled path
total = numbers.reduce(0, ->(a, b) a + b)   # (compiled)
```

```bash
bin/tungsten doc/examples/02-data/arrays.w
```

Pipeline form (tight `/method` map stages) is covered in
[05 — Novelties](05-novelties.md):

```tungsten
<< [1, 2, 3]/sq           # map each element through .sq
```

---

## Hashes

```tungsten
person = {name: "Alice", age: 30, city: "Portland"}

<< person[:name]            # => Alice
<< person.size              # => 3
```

```bash
bin/tungsten doc/examples/02-data/hashes.w
```

---

## Error handling

```tungsten
-> risky
  raise "boom"

begin
  risky()
rescue e
  << "Error: [e]"
ensure
  << "cleanup"
```

`<!" is a raise shorthand: `<! "boom"`.

---

## Indentation rules (the short version)

- Indent with **spaces** (convention: 2 spaces; be consistent).
- A block is everything indented under a header (`if`, `while`, `->`, `+`, …).
- Dedenting closes the block — that is the entire "end keyword" story.
- Mixing tabs and spaces will confuse you and the lexer; use spaces.

---

## Try it

```bash
bin/tungsten doc/examples/01-basics/functions.w   # may need -o for fn / @1
bin/tungsten doc/examples/02-data/arrays.w
bin/tungsten doc/examples/02-data/hashes.w
```

Next: **[03 — OOP](03-oop.md)**
