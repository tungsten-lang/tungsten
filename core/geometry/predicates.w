# Exact geometric predicates for two- and three-dimensional geometry.
#
# Coordinates must be Integer (including BigInt) or Rational values.  Integer
# products promote through the arbitrary-precision tower and Rational
# arithmetic remains exact, so the returned signs do not need an epsilon.
# Float and Decimal coordinates are deliberately rejected: ordinary arithmetic
# on them cannot provide a robust predicate near a degeneracy.
#
# `orient2d(a, b, c)` is positive when a,b,c are counterclockwise.
# `orient3d(a, b, c, d)` is positive when the ordered edge vectors
# b-a,c-a,d-a have positive determinant.  `incircle2d(a, b, c, d)` follows
# the conventional oriented sign: for counterclockwise a,b,c it is positive
# inside, zero on, and negative outside the circle.  Reversing a,b,c reverses
# that sign.  `incircle2d_location` is independent of that winding.

use core/numeric/rational

+ GeometryPredicates
  # Tungsten does not yet enforce private declarations.  Double-underscore
  # methods are implementation details; only the predicate methods without
  # that prefix form this namespace's supported API.
  -> .__exact_integer_value?(value)
    Integer.value?(value)

  -> .__exact_coordinate?(value)
    name = value.class_name
    return true if GeometryPredicates.__exact_integer_value?(value)
    if name == "Rational"
      begin
        return GeometryPredicates.__exact_integer_value?(value.numerator) && (
          GeometryPredicates.__exact_integer_value?(value.denominator))
      rescue error
        return false
    false

  -> .__validate_point(point, dimension, label)
    if point.class_name != "Array" || point.size != dimension
      raise label + " must be a " + dimension.to_s + "-coordinate Array"
    point.each -> (coordinate)
      if !GeometryPredicates.__exact_coordinate?(coordinate)
        raise (label + " coordinates must be exact Integer or Rational " +
               "values; Float and Decimal coordinates are unsupported")
    point

  -> .__sign(value)
    return -1 if value < 0
    return 1 if value > 0
    0

  -> .orient2d_determinant(a, b, c)
    GeometryPredicates.__validate_point(a, 2, "orient2d point a")
    GeometryPredicates.__validate_point(b, 2, "orient2d point b")
    GeometryPredicates.__validate_point(c, 2, "orient2d point c")
    GeometryPredicates.__orient2d_determinant(a, b, c)

  -> .__orient2d_determinant(a, b, c)
    (b[0] - a[0])*(c[1] - a[1]) - (
      b[1] - a[1])*(c[0] - a[0])

  -> .orient2d(a, b, c)
    GeometryPredicates.__sign(
      GeometryPredicates.orient2d_determinant(a, b, c))

  -> .orient3d_determinant(a, b, c, d)
    GeometryPredicates.__validate_point(a, 3, "orient3d point a")
    GeometryPredicates.__validate_point(b, 3, "orient3d point b")
    GeometryPredicates.__validate_point(c, 3, "orient3d point c")
    GeometryPredicates.__validate_point(d, 3, "orient3d point d")
    bax = b[0] - a[0]
    bay = b[1] - a[1]
    baz = b[2] - a[2]
    cax = c[0] - a[0]
    cay = c[1] - a[1]
    caz = c[2] - a[2]
    dax = d[0] - a[0]
    day = d[1] - a[1]
    daz = d[2] - a[2]
    bax*(cay*daz - caz*day) - bay*(cax*daz - caz*dax) + (
      baz*(cax*day - cay*dax))

  -> .orient3d(a, b, c, d)
    GeometryPredicates.__sign(
      GeometryPredicates.orient3d_determinant(a, b, c, d))

  # The raw polynomial is defined even for collinear a,b,c. Circle sign and
  # location queries below require a non-collinear defining triangle.
  -> .incircle2d_determinant(a, b, c, d)
    GeometryPredicates.__validate_point(a, 2, "incircle2d point a")
    GeometryPredicates.__validate_point(b, 2, "incircle2d point b")
    GeometryPredicates.__validate_point(c, 2, "incircle2d point c")
    GeometryPredicates.__validate_point(d, 2, "incircle2d point d")
    GeometryPredicates.__incircle2d_determinant(a, b, c, d)

  -> .__incircle2d_determinant(a, b, c, d)
    adx = a[0] - d[0]
    ady = a[1] - d[1]
    bdx = b[0] - d[0]
    bdy = b[1] - d[1]
    cdx = c[0] - d[0]
    cdy = c[1] - d[1]
    abdet = adx*bdy - bdx*ady
    bcdet = bdx*cdy - cdx*bdy
    cadet = cdx*ady - adx*cdy
    alift = adx*adx + ady*ady
    blift = bdx*bdx + bdy*bdy
    clift = cdx*cdx + cdy*cdy
    alift*bcdet + blift*cadet + clift*abdet

  -> .incircle2d(a, b, c, d)
    orientation = GeometryPredicates.orient2d(a, b, c)
    if orientation == 0
      raise "incircle2d needs three non-collinear circle points"
    GeometryPredicates.__validate_point(d, 2, "incircle2d point d")
    GeometryPredicates.__sign(
      GeometryPredicates.__incircle2d_determinant(a, b, c, d))

  -> .incircle2d_location(a, b, c, d)
    orientation = GeometryPredicates.orient2d(a, b, c)
    if orientation == 0
      raise "incircle2d needs three non-collinear circle points"
    GeometryPredicates.__validate_point(d, 2, "incircle2d point d")
    value = GeometryPredicates.__sign(
      GeometryPredicates.__incircle2d_determinant(a, b, c, d))
    value *= orientation
    return :inside if value > 0
    return :outside if value < 0
    :boundary

  -> .__same_point2d?(a, b)
    a[0] == b[0] && a[1] == b[1]

  -> .__between?(value, endpoint_a, endpoint_b)
    if endpoint_a <= endpoint_b
      endpoint_a <= value && value <= endpoint_b
    else
      endpoint_b <= value && value <= endpoint_a

  -> .__point_on_segment2d_validated?(point, a, b)
    return false if GeometryPredicates.__orient2d_determinant(a, b, point) != 0
    GeometryPredicates.__between?(point[0], a[0], b[0]) && (
      GeometryPredicates.__between?(point[1], a[1], b[1]))

  -> .point_on_segment2d?(point, a, b)
    GeometryPredicates.__validate_point(point, 2, "segment point")
    GeometryPredicates.__validate_point(a, 2, "segment endpoint a")
    GeometryPredicates.__validate_point(b, 2, "segment endpoint b")
    GeometryPredicates.__point_on_segment2d_validated?(point, a, b)

  # Classify two closed segments.  The exhaustive results are:
  #
  #   :crossing    one interior point of each segment is shared
  #   :touching    exactly one shared point, including degenerate segments
  #   :overlapping a positive-length collinear interval is shared
  #   :disjoint    no point is shared
  -> .segment_relation2d(a, b, c, d)
    GeometryPredicates.__validate_point(a, 2, "first segment endpoint a")
    GeometryPredicates.__validate_point(b, 2, "first segment endpoint b")
    GeometryPredicates.__validate_point(c, 2, "second segment endpoint a")
    GeometryPredicates.__validate_point(d, 2, "second segment endpoint b")

    first_point = GeometryPredicates.__same_point2d?(a, b)
    second_point = GeometryPredicates.__same_point2d?(c, d)
    if first_point
      if second_point
        return GeometryPredicates.__same_point2d?(a, c) ? (
          :touching) : :disjoint
      return GeometryPredicates.__point_on_segment2d_validated?(a, c, d) ? (
        :touching) : :disjoint
    if second_point
      return GeometryPredicates.__point_on_segment2d_validated?(c, a, b) ? (
        :touching) : :disjoint

    o1 = GeometryPredicates.__sign(GeometryPredicates.__orient2d_determinant(a, b, c))
    o2 = GeometryPredicates.__sign(GeometryPredicates.__orient2d_determinant(a, b, d))
    o3 = GeometryPredicates.__sign(GeometryPredicates.__orient2d_determinant(c, d, a))
    o4 = GeometryPredicates.__sign(GeometryPredicates.__orient2d_determinant(c, d, b))

    if o1 == 0 && o2 == 0 && o3 == 0 && o4 == 0
      axis = a[0] != b[0] || c[0] != d[0] ? 0 : 1
      first_low = a[axis] <= b[axis] ? a[axis] : b[axis]
      first_high = a[axis] <= b[axis] ? b[axis] : a[axis]
      second_low = c[axis] <= d[axis] ? c[axis] : d[axis]
      second_high = c[axis] <= d[axis] ? d[axis] : c[axis]
      overlap_low = first_low >= second_low ? first_low : second_low
      overlap_high = first_high <= second_high ? first_high : second_high
      return :disjoint if overlap_low > overlap_high
      return :touching if overlap_low == overlap_high
      return :overlapping

    if o1 != 0 && o2 != 0 && o1 != o2 && (
      o3 != 0 && o4 != 0 && o3 != o4)
      return :crossing

    return :touching if o1 == 0 && (
      GeometryPredicates.__point_on_segment2d_validated?(c, a, b))
    return :touching if o2 == 0 && (
      GeometryPredicates.__point_on_segment2d_validated?(d, a, b))
    return :touching if o3 == 0 && (
      GeometryPredicates.__point_on_segment2d_validated?(a, c, d))
    return :touching if o4 == 0 && (
      GeometryPredicates.__point_on_segment2d_validated?(b, c, d))
    :disjoint

  -> .segments_intersect2d?(a, b, c, d)
    GeometryPredicates.segment_relation2d(a, b, c, d) != :disjoint


