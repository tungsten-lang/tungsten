# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What Tungsten is

Tungsten is an object-oriented programming language — "pseudocode that runs":
no `end` or braces, and blocks close by dedent. It is
**self-hosted** — the compiler in `compiler/tungsten.w` is itself a Tungsten
program.

Compilation has two codegen targets. Most code lowers through a Tungsten-IR
layer called **WIRE** to LLVM IR, which clang turns into a native binary.
Functions annotated `@gpu fn` take a parallel path through
`compiler/lib/metal_emitter.w` to Metal Shading Language (MSL), which
`xcrun metal` compiles into a Metal binary. The Metal pass is wired in at
lowering (`lowering/definitions.w` hands `@gpu fn` defs to the emitter
instead of producing LLVM); current v0 is MSL-only — see
`doc/gpu-dialects.md` for the planned multi-dialect expansion.

```
                                ┌→ WIRE → LLVM IR → clang → native binary
Source → Lexer → Parser → AST ──┤
                                └→ metal_emitter → MSL → xcrun metal (@gpu fn)
```

## Bootstrap (the central build concern)

Because the compiler is written in Tungsten, building it needs a host
implementation to run the compiler source and produce the first self-hosted
compiler (stage 1); some hosts need a stage 0 of their own first, depending on
how they are implemented. Three implementations exist, selected at build time:

- `implementations/c/` — C bytecode VM (the **default**; fastest bootstrap).
  Parses to a typed AST in a bump arena, lowers to bytecode, dispatches via a
  computed-goto loop — see `implementations/c/include/tc.h` and `src/vm.c`.

- `implementations/ruby/` — Ruby tree-walking interpreter (`--ruby`).

- `implementations/spinel/` — alternate C-based stage 0 (`--spinel`). Not
  yet working and slow.

All three are front-ends to the *same* `.w` language. The build runs two
stages and checks that **stage 1 and stage 2 emit byte-identical `.ll`** —
proof the freshly built compiler reproduces itself (self-hosts to a fixed
point). Any compiler change must keep that check passing; for non-trivial
work, save a baseline `.ll` first and round-trip against it afterward.

## Commands

```bash
# Build the self-hosted compiler (C VM bootstrap by default)
bin/tungsten build
bin/tungsten build --force      # ignore cached stage binaries
bin/tungsten build --ruby       # bootstrap stage 1 via the Ruby interpreter
bin/tungsten build --spinel     # bootstrap via Spinel stage 0 (instead of the C VM)
bin/tungsten build -0           # build stage 0 (spinel or C VM)
bin/tungsten build -1           # build stage 1
bin/tungsten build -2           # build stage 2, re-use stage 1
bin/tungsten build --pgo        # build compiler with profile-guided optimization
bin/tungsten build --no-bits    # skip compiling bit entry points (implied by -0/-1/-2)
bin/tungsten build --help       # all options

# Run / inspect .w files
bin/tungsten file.w             # run
bin/tungsten -e "<< 1 + 1"      # eval an expression
bin/tungsten -c file.w          # syntax-check only
bin/tungsten --lex file.w       # print tokens
bin/tungsten --ast file.w       # print the AST
bin/tungsten --ll file.w        # print LLVM IR
bin/tungsten -o out file.w      # compile to a native binary
bin/tungsten --ruby file.w      # run via the Ruby interpreter (no compile)
bin/tungsten --repl             # interactive REPL
bin/tungsten --clear-cache      # clear all .memo (incremental compile) cache files
```

Ruby gem (run from `implementations/ruby/`):

```bash
bundle exec rake                          # default task — all tests
bundle exec rspec spec/lexer_spec.rb      # one spec file
bundle exec rspec spec/parser_spec.rb:42  # one example, by line number
bundle exec rake expensive                # slow specs (files ending _expensive.rb)
bundle exec rubocop                       # lint
bin/tungsten-console                      # interactive Tungsten REPL (via the Ruby gem)
bundle exec rake console                  # Ruby console (Pry) with Tungsten loaded
```

