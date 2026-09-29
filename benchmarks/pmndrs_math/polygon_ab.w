# Polygon A/B — pmndrs/math-inspired bodies (src/shapes/polygon2.ts
# containsPoint / signedArea / isConvex, src/geometry/quickhull2.ts) against
# core/geometry/polygon.w's current ones.
#
#   bin/tungsten --release -o <scratch>/bin/polygon_ab benchmarks/pmndrs_math/polygon_ab.w
#   <scratch>/bin/polygon_ab check
#   benchmarks/pmndrs_math/ab.py <scratch>/bin/polygon_ab 20000 5 area_ctl_64 area_fast_64
#
# Polygon is a class-method module, so the control (PolyCtl) carries the
# current bodies VERBATIM — their internal Polygon.validate / Polygon.cross /
# Polygon.on_boundary? / Polygon.sort_points calls still reach core — and
# the candidates sit beside it with the same `X.name(...)` call shape.
# Candidate bodies are written as they would land in core, except that the
# receiver of self-calls is the benchmark class (PolyQh.hull_side would be
# Polygon.hull_side).
#
# Everything stays EXACT: coordinates are only added, subtracted, multiplied
# and compared, so Integer, BigInt and Rational inputs give exact answers.
# Only loop counters (vertex counts) are typed ## i64.
#
# Variants: <op>_<impl>_<data>
#   op    area (double_area), sarea (signed_area), contains, convex, hull,
#         validate (diagnostic: Polygon.validate vs an is_a? rewrite)
#   impl  ctl | fast (single-pass rewrite) | andrew (hull: tuned monotone
#         chain) | andrew2 (andrew + blockless Array#sort) | qh (hull: exact
#         quickhull) | at (hull: Akl-Toussaint octagon filter + andrew) |
#         atctl (the filter + today's chain body)
#   data  area/sarea: 64 | 1024 (sawtooth vertex count)
#         contains: 16 | 64 (sawtooth) | cvx (convex, ~40 vertices)
#         convex: cvx (convex, full pass) | saw (concave sawtooth)
#         hull: 100 | 1000 | 10000 (uniform in [0,10^6)^2) | grid (10000 in
#         [0,64)^2: duplicates + collinear runs) | parab (1000 points in
#         convex position) | expo (60 points, quickhull's O(n^2) case)

# Results 2026-09-25 (M5, --release, ab.py x5 medians; instr/op speedup):
#   double_area/signed_area fast 1.70x  contains? fast 2.76-2.87x
#   convex? fast 2.07x (convex, full pass) / 4.43x (early exit)
#   convex_hull: andrew 1.04-1.06x (the lambda sort dominates);
#     qh 2.4-4.1x on random/grid BUT 0.61x in convex position and 0.09x
#     (2.7 GB peak) on expo; at 3.07/4.42/6.09/4.20x (n=100/1000/10000/grid),
#     1.01x parab, 0.93x expo.
#   Every candidate's output equals the control on all check sets
#   (andrew2 excepted: see its comment).

+ PolyCtl
  # ---- verbatim from core/geometry/polygon.w ----
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

