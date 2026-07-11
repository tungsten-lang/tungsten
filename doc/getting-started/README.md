# Getting Started with Tungsten

Tungsten is an object-oriented language that reads like the pseudocode in your
notebook: no `end`, no braces, blocks close by **dedent**. It is self-hosted —
the compiler is itself a Tungsten program — and runs on macOS and Linux.

This path walks you from install to the distinctive surface forms, then the
gotchas that trip people up in real programs.

## Learning path

| Step | Topic | What you'll learn |
| ---- | ----- | ----------------- |
| [01 — Hello](01-hello.md) | Install & first run | Build, `<<` print, `-e`, run vs compile |
| [02 — Syntax](02-syntax.md) | Everyday language | Variables, control flow, functions, strings, collections |
| [03 — OOP](03-oop.md) | Objects | `+ Class`, `->` methods, inheritance, traits |
| [04 — Literals & units](04-literals-and-units.md) | Domain literals | Currency, `%`, units, unicode math, dates |
| [05 — Novelties](05-novelties.md) | Distinctive surface | Dedent, pipelines, swap, `fn` memo, arity `@1` |
| [06 — Gotchas](06-gotchas.md) | Pitfalls | `Int` vs `## i64`, engines, free insertion, GPU subset |

Read them in order the first time. After that, [06 — Gotchas](06-gotchas.md) is
the page you will reopen most.

## One-line taste

```bash
# Install (macOS or Linux)
curl -fsSL https://tungsten-lang.org/install | sh

# Or from a clone
bin/tungsten bootstrap   # stage 1 (no Ruby)
bin/tungsten build       # full self-host + bits
bin/tungsten -e '<< 1 + 1'          # => 2
```

```tungsten
# Pseudocode that runs
<< "hello world"

price = $499.99
<< price - 15%                       # => ≈$424.99

+ Point
  -> new(@x, @y) ro
  -> distance/1
    √(Δx² + Δy²)

<< Point(3, 4).distance(Point(0, 0)) # => 5
```

## Runnable examples in the repo

Companion `.w` files live under [`doc/examples/`](../examples/):

| Path | Covers |
| ---- | ------ |
| [`01-basics/`](../examples/01-basics/) | hello, variables, functions |
| [`02-data/`](../examples/02-data/) | arrays, hashes |
| [`03-oop/`](../examples/03-oop/) | classes, traits |
| [`04-ai-native/`](../examples/04-ai-native/) | token density sketch |
| [`rosetta_code/`](../examples/rosetta_code/) | many small task ports |

```bash
bin/tungsten doc/examples/01-basics/hello.w
bin/tungsten doc/examples/02-data/arrays.w
# Some OOP / pure-fn examples need the native path — see 06-gotchas.md
bin/tungsten -o /tmp/classes doc/examples/03-oop/classes.w && /tmp/classes
```

## Orientation commands

```bash
bin/tungsten start           # map of the language + next steps
bin/tungsten start --agent   # same, for coding agents
bin/tungsten doctor          # check clang, LLVM, Ruby
bin/wit                      # interactive REPL (or: bin/tungsten console)
```

## Related docs

| Doc | Audience |
| --- | -------- |
| [README.md](../../README.md) | Install, flags, showcase snippets |
| [TUNGSTEN_FOR_LLMs.md](../TUNGSTEN_FOR_LLMs.md) | Dense surface reference for agents |
| [TUNGSTEN.md](../TUNGSTEN.md) | Man-page style overview |
| [WVALUE.md](../WVALUE.md) | Runtime value tagging (NaN-boxing) |
| [specification/](../specification/) | Formal language spec |
| [articles/tungsten-performance-engineering.md](../articles/tungsten-performance-engineering.md) | Why `## i64` matters on hot paths |

Next: **[01 — Hello](01-hello.md)**
