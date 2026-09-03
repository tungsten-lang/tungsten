# Complete fans in the plane and the smooth toric surfaces they define, plus
# the lattice-periodic triangulations whose cones over the faces form a
# toric degeneration (Mumford's construction).
#
# A complete fan in Z^2 is a cyclic list of primitive rays v_0, ..., v_(n-1)
# in counterclockwise order; the cones are the sectors between consecutive
# rays. The fan is smooth when every consecutive pair is a lattice basis,
# det(v_i, v_(i+1)) = 1, and then the toric surface X is smooth and complete
# with Euler number n (one torus-fixed point per cone) and Picard rank n - 2.
# The invariant curve D_i of the ray v_i has self-intersection read off from
# the relation v_(i-1) + v_(i+1) = -(D_i . D_i) v_i, the canonical class is
# K = -sum D_i, and Noether's formula K^2 + e = 12 is a check on all of it.
# The toric Kleiman criterion makes -K ample exactly when every D_i^2 >= -1,
# i.e. when X is a del Pezzo surface, of degree K^2.

+ ToricFan2D
  -> new(rays)
    @rays = []
    rays.each ->(v)
      if v.class_name != "Array" || v.size != 2
        raise "a fan ray is an \[x, y] integer vector"
      @rays.push([v[0], v[1]])
    validate!

  # --- standard fans ---

  -> .projective_plane
    ToricFan2D.new([[1, 0], [0, 1], [-1, -1]])

  # P^1 x P^1 is Hirzebruch(0).
  -> .hirzebruch(n)
    ToricFan2D.new([[1, 0], [0, 1], [-1, n], [0, -1]])

  # The hexagonal fan: P^2 blown up in its three fixed points, the degree-six
  # del Pezzo surface, whose moment polygon is a hexagon. Rays as in the star
  # of a vertex of the A2 triangulation: e1, e2, e2-e1, -e1, -e2, e1-e2.
  -> .del_pezzo_six
    ToricFan2D.new([[1, 0], [0, 1], [-1, 1], [-1, 0], [0, -1], [1, -1]])

  -> .hexagon
    ToricFan2D.del_pezzo_six

  # --- helpers ---

  -> .det(a, b)
    a[0] * b[1] - a[1] * b[0]

  -> .primitive?(v)
    return false if v[0] == 0 && v[1] == 0
    x = v[0] < 0 ? 0 - v[0] : v[0]
    y = v[1] < 0 ? 0 - v[1] : v[1]
    x.gcd(y) == 1

  -> validate!
    n = @rays.size
    raise "a complete fan has at least three rays" if n < 3
    i = 0
    while i < n
      raise "fan rays must be primitive" if !ToricFan2D.primitive?(@rays[i])
      j = i + 1
      while j < n
        if @rays[i][0] == @rays[j][0] && @rays[i][1] == @rays[j][1]
          raise "fan rays must be distinct"
        j += 1
      i += 1
    i = 0
    while i < n
      a = @rays[i]
      b = @rays[(i + 1) % n]
      raise "fan rays must be in counterclockwise order with convex cones" if ToricFan2D.det(a, b) <= 0
      # No other ray may fall strictly inside the cone (a, b): with distinct
      # rays this rules out wrapping around more than once.
      j = 0
      while j < n
        w = @rays[j]
        if ToricFan2D.det(a, w) > 0 && ToricFan2D.det(w, b) > 0
          raise "fan rays are not in cyclic order"
        j += 1
      i += 1
    true

  -> rays
    @rays

  -> ray_count
    @rays.size

  -> ray(i)
    @rays[((i % @rays.size) + @rays.size) % @rays.size]

  -> cone_count
    @rays.size

  # Determinant of the i-th cone (v_i, v_(i+1)): its index in Z^2; 1 when
  # the cone is unimodular, i.e. the affine chart is smooth.
  -> cone_determinant(i)
    ToricFan2D.det(ray(i), ray(i + 1))

  -> smooth?
    i = 0
    while i < @rays.size
      return false if cone_determinant(i) != 1
      i += 1
    true

  -> unimodular?
    smooth?

  -> euler_number
    @rays.size

  -> picard_rank
    @rays.size - 2

  # D_i . D_i from v_(i-1) + v_(i+1) = -(D_i^2) v_i; equals
  # -det(v_(i-1), v_(i+1)) on a smooth fan.
  -> self_intersection(i)
    raise "self-intersection numbers are integers only on a smooth fan" if !smooth?
    0 - ToricFan2D.det(ray(i - 1), ray(i + 1))

  -> self_intersections
    out = []
    i = 0
    while i < @rays.size
      out.push(self_intersection(i))
      i += 1
    out

  -> intersection_matrix
    n = @rays.size
    out = []
    i = 0
    while i < n
      row = []
      j = 0
      while j < n
        if i == j
          row.push(self_intersection(i))
        elsif (i + 1) % n == j || (j + 1) % n == i
          row.push(1)
        else
          row.push(0)
        j += 1
      out.push(row)
      i += 1
    out

  # K^2 for K = -sum D_i: the self-intersections plus twice the n adjacent
  # pairs. Noether: K^2 + e = 12 on any smooth complete toric surface.
  -> canonical_self_intersection
    total = 2 * @rays.size
    self_intersections.each ->(d)
      total += d
    total

  -> noether?
    canonical_self_intersection + euler_number == 12

  -> fano?
    return false if !smooth?
    self_intersections.each ->(d)
      return false if d < 0 - 1
    true

  -> del_pezzo?
    fano?

  # Degree of the del Pezzo surface, K^2 = 12 - n.
  -> degree
    raise "degree is defined for del Pezzo (Fano) surfaces" if !fano?
    canonical_self_intersection

  -> to_s
    "ToricFan2D(" + @rays.to_s + ")"

  -> inspect
    to_s