+ PolyFast
  # Shoelace in one pass: each vertex is read once and carried to the next
  # iteration, no `% n`. The terms are summed in the same order as before
  # (edge 0-1 first, closing edge n-1 - 0 last).
  -> .double_area(vertices)
    n = Polygon.validate(vertices) ## i64
    first = vertices[0]
    xi = first[0]
    yi = first[1]
    total = 0
    i = 1 ## i64
    while i < n
      v = vertices[i]
      xj = v[0]
      yj = v[1]
      total += xi * yj - xj * yi
      xi = xj
      yi = yj
      i += 1
    total + (xi * first[1] - first[0] * yi)

  -> .signed_area(vertices)
    PolyFast.double_area(vertices) * 0.5

  # One pass over the turns at every vertex, stopping at the first turn
  # whose sign disagrees with an earlier one (pmndrs isConvex).
  -> .convex?(vertices)
    n = Polygon.validate(vertices) ## i64
    a = vertices[n - 2]
    b = vertices[n - 1]
    ax = a[0]
    ay = a[1]
    bx = b[0]
    by = b[1]
    sign = 0 ## i64
    i = 0 ## i64
    while i < n
      c = vertices[i]
      cx = c[0]
      cy = c[1]
      turn = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
      if turn > 0
        return false if sign < 0
        sign = 1
      elsif turn < 0
        return false if sign > 0
        sign = -1
      ax = bx
      ay = by
      bx = cx
      by = cy
      i += 1
    true

  # Boundary test and crossing number fused into one pass: a single cross
  # product per edge decides both (pmndrs containsPoint). Zero means the
  # point is on the edge's line, and then on the edge iff inside its box; a
  # straddling edge with a zero cross product always has the point on it, so
  # the crossing branch only ever sees a nonzero sign. Boundary points count
  # as contained.
  -> .contains?(vertices, point)
    n = Polygon.validate(vertices) ## i64
    px = point[0]
    py = point[1]
    last = vertices[n - 1]
    xj = last[0]
    yj = last[1]
    inside = false
    i = 0 ## i64
    while i < n
      v = vertices[i]
      xi = v[0]
      yi = v[1]
      cross = (xj - xi) * (py - yi) - (yj - yi) * (px - xi)
      if cross == 0
        if (xi <= px || xj <= px) && (px <= xi || px <= xj) && (yi <= py || yj <= py) && (py <= yi || py <= yj)
          return true
      elsif (yi > py) != (yj > py)
        inside = !inside if (cross > 0) == (yj > yi)
      xj = xi
      yj = yi
      i += 1
    inside

  # Andrew's monotone chain, tuned: one output array (upper chain appended
  # after the lower one), the cross product inlined on the chain's last two
  # points, and deduplication against carried coordinates.
  -> .convex_hull(points)
    if points.class_name != "Array" || points.size == 0
      raise "convex hull needs at least one point"
    sorted = Polygon.sort_points(points)
    n = sorted.size ## i64
    first = sorted[0]
    unique = [first]
    ux = first[0]
    uy = first[1]
    i = 1 ## i64
    while i < n
      p = sorted[i]
      if p[0] != ux || p[1] != uy
        unique.push(p)
        ux = p[0]
        uy = p[1]
      i += 1
    m = unique.size ## i64
    return unique if m < 3
    hull = []
    k = 0 ## i64
    i = 0
    while i < m
      p = unique[i]
      while k >= 2 && PolyFast.cross_le0?(hull[k - 2], hull[k - 1], p)
        hull.pop
        k -= 1
      hull.push(p)
      k += 1
      i += 1
    floor = k + 1 ## i64
    i = m - 2
    while i >= 0
      p = unique[i]
      while k >= floor && PolyFast.cross_le0?(hull[k - 2], hull[k - 1], p)
        hull.pop
        k -= 1
      hull.push(p)
      k += 1
      i -= 1
    hull.pop
    hull

  # As convex_hull, but sorting with the blockless Array#sort. NOT LANDABLE:
  # blockless sort and Array#<=> order Rationals like their strings
  # ([3/7, 1/7, 2/1, 1/2].sort -> [1/2, 1/7, 2/1, 3/7], and
  # [3/7, 0] <=> [1/2, 0] is 1 while 3/7 <=> 1/2 is -1), so the "rational"
  # hull check FAILs for this variant only. Timed to price that bug.
  -> .convex_hull_sorted(points)
    if points.class_name != "Array" || points.size == 0
      raise "convex hull needs at least one point"
    sorted = points.sort
    n = sorted.size ## i64
    first = sorted[0]
    unique = [first]
    ux = first[0]
    uy = first[1]
    i = 1 ## i64
    while i < n
      p = sorted[i]
      if p[0] != ux || p[1] != uy
        unique.push(p)
        ux = p[0]
        uy = p[1]
      i += 1
    m = unique.size ## i64
    return unique if m < 3
    hull = []
    k = 0 ## i64
    i = 0
    while i < m
      p = unique[i]
      while k >= 2 && PolyFast.cross_le0?(hull[k - 2], hull[k - 1], p)
        hull.pop
        k -= 1
      hull.push(p)
      k += 1
      i += 1
    floor = k + 1 ## i64
    i = m - 2
    while i >= 0
      p = unique[i]
      while k >= floor && PolyFast.cross_le0?(hull[k - 2], hull[k - 1], p)
        hull.pop
        k -= 1
      hull.push(p)
      k += 1
      i -= 1
    hull.pop
    hull

  -> .cross_le0?(a, b, c)
    (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]) <= 0

  # Diagnostic candidate: validate with is_a?(Array) instead of a
  # class_name string (not wired into the bodies above). Measured ~90x
  # SLOWER: compiled is_a?(Array) costs ~1.4 us per call.
  -> .validate(vertices)
    if !vertices.is_a?(Array) || vertices.size < 3
      raise "a polygon needs at least three vertices"
    n = vertices.size ## i64
    i = 0 ## i64
    while i < n
      v = vertices[i]
      if !v.is_a?(Array) || v.size != 2
        raise "polygon vertex [i] must be a two-element \[x, y] array"
      i += 1
    vertices.size

