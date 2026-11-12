# Changelog

## Unreleased

- **One list of runtime sources** — `runtime/sources.txt` names every C
  translation unit of the runtime with the builds it belongs to (`program`,
  `compiler`, `tests`, `wasm`), the slot it fills (event backend, TLS or its
  stub, the zstd codec or its stub) and, for companions, the feature that
  links it. The compiler's links, `bin/commands/build.w`, `bootstrap.sh`,
  `runtime/Makefile`, the wasm runtime, the Ruby compile path and the UBSan
  sweep all read it (`runtime/sources.sh` for shell, make and Ruby); the ten
  hand-kept lists are gone, and `bootstrap.sh` now builds `unicode_tables.c`
  into the stage-1 runtime as `build.w` always did. The manifest is part of
  the runtime's content key. `scripts/test-runtime-sources.sh` fails when a
  runtime file is missing from it or a build path lists sources itself.
- **`TUNGSTEN_ROOT` decides `core/` as it decides `runtime/`** — a source
  inside another checkout, or under an older install's tree (a scratch file
  under `~/.tungsten` used to compile against the July install's core and
  the current runtime), is compiled against the core of the toolchain that
  links it, on the compiler, the interpreter and the Ruby implementation.
  With `TUNGSTEN_ROOT` unset the source's nearest checkout still wins (nested
  worktrees), and the compiler warns when that tree is not the one whose
  runtime it links.
- **Compiler images no longer leak their mark** — an image read
  `TUNGSTEN_COMPILER_IMAGE` and left it in its environment, so a script run
  by the interpreter image that started `tungsten run --interpret` did not
  delegate to the interpreter image and failed with "undefined method 'new'
  for nil". The image now takes the mark out after reading it
  (`scripts/test-compiler-image-env.sh`).

- **One shared build store** — build artifacts no longer live in each
  checkout's `build/cache`. Every checkout, worktree and installed toolchain
  reads and writes one store, `~/.tungsten/build` (`TUNGSTEN_HOME/build`;
  `TUNGSTEN_BUILD_STORE` moves it): `compile/` for the compiler's artifacts,
  `stages/` for bootstrap and stage compilers, `compilers/` for finished
  compilers and their images, `bits/` for bit executables. `TUNGSTEN_CACHE_DIR`
  still replaces the compiler's directory for an isolated run. Sharing is by
  fingerprint, not by location, and the keys were audited for it:
  - runtime archives, LTO objects and companion objects are keyed by the
    content of every file under `runtime/` (the old mtime check over a
    hand-kept list missed `prime_lut.inc` and `ast_schema_generated.h`) and
    compiled with `-ffile-prefix-map` for both the source names and the
    compilation directory, so one checkout's objects are right for any
    checkout with the same runtime;
  - stage compilers, compiler images and a toolchain's own bits are compiled
    from the checkout root by relative path with `TUNGSTEN_ROOT` unset, so
    their bytes no longer name the checkout that built them (the compiler
    used to embed 175 absolute source paths); a binary that still does is
    kept out of the shared name. The stage-0 VM's fast loader named the files
    of the `use` closure by realpath whatever the entry's spelling, which
    made stage 1 differ from stage 2 for a relative entry; it now names them
    as the entry was spelled. The stage key now hashes
    `compiler/tungsten_driver.w`, which neither `build.w` nor `bootstrap.sh`
    covered;
  - the stage identity hashed the lexer table's absolute path (the checkout
    again) and only a handful of the compiler's `TUNGSTEN_*` switches, the bit
    stamp none: the path is gone, and every switch set in the environment
    (`TUNGSTEN_FREE=0`, `TUNGSTEN_DEFINES`, ...) is now part of the stage,
    image and bit keys, so a build made under one is never served to a plain
    build;
  - per-program artifacts, which embed absolute source paths by design, stay
    keyed by those paths, and the root they resolve against (previously
    implied by the cache directory) is now part of the incremental-binary,
    snapshot and Ruby-host AST identities.
  `bin/tungsten-compiler` is a copy of a store entry (a clone on APFS), with
  its record in `build/compiler-build.profile` and its images in
  `build/compiler-images/`. A new worktree gets the compiler the store holds
  for exactly its sources, or none: the post-checkout hook no longer links
  another worktree's compiler. Bit executables are stored under the compiler
  binary, runtime, flags and a manifest of every source file the compiler
  read (`TUNGSTEN_DEPFILE`), so worktrees with the same sources share one
  build and an edited `core/` file can never be served another's;
  `bin/bit`, `bin/rung` and `tungsten bit|rung|flame` run the store's
  executable. Writers publish by rename; a complete bit or image entry is
  kept rather than replaced by a second builder (two builds of one key can
  differ in code layout, and an executable must keep the sidemap of its own
  build); readers renew what they use; and the sweep (`tungsten cleanup`)
  removes only entries unused for 7 days or, above
  `TUNGSTEN_CACHE_MAX_SIZE_MB` (20000), the least recently used, taking an
  LTO object bundle only whole (the old size sweep could leave `.ready` over
  a partial set of objects). Release packages carry their compiler images in
  `build/compiler-images/`, and release-artifact images are compiled by
  relative path like the artifact compiler.
  `--clear-cache` now covers every snapshot kind and, in the shared store,
  only the calling toolchain's incremental binaries; `cleanup --all` empties
  the store. Old `build/cache` directories are neither read nor removed:
  delete them by hand. `scripts/test-build-store.sh`,
  `test-compiler-cache-location.sh`, `test-worktree-compiler-hook.sh`,
  `test-cache-gc.sh`, `test-build-bit-driver.rb`.