# A Z^2-periodic triangulation of the plane with vertex set Z^2 — the input
# to Mumford's toric degeneration of a 2-torus. Such a triangulation is
# described by the star of the origin: the cyclic list of edge directions,
# which must be closed under negation and, for a smooth total space, must
# have consecutive pairs forming lattice bases. Euler characteristic forces
# six edges at every vertex, so modulo the lattice the triangulation has one
# vertex, three edges and two triangles.
#
# The central fibre W of the degeneration has one irreducible component per
# vertex class (the toric surface of the star fan), one double curve per
# edge class, and one triple point per triangle class; its Euler number is
# the number of triple points, all other orbits being tori of Euler number
# zero.

+ LatticeTriangulation
  -> new(star)
    @star = []
    star.each ->(v)
      if v.class_name != "Array" || v.size != 2
        raise "a star direction is an \[x, y] integer vector"
      @star.push([v[0], v[1]])
    validate!
    @fan = ToricFan2D.new(@star)

  # The standard A2 triangulation: triangles {v, v+e1, v+e2} and
  # {v+e1, v+e2, v+e1+e2}, star e1, e2, e2-e1, -e1, -e2, e1-e2.
  -> .a2
    LatticeTriangulation.new([[1, 0], [0, 1], [-1, 1], [-1, 0], [0, -1], [1, -1]])

  -> validate!
    n = @star.size
    if n != 6
      raise "a Z^2-periodic triangulation with vertex set Z^2 has six edges at each vertex"
    i = 0
    while i < n
      a = @star[i]
      b = @star[(i + n / 2) % n]
      if a[0] + b[0] != 0 || a[1] + b[1] != 0
        raise "the star of a periodic triangulation is closed under negation"
      i += 1
    i = 0
    while i < n
      d = ToricFan2D.det(@star[i], @star[(i + 1) % n])
      raise "star directions must be in counterclockwise order" if d <= 0
      raise "triangles must be unimodular for a smooth total space" if d != 1
      i += 1
    true

  -> star
    @star

  -> star_fan
    @fan

  -> vertex_count
    1

  -> edge_count
    @star.size / 2

  -> triangle_count
    @star.size / 3

  -> euler_characteristic
    vertex_count - edge_count + triangle_count

  -> unimodular?
    @fan.smooth?

  # Central fibre bookkeeping.

  -> component_count
    vertex_count

  -> double_curve_count
    edge_count

  -> triple_point_count
    triangle_count

  -> central_fibre_euler_number
    triangle_count

  -> component_fan
    @fan

  -> to_s
    "LatticeTriangulation(" + @star.to_s + ")"

  -> inspect
    to_s
