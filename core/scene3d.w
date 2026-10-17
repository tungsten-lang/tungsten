# Scene3D — vector 3D on top of Svg: a camera (orthographic or perspective)
# set by azimuth, elevation and roll; world-space polygons, cubes, segments,
# dots and labels; painter's-order depth sorting; flat Lambert shading.
#
#   v = View3D.new(~0.7853981633974483, ~0.6154797086703874, ~0.0, ~90.0, ~960.0, ~540.0)
#   sc = Scene3D.new(v)                                   # isometric, 90 px per unit
#   sc.cube([0, 0, 0], ~1.0, {fill: "#4ea1ff"})          # six faces, back faces culled
#   sc.polygon([[0, 0, 0], [2, 0, 0], [0, 2, 0]], {fill: "#ff8a5b", opacity: ~0.6})
#   sc.segment([0, 0, 0], [0, 0, 2], {stroke: "#e8e6e3", width: 2})
#   sc.dot([1, 1, 1], 6, {fill: "#f2c14e"})
#   sc.label([1, 1, 1], "corner", {size: 28, fill: "#e8e6e3"}, 12, -12)
#   s = Svg.new(1920, 1080)
#   sc.render(s)
#
# World z is up. Azimuth turns the eye about z (0 = eye on the +x side),
# elevation raises it above the xy-plane, and roll turns the finished picture
# counter-clockwise about the view axis. Screen y grows downward, as in Svg.
# A positive `distance` gives a perspective camera that many units from the
# target; nil or zero is orthographic.
#
# Every item is drawn back to front by the depth of a single key point: a
# polygon's centroid, a segment's midpoint, a cube's centre (its visible faces
# are emitted together). For disjoint equal cubes on a grid and for the faces
# of one convex solid that order is exact; for intersecting geometry it is the
# usual painter's approximation. `layer:` in the options draws an item after
# (positive) or before (negative) every item of a lower layer, regardless of
# depth.