- **Arity contracts reach runtime builtins** — methods the runtime implements
  natively through its inline-cache rows (Array#push, String#slice,
  Hash#keys, Int#times, StringBuffer#append, Socket#read, … 121 rows in 11
  tables) now carry `[min, max]` argument contracts, populated from what each
  C handler consumes (a trailing block counts as one argument). A call that
  misses the contract is `E_LOWER_ARITY` at compile time when the receiver's
  static type names the class (`[1, 2, 3].push(4, 5)`, `s.slice(1, 2, 3)`),
  and on an erased receiver a rescuable `ArgumentError` with the same message
  at the call — checked once per call site on the inline-cache miss path, so
  a cache hit costs nothing. Core source methods reached through type-class
  dispatch (`arr.size(5)`, `arr.first(10)`, `n.abs(1)`, `f.to_i(1)`) are
  checked the same way against their registered signatures, and the universal
  dispatcher arms (`to_s`, `hash`, `nil?`, `respond_to?`, `<=>`, `is_a?`, the
  file builtins) reject surplus arguments they used to ignore. The interpreter
  applies the same table on primitive receivers and states a contract for each
  of its builtin arms. `compiler/lib/builtin_arity.w` mirrors the runtime
  rows; `scripts/check-core-dispatch-contracts.rb` fails when a runtime row,
  its compiler mirror, or a Core `.w` declaration of the same method disagree.
  `TUNGSTEN_ARITY=off` still disables every check. Parity spec:
  `spec/parity/builtin_arity_spec.w`.

- **Release packages carry their compiler images and are linked and run
  before they are published** — the compiler execs prebuilt images for the
  REPL, `--interpret` and `@gpu` programs and never builds one on launch, but
  `scripts/package-release.sh` shipped only the compiler, so a packaged
  `tungsten console` failed and `scripts/validate-release-package.sh` would
  have failed the next tag at its REPL check. `tungsten build --target` /
  `--portable` now builds each artifact's `repl` and `metal` images for the
  artifact's target and CPU, beside it in
  `build/releases/<triple>/<cpu>/compiler-images/`; the package installs them
  as `build/compiler-images/`; the validator requires them, starts the
  Metal image, and compiles, links and runs a program through the packaged
  launcher from outside any checkout. An image also could not find `core/`,
  `data/` or `runtime/` when the caller set no `TUNGSTEN_ROOT` (it sits in
  `build/compiler-images`, not `bin/`): `tungsten-compiler --repl` then
  died on the unit registry even with the image present. The compiler now
  hands the image the root that owns it. The release workflow's smoke step now
  runs a program on the default profile and builds and runs one with
  `--release` (it only type-checked before). Linux CI and the release matrix
  install LLVM 22 from apt.llvm.org through
  `scripts/install-linux-toolchain.sh` (the distribution package is LLVM 18),
  with compiler-rt for the sanitizer and PGO jobs. The `Dockerfile` uses that
  script on plain Ubuntu 24.04 (the Ruby base image is gone: the bootstrap
  needs no Ruby), and a new allowlist `.dockerignore` keeps a checkout's host
  binaries out of the image, where a macOS `bin/commands/build` newer than its
  source would be reused and fail to exec. `scripts/test-build-self-host.rb`
  covers the artifact images (3 checks) and
  `scripts/test-unit-release-package.rb` (rake `test:release_package`)
  packages this checkout and validates it in full. The build prints VERIFIED
  stage1==stage2. The Linux toolchain script, the workflows and the Docker
  build have not been run: no Linux host or Docker daemon was available.
- **A stage-identity mismatch fails strict builds** — `tungsten build` printed
  WARNING, installed stage 2 and exited 0 whenever stage 1 and stage 2 emitted
  different LLVM IR, so nothing that ran unattended could notice. It now
  prints ERROR, installs nothing and exits 1 when `CI` is set (to anything but
  empty, `0` or `false`) or the build was given `--strict` (new; `bootstrap`
  forwards it), `--install`, `--pgo`, `--target` or `--portable`. A plain
  local build keeps the warning and the installed compiler, since a two-step
  bootstrap change needs one. `scripts/install.sh`, the `Dockerfile` and the
  release workflow pass `--strict`. Both messages now print the two `.ll`
  paths. `scripts/test-build-self-host.rb` (rake `test:build_self_host`)
  drives the real build driver over a fake checkout: 13 checks, of which the
  previous driver fails the first strict one; the same was confirmed in a
  real checkout by altering the cached stage-2 module.
