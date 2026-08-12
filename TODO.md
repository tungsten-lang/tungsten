# TODO

## Compiler bugs found building core/physics + Plot3D (2026-08-03)

Found porting Lanyon's CompressibleEuler to core/physics with the Plot3D
three.js viewer. One is FIXED in this change set; the rest have minimal
repros and workarounds noted at the use sites.

1. **[FIXED] Function dedup merged bodies differing only in literal
   constants.** `compiler/lib/content_hash.w` encode_inst's generic arm
   skipped the payload fields of `const_quantity` / `const_decimal` /
   `const_currency` / `const_duration_*` / `const_date` / `const_ipv4` /
   `const_rational` / `const_color`, so e.g. every class method returning
   a bare quantity literal collapsed to the first one compiled
   (`Physics.boltzmann` == `Physics.air_density` == `1.225 kg/m³`).
   Fixed by hashing sig/scale/unit_id/symbol_id/date/ipv4/etc. Repro that
   used to fail: three class methods returning `100 m/s`, `5 Pa`, `3 kg`.

2. **[FIXED] Interpreter: autoload stub drops `< Parent` link.** When a
   registry entry maps a class to a file other than the one defining it
   (orchestrator-style entries like `auto :CompressibleEuler, "physics"`),
   the eval of `+ Sub < Parent` first ran try_autoload_class, which
   installed a parentless stub; the real definition then merged methods
   into the stub without ever setting `:superclass`, so all inherited
   methods raised "undefined method". Fixed in
   `compiler/lib/interpreter.w` (class-def now backfills `:superclass`
   on a stub when the definition names a parent). Latent victim:
   `WeilSexticGaloisGroup < GaloisGroup` (works only because it overrides
   everything it uses).

3. **[FIXED] Compiled StringBuffer#append dropped non-literal strings
   inside function bodies.** The known-StringBuffer lowering only used the
   direct runtime append for statically inferred strings; parameters, locals,
   concat results, and other dynamic values fell through the bodiless Core
   declaration and silently appended nothing. All known-StringBuffer appends
   now lower directly and dynamic values pass through `w_to_s`, matching the
   interpreter and `StringBuffer#<<` runtime semantics. Pinned in
   `spec/compiler/string_buffer_dynamic_append_spec.w`.

4. **[FIXED] Quantity arg slot clobber around inline `.class.to_s`, early
   return, and `case`.** The original Physics.si control-flow shape now
   preserves the Quantity argument across the guard and case, including after
   the same call site handles a Decimal, and quantity-literal case branches
   select the right unit. The exact historical shape is pinned across both
   engines in `spec/compiler/quantity_control_flow_parity_spec.w`.

5. **[FIXED] `bin/tungsten -c` rejected array types in typed signatures.**
   Parameter and return type parsing now accepts the shared `T[]` spelling,
   and the CLI contract gate checks a real `i64[]` signature through `-c` so
   checker/parser drift cannot silently return.

6. **[FIXED] Stage binaries went stale across the unit-registry expansion
   (b7269d7): compiled `1 kg/m³` printed `1 mickey`.** The committed
   tables were consistent, but the cached stage compiler + prebuilt
   runtime predated the expansion, so compile-time unit ids and the
   linked runtime's unit_names[] disagreed by 4 slots. `build --force`
   resyncs. Runtime identities already content-hash the generated C table;
   stage identities now also hash the external lexer membership table, so a
   registry change invalidates both sides automatically. `gen_units.rb` also
   skips byte-identical block rewrites, avoiding no-op mtime churn.

7. **[FIXED] Interpreter: `Class.method(["array", "literal"])` bound the
   array as a block.** Call ASTs now carry trailing blocks explicitly instead
   of inferring one from the final argument. The historical class-method shape
   is pinned in `spec/compiler/array_constructor_parity_spec.w` across both
   engines.

