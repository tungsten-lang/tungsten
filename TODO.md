# TODO

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