- **`--release` is whole-program LTO again** — since 2026-10-25 `--release`
  linked the cached native runtime archive unless `--lto` was also given (only
  compiler images kept LTO), while the help text, `AGENTS.md` and the manual
  all said "full LTO". `--release` again passes `-flto=full` and links the
  cached runtime bitcode bundle; `--no-lto` opts out. `compile-batch --release`
  compiled runtime bitcode into a scratch directory for every batch and then
  linked it without `-flto`; it now takes the same cached bundle (resolved
  once, before the parallel link workers) and every link carries the flag.
  The bundle is compiled without the value-changing FP flags `--fast` adds to
  the module, so `--release --fast` shares it and the C runtime stays IEEE.
  Instructions retired, apple-m5, clang 23.1.5, same emitted `.ll`: a hello
  binary 2,040,864 → 54,336 bytes and 21.5M → 15.9M per run; a 25-line
  array/hash/string loop 441M → 387M per run (−12%), 4,879,056 → 5,042,832
  bytes. The link costs more: 1.6e9 → 11.6e9 for hello, 77e9 → 240e9 for the
  loop. `scripts/test-compile-profiles.sh` pins the clang flags of the default
  profile, `--dev`, `--release`, `--release --no-lto`, `--lto`,
  `--release --fast` and the batch forms; against the previous compiler it
  fails on the batch link. The build prints VERIFIED stage1==stage2.
- **BLAS keeps its non-finite results in fast builds** — both the package
  runtime archive and standalone compiler companion add
  `-fno-finite-math-only` to `blas_bridge.c`. Other fast optimizations remain
  enabled. This preserves `LinAlg.slogdet`'s `[0, -Inf]` singular result and
  removes Clang23's `-Wnan-infinity-disabled` warnings. The archive cache keys
  the per-bridge flags. `runtime/tests/test_blas_slogdet.c`: eight cases in both
  precise and fast builds; LU/Cholesky19 checks pass with that warning as an
  error. Clean-HEAD baseline and final compiler both print VERIFIED stage1==stage2.
- **Native file drops** — `GFX_DROP_FILES` registers an editor window for file
  URL pasteboard drops. Real `NSDraggingDestination` callbacks queue `GFX_EV_OPEN`
  on the destination window, independently of previous focus. Synthetic drops
  use the same callbacks via `gfx_post_event(..., GFX_EV_OPEN, ..., a=1, ..., path)`.
  Non-file URLs and non-opted-in windows reject the drop. Graphics events93 pass.

- **Native menu labels retain concatenated strings** — graphics.m's shared
  string conversion flattens ropes before reading UTF-8. Long Unicode Recent
  filenames/directories and concatenated submenu paths no longer become blank.
  graphics_rope_menu_spec.w exercises runtime-built strings (constant-folded
  strings would miss this bug); native graphics events still pass87 checks.
- **Native resize preserves cached-frame scale** — CAMetalLayer uses a corner
  gravity selected for contentsAreFlipped, with implicit bounds/position/contents
  animations disabled. The old frame keeps its pixel scale while AppKit tracks
  a resize; Retina drawable dimensions continue to follow the backing scale.
  Arranger's native resize regression checks fixed sidebar pixels at five sizes.
  A live mouse-drag visual check remains unverified. No compiler/core change.

- **`(float expression) ## i64` converts the value, not the operands** — the
  compiled engine pushed a machine-int ascription into the operands of float
  arithmetic, so `(a * ~48000.0) ## i64` computed `trunc(a) * 48000` (0 for
  `a = ~0.279`; 48000 for 1.484 s instead of 71232) while the interpreter
  printed 13392. Float arithmetic under `## i64`/`## u64`/`## i32`/... now runs
  in floating point and is truncated once, like `.to_i`; integer arithmetic
  still wraps at the machine width. Expression-level `## i32`/`## u8`/...
  now convert like their assignment form (they passed a float through), the
  interpreter and the Ruby implementation truncate a float under every
  machine-int hint, and `<< e ## T` converts the printed value instead of
  ascribing the print statement (which crashed compiled code). The grammar
  chapter (§3.7, §3.9) now documents where `##` binds.
