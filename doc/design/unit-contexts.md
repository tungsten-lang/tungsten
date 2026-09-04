# Item 21: versioned unit contexts

Proposed API, not implemented. Start with ordinary method calls and immutable
objects; no new parser syntax is required:

```w
lab = UnitContext.load("units/lab-2026-09.json", sha256: "<expected digest>")
reading = lab.quantity(12.5, :sensor_tick)
seconds = lab.convert(reading, :second)

updated = lab.derive("lab-2026-10", {
  sensor_tick: {dimension: :time, scale: 1/48000, offset: 0}
})
```

`derive` creates a new context whose manifest names the parent digest and
explicit overrides. It does not mutate `lab`. Unit names resolve inside that
context; matching spellings in different contexts do not imply equivalent
units. Serialization includes the context digest and unit definition identity,
not a process-local 8-bit unit registry number. A label such as `lab-2026-09`
is descriptive; content hashes establish identity.

Return a `ContextQuantity` wrapper carrying magnitude, dimensional definition,
point/delta origin and context identity. This avoids prematurely changing
packed Quantity's ABI or exhausting its registry identifiers. When converting
to built-in SI units, preserve exact Rational/Decimal arithmetic and the
existing Quantity point/delta rules. An affine offset applies to points, never
to deltas. Mixing incompatible contexts requires explicit conversion into a
chosen destination context, even when dimensions match.

A context manifest contains schema version, identity, parent digest, exact
scales/offsets, dimensions, source/calibration references, effective interval,
and uncertainty where applicable. Exchange-rate tables and physical equivalences
must remain explicit conversions with their own date/provenance; they must not
silently become ordinary dimensional unit conversions. Existing
`Quantity.equivalent(target, using)` remains explicitly opt-in.

Later convenience syntax could be `lab.with -> (units) ...`, still passing a
lexically bound object. Avoid a mutable process-global "current context";
concurrent tasks would otherwise depend on timing. If task-local defaults are
introduced, children capture the immutable parent context at spawn and an
explicit context always wins.

Start with load/hash validation, exact scale/affine conversion and serialization.
Test two conflicting calibrations concurrently, point versus delta conversions,
parent override resolution and round trips after registry IDs change. Notes
should show the calibration label with its digest and source next to results.
