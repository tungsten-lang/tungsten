# Exact affine-predicate regressions.
# Run in both engines:
#   bin/tungsten run spec/core/geometry_predicates_spec.w
#   bin/tungsten compile spec/core/geometry_predicates_spec.w \
#     --out /tmp/geometry-predicates-spec
#   /tmp/geometry-predicates-spec

use core/geometry/predicates

-> predicate_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

origin2 = [0, 0]
x2 = [1, 0]
y2 = [0, 1]
predicate_check("orient2d.counterclockwise",
                Geometry.orient2d(origin2, x2, y2) == 1)
predicate_check("orient2d.clockwise",
                Geometry.orient2d(origin2, y2, x2) == -1)
predicate_check("orient2d.collinear",
                Geometry.orient2d(origin2, [1, 1], [3, 3]) == 0)
predicate_check("orient2d.rational_determinant",
                Geometry.orient2d_determinant(
                  origin2, [Rational.new(1, 2), 0],
                  [0, Rational.new(1, 3)]) == Rational.new(1, 6))

# Products far beyond the immediate Integer range still decide the exact sign.
large = 1 ## big
40.times -> large *= 10
predicate_check("orient2d.bigint_exact",
                Geometry.orient2d_determinant(
                  [0, 0], [large, 1], [1, large]) == large*large - 1)

origin3 = [0, 0, 0]
x3 = [1, 0, 0]
y3 = [0, 1, 0]
z3 = [0, 0, 1]
predicate_check("orient3d.positive",
                Geometry.orient3d(origin3, x3, y3, z3) == 1)
predicate_check("orient3d.negative",
                Geometry.orient3d(origin3, x3, z3, y3) == -1)
predicate_check("orient3d.coplanar",
                Geometry.orient3d(
                  origin3, x3, y3, [Rational.new(1, 2),
                                    Rational.new(1, 2), 0]) == 0)

circle_a = [0, 0]
circle_b = [4, 0]
circle_c = [0, 4]
predicate_check("incircle.inside",
                Geometry.incircle2d(circle_a, circle_b, circle_c, [1, 1]) == 1)
predicate_check("incircle.outside",
                Geometry.incircle2d(circle_a, circle_b, circle_c, [5, 5]) == -1)
predicate_check("incircle.boundary",
                Geometry.incircle2d(circle_a, circle_b, circle_c, [4, 4]) == 0)
predicate_check("incircle.oriented_sign",
                Geometry.incircle2d(circle_a, circle_c, circle_b, [1, 1]) == -1)
predicate_check("incircle.location_ignores_winding",
                Geometry.incircle2d_location(
                  circle_a, circle_c, circle_b, [1, 1]) == :inside)

degenerate_circle_raised = false
begin
  Geometry.incircle2d([0, 0], [1, 1], [2, 2], [0, 1])
rescue error
  degenerate_circle_raised = error.to_s.include?("non-collinear")
predicate_check("incircle.degenerate_rejected", degenerate_circle_raised)

predicate_check("segment.crossing",
                Geometry.segment_relation2d(
                  [0, 0], [4, 4], [0, 4], [4, 0]) == :crossing)
predicate_check("segment.endpoint_touch",
                Geometry.segment_relation2d(
                  [0, 0], [2, 0], [2, 0], [2, 3]) == :touching)
predicate_check("segment.collinear_overlap",
                Geometry.segment_relation2d(
                  [0, 0], [4, 0], [1, 0], [3, 0]) == :overlapping)
predicate_check("segment.collinear_disjoint",
                Geometry.segment_relation2d(
                  [0, 0], [1, 0], [2, 0], [3, 0]) == :disjoint)
predicate_check("segment.vertical_overlap_reversed",
                Geometry.segment_relation2d(
                  [0, 5], [0, 1], [0, 2], [0, 7]) == :overlapping)
predicate_check("segment.collinear_single_point",
                Geometry.segment_relation2d(
                  [3, 0], [1, 0], [3, 0], [5, 0]) == :touching)
predicate_check("segment.point_on_segment",
                Geometry.segment_relation2d(
                  [1, 1], [1, 1], [0, 0], [2, 2]) == :touching)