- **Compiled programs free far more of what they allocate** — with no GC, the
  compiler freed only known constructors' results that never left a scope,
  plus a few BigInt loop shapes. Everything else lived until exit: the inner
  `x * x` of `x * x + 1`, both sides of `a * 3 < a * 2`, the result of a
  helper like `sq(x)`, every value a loop variable held, every array a helper
  such as `zeros(n)` built, and every value of a top-level script loop. One
  research sweep leaked about 10 GB/s per process and took a 128 GB Mac down
  three times in a night. The ownership pass (`compiler/lib/ownership.w`)
  now releases:
  - integer temporaries after their last read (`int_temp_releases`), when
    they and the operands that produced and consumed them are integers at run
    time -- core integer arithmetic never keeps an operand;
  - results of functions that return a fresh integer or a fresh
    Array/String/Hash (`int_fresh_returns`, `fresh_heap_returns`), and
    arguments a callee provably does not keep (escape summaries now record
    what a parameter keeps when it is an Integer or a core container);
  - a variable's old value on each assignment and its last value on return
    (`owned_slot_releases`), with integers held by several variables
    reference-counted through the BigInt shared count;
  - top-level script variables, whose module-global copy nothing reads
    (`write_only_globals`).
  A program that redefines a core Integer or container method the releases
  rely on keeps the old behaviour for that kind. On the crash-era sweep one
  search went from 8.6 GB to 0.2 GB and ran three times faster; the
  `bench bignum` native lane is unchanged within noise. `TUNGSTEN_INT_TEMP_RELEASE=0`,
  `TUNGSTEN_SLOT_RELEASE=0` and `TUNGSTEN_FRESH_HEAP=0` turn the new releases
  off for diagnosis. Pinned in `spec/compiler/int_temp_release_spec.w`,
  `int_contract_reopen_spec.w`, `top_level_release_spec.w` and
  `fresh_heap_release_spec.w`.

- **Compiled programs have a memory ceiling** — with no GC, a leak in a
  compiled program grew until the machine ran out of memory; on macOS that
  ended in a watchdog kernel panic, not an OOM kill. Parallel sweeps leaking
  BigInt temporaries at about 10 GB/s took a 128 GB Mac down three times in one
  night. A runtime thread now samples the process's physical footprint every
  100 ms and exits with status 137 past `TUNGSTEN_MEMORY_LIMIT` (default `8G`;
  `off` disables it). A process holding 1 GiB or more also exits when the
  system is down to its last 5% of memory, so many processes that each stay
  under the limit cannot exhaust the machine together. The allocation paths
  are untouched; startup cost is one thread.

- **A parameter named `t0` compiles** — WIRE emitted each parameter as
  `%<name>`, in the one LLVM namespace per function that the compiler's own
  `%t<N>` temporaries share, so `-> run(k, t0, t1)` died in clang with
  "multiple definition of local value named 't0'". Parameters now live under
  a leading dot (`%.t0`, `llvm_param_reg` in `compiler/lib/naming.w`), which
  no compiler-minted name and no Tungsten identifier starts with. The same
  change fixes two bugs of that kind: escape analysis found a parameter by
  its stripped register spelling, so a unicode parameter such as `α` was never
  recorded as escaping and the caller freed a string the callee had stored
  (a use-after-free), and the content hash seeded parameters under their raw
  names, so bodies differing only in which unicode parameter they used could
  hash alike and be merged. Pinned in
  `spec/compiler/param_register_namespace_spec.w`.

- **Dynamic method dispatch reaches any arity** — a method with more than
  eight parameters, reached through runtime dispatch (an untyped receiver,
  a parent's self-call a subclass overrides, a class held in a variable, a
  primitive receiver), died with "unsupported method dispatch ... (runtime
  supports up to 8)"; primitive-receiver methods already failed at eight as
  "undefined method". Such a method now registers a compiler-emitted argv
  entry (`name__argv(self, argv)`) in place of its native one, and every
  runtime dispatcher (instance, class method, constructor, primitive type
  class) binds arguments through one generic path, `w_method_invoke`.
  Signatures of up to eight parameters keep their direct native calls and
  inline caches. Found in robolab (RunKnotsSkill running RunNaturalSkill's
  nine-argument `step_chunk`). Pinned in
  `spec/compiler/wide_arity_dispatch_spec.w`.