The Ruby implementation uses double-quoted strings, 120-char lines, Ruby ≥ 2.6.

Programmatic entry into the Ruby interpreter is `Tungsten::Parser.parse(code)`
(or `Tungsten.parse(code)`). Spec helper
`implementations/ruby/spec/support/to_node.rb` builds AST nodes for assertion
matching (`.int`, `.var`, `.call`, …).

`TUNGSTEN_FREE` (default on) controls compile-time `free` insertion for
non-escaping heap values; set `TUNGSTEN_FREE=0` to disable.

## Repository layout

- `compiler/` — the self-hosted compiler. `tungsten.w` is the entry point;
  `compiler/lib/` holds its modules (`lexer`, `parser`, `ast`, `cfg`,
  `lowering`, `emitter`, `environment`, …).
- `core/` — the Tungsten standard library (`.w` files). `core/tungsten.w` is
  its manifest (see below); `core/traits/` holds traits.
- `lib/` — additional Tungsten library code, organized as `base/`, `core/`,
  `ext/`, `tungsten/`, with a `tungsten.w` orchestrator.
- `runtime/` — C runtime that compiled Tungsten binaries link against. Much
  more than a GC core: platform event loops (`event_kqueue.c` /
  `event_iouring.c` / `event_epoll.c`), HTTP/2 and HTTP/3 (`http2.c` /
  `http3.c`), TLS, Apple Metal (`metal.m`) and MLX (`mlx_bridge.c`) bridges,
  plus precomputed lexer character tables consumed by a SIMD lexer (see
  `runtime/SIMD_LEXER.md`).
- `implementations/{c,spinel,ruby}/` — the three bootstrap host VMs.
- `languages/` — lexers/parsers for other languages (`json/`, `ruby/`, `c/`,
  `openai/`, `archive/`, `tungsten/`), themselves written in Tungsten. Each
  carries a `lexer.w`, optional SIMD variants, and precomputed
  `*.lex{16,32,64}` table files.
- `bin/` — CLI entry points (`tungsten`, `tungsten-compiler`, `wit`).
- `spec/` — `.w` test files exercising language features.
- `doc/` — language specification (`doc/specification/`), guides, examples,
  and rosetta-code solutions.

## The `.w` language

Editing `core/` or `compiler/` requires the surface forms:

- `+ Name` / `+ Name < Parent` — class definition, optionally with a superclass.
- `trait Name` — trait definition. Inside a trait, `with OtherTrait` composes
  in another trait.
- `is TraitName` — indented in a class body; declares the class conforms to a
  trait and must supply the methods that trait requires.
- `-> name` / `-> name/N` — method definition. `N` is the arity; arguments are
  `@1`, `@2`, …. `-> name(@x, @y)` binds arguments straight to instance fields.
- A `-> name` with **no body** is an abstract/interface declaration — the
  implementation comes from a concrete subclass or an intrinsic. The numeric
  stdlib relies on this heavily.
- `- data` introduces a typed memory-layout block; `ro`/`rw`/`field`/`readonly`
  declare fields.

Conventions: 2-space indent, double-quoted strings, snake_case methods,
PascalCase classes, blocks closed by dedent.

## Standard library: the autoload manifest

`core/tungsten.w` defines `+ Tungsten`, whose body is an
`auto :ClassName, "relative/path"` table of lazily autoloaded stdlib classes
and traits (e.g. `auto :Comparable, "traits/comparable"`). **A new stdlib
class or trait is invisible until it is registered in this table** — when
adding a file to `core/`, add the matching `auto` line.

## Module-split pattern

Large compiler modules are split into a thin orchestrator (`<module>.w`) plus
a sibling `<module>/` directory of worker submodules. `compiler/lib/lowering.w`
+ `compiler/lib/lowering/*.w` (`pass_registry`, `types`, `analysis`,
`monomorphize`, `literals`, `ops`, `blocks`, `control_flow`, `calls`,
`definitions`) is the canonical example. When working in such a module:

- The first worker is a **dispatch shim** (e.g. `pass_registry.w`) holding the
  case-statement dispatchers and shared helpers. It imports no other worker,
  which breaks the orchestrator↔worker dependency cycle.
- Submodules carry **no `use` directives** — from inside
  `compiler/lib/<module>/`, `use wire` would resolve to a nonexistent sibling.
  Cross-references resolve through the flat top-level namespace once the
  orchestrator's `use` block merges the workers.
- The orchestrator's `use` order **is** the dependency chain: each worker may
  only reference symbols defined in earlier workers. Aim for ~500–1800 lines
  per worker and a small orchestrator. `make lowering-graph` prints lowering's
  chain (its Makefile recipe is literally `grep '^use lowering/'
  compiler/lib/lowering.w` — a faithful echo of the convention).

## How to work here

- **Work autonomously**: given a bug report or a failing test, fix it — point at
  the logs, errors, and failing tests, then resolve them without asking for
  hand-holding. Deciding when to enter plan mode is the user's call, not yours.
  If something goes sideways, stop and rethink before pushing on.
- **Use subagents liberally**: offload research, exploration, and parallel
  analysis to keep the main context clean. One focused task per subagent; throw
  more compute at hard problems by fanning out.
- **Be thorough**: when the marginal cost is low, do the complete thing rather
  than the minimal thing (boil the lake), and fix root causes, not symptoms.
- **Verify before done**: never mark a task complete without proving it works —
  run the tests, check the logs, and diff behavior against `main` when relevant.
  Ask "would a staff engineer approve this?"
- **Track and explain**: use TaskCreate for non-trivial work, mark items done as
  you go, and give a high-level summary at each step.
- **Learn from corrections**: after a correction from the user, capture the
  pattern as a `feedback` memory (see the memory system) and write yourself a
  rule that prevents the repeat; iterate until the mistake rate drops.

## gstack
Use /browse from gstack for all web browsing. Never use mcp__claude-in-chrome__* tools.
Available skills: /office-hours, /plan-ceo-review, /plan-eng-review, /plan-design-review,
/design-consultation, /design-shotgun, /design-html, /review, /ship, /land-and-deploy,
/canary, /benchmark, /browse, /open-gstack-browser, /qa, /qa-only, /design-review,
/setup-browser-cookies, /setup-deploy, /setup-gbrain, /sync-gbrain, /retro, /investigate,
/document-release, /document-generate, /codex, /cso, /autoplan, /pair-agent, /careful, /freeze,
/guard, /unfreeze, /gstack-upgrade, /learn.

## Core Principles
- **Simplicity first**: make every change as simple as possible; touch minimal code.
- **No workarounds**: when you find a bug, fix the bug — don't reshape the
  calling code to avoid triggering it. If the parser mishandles a bare array
  literal, fix the parser; don't rewrite the array to use a temp variable. A
  simple fix that leaves the bug is not a fix. The only acceptable workarounds
  are a temporary one carrying a TODO that names the root cause, or one the user
  explicitly requests.
- **Demand elegance**: for non-trivial changes, pause and ask "is there a more
  elegant way?" If a fix feels hacky, treat it as a bug and challenge your own
  work before presenting it.
- **Minimal impact**: changes should only touch what's necessary; avoid
  introducing bugs.

When in doubt, follow the principles at uncertainlight.com.

## Skill routing

When a request clearly matches an available skill, prefer invoking it with the
Skill tool over an ad-hoc answer — the skill's workflow produces better results.
Use judgment: answer direct questions and quick lookups yourself rather than
forcing them through a skill.

Key routing rules:
- Product ideas, "is this worth building", brainstorming → `/office-hours`
- Bugs, errors, "why is this broken", 500 errors → `/investigate`
- Ship, deploy, push, create PR → `/ship`
- QA, test the site, find bugs → `/qa`
- Code review, check my diff → `/review`
- Update docs after shipping → `/document-release`
- Weekly retro → `/retro`
- Design system, brand → `/design-consultation`
- Visual audit, design polish → `/design-review`
- Architecture review → `/plan-eng-review`