predicate_check("segment.distinct_points",
                Geometry.segment_relation2d(
                  [1, 1], [1, 1], [2, 2], [2, 2]) == :disjoint)
predicate_check("segment.rational_point",
                Geometry.point_on_segment2d?(
                  [Rational.new(1, 2), Rational.new(1, 2)],
                  [0, 0], [1, 1]))
predicate_check("segment.collinear_point_outside",
                !Geometry.point_on_segment2d?([3, 3], [0, 0], [2, 2]))
predicate_check("segment.intersection_boolean",
                Geometry.segments_intersect2d?(
                  [0, 0], [4, 4], [0, 4], [4, 0]))

float_rejected = false
begin
  Geometry.orient2d([~0.0, 0], [1, 0], [0, 1])
rescue error
  float_rejected = error.to_s.include?("Float and Decimal")
predicate_check("coordinate.float_rejected", float_rejected)

shape_rejected = false
begin
  Geometry.orient3d([0, 0], x3, y3, z3)
rescue error
  shape_rejected = error.to_s.include?("3-coordinate Array")
predicate_check("coordinate.shape_rejected", shape_rejected)

scaffold_rejected = false
begin
  Geometry.orient2d([Integer.new, 0], [1, 0], [0, 1])
rescue error
  scaffold_rejected = error.to_s.include?("exact Integer or Rational")
predicate_check("coordinate.scaffold_rejected", scaffold_rejected)

# Translation, argument symmetry and endpoint reversal must preserve the
# geometric decisions even when every coordinate is in the heap tower.
shift = 281474976710657
permutations = [[0, 1, 2, 1], [1, 2, 0, 1], [2, 0, 1, 1],
                [0, 2, 1, -1], [2, 1, 0, -1], [1, 0, 2, -1]]
points = [[shift, shift], [shift + 4, shift], [shift, shift + 4]]
permutations.each -> (p)
  predicate_check("permutation.orient2d", Geometry.orient2d(points[p[0]], points[p[1]], points[p[2]]) == p[3])
  predicate_check("permutation.incircle", Geometry.incircle2d(points[p[0]], points[p[1]], points[p[2]], [shift + 1, shift + 1]) == p[3])
  predicate_check("permutation.location", Geometry.incircle2d_location(points[p[0]], points[p[1]], points[p[2]], [shift + 1, shift + 1]) == :inside)
predicate_check("orient3d.rational", Geometry.orient3d_determinant(
                  origin3, [Rational.new(1, 2), 0, 0],
                  [0, Rational.new(1, 3), 0], [0, 0, Rational.new(1, 5)]) == Rational.new(1, 30))
predicate_check("incircle.raw_degenerate", Geometry.incircle2d_determinant([0,0], [1,1], [2,2], [0,1]) == 4)
predicate_check("segment.degenerate_point", Geometry.point_on_segment2d?([1,2], [1,2], [1,2]) &&
                !Geometry.point_on_segment2d?([1,3], [1,2], [1,2]))

# Exhaustive pairs of segments on a 2x2 grid, including point segments.
grid = [[0,0], [0,1], [1,0], [1,1]]
symmetry = true
grid.each -> (a)
  grid.each -> (b)
    grid.each -> (c)
      grid.each -> (d)
        relation = Geometry.segment_relation2d(a, b, c, d)
        symmetry = false if relation != Geometry.segment_relation2d(c, d, a, b)
        symmetry = false if relation != Geometry.segment_relation2d(b, a, c, d)
        symmetry = false if relation != Geometry.segment_relation2d(a, b, d, c)
predicate_check("segment.exhaustive_symmetry", symmetry)
[Integer.new, Int.new, BigInt.new, 1.0, Float.new].each -> (coordinate)
  rejected = false
  begin
    Geometry.orient2d([coordinate, 0], [1, 0], [0, 1])
  rescue error
    rejected = error.to_s.include?("exact Integer or Rational")
  predicate_check("coordinate.operational_domain", rejected)

<< "geometry_predicates_spec: all checks passed"