- **Float division by zero is IEEE** — `~1.0 / ~0.0` is `inf`, `-~1.0 / ~0.0` is `-inf`, and `~0.0 / ~0.0` is `nan` on both engines. A unary minus of a float stays a float, so the negated form takes the same `fdiv`.
- **Currency and quantity division** — `$10.00 / 3` stays currency, `10 m / 2` stays a quantity, and `$10.00 / $2.00` is a decimal ratio.
- **Date ordering** — `<`, `>`, `<=`, `>=`, and `<=>` compare the packed civil word. `Date` includes `BitOrdered`, whose bit order is that same word.
- **Interpreter `super`** calls the superclass method of the same name and returns its value, so `super + "!"` in an override is the parent's text plus `"!"`.
- **Prefix `Σ(expr, range)` compiles** — `Σ(2x⁷ + 3x², 1..10)` lowers as the same ranged sum as `(1..10)/Σ(2x⁷ + 3x²)`, including the closed form. A call without bounds is still an error. Pinned in `spec/parity/range_closed_form_sums_spec.w`.
- **`type` of a range is `Range` on both engines** — the interpreter still stores `1..2` as a tagged hash, and `type()` now reports `Range` for that record, the same name the runtime already returns. Pinned in `spec/parity/range_type_name_spec.w`.
- **`String#to_i` past i64 stays a BigInt under arithmetic** — a receiver known to be a String infers `:int`, and the direct conversion returns that boxed value, so `s.to_i * 3` promotes instead of unboxing the heap pointer as a machine int. `to_i` on an unknown receiver is still a name-based `:i64` guess. Pinned in `spec/parity/integer_to_i_bignum_spec.w`.
- **One date scene for every host** — the `? date` inspection (header,
  season rail, calendar grid, holiday names and artwork, history panels)
  now lives in `compiler/lib/wit/scenes/date.w` as `DateScene`, a pure function of civil
  fields. The compiled REPL calls it natively and the Ruby REPL evaluates it
  through its interpreter, so the two renderers can no longer drift. New
  names: Christmas Eve, Leap Day, US Independence Day (also Tungsten's
  birthday, with fireworks bursting as a 7 and a 4), Martin Luther King
  Jr. Day, Memorial Day, Labor Day, and the equinoxes and solstices (Meeus
  Table 27.B in scaled integer arithmetic). The compiled REPL gains the
  Valentine's, St. Patrick's, Halloween, Easter, and Thanksgiving art the
  Ruby inspector already had. The current day renders bright white, the
  grid keeps a gutter so `[21]` never shifts the number, and month/year
  scrubs remember the day they started on (Mar 30 → Feb 29 → Jan 30, and
  back). The scene is not on the global autoload manifest: the REPL image
  `use`s it and the Ruby REPL loads the file on first inspection. Two Ruby
  host fixes made that possible: class-body constants now resolve against
  the class that defines the method (previously the caller's scope, which
  broke `Date.in` and any cross-class call into `Calendar`), and a `[]` on
  the line after a control-flow statement is an empty array literal, not an
  index call on the statement's value.

- **`bin/wit` never compiles on launch** — the REPL and Metal compiler
  images are built by `bin/tungsten build` (new `build-image KIND` compiler
  command, same incremental link cache as any compile) and `--repl` only
  execs the last built image, failing fast with "run bin/tungsten build"
  when none exists. Previously every launch after a compiler, core, or REPL
  edit blocked on a ~30s native build. The delegate now `exec`s the image
  (new `Process.exec`) instead of spawning it into its own process group,
  which had left the interactive REPL stopped by the terminal before its
  first prompt. The REPL image no longer links the Metal GPU emitter;
  `@gpu` programs delegate to the metal image as usual. Date scrubbing in
  `wit` (blank Enter after `? date`, then arrows) works again: the nudge
  passed boxed integers to a raw-int leaf, whose tag bits tripped the
  "exceeded the representable year range" guard and killed the REPL.

- **Dates remember civil history without extra bits** — packed `Date` stays a
  Y-M-D-h-m-s tuple. `Date.parse` / `Date.new` accept Sweden's 1712-02-30 and
  Julian century leaps; `23:59:60` only on IERS leap-second dates. Ordinals
  and `+` are proleptic Gregorian; skips/repeats/extra days belong on
  `Date.in`. Packed years are −1024…3071 (unsigned 12-bit `year+1024`). Amsterdam
  `+00:20` packs as a spare tz code; explicit `Z` is not overwritten.
  Constructors reject out-of-range years and oversized day values instead of
  wrapping. Bare `1712-02-30 + 1` raises until `Date.in("Sweden")`.
  Native `?` / `w_value_fields` and Ruby inspection both decode year and tz
  through the unpack helpers. Skip/repeat/extra days are one list on
  `Calendar`; local year length is derived from that list, and both
  inspectors call `Calendar.history_title` / `history_art`. On the Ruby
  engine, `Date.ordinal` no longer dies at `is_a?(Int)`, `Date.parse`
  keeps datetime clocks and rejects non-packed offsets such as `+00:10`,
  catch-up `1712-02-30 + 1` raises instead of clamping to Feb 29, and
  `Date.new(y, m, d)` runs the core class method through a date `ccall`
  allowlist instead of dying with `undefined method ccall`. Clock
  arithmetic wraps ordinary days at 86400 (`23:59:59Z + 1s` is the next
  midnight) and leap-second days at 86401. Ruby `Date.in` autoloads
  calendar constants in the interpreter root env so they survive the
  caller method frame.

- **`Integer#modpow` recognizes two exact Fermat identities** — for the
  BN254 and secp256k1 base-field primes with exponent `p - 1`, it returns
  zero for divisible bases and one otherwise. All modulus/exponent limbs
  are checked; signed and oversized bases retain their existing semantics.
  Added guard-miss regressions and an independent Python-pow oracle. See
  [the MODEXP transfer audit](design/montgomery-entry.md).

