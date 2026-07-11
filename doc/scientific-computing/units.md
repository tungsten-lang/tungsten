# Quantities, measurements, and unit-carrying tensors

Tungsten has two complementary representations:

- `Quantity` stores one numeric value and one unit.
- `Tensor<f64, m/s>.zeros([100, 100])` stores one unit for a homogeneous
  numeric buffer. Elements stay unboxed; the tensor carries the unit once.

An array of `Quantity` values is still useful when every element may have a
different unit. A unit-carrying tensor is the representation for scientific
kernels where all elements have the same meaning.

## Dimensions and semantic kinds

A dimension contains the eight SI exponent axes (length, mass, time, current,
temperature, amount, luminous intensity, and information) plus sparse semantic
axes. The latter keep concepts with the same SI exponents from becoming
accidentally interchangeable.

Angle is an explicit semantic dimension. `rad`, `deg`, `turn`, `arcmin`, and
angular-rate units convert within it. This does **not** change energy to
`N·m·θ`: the joule remains `kg·m²/s²`. Torque is represented as the same SI
exponents plus a `torque` semantic tag, so `N·m` and `J` cannot silently mix.

The same mechanism distinguishes:

- heat capacity from entropy (`heat_capacity` and `entropy`);
- absorbed dose from specific energy (`Gy` and `specific_energy`);
- absorbed dose from equivalent dose (`Gy` and `Sv`);
- activity, frequency, heart rate, and rotational rate (`Bq`, `Hz`, `bpm`,
  and `rpm`).

Rate units remain compositional: `Hz·s` is a cycle, `Bq·s` is a decay,
`bpm·min` is a beat, and `rpm·min` is a revolution. A plain undefined symbol
still participates in symbolic algebra (`2x + 3x`); define it as a unit when
conversion or a semantic identity is required.

The compiler rejects a known mismatch such as this during lowering:

```tungsten
distance = 10 m
elapsed = 2 s
distance + elapsed       # compile error: quantity dimension mismatch
```

This analysis is conservative. If a unit is produced by dynamic user code,
the established runtime dimension check remains the safety boundary.

## Points and deltas

Ordinary quantities are vectors, preserving familiar arithmetic:

```tungsten
10 m + 10 m                         # 20 m
```

Use a point annotation when a value is a coordinate in an affine space and a
delta annotation when it is a displacement. Origins are optional but, when
present, must agree.

```tungsten
p = (10 m).point(:map)
d = (2 m).delta(:map)
p + d                               # point at 12 m
p - (3 m).point(:map)               # delta of 7 m
p + (3 m).point(:map)               # error: cannot add two points
```

The algebra is:

| Expression | Result |
|---|---|
| vector + vector | vector |
| point + delta, delta + point | point |
| point - delta | point |
| point - point | delta |
| point + point | error |
| multiplication or division involving a point | error |

Absolute temperatures are points by default; `ΔK`, `Δ°C`, and the other delta
temperature units are vectors. Explicit `.point`/`.delta` annotations extend
the same rule to positions, timestamps, voltages relative to a reference, and
other affine coordinate systems.

## Measurements and uncertainty

`±` is a literal-form operator in both front ends and the compiled REPL:

```tungsten
x = 10.0 ± 0.2
```

`Measurement` stores a standard uncertainty and may also carry asymmetric
bounds, a coverage factor/confidence level, degrees of freedom, named
random/systematic components, correlations, and provenance. First-order
arithmetic propagates covariance. Use seeded Monte Carlo propagation for a
nonlinear model:

```ruby
x = Tungsten::Measurement.new(2.0, 0.1)
y = Tungsten::Measurement.propagate(x, samples: 20_000, seed: 7) { |v| v**2 }
```

Values and uncertainty are formatted together using uncertainty-aware
significant digits. `expanded(k, confidence:)` records expanded uncertainty;
`interval` returns the corresponding bounds.

## Calibration

Calibration is a measurement model, not a conversion alias. Tungsten uses a
polynomial model `y = c0 + c1·x + c2·x² + …`, with coefficient uncertainties,
optional coefficient covariance, an additional standard-uncertainty term, a
valid input range, and certificate metadata. Applying it to a `Measurement`
propagates the input and calibration uncertainty and appends the certificate
identifier to provenance.

```ruby
certificate = Tungsten::CalibrationCertificate.new(
  id: "CAL-42", laboratory: "Example Lab", traceability_chain: ["SI"]
)
calibration = Tungsten::Calibration.new(
  coefficients: [1, 2], coefficient_uncertainties: [0.1, 0.05],
  standard_uncertainty: 0.2, valid_range: 0..10, certificate: certificate
)
result = (3.0 ± 0.4).calibrate(calibration)
```

The certificate fields follow common VIM/GUM calibration vocabulary:
identity, laboratory, issue/validity dates, reference, method, conditions, and
traceability chain. Metadata supports documenting a traceability claim; merely
constructing the object does not establish traceability.

## Explicit physical equivalencies

Ordinary conversion never crosses dimensions. Physical equivalencies must name
the bridge:

```tungsten
(1 kg).equivalent("J", :mass_energy)
(500 nm).equivalent("Hz", :spectral)
(300 K).equivalent("J", :thermal)
```

The bridges use the exact SI values of `c`, `h`, and `k_B`. They are opt-in so
that a routine unit conversion cannot unexpectedly reinterpret a quantity.

## Tensor units

```tungsten
velocity = Tensor<f64, m/s>.zeros([100, 100])
```

The dtype and unit are aggregate metadata; the buffer contains raw `f64`
values. Addition/subtraction require identical units. Multiplication and
division combine unit expressions, and tensor views preserve the annotation.
The initial CPU factory supports `f32` and `f64`; GPU dtypes remain available
through the existing runtime-dtype factories.
