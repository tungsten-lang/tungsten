# Drawille scene primitives, bounded viewports, and 3-D projection.
#
# This file deliberately knows nothing about algebra classes.  It accepts
# numeric points and line strips; the type-aware adapters live in inspection.w.
# Keeping this boundary lets core/algebra remain exact and visualization-free.

use canvas

+ DrawilleNumbers
  -> .numeric(value)
    return nil if value.class_name == "Nil"
    name = value.class_name
    numeric_names = [
      "Integer", "Int", "BigInt", "Rational",
      "Float", "Float16", "Float32", "Float64", "Float80", "Float128", "Float256",
      "Decimal", "Decimal32", "Decimal64", "Decimal128",
      "AlgebraicRealRoot"
    ]
    if numeric_names.include?(name)
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
    result = ~1.0
    factor = base.to_f()
    remaining = exponent
    while remaining > 0
      result *= factor if remaining.odd?()
      remaining /= 2
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

  -> px(x)
    span = @xmax - @xmin
    DrawilleNumbers.round_i(
      (x.to_f() - @xmin) * (@canvas.pixel_width() - 1).to_f() / span)

  -> py(y)
    span = @ymax - @ymin
    DrawilleNumbers.round_i(
      (@ymax - y.to_f()) * (@canvas.pixel_height() - 1).to_f() / span)

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
    xr = x.to_f() * cy - z.to_f() * sy
    zr = x.to_f() * sy + z.to_f() * cy
    yr = y.to_f() * cp - zr * sp
    depth = y.to_f() * sp + zr * cp
    scale = ~1.0
    if perspective
      denominator = distance.to_f() + depth
      denominator = ~0.25 if denominator < ~0.25
      scale = distance.to_f() / denominator
      scale = ~4.0 if scale > ~4.0
    [xr * scale, yr * scale, depth]

  -> .polyline(points, yaw_degrees = 38, pitch_degrees = 24,
               perspective = true, distance = 6)
    out = []
    points.each -> (point)
      out.push(project(
        point[0], point[1], point[2],
        yaw_degrees, pitch_degrees, perspective, distance))
    out


+ DrawilleScene
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
    return self if points.size() == 0
    points.each -> (point)
      self.point(point[0], point[1])
    i = 1
    while i < points.size()
      segment(points[i - 1][0], points[i - 1][1], points[i][0], points[i][1])
      i += 1
    self

  -> empty?
    @points.size() == 0 && @segments.size() == 0

  -> bounds(include_origin = false)
    values = []
    @points.each -> (point)
      values.push(point)
    @segments.each -> (segment)
      values.push([segment[0], segment[1]])
      values.push([segment[2], segment[3]])
    values.push([~0.0, ~0.0]) if include_origin
    return [~0.0, ~1.0, ~0.0, ~1.0] if values.size() == 0
    xmin = values[0][0]
    xmax = xmin
    ymin = values[0][1]
    ymax = ymin
    values.each -> (point)
      xmin = point[0] if point[0] < xmin
      xmax = point[0] if point[0] > xmax
      ymin = point[1] if point[1] < ymin
      ymax = point[1] if point[1] > ymax
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
    @segments.each -> (segment)
      p0 = viewport.point(segment[0], segment[1])
      p1 = viewport.point(segment[2], segment[3])
      canvas.line(p0[0], p0[1], p1[0], p1[1])
    @points.each -> (point)
      pixel = viewport.point(point[0], point[1])
      canvas.set(pixel[0], pixel[1])
    DrawilleScene.canvas_text(canvas, viewport, axes)

  -> .canvas_text(canvas, viewport = nil, axes = false)
    axis_row = -1
    axis_col = -1
    if axes && viewport != nil
      axis_row = viewport.x_axis_row()
      axis_col = viewport.y_axis_col()
    out = ""
    row = 0
    while row < canvas.rows
      out += "  "
      col = 0
      while col < canvas.cols
        if !canvas.cell_empty?(col, row)
          out += canvas.cell_char(col, row)
        elsif row == axis_row && col == axis_col
          out += "+"
        elsif row == axis_row
          out += "-"
        elsif col == axis_col
          out += "|"
        else
          out += " "
        col += 1
      out += "\n"
      row += 1
    out

  -> .label_line(left, right, cols)
    width = DrawilleNumbers.bounded_cols(cols)
    gap = width - left.size() - right.size()
    gap = 1 if gap < 1
    "  " + left + (" " * gap) + right + "\n"
