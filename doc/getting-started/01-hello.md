# 01 — Hello

Install Tungsten, print something, and learn the difference between **running**
and **compiling**.

← [Index](README.md) · Next: [02 — Syntax](02-syntax.md) →

---

## Install

**One-line install** (macOS or Linux):

```bash
curl -fsSL https://tungsten-lang.org/install | sh
```

**Or build from source:**

```bash
git clone https://github.com/tungsten-lang/tungsten
cd tungsten
bin/tungsten doctor          # check git, clang, LLVM, make, ruby
bin/tungsten bootstrap       # stage-1 compiler (C VM, no Ruby)
bin/tungsten build           # full self-host: stage1+stage2 + bits
```

`bin/tungsten bootstrap` is the fresh-clone path (stage 1 only, bash).  
`bin/tungsten build` still builds stage 1 as before, then stage 2 (byte-identical IR) and bits. It
builds stage 1 and stage 2 of the compiler and checks that they emit
**byte-identical LLVM IR** — proof the compiler self-hosts to a fixed point.

On Windows, use [WSL2](../WSL2.md), then follow the Linux steps.

---

## Your first program

Tungsten source files use the `.w` extension.

```tungsten
# hello.w
<< "hello world"
```

```bash
bin/tungsten hello.w
# => hello world
```

`<<` is print-with-newline (like `puts` in Ruby or `print` in Python). That is
the usual way to write to stdout.

A matching example already lives in the repo:

```bash
bin/tungsten doc/examples/01-basics/hello.w
```

---

## One-liners with `-e`

Evaluate an expression without a file:

```bash
bin/tungsten -e '<< 1 + 1'                 # => 2
bin/tungsten -e '<< "hello world"'         # => hello world
bin/tungsten -e '<< $3.50 - 25¢'           # => $3.25
```

Useful for trying a literal or operator before putting it in a file.

---

## Print forms

| Form | Meaning |
| ---- | ------- |
| `<< x` | Print `x` followed by a newline |
| `<< a, b` | Print each value on its own line |
| `<- x` | Print `x` **without** a trailing newline |
| `<! x` | Raise / throw `x` (error shorthand) |

```tungsten
<- "no newline"
<< " … now a newline"

# Suffix modifiers work on print statements
i = 4
<< i /= 2 while i > 0
```

---

## Run vs compile

`bin/tungsten` has two main ways to execute code:

| Command | What happens |
| ------- | ------------ |
| `bin/tungsten file.w` | **Quick run** — interprets (or picks a fast path). Good for scripts and examples. |
| `bin/tungsten -o out file.w` | **Compile** to a native binary via LLVM → clang. Most complete engine. |
| `bin/tungsten -e '…'` | Eval a one-liner (quick path). |
| `bin/tungsten --ruby file.w` | Force the Ruby tree-walking interpreter. |

```bash
# Quick run
bin/tungsten hello.w

# Native binary
bin/tungsten -o hello hello.w
./hello

# Optimized native build
bin/tungsten -o hello --release --native hello.w
```

Most of this tutorial's snippets work under quick run. A few constructs —
`fn` pure functions, `@1`/`@2` arity args, trait dispatch, some accessors —
need the **compiled** path. They are marked *(compiled)* in later pages and
collected in [06 — Gotchas](06-gotchas.md).

---

## Inspect without running

```bash
bin/tungsten -c file.w        # syntax-check only → "200 OK"
bin/tungsten --lex file.w     # print tokens
bin/tungsten --ast file.w     # print the AST
bin/tungsten --ll file.w      # print LLVM IR (no execute)
bin/wit                       # interactive REPL (or: bin/tungsten console)
```

---

## Strings and interpolation (preview)

String interpolation uses square brackets, not `#{}` or `f""`:

```tungsten
name = "world"
<< "hello [name]"            # => hello world
<< "2 + 2 = [2 + 2]"         # => 2 + 2 = 4
```

Full string and collection syntax is in [02 — Syntax](02-syntax.md).

---

## Checklist

- [ ] `bin/tungsten doctor` is clean
- [ ] `bin/tungsten bootstrap` (or `build`) finished (from source)
- [ ] `bin/tungsten -e '<< 1 + 1'` prints `2`
- [ ] You can print with `<<` and know when to use `-o`

Next: **[02 — Syntax](02-syntax.md)**
