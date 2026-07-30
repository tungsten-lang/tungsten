# Transcendental closure across Complex, TaylorJet, Differential, and
# complex-valued adaptive quadrature.
#
# Run in both engines:
#   bin/tungsten run spec/core/calculus_complex_spec.w
#   bin/tungsten compile spec/core/calculus_complex_spec.w \
#     --out /tmp/calculus-complex-spec

use calculus

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> close?(got, want, tolerance = ~1.0e-10)
  difference = got - want
  difference = ~0.0 - difference if difference < ~0.0
  difference <= tolerance

-> relative_close?(got, want, tolerance = ~1.0e-12)
  difference = got - want
  difference = ~0.0 - difference if difference < ~0.0
  scale = want
  scale = ~0.0 - scale if scale < ~0.0
  scale = ~1.0 if scale < ~1.0
  difference <= tolerance * scale

-> complex_close?(got, want, tolerance = ~1.0e-10)
  real_close = close?(got.real, want.real, tolerance)
  imag_close = close?(got.imag, want.imag, tolerance)
  real_close && imag_close

zero = Complex<f64>.zero
one = Complex<f64>.one
i = Complex<f64>.i

zero_log_raised = false
begin
  zero.log
rescue error
  zero_log_raised = true
check("complex.log.zero.is_loud", zero_log_raised)

# --- principal complex elementary functions ------------------------------

check("complex.i.square", complex_close?(i.sq, Complex<f64>.real(~-1.0)))
check("complex.cis.pi",
      complex_close?(Complex<f64>.cis(~3.141592653589793),
                     Complex<f64>.real(~-1.0)))

polar = Complex<f64>.polar(~2.5, ~0.7)
check("complex.polar.radius", close?(polar.abs, ~2.5))
check("complex.polar.angle", close?(polar.arg, ~0.7, ~2.0e-13))

euler = i.scale(~3.141592653589793).exp
check("complex.euler", complex_close?(euler, Complex<f64>.real(~-1.0)))

z = Complex<f64>.new([~0.4, ~-0.3])
check("complex.to_s", z.to_s.starts_with?("Complex("))
check("complex.exp.log", complex_close?(z.exp.log, z, ~2.0e-13))

negative_root = Complex<f64>.real(~-4.0).sqrt
check("complex.sqrt.negative",
      complex_close?(negative_root, Complex<f64>.new([~0.0, ~2.0])))
check("complex.sqrt.square",
      complex_close?(z.sqrt.sq, z, ~2.0e-10))
huge = Complex<f64>.new([~3.0e300, ~4.0e300])
check("complex.abs.scaled", relative_close?(huge.abs, ~5.0e300))
huge_root = huge.sqrt
check("complex.sqrt.scaled.real",
      relative_close?(huge_root.real, ~2.0e150))
check("complex.sqrt.scaled.imag",
      relative_close?(huge_root.imag, ~1.0e150))

trig_identity = z.sin.sq + z.cos.sq
check("complex.trig.identity", complex_close?(trig_identity, one, ~2.0e-10))
hyperbolic_identity = z.cosh.sq - z.sinh.sq
check("complex.hyperbolic.identity",
      complex_close?(hyperbolic_identity, one, ~2.0e-10))
check("complex.tan.quotient",
      complex_close?(z.tan, z.sin / z.cos, ~2.0e-10))
check("complex.tanh.quotient",
      complex_close?(z.tanh, z.sinh / z.cosh, ~2.0e-10))

check("complex.asin.inverse",
      complex_close?(z.sin.asin, z, ~4.0e-13))
check("complex.atan.inverse",
      complex_close?(z.tan.atan, z, ~4.0e-13))
check("complex.asinh.inverse",
      complex_close?(z.sinh.asinh, z, ~4.0e-13))
check("complex.atanh.inverse",
      complex_close?(z.tanh.atanh, z, ~4.0e-13))
check("complex.acos.complement",
      complex_close?(z.asin + z.acos,
                     Complex<f64>.real(~1.5707963267948966),
                     ~4.0e-13))
check("complex.acosh.inverse",
      complex_close?(z.cosh.acosh, z, ~4.0e-13))

square_root_power = z.pow(~0.5)
check("complex.principal.power",
      complex_close?(square_root_power.sq, z, ~4.0e-13))
imaginary_power = i.pow(i)
check("complex.imaginary.power",
      complex_close?(imaginary_power,
                     Complex<f64>.real(Math.exp(~-1.5707963267948966)),
                     ~4.0e-13))

atan_samples = [~-100.0, ~-1.0, ~-0.4, ~0.0, ~0.4, ~1.0, ~100.0]
atan_samples.each ->
  expected = Math.atan2(item, ~1.0)
  check("math.atan.libm." + item.to_s,
        close?(Math.atan(item), expected, ~3.0e-15))
atan_max_error = ~0.0
atan_index = 0
while atan_index <= 4000
  atan_input = (atan_index + ~0.0) / ~20.0 - ~100.0
  atan_error = Math.atan(atan_input) - Math.atan2(atan_input, ~1.0)
  atan_error = ~0.0 - atan_error if atan_error < ~0.0
  atan_max_error = atan_error if atan_error > atan_max_error
  atan_index += 1
check("math.atan.libm.grid", atan_max_error <= ~3.0e-15)
infinity = Math.exp(~1000.0)
check("math.hypot.infinity", Math.hypot(infinity, infinity).infinite?)

# --- the same elementary surface through automatic differentiation --------

