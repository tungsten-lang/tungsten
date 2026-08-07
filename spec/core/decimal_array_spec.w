# %d[…] decimal array literals, %f32[…]/%f64[…] typed float array
# literals, elementwise `| unit` pipes over arrays, scalar unit attach,
# and Array statistics (mean/variance/stdev/median) incl. quantities.
#
# Run compiled:    bin/tungsten -o /tmp/decarr spec/core/decimal_array_spec.w && /tmp/decarr
# Run interpreted: bin/tungsten spec/core/decimal_array_spec.w

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

# -- %d[…] decimal array literals --
a = %d[1.0 2.5 3.75]
check("pd.size", a.size, 3)
check("pd.elem", a[1].to_s(), "2.5")
check("pd.neg", %d[-1.5 2.0][0].to_s(), "-1.5")
check("pd.int_spelling", %d[1 2 3].sum.to_s(), "6")
check("pd.sci", %d[1.5e3 2.5][0].to_s(), "1500")

# -- %d[…] | unit: elementwise attach, convert, digits --
v = %d[1.0 2.5] | m/s
check("pd.pipe.size", v.size, 2)
check("pd.pipe.elem", v[1].to_s(), "2.5 m/s")
w = v | km/h
check("pd.pipe.convert", w[0].to_s(), "3.6 km/h")
check("pd.pipe.digits", (%d[1.23456 2.0] | m(2))[0].to_s(), "1.23 m")

# Scalar unit attach through the same pipe
check("scalar.attach.decimal", (2.5 | km).to_s(), "2.5 km")
check("scalar.attach.int", (5 | km).to_s(), "5 km")

# -- %f64[…]/%f32[…] typed float array literals --
f = %f64[1.5 2.5 4.0]
check("pf64.size", f.size, 3)
check("pf64.elem", f[1], ~2.5)
check("pf64.sum", f.sum, ~8.0)
g = %f32[1.5 2.5]
check("pf32.size", g.size, 2)
check("pf32.elem", g[0], ~1.5)
h = %f64[1.0 2.0] .+ %f64[3.0 4.0]
check("pf64.dotplus", h[1], ~6.0)

# -- Array statistics: decimals --
check("mean.decimal", %d[1.0 2.0 3.0].mean.to_s(), "2")
check("mean.uneven", %d[1.0 2.0 4.0].mean.to_s(), "2.333333333333")
s = %d[2.0 4.0 4.0 4.0 5.0 5.0 7.0 9.0]
check("variance.sample", s.variance > 4.571 && s.variance < 4.572, true)
check("stdev.sample", s.stdev > 2.138 && s.stdev < 2.139, true)
check("median.odd", %d[3.0 1.0 2.0].median.to_s(), "2")
check("median.even", %d[4.0 1.0 3.0 2.0].median.to_s(), "2.5")

# -- Array statistics: typed floats --
check("mean.f64", %f64[1.0 2.0 3.0].mean, ~2.0)
check("stdev.f64", %f64[2.0 4.0 4.0 4.0 5.0 5.0 7.0 9.0].stdev > 2.138, true)

# -- Quantity ordering (comparison ladder; converts across units) --
check("quantity.lt", 1 km < 2 km, true)
check("quantity.gte", 2 km >= 2 km, true)
check("quantity.cross_unit", 1 km > 900 m, true)
check("quantity.spaceship", (1 km <=> 2 km), 0 - 1)

# -- Quantity accessors + statistics over quantity arrays --
check("quantity.value", (5 km).value.to_s(), "5")
check("quantity.unit_name", (5 km).unit_name, "km")
q = %d[1.0 2.0 3.0] | km
check("mean.quantity", q.mean.to_s(), "2 km")
check("median.quantity", q.median.to_s(), "2 km")
qs = %d[2.0 4.0 4.0 4.0 5.0 5.0 7.0 9.0] | m
check("stdev.quantity.unit", qs.stdev.unit_name, "m")
check("stdev.quantity.val", qs.stdev.value > 2.138 && qs.stdev.value < 2.139, true)

<< "decimal_array_spec: all green"
