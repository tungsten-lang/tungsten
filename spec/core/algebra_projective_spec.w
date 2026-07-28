# Field and arbitrary-dimensional projective-space regressions.
# The algebra orchestrator loads core/algebra/field and
# core/algebra/projective before this file executes.

use algebra

-> projective_check(name, got, want)
  if got != want
    raise "FAIL " + name + " got " + got.to_s + " want " + want.to_s
  << "PASS " + name

field = RationalField.new
projective_check("field.supported", Field.supported?(field), true)
projective_check("field.abstract_not_supported", Field.supported?(Field.new), false)
projective_check("field.characteristic", field.characteristic, 0)
projective_check("field.exact", field.exact?, true)
projective_check("field.zero", field.zero, Rational.new(0))
projective_check("field.one", field.one, Rational.new(1))
projective_check("field.coerce", field.coerce(Rational.new(3, 5)), Rational.new(3, 5))
projective_check("field.equality", field.equal?(1, Rational.new(2, 2)), true)

unsupported_raised = false
begin
  Field.for(:not_implemented)
rescue error
  unsupported_raised = true
projective_check("field.unsupported_raises", unsupported_raised, true)

p0 = ProjectiveSpace<ℚ, 0>.new(:O)
projective_check("p0.dimension", p0.dimension, 0)
projective_check("p0.coordinate_count", p0.coordinate_count, 1)
projective_check("p0.normalization", p0.point([7]).to_s, "\[1\]")

p1 = ProjectiveSpace<ℚ, 1>.new()
projective_check("p1.dimension", p1.dimension, 1)
projective_check("p1.arity", p1.coordinate_count, 2)
projective_check("p1.default_names", p1.coordinate_names.join(","), "X0,X1")
projective_check("p1.field", p1.field.class_name, "RationalField")
projective_check("p1.ring_field", p1.ring.field, p1.field)
projective_check("p1.generator_count", p1.coords.size, 2)

p2 = ProjectiveSpace<ℚ, 2>.new(:X, :Y, :Z)
projective_check("p2.compat_names", p2.coordinate_names.join(","), "X,Y,Z")
projective_check("p2.compat_point", p2.point(2, 0, 0).to_s, "\[1:0:0\]")
p2_renamed = p2.with_coords(:B, :S, :T)
projective_check("p2.compat_rename", p2_renamed.coordinate_names.join(","), "B,S,T")

p3 = ProjectiveSpace<ℚ, 3>.new([:W, :X, :Y, :Z])
projective_check("p3.dimension", p3.dimension, 3)
projective_check("p3.arity", p3.coordinate_count, 4)
projective_check("p3.names", p3.coordinate_names.join(","), "W,X,Y,Z")
projective_check("p3.generator_count", p3.coords.size, 4)

p5 = ProjectiveSpace<ℚ, 5>.new([:A, :B, :C, :D, :E, :F])
projective_check("p5.dimension", p5.dimension, 5)
projective_check("p5.arity", p5.coordinate_count, 6)
projective_check("p5.point", p5.point([2, 0, 0, 0, 0, 0]).to_s, "\[1:0:0:0:0:0\]")

fractional = p2.point([
  Rational.new(1, 2),
  Rational.new(-1, 3),
  Rational.new(0)
])
projective_check("point.fraction_normalize", fractional.to_s, "\[3:-2:0\]")
projective_check("point.negative_normalize", p2.point(-2, 4, 0).to_s, "\[1:-2:0\]")
projective_check("point.index", fractional[1], -2)

all_zero_raised = false
begin
  p2.point(0, 0, 0)
rescue error
  all_zero_raised = true
projective_check("point.all_zero_raises", all_zero_raised, true)

wrong_arity_raised = false
begin
  ProjectiveSpace<ℚ, 3>.new([:X, :Y, :Z])
rescue error
  wrong_arity_raised = true
projective_check("space.wrong_arity_raises", wrong_arity_raised, true)

chart_point = p3.point([
  Rational.new(1, 2),
  Rational.new(3, 4),
  Rational.new(-5, 6),
  Rational.new(7, 3)
])
affine = chart_point.dehomogenize(3)
projective_check("chart.coordinate_count", affine.size, 3)
projective_check("chart.first", affine[0], Rational.new(3, 14))
projective_check("chart.second", affine[1], Rational.new(9, 28))
projective_check("chart.third", affine[2], Rational.new(-5, 14))
projective_check("chart.round_trip", p3.homogenize(affine, 3).coordinates.to_s, chart_point.coordinates.to_s)

missing_chart_raised = false
begin
  p2.point(1, 0, 0).dehomogenize(2)
rescue error
  missing_chart_raised = true
projective_check("chart.zero_pivot_raises", missing_chart_raised, true)
