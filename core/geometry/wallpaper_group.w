# The wallpaper groups as actual groups, not just names.
#
# A symmetry of a periodic plane pattern is an affine isometry
#
#     x -> M x + t
#
# with M in the lattice's point group and t a translation. The group itself is
# infinite, since it contains every lattice translation, so the finite object
# to compute with is the quotient by that translation lattice: one coset per
# point-group element, each carrying the translation part that goes with it.
# That quotient is finite — order 1 to 12 — and it determines the group.
#
# The translation parts are what separate groups sharing a point group. A
# mirror with zero translation is a reflection; the same mirror carrying half
# a lattice vector is a *glide*, which has no fixed line. That is the whole
# difference between pm and pg, and between pmm and pgg. Translations are
# therefore stored scaled by a denominator (2 suffices: every glide in the
# seventeen groups carries half a lattice vector), which keeps the arithmetic
# exact.
#
# Composition is (M1, t1) . (M2, t2) = (M1 M2, M1 t2 + t1), and since M1 is an
# integer matrix it maps the scaled translation lattice to itself, so the
# denominator never grows. Each group is built by closing its generators under
# that law, modulo translations — the same closure idea as LatticeSymmetry,
# now in the affine setting. Building them this way means the construction
# *verifies* itself: if the generators are right the closure terminates at the
# known point-group order, and if they are wrong it does not.
#
# Centred lattices (cm, cmm) carry the extra translation (1/2, 1/2), which is
# handled by identifying translations that differ by it.

