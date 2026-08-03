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

3. **Compiled StringBuffer#append drops non-literal strings inside any
   function body.** At top level all appends work; inside a `->` body
   (top-level fn, instance or class method), `sb.append(x)` where x is a
   param, a local, or a `+`-concat result appends NOTHING (only literals,
   interpolated strings, and `.to_s` results survive). Repro:
   `-> tf(x)\n  sb = StringBuffer(256)\n  sb.append(x)\n  sb.to_s` returns
   "". Likely a representation mismatch on the w_strbuf_append fast path
   (compiler/lib/lowering/method_call.w:978). Workaround used in
   core/plot3d.w: wrap every dynamic append arg in interpolation
   (`sb.append("[v]")`).

4. **Quantity arg slot clobbered: inline `.class.to_s` guard + early
   return + `case`.** In a class method
   `if value.class.to_s != "Quantity"\n  return value.to_f()\n case ...`,
   the quantity in `value` is corrupted before the case body's unit pipe
   (dies "| unit conversion expects a quantity"). Landing the class name
   in a local first avoids it. A related shape: a `case` whose branches
   contain quantity literals miscompiled branch selection inside
   core/physics Physics.si until it was rewritten as an if-chain (both
   guards documented in core/physics/constants.w).

5. **`bin/tungsten -c` rejects array types in typed signatures.** Even
   the doc example `-> dot(xs, ys, n) (f64[] f64[] i64) f64` fails
   `-c` with "expected ')'" while running/compiling the same file works.
   Checker-path lexer/parser divergence.

6. **Stage binaries went stale across the unit-registry expansion
   (b7269d7): compiled `1 kg/m³` printed `1 mickey`.** The committed
   tables were consistent, but the cached stage compiler + prebuilt
   runtime predated the expansion, so compile-time unit ids and the
   linked runtime's unit_names[] disagreed by 4 slots. `build --force`
   resyncs; the build should fingerprint the generated unit tables into
   its staleness check so a registry change invalidates stages
   automatically. (Also: `gen_units.rb --check` rewrites the generated
   files — mtime churn — while reporting "up to date"; it should diff
   without writing.)

7. **Interpreter: `Class.method(["array", "literal"])` binds the array as
   a block.** `A.enc(["a", "b"])` with `-> .enc(v) JSON.encode(v)` raises
   "Undefined variable or method 'item'" interpreted (works compiled).

8. **Packed lexer mis-scans heredoc content (`Unexpected token
   TYPE_HINT(<<~JS…`).** Heredocs whose bodies look token-dense to the
   fast64 tokenizer (e.g. many `//`-prefixed JavaScript lines) come back
   as a TYPE_HINT token instead of a STRING. Not a pure size limit:
   170 lines × 100 chars (17 KB) passes while 200 × 38 (8 KB) and
   1000 × 8 fail. Repro: `+ T` / `-> .a` / `<<~JS` + 300 lines of
   `// pad N …` + `JS`. Likely the fast64 pre-tokenizer scanning inside
   the heredoc span (`//` starts a regex/comment state) and the packed
   12-bit length or the materializer skip logic losing sync. Workaround:
   core/plot3d.w ships its viewer JS/CSS as data/viewer3d assets read at
   runtime instead of heredocs.

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

**Trigger:** Phase 3 `--fast` clause sharing lands AND demonstrates superlinear
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