8. **[FIXED] Packed lexer mis-scanned heredoc content (`Unexpected token
   TYPE_HINT(<<~JS…`).** Heredocs whose bodies look token-dense to the
   fast64 tokenizer (e.g. many `//`-prefixed JavaScript lines) come back
   as a TYPE_HINT token instead of a STRING. Not a pure size limit:
   170 lines × 100 chars (17 KB) passes while 200 × 38 (8 KB) and
   1000 × 8 fail. Repro: `+ T` / `-> .a` / `<<~JS` + 300 lines of
   `// pad N …` + `JS`. Likely the fast64 pre-tokenizer scanning inside
   the heredoc span (`//` starts a regex/comment state) and the packed
   12-bit length or the materializer skip logic losing sync. Workaround:
   core/plot3d.w ships its viewer JS/CSS as data/viewer3d assets read at
   runtime instead of heredocs. The packed lexer now skips directly to the
   heredoc terminator and materializes the body as one string; a 240-line
   token-dense body is pinned in `spec/compiler/heredoc_opaque_lexer_spec.w`
   across interpreted and compiled execution.

9. **[FIXED] `Closure#call` capped at 2 arguments.** `f.call(x, y, z)`
   died "closure .call supports up to 2 arguments"
   (runtime w_method_dispatch); 3D simulation init lambdas need 3.
   Added w_closure_call_3/_4 and dispatch arms.


## BigInt: mutate-if-unique arithmetic (promoted from COW deferral, 2026-08-01)

**What:** add/sub/mul/div mutate the LHS in place when it is provably
unshared and dead after the statement. Not COW — no limb sharing between
live values; the uniqueness test is the only overlap with the original COW
idea.

**Why:** add/sub can compute truly in place (carry propagation is
element-wise), removing the alloc + TLS pool round-trip — the proven
overhead class — AND turning `big += small` from O(n) copy into amortized
O(1) sparse update (GMP's retained-mpz advantage, a complexity-class gap
today). Mul cannot compute in place (every algorithm re-reads input limbs;
GMP scratches too) — mutation there is only buffer recycling, which the
hot-slot pool already approximates; whether true in-place mul is possible
is now a research thread at
`~/math/numeric-experiments/inplace_bignum_multiplication.md` (n×1 and
small-m over-place look solvable by engineering; balanced is the open
part). Div partial: Knuth consumes the dividend in place; a dead LHS
buffer can be the remainder scratch.

**Staged route:**
1. Static, no flag: lowering emits `w_add_mut`/`w_sub_mut` (runtime cap
   check, fresh-alloc fallback) exactly where the escape pass would insert
   a free of the old LHS — same proof, different payoff. Zero tax on other
   paths.
2. Sticky shared-bit in the header (pad bytes at `runtime/wvalue.h:498`),
   set at escape sites, checked only in mutating entries — only if
   profiling shows container-resident accumulators matter. Failure mode of
   a missed escape site is a silently wrong value (worse than UAF); the
   ownership pass's known unsoundness (hash frees) was repaired 2026-08-02
   (missing mark_escapes arms closed, hash freeing re-enabled with stage-2
   self-host green — see ownership.w and hash_free_escape_spec.w), but any
   E4 work must still gate and fuzz against the immutable engine: a wrong
   uniqueness proof computes silently wrong numbers either way.
3. Never full refcounting (would tax every WValue store language-wide).

**Coupling:** sign-in-the-value makes `-x` an alias of `x`; the uniqueness
analysis must model negate as aliasing or fall back to copy when the
operand stays live. Design the alias model once, shared by both features.

**Still deferred (original COW):** sharing limb buffers between live
values. Mutation makes it less attractive, not more — mutating is only
legal because nobody shares.

## BigInt: FLINT end-to-end exact-math comparison

Keep GMP as the limb-level arithmetic oracle, then add a separate optional
FLINT workload suite for the work users actually perform above raw `mpz`
operations: modular polynomial multiplication/GCD, exact matrix operations,
and representative number-theory kernels. Record end-to-end wall time,
allocation, operand-size distribution, platform, and exact FLINT/GMP build
versions. This is a comparison harness, not a production dependency or a
reason to duplicate FLINT's domain APIs. Start only after the current GMP
matrix and large-worker sweep have stable artifacts.

## Unit conversion contexts