+ PolyQh
  # Exact quickhull (pmndrs quickhull2 with the epsilon removed). The two
  # seeds are the lexicographic min and max, which are always hull vertices;
  # a tie for "farthest from the chord" goes to the point first along the
  # chord, which is a vertex (a middle one would be collinear). Output: CCW,
  # no collinear points, starting at the lexicographically smallest point —
  # the same list the monotone chain returns, without sorting.
  -> .convex_hull(points)
    if points.class_name != "Array" || points.size == 0
      raise "convex hull needs at least one point"
    n = points.size ## i64
    lo = points[0]
    hi = points[0]
    i = 1 ## i64
    while i < n
      p = points[i]
      if p[0] < lo[0] || (p[0] == lo[0] && p[1] < lo[1])
        lo = p
      if p[0] > hi[0] || (p[0] == hi[0] && p[1] > hi[1])
        hi = p
      i += 1
    if lo[0] == hi[0] && lo[1] == hi[1]
      return [lo]
    ax = lo[0]
    ay = lo[1]
    dx = hi[0] - ax
    dy = hi[1] - ay
    below = []
    above = []
    i = 0
    while i < n
      p = points[i]
      c = dx * (p[1] - ay) - dy * (p[0] - ax)
      if c < 0
        below.push(p)
      elsif c > 0
        above.push(p)
      i += 1
    hull = [lo]
    PolyQh.hull_side(below, lo, hi, hull)
    hull.push(hi)
    PolyQh.hull_side(above, hi, lo, hull)
    hull

  # Appends to `hull`, in order from p to q, the hull vertices among `side`
  # (every point of which is strictly right of p -> q).
  -> .hull_side(side, p, q, hull)
    m = side.size ## i64
    return hull if m == 0
    px = p[0]
    py = p[1]
    dx = q[0] - px
    dy = q[1] - py
    far = side[0]
    best = dx * (far[1] - py) - dy * (far[0] - px)
    i = 1 ## i64
    while i < m
      s = side[i]
      c = dx * (s[1] - py) - dy * (s[0] - px)
      if c < best || (c == best && (s[0] - far[0]) * dx + (s[1] - far[1]) * dy < 0)
        best = c
        far = s
      i += 1
    cx = far[0]
    cy = far[1]
    ex = cx - px
    ey = cy - py
    fx = q[0] - cx
    fy = q[1] - cy
    near_p = []
    near_q = []
    i = 0
    while i < m
      s = side[i]
      if ex * (s[1] - py) - ey * (s[0] - px) < 0
        near_p.push(s)
      elsif fx * (s[1] - cy) - fy * (s[0] - cx) < 0
        near_q.push(s)
      i += 1
    PolyQh.hull_side(near_p, p, far, hull)
    hull.push(far)
    PolyQh.hull_side(near_q, far, q, hull)

