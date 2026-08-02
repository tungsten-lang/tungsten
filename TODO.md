# TODO

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
