# Certified rational-point search for monotone plane quartics.
#
# Default regression (tree-walking interpreter and native compiler):
#   bin/tungsten run spec/core/algebra_point_search_spec.w
#   bin/tungsten compile spec/core/algebra_point_search_spec.w \
#     --out /tmp/tungsten-algebra-point-search-spec
#   /tmp/tungsten-algebra-point-search-spec
#
# Full shell-width height-100000 fixture (compiled):
#   TUNGSTEN_QUARTIC_POINTS_FULL=1 /tmp/tungsten-algebra-point-search-spec

use algebra
use core/algebra/point_search

-> point_search_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

-> point_strings(points)
  strings = points.map -> item.to_s
  strings.join("|")

# X^3 Z + X Y^2 Z - Y^4 = 0 is in the certified family.  Direct substitution
# gives exactly four primitive points through height 8:
# [1:0:0], [0:0:1], and [2:±2:1].
small_space = ProjectiveSpace<ℚ, 2>.new(:X, :Y, :Z)
X = small_space.coords[0]
Y = small_space.coords[1]
Z = small_space.coords[2]
small_equation = X**3 * Z + X * Y**2 * Z - Y**4
small_curve = Curve.new(small_space, small_equation)

height_one = small_curve.rational_points(height: 1)
point_search_check("height.one",
                   point_strings(height_one),
                   "\[1:0:0\]|\[0:0:1\]")

height_eight = small_curve.rational_points(height: 8)
point_search_check("small.complete.count", height_eight.size, 4)
point_search_check("small.complete.points",
                   point_strings(height_eight),
                   "\[1:0:0\]|\[0:0:1\]|\[2:2:1\]|\[2:-2:1\]")
height_eight.each -> (point)
  point_search_check("small.point.certified." + point.to_s,
                     small_curve.contains?(point), true)

# Clearing denominators and taking primitive part does not change the curve or
# the search result.
scaled_curve = Curve.new(small_space, small_equation * Rational.new(-3, 2))
point_search_check("primitive.rational.scale",
                   point_strings(scaled_curve.rational_points(height: 8)),
                   point_strings(height_eight))

# The Y=0 chart is solved as a reduced rational-cube identity rather than by
# scanning all Z.  Here -c4/a=1/8=(1/2)^3 gives [1:0:2].
cube_equation = X**3 * Z * 8 + X * Y**2 * Z * 8 - Y**4 - Z**4
cube_curve = Curve.new(small_space, cube_equation)
cube_points = cube_curve.rational_points(height: 2)
point_search_check("y.zero.rational.cube",
                   point_strings(cube_points).include?("\[1:0:2\]"), true)

# Unsupported shapes and coefficient fields fail explicitly.
shape_failed = false
begin
  Curve.new(small_space,
            small_equation + X**2 * Y * Z).rational_points(height: 8)
rescue error
  shape_failed = error.to_s.include?("supports only")
point_search_check("unsupported.shape.is.loud", shape_failed, true)

sign_failed = false
begin
  wrong_sign = X**3 * Z - X * Y**2 * Z - Y**4
  Curve.new(small_space, wrong_sign).rational_points(height: 8)
rescue error
  sign_failed = error.to_s.include?("same sign")
point_search_check("unsupported.sign.is.loud", sign_failed, true)

infinity_failed = false
begin
  no_y4 = X**3 * Z + X * Y**2 * Z + Z**4
  Curve.new(small_space, no_y4).rational_points(height: 8)
rescue error
  infinity_failed = error.to_s.include?("Y^4 coefficient")
point_search_check("unsupported.infinity.family.is.loud", infinity_failed, true)

finite_failed = false
begin
  finite_space = ProjectiveSpace<FiniteField, 2>.new(
    Algebra.field(FiniteField.new(5)), 2, [:X, :Y, :Z])
  fx = finite_space.coords[0]
  fy = finite_space.coords[1]
  fz = finite_space.coords[2]
  finite_curve = Curve.new(
    finite_space, fx**3 * fz + fx * fy**2 * fz - fy**4)
  finite_curve.rational_points(height: 8)
rescue error
  finite_failed = error.to_s.include?("over ℚ")
point_search_check("unsupported.field.is.loud", finite_failed, true)

height_failed = false
begin
  small_curve.rational_points(height: 0)
rescue error
  height_failed = error.to_s.include?("must be positive")
point_search_check("unsupported.height.is.loud", height_failed, true)

# The complete research fixture is intentionally opt-in for the interpreter.
# Native mode is the intended height-100000 execution path.
if env("TUNGSTEN_QUARTIC_POINTS_FULL") == "1"
  shell_space = ProjectiveSpace<ℚ, 2>.new(:B, :S, :Z)
  B = shell_space.coords[0]
  S = shell_space.coords[1]
  ZZ = shell_space.coords[2]
  shell_equation = B**3 * ZZ * 16 + B * S**2 * ZZ * 48 - S**4 * 3 + S**3 * ZZ * 8 + S**2 * ZZ**2 * 162 + ZZ**4 * 729
  shell_curve = Curve.new(shell_space, shell_equation)
  shell_points = shell_curve.rational_points(height: 100_000)
  point_search_check("shell.height100000.count", shell_points.size, 3)
  point_search_check("shell.height100000.points",
                     point_strings(shell_points),
                     "\[1:0:0\]|\[3:3:-1\]|\[0:9:1\]")
  shell_points.each -> (point)
    point_search_check("shell.point.certified." + point.to_s,
                       shell_curve.contains?(point), true)