- Add an explicit context scope for conversions whose value depends on
  environment, convention, locale, or date (for example standard atmosphere,
  assay/analyte assumptions, historical currency, and calendar-dependent
  durations).
- Put versioned physical constants in the same context model. A calculation
  should be able to select a named CODATA/SI release and record it in result
  provenance rather than silently using whichever table shipped with the
  binary.
- Version unit definitions and conversion factors that changed historically;
  the context should select an effective date or named standards edition.
- Define context inheritance, serialization, cache keys, and reproducibility
  rules before exposing syntax. Context-dependent values must never enter the
  unconditional unit conversion table.

## Finish HDF5 format support

**Done (subset):** pure-C foreign path in `runtime/sci_io_native.c` after TH5
magic check — superblock v0/v2, OHDR v1/v2, symbol-table + compact link
messages, contiguous f32/f64/integer datasets (LE/BE). TH5C/TH5D unchanged.

**Still remaining:**

- Nested groups (multi-level paths), attributes, named datatypes, soft/external
  links.
- Chunked layouts, compression filters (gzip/shuffle), virtual datasets.
- Compound / string / variable-length types; multi-D shape metadata on the
  SciIO surface (today values are flattened to 1-D Arrays).
- Golden fixtures from h5py/`h5dump` under `spec/sci/fixtures/`.
- Optional `libhdf5` bridge (`runtime/sci_io_bridge.c`) remains unlinked —
  only if the pure walker stalls on exotic files.

## Wassat: merged multi-thread proof stream (deferred by CEO review 2026-07-22)

**Trigger:** the plan's `--fast` clause sharing lands AND demonstrates superlinear
gains AND certified (`--proof`) runs become the wall-clock bottleneck. Until
all three hold, do not build this.

**What:** design + implement a single merged proof stream with cross-thread
derivation tracking, so a clause-sharing portfolio can emit checkable
refutations. Today's decision (review findings 3A + 12C): `--proof` races
isolated processes with self-contained proofs and no sharing; sharing lives
only in `--fast`, where answers are trusted-not-proven by contract. This TODO
is the one door that design closes, and this note is where the key is.

**Context to reload:** plan `~/.claude/plans/would-you-rather-write-floating-parnas.md`
(Phase 3 section), CEO record
`~/.gstack/projects/companygardener-math/ceo-plans/2026-07-22-wassat-portfolio.md`.
Effort: XL human / L with CC. Priority: P3.

## Engineering roadmap (2026-08-11)

This is the execution checklist for the compiler/runtime review. A checked item
has a regression or an independently runnable contract in the tree; broad
projects stay unchecked until their stated acceptance criteria are met.

### Correctness and compiler contracts

- [x] Fix the C VM empty-operand-stack transition. `NEXT()` must not refresh
  its top-of-stack cache when `sp == 0`; keep the exact `STORE_LOCAL; POP`
  transition under ASan+UBSan on ARM64 and x86_64.
- [x] Generate one machine-readable foreign-call contract table and verify
  compiler declarations, WIRE calls, C symbols, arity, and raw/WValue ABI from
  it. The default suite must fail on an undeclared or mismatched `ccall`.
- [x] Route `tungsten check`, `-c`, and `--check` through the stage-2 loader and
  lowering/type-inference path, stopping before CFG/LLVM/linking. Keep valid and
  static-error CLI fixtures in the root gate.
