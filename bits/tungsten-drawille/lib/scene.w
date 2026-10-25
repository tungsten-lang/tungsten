# Drawille scene primitives, bounded viewports, and 3-D projection.
#
# This file deliberately knows nothing about algebra classes.  It accepts
# numeric points and line strips; the type-aware adapters live in inspection.w.
# Keeping this boundary lets core/algebra remain exact and visualization-free.

use canvas

DRAWILLE_NUMERIC_NAMES = [
  "Integer", "Int", "BigInt", "Rational",
  "Float", "Float16", "Float32", "Float64", "Float80", "Float128", "Float256",
  "Decimal", "Decimal32", "Decimal64", "Decimal128",
  "AlgebraicRealRoot"
]

+ DrawilleNumbers
  -> .numeric(value)
    name = value.class_name
    return nil if name == "Nil"
    if name == "Float" || name == "Int" || name == "Float64" || name == "Integer"
      number = value.to_f()
      return nil if number.nan?() || number.infinite?()
      return number
    if DRAWILLE_NUMERIC_NAMES.include?(name)
      begin
        number = value.to_f()
        # The tree-walker exposes nan?/infinite? as primitive dispatch even
        # when respond_to? cannot enumerate those runtime-only methods.
        return nil if number.nan?() || number.infinite?()
        return number
      rescue error
        return nil
    if name == "Expression" && value.respond_to?("constant?") && value.constant?
      return numeric(value.constant_value)
    nil

  -> .round_i(value)
    v = value.to_f()
    if v < ~0.0
      return Math.ceil(v - ~0.5).to_i()
    Math.floor(v + ~0.5).to_i()

  -> .integer_power(base, exponent)
    return ~1.0 if exponent == 0
    if exponent == 1
      return base.to_f()
    if exponent == 2
      f = base.to_f()
      return f * f
    result = ~1.0
    factor = base.to_f()
    remaining = exponent
    while remaining > 0
      result *= factor if (remaining & 1) == 1
      remaining = remaining >> 1
      factor *= factor if remaining > 0
    result

  -> .bounded_cols(value)
    out = value
    out = 8 if out < 8
    out = 160 if out > 160
    out

  -> .bounded_rows(value)
    out = value
    out = 4 if out < 4
    out = 60 if out > 60
    out


+ DrawilleViewport
  ro :canvas
  ro :xmin
  ro :xmax
  ro :ymin
  ro :ymax
  ro :xscale
  ro :yscale

  -> new(@canvas, xmin, xmax, ymin, ymax)
    @xmin = xmin.to_f()
    @xmax = xmax.to_f()
    @ymin = ymin.to_f()
    @ymax = ymax.to_f()
    if @xmax <= @xmin
      @xmin -= ~0.5
      @xmax += ~0.5
    if @ymax <= @ymin
      @ymin -= ~0.5
      @ymax += ~0.5
    @xscale = (@canvas.pixel_width() - 1).to_f() / (@xmax - @xmin)
    @yscale = (@canvas.pixel_height() - 1).to_f() / (@ymax - @ymin)

  -> px(x)
    DrawilleNumbers.round_i((x.to_f() - @xmin) * @xscale)

  -> py(y)
    DrawilleNumbers.round_i((@ymax - y.to_f()) * @yscale)

  -> point(x, y)
    [px(x), py(y)]

  -> x_axis_row
    return -1 if @ymin > ~0.0 || @ymax < ~0.0
    py(~0.0) / 4

  -> y_axis_col
    return -1 if @xmin > ~0.0 || @xmax < ~0.0
    px(~0.0) / 2


+ DrawilleProjection3D
  # Rotate around the vertical axis, then tilt around the horizontal axis.
  # Perspective is bounded away from its singular plane; callers can request
  # orthographic projection by passing false.
  -> .project(x, y, z, yaw_degrees = 38, pitch_degrees = 24,
              perspective = true, distance = 6)
    radians = ~3.141592653589793 / ~180.0
    yaw = yaw_degrees.to_f() * radians
    pitch = pitch_degrees.to_f() * radians
    cy = Math.cos(yaw)
    sy = Math.sin(yaw)
    cp = Math.cos(pitch)
    sp = Math.sin(pitch)
    xf = x.to_f()
    yf = y.to_f()
    zf = z.to_f()
    xr = xf * cy - zf * sy
    zr = xf * sy + zf * cy
    yr = yf * cp - zr * sp
    depth = yf * sp + zr * cp
    scale = ~1.0
    if perspective
      df = distance.to_f()
      denominator = df + depth
      denominator = ~0.25 if denominator < ~0.25
      scale = df / denominator
      scale = ~4.0 if scale > ~4.0
    [xr * scale, yr * scale, depth]

  -> .polyline(points, yaw_degrees = 38, pitch_degrees = 24,
               perspective = true, distance = 6)
    out = []
    n = points.size()
    return out if n == 0
    radians = ~3.141592653589793 / ~180.0
    yaw = yaw_degrees.to_f() * radians
    pitch = pitch_degrees.to_f() * radians
    cy = Math.cos(yaw)
    sy = Math.sin(yaw)
    cp = Math.cos(pitch)
    sp = Math.sin(pitch)
    df = distance.to_f()
    i = 0
    while i < n
      point = points[i]
      xf = point[0].to_f()
      yf = point[1].to_f()
      zf = point[2].to_f()
      xr = xf * cy - zf * sy
      zr = xf * sy + zf * cy
      yr = yf * cp - zr * sp
      depth = yf * sp + zr * cp
      scale = ~1.0
      if perspective
        denominator = df + depth
        denominator = ~0.25 if denominator < ~0.25
        scale = df / denominator
        scale = ~4.0 if scale > ~4.0
      out.push([xr * scale, yr * scale, depth])
      i += 1
    out


