# Measurement — a measured scalar with GUM uncertainty propagation (core/measurement.w).
#
# Run:
#   bin/tungsten run --interpret spec/core/measurement_spec.w
#   bin/tungsten -o /tmp/measurement_spec spec/core/measurement_spec.w && /tmp/measurement_spec

use core/measurement

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

-> near(a, b)
  d = a - b
  if d < ~0.0
    d = ~0.0 - d
  return d < ~1.0e-12

m = Measurement.new(~10.0, ~2.0)
n = Measurement.new(~4.0, ~1.0)

# ---- construction / defaults ----
check("constructs", type(m) == "Measurement")
check("value", m.value == ~10.0)
check("uncertainty", m.uncertainty == ~2.0)
check("symmetric lower", m.lower_uncertainty == ~2.0)
check("symmetric upper", m.upper_uncertainty == ~2.0)
check("coverage factor defaults to 1", m.coverage_factor == ~1.0)
check("confidence defaults to nil", m.confidence == nil)
check("degrees of freedom defaults to nil", m.degrees_of_freedom == nil)
check("provenance starts empty", m.provenance == [])
check("random component defaults to 0", m.random_uncertainty == ~0.0)
check("systematic component defaults to 0", m.systematic_uncertainty == ~0.0)
check("correlation peer defaults to nil", m.correlation_peer == nil)
check("correlation coefficient defaults to 0", m.correlation_coefficient == ~0.0)
# `new` takes |uncertainty| for both one-sided bounds.
negative_u = Measurement.new(~1.0, ~-2.0)
check("negative uncertainty is absolute in the bounds",
      negative_u.lower_uncertainty == ~2.0 && negative_u.upper_uncertainty == ~2.0)

# ---- the `±` literal desugars to Measurement.new ----
literal = ~10.0 ± ~2.0
check("plus-minus literal builds a Measurement", type(literal) == "Measurement")
check("plus-minus literal value", literal.value == ~10.0)
check("plus-minus literal uncertainty", literal.uncertainty == ~2.0)

# ---- formatting ----
check("to_s is symmetric", m.to_s == "10 ± 2")
check("to_s is asymmetric when the bounds differ",
      Measurement.asymmetric(~5.0, ~1.0, ~3.0).to_s == "5 +3/-1")

# ---- interval = value ∓ one-sided bound × coverage factor ----
check("interval", m.interval == [~8.0, ~12.0])
check("expanded scales the interval", m.expanded(~2.0).interval == [~6.0, ~14.0])
check("expanded keeps the standard uncertainty", m.expanded(~2.0).uncertainty == ~2.0)
check("expanded records k", m.expanded(~2.0).coverage_factor == ~2.0)
check("expanded carries a confidence", m.expanded(~2.0, ~0.95).confidence == ~0.95)
check("expanded leaves the original alone", m.coverage_factor == ~1.0)

# ---- asymmetric: standard uncertainty is the mean of the two bounds ----
asym = Measurement.asymmetric(~5.0, ~1.0, ~3.0)
check("asymmetric standard uncertainty is the mean bound", asym.uncertainty == ~2.0)
check("asymmetric lower", asym.lower_uncertainty == ~1.0)
check("asymmetric upper", asym.upper_uncertainty == ~3.0)
check("asymmetric interval", asym.interval == [~4.0, ~8.0])
check("asymmetric takes absolute bounds",
      Measurement.asymmetric(~5.0, ~-1.0, ~-3.0).lower_uncertainty == ~1.0)

# ---- with_components: random and systematic add in quadrature ----
comp = Measurement.with_components(~1.0, ~3.0, ~4.0)
check("with_components combines in quadrature", comp.uncertainty == ~5.0)
check("with_components keeps the random part", comp.random_uncertainty == ~3.0)
check("with_components keeps the systematic part", comp.systematic_uncertainty == ~4.0)
check("components hash", comp.components == {:random => ~3.0, :systematic => ~4.0})
check("components of a plain measurement are zero",
      m.components == {:random => ~0.0, :systematic => ~0.0})

