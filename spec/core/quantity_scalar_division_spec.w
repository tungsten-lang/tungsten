# Division precision regressions: a divisor wider than the dividend used to
# swallow every digit of the fixed 10^12 scale-up (`2 m / 1.7320508075688772`
# printed `0 m`, `2.0 / 1.7320508075688772` printed `0`, `1 J | eV` kept four
# digits), a wide dividend overflowed the int64 significand, and a product of
# two 12-digit quantities died with "quantity overflow". A ratio whose
# dimensions cancel is a plain number on every engine, so `1 + ratio` works.
#
# Run: `bin/tungsten spec/core/quantity_scalar_division_spec.w`
# Engine parity: also `bin/tungsten run` and `bin/tungsten --interpret`.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> close(name, got, want, tol)
  if (got - want).abs < tol
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

# -- Wide divisors keep at least 12 significant digits --
close("quantity.div.decimal.wide", (2 m / 1.7320508075688772).to_f(), ~1.1547005383792517, ~1.0e-9)
close("quantity.div.float", (2 m / √3).to_f(), ~1.1547005383792517, ~1.0e-9)
close("quantity.div.quantity.wide", ((2 m) / (1.7320508075688772 m)).to_f(), ~1.1547005383792517, ~1.0e-9)
close("decimal.div.wide", (2.0 / 1.7320508075688772).to_f(), ~1.1547005383792517, ~1.0e-9)
close("decimal.div.bigsig", (2.0 / 12345678901234567890.0).to_f(), ~1.6200000145800002e-19, ~1.0e-28)
close("convert.wide.factor", (1 J | eV).to_f(), ~6.241509074460763e18, ~1.0e9)

# -- Wide dividends and products degrade to fewer places, never overflow --
close("quantity.div.int.wide_dividend", (123456789012345 m / 7).to_f(), ~17636684144620.714, ~0.01)
close("quantity.mul.wide_product", (1.73205080757 Hz * 1.15470053837 m).to_f(), ~2.0, ~1.0e-9)
close("quantity.mul.scalar.wide_product", (1.73205080757 Hz * 1.15470053837).to_f(), ~2.0, ~1.0e-9)

# -- Exact quotients stay exact --
check("quantity.div.exact", (2 m / 4).to_s(), "0.5 m")
check("convert.exact", (1 in | cm).to_s(), "2.54 cm")

# -- Dimensionless ratios are plain numbers --
check("ratio.scalar.add", 1 + (1 m/s) / (2 m/s) == 1.5, true)
check("ratio.factor.folds", ((1 km) / (1 m) + 1).to_s(), "1001")
check("ratio.custom.cancels", (1 rad / 1 rad).to_s(), "1")
check("product.custom.keeps", (1 Hz * 1 s).to_s(), "1 cycle")

<< "quantity_scalar_division_spec: all green"