- [ ] Differential-fuzz all frontends: generate grammar-aware valid and
  near-valid sources, compare canonical tokens/ASTs from the reference, packed,
  and fast C paths, minimize disagreements, and retain every counterexample as
  a fixture. A crash is only one failure mode; any semantic disagreement is an
  oracle failure.
  - [x] Deterministic seed/case generation, replay, line minimization, and
    failure retention under `build/cache/frontend-fuzz/`.
  - [x] Token/value/location/error parity for the Ruby regex/codepoint pair and
    the self-hosted reference/packed pair.
  - [x] Valid/invalid acceptance checks plus execution parity across Ruby,
    self-hosted, and the C VM for the shared arithmetic/control-flow subset.
  - [x] Compare complete normalized AST trees for every generated valid source
    across the Ruby, self-hosted packed, and fast C parsers. The canonical C
    view is generated from the AST schema, so omitted nil fields and hash
    insertion order cannot hide or invent disagreements.
  - [x] Broaden the shared grammar through grouped expressions, arrays,
    indexing/calls, `while`/compound-assignment loops, function/method
    definitions, class declarations, inherited constructors/methods,
    non-escaping iterator blocks, and basic scalar literals.
    Promote each observed minimized
    disagreement into a committed fixture; the campaign has caught
    same-indent and multi-level token-column bugs, cyclic Ruby `fn`
    fingerprints, a non-advancing C parse at top-level `DEDENT`, underscored
    PascalCase splitting, C `class_ref` drift, and missing implicit C-VM
    constructors.
  - [ ] Extend the Ruby normalization adapter and generator through
    general/escaping blocks, exception handling, and numeric/domain literal
    families before calling the differential campaign complete.
- [ ] Add a GPU-kernel type/subset pre-pass at check time. Batch unsupported
  statements, bad address spaces, shape errors, and dialect-only intrinsics
  before invoking `metal` or `nvcc`.
- [ ] Make `compiler2` packed/slab nodes use generated `node.field` accessors
  instead of mixed `ast_get`/index access, then delete the compatibility path.
- [ ] Enforce generic constraints when definitions are checked, including
  parent constraints such as `Class<T> < Parent`, instead of deferring them to
  runtime dispatch failures.
- [ ] Add a compiler consistency audit: every Core method requiring dynamic
  dispatch has the needed IC row and static-whitelist entry. Make missing wires
  a build error, not a release checklist item.
  - [x] Validate every native IC initializer structurally and make Quantity's
    full source/static-lowering/native-IC method surface an exhaustive root and
    `build:tungsten` gate. Dynamic Quantity receivers now cover roles,
    metadata, equivalence, and the `equivalent_to` alias.
  - [ ] Classify the remaining runtime-backed Core classes exhaustively so a
    newly added source method must declare its native-IC or autoload fallback.
- [x] Reject ASCII `camelCase` identifiers lexically. Uppercase ASCII after a
  lowercase start is neither a variable, `ClassName`, nor `CONSTANT`. The
  packed, reference self-hosted, Ruby regex/codepoint, and direct C lexers all
  reject it; their generated unit-membership exception preserves valid `eV`,
  `mmHg`, `kWh`, and other registered mixed-case unit spellings.
- [x] Specify and test method fallthrough: a taken final conditional arm returns
  its bare value, while every path that reaches the end without producing one
  returns `nil`. Native and interpreted coverage includes `if`, `elsif`, nested
  conditionals, and an untaken explicit-return arm.
- [x] Preserve the intended integer tower instead of merging names by accident:
  `Int` is the exact auto-promoting family; concrete inline `Integer` and heap
  `BigInt` representations inherit from it. Promotion/demotion and subtype /
  overload parity are executable contracts, and BigInt no longer claims the
  distinct concrete `Integer` type.

### Frontend and compilation performance

- [x] Make the C fast loader/parser byte-for-byte equivalent and the default
  bootstrap path. `scripts/test-fast-parse-parity.sh` compares byte-identical
  stage-1 LLVM IR and runs an acid test against the fast-built compiler. The
  native path is roughly 35x faster at lexing/parsing in its focused benchmark.
  Transfer its useful ideas to the self-hosted frontend: flat packed token
  storage, one-pass use-graph
  flattening, avoiding intermediate AST containers, memoized target probes,
  and watermarked rather than repeated whole-tree autoload scans.
- [ ] Persist a reusable lowered-Core image under `build/cache/`. Its identity
  must cover compiler/schema version, all loaded Core contents, build defines,
  target/mode, service bindings, and lowering configuration; remap IDs safely
  when composing it with a user module. Benchmark cold miss, warm hit, and RSS.
- [ ] Add file/use dependency tracking for incremental recompilation. Rebuild
  only invalidated files and downstream users, while retaining stage-1/stage-2
  byte identity as the bootstrap invariant.
