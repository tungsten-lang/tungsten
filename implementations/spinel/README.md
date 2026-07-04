# Tungsten on Spinel

This directory is the parallel Spinel-backed stage0 experiment. It must not
patch files under `implementations/ruby`; anything Spinel-specific lives here.

## Layout

- `../../src/pristine/spinel/` - untouched local checkout of `matz/spinel`
- `../../src/pristine/ruby/` - untouched local checkout of upstream Ruby
- `../../src/patched/spinel/` - working copy for Spinel fixes used by this implementation
- `stage0/` - Tungsten stage0 preamble, shims, and entrypoint
- `scripts/` - bundle/build helpers
- `bin/` - command wrappers
- `build/` - generated bundle, C, and native binary

## Build

```sh
implementations/spinel/bin/build_stage0
```

By default this currently builds the narrow Spinel-native smoke runner. It is
deliberately small: it proves the Spinel path can produce a `tungsten-stage0`
binary and run a first set of Tungsten fixtures while the full Ruby interpreter
bundle is still being brought into Spinel's subset.

That creates:

- `implementations/spinel/build/tungsten_stage0_bundle.rb`
- `implementations/spinel/build/tungsten_stage0.c`
- `implementations/spinel/build/tungsten-stage0`

The first target is a tiny proof binary:

```sh
implementations/spinel/build/tungsten-stage0 compiler/test/fixtures/hello.w
```

Current smoke coverage:

```sh
implementations/spinel/bin/run_stage0 compiler/test/fixtures/hello.w
implementations/spinel/bin/run_stage0 compiler/test/fixtures/arithmetic.w
implementations/spinel/bin/run_stage0 compiler/test/fixtures/simple.w
implementations/spinel/bin/run_stage0 compiler/test/fixtures/variables.w
implementations/spinel/bin/run_stage0 compiler/test/fixtures/add.w
implementations/spinel/bin/run_stage0 compiler/test/fixtures/ifelse.w
implementations/spinel/bin/run_stage0 compiler/test/fixtures/while.w
```

The smoke runner is intentionally not a parser yet. It is a line-oriented
subset that supports `<<`, integer arithmetic, `x/y/z` assignments and `+=`,
one hardcoded `add(a, b)` shape, single-line `if/else`, and single-line
`while` loops.

The real target is the full flattened Ruby interpreter bundle:

```sh
SPINEL_STAGE0_FULL=1 implementations/spinel/bin/build_stage0
```

The currently compiling full-interpreter shell uses:

```sh
SPINEL_STAGE0_FULL=1 \
SPINEL_STAGE0_REAL_TOKEN=1 \
SPINEL_STAGE0_REAL_LEXER=1 \
SPINEL_STAGE0_REAL_PARSER=1 \
SPINEL_STAGE0_FULL_REAL_PARSER=1 \
SPINEL_STAGE0_REAL_ENV=1 \
SPINEL_STAGE0_REAL_LOADER=1 \
SPINEL_STAGE0_REAL_INTERPRETER=1 \
SPINEL_STAGE0_FULL_RUBY_INTERPRETER=1 \
implementations/spinel/bin/build_stage0
```

That path now generates C and links `build/tungsten-stage0`, but it still uses
compatibility stubs for large parts of parser/evaluator behavior.

The current stage0 calling convention is:

```sh
implementations/spinel/build/tungsten-stage0 compiler/tungsten.w compile compiler/tungsten.w
```

That emits `/tmp/tungsten/tungsten.ll` and links `/tmp/tungsten/tungsten-stage1`.
The resulting stage1 compiler has been smoke-tested by compiling
`compiler/test/fixtures/add.w` and running the produced binary.

## Current Strategy

The normal Ruby implementation is written for CRuby: `autoload`, many separate
`require`s, and dynamic runtime hooks. Spinel wants a whole-program Ruby input,
so the first step is to flatten the interpreter into a single source file and
compile that.

The order of attack is:

1. Conform the generated stage0 Ruby bundle to the Ruby subset Spinel already
   compiles well.
2. Keep those source-shaping changes under `implementations/spinel`.
3. Patch `../../src/patched/spinel` only when a limitation is impractical to
   avoid in the stage0 bundle or is clearly a Spinel codegen bug.

The patched Spinel checkout also has a small Tungsten runtime intrinsic probe:
Ruby calls named `__w_int(...)` and `__w_to_i64(...)` lower directly to
`w_int(...)` and `w_to_i64(...)`. When those intrinsics are present, generated C
includes `runtime.h`; `bin/build_stage0` then links the Tungsten runtime C
objects beside Spinel's own runtime archive.

The bundle generator deliberately reads from `implementations/ruby` without modifying
it. When Spinel needs compatibility shims or narrower stage0 behavior, add those
under `implementations/spinel/stage0` and include them in the generated bundle.
