# Canvas — native vector drawing (CoreGraphics + CoreText + ImageIO) into an RGBA bitmap.
#
# The drop-in successor to building an Svg and rasterizing it with rsvg-convert:
# the same shapes and attribute hashes, drawn straight into pixels, with real
# text metrics. Compiled programs on macOS only (runtime/quartz.c), like Metal.
#
#   c = Canvas.new(1280, 720, scale: 2)            # user units; 2560 x 1440 pixels
#   c.clear("#0b0e13")
#   field = Canvas.radial(0.62, 0.45, 0.75, [[0, "#1c2533"], [1, "#0b0e13"]], units: :bbox)
#   c.rect(0, 0, 1280, 720, fill: field)
#   c.image("s17.png", 0, -18, 1780, 755, fit: :slice)
#   c.rect(46, 72, 206, 100, fill: "#ff8a5b", rx: 50)
#   c.circle(200, 150, 40, fill: "#2266aa", stroke: "#000", width: 1.5)
#   c.path("M 10 20 C 40 0, 60 0, 90 20", stroke: "#c31", width: 3, fill: "none")
#   c.text(56, 380, "ALL IS", size: 160, weight: "bold", fill: "#fff",
#          stroke: "#0b0e13", width: 9, linejoin: "round", spacing: -4)
#   c.write_png("thumb.png")                       # sRGB ICC profile embedded
#   c.close                                        # frees the pixels now
#
# Coordinates are user units, y down, origin top-left; `scale` device pixels
# per unit. Shapes take Svg's attribute keys: fill, stroke, width (stroke
# width), opacity, fill_opacity, stroke_opacity, dash ("10 8" or [10, 8]),
# dash_offset, linecap, linejoin, miter, rule (:evenodd), blend, rx/ry (rect
# corners). SVG defaults apply: fill black, stroke none. A fill or stroke is a
# colour ("#rgb", "#rrggbbaa", "rgba(…)", CSS names, Color values such as
# #FF8A5B, 0xRRGGBB, or [r, g, b(, a)] in 0..1) or a gradient from
# Canvas.linear / Canvas.radial.
#
# Text: size, family (a CSS list, "Helvetica Neue, Helvetica, sans-serif"),
# weight ("bold", 500, …), style ("italic"), anchor (start/middle/end),
# baseline (alphabetic/middle/hanging/bottom), spacing (letter spacing). A
# stroke is drawn under the fill (SVG paint-order="stroke"). CoreText falls back
# per glyph, so Greek, √, ², the full-width ＜＞ and emoji all render.
# measure_text gives the advance, ascent, descent and ink box.
#
# Colour: `space:` is "srgb" (default), "rec709", "display_p3", "linear_srgb",
# "extended_srgb", "extended_linear_srgb", "linear_display_p3", "rec2020",
# "linear_rec2020", "dci_p3", "adobe_rgb" or "acescg"; `depth:` is 8 (default),
# 16, "half" or "float". With `manage: false` (default) colours and image pixels
# are code values in the canvas space, as the SVG -> rsvg -> ffmpeg pipeline
# treated them; `manage: true` reads colours as sRGB and images through their
# embedded profiles, and colour-matches into the canvas space.
#
# Video frames: keep one canvas, call clear (and reset) per frame, read pixels
# with bytes / pixel / data_pointer, or write_png. Images are decoded once and
# cached by path (Canvas.load_image), so a still drawn on 10,000 frames costs
# one decode. There are no finalizers: close a canvas you are done with.

