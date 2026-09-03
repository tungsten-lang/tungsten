# Polygons on the integer plane, with exact arithmetic throughout.
#
# The predicates here all reduce to the signed area of a triangle,
#
#   cross(a, b, c) = (b.x - a.x)(c.y - a.y) - (b.y - a.y)(c.x - a.x)
#
# which is an integer when the vertices are. Orientation, convexity, point
# containment and segment crossing are then decided by *signs* of integers
# rather than by comparing floating-point numbers, so no tolerance is ever
# needed and no degenerate case is decided by rounding.
#
# Area follows the same principle. The shoelace sum gives twice the area, and
# twice the area of a lattice polygon is always an integer — so `double_area`
# is the exact primitive and `area` merely halves it.
#
# Pick's theorem lives here too, and it is the bridge between this module and
# the cell-based ones: for a simple lattice polygon
#
#   A = I + B/2 - 1
#
# with I interior and B boundary lattice points. B is computable directly —
# an edge from p to q passes through gcd(|dx|, |dy|) lattice points — so the
# theorem determines I from the area, and the identity becomes a way to count
# lattice points rather than merely a curiosity. It is the two-dimensional
# shadow of the Ehrhart theory in `core/algebra/lattice_polytope.w`.

+ Polygon
  -> .integer?(value)
    name = value.class_name
    name == "Integer" || name == "Int" || name == "BigInt"

  -> .abs(value)
    value < 0 ? 0 - value : value

  -> .gcd(a, b)
    x = Polygon.abs(a)
    y = Polygon.abs(b)
    while y != 0
      r = x % y
      x = y
      y = r
    x

  -> .validate(vertices)
    if vertices.class_name != "Array" || vertices.size < 3
      raise "a polygon needs at least three vertices"
    i = 0
    while i < vertices.size
      v = vertices[i]
      if v.class_name != "Array" || v.size != 2
        raise "polygon vertex [i] must be a two-element \[x, y] array"
      i += 1
    vertices.size

  # Twice the signed area of triangle a-b-c. Positive when the turn a -> b -> c
  # is counter-clockwise, zero when the three are collinear.
  -> .cross(a, b, c)
    (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])

  -> .orientation(a, b, c)
    value = Polygon.cross(a, b, c)
    return 0 if value == 0
    value > 0 ? 1 : 0 - 1

  # Shoelace: exactly twice the signed area, positive for counter-clockwise.
  -> .double_area(vertices)
    n = Polygon.validate(vertices)
    total = 0
    i = 0
    while i < n
      j = (i + 1) % n
      total += vertices[i][0] * vertices[j][1] - vertices[j][0] * vertices[i][1]
      i += 1
    total

  -> .signed_area(vertices)
    Polygon.double_area(vertices) * 0.5

  -> .area(vertices)
    value = Polygon.double_area(vertices)
    value = 0 - value if value < 0
    value * 0.5

  -> .counter_clockwise?(vertices)
    Polygon.double_area(vertices) > 0

  # Reverse the vertex order, flipping the orientation.
  -> .reverse(vertices)
    out = []
    i = vertices.size - 1
    while i >= 0
      out.push([vertices[i][0], vertices[i][1]])
      i -= 1
    out

  -> .convex?(vertices)
    n = Polygon.validate(vertices)
    positive = false
    negative = false
    i = 0
    while i < n
      turn = Polygon.orientation(vertices[i], vertices[(i + 1) % n], vertices[(i + 2) % n])
      positive = true if turn > 0
      negative = true if turn < 0
      i += 1
    !(positive && negative)

  # ---- containment ------------------------------------------------------

  -> .on_segment?(a, b, p)
    return false if Polygon.cross(a, b, p) != 0
    minx = a[0] < b[0] ? a[0] : b[0]
    maxx = a[0] > b[0] ? a[0] : b[0]
    miny = a[1] < b[1] ? a[1] : b[1]
    maxy = a[1] > b[1] ? a[1] : b[1]
    p[0] >= minx && p[0] <= maxx && p[1] >= miny && p[1] <= maxy

  -> .on_boundary?(vertices, point)
    n = Polygon.validate(vertices)
    i = 0
    while i < n
      return true if Polygon.on_segment?(vertices[i], vertices[(i + 1) % n], point)
      i += 1
    false

  # Crossing-number test, decided by integer comparisons only. Boundary points
  # count as contained.
  -> .contains?(vertices, point)
    return true if Polygon.on_boundary?(vertices, point)
    n = vertices.size
    px = point[0]
    py = point[1]
    inside = false
    j = n - 1
    i = 0
    while i < n
      xi = vertices[i][0]
      yi = vertices[i][1]
      xj = vertices[j][0]
      yj = vertices[j][1]
      if (yi > py) != (yj > py)
        left = (px - xi) * (yj - yi)
        right = (xj - xi) * (py - yi)
        if yj > yi
          inside = !inside if left < right
        else
          inside = !inside if left > right
      j = i
      i += 1
    inside

  # Proper or improper crossing of two closed segments.
  -> .segments_intersect?(p1, p2, p3, p4)
    d1 = Polygon.orientation(p3, p4, p1)
    d2 = Polygon.orientation(p3, p4, p2)
    d3 = Polygon.orientation(p1, p2, p3)
    d4 = Polygon.orientation(p1, p2, p4)
    return true if d1 * d2 < 0 && d3 * d4 < 0
    return true if d1 == 0 && Polygon.on_segment?(p3, p4, p1)
    return true if d2 == 0 && Polygon.on_segment?(p3, p4, p2)
    return true if d3 == 0 && Polygon.on_segment?(p1, p2, p3)
    return true if d4 == 0 && Polygon.on_segment?(p1, p2, p4)
    false

  # ---- convex hull ------------------------------------------------------

  -> .sort_points(points)
    points.sort ->(a, b)
      if a[0] != b[0]
        a[0] <=> b[0]
      else
        a[1] <=> b[1]

  # Andrew's monotone chain. Returns the hull counter-clockwise, without
  # collinear points, starting from the lexicographically smallest vertex.
  -> .convex_hull(points)
    if points.class_name != "Array" || points.size == 0
      raise "convex hull needs at least one point"
    sorted = Polygon.sort_points(points)
    unique = []
    i = 0
    while i < sorted.size
      last = unique.size - 1
      if unique.size == 0 || unique[last][0] != sorted[i][0] || unique[last][1] != sorted[i][1]
        unique.push(sorted[i])
      i += 1
    return unique if unique.size < 3
    lower = []
    i = 0
    while i < unique.size
      while lower.size >= 2 && Polygon.cross(lower[lower.size - 2], lower[lower.size - 1], unique[i]) <= 0
        lower.pop
      lower.push(unique[i])
      i += 1
    upper = []
    i = unique.size - 1
    while i >= 0
      while upper.size >= 2 && Polygon.cross(upper[upper.size - 2], upper[upper.size - 1], unique[i]) <= 0
        upper.pop
      upper.push(unique[i])
      i -= 1
    hull = []
    i = 0
    while i < lower.size - 1
      hull.push(lower[i])
      i += 1
    i = 0
    while i < upper.size - 1
      hull.push(upper[i])
      i += 1
    hull

  # Minkowski sum. Every sum of a vertex of one with a vertex of the other is
  # a candidate, and for convex operands the hull of those candidates is
  # exactly the sum. Reflecting the second argument first gives the *no-fit
  # polygon*: the set of translations at which two shapes overlap, which is
  # how packing decides placement in the continuous setting.
  -> .minkowski_sum(a, b)
    candidates = []
    i = 0
    while i < a.size
      j = 0
      while j < b.size
        candidates.push([a[i][0] + b[j][0], a[i][1] + b[j][1]])
        j += 1
      i += 1
    Polygon.convex_hull(candidates)

  -> .negate(vertices)
    out = []
    i = 0
    while i < vertices.size
      out.push([0 - vertices[i][0], 0 - vertices[i][1]])
      i += 1
    out

  -> .no_fit_polygon(fixed, moving)
    Polygon.minkowski_sum(fixed, Polygon.negate(moving))

  # ---- Pick's theorem ---------------------------------------------------

  # Lattice points on the boundary: an edge (dx, dy) carries gcd(|dx|, |dy|)
  # of them, counting one endpoint each.
  -> .boundary_points(vertices)
    n = Polygon.validate(vertices)
    total = 0
    i = 0
    while i < n
      j = (i + 1) % n
      total += Polygon.gcd(vertices[j][0] - vertices[i][0], vertices[j][1] - vertices[i][1])
      i += 1
    total

  # Pick rearranged: 2A = 2I + B - 2, so I = (2A - B + 2) / 2.
  -> .interior_points(vertices)
    doubled = Polygon.double_area(vertices)
    doubled = 0 - doubled if doubled < 0
    (doubled - Polygon.boundary_points(vertices) + 2) / 2

  # Area from the lattice-point counts — the theorem in its usual direction.
  -> .pick_area(interior, boundary)
    (2 * interior + boundary - 2) * 0.5

  # Total lattice points in the closed polygon.
  -> .lattice_points(vertices)
    Polygon.interior_points(vertices) + Polygon.boundary_points(vertices)

  # Does Pick's identity hold for these vertices? True for every simple
  # lattice polygon, so a false here means the input was not simple.
  -> .pick_consistent?(vertices)
    doubled = Polygon.double_area(vertices)
    doubled = 0 - doubled if doubled < 0
    interior = Polygon.interior_points(vertices)
    boundary = Polygon.boundary_points(vertices)
    2 * interior + boundary - 2 == doubled