+ WallpaperGroup
  -> new(@name, @cosets, @denominator, @centred, @lattice) ro

  # ---- affine arithmetic ----------------------------------------------

  -> .multiply(a, b)
    [[a[0][0] * b[0][0] + a[0][1] * b[1][0], a[0][0] * b[0][1] + a[0][1] * b[1][1]],
     [a[1][0] * b[0][0] + a[1][1] * b[1][0], a[1][0] * b[0][1] + a[1][1] * b[1][1]]]

  -> .transform(m, v)
    [m[0][0] * v[0] + m[0][1] * v[1], m[1][0] * v[0] + m[1][1] * v[1]]

  -> .determinant(m)
    m[0][0] * m[1][1] - m[0][1] * m[1][0]

  -> .modulo(value, base)
    r = value % base
    r += base if r < 0
    r

  # Canonical representative of a translation modulo the lattice. On a centred
  # lattice the vector (1/2, 1/2) is itself a translation, so the two
  # candidates are identified and the smaller is chosen.
  -> .reduce(translation, denominator, centred)
    a = WallpaperGroup.modulo(translation[0], denominator)
    b = WallpaperGroup.modulo(translation[1], denominator)
    return [a, b] if !centred
    half = denominator / 2
    c = WallpaperGroup.modulo(a + half, denominator)
    d = WallpaperGroup.modulo(b + half, denominator)
    return [a, b] if a < c || (a == c && b <= d)
    [c, d]

  -> .compose(x, y, denominator, centred)
    matrix = WallpaperGroup.multiply(x[0], y[0])
    shifted = WallpaperGroup.transform(x[0], y[1])
    translation = [shifted[0] + x[1][0], shifted[1] + x[1][1]]
    [matrix, WallpaperGroup.reduce(translation, denominator, centred)]

  -> .key_of(element)
    m = element[0]
    "[m[0][0]],[m[0][1]],[m[1][0]],[m[1][1]]|[element[1][0]],[element[1][1]]"

  # Close generators under composition, modulo translations.
  -> .from_generators(name, generators, denominator, centred, lattice)
    identity = [[[1, 0], [0, 1]], [0, 0]]
    seen = {}
    cosets = []
    seen[WallpaperGroup.key_of(identity)] = true
    cosets.push(identity)
    head = 0
    while head < cosets.size
      current = cosets[head]
      head += 1
      g = 0
      while g < generators.size
        product = WallpaperGroup.compose(current, generators[g], denominator, centred)
        key = WallpaperGroup.key_of(product)
        if !seen.key?(key)
          seen[key] = true
          cosets.push(product)
        g += 1
        raise "wallpaper generators did not close" if cosets.size > 64
    WallpaperGroup.new(name, cosets, denominator, centred, lattice)

  # ---- structure ------------------------------------------------------

  # Order of the quotient by translations, i.e. of the point group.
  -> point_group_order
    @cosets.size

  -> highest_rotation_order
    best = 1
    @cosets.each ->(element)
      m = element[0]
      next if WallpaperGroup.determinant(m) != 1
      trace = m[0][0] + m[1][1]
      order = 1
      order = 2 if trace == 0 - 2
      order = 3 if trace == 0 - 1
      order = 4 if trace == 0 && (m[0][1] != 0 || m[1][0] != 0)
      order = 6 if trace == 1
      best = order if order > best
    best

  # A reflection whose translation part vanishes: a genuine mirror line.
  -> has_reflection?
    found = false
    @cosets.each ->(element)
      if WallpaperGroup.determinant(element[0]) == 0 - 1
        found = true if element[1][0] == 0 && element[1][1] == 0
    found

  # A reflection carrying a nonzero translation: a glide, with no fixed line.
  -> has_glide?
    found = false
    @cosets.each ->(element)
      if WallpaperGroup.determinant(element[0]) == 0 - 1
        found = true if element[1][0] != 0 || element[1][1] != 0
    found

  # Closure check: every product of two cosets is again a coset. True by
  # construction, so this is an audit of the construction.
  -> closed?
    keys = {}
    @cosets.each ->(element)
      keys[WallpaperGroup.key_of(element)] = true
    ok = true
    i = 0
    while i < @cosets.size
      j = 0
      while j < @cosets.size
        product = WallpaperGroup.compose(@cosets[i], @cosets[j], @denominator, @centred)
        ok = false if !keys.key?(WallpaperGroup.key_of(product))
        j += 1
      i += 1
    ok

  # Image of an integer lattice point under a coset, in units of 1/denominator.
  -> apply_scaled(element, point)
    mapped = WallpaperGroup.transform(element[0], point)
    [mapped[0] * @denominator + element[1][0], mapped[1] * @denominator + element[1][1]]

  # The images of one point under every coset, as scaled coordinates.
  -> orbit(point)
    out = []
    @cosets.each ->(element)
      out.push(apply_scaled(element, point))
    out

  # ---- the seventeen groups -------------------------------------------
  # Matrices are written in the basis of the group's own lattice, so the
  # square and hexagonal families use different integer representatives of
  # the same geometric rotations.

  -> .rotation_180
    [[0 - 1, 0], [0, 0 - 1]]

  -> .rotation_90
    [[0, 0 - 1], [1, 0]]

  -> .mirror_x
    [[0 - 1, 0], [0, 1]]

  -> .mirror_y
    [[1, 0], [0, 0 - 1]]

  # Hexagonal basis: a sixty degree turn is (q, r) -> (-r, q + r).
  -> .rotation_60
    [[0, 0 - 1], [1, 1]]

  -> .rotation_120
    [[0 - 1, 0 - 1], [1, 0]]

  -> .mirror_hex
    [[0, 1], [1, 0]]

  -> .mirror_hex_alternate
    [[0, 0 - 1], [0 - 1, 0]]

  -> .p1
    WallpaperGroup.from_generators("p1", [], 2, false, "oblique")

  -> .p2
    WallpaperGroup.from_generators("p2", [[WallpaperGroup.rotation_180, [0, 0]]], 2, false, "oblique")

  -> .pm
    WallpaperGroup.from_generators("pm", [[WallpaperGroup.mirror_x, [0, 0]]], 2, false, "rectangular")

  # The mirror carries half a lattice vector, so it is a glide.
  -> .pg
    WallpaperGroup.from_generators("pg", [[WallpaperGroup.mirror_x, [0, 1]]], 2, false, "rectangular")

  -> .cm
    WallpaperGroup.from_generators("cm", [[WallpaperGroup.mirror_x, [0, 0]]], 2, true, "rhombic")

  -> .pmm
    WallpaperGroup.from_generators("pmm",
      [[WallpaperGroup.mirror_x, [0, 0]], [WallpaperGroup.mirror_y, [0, 0]]], 2, false, "rectangular")

  -> .pmg
    WallpaperGroup.from_generators("pmg",
      [[WallpaperGroup.rotation_180, [0, 0]], [WallpaperGroup.mirror_x, [0, 1]]], 2, false, "rectangular")

  -> .pgg
    WallpaperGroup.from_generators("pgg",
      [[WallpaperGroup.rotation_180, [0, 0]], [WallpaperGroup.mirror_x, [1, 1]]], 2, false, "rectangular")

  -> .cmm
    WallpaperGroup.from_generators("cmm",
      [[WallpaperGroup.mirror_x, [0, 0]], [WallpaperGroup.mirror_y, [0, 0]]], 2, true, "rhombic")

  -> .p4
    WallpaperGroup.from_generators("p4", [[WallpaperGroup.rotation_90, [0, 0]]], 2, false, "square")

  -> .p4m
    WallpaperGroup.from_generators("p4m",
      [[WallpaperGroup.rotation_90, [0, 0]], [WallpaperGroup.mirror_x, [0, 0]]], 2, false, "square")

  -> .p4g
    WallpaperGroup.from_generators("p4g",
      [[WallpaperGroup.rotation_90, [0, 0]], [WallpaperGroup.mirror_x, [1, 1]]], 2, false, "square")

  -> .p3
    WallpaperGroup.from_generators("p3", [[WallpaperGroup.rotation_120, [0, 0]]], 2, false, "hexagonal")

  # p3m1 and p31m share a point group and differ in how its mirrors sit
  # against the lattice: one set runs through lattice vectors, the other
  # between them.
  -> .p3m1
    WallpaperGroup.from_generators("p3m1",
      [[WallpaperGroup.rotation_120, [0, 0]], [WallpaperGroup.mirror_hex, [0, 0]]], 2, false, "hexagonal")

  -> .p31m
    WallpaperGroup.from_generators("p31m",
      [[WallpaperGroup.rotation_120, [0, 0]], [WallpaperGroup.mirror_hex_alternate, [0, 0]]], 2, false, "hexagonal")

  -> .p6
    WallpaperGroup.from_generators("p6", [[WallpaperGroup.rotation_60, [0, 0]]], 2, false, "hexagonal")

  -> .p6m
    WallpaperGroup.from_generators("p6m",
      [[WallpaperGroup.rotation_60, [0, 0]], [WallpaperGroup.mirror_hex, [0, 0]]], 2, false, "hexagonal")

  -> .all
    [WallpaperGroup.p1, WallpaperGroup.p2, WallpaperGroup.pm, WallpaperGroup.pg,
     WallpaperGroup.cm, WallpaperGroup.pmm, WallpaperGroup.pmg, WallpaperGroup.pgg,
     WallpaperGroup.cmm, WallpaperGroup.p4, WallpaperGroup.p4m, WallpaperGroup.p4g,
     WallpaperGroup.p3, WallpaperGroup.p3m1, WallpaperGroup.p31m, WallpaperGroup.p6,
     WallpaperGroup.p6m]

  -> .named(name)
    found = nil
    WallpaperGroup.all.each ->(group)
      found = group if group.name == name
    raise "unknown wallpaper group [name]" if found == nil
    found