# Akl-Toussaint prefilter + the tuned monotone chain (PolyFast): the eight
# extreme points in the directions x, x+y, y, x-y (and their negatives) lie
# on the hull boundary in counter-clockwise order, so any point strictly
# inside their octagon is not a hull vertex and is dropped before the sort.
# The chain then sees a subset with the same hull, so the output is the
# same list; the worst case stays O(n log n) (quickhull's is O(n^2)).
+ PolyAt
  -> .convex_hull(points)
    PolyFast.convex_hull(PolyAt.octagon_filter(points))

  # The same filter in front of today's chain body, unchanged (PolyCtl is a
  # verbatim copy of core's convex_hull).
  -> .convex_hull_ctl(points)
    PolyCtl.convex_hull(PolyAt.octagon_filter(points))

  # Returns the points that can still be hull vertices (all of them when
  # the octagon is degenerate).
  -> .octagon_filter(points)
    if points.class_name != "Array" || points.size == 0
      raise "convex hull needs at least one point"
    n = points.size ## i64
    first = points[0]
    l = first
    r = first
    b = first
    t = first
    bl = first
    tr = first
    br = first
    tl = first
    minx = first[0]
    maxx = minx
    miny = first[1]
    maxy = miny
    mins = minx + miny
    maxs = mins
    mind = minx - miny
    maxd = mind
    i = 1 ## i64
    while i < n
      p = points[i]
      x = p[0]
      y = p[1]
      if x < minx
        minx = x
        l = p
      elsif x > maxx
        maxx = x
        r = p
      if y < miny
        miny = y
        b = p
      elsif y > maxy
        maxy = y
        t = p
      sum = x + y
      if sum < mins
        mins = sum
        bl = p
      elsif sum > maxs
        maxs = sum
        tr = p
      diff = x - y
      if diff < mind
        mind = diff
        tl = p
      elsif diff > maxd
        maxd = diff
        br = p
      i += 1
    ring = []
    [l, bl, b, br, r, tr, t, tl].each -> (q)
      if ring.size == 0 || q[0] != ring[ring.size - 1][0] || q[1] != ring[ring.size - 1][1]
        ring.push(q)
    while ring.size > 1 && ring[0][0] == ring[ring.size - 1][0] && ring[0][1] == ring[ring.size - 1][1]
      ring.pop
    m = ring.size ## i64
    return points if m < 3
    ax = []
    ay = []
    ex = []
    ey = []
    j = 0 ## i64
    while j < m
      a = ring[j]
      c = ring[(j + 1) % m]
      ax.push(a[0])
      ay.push(a[1])
      ex.push(c[0] - a[0])
      ey.push(c[1] - a[1])
      j += 1
    keep = []
    i = 0
    while i < n
      p = points[i]
      x = p[0]
      y = p[1]
      j = 0
      while j < m && ex[j] * (y - ay[j]) - ey[j] * (x - ax[j]) > 0
        j += 1
      keep.push(p) if j < m
      i += 1
    keep

# ---- data -----------------------------------------------------------------

