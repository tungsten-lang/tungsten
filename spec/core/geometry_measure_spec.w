# Symbolic and stable numeric Euclidean measures.
# Run in both engines:
#   bin/tungsten run spec/core/geometry_measure_spec.w
#   bin/tungsten compile spec/core/geometry_measure_spec.w \
#     --out /tmp/geometry-measure-spec

use geometry

-> measure_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> measure_close?(left, right, tolerance = ~2.0e-13)
  difference = Math.abs(left - right)
  scale = Math.abs(right)
  scale = ~1.0 if scale < ~1.0
  difference <= tolerance * scale

pi = ~3.14159265358979323846
measure_check("ball.dimension_zero",
              EuclideanMeasure.unit_ball_volume(0) == Expression.constant(1))
measure_check("ball.dimension_two.symbolic",
              EuclideanMeasure.unit_ball_volume(2) == Expression.pi)
measure_check("ball.dimension_three.numeric",
              measure_close?(
                EuclideanMeasure.unit_ball_volume(3).evaluate({}),
                ~4.0 * pi / ~3.0))
measure_check("sphere.dimension_two.symbolic",
              EuclideanMeasure.unit_sphere_area(2) ==
                Expression.constant(2) * Expression.pi)
measure_check("sphere.boundary_alias",
              EuclideanMeasure.unit_ball_boundary_area(3) ==
                EuclideanMeasure.unit_sphere_area(3))

expected_volumes = [~1.0, ~2.0, pi]
dimension = 3
while dimension <= 64
  expected_volumes.push(
    expected_volumes[dimension - 2] * ~2.0 * pi / (dimension + ~0.0))
  dimension += 1

dimension = 1
while dimension <= 64
  numeric = EuclideanMeasure.unit_ball_volume_numeric(dimension)
  measure_check("ball.numeric_agrees.[dimension]",
                measure_close?(numeric, expected_volumes[dimension], ~2.0e-12))
  if dimension <= 20
    symbolic = EuclideanMeasure.unit_ball_volume(dimension).evaluate({})
    measure_check("ball.symbolic_evaluation.[dimension]",
                  measure_close?(numeric, symbolic, ~8.0e-13))
  dimension += 1

measure_check("ball.log_high_dimension",
              EuclideanMeasure.log_unit_ball_volume_numeric(512) < ~-800.0)
measure_check("ball.root_high_dimension",
              EuclideanMeasure.unit_ball_root_volume_numeric(512) > ~0.0)

invalid_raised = false
begin
  EuclideanMeasure.unit_sphere_area(0)
rescue error
  invalid_raised = error.to_s.include?("positive integer")
measure_check("sphere.dimension_zero.rejected", invalid_raised)

<< "geometry_measure_spec: all checks passed"