asin_jet = Calculus.taylor(-> (x) x.asin, ~0.25, 2)
asin_base = ~1.0 - ~0.25 * ~0.25
asin_root = Math.sqrt(asin_base)
check("jet.asin.first",
      close?(asin_jet.derivative_value(1), ~1.0 / asin_root))
check("jet.asin.second",
      close?(asin_jet.derivative_value(2),
             ~0.25 / (asin_base * asin_root)))

asinh_jet = Calculus.taylor(-> (x) x.asinh, ~0.5, 2)
asinh_base = ~1.0 + ~0.5 * ~0.5
asinh_root = Math.sqrt(asinh_base)
check("jet.asinh.first",
      close?(asinh_jet.derivative_value(1), ~1.0 / asinh_root))
check("jet.asinh.second",
      close?(asinh_jet.derivative_value(2),
             ~-0.5 / (asinh_base * asinh_root)))

atanh_jet = Calculus.taylor(-> (x) x.atanh, ~0.25, 2)
atanh_base = ~1.0 - ~0.25 * ~0.25
check("jet.atanh.first",
      close?(atanh_jet.derivative_value(1), ~1.0 / atanh_base))
check("jet.atanh.second",
      close?(atanh_jet.derivative_value(2),
             ~0.5 / (atanh_base * atanh_base)))

log1p_jet = Calculus.taylor(-> (x) x.log1p, ~0.0, 4)
check("jet.log1p.first", close?(log1p_jet.derivative_value(1), ~1.0))
check("jet.log1p.fourth", close?(log1p_jet.derivative_value(4), ~-6.0))
expm1_jet = Calculus.taylor(-> (x) x.expm1, ~0.0, 4)
check("jet.expm1.fourth", close?(expm1_jet.derivative_value(4), ~1.0))
log2_jet = Calculus.taylor(-> (x) x.log2, ~2.0, 1)
check("jet.log2.first",
      close?(log2_jet.derivative_value(1), ~0.7213475204444817))
log10_jet = Calculus.taylor(-> (x) x.log10, ~10.0, 1)
check("jet.log10.first",
      close?(log10_jet.derivative_value(1), ~0.04342944819032518))

cbrt_jet = Calculus.taylor(-> (x) x.cbrt, ~-8.0, 2)
check("jet.cbrt.value", close?(cbrt_jet.value, ~-2.0))
check("jet.cbrt.first",
      close?(cbrt_jet.derivative_value(1), ~0.08333333333333333))
check("jet.cbrt.second",
      close?(cbrt_jet.derivative_value(2), ~0.006944444444444444))

asinh_bundle = Calculus.value_gradient_hessian(
  -> (variables) variables[0].asinh,
  [~0.5])
check("differential.asinh.value",
      close?(asinh_bundle["value"], Math.asinh(~0.5)))
check("differential.asinh.gradient",
      close?(asinh_bundle["gradient"][0], ~1.0 / asinh_root))
check("differential.asinh.hessian",
      close?(asinh_bundle["hessian"][0][0],
             ~-0.5 / (asinh_base * asinh_root)))

atanh_bundle = Calculus.value_gradient_hessian(
  -> (variables) variables[0].atanh,
  [~0.25])
check("differential.atanh.gradient",
      close?(atanh_bundle["gradient"][0], ~1.0 / atanh_base))
check("differential.atanh.hessian",
      close?(atanh_bundle["hessian"][0][0],
             ~0.5 / (atanh_base * atanh_base)))

log1p_bundle = Calculus.value_gradient_hessian(
  -> (variables) variables[0].log1p,
  [~0.25])
check("differential.log1p.gradient",
      close?(log1p_bundle["gradient"][0], ~0.8))
check("differential.log1p.hessian",
      close?(log1p_bundle["hessian"][0][0], ~-0.64))

absolute_bundle = Calculus.value_gradient_hessian(
  -> (variables) variables[0].abs,
  [~-2.0])
check("differential.abs.value", close?(absolute_bundle["value"], ~2.0))
check("differential.abs.gradient",
      close?(absolute_bundle["gradient"][0], ~-1.0))
check("differential.abs.hessian",
      close?(absolute_bundle["hessian"][0][0], ~0.0))

absolute_zero_raised = false
begin
  Calculus.gradient(-> (variables) variables[0].abs, [~0.0])
rescue error
  absolute_zero_raised = true
check("differential.abs.zero.is_loud", absolute_zero_raised)

cbrt_zero_raised = false
begin
  Calculus.derivative(-> (x) x.cbrt, ~0.0)
rescue error
  cbrt_zero_raised = true
check("jet.cbrt.zero.is_loud", cbrt_zero_raised)

cbrt_bundle = Calculus.value_gradient_hessian(
  -> (variables) variables[0].cbrt,
  [~-8.0])
check("differential.cbrt.gradient",
      close?(cbrt_bundle["gradient"][0], ~0.08333333333333333))
check("differential.cbrt.hessian",
      close?(cbrt_bundle["hessian"][0][0], ~0.006944444444444444))

# --- complex-valued quadrature --------------------------------------------

oscillatory = Calculus.integrate(
  -> (x) i.scale(x).exp,
  ~0.0,
  ~3.141592653589793)
check("quadrature.complex.converged", oscillatory.converged?)
check("quadrature.complex.value",
      complex_close?(oscillatory.value,
                     Complex<f64>.new([~0.0, ~2.0]),
                     ~2.0e-9))
check("quadrature.complex.error", oscillatory.error_estimate < ~1.0e-9)

<< "calculus_complex_spec: all checks passed"
