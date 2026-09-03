# Interpolate — 1-D interpolation, natural cubic splines, quadrature (core/interpolate.w).
#
# Run:
#   bin/tungsten run --interpret spec/core/interpolate_spec.w
#   bin/tungsten -o /tmp/interpolate_spec spec/core/interpolate_spec.w && /tmp/interpolate_spec

use core/interpolate

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

-> near(a, b, eps)
  d = a - b
  if d < ~0.0
    d = ~0.0 - d
  return d < eps

xs = [~0.0, ~1.0, ~2.0]
ys = [~0.0, ~1.0, ~4.0]

# ---- linear ----
check("linear midpoint", Interpolate.linear(xs, ys, ~1.5) == ~2.5)
check("linear first segment", Interpolate.linear(xs, ys, ~0.5) == ~0.5)
check("linear at node", Interpolate.linear(xs, ys, ~1.0) == ~1.0)
check("linear clamps below", Interpolate.linear(xs, ys, ~-3.0) == ~0.0)
check("linear clamps above", Interpolate.linear(xs, ys, ~9.0) == ~4.0)
check("linear at last node", Interpolate.linear(xs, ys, ~2.0) == ~4.0)
check("linear empty", Interpolate.linear([], [], ~1.0) == ~0.0)
check("linear two points", Interpolate.linear([~0.0, ~10.0], [~0.0, ~100.0], ~2.5) == ~25.0)
check("linear single point", Interpolate.linear([~5.0], [~7.0], ~1.0) == ~7.0)

# ---- lagrange (exact for polynomials of degree < n) ----
check("lagrange extrapolates x^2", near(Interpolate.lagrange(xs, ys, ~3.0), ~9.0, ~1.0e-12))
check("lagrange interior", near(Interpolate.lagrange(xs, ys, ~1.5), ~2.25, ~1.0e-12))
check("lagrange at node", near(Interpolate.lagrange(xs, ys, ~2.0), ~4.0, ~1.0e-12))
check("lagrange single point is constant", Interpolate.lagrange([~5.0], [~7.0], ~100.0) == ~7.0)
check("lagrange line", near(Interpolate.lagrange([~0.0, ~1.0], [~1.0, ~3.0], ~4.0), ~9.0, ~1.0e-12))

# ---- natural cubic spline ----
raised = false
begin
  Interpolate.spline_natural([~1.0], [~1.0])
rescue error
  raised = true
check("spline_natural rejects < 2 points", raised)

two = Interpolate.spline_natural([~0.0, ~2.0], [~1.0, ~5.0])
check("spline two-point xs", two[:xs] == [~0.0, ~2.0])
check("spline two-point a", two[:a] == [~1.0])
check("spline two-point b", two[:b] == [~2.0])
check("spline two-point c", two[:c] == [~0.0])
check("spline two-point d", two[:d] == [~0.0])
check("spline two-point eval is linear", Interpolate.spline_eval(two, ~1.0) == ~3.0)

# (0,0), (1,1), (2,0): m = [0, -3, 0] from the single interior equation 4 m1 = -12.
tri = Interpolate.spline_natural([~0.0, ~1.0, ~2.0], [~0.0, ~1.0, ~0.0])
check("spline a", tri[:a] == [~0.0, ~1.0])
check("spline b", near(tri[:b][0], ~1.5, ~1.0e-12) && near(tri[:b][1], ~0.0, ~1.0e-12))
check("spline c", near(tri[:c][0], ~0.0, ~1.0e-12) && near(tri[:c][1], ~-1.5, ~1.0e-12))
check("spline d", near(tri[:d][0], ~-0.5, ~1.0e-12) && near(tri[:d][1], ~0.5, ~1.0e-12))
check("spline eval first segment", near(Interpolate.spline_eval(tri, ~0.5), ~0.6875, ~1.0e-12))
check("spline eval second segment", near(Interpolate.spline_eval(tri, ~1.5), ~0.6875, ~1.0e-12))
check("spline eval node 0", near(Interpolate.spline_eval(tri, ~0.0), ~0.0, ~1.0e-12))
check("spline eval node 1", near(Interpolate.spline_eval(tri, ~1.0), ~1.0, ~1.0e-12))
check("spline eval node 2", near(Interpolate.spline_eval(tri, ~2.0), ~0.0, ~1.0e-12))
check("spline extrapolates left", near(Interpolate.spline_eval(tri, ~-1.0), ~-1.0, ~1.0e-12))
check("spline extrapolates right", near(Interpolate.spline_eval(tri, ~3.0), ~-1.0, ~1.0e-12))

quad_xs = [~0.0, ~1.0, ~2.0, ~3.0]
quad_ys = [~0.0, ~1.0, ~0.0, ~1.0]
four = Interpolate.spline_natural(quad_xs, quad_ys)
check("spline four-point segment count", four[:a].size == 3 && four[:d].size == 3)
ok = true
i = 0
while i < 4
  ok = ok && near(Interpolate.spline_eval(four, quad_xs[i]), quad_ys[i], ~1.0e-12)
  i += 1
check("spline four-point interpolates nodes", ok)

# ---- quadrature ----
check("trapz", Interpolate.trapz([~0.0, ~1.0, ~2.0], ~1.0) == ~2.0)
check("trapz two points", Interpolate.trapz([~1.0, ~3.0], ~0.5) == ~1.0)
check("trapz single", Interpolate.trapz([~1.0], ~1.0) == ~0.0)
check("trapz empty", Interpolate.trapz([], ~1.0) == ~0.0)
check("trapz_x", Interpolate.trapz_x([~0.0, ~1.0, ~3.0], [~0.0, ~1.0, ~3.0]) == ~4.5)
check("trapz_x single", Interpolate.trapz_x([~1.0], [~1.0]) == ~0.0)
check("trapz_x empty", Interpolate.trapz_x([], []) == ~0.0)
check("simpson x^2 on 0..2", near(Interpolate.simpson([~0.0, ~1.0, ~4.0], ~1.0), ~8.0 / ~3.0, ~1.0e-12))
check("simpson x^2 on 0..4", near(Interpolate.simpson([~0.0, ~1.0, ~4.0, ~9.0, ~16.0], ~1.0), ~64.0 / ~3.0, ~1.0e-12))
check("simpson odd intervals falls back to trapz", Interpolate.simpson([~0.0, ~1.0, ~4.0, ~9.0], ~1.0) == ~9.5)
check("simpson single", Interpolate.simpson([~1.0], ~1.0) == ~0.0)
check("simpson empty", Interpolate.simpson([], ~1.0) == ~0.0)
sq = -> (x) x * x
check("quad x^2", near(Interpolate.quad(sq, ~0.0, ~1.0, 200), ~1.0 / ~3.0, ~1.0e-5))
check("quad default panels", near(Interpolate.quad(sq, ~0.0, ~1.0), ~1.0 / ~3.0, ~1.0e-4))
check("quad constant is exact", Interpolate.quad(-> (x) ~1.0, ~0.0, ~2.0, 4) == ~2.0)
check("quad clamps n to 1", Interpolate.quad(sq, ~0.0, ~1.0, 0) == ~0.5)
check("quad reversed bounds is negative", Interpolate.quad(-> (x) ~1.0, ~2.0, ~0.0, 4) == ~-2.0)

<< "ALL PASS interpolate_spec ([passed.load()] checks)"
