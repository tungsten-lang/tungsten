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

## Scientific registry coverage

The generated compiler and the Ruby interpreter share one registry. In
addition to the seven SI base units, all 22 SI units with special names, and
coherent compound expressions, the registry materializes every supported
symbolic SI prefix from quetta (`Q`, 10³⁰) through quecto (`q`, 10⁻³⁰). IEC
binary prefixes run from kibi (`Ki`, 2¹⁰) through quebi (`Qi`, 2¹⁰⁰). Exact
unit and alias spellings take precedence over prefix decomposition, so `M` is
molar concentration while `Mm` is a megametre.

The focused cross-domain surface includes:

| Domain | Representative units and conventions |
|---|---|
| Chemistry and laboratory | `M`, `mmol/L`, `mg/dL`, `Eq`, `mEq/L`, `osmol`, `mOsm/L`, `U_enzyme`, `U/L`, `Svedberg` |
| Biology and biomedicine | `IU`, `CFU`, `PFU`, `cells/mL`, `copies/mL`, analyte-scoped glucose units |
| Electromagnetism | `Ah`, `var`, `VA`, SI electrical units, and explicit CGS-EMU/ESU forms such as `abA`, `statV`, and `statΩ` |
| Optics and photonics | `phot`, `fc`, `diopter`, `W/sr`, `W/sr/m²`, `Jy`, `photon`, `einstein`, and photon-flux density |
| Radiation and nuclear | `Bq`, `Ci`, `dpm`, `Gy`, `rad_dose`, `Sv`, `R_exposure`, activity/dose rates, and detector `count` rates |
| Astronomy | `au`, `ly`, `pc` and prefixes, `mas`, `µas`, `Jy` and prefixes, `foe`, and exact IAU nominal solar conversions |
| Geoscience and meteorology | `DU`, `PVU`, `sverdrup`, `darcy`, `mGal`, `Eotvos`, `TECU`, `gpm`, `clo`, `ppmv`, and `ppmw` |
| Computing and research | decimal/binary information units, `baud`, `bit/symbol`, common link and memory rates, `TEPS`, `GUPS`, and energy-efficiency units |

Some examples:

```tungsten
1 M | mmol/L                 # 1000 mmol/L
1 statV | V                  # 299.792458 V
1 Jy | W/m²/Hz               # 1e-26 W/m²/Hz
1 rad_dose | Gy              # 0.01 Gy
1 sverdrup | "m³/s"          # 1000000 m³/s
1 Rm | Qm                    # 0.001 Qm
1 Kib | b                    # 1024 b
```

### Conversion-pipe targets

The right side of a conversion pipe is a unit spelling, written bare in any
of the registry's forms — simple (`| km`), prefixed and mixed-case (`| eV`,
`| mmHg`, `| kWh`), compound with `/` and `·` (`| km/h`, `| W/m²/Hz`,
`| kg·m/s`), and with superscript exponents (`| W/m²`). Rounding digits
attach in parentheses: `| cm(2)`, `| km/h(2)`, `| eV(3)`.

A quoted spelling (`| "m³/s"`) is always accepted and remains necessary for
names the expression grammar cannot carry bare: multi-word spellings such as
`"metric cup"` and negative superscript exponents such as `"cm⁻¹"`.

A bare component that names a local variable or function keeps its ordinary
expression meaning — shadowed spellings fall back to division/bitwise-or, so
`x | y` on integers stays bitwise-or whenever `y` is real code. Conversion
pipes also work inside string interpolation, which is the idiomatic
formatting position:

```tungsten
speed = 5 m/s
<< "cruise: [speed | km/h(1)]"      # cruise: 18 km/h
<< "flux: [340.25 W/m² | W/m²]"     # flux: 340.25 W/m²
```

### Attaching units to bare numbers and arrays

A pipe whose left side is a bare number has nothing to convert from, so it
*attaches* the unit instead: `2.5 | km` is `2.5 km`. Piped onto an array,
the conversion maps elementwise — decimals and ints attach, quantities
convert — which pairs with the `%d[…]` decimal-array literal for building
measurement series:

```tungsten
samples = %d[1.0 2.5 4.0] | m/s     # [1 m/s, 2.5 m/s, 4 m/s]
samples | km/h                       # [3.6 km/h, 9 km/h, 14.4 km/h]
samples.mean                         # 2.5 m/s
samples.stdev                        # sample σ, unit re-attached
```

Array statistics (`mean`, `variance`, `stdev`, `median`) are quantity-aware:
`mean`/`median` keep the element unit, `variance` carries the squared unit,
and `stdev` converts elements to the first element's unit before taking σ.

The registry keeps common same-shape distinctions semantic. Baud is symbols
per second, not bits per second. `M` cannot silently add to `mEq/L`; `CFU`
cannot add to `PFU`; `ppmv` cannot add to `ppmw`; `rad_dose`, `Gy`, `Sv`, and
`R_exposure` preserve their radiation quantity kinds. A named bridge or
domain model is required when chemistry, density, biological response, or
encoding supplies the missing context.

### Conversion and reference policy

Definitions that are exact are stored as integers or rationals. This includes
post-2019 SI constants used by conversions, the international foot, the
electronvolt, CGS electrical relationships derived from exact `c`, the enzyme
unit, and the separately named `cal_IT` (4.1868 J) and `cal_th` (4.184 J).
Measured or conventional factors retain that status in external metadata
instead of being described as exact observations.

The registry also labels entries by role:

- ordinary and nominal units have linear conversions;
- `R_sun_nominal` and `L_sun_nominal` are exact IAU conversion constants,
  distinct from uncertain estimates of actual solar radius and luminosity;
- `electron_mass` and similar compatibility entries are physical constants,
  while `solarmass` and planetary-property entries are measured reference
  quantities;
- `IU` is contextual: its physical conversion depends on the named biological
  preparation;
- ordinal and logarithmic entries are reference scales, not linear units.

`? 1 unit` exposes the role plus externally loaded description, etymology,
history, authority, date, and exact/measured status when available.

Deliberate exclusions are pH and other analyte-dependent logarithmic scales;
referenced decibel variants, absorbance/optical density, and stellar magnitude
zero points as linear conversions; standard-volume gas units without a stated
temperature/pressure convention; Mach without a medium and state; and
clinical conversions without a named analyte. These belong in `LogQuantity`,
calibration/equivalency APIs, or explicit contextual names rather than the
linear unit registry.

The coverage and spelling policy follow the [BIPM SI Brochure](https://www.bipm.org/en/publications/si-brochure),
with cross-domain spellings informed by [UCUM](https://unitsofmeasure.org/ucum).
Nominal solar values follow [IAU Resolution B3](https://www.iau.org/common/Uploaded%20files/IAUGA2015-Resolution-B3-recommended-nominal-conversion.pdf).

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