- **`Integer#modpow` enters Montgomery form by one division** — the runtime's
  Montgomery ladder (odd moduli of 3 limbs and up) used to compute
  R² = B^2k mod n by a 2k-by-k division and then pay two Montgomery
  multiplies of setup (base·R² and R mod n). It now converts the base with a
  single division of base·B^k (the limb-shift-and-reduce entry from the
  EIP-8200 MODEXP work), and the odd-power window table only builds the prefix
  through the largest row selected by the exponent — a fixed exponent such as
  65537 = 2^16 + 1 builds no additional powers. RSA-shaped 32-limb calls: e=3 3.4 → 1.7 µs,
  e=65537 10.3 → 7.8 µs, full-width exponents unchanged (runtime
  `bench_powmod`, `make bench-powmod`). Prime testing keeps its full context.
  Spec: `spec/numeric/bigint_powmod_entry_spec.w`.

- **Worktrees inherit the host compiler** — `git worktree add` no longer
  leaves you without `bin/tungsten-compiler`. A post-checkout hook (installed
  by `bin/tungsten doctor`) and a `bin/tungsten` fallback symlink the primary
  checkout's compiler into the new tree. An existing local compiler is never
  replaced.

- **Typed rescue and an error hierarchy** — `rescue e: Class` binds only an
  instance of `Class` or a subclass, `rescue Class` matches without binding,
  and a `begin` may carry several rescue clauses tried in source order; an
  unmatched error propagates unchanged (ensure still runs). `Error` now
  descends from the abstract `Exception` and carries `code`, `cause`, `data`
  and `backtrace` alongside `message`, with `with_cause` / `with_code` /
  `with_data` builders and `full_message` (the cause chain, one line each).
  New core classes: `NameError > NoMethodError`, `KeyError`, `IndexError`,
  `ZeroDivisionError`, `OverflowError`, `FrozenError`, `NotImplementedError`,
  `StopIteration`, `IOError > FileNotFound / PermissionDenied / EndOfFile`,
  `NetworkError > ConnectionRefused / TimeoutError / TLSError`, `ParseError`,
  `CancelledError`, `AssertionError`, and `SystemExit` / `Interrupt` directly
  under `Exception`. Runtime failures start mapping onto the hierarchy:
  integer division by zero raises `ZeroDivisionError`, a missing method
  `NoMethodError`, mutation of a frozen AST body `FrozenError`, and the
  string/number coercion failures `TypeError`. Any program containing a
  `begin`/`rescue` or postfix `rescue` links the whole hierarchy, so the typed
  object is always available to a handler; programs with no handler at all
  keep the historical plain-string raise (and die fatally as before). These
  typed runtime failures are rescuable in ordinary programs (plain `die`
  sites stay fatal outside the REPL). The interpreter builds the same typed
  objects for its own undefined-name errors and for tagged runtime messages.
  Typed clauses are a parser desugar, so both engines share one
  implementation. A raise inside a rescue body now runs the begin's `ensure`
  on the compiled engine before propagating, as the interpreter already did.

- **Objects are freed at scope close** — `Cls.new(...)` on a class name now
  lowers to the guarded construct arm (allocate, then call the plain
  initializer worker directly) that `class.new` inside methods already used,
  and the ownership pass treats that fresh object as an owned producer when
  the initializer provably never stores `self`. A devirtualized method call
  on such an object consults the method's escape summary instead of pinning
  the receiver, so `p = Pt.new(i, i + 1); total += p.sum` in a loop no longer
  leaks one WObject per iteration (163 MB → constant at two million
  iterations). Ivar values are not recursed into. Escape summaries
  (`compiler/lib/escape.w`) now cover every retention shape the ownership
  pass knows, distinguish "stored" from "returned", and treat any unknown
  call-shaped instruction as retaining its operands; the ownership pass runs
  after them and uses them for every direct call to a source function.

- **Compile-time arity contracts** — a call that passes more arguments than
  the callee declares, or fewer than its required leading parameters, is a
  compile error (`E_LOWER_ARITY`, `tungsten explain E_LOWER_ARITY`) wherever
  the callee is resolved at compile time: source functions, constructors
  (too many as well as too few), class statics, and instance methods on a
  receiver whose class is exactly known (a local bound from a constructor,
  an exactly typed ivar, `Cls.new(...)`). The interpreter raises the same
  message when it binds parameters. Previously extra arguments were silently
  dropped and missing ones nil-padded (`arr.first(10)` returned `arr.first`).
  Dynamic dispatch on an unknown receiver is not checked, so compiled code
  pays nothing at runtime (runtime builtins and Core methods on erased
  receivers are covered by the follow-up entry above). `TUNGSTEN_ARITY=off`
  disables the check for triage.