- [ ] Make codegen parallelism adaptive. Gate LLVM partitioning on module size,
  available memory/cores, architecture, and measured benefit; fall back to one
  TU on small modules or any split failure. Record the tradeoff: parallel jobs
  raise peak RSS and can lose whole-module optimization, particularly on ARM64.
- [ ] Promote compiler PGO from an opt-in experiment to a reproducible cold
  bootstrap profile, with versioned training inputs and before/after timings.
- [ ] Resolve the `-O0` performance inversion. User `-o` builds should default
  to a meaningful optimized profile, while an explicit debug/O0 mode remains
  available; all benchmark harnesses must require/restate release mode.
- [ ] Move the remaining reusable runtime archive and incremental artifacts out
  of `/tmp`/implicit home caches into the selected content-addressed cache, and
  include tool contents, generated tables, runtime sources, ambient SDK paths,
  flags, target, and optional features in their identities.

### Build, cache, CI, and release

- [x] Garbage-collect reproducible files in `build/cache/` after seven days.
  Automatic sweeps are daily and concurrency-safe; a retention-contract test
  covers fresh files, stale files, nested directories, and invalid settings.
- [x] Unify `bootstrap` and `build` around one runtime/stage-1 build function and
  artifact manifest. A chained fresh bootstrap must hand the verified artifacts
  to build without recompiling them, while different flags/features remain
  cache misses.
- [x] Remove `/opt/homebrew` assumptions from executable paths. Prefer explicit
  config, `pkg-config`, `brew --prefix <formula>`, the compiler search path, and
  standard system prefixes; include discovered prefixes in cache identities.
- [x] Add `rake spec:bits`: classify all tracked bit specs, exclude generator
  templates explicitly, run each real suite exactly once, and fail discovery
  drift. Wire it into root `rake` and CI.
- [x] Put unit-registry superset and regex-lexer parity checks in the default
  root gate; run Metal, REPL/PTY, and API contracts on appropriate CI hosts.
- [x] Add x86_64 and ARM64 sanitizer lanes for the C VM/runtime. Keep ordinary
  CI portable; use Spot only for a missing architecture or a failure that cannot
  be reproduced on GitHub's native runners.
- [ ] Add a GitHub performance workflow with pinned hardware classes, warmups,
  multiple samples, machine-readable baselines, noise bands, and an explicitly
  approved baseline-update path. Report regressions without comparing unlike
  runner generations.
- [x] Implement `bin/tungsten release`: validate a clean `main`, run root `rake`,
  create/push an annotated version tag, then build, smoke, checksum, attest, and
  publish native packages for macOS/Linux ARM64 baselines and x86-64-v2/v3.
- [x] Make the release workflow exercise `--dry-run` and package validation in
  pull requests without creating tags or releases.
- [x] Repair `-march=native` on Apple Silicon so release/native never suppresses
  crypto extensions. Stamp the explicit detected feature set and pin it with an
  ARM64 release/native IR contract plus the default hardware crypto vectors.

### CLI, package manager, and developer tools

- [x] Add `tungsten explain CODE` and point structured diagnostics/API parsing
  at that spelling; unknown codes must be non-zero.
- [x] Preserve exact child status from `tungsten run` and compiler delegation.
  A program that calls `exit(7)` must surface status 7, and exceptions must keep
  their formatted diagnostic rather than becoming silent status 1.
- [x] Keep runtime error source locations, context windows, and caret pointers
  under compiled regression coverage, including the no-source fallback.
- [ ] Port `implementations/ruby/lib/tungsten/formatter.rb` to the self-hosted
  `bin/tungsten fmt`; require idempotence and AST equivalence over the corpus.
- [x] Add `bin/tungsten lint` with stable diagnostic codes, machine-readable
  output, configurable severities, and no source mutation.
- [x] Add `bin/tungsten debug` for build/run with symbols, frame pointers,
  sidemap validation, LLDB/GDB selection, build-only automation, cached
  artifacts, and a direct-run mode with faithful child exit status.
