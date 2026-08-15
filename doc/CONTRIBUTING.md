# Contributing to Tungsten

Tungsten is self-hosted: the compiler is written in Tungsten, and a complete
build must prove that stage 1 and stage 2 emit byte-identical LLVM IR. Please
keep that fixed-point invariant, cross-engine behavior, and reproducible tests
in mind when changing the compiler, runtime, or Core.

## Set up a development checkout

Tungsten supports macOS and Linux. On Windows, use [WSL2](WSL2.md) and follow
the Linux instructions.

```bash
git clone https://github.com/tungsten-lang/tungsten.git
cd tungsten
bin/tungsten doctor
bin/tungsten bootstrap
```

`bootstrap` builds the C stage-0 VM, runtime archive, and stage-1 compiler, then
hands those exact artifacts to the normal build pipeline. The build produces
stage 2 and rejects it unless its LLVM IR is byte-identical to stage 1. Use
`bin/tungsten bootstrap --force` when validating changes to that path.

The Ruby implementation has its own bundle:

```bash
cd implementations/ruby
bundle install
bundle exec rake
```

## Run tests

Run the narrowest relevant check while developing. Useful examples include:

```bash
bin/tungsten spec/core/array_spec.w
bin/tungsten --ruby spec/core/array_spec.w
(cd implementations/ruby && bundle exec rspec spec/parser_spec.rb)
make -C implementations/c test
rake spec:bits
rake check:all
```

Before submitting a change, run the authoritative gate from the project root:

```bash
cd /path/to/tungsten
rake
```

Root `rake` checks generated data and layouts, performs a fixed-point compiler
build, and runs the Ruby, C, interpreted, compiled, parity, CLI, cache, and bit
test suites. Hardware-specific checks may also need an appropriate Metal or
CUDA host.

Every semantic fix should have a focused regression. `run` and `-e` exercise
the compiled WIRE semantics. When a change also touches the legacy bootstrap
interpreter, exercise that path explicitly with `--ruby`; do not duplicate an
ordinary product-runtime test just to retest the same WIRE path. Keep
platform-specific expectations explicit instead of silently skipping an
otherwise portable test.

## Style and generated files

- Use two-space indentation, double-quoted strings, snake_case methods, and
  PascalCase classes in `.w` sources.
- Prefer `#size` to `#length` in new and changed Tungsten code. `length` can
  remain a compatibility alias, but it is not the idiomatic spelling.
- Keep changes focused and do not reformat unrelated files.
- Register every new Core class or trait in `core/tungsten.w`.
- Do not hand-edit files that identify themselves as generated.

The root checks report the exact regeneration command when generated content is
stale. Common commands are:

```bash
rake doc:core
ruby scripts/gen_units.rb --write
ruby scripts/gen_ast_schema.rb
```

Run `git diff --check` before submitting a change.

## Benchmarking and performance changes

Always compile benchmark subjects with `--release`. Explicit `--dev`/O0 builds
can change algorithm rankings and do not support performance claims. Compare the
same workload on the same hardware, include warmups and multiple samples, and
record the compiler flags, target CPU, operating system, and summary statistics.
Keep the correctness oracle separate from the timed region.

Performance work on the compiler must still pass the stage-1/stage-2
byte-identity check. A faster build that changes the fixed point is a compiler
bug, not a benchmark win.

GitHub's Performance workflow measures the base and candidate revisions on the
same pinned Blacksmith 4-vCPU runner, then applies the committed long-term
baseline when its runner identity still matches. Results, samples, and noise
bands are JSON artifacts. Long-term baseline changes are created only by a
manual workflow dispatch through the approval-gated `performance-baselines`
environment; the job opens a pull request for review. See
`benchmarks/performance/README.md` for the comparison, environment, and GitHub
repository-setting contract.

Builds keep reusable artifacts in `build/cache/`. A concurrency-safe sweep runs
automatically and retains files for seven days by default. To exercise the
retention contract directly, run `rake test:cache_gc`; do not commit cache or
build products.

## Continuous integration

Linux CI and release builds use pinned Blacksmith Ubuntu 24.04 runners; macOS
Intel coverage remains on GitHub-hosted hardware. The repository's Blacksmith
GitHub integration must be enabled before changing a job to a `blacksmith-*`
label, or GitHub will leave that job queued without a matching runner.

CI persists `build/cache/` and the content-addressed C VM cache with the
upstream `actions/cache` action. Blacksmith redirects that action to its
co-located cache automatically. The outer key separates operating systems and
architectures and hashes build inputs; its rolling restore prefix deliberately
allows older entries through because Tungsten validates every restored artifact
against its own complete content/toolchain identity before reuse. Avoid adding
a second cache action for a subdirectory of `build/cache/`.

## Pull requests

A pull request should explain the user-visible problem, the root cause, the
chosen fix, and the exact validation performed. Keep unrelated work out of the
diff, call out platform or hardware coverage that was not available, and update
the relevant documentation and changelog when behavior changes. Compiler and
runtime changes should include focused parity or ABI coverage where applicable.

Release changes should additionally pass:

```bash
bin/tungsten release --dry-run
```

Only a clean `main` checkout can create a release tag; GitHub builds, smokes,
checksums, attests, and publishes the native platform matrix after the tag is
pushed.

## Issues and security

Search the [issue tracker](https://github.com/tungsten-lang/tungsten/issues)
before reporting a bug or proposing a feature. Include a minimal reproducer,
the output of `bin/tungsten doctor`, the execution mode, and the observed and
expected behavior.

Do **not** report security vulnerabilities in the public issue tracker. Send
them privately to thecompanygardener@gmail.com.

Website issues can be reported in the
[website tracker](https://github.com/tungsten-lang/website/issues).