+ View3D
  ro :azimuth, :elevation, :roll, :scale, :cx, :cy, :distance, :target
  ro :eye, :right, :up

  -> new(azimuth, elevation, roll, scale, cx, cy, distance = nil, target = nil)
    @azimuth = azimuth + ~0.0
    @elevation = elevation + ~0.0
    @roll = roll + ~0.0
    @scale = scale + ~0.0
    @cx = cx + ~0.0
    @cy = cy + ~0.0
    @distance = distance
    @target = target
    if @target == nil
      @target = [~0.0, ~0.0, ~0.0]
    ce = Math.cos(@elevation)
    # eye: unit vector from the target toward the viewer
    @eye = [ce * Math.cos(@azimuth), ce * Math.sin(@azimuth), Math.sin(@elevation)]
    # right = forward × z, up = right × forward, with forward = -eye
    rx = ~0.0 - @eye[1]
    ry = @eye[0]
    rn = Math.sqrt(rx * rx + ry * ry)
    if rn < ~0.000000001
      rx = ~0.0
      ry = ~1.0
      rn = ~1.0
    @right = [rx / rn, ry / rn, ~0.0]
    f = [~0.0 - @eye[0], ~0.0 - @eye[1], ~0.0 - @eye[2]]
    @up = View3D.cross(@right, f)
    @cr = Math.cos(@roll)
    @sr = Math.sin(@roll)

  # The view straight down the body diagonal (1, 1, 1), the isometric eye.
  -> .isometric(scale, cx, cy, roll = ~0.0)
    View3D.new(~0.7853981633974483, ~0.6154797086703874, roll, scale, cx, cy)

  -> .dot(a, b)
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]

  -> .cross(a, b)
    [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]

  -> .sub(a, b)
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]

  -> .add(a, b)
    [a[0] + b[0], a[1] + b[1], a[2] + b[2]]

  -> .scale_vec(a, s)
    [a[0] * s, a[1] * s, a[2] * s]

  -> .lerp_vec(a, b, t)
    [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]

  -> .normalize(a)
    n = Math.sqrt(View3D.dot(a, a))
    if n < ~0.000000000001
      return [~0.0, ~0.0, ~0.0]
    [a[0] / n, a[1] / n, a[2] / n]

  # A camera part of the way from `a` to `b` (angles, scale, centre and target
  # interpolate linearly; the distance switches at the end).
  -> .between(a, b, t)
    d = a.distance
    if t >= ~1.0
      d = b.distance
    View3D.new(a.azimuth + (b.azimuth - a.azimuth) * t,
               a.elevation + (b.elevation - a.elevation) * t,
               a.roll + (b.roll - a.roll) * t,
               a.scale + (b.scale - a.scale) * t,
               a.cx + (b.cx - a.cx) * t,
               a.cy + (b.cy - a.cy) * t,
               d,
               View3D.lerp_vec(a.target, b.target, t))

  # signed depth toward the viewer: larger is nearer
  -> depth(p)
    View3D.dot(View3D.sub([p[0] + ~0.0, p[1] + ~0.0, p[2] + ~0.0], @target), @eye)

  # perspective magnification at p (1 for an orthographic camera)
  -> magnification(p)
    if @distance == nil || @distance <= ~0.0
      return ~1.0
    gap = @distance - depth(p)
    if gap < ~0.05
      gap = ~0.05
    @distance / gap

  # [screen x, screen y]
  -> project(p)
    q = View3D.sub([p[0] + ~0.0, p[1] + ~0.0, p[2] + ~0.0], @target)
    x = View3D.dot(q, @right)
    y = View3D.dot(q, @up)
    m = magnification(p)
    x = x * m
    y = y * m
    [@cx + @scale * (x * @cr - y * @sr), @cy - @scale * (x * @sr + y * @cr)]

  # the screen direction (unit, Svg orientation) of the world vector v
  -> screen_direction(v)
    a = project([~0.0, ~0.0, ~0.0])
    b = project(v)
    dx = b[0] - a[0]
    dy = b[1] - a[1]
    n = Math.sqrt(dx * dx + dy * dy)
    if n < ~0.000000001
      return [~0.0, ~0.0]
    [dx / n, dy / n]