- [x] Finish the self-hosted REPL migration (`repl.rb` to `repl.w`) and remove
  Ruby as an interactive runtime dependency after PTY/history/error parity.
- [x] Make `bit install` resolve a lockfile, verify checksums, and install to
  `$BIT_HOME/<name>/<version>/`; default `BIT_HOME` to
  `$TUNGSTEN_HOME/bits`, and `TUNGSTEN_HOME` to `~/.tungsten`. Support an
  explicit system-wide prefix without requiring it for ordinary installs.
- [ ] Add streaming CSV and broaden filesystem coverage:
  - [x] Add a chunk-fed CSV state machine with quoted multiline fields,
    escaped quotes, CRLF boundary handling, eager row delivery, strict parse
    errors, SciIO integration, and interpreter/native parity fixtures.
  - [x] Add depth-first File/Directory/Dir traversal without following symlink
    directories, with interpreter/native fixtures.
  - [ ] Add incremental file-handle reads, compiled link/permission mutation,
    atomic replace, and platform error parity. Metadata and memory mapping have
    portable source facades but still need Windows coverage.
- [ ] Improve FFI declaration, ownership, callbacks, strings/bytes, structs,
  arrays, error translation, and marshalling; specify which side allocates and
  frees every representation.

### Core semantics and concurrency

- [x] Enforce `string` as the text type spelling. Reject `str`/`str[]` at the
  source annotation with `E_PARSE_INVALID_TYPE_NAME`; keep internal `:str`
  interpolation tags private to the AST representation.
- [x] Give `Enumerable` real producer-side early termination. Indexed sources
  return directly; generic/pair-yielding sources use an identity-checked private
  unwind signal so infinite streams stop, `ensure` runs, and user exceptions
  are rethrown.
- [x] Implement `block?` in the self-hosted compiler and replace Core uses of
  `block_given?`; retain a documented compatibility alias only if external code
  requires it.
- [x] Complete interpreter/native parity for `SmallArray` and
  `Array.new(n, fill)`, including zero size, mutable fill aliasing, typed fills,
  bounds, stack promotion, and calls through dynamically typed receivers. Keep
  constructor parity, dirty-stack zero initialization, and wide-element boxing
  in the default gate.
- [ ] Eliminate remaining interpreter/compiled divergence systematically: bare
  sibling class-method calls, array literals passed to class methods, packed
  AST containers, reverse-operand dispatch, Hash keys/equality, and constructor
  defaults all need paired fixtures.
- [ ] Define cancellation and close semantics shared by `Thread`, `Channel`,
  `Future`, and `Promise`: blocked send/receive wakeup, timeout races,
  cancellation propagation, cleanup, and uncaught worker errors.
- [ ] Expand `core/channel.w` with bounded/unbounded send, receive, close,
  iteration, timeout/nonblocking operations, and select semantics.
  Bounded `send`, `receive`/`recv`, close/drain behavior, and invalid
  capacity rejection are source-defined and covered across both engines.
  `receive_result` distinguishes a received `nil` from closed-and-drained
  state and powers close-aware iteration. `Channel.unbounded` grows its FIFO
  geometrically, while `Channel.new(0)` performs a sender/receiver rendezvous.
  Nonblocking and millisecond-timeout send/receive operations use a three-state
  result so nil, timeout, and closed remain distinct. Select uses rotating
  receive/send probes with an optional timeout and treats closed arms as ready;
  event-loop-backed parking remains open. The unbuffered concurrency fixtures
  cover close and cancellation waking or removing blocked participants and are
  compiled-only until interpreted `go` is asynchronous.
- [x] Flesh out `core/mutex.w` with lock/try_lock/unlock/synchronize, ownership
  errors, an explicit non-reentrant/non-poisoning policy, ensure-based release,
  and forced native-thread-exit cleanup.
- [x] Flesh out `core/atomic.w` with signed-i64 load/store/exchange/CAS/fetch
  ops, wide-value promotion, compatibility spellings, and explicit
  sequential-consistency semantics mapped consistently on every host.