+ Canvas
  ro :width, :height, :scale, :space, :handle

  # Canvas.new(width, height, scale: 1, space: "srgb", depth: 8, manage: false,
  # background: nil). Pixels start transparent unless a background is given.
  -> new(@width, @height, opts = {})
    @scale = opts[:scale]
    @scale = 1 if @scale == nil
    @closed = false
    @handle = ccall("w_cg_canvas_new", @width, @height, @scale, opts[:space], opts[:depth], opts[:manage])
    @space = ccall("w_cg_canvas_info", @handle, "space")
    bg = opts[:background]
    if bg != nil
      ccall("w_cg_clear", @handle, bg)

  # True when this build has the native bridge (macOS); elsewhere every Canvas
  # call raises "Canvas needs macOS CoreGraphics/CoreText".
  -> .available?
    ccall("w_cg_available")

  # PostScript name of the face a CSS family list resolves to, after fallback:
  # Canvas.font_name("Helvetica Neue", "bold") == "HelveticaNeue-Bold".
  -> .font_name(family, weight = nil, style = nil)
    ccall("w_cg_font_name", family, weight, style)

  # Decode an image file once (PNG, JPEG, HEIC, TIFF, GIF, OpenEXR, …); loading
  # the same unchanged path again returns the cached pixels.
  -> .load_image(path)
    h = ccall("w_cg_image_load", path)
    CanvasImage.new(h, ccall("w_cg_image_info", h, "width"), ccall("w_cg_image_info", h, "height"), path)

  # Release every cached image; returns how many were released.
  -> .purge_images
    ccall("w_cg_image_purge")

  # Native memory in use: {canvases:, canvas_bytes:, images:, image_bytes:, fonts:}.
  -> .stats
    s = ccall("w_cg_stats")
    {canvases: s[0], canvas_bytes: s[1], images: s[2], image_bytes: s[3], fonts: s[4]}

  # A linear gradient from (x1, y1) to (x2, y2). stops = [[offset, colour], …]
  # or [[offset, colour, opacity], …]. units: :user (default) or :bbox
  # (fractions of the painted shape's bounding box, like SVG's default);
  # spread: :pad (default) or :none.
  -> .linear(x1, y1, x2, y2, stops, opts = {})
    CanvasGradient.new("linear", [x1, y1, x2, y2, nil, nil], stops, opts[:units], opts[:spread])

  # A radial gradient: centre (cx, cy), radius r, optional focal point fx/fy
  # and focal radius fr in opts (SVG radialGradient).
  -> .radial(cx, cy, r, stops, opts = {})
    CanvasGradient.new("radial", [cx, cy, r, opts[:fx], opts[:fy], opts[:fr]], stops, opts[:units], opts[:spread])

  # ---- size, lifetime ----

  -> pixel_width
    ccall("w_cg_canvas_info", @handle, "pixel_width")

  -> pixel_height
    ccall("w_cg_canvas_info", @handle, "pixel_height")

  # Bytes per pixel row of the buffer behind data_pointer.
  -> stride
    ccall("w_cg_canvas_info", @handle, "stride")

  # 8, 16, "half" or "float".
  -> depth
    ccall("w_cg_canvas_info", @handle, "depth")

  # Free the pixel buffer now. Later drawing raises; closing twice is fine.
  -> close
    ccall("w_cg_canvas_close", @handle)
    @closed = true
    nil

  -> closed?
    @closed

  # ---- state ----

  -> save
    ccall("w_cg_save", @handle)
    self

  -> restore
    ccall("w_cg_restore", @handle)
    self

  # Pop every save: identity transform, no clip, alpha 1, normal blend, empty
  # path. Pixels are kept (see clear).
  -> reset
    ccall("w_cg_reset", @handle)
    self

  -> translate(x, y)
    ccall("w_cg_translate", @handle, x, y)
    self

  -> scale_by(sx, sy = nil)
    ccall("w_cg_scale", @handle, sx, sy)
    self

  # Radians, clockwise on screen; with cx/cy, about that point (SVG rotate).
  -> rotate(angle, cx = nil, cy = nil)
    if cx != nil
      ccall("w_cg_translate", @handle, cx, cy)
    ccall("w_cg_rotate", @handle, angle)
    if cx != nil
      ccall("w_cg_translate", @handle, ~0.0 - cx, ~0.0 - cy)
    self

  # Concatenate SVG matrix(a b c d e f).
  -> transform(a, b, c, d, e, f)
    ccall("w_cg_concat", @handle, a, b, c, d, e, f)
    self

  # The current user transform as [a, b, c, d, e, f].
  -> ctm
    ccall("w_cg_ctm", @handle)

  # Global alpha (0..1) for everything drawn until restore.
  -> alpha=(a)
    ccall("w_cg_set_alpha", @handle, a)

  # normal, multiply, screen, overlay, darken, lighten, color_dodge,
  # color_burn, soft_light, hard_light, difference, exclusion, hue,
  # saturation, color, luminosity, plus the Porter-Duff modes (copy,
  # source_in, destination_out, xor, plus_lighter, …).
  -> blend=(mode)
    ccall("w_cg_set_blend", @handle, mode)

  # Image interpolation: none, low, medium, high (default).
  -> quality=(q)
    ccall("w_cg_set_quality", @handle, q)

  -> antialias=(enabled)
    ccall("w_cg_set_antialias", @handle, enabled)

  # Group opacity: everything drawn until end_layer composites as one image.
  -> begin_layer(opacity = nil)
    ccall("w_cg_layer_begin", @handle, opacity)
    self

  -> end_layer
    ccall("w_cg_layer_end", @handle)
    self

  # ---- pixels ----

  # Set every pixel to a colour (transparent for nil), ignoring transform,
  # clip, alpha and blend.
  -> clear(color = nil)
    ccall("w_cg_clear", @handle, color)
    self

  # [r, g, b, a] unpremultiplied at device pixel (px, py): 0..255 on 8-bit
  # canvases, 0..65535 on 16-bit, Floats on half/float. nil outside.
  -> pixel(px, py)
    ccall("w_cg_pixel", @handle, px, py)

  # RGBA8 ByteArray (pixel_width * pixel_height * 4, rows packed), straight
  # alpha unless premultiplied.
  -> bytes(premultiplied = false)
    ccall("w_cg_bytes", @handle, premultiplied)

  # Address of the premultiplied RGBA pixel buffer (stride bytes per row), for
  # native encoders; valid until close.
  -> data_pointer
    ccall("w_cg_data_ptr", @handle)

  # An RGB Raster of the canvas composited over a 0xRRGGBB background.
  -> to_raster(background = 0xFFFFFF)
    r = Raster.new(pixel_width, pixel_height, background)
    ccall("w_cg_to_raster", @handle, r.pixels, background)
    r

  # The current pixels as a CanvasImage (release it when done).
  -> snapshot
    h = ccall("w_cg_image_from_canvas", @handle)
    CanvasImage.new(h, pixel_width, pixel_height, nil)

  # PNG with the colour space's ICC profile; alpha: false composites over black.
  -> write_png(path, opts = {})
    ccall("w_cg_write", @handle, path, "png", nil, opts[:alpha])
    path

  # Type from the extension: .png, .jpg/.jpeg, .tif/.tiff, .heic; quality 0..1
  # for the lossy ones.
  -> write(path, opts = {})
    ccall("w_cg_write", @handle, path, Canvas.type_for(path), opts[:quality], opts[:alpha])
    path

  # The encoded file as a ByteArray.
  -> encode(type = "png", opts = {})
    ccall("w_cg_encode", @handle, type, opts[:quality], opts[:alpha])

  -> .type_for(path)
    p = path.downcase
    return "jpeg" if p.ends_with?(".jpg") || p.ends_with?(".jpeg")
    return "tiff" if p.ends_with?(".tif") || p.ends_with?(".tiff")
    return "heic" if p.ends_with?(".heic")
    "png"

  # ---- paths ----

  -> begin_path
    ccall("w_cg_path_begin", @handle)
    self

  -> move_to(x, y)
    ccall("w_cg_move_to", @handle, x, y)
    self

  -> line_to(x, y)
    ccall("w_cg_line_to", @handle, x, y)
    self

  -> quad_to(cx, cy, x, y)
    ccall("w_cg_quad_to", @handle, cx, cy, x, y)
    self

  -> curve_to(c1x, c1y, c2x, c2y, x, y)
    ccall("w_cg_curve_to", @handle, c1x, c1y, c2x, c2y, x, y)
    self

  # HTML canvas arc: radians, clockwise on screen unless ccw.
  -> arc(cx, cy, r, start, stop, ccw = false)
    ccall("w_cg_arc", @handle, cx, cy, r, start, stop, ccw)
    self

  -> arc_to(x1, y1, x2, y2, r)
    ccall("w_cg_arc_to", @handle, x1, y1, x2, y2, r)
    self

  -> close_path
    ccall("w_cg_path_close", @handle)
    self

  -> add_rect(x, y, w, h)
    ccall("w_cg_add_rect", @handle, x, y, w, h)
    self

  -> add_round_rect(x, y, w, h, rx, ry = nil)
    ccall("w_cg_add_round_rect", @handle, x, y, w, h, rx, ry)
    self

  -> add_ellipse(cx, cy, rx, ry = nil)
    ccall("w_cg_add_ellipse", @handle, cx, cy, rx, ry)
    self

  # SVG path data: M L H V C S Q T A Z, absolute and relative.
  -> add_path(d)
    ccall("w_cg_add_svg", @handle, d)
    self

  # [[x, y], …] or a flat [x0, y0, x1, y1, …], as one subpath.
  -> add_points(pts, closed = false)
    ccall("w_cg_add_points", @handle, pts, closed)
    self

  # [x, y, w, h] of the current path, or nil when it is empty.
  -> path_bounds
    ccall("w_cg_path_bounds", @handle)

  -> contains?(x, y, rule = nil)
    ccall("w_cg_path_contains", @handle, x, y, Canvas.evenodd?(rule))

  # Paint the current path with an attribute hash (fill, stroke, …).
  -> paint(opts = {})
    draw_current(opts, "#000")

  -> fill(paint = "#000", opts = {})
    draw_current(opts.merge({fill: paint, stroke: nil}), paint)

  -> stroke(paint = "#000", opts = {})
    draw_current(opts.merge({fill: nil, stroke: paint}), nil)

  # Intersect the clip with the current path (consuming it); undo with restore.
  -> clip(rule = nil)
    ccall("w_cg_clip", @handle, Canvas.evenodd?(rule))
    self

  -> clip_rect(x, y, w, h)
    ccall("w_cg_path_begin", @handle)
    ccall("w_cg_add_rect", @handle, x, y, w, h)
    ccall("w_cg_clip", @handle, false)
    self

  -> clip_path(d, rule = nil)
    ccall("w_cg_path_begin", @handle)
    ccall("w_cg_add_svg", @handle, d)
    ccall("w_cg_clip", @handle, Canvas.evenodd?(rule))
    self

  # ---- shapes (Svg's methods and attribute keys) ----

  -> rect(x, y, w, h, opts = {})
    ccall("w_cg_path_begin", @handle)
    rx = opts[:rx]
    ry = opts[:ry]
    if rx == nil && ry == nil
      ccall("w_cg_add_rect", @handle, x, y, w, h)
    else
      ccall("w_cg_add_round_rect", @handle, x, y, w, h, rx, ry)
    draw_current(opts, "#000")

  -> circle(cx, cy, r, opts = {})
    ccall("w_cg_path_begin", @handle)
    ccall("w_cg_add_ellipse", @handle, cx, cy, r, r)
    draw_current(opts, "#000")

  -> ellipse(cx, cy, rx, ry, opts = {})
    ccall("w_cg_path_begin", @handle)
    ccall("w_cg_add_ellipse", @handle, cx, cy, rx, ry)
    draw_current(opts, "#000")

  # A line has no fill; give it a stroke.
  -> line(x1, y1, x2, y2, opts = {})
    ccall("w_cg_path_begin", @handle)
    ccall("w_cg_move_to", @handle, x1, y1)
    ccall("w_cg_line_to", @handle, x2, y2)
    draw_current(opts, nil)

  # Open polyline, unfilled by default (as Svg#polyline).
  -> polyline(pts, opts = {})
    ccall("w_cg_path_begin", @handle)
    ccall("w_cg_add_points", @handle, pts, false)
    draw_current(opts, nil)

  -> polygon(pts, opts = {})
    ccall("w_cg_path_begin", @handle)
    ccall("w_cg_add_points", @handle, pts, true)
    draw_current(opts, "#000")

  # SVG path data, as Svg#path.
  -> path(d, opts = {})
    ccall("w_cg_path_begin", @handle)
    ccall("w_cg_add_svg", @handle, d)
    draw_current(opts, "#000")

  # ---- images ----

  # Draw src (a path, a CanvasImage, or another Canvas) into the box x, y, w, h
  # (w/h nil = the image's size). opts: fit (:meet default, :slice, :fill),
  # align ("xMidYMid", "xMinYMin", …), opacity, quality, src ([sx, sy, sw, sh]
  # crop in image pixels), blend.
  -> image(src, x, y, w = nil, h = nil, opts = {})
    snap = nil
    img = src
    if src.is_a?(Canvas)
      snap = src.snapshot
      img = snap
    elsif !src.is_a?(CanvasImage)
      img = Canvas.load_image(src)
    crop = opts[:src]
    sx = nil
    sy = nil
    sw = nil
    sh = nil
    if crop != nil
      sx = crop[0]
      sy = crop[1]
      sw = crop[2]
      sh = crop[3]
    blend = opts[:blend]
    if blend != nil
      ccall("w_cg_save", @handle)
      ccall("w_cg_set_blend", @handle, blend)
    ccall("w_cg_image_draw", @handle, img.handle, x, y, w, h, opts[:fit], opts[:align], opts[:opacity], opts[:quality], sx, sy, sw, sh)
    if blend != nil
      ccall("w_cg_restore", @handle)
    if snap != nil
      snap.release
    self

  # ---- text ----

  # One line of text with its baseline at (x, y); see the header for opts.
  -> text(x, y, s, opts = {})
    text_style(opts)
    str = s.to_s
    fill = "#000"
    fill = opts[:fill] if opts.has_key?(:fill)
    stroke = opts[:stroke]
    blend = opts[:blend]
    if blend != nil
      ccall("w_cg_save", @handle)
      ccall("w_cg_set_blend", @handle, blend)
    if stroke != nil
      apply_line(opts)
    if fill.is_a?(CanvasGradient)
      gradient_text(x, y, str, fill, stroke, opts)
    else
      ccall("w_cg_text", @handle, x, y, str, opts[:anchor], opts[:baseline], fill, opts[:fill_opacity], stroke, opts[:stroke_opacity], opts[:opacity])
    if blend != nil
      ccall("w_cg_restore", @handle)
    self

  # Several differently styled pieces on one baseline, as Svg#text_runs:
  # runs = [[string, opts], …]; run opts override the outer ones and may add
  # dx (a gap before the run) and shift (raise the run: user units, or
  # "super" / "sub"). Strokes are all drawn before fills.
  -> text_runs(x, y, runs, opts = {})
    merged = []
    widths = []
    total = ~0.0
    runs.each -> (r)
      o = opts
      if r.size > 1 && r[1] != nil
        o = opts.merge(r[1])
      text_style(o)
      wd = ccall("w_cg_text_measure", @handle, r[0].to_s)[0]
      dx = o[:dx]
      dx = ~0.0 if dx == nil
      merged.push(o)
      widths.push(wd)
      total = total + dx + wd
    anchor = opts[:anchor]
    cx = x + ~0.0
    if anchor == "middle" || anchor == :middle
      cx = cx - total / ~2.0
    elsif anchor == "end" || anchor == :end
      cx = cx - total
    pass = 0
    while pass < 2
      px = cx
      i = 0
      while i < merged.size
        o = merged[i]
        dx = o[:dx]
        dx = ~0.0 if dx == nil
        px = px + dx
        py = y - run_shift(o)
        stroke = o[:stroke]
        if pass == 0 && stroke != nil
          text_style(o)
          apply_line(o)
          ccall("w_cg_text", @handle, px, py, runs[i][0].to_s, nil, o[:baseline], nil, nil, stroke, o[:stroke_opacity], o[:opacity])
        if pass == 1
          fill = "#000"
          fill = o[:fill] if o.has_key?(:fill)
          text_style(o)
          ccall("w_cg_text", @handle, px, py, runs[i][0].to_s, nil, o[:baseline], fill, o[:fill_opacity], nil, nil, o[:opacity])
        px = px + widths[i]
        i += 1
      pass += 1
    self

  # {width:, ascent:, descent:, leading:, left:, top:, right:, bottom:} in user
  # units. width is the advance; left..bottom is the ink box relative to the
  # baseline origin, y down (top is negative above the baseline).
  -> measure_text(s, opts = {})
    text_style(opts)
    m = ccall("w_cg_text_measure", @handle, s.to_s)
    {width: m[0], ascent: m[1], descent: m[2], leading: m[3], left: m[4], top: m[5], right: m[6], bottom: m[7]}

  # The advance width of s, in user units.
  -> text_width(s, opts = {})
    text_style(opts)
    ccall("w_cg_text_measure", @handle, s.to_s)[0]

  # ---- internals ----

  -> .evenodd?(rule)
    rule == "evenodd" || rule == :evenodd

  -> text_style(opts)
    family = opts[:family]
    family = "Helvetica, Arial, sans-serif" if family == nil
    ccall("w_cg_text_style", @handle, family, opts[:size], opts[:weight], opts[:style], opts[:spacing])

  -> apply_line(opts)
    w = opts[:width]
    w = opts[:stroke_width] if w == nil
    ccall("w_cg_set_line", @handle, w, opts[:linecap], opts[:linejoin], opts[:miter], opts[:dash], opts[:dash_offset])

  -> run_shift(o)
    s = o[:shift]
    return ~0.0 if s == nil
    size = o[:size]
    size = 16 if size == nil
    return size * ~0.4 if s == "super" || s == :super
    return ~0.0 - size * ~0.2 if s == "sub" || s == :sub
    s + ~0.0

  -> none?(p)
    p == nil || p == "none" || p == :none || p == false

  # Paint the current path per the attribute hash, SVG order: fill, stroke.
  -> draw_current(opts, default_fill)
    fill = default_fill
    fill = opts[:fill] if opts.has_key?(:fill)
    stroke = opts[:stroke]
    blend = opts[:blend]
    rule = opts[:rule]
    rule = opts[:fill_rule] if rule == nil
    eo = Canvas.evenodd?(rule)
    if blend != nil
      ccall("w_cg_save", @handle)
      ccall("w_cg_set_blend", @handle, blend)
    if !none?(stroke)
      apply_line(opts)
    if fill.is_a?(CanvasGradient) || stroke.is_a?(CanvasGradient)
      paint_gradients(fill, stroke, opts, eo)
    else
      ccall("w_cg_paint", @handle, fill, opts[:fill_opacity], stroke, opts[:stroke_opacity], opts[:opacity], eo)
    if blend != nil
      ccall("w_cg_restore", @handle)
    self

  -> paint_gradients(fill, stroke, opts, eo)
    op = opts[:opacity]
    op = ~1.0 if op == nil
    group = !none?(fill) && !none?(stroke) && op < 1
    if group
      ccall("w_cg_layer_begin", @handle, op)
      op = ~1.0
    fo = opts[:fill_opacity]
    fo = ~1.0 if fo == nil
    so = opts[:stroke_opacity]
    so = ~1.0 if so == nil
    if fill.is_a?(CanvasGradient)
      paint_gradient("fill", fill, fo * op, eo)
    elsif !none?(fill)
      ccall("w_cg_paint", @handle, fill, fo * op, nil, nil, nil, eo)
    if stroke.is_a?(CanvasGradient)
      paint_gradient("stroke", stroke, so * op, eo)
    elsif !none?(stroke)
      ccall("w_cg_paint", @handle, nil, nil, stroke, so * op, nil, eo)
    if group
      ccall("w_cg_layer_end", @handle)
    self

  -> paint_gradient(target, g, opacity, eo)
    k = g.coords
    ccall("w_cg_gradient", @handle, target, g.kind, k[0], k[1], k[2], k[3], k[4], k[5], g.stops, opacity, eo, g.bbox?, g.spread)

  # Gradient-filled text: stroke first, then clip to the glyphs and paint the
  # gradient over the ink box.
  -> gradient_text(x, y, str, g, stroke, opts)
    if !none?(stroke)
      ccall("w_cg_text", @handle, x, y, str, opts[:anchor], opts[:baseline], nil, nil, stroke, opts[:stroke_opacity], opts[:opacity])
    m = ccall("w_cg_text_measure", @handle, str)
    ccall("w_cg_save", @handle)
    ccall("w_cg_text_clip", @handle, x, y, str, opts[:anchor], opts[:baseline])
    ccall("w_cg_path_begin", @handle)
    left = x + m[4] - m[0]
    ccall("w_cg_add_rect", @handle, left, y - m[1] - m[2], m[0] * ~3.0, (m[1] + m[2]) * ~3.0)
    fo = opts[:fill_opacity]
    fo = ~1.0 if fo == nil
    op = opts[:opacity]
    op = ~1.0 if op == nil
    paint_gradient("fill", g, fo * op, false)
    ccall("w_cg_restore", @handle)
    self

# CanvasGradient — a linear or radial gradient for Canvas fills and strokes
# (Canvas.linear / Canvas.radial); plain data, no native resources.
+ CanvasGradient
  ro :kind, :coords, :stops, :units, :spread

  -> new(@kind, @coords, @stops, @units, @spread)

  -> bbox?
    @units == "bbox" || @units == :bbox

# CanvasImage — a decoded image held by the Canvas image cache
# (Canvas.load_image, Canvas#snapshot).
+ CanvasImage
  ro :handle, :width, :height, :path

  -> new(@handle, @width, @height, @path)

  # The image's colour space selector ("srgb", "display_p3", …) or ICC name.
  -> space
    ccall("w_cg_image_info", @handle, "space")

  # Decoded RGBA8 (unpremultiplied, in the image's own colour space) as a
  # ByteArray of width * height * 4.
  -> bytes
    ccall("w_cg_image_bytes", @handle)

  # Drop the decoded pixels now (the cache also evicts past 4 GiB).
  -> release
    ccall("w_cg_image_release", @handle)
    nil