# The public geometry facade keeps predicate discovery alongside Chart,
# Metric, and TensorField while the implementation remains separately usable.
+ Geometry
  -> .orient2d_determinant(a, b, c)
    GeometryPredicates.orient2d_determinant(a, b, c)

  -> .orient2d(a, b, c)
    GeometryPredicates.orient2d(a, b, c)

  -> .orient3d_determinant(a, b, c, d)
    GeometryPredicates.orient3d_determinant(a, b, c, d)

  -> .orient3d(a, b, c, d)
    GeometryPredicates.orient3d(a, b, c, d)

  -> .incircle2d_determinant(a, b, c, d)
    GeometryPredicates.incircle2d_determinant(a, b, c, d)

  -> .incircle2d(a, b, c, d)
    GeometryPredicates.incircle2d(a, b, c, d)

  -> .incircle2d_location(a, b, c, d)
    GeometryPredicates.incircle2d_location(a, b, c, d)

  -> .point_on_segment2d?(point, a, b)
    GeometryPredicates.point_on_segment2d?(point, a, b)

  -> .segment_relation2d(a, b, c, d)
    GeometryPredicates.segment_relation2d(a, b, c, d)

  -> .segments_intersect2d?(a, b, c, d)
    GeometryPredicates.segments_intersect2d?(a, b, c, d)
