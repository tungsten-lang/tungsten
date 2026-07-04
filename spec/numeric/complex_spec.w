# Dogfood + atan2 regression for the Argand viz.
#
# Exercises compiled Complex<f64> (abs / arg / real / imag / multiply) plus the
# w_math_atan2 intrinsic and the existing Math libm wrappers. Every check prints
# `PASS <name>` or `FAIL <name> got … want …`.
#
# Run: `bin/tungsten -o /tmp/cd spec/numeric/complex_spec.w && /tmp/cd`.
# (Needs generics, which the compiler supports by default.)

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()

# Modulus / argument / parts.
z = Complex<f64>.new([~3.0, ~4.0])
check("abs", z.abs.to_i, 5)
check("real", z.real.to_i, 3)
check("imag", z.imag.to_i, 4)
check("arg*1e4", (z.arg * ~10000.0).to_i, 9272)          # atan2(4,3) = 0.92729…

# Multiply = rotation: (1+i)(2+3i) = -1+5i.
p = Complex<f64>.new([~1.0, ~1.0]) * Complex<f64>.new([~2.0, ~3.0])
check("prod.real", p.real.to_i, -1)
check("prod.imag", p.imag.to_i, 5)
check("prod.abs*1e4", (p.abs * ~10000.0).to_i, 50990)    # √26 = 5.0990…

# atan2 intrinsic + the existing Math libm wrappers still resolve.
check("atan2*1e4", (Math.atan2(~4.0, ~3.0) * ~10000.0).to_i, 9272)
check("sqrt9", Math.sqrt(~9.0).to_i, 3)
check("floor2.7", Math.floor(~2.7).to_i, 2)
check("pow2,10", Math.pow(~2.0, ~10.0).to_i, 1024)

# Complex `**` (operator → Hypercomplex#** via the `@1.prev -> body` loop).
zp = Complex<f64>.new([~2.0, ~3.0])
check("z**0.real", (zp ** 0).real.to_i, 1)
check("z**1.real", (zp ** 1).real.to_i, 2)
check("z**2.real", (zp ** 2).real.to_i, -5)
check("z**3.real", (zp ** 3).real.to_i, -46)
check("z**3.imag", (zp ** 3).imag.to_i, 9)