- [x] Add `Future`/`Promise` with exactly-once settlement, multi-waiter
  publication, worker-error propagation, map/flat-map/recover/finally
  composition, timeout, and cancellation. Cancellation is explicit best-effort
  worker interruption and never rolls back side effects or cancels a shared
  parent Future.
- [ ] Add scope-safe/finalizer-backed release for Metal and Tensor handles.
  Prefer explicit deterministic `close` plus idempotent finalization; prove that
  finalizers never run GPU work or deadlock the runtime.
- [ ] Add typed runtime error values without losing stable codes/source spans.
  Specify hierarchy, cause/backtrace, rescue matching, serialization, and FFI
  error translation before replacing string raises.

### Core library surface

- [x] Add `core/url.w` with strict absolute `URL.parse/1`, canonical
  reconstruction, userinfo/IPv6/port handling, and malformed-input rejection.
- [x] Define the `core/socket.w` facade for event-loop-backed TCP listen,
  connect, accept, String/ByteArray I/O, deadlines, shutdown, ALPN, and close.
- [ ] Add `core/http.w`. HTTP needs streaming bodies, redirects, timeouts,
  cancellation, TLS verification, proxy behavior, and typed transport/status
  errors.
- [ ] Replace curl subprocess TLS with an in-process transport. Reuse the native
  HTTP/2/HTTP/3 work, avoid `system(3)` global signal/mutex hazards, and test
  certificate validation plus concurrent requests on macOS and Linux.
- [ ] Add `core/timezone.w`, `core/datetime.w`, and `core/timestamp.w` with a
  versioned timezone database, DST gap/fold policy, monotonic-vs-wall-clock
  separation, parsing/formatting, and serialization provenance.
- [x] Add `core/env.w` with fetch/get/set/delete/keys/each/to_h, process-local
  mutation, point-in-time snapshots, String/NUL validation, and sandbox gates.
- [ ] Add `File.stat` and `Tempfile`, including typed metadata, secure atomic
  creation, cleanup/close behavior, symlink policy, and Windows parity.
  - [x] POSIX `stat`/`lstat`, portable `FileStat` metadata, atomic mode-0600
    creation, explicit non-block ownership, and ensure-backed block cleanup.
  - [ ] Implement and exercise the same contract on the Windows runtime port.
- [x] Add `core/timer.w` with monotonic deadlines, one-shot/fixed-rate repeating
  timers, cancellation, retained callback errors, and no callback after a
  successful cancel.
- [ ] Move Timer's interruptible waits from one native thread per timer onto
  the event loop while preserving the cancellation gate and `wait` semantics.
- [ ] Add regex capture groups with consistent numbered/named captures,
  unmatched-group behavior, offsets, Unicode semantics, and engine parity.
- [ ] Complete Hash on every host: insertion order, symbol/table separation,
  char keys, structural equality/hash agreement, deletion/tombstones, and
  mutation-during-iteration behavior.
- [ ] Finish HDF5 and the multi-dimensional SciIO contract described above,
  with h5py/`h5dump` golden fixtures and shapes that are not silently flattened.
- [ ] Design unit conversion contexts as described above: versioned CODATA,
  standard atmosphere, historical currency, effective dates, serialization,
  cache identity, and provenance on results.

### Native data and numerical performance

- [ ] Start Array-to-native Tier A: instrument hot Array paths, move typed
  storage/arithmetic to unboxed native buffers, retain WValue fallback, and pin
  aliasing/GC/exception semantics. Matmul is the primary acceptance workload.
- [ ] Close the integer pipeline-fusion dispatch gap and compose it with loop
  versioning, stack promotion, and typed storage; compare fused/unfused output
  and performance.
- [ ] Apply the proven `## i64`/unboxed discipline to the regex VM and measure
  instruction/boxing counts before and after.
- [ ] Finish BigInt mutate-if-unique `add/sub` first, using the ownership proof
  at the point an old LHS would be freed; model negate aliases and
  differential-test against the immutable path before expanding to mul/div.
- [ ] Add PMULL GHASH on supported Apple Silicon with feature dispatch and
  standard test vectors; retain constant-time portable fallback.
