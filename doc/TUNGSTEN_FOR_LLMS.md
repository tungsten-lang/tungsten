# Tungsten Language Reference (for LLMs)

Tungsten is an indentation-based, object-oriented language with Ruby-like
semantics and Python-like syntax density.

Two ways to run code (see **Engines** at the bottom):

- `bin/tungsten file.w` — quick run (interpreter)
- `bin/tungsten -o app file.w && ./app` — compile to a native binary

## Basics

```tungsten
# Print to stdout
<< "hello world"

# Variables (no keyword needed)
name = "Tungsten"
x = 42

# String interpolation uses [ ]  (but a [ right after ESC is literal,
# so ANSI sequences like "\e[K" are safe; \[ escapes explicitly)
<< "hello [name], [x * 2]"
```

## Functions

```tungsten
# Method definition
-> greet(name)
  << "hello [name]"

# Anonymous reference (position)
-> greet/1
  << "hello [@1]"

# Anonymous lambda
double = ->(x) x * 2
<< double.call(21)

# Pure function, auto-memoized (compiled)
fn fib(n)
  if n <= 1
    n
  else
    fib(n - 1) + fib(n - 2)

# Arity shorthand: args are @1, @2, … (compiled)
-> add/2
  @1 + @2

# Anonymous reference (@1.x)
-> distance/1
  << "hello [x' - x]"
```

## Blocks

```tungsten
# Inline block
[1, 2, 3].each ->(x) << x

# Implicit #each
[1, 2, 3] ->(x) << x * 2

# Free arg binding
[1, 2, 3] -> << x
[1, 2, 3] -> << i

# Multiline block with ->
[1, 2, 3].each ->(x)
  << x * 2

# Multiline block - implicit each
[1, 2, 3] ->(x)
  << x * 2

# Multiline block - implicit each
[1, 2, 3] ->
  << x * 2
```

## Control Flow

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

# While loop
while x > 0
  x -= 1

# Case with expression
value = 2
case value
  when 1
    << "one"
  when 2, 3
    << "two or three"
  else
    << "other"

# Case without expression (guard clauses)
y = 7
case
when y > 10
  << "big"
when y > 5
  << "medium"
else
  << "small"
```

## Classes

```tungsten
# + defines a class. The constructor binds @-args straight to fields;
# a trailing `ro` (read-only) or `rw` (read-write) generates accessors.
+ Dog
  -> new(@name, @breed) rw

  -> speak
    "woof from [@name]"

# Inheritance
+ Puppy < Dog
  -> speak
    "yip from [@name]"

d = Dog.new("Rex", "lab")
<< d.speak()
<< d.breed
d.name = "Max"

# Standalone accessor declarations also exist (compiled):
#   ro :name    rw :breed
```

Classes construct without `.new` too: `Dog("Rex", "lab")`.

## Traits

```tungsten
trait Greetable
  -> greet
    "Hello, I am [self.name]"

+ Person
  is Greetable
  -> new(@name) rw

<< Person.new("Alice").greet()   # (compiled)
```

## Collections

```tungsten
# Arrays — lambdas attach without parens
arr = [1, 2, 3, 4, 5]
<< arr.map ->(x) x * 2
<< arr.select ->(x) x > 3
<< arr.sum
<< arr.reduce(0, ->(a, b) a + b)   # (compiled)

# Blocks also bind `item` implicitly
<< arr.map -> item ** 2

# Hashes
h = {name: "Alice", age: 30}
<< h.keys
<< h.values

# Ranges
(1..10).each ->(i)
  << i
```


## Error Handling

```tungsten
-> risky_operation
  raise "boom"

begin
  risky_operation()
rescue e
  << "Error: [e]"
ensure
  << "cleanup"
```

## Built-in Types

- **Decimal**: `3.14` — bare fractional literals are **exact decimals**
  (`0.1 + 0.2 == 0.3` is `true`)
- **Float**: `~3.14` — machine floats are opt-in with `~`
- **Int**: `42`, `0xFF`, `0b1010`
- **String**: `"hello"`, with `[expr]` interpolation
- **Bool**: `true`, `false`
- **Nil**: `nil`
- **Symbol**: `:name`
- **Array**: `[1, 2, 3]`
- **Hash**: `{key: value}`
- **Range**: `1..10`, `1...10`
- **ByteArray**: `« ff 00 a5 »` (hex bytes)
- **StringBuffer**: `StringBuffer()` (mutable UTF-8 builder, `.append`, `.to_s`)
- **Currency**: `$3.50`, `25¢` — and percent literals: `price - 15%`
- **Quantity**: `5 kg`, `100 mph` (units with conversion: `1 acre | sqft`)
- **Date/Time**: `2024-01-15`, `14:30:00`
- **Duration**: `5m30s`

## Key Differences from Ruby/Python

1. `<<` prints (not `puts` or `print`)
2. `+` defines classes (not `class`)
3. `->` defines methods (not `def`)
4. `[ ]` for interpolation (not `#{ }`)
5. No `end` keywords — indentation-based
6. Bare decimals are exact; floats are opt-in with `~`
7. `fn` for pure, memoized functions
8. Built-in currency, units, dates, quantities
9. Trailing `ro`/`rw` on the constructor for accessors (not
   `attr_reader`/`attr_accessor`)

## Engines

Both engines share the same surface for everyday code:

| Path | Command |
| ---- | ------- |
| Quick run (tree-walk) | `bin/tungsten file.w` or `bin/tungsten -e '…'` |
| Native compile | `bin/tungsten -o out file.w && ./out` |

Supported under quick run: `fn`, `with`, duration literals, `@@` class vars,
standalone `ro`/`rw`, `StringBuffer.append`, `@1`/`@2`, classes, traits (local
bodies), pipelines, units, currency. Prefer compile for `@gpu fn`, full channel
/`go` concurrency edge cases, and maximum performance.

`implementations/c` and `implementations/ruby` are **bootstrap hosts only** —
they build the self-hosted compiler; they are not the product runtime.

## Tooling for agents

```bash
bin/tungsten start --agent          # this primer + absolute doc paths
bin/tungsten -c file.w              # syntax / lower check (exit code)
bin/tungsten --ast file.w           # AST dump
bin/tungsten --lex file.w           # tokens
bin/tungsten --ll file.w            # LLVM IR
TUNGSTEN_ERROR_FORMAT=json bin/tungsten -c file.w   # structured errors
bin/tungsten --explain E_PARSE_…    # lesson from doc/explain.md
```

Structured compile errors (internal hash and JSON export) include:
`code`, `message`, `file`, `row`, `col`, `span_length`.

**MCP / LSP:** `bits/tungsten-lsp/` — symbols, hover, definition, references,
completions, and `tungsten_diagnose`. Build with the monorepo bit build.

**Packages:** `bit install` vendors deps into `vendor/bits/`; `use` resolves
`vendor/bits` → `$BIT_HOME` → `bits/` automatically.

**Gotchas:** `doc/getting-started/06-gotchas.md` · **stdlib index:** `doc/CORE.md`
