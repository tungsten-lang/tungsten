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

Today SciIO only implements **TH5C/TH5D** — Tungsten-native payloads under the
HDF5 file signature (single or multi-named contiguous f32). That is not full
HDF5. Remaining work:

- Walk real HDF5 object headers (OHDR), B-trees, local/fractal heaps, and
  links so foreign files from h5py / `h5dump` / NetCDF-4-on-HDF5 can be read.
- Groups, attributes, named datatypes, and soft/external links.
- Datatypes beyond contiguous little-endian f32 (f64, integers, strings,
  compound types; endianness).
- Chunked layouts, compression filters, and virtual datasets.
- Decide whether to grow the pure-C walker in `runtime/sci_io_native.c` or
  add an optional `libhdf5` bridge (currently not linked by default).
- Keep TH5 as a fast interop subset for Tungsten↔Tungsten; do not break
  existing TH5C/TH5D readers when adding the full path.
