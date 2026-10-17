# AGENTS.md

Guidance for Claude Code, Codex, and other agents working in this repository.
This file covers working in the repo. For writing Tungsten code, read
`doc/TUNGSTEN_FOR_LLMS.md`.

## What is Tungsten?

Tungsten is an object-oriented programming language for scientists and
mathematicians: "pseudocode that runs". It has significant whitespace: like
Python, it uses indentation to delimit scope. It is self-hosted: the compiler
and its interpreter are written in Tungsten.

```text
                                ┌→ interpreter (run --interpret, REPL)
Source → Lexer → Parser → AST ──┼→ WIRE → LLVM IR → clang → native binary / wasm32
                                └→ metal_emitter → MSL / CUDA / WGSL (@gpu fn)
```

`bin/tungsten file.w`, `run`, `-e`, and `-o` all compile through WIRE, the
compiler's own IR. Bare runs exec a cached binary, and the tree-walking
interpreter is opt-in. The Ruby implementation (`--ruby`) is a separate
implementation of the same language and the fallback before a compiler is
built. GPU dialect options are in `doc/gpu-cuda.md`, and the wasm32 build lives
in `wasm/`.

A language change must behave the same in the compiler, the interpreter, and
the Ruby implementation.

## Bootstrapping the compiler

The compiler is written in Tungsten, so something else has to run it the first
time.

- stage 0: a bootstrap-only interpreter the build compiles from C, by default
  the C VM in `implementations/c`. It implements just enough Tungsten to run
  `compiler/tungsten.w`, and runs it once to produce stage 1.
- stage 1: the compiler stage 0 produces. A normal build uses it only to build
  stage 2.
- stage 2: the compiler stage 1 builds from the same sources, installed as
  `bin/tungsten-compiler`.

`build --ruby` has no stage 0: the Ruby implementation runs
`compiler/tungsten.w` directly to produce stage 1. `build --spinel` compiles
the Ruby implementation to C with Spinel and uses that binary as stage 0. Both
are maintainer options, and Spinel is experimental and incomplete.

### The stage-identity check

The build compares the `.ll` that stages 1 and 2 emit; matching output proves
the compiler reproduces itself. A match prints
`VERIFIED stage 1 .ll == stage 2 .ll`. A mismatch prints `WARNING`, still
installs stage 2, and still ends with `==> Done`, so read the output, not the
exit code. The pair usually stays in `/tmp/tungsten-build-<pid>/ll/` for
diffing.

Before changing `compiler/`, `core/`, `languages/tungsten/lexers/`,
`data/unit_names.txt`, or `data/units.tsv`, build a clean checkout of HEAD and
note which line it prints. After your change the build must print the same
line.

## Commands

```bash
bin/tungsten bootstrap                  # fresh clone: stages 0-2, install, bits
bin/tungsten build                      # rebuild the compiler (needs one installed)
bin/tungsten build --force              # ignore cached stages
bin/tungsten build -1                   # build and install stage 1 only
bin/tungsten build -2                   # reuse stage 1, build stage 2
bin/tungsten build --no-bits            # skip bit entry points (implied by -1/-2)
bin/tungsten build --help               # all options, incl. --pgo, --ruby, --spinel

bin/tungsten file.w                     # compile through WIRE and run
bin/tungsten run --interpret file.w     # run on the tree-walking interpreter
bin/tungsten --ruby file.w              # run on the Ruby implementation
bin/tungsten -e "<< 1 + 1"              # evaluate an expression
bin/tungsten -c file.w                  # parse and lower, no codegen; reports type errors
bin/tungsten --lex file.w               # print tokens
bin/tungsten --ast file.w               # print the AST
bin/tungsten --ll file.w                # print LLVM IR
bin/tungsten -o out file.w              # compile a binary (-O3, no LTO)
bin/tungsten -o out --release file.w    # full LTO, no dev checks
bin/tungsten --clear-cache              # delete incremental-compile caches
bin/wit                                 # REPL (same as bin/tungsten console)
```

Benchmark only `--release` builds. `--dev` builds are `-O0`, which does not
just slow code down but reorders algorithm rankings: branchless kernels lose
4-6x while simple loops lose about 2x.

`TUNGSTEN_FREE=0` disables the `free` calls the compiler inserts for
non-escaping heap values, which helps rule out ownership bugs.

The Ruby implementation has its own tooling, run from `implementations/ruby/`:

```bash
bundle exec rspec spec/lexer_spec.rb      # one spec file
bundle exec rspec spec/parser_spec.rb:42  # one example
bundle exec rake expensive                # slow specs (*_expensive.rb)
bundle exec rubocop                       # lint: double quotes, 120 columns
```

In Ruby specs, `Tungsten.parse(code)` returns the AST, and
`spec/support/to_node.rb` builds expected nodes (`.int`, `.var`, `.call`).

## Testing

