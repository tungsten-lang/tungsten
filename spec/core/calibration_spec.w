# Calibration — polynomial measurement model with traceability metadata (core/calibration.w).
#
# Coefficients are stored lowest-order first: [a0, a1, a2] means a0 + a1·x + a2·x².
#
# Run:
#   bin/tungsten run --interpret spec/core/calibration_spec.w
#   bin/tungsten -o /tmp/calibration_spec spec/core/calibration_spec.w && /tmp/calibration_spec

use core/calibration
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

# 1 + 2x + 3x², coefficient uncertainties 0.1 / 0.2 / 0.3, u_cal = 0.5, valid on [0, 10].
c = Calibration.new([~1.0, ~2.0, ~3.0], [~0.1, ~0.2, ~0.3], "V", "K", ~0.5, ~0.0, ~10.0, "CERT-1")

# ---- construction / metadata ----
check("constructs", type(c) == "Calibration")
check("coefficients", c.coefficients == [~1.0, ~2.0, ~3.0])
check("coefficient uncertainties", c.coefficient_uncertainties == [~0.1, ~0.2, ~0.3])
check("input unit", c.input_unit == "V")
check("output unit", c.output_unit == "K")
check("standard uncertainty", c.standard_uncertainty == ~0.5)
check("validity minimum", c.valid_min == ~0.0)
check("validity maximum", c.valid_max == ~10.0)
check("certificate", c.certificate == "CERT-1")
check("reference defaults to nil", c.reference == nil)
check("method defaults to nil", c.method == nil)
check("conditions default to nil", c.conditions == nil)
check("traceability chain starts empty", c.traceability_chain == [])

# ---- polynomial: Horner over ascending coefficients ----
check("polynomial at 0 is the constant term", c.polynomial(~0.0) == ~1.0)
check("polynomial at 1 sums the coefficients", c.polynomial(~1.0) == ~6.0)
# 1 + 2·2 + 3·4 = 17
check("polynomial at 2", c.polynomial(~2.0) == ~17.0)
# 1 - 2 + 3 = 2
check("polynomial at -1", c.polynomial(~-1.0) == ~2.0)

# ---- derivative: 2 + 6x ----
check("derivative at 0", c.derivative(~0.0) == ~2.0)
check("derivative at 1", c.derivative(~1.0) == ~8.0)
check("derivative at 2", c.derivative(~2.0) == ~14.0)
check("derivative of a constant model is 0", Calibration.linear(~0.0, ~7.0).derivative(~3.0) == ~0.0)

# ---- coefficient_variance: Σ (xⁱ · u_i)² ----
check("coefficient variance at 0 is the constant term alone",
      near(c.coefficient_variance(~0.0), ~0.01))
# 0.1² + 0.2² + 0.3² = 0.14
check("coefficient variance at 1", near(c.coefficient_variance(~1.0), ~0.14))
# 0.1² + (2·0.2)² + (4·0.3)² = 0.01 + 0.16 + 1.44 = 1.61
check("coefficient variance at 2", near(c.coefficient_variance(~2.0), ~1.61))

# ---- Calibration.linear(slope, intercept) ----
lin = Calibration.linear(~3.0, ~1.0)
check("linear stores intercept first", lin.coefficients == [~1.0, ~3.0])
check("linear evaluates", lin.polynomial(~2.0) == ~7.0)
check("linear slope is the derivative", lin.derivative(~2.0) == ~3.0)
check("linear has zero coefficient uncertainty", lin.coefficient_uncertainties == [~0.0, ~0.0])
check("linear has no validity bounds", lin.valid_min == nil && lin.valid_max == nil)
check("linear intercept defaults to 0", Calibration.linear(~2.0).polynomial(~3.0) == ~6.0)
check("linear default standard uncertainty", Calibration.linear(~2.0).standard_uncertainty == ~0.0)
check("linear carries units and certificate",
      Calibration.linear(~2.0, ~0.0, "A", "N", ~0.1, "C2").output_unit == "N")

# ---- apply: propagate a Measurement through the model ----
m = Measurement.new(~2.0, ~0.1)
r = c.apply(m)
check("apply returns a Measurement", type(r) == "Measurement")
check("apply evaluates the polynomial", r.value == ~17.0)
# u² = (14·0.1)² + 1.61 + 0.5² = 1.96 + 1.61 + 0.25 = 3.82
check("apply combines input, coefficient and calibration uncertainty",
      near(r.uncertainty, Math.sqrt(~3.82)))
check("apply result is symmetric", r.lower_uncertainty == r.upper_uncertainty)
check("apply records the certificate in the provenance", r.provenance == ["calibration CERT-1"])
check("Measurement#calibrate is apply", m.calibrate(c).value == r.value)

# An uncertified model leaves provenance untouched.
plain = Calibration.linear(~2.0, ~1.0)
plain_result = plain.apply(Measurement.new(~3.0, ~0.5))
check("uncertified apply value", plain_result.value == ~7.0)
check("uncertified apply uncertainty", near(plain_result.uncertainty, ~1.0))
check("uncertified apply leaves provenance empty", plain_result.provenance == [])

# ---- validity range is enforced on the input value ----
below = false
begin
  c.apply(Measurement.new(~-1.0, ~0.1))
rescue e
  below = true
check("apply rejects an input below the validity range", below)
above = false
begin
  c.apply(Measurement.new(~11.0, ~0.1))
rescue e
  above = true
check("apply rejects an input above the validity range", above)
check("apply accepts the lower endpoint", c.apply(Measurement.new(~0.0, ~0.0)).value == ~1.0)
check("apply accepts the upper endpoint", c.apply(Measurement.new(~10.0, ~0.0)).value == ~321.0)
check("an unbounded model accepts anything", plain.apply(Measurement.new(~-999.0, ~0.0)).value == ~-1997.0)

<< "ALL PASS calibration_spec ([passed.load()] checks)"
