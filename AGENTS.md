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

The stages are compiled from the checkout root by a relative entry path with
`TUNGSTEN_ROOT` unset, so the compiler names its own sources relatively
(`compiler/lib/lexer.w`) and its bytes do not depend on where the checkout is.
That is what lets every worktree with the same sources share one build of each
stage through the build store (see "Build store").

`build --ruby` has no stage 0: the Ruby implementation runs
`compiler/tungsten.w` directly to produce stage 1. `build --spinel` compiles
the Ruby implementation to C with Spinel and uses that binary as stage 0. Both
are maintainer options, and Spinel is experimental and incomplete.

### The stage-identity check

The build compares the `.ll` that stages 1 and 2 emit; matching output proves
the compiler reproduces itself. A match prints
`VERIFIED stage 1 .ll == stage 2 .ll`. What a mismatch does depends on who is
building:

- A plain local build prints `WARNING`, still installs stage 2, and still ends
  with `==> Done` and exit 0, so read the output, not the exit code. (A
  two-step bootstrap change needs an installed compiler to take its second
  step.)
- A strict build prints `ERROR`, installs nothing, and exits 1. Strict means
  `CI` is set (to anything but empty, `0` or `false`), or the build was given
  `--strict`, `--install`, `--pgo`, `--target` or `--portable`.
  `scripts/install.sh`, the `Dockerfile` and the release workflow pass
  `--strict`.

Both print the two modules' paths; the pair usually stays in
`/tmp/tungsten-build-<pid>/ll/` for diffing.

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
bin/tungsten build --strict             # a stage-identity mismatch fails the build
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
bin/tungsten -o out --release file.w    # full LTO, no dev checks (--no-lto opts out)
bin/tungsten --clear-cache              # drop this checkout's incremental binaries and all snapshots
bin/tungsten cleanup                    # sweep the build store now (`--all` empties it)
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

## Build store

Reusable build artifacts live in one store shared by every checkout, worktree
and installed toolchain: `~/.tungsten/build` (`TUNGSTEN_HOME/build`), or
`TUNGSTEN_BUILD_STORE`. A checkout has no `build/cache` of its own.

```text
compile/     the compiler's artifacts: runtime archives and companion objects,
             incremental binaries (irbin, linkbin, run/), parse and Core snapshots
stages/      stage-0 VMs, stage-1/2 compilers with their .ll, build runtime archives
compilers/   finished compilers, their repl/metal images, by-source/ index
bits/        bit executables
```

- Every entry's name is a fingerprint of what determines its bytes. What is
  shared between checkouts is keyed by content (runtime objects by every file
  in `runtime/`, stages and compilers by the compiler sources, bits by a
  manifest of each source file the compiler read plus the compiler binary) and
  is built so its bytes do not name the checkout: stages, images and
  in-checkout bits are compiled from the root, by relative path, with
  `TUNGSTEN_ROOT` unset. What embeds absolute paths by design (a program's
  incremental binary, anything using `__DIR__`) is keyed by those paths.
- A compiler switch in the environment (`TUNGSTEN_FREE=0`, `TUNGSTEN_DEFINES`,
  any `TUNGSTEN_*` that is not a location or a store/GC knob) is part of the
  stage, image and bit keys, so a build made under one gets its own entries
  and is never handed to a plain build (`bin/commands/store.sh
  tuning-environment` prints what counts).
- `bin/tungsten-compiler`, `build/compiler-images/` and each bit's `bin/` are
  copies of store entries; `build/compiler-build.profile` records what is
  installed. A new worktree gets the compiler the store holds for exactly its
  sources (post-checkout hook, `bin/commands/store.sh install-compiler`), or
  none: then `bin/tungsten build` builds it, reusing every stage that matches.
- `TUNGSTEN_CACHE_DIR=DIR` replaces `compile/` for one run (the spec and
  parity suites isolate themselves this way). `TUNGSTEN_BUILD_STORE=DIR`
  moves the whole store: use an empty one to verify a build from nothing.
- Writers publish with a temp file and a rename, the member a reader checks
  for completeness last; a complete bit or image entry is never replaced (two
  builds of one key may differ in layout, and executable and sidemap must come
  from one build), except by `--force`. Readers renew what they use;
  `bin/commands/cache_gc.sh` removes only entries unused for 7 days, or the
  least recently used ones above 20 GB, and an LTO object bundle (a directory
  with `.ready`) only whole.
- When you add an artifact kind, decide what its name must cover before
  choosing where it goes, and add it to `scripts/test-build-store.sh`.

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
  (`runtime/SIMD_LEXER.md`). `runtime/sources.txt` is the one list of its
  translation units, read by every build of the runtime (the compiler's
  links, `build.w`, `bootstrap.sh`, `runtime/Makefile`, wasm): a new runtime
  file is a line there, and `scripts/test-runtime-sources.sh` fails until it
  is.
- `implementations/`: the bootstrap hosts `c/`, `ruby/`, and `spinel/`.
- `languages/`: lexers for other languages, written in Tungsten, with
  precomputed `.lex16`, `.lex32`, and `.lex64` tables.
- `bits/`: Tungsten packages, such as `tungsten-lsp`, `tungsten-wassat`,
  `tungsten-metaflip`, and `tungsten-rung`.
- `bin/`: `tungsten` (the CLI), `tungsten-compiler` (the installed stage 2),
  `wit` (the REPL), `bit` (package manager), `rung` (model-ladder improver),
  and `commands/` (build and bootstrap).
- `spec/`: `.w` specs. `scripts/`: test and maintenance scripts.
- `benchmarks/`; `wasm/`, the wasm32 build of the interpreter; `apps/`, the
  docs site and other apps.
- `doc/`: the language specification (`doc/specification/`), guides, and
  examples.

## Rung (model-ladder improver)

`rung` (`bits/tungsten-rung`, invoked via `bin/rung` or `bin/tungsten rung`;
full guide in `bits/tungsten-rung/README.md`) runs a Markdown prompt file up a
ladder of models (`codex`, `agy`, `grok`, `muse`, `claude`, `ollama:<model>`).
After every step, an integrator model merges the step's answer(s) into
`state.md` and records a verdict (`improved`, `credit`, `changed`, `verify`)
until a full round plateaus or reaches `--max-rounds`.

```bash
bin/rung task.md                              # default ladder: codex, agy, grok, claude
bin/rung -m "codex | grok" -r 1 task.md       # run codex and grok in parallel + integrator
bin/rung models                               # check installed / signed-in models
bin/rung check task.md                        # validate registry, guard, and staged files
bin/rung --dry-run task.md                    # write plan and first prompts without calling models
bin/rung --resume task.rung/STAMP             # resume an interrupted or paused run
```

Prompt files use optional YAML front matter followed by the Markdown task:

```markdown
---
models: codex | grok
integrator: claude
stage:
  - README.md
  - src/**/*.w
timeout: 1800
max_rounds: 2
deliverable: |
  One Markdown note with concrete improvements, file/line references, and verification steps.
---
# Task title

Review the staged files and propose high-leverage improvements...
```

- **Ladder syntax (`models` / `-m`, `integrator` / `-i`):** `,` separates
  sequential steps; `|` joins models into one parallel step whose answers are
  merged together in a single integrator call.
- **Read-only safety:** `rung` only orchestrates text (`state.md` and
  `report.md` under `TASK.rung/STAMP/`). Staged files (`stage` / `files`,
  relative to the prompt file) are copied into each call's workdir with mode
  `0444`, and all built-in model commands run in read-only/plan mode.

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