- While working locally, run only the focused specs and checks for the files or
  behavior you changed. Do not run the full root `rake` suite locally; CI runs
  it. Broaden coverage only to diagnose a failing focused check.
- Run one `.w` spec compiled with `bin/tungsten spec/path_spec.w`, and
  interpreted with `bin/tungsten run --interpret spec/path_spec.w`. Run a
  semantic change on every engine it affects.
- A new `spec/**/*_spec.w` runs on both engines automatically, and
  `spec/parity/` specs run as cross-engine parity checks. To restrict or skip
  one, add a line such as `# spec: compiled -- why` or `# spec: skip -- why`
  to its top comment block; the words are listed at the top of
  `scripts/spec-lanes.sh`.

## Repository layout

- `compiler/`: the self-hosted compiler. `compiler/tungsten.w` is the entry
  point, and `compiler/lib/` holds its modules.
- `core/`: the standard library. `core/tungsten.w` is its autoload manifest.
- `runtime/`: the C runtime compiled programs link against: GC, event loops,
  HTTP/2 and HTTP/3, TLS, Metal and MLX bridges, and the SIMD lexer tables
  (`runtime/SIMD_LEXER.md`).
- `implementations/`: the bootstrap hosts `c/`, `ruby/`, and `spinel/`.
- `languages/`: lexers for other languages, written in Tungsten, with
  precomputed `.lex16`, `.lex32`, and `.lex64` tables.
- `bits/`: Tungsten packages, such as `tungsten-lsp`, `tungsten-wassat`, and
  `tungsten-metaflip`.
- `bin/`: `tungsten` (the CLI), `tungsten-compiler` (the installed stage 2),
  `wit` (the REPL), and `commands/` (build and bootstrap).
- `spec/`: `.w` specs. `scripts/`: test and maintenance scripts.
- `benchmarks/`; `wasm/`, the wasm32 build of the interpreter; `apps/`, the
  docs site and other apps.
- `doc/`: the language specification (`doc/specification/`), guides, and
  examples.

## Writing `.w` in this repo

`doc/TUNGSTEN_FOR_LLMS.md` is the language reference. Conventions here:

- 2-space indent, double-quoted strings, snake_case methods, PascalCase
  classes.
- Tungsten is not Ruby: never hand-write a trivial accessor (`-> name` whose
  body is `@name`). Declare it at class level with `ro :name`, or `rw :name`
  for a getter and setter. Both expand to the same methods on every engine.
- A `-> name` with no body is abstract: a subclass or an intrinsic supplies the
  implementation. The numeric library relies on this heavily.
- `- data` in a class body declares its memory layout, as typed C fields
  (`u32 size`) or `ro`/`rw` fields.

### The autoload manifest

A new `core/` class or trait is invisible until `core/tungsten.w` registers it
with an `auto` line, such as `auto :Comparable, "traits/comparable"`. Then
regenerate `doc/CORE.md` with `rake doc:core`; `rake check:core_doc` fails when
it is stale.

### Module-split pattern

Large compiler modules (`emitter`, `interpreter`, `lexer`, `lowering`,
`metal_emitter`, `parser`) are a thin orchestrator, `compiler/lib/<module>.w`,
plus worker files in `compiler/lib/<module>/`. In those modules:

- The orchestrator's `use` order is the dependency chain: a worker may only
  reference symbols from workers above it. `make lowering-graph` prints
  lowering's chain.
- The first worker is a dispatch shim, such as lowering's `pass_registry.w`. It
  holds the case dispatchers and shared helpers and uses no other worker, which
  breaks the orchestrator-worker cycle.
- `use` resolves relative to the file's own directory, so a worker cannot
  `use wire`. Top-level modules reach workers through the orchestrator's `use`
  block.
- Aim for 500-1800 lines per worker.

## How to work here

- **Work autonomously.** Given a bug report or a failing test, find the cause
  in the logs, errors, and tests, and fix it without asking for hand-holding.
- **Fix the root cause.** When you find a bug, fix the bug; don't reshape the
  calling code to avoid it. If the parser mishandles a bare array literal, fix
  the parser instead of rewriting the array into a temp variable. The only
  acceptable workaround is a temporary one with a TODO naming the root cause,
  or one the user asks for.
- **Finish the task, and only the task.** Cover every call site and engine the
  change affects, and leave unrelated code alone. Prefer the simplest change
  that does that. If a fix feels hacky, treat it as a bug and rework it before
  presenting it.
- **Verify before calling it done.** Run the focused specs for what you
  changed. For `compiler/` or `core/` changes, the build must print the same
  stage-identity line as the baseline. Before calling something a regression,
  reproduce it at the merge base.
- **Track long work.** Mark items done as you go, and put status notes in the
  same message as the next action. For work that outlasts a session, keep the
  checklist in a file and tick it there.

When in doubt, follow the principles at uncertainlight.com.
