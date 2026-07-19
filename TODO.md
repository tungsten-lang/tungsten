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
