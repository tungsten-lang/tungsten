# studio/overlay — generic overlay elements, drawn with Canvas.
#
# The look of a series (its source bars, supers, title and credit cards, pane labels) is data: lists of elements
# that the episode or its style file supplies, in canvas units. The engine only draws them.
#
#   text    {t, text, x, y, size, family, weight, style, fill, anchor: start|middle|end, valign: base|mid,
#            spacing, center_spaced, stroke, stroke_w, linejoin, id}
#             valign "mid": y is the middle between ascender and descender (PIL's "lm"/"rm" anchors)
#             center_spaced: x is the centre of letter-spaced text whose width counts the spacing between glyphs
#             only (PIL drew such text glyph by glyph)
#   circle  {t, x, y, r, fill}
#   line    {t, x0, y0, x1, y1, stroke, width}
#   rect    {t, x, y, w, h, fill}
#   image   {t, src (an asset key), x, y, w, h}
#   fit     {t, against, side: right|left, pad, limit, options: [[element, ...], ...]}
#             the first option whose first text element keeps `pad` clear of the element whose id is `against`
#             (on the given side of it; `limit` is the free edge when that element is absent), else the last option
#
# Colours are [r, g, b] in 0..255, scaled by the alpha the caller passes (premultiplied over black, as the legacy
# renderer drew faded labels), or CSS strings, which are used as they are.

use base

-> ov_rgb(c, a)
  return c if c.is_a?(String)
  [(c[0] + ~0.0) * a / ~255.0, (c[1] + ~0.0) * a / ~255.0, (c[2] + ~0.0) * a / ~255.0]

# The font options of a text element (only the keys it sets, so Canvas sees what the legacy calls passed).
-> ov_font(e)
  o = {size: e["size"]}
  o[:family] = e["family"] if e["family"] != nil
  o[:weight] = e["weight"] if e["weight"] != nil
  o[:style] = e["style"] if e["style"] != nil
  o[:spacing] = e["spacing"] if e["spacing"] != nil
  o

-> ov_text_opts(e, a)
  o = ov_font(e)
  o[:fill] = ov_rgb(e["fill"], a)
  o[:anchor] = e["anchor"] if e["anchor"] != nil
  o

# Index the elements that carry an id (inside fit options too), for `against`.
-> ov_index(els, idx)
  els.each ->(e)
    idx[e["id"]] = e if e["id"] != nil
    if e["t"] == "fit"
      e["options"].each ->(op)
        ov_index(op, idx)
  idx

# Left and right edge of a text element, measured.
-> ov_text_edges(c, e)
  w = c.text_width(e["text"], ov_font(e))
  x = e["x"]
  an = get(e, "anchor", "start")
  return [x - w, x] if an == "end"
  return [x - w / ~2.0, x + w / ~2.0] if an == "middle"
  [x, x + w]

-> ov_first_text(op)
  op.each ->(e)
    return e if e["t"] == "text"
  nil

# The option of a fit element to draw.
-> ov_choose(c, e, idx)
  ops = e["options"]
  ag = idx[e["against"]]
  pad = get(e, "pad", 0)
  side = get(e, "side", "right")
  i = 0
  while i + 1 < ops.size
    t = ov_first_text(ops[i])
    return ops[i] if t == nil
    w = c.text_width(t["text"], ov_font(t))
    if side == "right"
      # the free edge on the right: the against element's left edge minus pad (or the limit)
      right = to_f(get(e, "limit", ~0.0))
      if ag != nil
        right = ov_text_edges(c, ag)[0] - pad
      return ops[i] if !(w > right - t["x"])
    else
      left = to_f(get(e, "limit", ~0.0))
      if ag != nil
        left = ov_text_edges(c, ag)[1] + pad
      return ops[i] if !(left > ov_text_edges(c, t)[0])
    i += 1
  ops[ops.size - 1]

-> ov_draw_text(c, e, a, text)
  x = e["x"]
  y = e["y"]
  if get(e, "valign", "base") == "mid"
    m = c.measure_text(text, ov_font(e))
    y = y + (m[:ascent] - m[:descent]) / ~2.0
  o = ov_text_opts(e, a)
  if get(e, "center_spaced", false)
    sp = e["spacing"]
    tw = c.text_width(text, ov_font(e))
    total = tw - sp
    x = x - total / ~2.0
    o[:anchor] = "start"
  if e["stroke"] != nil
    o[:stroke] = ov_rgb(e["stroke"], a)
    o[:width] = e["stroke_w"]
    o[:linejoin] = e["linejoin"] if e["linejoin"] != nil
  c.text(x, y, text, o)

# Draw a list of elements at alpha a. `owner.overlay_image(key)` turns an asset key into a CanvasImage.
-> ov_draw(c, els, a, owner)
  return nil if els == nil
  idx = ov_index(els, {})
  els.each ->(e)
    ov_draw_one(c, e, a, idx, owner)
  nil

-> ov_draw_one(c, e, a, idx, owner)
  t = e["t"]
  if t == "text"
    ov_draw_text(c, e, a, e["text"])
  elsif t == "circle"
    c.circle(e["x"], e["y"], e["r"], {fill: ov_rgb(e["fill"], a)})
  elsif t == "line"
    c.line(e["x0"], e["y0"], e["x1"], e["y1"], {stroke: ov_rgb(e["stroke"], a), width: e["width"]})
  elsif t == "rect"
    c.rect(e["x"], e["y"], e["w"], e["h"], {fill: ov_rgb(e["fill"], a)})
  elsif t == "image"
    c.image(owner.overlay_image(e["src"]), e["x"], e["y"], e["w"], e["h"], {fit: :fill, quality: :high})
  elsif t == "fit"
    ov_choose(c, e, idx).each ->(x)
      ov_draw_one(c, x, a, idx, owner)
  else
    die("unknown overlay element " + t.to_s)
  nil

# Timed text overlays (supers): [local start ms, duration ms, spec] where spec = {el: text element, reveal_ms:
# ms per character typed (0: all at once), fade_ms: fade-out at the end, stroke_min_alpha: below this alpha the
# stroke is dropped}. lt is item-local seconds.
-> ov_draw_timed(c, list, lt)
  return nil if list == nil
  list.each ->(s)
    at = to_f(s[0]) / ~1000.0
    dur = to_f(s[1]) / ~1000.0
    ls = lt - at
    if ls >= ~0.0 && ls < dur
      sp = s[2]
      e = sp["el"]
      text = e["text"]
      cps = to_f(get(sp, "reveal_ms", 0)) / ~1000.0
      nch = text.size
      if cps > ~0.0
        nch = (ls / cps).floor.to_i + 1
        nch = text.size if nch > text.size
      fade = to_f(get(sp, "fade_ms", 0)) / ~1000.0
      alpha = ~1.0
      alpha = [~0.0, (dur - ls) / fade].max if fade > ~0.0 && ls >= dur - fade
      part = text.slice(0, nch)
      if e["stroke"] != nil && alpha > to_f(get(sp, "stroke_min_alpha", ~0.0))
        ov_draw_text(c, e, alpha, part)
      else
        o = ov_text_opts(e, alpha)
        c.text(e["x"], e["y"], part, o)
  nil