+ Scene3D
  ro :view, :light

  -> new(@view)
    @items = []
    @seq = 0
    @light = View3D.normalize([~0.35, ~0.55, ~1.0])
    @ambient = ~0.42

  # light direction in world space (toward the light) and ambient level
  -> lighting(dir, ambient = ~0.42)
    @light = View3D.normalize(dir)
    @ambient = ambient
    self

  -> count
    @items.size

  # ---- colour arithmetic on "#rrggbb" strings ----

  -> .nibble(ch)
    "0123456789abcdef".index(ch.downcase)

  -> .rgb(color)
    s = color
    if s[0] == "#"
      s = s.slice(1, s.size - 1)
    if s.size == 3
      return [Scene3D.nibble(s[0]) * 17, Scene3D.nibble(s[1]) * 17, Scene3D.nibble(s[2]) * 17]
    [Scene3D.nibble(s[0]) * 16 + Scene3D.nibble(s[1]), Scene3D.nibble(s[2]) * 16 + Scene3D.nibble(s[3]),
     Scene3D.nibble(s[4]) * 16 + Scene3D.nibble(s[5])]

  -> .hex2(v)
    digits = "0123456789abcdef"
    x = v
    if x < 0
      x = 0
    if x > 255
      x = 255
    digits[x / 16] + digits[x % 16]

  -> .hex(r, g, b)
    "#" + Scene3D.hex2((r + ~0.0).round.to_i) + Scene3D.hex2((g + ~0.0).round.to_i) + Scene3D.hex2((b + ~0.0).round.to_i)

  # the colour a fraction f of the way from c0 to c1
  -> .mix(c0, c1, f)
    a = Scene3D.rgb(c0)
    b = Scene3D.rgb(c1)
    t = f + ~0.0
    if t < ~0.0
      t = ~0.0
    if t > ~1.0
      t = ~1.0
    Scene3D.hex(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)

  # brightness factor in [ambient, 1] of a face with outward unit normal n,
  # turned toward the viewer first so that two-sided faces light the same way
  -> brightness(n)
    m = n
    if View3D.dot(m, @view.eye) < ~0.0
      m = View3D.scale_vec(n, ~-1.0)
    lam = View3D.dot(m, @light)
    if lam < ~0.0
      lam = ~0.0
    @ambient + (~1.0 - @ambient) * lam

  -> shaded(color, n, strength)
    b = brightness(n)
    Scene3D.mix(color, "#000000", (~1.0 - b) * strength)

  # Newell's normal of a planar polygon (unit; orientation follows the winding)
  -> .normal(pts)
    nx = ~0.0
    ny = ~0.0
    nz = ~0.0
    i = 0
    n = pts.size
    while i < n
      a = pts[i]
      b = pts[(i + 1) % n]
      nx = nx + (a[1] - b[1]) * (a[2] + b[2])
      ny = ny + (a[2] - b[2]) * (a[0] + b[0])
      nz = nz + (a[0] - b[0]) * (a[1] + b[1])
      i += 1
    View3D.normalize([nx, ny, nz])

  -> .centroid(pts)
    sx = ~0.0
    sy = ~0.0
    sz = ~0.0
    pts.each -> (p)
      sx = sx + p[0]
      sy = sy + p[1]
      sz = sz + p[2]
    n = pts.size + ~0.0
    [sx / n, sy / n, sz / n]

  -> push_item(depth, kind, payload, opts)
    layer = 0
    if opts != nil && opts.has_key?(:layer)
      layer = opts[:layer]
    @items.push([layer, depth, @seq, kind, payload])
    @seq += 1
    self

  -> .copy_opts(opts)
    out = {}
    if opts != nil
      opts.keys.each -> (k)
        if k != :layer && k != :shade && k != :cull && k != :edge && k != :fills
          out[k] = opts[k]
    out

  # A planar polygon. Options are Svg's, plus shade: (0..1, default 0.85 when
  # filled), cull: true (skip when the winding faces away), edge: a stroke
  # colour mixed from the shaded fill when "auto".
  -> polygon(pts, opts = {})
    n = Scene3D.normal(pts)
    if opts.has_key?(:cull) && opts[:cull] && View3D.dot(n, @view.eye) <= ~0.0
      return self
    o = Scene3D.copy_opts(opts)
    if opts.has_key?(:fill) && opts[:fill] != "none"
      strength = ~0.85
      if opts.has_key?(:shade)
        strength = opts[:shade]
      if strength > ~0.0
        o[:fill] = shaded(opts[:fill], n, strength)
      if opts.has_key?(:edge) && opts[:edge] == "auto"
        o[:stroke] = Scene3D.mix(o[:fill], "#000000", ~0.38)
    screen = []
    pts.each -> (p)
      screen.push(@view.project(p))
    push_item(@view.depth(Scene3D.centroid(pts)), :polygon, [screen, o], opts)

  # The six faces of the axis-aligned box [o, o + dims], outward wound, in the
  # order +x, -x, +y, -y, +z, -z.
  -> .box_faces(o, dims)
    x0 = o[0] + ~0.0
    y0 = o[1] + ~0.0
    z0 = o[2] + ~0.0
    x1 = x0 + dims[0]
    y1 = y0 + dims[1]
    z1 = z0 + dims[2]
    [[[x1, y0, z0], [x1, y1, z0], [x1, y1, z1], [x1, y0, z1]],
     [[x0, y0, z0], [x0, y0, z1], [x0, y1, z1], [x0, y1, z0]],
     [[x0, y1, z0], [x0, y1, z1], [x1, y1, z1], [x1, y1, z0]],
     [[x0, y0, z0], [x1, y0, z0], [x1, y0, z1], [x0, y0, z1]],
     [[x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1]],
     [[x0, y0, z0], [x0, y1, z0], [x1, y1, z0], [x1, y0, z0]]]

  -> .cube_faces(o, size)
    Scene3D.box_faces(o, [size, size, size])

  # A solid axis-aligned box drawn as one item: its front faces share one
  # depth slot (the box centre). Options as for polygon; fills: six colours
  # in box_faces order override fill. Unless a stroke is given, each face is
  # outlined in a darker shade of its own fill.
  -> box(o, dims, opts = {})
    faces = Scene3D.box_faces(o, dims)
    polys = []
    k = 0
    while k < 6
      f = faces[k]
      n = Scene3D.normal(f)
      if View3D.dot(n, @view.eye) > ~0.0
        o2 = Scene3D.copy_opts(opts)
        color = nil
        if opts.has_key?(:fills)
          color = opts[:fills][k]
        elsif opts.has_key?(:fill)
          color = opts[:fill]
        if color != nil
          strength = ~0.85
          if opts.has_key?(:shade)
            strength = opts[:shade]
          o2[:fill] = shaded(color, n, strength)
          if !opts.has_key?(:stroke)
            o2[:stroke] = Scene3D.mix(o2[:fill], "#000000", ~0.38)
            o2[:width] = ~1.2
            o2[:linejoin] = "round"
        screen = []
        f.each -> (p)
          screen.push(@view.project(p))
        polys.push([screen, o2])
      k += 1
    c = [o[0] + dims[0] / ~2.0, o[1] + dims[1] / ~2.0, o[2] + dims[2] / ~2.0]
    push_item(@view.depth(c), :group, polys, opts)

  -> cube(o, size, opts = {})
    box(o, [size, size, size], opts)

  -> segment(p, q, opts = {})
    mid = View3D.lerp_vec([p[0] + ~0.0, p[1] + ~0.0, p[2] + ~0.0], [q[0] + ~0.0, q[1] + ~0.0, q[2] + ~0.0], ~0.5)
    push_item(@view.depth(mid), :segment, [@view.project(p), @view.project(q), Scene3D.copy_opts(opts)], opts)

  # an open polyline through world points
  -> path(pts, opts = {})
    screen = []
    pts.each -> (p)
      screen.push(@view.project(p))
    push_item(@view.depth(Scene3D.centroid(pts)), :polyline, [screen, Scene3D.copy_opts(opts)], opts)

  # a disc of radius r pixels (scaled by perspective) at a world point
  -> dot(p, r, opts = {})
    s = @view.project(p)
    push_item(@view.depth(p), :dot, [s, r * @view.magnification(p), Scene3D.copy_opts(opts)], opts)

  # text anchored at the projection of p, offset by (dx, dy) pixels
  -> label(p, text, opts = {}, dx = 0, dy = 0)
    s = @view.project(p)
    push_item(@view.depth(p), :label, [[s[0] + dx, s[1] + dy], text, Scene3D.copy_opts(opts)], opts)

  # items in drawing order (layer, then depth far → near, then insertion)
  -> ordered
    @items.sort_by -> (it)
      [it[0], it[1], it[2]]

  -> render(svg)
    ordered.each -> (it)
      kind = it[3]
      pl = it[4]
      if kind == :polygon
        svg.polygon(pl[0], pl[1])
      elsif kind == :group
        pl.each -> (face)
          svg.polygon(face[0], face[1])
      elsif kind == :segment
        a = pl[0]
        b = pl[1]
        svg.line(a[0], a[1], b[0], b[1], pl[2])
      elsif kind == :polyline
        svg.polyline(pl[0], pl[1])
      elsif kind == :dot
        svg.circle(pl[0][0], pl[0][1], pl[1], pl[2])
      elsif kind == :label
        svg.text(pl[0][0], pl[0][1], pl[1], pl[2])
    svg