# mulberry32 on an i64 cell (setup only; never timed).
-> rand_u32(cell)
  s = ((cell[0] ## i64) + 0x6D2B79F5) & 0xFFFFFFFF ## i64
  cell[0] = s
  t = ((s ^ (s >> 15)) * (s | 1)) & 0xFFFFFFFF ## i64
  t = (t ^ (t + (((t ^ (t >> 7)) * (t | 61)) & 0xFFFFFFFF))) & 0xFFFFFFFF ## i64
  (t ^ (t >> 14)) ## i64

-> rand_points(seed, n, range)
  cell = i64[1]
  cell[0] = seed
  out = []
  i = 0
  while i < n
    x = rand_u32(cell) % range
    y = rand_u32(cell) % range
    out.push([x, y])
    i += 1
  out

# Concave, simple: bottom edge (0,0)-(2t,0), then a zigzag top from right to
# left alternating heights 10 and 3; 2t + 3 vertices. Horizontal rays at
# y = 3 and y = 10 pass through vertices, y = 0 runs along an edge.
-> sawtooth(teeth)
  out = [[0, 0], [2 * teeth, 0]]
  x = 2 * teeth
  while x >= 0
    out.push([x, x % 2 == 0 ? 10 : 3])
    x -= 1
  out

# Query points: lattice points of the polygon's box grown by 2, on a stride
# that keeps big boxes to ~100 x 100 points.
-> queries(poly)
  minx = poly[0][0]
  maxx = poly[0][0]
  miny = poly[0][1]
  maxy = poly[0][1]
  poly.each -> (v)
    minx = v[0] if v[0] < minx
    maxx = v[0] if v[0] > maxx
    miny = v[1] if v[1] < miny
    maxy = v[1] if v[1] > maxy
  sx = (maxx - minx) / 100 + 1
  sy = (maxy - miny) / 100 + 1
  out = []
  y = miny - 2
  while y <= maxy + 2
    x = minx - 2
    while x <= maxx + 2
      out.push([x, y])
      x += sx
    y += sy
  out

# n points in convex position (all on the hull): y = x^2, x a permutation
# of 0..n-1. Quickhull's splits stay balanced here.
-> parabola(n)
  out = []
  i = 0
  while i < n
    x = (i * 7919) % n
    out.push([x, x * x])
    i += 1
  out

# Quickhull's bad case: (2^i, 4^i) — every point is a hull vertex and the
# farthest point from each chord is the one next to its right end, so each
# split peels off one point (O(n^2)). Coordinates reach BigInt.
-> expo(n)
  out = []
  x = 1
  j = 0
  while j < n
    out.push([x, x * x])
    x = x * 2
    j += 1
  reverse(out)

-> scale(points, factor)
  points.map -> (p)
    [p[0] * factor, p[1] * factor]

-> rscale(points, den)
  points.map -> (p)
    [Rational.new(p[0], den), Rational.new(p[1], den)]

-> reverse(points)
  out = []
  i = points.size - 1
  while i >= 0
    out.push(points[i])
    i -= 1
  out

-> same_points?(a, b)
  return false if a.size != b.size
  i = 0
  while i < a.size
    return false if a[i][0] != b[i][0] || a[i][1] != b[i][1]
    i += 1
  true

-> hull_sum(h)
  s = h.size * 1000003
  h.each -> (p)
    s = s + p[0] + p[1]
  s

# ---- correctness ----------------------------------------------------------

-> check_contains(name, poly, qs)
  bad = 0
  inside = 0
  qs.each -> (q)
    a = PolyCtl.contains?(poly, q)
    b = PolyFast.contains?(poly, q)
    bad += 1 if a != b
    inside += 1 if a
  tag = bad == 0 ? "PASS" : "FAIL"
  << tag + " contains " + name + " queries=" + qs.size.to_s + " inside=" + inside.to_s + " mismatches=" + bad.to_s

# signed_area is skipped for BigInt polygons: `BigInt * 0.5` raises
# "expected int, got bigint" (runtime), so core's signed_area/area fail for
# any |double_area| >= 2^47 — control and candidate alike.
-> check_poly(name, poly, with_signed = true)
  a1 = PolyCtl.double_area(poly)
  a2 = PolyFast.double_area(poly)
  s1 = 0
  s2 = 0
  if with_signed
    s1 = PolyCtl.signed_area(poly)
    s2 = PolyFast.signed_area(poly)
  c1 = PolyCtl.convex?(poly)
  c2 = PolyFast.convex?(poly)
  ok = a1 == a2 && s1 == s2 && c1 == c2
  tag = ok ? "PASS" : "FAIL"
  << tag + " poly " + name + " double_area=" + a1.to_s + "/" + a2.to_s + " signed=" + s1.to_s + "/" + s2.to_s + " convex=" + c1.to_s + "/" + c2.to_s

-> check_hull(name, pts)
  h1 = PolyCtl.convex_hull(pts)
  h2 = PolyFast.convex_hull(pts)
  h3 = PolyQh.convex_hull(pts)
  h4 = PolyFast.convex_hull_sorted(pts)
  h5 = PolyAt.convex_hull(pts)
  h6 = PolyAt.convex_hull_ctl(pts)
  ok = same_points?(h1, h2) && same_points?(h1, h3) && same_points?(h1, h4) && same_points?(h1, h5) && same_points?(h1, h6)
  tag = ok ? "PASS" : "FAIL"
  << tag + " hull " + name + " n=" + pts.size.to_s + " h=" + h1.size.to_s + "/" + h2.size.to_s + "/" + h3.size.to_s + "/" + h4.size.to_s + "/" + h5.size.to_s
  if !ok && h1.size < 40
    << "  ctl    " + h1.to_s
    << "  andrew " + h2.to_s
    << "  qh     " + h3.to_s

-> run_rational_check
  third = rscale(sawtooth(7), 3)
  check_contains("saw16_rational", third, rscale(queries(sawtooth(7)), 3))
  check_poly("saw16_rational", third, false)
  check_hull("rational", rscale(rand_points(19, 200, 50), 7))

-> run_check
  saw16 = sawtooth(7)
  saw64 = sawtooth(31)
  cvx = PolyCtl.convex_hull(rand_points(7, 400, 1000))
  # horizontal edges, collinear vertices, a spike and a notch whose vertices
  # sit on the query rows
  tricky = [[0, 0], [4, 0], [8, 0], [8, 4], [6, 4], [6, 2], [4, 6], [2, 2], [2, 4], [0, 4], [0, 2]]
  cw = reverse(saw16)
  big = scale(saw16, 100000000000000000000)
  bigq = scale(queries(saw16), 100000000000000000000)
  check_contains("saw16", saw16, queries(saw16))
  check_contains("saw64", saw64, queries(saw64))
  check_contains("saw16_cw", cw, queries(cw))
  check_contains("tricky", tricky, queries(tricky))
  check_contains("tricky_cw", reverse(tricky), queries(tricky))
  check_contains("cvx", cvx, queries(cvx))
  check_contains("saw16_bigint", big, bigq)
  check_poly("saw16", saw16)
  check_poly("saw64", saw64)
  check_poly("saw1024", sawtooth(511))
  check_poly("saw16_cw", cw)
  check_poly("tricky", tricky)
  check_poly("cvx", cvx)
  check_poly("cvx_cw", reverse(cvx))
  check_poly("collinear_run", [[0, 0], [1, 0], [2, 0], [2, 2], [0, 2]])
  check_poly("degenerate_line", [[0, 0], [1, 1], [2, 2]])
  check_poly("bowtie", [[0, 0], [2, 2], [2, 0], [0, 2]])
  check_poly("saw16_bigint", big, false)
  check_hull("uniform100", rand_points(11, 100, 1000000))
  check_hull("uniform1000", rand_points(12, 1000, 1000000))
  check_hull("uniform10000", rand_points(13, 10000, 1000000))
  check_hull("grid64", rand_points(14, 10000, 64))
  check_hull("grid8", rand_points(15, 500, 8))
  check_hull("grid3", rand_points(16, 200, 3))
  check_hull("square_edges", [[0, 0], [1, 0], [2, 0], [3, 0], [3, 1], [3, 2], [3, 3], [2, 3], [1, 3], [0, 3], [0, 2], [0, 1], [1, 1], [2, 2]])
  check_hull("collinear", [[3, 3], [0, 0], [1, 1], [2, 2]])
  check_hull("vertical", [[5, 3], [5, 0], [5, 9], [5, 1]])
  check_hull("single", [[4, 2]])
  check_hull("dupes", [[4, 2], [4, 2], [4, 2]])
  check_hull("two", [[4, 2], [1, 7], [4, 2]])
  check_hull("triangle_dupes", [[0, 0], [5, 0], [0, 5], [5, 0], [0, 0], [1, 1]])
  check_hull("bigint", scale(rand_points(17, 300, 1000), 100000000000000000000))
  check_hull("negative", scale(rand_points(18, 300, 1000), -1))
  # four points tie for farthest below the chord (0,0)-(10,0); the middle
  # ones come first, so an untie-broken quickhull would emit a collinear
  # vertex
  check_hull("far_tie", [[5, -5], [2, -5], [0, 0], [10, 0], [8, -5], [1, -5], [5, 7], [3, 7], [9, 7]])
  check_hull("parabola1000", parabola(1000))
  check_hull("diamond", [[0, 5], [5, 0], [10, 5], [5, 10], [5, 5], [4, 5], [5, 6]])
  check_hull("axis_square", [[0, 0], [10, 0], [10, 10], [0, 10], [5, 5], [0, 5], [5, 0]])
  check_hull("rect_ties", [[0, 0], [0, 3], [0, 7], [9, 0], [9, 7], [4, 7], [4, 0], [3, 3]])
  check_hull("triangle_int", [[0, 0], [9, 0], [0, 9], [1, 1], [2, 3], [3, 3]])
  check_hull("expo60", expo(60))
  check_hull("minkowski", [[0, 0], [1, 0], [1, 1], [0, 1], [1, 0], [2, 0], [2, 1], [1, 1], [1, 1], [2, 1], [2, 2], [1, 2], [0, 1], [1, 1], [1, 2], [0, 2]])

# ---- timing -------------------------------------------------------------

-> time_area(impl, poly, iters)
  s = 0
  i = 0 ## i64
  lim = iters ## i64
  t0 = clock()
  if impl == "ctl"
    while i < lim
      s = s + PolyCtl.double_area(poly)
      i += 1
  else
    while i < lim
      s = s + PolyFast.double_area(poly)
      i += 1
  t1 = clock()
  [t1 - t0, s]

# Diagnostic: the Polygon.validate pass every candidate still pays.
-> time_validate(impl, poly, iters)
  s = 0
  i = 0 ## i64
  lim = iters ## i64
  t0 = clock()
  if impl == "ctl"
    while i < lim
      s = s + Polygon.validate(poly)
      i += 1
  else
    while i < lim
      s = s + PolyFast.validate(poly)
      i += 1
  t1 = clock()
  [t1 - t0, s]

-> time_sarea(impl, poly, iters)
  s = 0
  i = 0 ## i64
  lim = iters ## i64
  t0 = clock()
  if impl == "ctl"
    while i < lim
      s = s + PolyCtl.signed_area(poly)
      i += 1
  else
    while i < lim
      s = s + PolyFast.signed_area(poly)
      i += 1
  t1 = clock()
  [t1 - t0, s]

-> time_contains(impl, poly, qs, iters)
  s = 0 ## i64
  i = 0 ## i64
  lim = iters ## i64
  nq = qs.size ## i64
  t0 = clock()
  if impl == "ctl"
    while i < lim
      s += 1 if PolyCtl.contains?(poly, qs[i % nq])
      i += 1
  else
    while i < lim
      s += 1 if PolyFast.contains?(poly, qs[i % nq])
      i += 1
  t1 = clock()
  [t1 - t0, s]

-> time_convex(impl, poly, iters)
  s = 0 ## i64
  i = 0 ## i64
  lim = iters ## i64
  t0 = clock()
  if impl == "ctl"
    while i < lim
      s += 1 if PolyCtl.convex?(poly)
      i += 1
  else
    while i < lim
      s += 1 if PolyFast.convex?(poly)
      i += 1
  t1 = clock()
  [t1 - t0, s]

-> time_hull(impl, pts, iters)
  s = 0
  i = 0 ## i64
  lim = iters ## i64
  t0 = clock()
  if impl == "ctl"
    while i < lim
      s = s + hull_sum(PolyCtl.convex_hull(pts))
      i += 1
  if impl == "andrew"
    while i < lim
      s = s + hull_sum(PolyFast.convex_hull(pts))
      i += 1
  if impl == "qh"
    while i < lim
      s = s + hull_sum(PolyQh.convex_hull(pts))
      i += 1
  if impl == "at"
    while i < lim
      s = s + hull_sum(PolyAt.convex_hull(pts))
      i += 1
  if impl == "atctl"
    while i < lim
      s = s + hull_sum(PolyAt.convex_hull_ctl(pts))
      i += 1
  if impl == "andrew2"
    while i < lim
      s = s + hull_sum(PolyFast.convex_hull_sorted(pts))
      i += 1
  t1 = clock()
  [t1 - t0, s]

variant = ARGV[0] == nil ? "check" : ARGV[0]
iters = ARGV[1] == nil ? 100 : ARGV[1].to_i

if variant == "check"
  run_check
elsif variant == "rcheck"
  run_rational_check
else
  parts = variant.split("_")
  op = parts[0]
  impl = parts[1]
  data = parts[2]
  result = [~0.0, 0]
  if op == "area" || op == "sarea"
    poly = data == "1024" ? sawtooth(510) : sawtooth(30)
    if op == "area"
      result = time_area(impl, poly, iters)
    else
      result = time_sarea(impl, poly, iters)
  if op == "validate"
    poly = data == "1024" ? sawtooth(510) : sawtooth(30)
    result = time_validate(impl, poly, iters)
  if op == "contains"
    poly = sawtooth(6)
    poly = sawtooth(30) if data == "64"
    poly = PolyCtl.convex_hull(rand_points(7, 400, 1000)) if data == "cvx"
    result = time_contains(impl, poly, queries(poly), iters)
  if op == "convex"
    poly = data == "saw" ? sawtooth(30) : PolyCtl.convex_hull(rand_points(7, 400, 1000))
    result = time_convex(impl, poly, iters)
  if op == "hull"
    pts = []
    pts = rand_points(21, 100, 1000000) if data == "100"
    pts = rand_points(22, 1000, 1000000) if data == "1000"
    pts = rand_points(23, 10000, 1000000) if data == "10000"
    pts = rand_points(24, 10000, 64) if data == "grid"
    pts = parabola(1000) if data == "parab"
    pts = expo(60) if data == "expo"
    result = time_hull(impl, pts, iters)
  ns = ~0.0
  ns = result[0] * ~1000000000.0 / iters if iters > 0
  << "ns/op: " + ns.to_s + " checksum: " + result[1].to_s