- **Explicit partial application** — a bare `_` argument is a placeholder:
  `add(1, _)` is `->(x) add(1, x)`, one parameter per placeholder in argument
  order (`[1, 2, 3].map(add(10, _))`). A name `_` assigned in the enclosing
  function is an ordinary variable.
- **Method references and currying** — `add/2` denotes the source function
  `add` as a closure of arity 2 (the value form of the `-> add/2` declaration
  spelling; the arity must be one the definition accepts). `Closure#arity`
  and `Closure#curry` (`(add/2).curry.call(1).call(2)`; `curry(n)` for a
  closure of unknown arity; arities 1..4) work on both engines. `x/2` on a
  variable is still division; write `(add/2).curry`, since `/` binds looser
  than `.`.
- **Loop temporaries are freed at scope close** — `s = "payload-[i]-" + "x" * 200`
  and `a = [i, i + 1, i + 2, i + 3]` inside a loop body no longer leak one
  allocation per iteration (1.1 GB → 3 MB and 131 MB → 2 MB peak RSS at two
  million iterations). `String * Int` is typed and lowered as a direct
  repeat, integer interpolation parts stringify through a fresh producer, and
  a concat whose operands are anonymous fresh temporaries takes ownership of
  them (`w_str_concat_own`), flattening instead of building a rope that would
  retain both leaves. Array literals are recognized as owned producers. A
  temporary stored in a top-level (global) variable is still retained: it may
  be read from anywhere.
- **Exact `Decimal#round(digits)`** — `(2.345).round(2)` is `2.35` on both
  engines (rounding on the significand, half away from zero); the digits
  argument was silently ignored. `Float#round(digits)` rounds to that many
  places.
- **Inference evidence policy** — `compiler/lib/lowering/inference.w` now
  documents which arms rest on declared, literal, or closed-form evidence,
  and `TUNGSTEN_INFER=boxed` is a reference oracle that routes all untyped
  integer arithmetic through the guarded, promoting runtime path so a
  program's output can be diffed against the default lowering. Unknown-receiver
  `to_i` remains a name-based `:i64` guess. A receiver known to be a String is
  typed `:int`, so a value past i64 stays a BigInt.
- **Cross-engine parity suite** — `spec/parity/` runs each spec through the
  native interpreter and the compiled path and diffs the transcripts
  (`make parity`, `scripts/parity.sh`, `doc/PARITY.md`; a default stage of
  `scripts/test-specs.sh`). Divergences carry a `## parity xfail` header and a
  row in `spec/parity/DIVERGENCES.md`; an unexpected agreement is reported so
  the ledger cannot go stale.
- **Fixed** — `"abcdef"[1..3]` SIGSEGV compiled; `super(name)` in a subclass
  constructor leaving the field empty compiled; `~5` / `~1e10` emitting
  invalid IR; `Hash#count` dying compiled; a raise from a constructor with a
  default or keyword parameter, or from a zero-argument function called
  without parentheses, escaping `begin`/`rescue` compiled; a symbol literal
  passed to a user class's own `select`/`map`/`reject`/`count` being rewritten
  into a block; bracketed prose in core validation messages (`[x, y]`)
  interpolating as code; `BitOrdered`/`BitEqual` missing from the autoload
  manifest; `make specs` running nothing because one spec was unclassified;
  twelve default-lane spec failures (WIRE-record specs, a Range pipeline
  SIGSEGV, an i128 shift miscompile, a postfix-rescue lowering crash, a
  no-raise summary eliding a landing pad, `Tempfile.create`, `Atomic.new`, and
  the S-class relation search bound).
- **Performance** — `bigint_fib` 476 ms → 38 ms (the bigint arena walked every
  chunk on each freelist miss; the drain is now gated on a cross-thread
  release epoch) and `array_fill` 170 ms → 16 ms (a typed-array size was
  treated as an escape, pinning the loop bound boxed). Cross-language suite:
  1.43x vs C, 1.23x vs Rust on the head-to-head geomean.
- **Removed from the tree** — 416 flip-graph result text files (223 MB) under
  `benchmarks/matmul/metaflip/`; see `TODO.md` for the history purge.

### Earlier unreleased notes

- **Machine-int annotated params materialize as raw entry slots** — a
  parameter reassigned anywhere in its body with `## i64/u64` now gets a
  raw machine slot at function ENTRY (the representation a local gets from
  `y = x ## u64`): full-width reads, native 2^64 wrap on UNANNOTATED
  arithmetic reassigns in the same chain (previously those promoted to
  bignums while identical local chains wrapped), and no mid-branch
  retype. Captured and signature-typed params are unaffected.
- **`size`/`length` reachable through dynamic dispatch on String/Symbol** —
  untyped receivers (`f(s).size()`, chained `.to_s().size()` in
  interpolation) previously died with "undefined method 'size' for
  String": the type-class cascade misses core String/Symbol source
  methods (pre-existing gap; other source methods like `reverse` remain
  dynamically unreachable — documented in runtime.c).

