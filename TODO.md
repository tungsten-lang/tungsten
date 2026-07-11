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
