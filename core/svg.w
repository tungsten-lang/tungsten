# Svg — a small vector-figure builder.
#
#   s = Svg.new(400, 300)                  # viewBox 0 0 400 300
#   s.rect(0, 0, 400, 300, fill: "#fff")
#   s.circle(200, 150, 40, fill: "#2266aa", stroke: "#000", width: 1.5)
#   s.line(0, 0, 400, 300, stroke: "#c31", width: 2)
#   s.polyline([[0, 0], [10, 20], [30, 5]], stroke: "#000")
#   s.text(10, 20, "label", size: 14)
#   s.write("fig.svg")                     # s.write_png("fig.png") via rsvg-convert
#
# Attribute hashes accept: fill, stroke, width (stroke width), opacity,
# dash, anchor (text-anchor), size (font size), weight, family, class, transform.

+ Svg
  ro :width, :height

  -> new(@width, @height, view = nil)
    @buf = StringBuffer()
    if view == nil
      @view = "0 0 [@width] [@height]"
    else
      @view = view

  -> .num(v)
    if v.class_name == "Int"
      return v.to_s
    f = v + ~0.0
    r = (f * ~100.0).round / ~100.0
    s = r.to_s
    if s.ends_with?(".0")
      s = s.slice(0, s.size - 2)
    s

  -> .esc(s)
    s.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub("\"", "&quot;")

  -> attrs(opts)
    out = ""
    if opts == nil
      return out
    if opts.has_key?(:fill)
      out = out + " fill=\"[opts[:fill]]\""
    if opts.has_key?(:stroke)
      out = out + " stroke=\"[opts[:stroke]]\""
    if opts.has_key?(:width)
      out = out + " stroke-width=\"[Svg.num(opts[:width])]\""
    if opts.has_key?(:opacity)
      out = out + " opacity=\"[Svg.num(opts[:opacity])]\""
    if opts.has_key?(:dash)
      out = out + " stroke-dasharray=\"[opts[:dash]]\""
    if opts.has_key?(:anchor)
      out = out + " text-anchor=\"[opts[:anchor]]\""
    if opts.has_key?(:size)
      out = out + " font-size=\"[Svg.num(opts[:size])]\""
    if opts.has_key?(:weight)
      out = out + " font-weight=\"[opts[:weight]]\""
    if opts.has_key?(:family)
      out = out + " font-family=\"[opts[:family]]\""
    if opts.has_key?(:class)
      out = out + " class=\"[opts[:class]]\""
    if opts.has_key?(:transform)
      out = out + " transform=\"[opts[:transform]]\""
    if opts.has_key?(:linecap)
      out = out + " stroke-linecap=\"[opts[:linecap]]\""
    out

  -> raw(s)
    @buf.append(s)
    @buf.append("\n")
    self

  -> rect(x, y, w, h, opts = {})
    raw("<rect x=\"[Svg.num(x)]\" y=\"[Svg.num(y)]\" width=\"[Svg.num(w)]\" height=\"[Svg.num(h)]\"[attrs(opts)]/>")

  -> circle(cx, cy, r, opts = {})
    raw("<circle cx=\"[Svg.num(cx)]\" cy=\"[Svg.num(cy)]\" r=\"[Svg.num(r)]\"[attrs(opts)]/>")

  -> line(x1, y1, x2, y2, opts = {})
    raw("<line x1=\"[Svg.num(x1)]\" y1=\"[Svg.num(y1)]\" x2=\"[Svg.num(x2)]\" y2=\"[Svg.num(y2)]\"[attrs(opts)]/>")

  -> points_attr(pts)
    parts = []
    pts.each -> (p)
      parts.push(Svg.num(p[0]) + "," + Svg.num(p[1]))
    parts.join(" ")

  -> polyline(pts, opts = {})
    if !opts.has_key?(:fill)
      opts[:fill] = "none"
    raw("<polyline points=\"[points_attr(pts)]\"[attrs(opts)]/>")

  -> polygon(pts, opts = {})
    raw("<polygon points=\"[points_attr(pts)]\"[attrs(opts)]/>")

  -> path(d, opts = {})
    raw("<path d=\"[d]\"[attrs(opts)]/>")

  -> text(x, y, s, opts = {})
    if !opts.has_key?(:family)
      opts[:family] = "Helvetica, Arial, sans-serif"
    raw("<text x=\"[Svg.num(x)]\" y=\"[Svg.num(y)]\"[attrs(opts)]>[Svg.esc(s)]</text>")

  -> group_open(opts = {})
    raw("<g[attrs(opts)]>")

  -> group_close
    raw("</g>")

  -> to_s
    head = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"[@width]\" height=\"[@height]\" viewBox=\"[@view]\">\n"
    head + @buf.to_s + "</svg>\n"

  -> write(path)
    File.write(path, to_s)
    path

  # Rasterizes with rsvg-convert when it is installed; returns the PNG path.
  -> write_png(path, scale = 1)
    tmp = path + ".tmp.svg"
    File.write(tmp, to_s)
    p = Process.spawn(["rsvg-convert", "-z", scale.to_s, "-o", path, tmp])
    p.wait
    File.delete(tmp)
    path