- [ ] Make small matrix multiplication competitive with C across tiny fixed
  shapes. Benchmark call/shape-check/allocation overhead separately from the
  arithmetic and generate specialized kernels where it wins.
- [ ] Add shape-safe linear algebra: checked dimensions by default, compile-time
  shapes when known, overflow-safe allocation math, and one explicit unsafe
  escape hatch. Measure checks so small matrices do not regress.

### GPU and additional platforms

- [x] Reject unsupported CUDA `tg_sum/tg_max/tg_min`, SIMD reductions, and
  `simdgroup_*` matrix intrinsics during dialect emission. Invalid MSL names
  never reach a `.cu` sidecar; emit-only expected-failure fixtures keep the
  diagnostics explicit until native CUDA equivalents are implemented.
- [x] Broaden WGSL beyond assignments/calls/if: while-as-loop, return,
  workgroup memory, barriers, and atomics, with emitted WGSL validated by a real
  tool in CI.
  - [x] Emit while/if/else, return/break/continue, compound assignment,
    workgroup arrays, invocation/workgroup IDs, barriers, and i32 storage
    atomics; keep an emit-only sidecar regression in the default spec gate.
  - [x] Pin naga-cli 30.0.0 in the Linux CI cache and validate the emitted
    sidecar semantically in addition to the source-marker assertions.
- [ ] Make multi-dialect GPU sidecars deliberate and stable by default. Invalid
  dialect combinations must be diagnostics, not skipped comments or silent
  fallback; keep explicit opt-out for users who only want one backend.
  - [x] Reject unknown, duplicate, empty-entry, and `none`-combined dialect lists
    with E_GPU_DIALECTS before writing any sidecar.
  - [ ] Default WGSL emission once every default kernel either emits valid
    portable WGSL or receives an explicit dialect diagnostic.
- [ ] Verify GPU kernel shapes and intrinsic legality before emission, including
  SELF shapes, addcarry/asm restrictions, workgroup sizes, and buffer bounds.
  - [x] Run the actual selected-dialect GPU emitter as an early shared preflight
    for compile and `-c`, with source-located subset/type diagnostics and no
    sidecar writes in check mode.
  - [x] Accumulate independent kernel diagnostics so one check reports every
    invalid kernel instead of stopping after the first.
- [ ] Make carry-chain unroll count a source/env tuning hint rather than a
  hardcoded 8, and add `bin/tungsten gpu-bench` to emit, compile, dispatch, and
  time reproducible kernels with device/compiler metadata.
  - [x] Add `TUNGSTEN_CARRY_UNROLL=0..64`, retain 8 as the default, include it
    in incremental-cache identity, and verify emitted LLVM metadata.
  - [x] Add a reproducible Metal `bin/tungsten gpu-bench` harness with
    synchronous and batched timing, correctness checks, cached artifacts, and
    device/compiler/source provenance.
  - [ ] Add an equivalent standardized CUDA timing host to `gpu-bench`.
- [ ] Add MinGW and a Windows-native event loop, filesystem/process/socket
  parity, path/encoding rules, and x64/ARM64 CI. Use a temporary native host or
  Spot runner only where GitHub runners cannot exercise the required kernel API.
- [ ] Add a WASM target. First evaluate LLVM's wasm32 output against WIRE ABI,
  exception, GC/ownership, filesystem, and browser/WASI constraints; avoid a
  second lowering backend unless the LLVM route cannot meet the contract.

### Documentation and onboarding

- [x] Expand `doc/CONTRIBUTING.md` with fresh-clone build, root `rake`, focused
  specs, style (`size`, not `length`), generated files, benchmark discipline,
  stage identity, cache cleanup, PR expectations, and release verification.
- [x] Fix case-sensitive/stale references: `doc/WSL2.md`, the specification TOC
  and Appendix B spelling/link, current standard references, and the duplicate
  `SYNTAX_WISHLIST` source of truth.
- [x] Treat `tungsten-lang.org` as launched in project notes and future audits;
  do not repeat the stale pre-launch status.