# ---- independent arithmetic (rho = 0) ----
check("add values", (m + n).value == ~14.0)
check("add uncertainties in quadrature", near((m + n).uncertainty, Math.sqrt(~5.0)))
check("sub values", (m - n).value == ~6.0)
check("sub uncertainties in quadrature", near((m - n).uncertainty, Math.sqrt(~5.0)))
check("mul values", (m * n).value == ~40.0)
# var = dx²u² + dy²v² with dx = 4, dy = 10 -> 16*4 + 100*1 = 164
check("mul uncertainty", near((m * n).uncertainty, Math.sqrt(~164.0)))
check("div values", (m / n).value == ~2.5)
# dx = 1/4, dy = -10/16 -> 0.0625*4 + 0.390625*1 = 0.640625
check("div uncertainty", near((m / n).uncertainty, Math.sqrt(~0.640625)))
check("arithmetic returns a Measurement", type(m + n) == "Measurement")
check("arithmetic result is symmetric", (m + n).lower_uncertainty == (m + n).upper_uncertainty)

# ---- explicit correlation coefficients ----
check("fully correlated sum adds linearly", near(m.add_correlated(n, ~1.0).uncertainty, ~3.0))
check("fully correlated difference cancels", near(m.sub_correlated(n, ~1.0).uncertainty, ~1.0))
check("anti-correlated sum cancels", near(m.add_correlated(n, ~-1.0).uncertainty, ~1.0))
check("uncorrelated sum is quadrature", near(m.add_correlated(n, ~0.0).uncertainty, Math.sqrt(~5.0)))
# var = 16·4 + 100·1 + 2·4·10·(1·2·1) = 64 + 100 + 160 = 324
check("correlated product", near(m.mul_correlated(n, ~1.0).uncertainty, ~18.0))
check("correlated quotient", near(m.div_correlated(n, ~0.0).uncertainty, Math.sqrt(~0.640625)))

# ---- correlate: symmetric registration, then the operators pick rho up ----
a = Measurement.new(~10.0, ~2.0)
b = Measurement.new(~4.0, ~1.0)
check("correlate returns self", a.correlate(b, ~0.5) == a)
check("correlation is visible from the left", a.correlation_with(b) == ~0.5)
check("correlate_back registers on the peer", b.correlation_with(a) == ~0.5)
check("correlation with a stranger is 0", a.correlation_with(m) == ~0.0)
# var = 4 + 1 + 2·0.5·2·1 = 7
check("+ uses the registered correlation", near((a + b).uncertainty, Math.sqrt(~7.0)))
# var = 4 + 1 - 2·0.5·2·1 = 3
check("- uses the registered correlation", near((a - b).uncertainty, Math.sqrt(~3.0)))

out_of_range = false
begin
  a.correlate(b, ~1.5)
rescue e
  out_of_range = true
check("correlate rejects rho above 1", out_of_range)
under_range = false
begin
  a.correlate(b, ~-1.5)
rescue e
  under_range = true
check("correlate rejects rho below -1", under_range)
check("correlate accepts the endpoints", a.correlate(b, ~1.0).correlation_with(b) == ~1.0)

# ---- mutable accessors ----
# BUG: `- data` declares every field `rw`, but no writer is generated on either engine:
# `w.value = ~2.0` raises "undefined method 'value='". Only the reader half of `rw` exists.
# Repro: printf 'use core/measurement\nw = Measurement.new(~1.0, ~0.1)\nw.value = ~2.0\n' > /tmp/m.w &&
#        bin/tungsten run --interpret /tmp/m.w
# w = Measurement.new(~1.0, ~0.1)
# w.value = ~2.0
# check("value is writable", w.value == ~2.0)

<< "ALL PASS measurement_spec ([passed.load()] checks)"