+ DrawilleScene
  ro :points
  ro :segments

  -> new
    @points = []
    @segments = []

  -> point(x, y)
    @points.push([x.to_f(), y.to_f()])
    self

  -> segment(x0, y0, x1, y1)
    @segments.push([x0.to_f(), y0.to_f(), x1.to_f(), y1.to_f()])
    self

  -> polyline(points)
    n = points.size()
    return self if n == 0
    i = 0
    while i < n
      pt = points[i]
      point(pt[0], pt[1])
      i += 1
    i = 1
    while i < n
      p0 = points[i - 1]
      p1 = points[i]
      segment(p0[0], p0[1], p1[0], p1[1])
      i += 1
    self

  -> empty?
    @points.size() == 0 && @segments.size() == 0

  -> bounds(include_origin = false)
    np = @points.size()
    ns = @segments.size()
    if np == 0 && ns == 0 && !include_origin
      return [~0.0, ~1.0, ~0.0, ~1.0]
    xmin = ~0.0
    xmax = ~0.0
    ymin = ~0.0
    ymax = ~0.0
    have_init = include_origin
    i = 0
    while i < np
      pt = @points[i]
      px = pt[0]
      py = pt[1]
      if !have_init
        xmin = px
        xmax = px
        ymin = py
        ymax = py
        have_init = true
      else
        xmin = px if px < xmin
        xmax = px if px > xmax
        ymin = py if py < ymin
        ymax = py if py > ymax
      i += 1
    i = 0
    while i < ns
      seg = @segments[i]
      x0 = seg[0]
      y0 = seg[1]
      x1 = seg[2]
      y1 = seg[3]
      if !have_init
        xmin = x0
        xmax = x0
        ymin = y0
        ymax = y0
        have_init = true
      else
        xmin = x0 if x0 < xmin
        xmax = x0 if x0 > xmax
        ymin = y0 if y0 < ymin
        ymax = y0 if y0 > ymax
      xmin = x1 if x1 < xmin
      xmax = x1 if x1 > xmax
      ymin = y1 if y1 < ymin
      ymax = y1 if y1 > ymax
      i += 1
    xspan = xmax - xmin
    yspan = ymax - ymin
    xspan = ~1.0 if xspan <= ~0.0
    yspan = ~1.0 if yspan <= ~0.0
    [xmin - xspan * ~0.04, xmax + xspan * ~0.04,
     ymin - yspan * ~0.06, ymax + yspan * ~0.06]

  -> render(cols = 70, rows = 15, axes = true)
    cols = DrawilleNumbers.bounded_cols(cols)
    rows = DrawilleNumbers.bounded_rows(rows)
    canvas = Canvas.new(cols, rows)
    box = bounds(axes)
    viewport = DrawilleViewport.new(canvas, box[0], box[1], box[2], box[3])
    ns = @segments.size()
    i = 0
    while i < ns
      seg = @segments[i]
      canvas.line(viewport.px(seg[0]), viewport.py(seg[1]), viewport.px(seg[2]), viewport.py(seg[3]))
      i += 1
    np = @points.size()
    i = 0
    while i < np
      pt = @points[i]
      canvas.set(viewport.px(pt[0]), viewport.py(pt[1]))
      i += 1
    DrawilleScene.canvas_text(canvas, viewport, axes)

  -> .canvas_text(canvas, viewport = nil, axes = false)
    axis_row = -1
    axis_col = -1
    if axes && viewport != nil
      axis_row = viewport.x_axis_row()
      axis_col = viewport.y_axis_col()
    out = ""
    rows = canvas.rows
    cols = canvas.cols
    cells = canvas.cells
    idx = 0
    row = 0
    while row < rows
      out += "  "
      col = 0
      while col < cols
        v = cells[idx]
        if v != 0
          out += DRAWILLE_BRAILLE_GLYPHS[v]
        elsif row == axis_row && col == axis_col
          out += "+"
        elsif row == axis_row
          out += "-"
        elsif col == axis_col
          out += "|"
        else
          out += " "
        idx += 1
        col += 1
      out += "\n"
      row += 1
    out

  -> .label_line(left, right, cols)
    width = DrawilleNumbers.bounded_cols(cols)
    gap = width - left.size() - right.size()
    gap = 1 if gap < 1
    "  " + left + (" " * gap) + right + "\n"
