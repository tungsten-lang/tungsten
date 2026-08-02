# Euclidean ball and sphere measures in arbitrary integer dimension.  The
# symbolic surface preserves pi and Gamma; the numeric surface uses log-Gamma
# to avoid avoidable overflow in intermediate values.

use core/expression
use core/special

+ EuclideanMeasure
  -> .validate_dimension(dimension, positive = false)
    name = dimension.class_name
    integer = name == "Integer" || name == "Int" || name == "BigInt"
    minimum = positive ? 1 : 0
    if !integer || dimension < minimum
      label = positive ? "positive" : "nonnegative"
      raise "Euclidean dimension must be a " + label + " integer"
    dimension

  -> .unit_ball_volume(dimension)
    d = EuclideanMeasure.validate_dimension(dimension)
    half = Expression.constant(Rational.new(d, 2))
    ((Expression.pi ** half) /
      (half + Expression.constant(1)).gamma)

  -> .unit_ball_volume_numeric(dimension)
    Math.exp(EuclideanMeasure.log_unit_ball_volume_numeric(dimension))

  # Natural logarithm of V_d. Unlike V_d itself this remains representable
  # after high-dimensional f64 volumes have underflowed to zero.
  -> .log_unit_ball_volume_numeric(dimension)
    d = EuclideanMeasure.validate_dimension(dimension)
    half = (d + ~0.0) / ~2.0
    (half * Math.log(~3.14159265358979323846) -
      Special.log_gamma(half + ~1.0))

  -> .unit_ball_root_volume_numeric(dimension)
    d = EuclideanMeasure.validate_dimension(dimension, true)
    Math.exp(EuclideanMeasure.log_unit_ball_volume_numeric(d) /
             (d + ~0.0))

  -> .unit_sphere_area(dimension)
    d = EuclideanMeasure.validate_dimension(dimension, true)
    Expression.constant(d) * EuclideanMeasure.unit_ball_volume(d)

  -> .unit_sphere_area_numeric(dimension)
    d = EuclideanMeasure.validate_dimension(dimension, true)
    (d + ~0.0) * EuclideanMeasure.unit_ball_volume_numeric(d)

  # Explicit alias: the argument is the ambient dimension d, so this is the
  # (d-1)-dimensional boundary area of the unit ball in R^d.
  -> .unit_ball_boundary_area(dimension)
    EuclideanMeasure.unit_sphere_area(dimension)

  -> .unit_ball_boundary_area_numeric(dimension)
    EuclideanMeasure.unit_sphere_area_numeric(dimension)