- **Annotated reassign of a boxed variable is full-width correct** — a
  `## i64/u64` reassign of an existing parameter or boxed local (e.g.
  inside one branch of an `if`, or an unconditional chain like
  xorshift64* through a parameter) no longer retypes it to a raw machine
  slot; the RHS keeps wrapping semantics but the result is boxed back and
  the variable is classified `:bigint` so subsequent machine-context reads
  take the full-width unbox. Previously post-merge reads mixed NaN-boxed
  and raw bits (silent wrong values at call boundaries), and — even
  unconditionally — values past 2^48 read back through the 48-bit nanunbox
  shortcut were truncated to garbage.
- **begin/rescue is a value expression in compiled code** — in value
  position (method tail, case/if arm, assignment rhs) it now produces the
  taken arm's last expression; both arms previously reached callers as
  nil. `ensure` still runs for effect only. Matches the interpreter.
- **Fused machine-int subscript reads AND writes** — `x = arr[i] ## u64`
  and `arr[i] = x` (machine-int x) on untyped `:var` receivers lower to
  raw runtime reads/writes for typed integer arrays: zero heap boxing
  (previously one dead bignum box per read AND per write past 2^48 — the
  chessbot 1 GB/s leak). Every other receiver keeps byte-identical
  dynamic dispatch.
- **u64×u64 multiply confirmed raw** — annotated u64 multiplies lower to a
  raw wrapping `mul` in all positions; pinned by spec with xorshift64*
  reference vectors.
- Wide-arity (16-param) direct functions with in-body calls pinned by
  spec; dynamic method dispatch keeps its documented 8-argument limit
  (loud error, never corruption).

- **`sleep()` works in compiled binaries** — bare `sleep(duration)` lowers
  to `__w_sleep`, which now exists in the runtime (Int/Float/Decimal
  seconds; `nil` blocks forever; returns the duration). Previously every
  program calling `sleep()` failed at link time with `___w_sleep` undefined.
- **`System` registered in the core auto table** — `System.cpu_count`,
  `System.executable_path`, etc. resolve in compiled programs instead of
  dying with "undefined method for nil".
- **`String#to_i` promotes past i64** — decimals outside the i64 range parse
  to bignums instead of silently saturating at `LLONG_MAX`/`LLONG_MIN`.
  Non-decimal bases keep the fixed-width parse; `String#to_i` still stops at
  underscores (unchanged).
- **Interpolation ruling: ESC-`[` never interpolates** — inside a string, a
  `[` immediately preceded by ESC (0x1B) is literal no matter how the ESC
  was produced (`\e`, `\u001b`, concatenation), so ANSI CSI sequences like `"\e[K"` can
  never be misread as interpolation. Brackets after any other character
  interpolate as before; `\[` remains the escaped-literal form. New specs:
  `spec/compiler/string_interp_esc_bracket_spec.w`,
  `spec/compiler/string_escape_backslash_spec.w`,
  `spec/core/{global_sleep,system_cpu_count,string_to_i_bignum}_spec.w`.

## 2026.07.04 — Public Preview

The first public release of Tungsten: an object-oriented language that reads
like pseudocode — no `end`, braces, or `return`; blocks close by dedent — and
compiles, through its own self-hosted compiler, to native binaries via LLVM
and to Metal GPU kernels via `@gpu fn`.

Highlights of this preview:

- **Self-hosted compiler** — `compiler/tungsten.w` compiles itself; every
  build proves the fixed point (stage 1 and stage 2 emit byte-identical
  LLVM IR).
- **Exact decimals by default** — `3.14` is a Decimal; floats are opt-in
  with `~3.14`. `0.1 + 0.2 == 0.3` is `true`.
- **Currency, units, and percentages as literals** — `$3.50 - 25¢`,
  `299_792_458 m/s`, `price - 15%` (units pipeline in active development on
  the compiled path).
- **Generics, monomorphized** — `Complex<f64>` stamps out a specialized
  class with native arithmetic; powers a hypercomplex numeric tower
  (Complex → Quaternion → Octonion → Sedenion → 256-dimensional algebras).
- **GPU in the language** — `@gpu fn` lowers to Metal Shading Language;
  Tensors share one allocation with Metal 4 `MTLTensor`s (zero-copy);
  single-head attention runs end-to-end on-device.
- **Floating-point math modes** — strict / precise / fast, with scoped
  `@strictmath` / `@fastmath` blocks and explicit `fma()`.
- **Pattern dispatch** — `case`/`when` plus the `recase` re-dispatch
  keyword; interned scrutinees compile to real LLVM switches.
- **REPL that plots** — braille-rendered curves in the terminal with live
  coefficient scrubbing.

Platforms: macOS (Apple silicon) and Linux, x86_64 + arm64.
Requires clang/LLVM; GPU features need macOS 26+.

## 0.1.0

## 0.0.1
