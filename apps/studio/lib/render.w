# studio/render — frame(f) = F(resolved timeline, assets, f).
#
# Binary-search the interval table, render each active item at its item-local frame into a layer canvas, and
# composite (dissolve, fade-in, the V4 fades) into packed RGB24. Nothing carries from one frame to the next except
# caches of pure precomputations keyed by their owners (decoded images, grain and vignette planes per style, the
# rain/fog/particle fields per item, the bars and cards per item), so any worker renders any frame in any order
# with identical bits. Ports every feature of tools/render.py; the differences are listed in TIMELINE.md §6.

use base
use raster

-> smooth(a)
  a = ~0.0 if a < ~0.0
  a = ~1.0 if a > ~1.0
  a * a * (~3.0 - ~2.0 * a)

-> clamp01(a)
  return ~0.0 if a < ~0.0
  return ~1.0 if a > ~1.0
  a

-> ease(u)
  u * ~0.6 + ~0.4 * (~0.5 - ~0.5 * Math.cos(~3.141592653589793 * u))

# render.py camera(): zoom and centre of a move at progress u over a shot of dur seconds.
-> camera_at(move, u, dur, fx, fy)
  amp = ~0.035 + ~0.010 * dur
  amp = ~0.15 if amp > ~0.15
  e = ease(u)
  if move == "push" || move == "pull"
    z = ~1.0 + amp * e
    z = ~1.0 + amp * (~1.0 - e) if move == "pull"
    k = (z - ~1.0) / [amp, ~0.000001].max
    return [z, ~0.5 + (fx - ~0.5) * ~0.5 * k, ~0.5 + (fy - ~0.5) * ~0.5 * k]
  if move == "pan_l" || move == "pan_r"
    span = ~0.035 + ~0.004 * dur
    d = ~1.0
    d = ~0.0 - ~1.0 if move == "pan_l"
    return [~1.10, ~0.5 + d * span * (e - ~0.5), ~0.5]
  if move == "tilt_u" || move == "tilt_d"
    span = ~0.03 + ~0.004 * dur
    d = ~1.0
    d = ~0.0 - ~1.0 if move == "tilt_u"
    return [~1.12, ~0.5, fy + d * span * (e - ~0.5)]
  if move == "drift"
    return [~1.04 + ~0.05 * e, ~0.5 + ~0.02 * (e - ~0.5), ~0.5 - ~0.012 * (e - ~0.5)]
  [~1.02 + ~0.025 * e, ~0.5, ~0.5]

-> status_color(label)
  u = label.upcase
  return [125, 220, 138] if u.starts_with?("ARTIFACT")
  return [242, 193, 78] if u.starts_with?("THEOREM")
  return [78, 161, 255] if u.starts_with?("EARLY")
  return [242, 193, 78] if u.starts_with?("ARISTOTLE")
  return [255, 138, 91] if u.starts_with?("LATE")
  return [255, 107, 107] if u.starts_with?("LEGEND")
  return [179, 157, 255] if u.starts_with?("MODERN")
  [239, 234, 225]

-> rgb(c)
  [(c[0] + ~0.0) / ~255.0, (c[1] + ~0.0) / ~255.0, (c[2] + ~0.0) / ~255.0]

-> rgb_scaled(c, a)
  [(c[0] + ~0.0) * a / ~255.0, (c[1] + ~0.0) * a / ~255.0, (c[2] + ~0.0) * a / ~255.0]

# Python round(): half to even.
-> round_even(x)
  f = Math.floor(x)
  d = x - f
  return f.to_i + 1 if d > ~0.5
  return f.to_i if d < ~0.5
  return f.to_i if f.to_i % 2 == 0
  f.to_i + 1

# render.py gap_text: centuries as Decimal(gap / 100) quantized half up (the exact value of the double), decades
# with Python's round.
-> gap_text(gap)
  if gap >= 100
    tenths = gap / 10
    r = gap % 10
    if r > 5
      tenths += 1
    elsif r == 5
      x = (gap + ~0.0) / ~100.0
      tenths += 1 if exact_sign_mul_sub(x, ~100.0, gap + ~0.0) >= 0
    return (tenths / 10).to_s + "." + (tenths % 10).to_s + " centuries later"
  if gap >= 5
    return "~" + (round_even((gap + ~0.0) / ~10.0) * 10).to_s + " years later"
  "contemporary"

-> dotted(s)
  return "" if s == nil
  s.gsub("·", "•")

+ Engine
  ro :out, :w, :h, :frames_rendered

  -> new(@proj, @r)
    @w = @r["w"]
    @h = @r["h"]
    @num = @r["rate"][0]
    @den = @r["rate"][1]
    @fps = (@num + ~0.0) / (@den + ~0.0)
    @seed = @r["seed"]
    act = @proj.ep["cuts"][@r["cut"]]["picture"]["active"]
    @ax0 = act[0]
    @bar_y = act[1]
    @aw = act[2]
    @ah = act[3]
    @v1 = @r["tracks"][0]["items"]
    @v4 = @r["tracks"][1]["items"]
    @iv = @r["intervals"]
    @act_a = Canvas.new(@aw, @ah)
    @act_b = Canvas.new(@aw, @ah)
    @layer0 = Canvas.new(@w, @h)
    @layer1 = Canvas.new(@w, @h)
    @pa = @act_a.data_pointer
    @pb_ptr = @act_b.data_pointer
    @l0 = @layer0.data_pointer
    @l1 = @layer1.data_pointer
    @astride = @act_a.stride
    @lstride = @layer0.stride
    n = @aw * @ah
    @wb = f32[n * 3]
    @lb = f32[n]
    @pbuf = f32[n]
    @bbuf = f32[n]
    @gw = @aw / 8
    @gh = @ah / 8
    @grid = f64[@gw * @gh]
    @gcnt = f64[@gw * @gh]
    @gtmp = f64[@gw * @gh]
    @gp = f64[16]
    @gk = f64[49]
    gs = ~0.0
    j = 0
    while j < 49
      dx = (j % 7 - 3) + ~0.0
      dy = (j / 7 - 3) + ~0.0
      @gk[j] = Math.exp(~0.0 - (dx * dx + dy * dy) / ~2.0)
      gs += @gk[j]
      j += 1
    j = 0
    while j < 49
      @gk[j] = @gk[j] / gs
      j += 1
    @out = u8[@w * @h * 3]
    @planes = {}
    @fields = {}
    @parts = {}
    @bars = {}
    @cards = {}
    @panes = {}
    @images = {}
    @image_order = []
    @seq = {}
    @seq_order = []
    @item_keys = {}
    @frames_rendered = 0

  -> close
    @act_a.close
    @act_b.close
    @layer0.close
    @layer1.close
    @bars.values.each ->(c)
      c.close
    @cards.values.each ->(c)
      c.close
    @panes.values.each ->(c)
      c.close
    Canvas.purge_images

  # ------------------------------------------------------------------------------------------ lookup

  -> interval_at(f)
    lo = 0
    hi = @iv.size - 1
    while lo < hi
      mid = (lo + hi + 1) / 2
      if @iv[mid][0] <= f
        lo = mid
      else
        hi = mid - 1
    @iv[lo]

  -> item_key(it)
    k = @item_keys[it["id"]]
    if k == nil
      k = id60(it["id"])
      @item_keys[it["id"]] = k
    k

  # Decoded stills (panels): a small LRU; the native cache would otherwise hold every still drawn.
  -> still(key)
    img = @images[key]
    if img == nil
      img = Canvas.load_image(@proj.asset_path(key))
      @images[key] = img
      @image_order.push(key)
      if @image_order.size > 6
        old = @image_order[0]
        @image_order = @image_order.drop(1)
        @images[old].release
        @images.delete(old)
    img

  # Frame-sequence images (clips, animations, program caches): an LRU of 4, released as they fall out.
  -> seq_image(path)
    img = @seq[path]
    if img == nil
      img = Canvas.load_image(path)
      @seq[path] = img
      @seq_order.push(path)
      if @seq_order.size > 4
        old = @seq_order[0]
        @seq_order = @seq_order.drop(1)
        @seq[old].release
        @seq.delete(old)
    img

  -> seq_path(dir, pattern, first, idx)
    # pattern "%05d.png": digits and extension
    digits = pattern.slice(2, 1).to_i
    ext = pattern.slice(4, pattern.size - 4)
    dir + "/" + pad_int(first + idx, digits) + ext

  -> asset_seq_path(key, idx)
    a = @proj.ep["assets"][key]
    seq_path(@proj.asset_path(key), a["pattern"], a["first"], idx)

  # ------------------------------------------------------------------------------------------ planes

  # Grain (10 planes) and vignette for a style, keyed by the style's own hash.
  -> planes(st)
    sk = hash_of(st)
    pl = @planes[sk]
    if pl == nil
      n = @aw * @ah
      vg = st["vignette"]
      vig = f32[n]
      rs_vignette(@aw, @ah, to_f(vg["amount"]), to_f(vg["x"]), to_f(vg["y"]), to_f(vg["clip"]), to_f(vg["power"]), vig)
      gr = st["grain"]
      cnt = gr["count"]
      tmp = f32[n]
      grains = []
      g = 0
      while g < cnt
        buf = f32[n]
        rs_grain_tex(rng_key(@seed, id60("grain:" + sk), g, P_GRAIN), @aw, @ah, buf, tmp)
        grains.push(buf)
        g += 1
      pl = [vig, grains]
      @planes[sk] = pl
    pl

  -> load_gp(st)
    gd = st["grade"]
    st_t = gd["shadow_tint"]
    hl_t = gd["highlight_tint"]
    bl = gd["bloom"]
    bt = bl["tint"]
    gr = st["grain"]
    @gp[0] = to_f(st_t[0])
    @gp[1] = to_f(st_t[1])
    @gp[2] = to_f(st_t[2])
    @gp[3] = to_f(hl_t[0])
    @gp[4] = to_f(hl_t[1])
    @gp[5] = to_f(hl_t[2])
    @gp[6] = to_f(gd["contrast_mix"])
    @gp[7] = to_f(gd["saturation"])
    @gp[8] = to_f(bt[0])
    @gp[9] = to_f(bt[1])
    @gp[10] = to_f(bt[2])
    @gp[11] = to_f(gd["lift"])
    @gp[12] = to_f(gd["gain"])
    @gp[13] = to_f(gr["base"])
    @gp[14] = to_f(gr["mid"])
    @gp[15] = to_f(bl["threshold"])
    to_f(bl["sigma"])

  -> rain_field(it)
    f = @fields["rain:" + it["id"]]
    if f == nil
      h2 = @ah * 2
      f = f32[@aw * h2]
      tmp = f32[@aw * h2]
      rs_rain_sheet(rng_key(@seed, item_key(it), 0, P_RAIN), @aw, h2, f, tmp)
      @fields["rain:" + it["id"]] = f
    f

  -> fog_field(it)
    f = @fields["fog:" + it["id"]]
    if f == nil
      fw = @aw * 2
      f = f32[fw * @ah]
      tmp = f32[fw * @ah]
      small = f64[160 * 40]
      rng_fill_uniform(rng_key(@seed, item_key(it), 0, P_FOG), 160 * 40, small)
      rs_upsample(small, 160, 40, fw, @ah, f)
      rs_box_rows(f, tmp, fw, @ah, 40)
      rs_box_cols(tmp, f, fw, @ah, 40)
      rs_box_rows(f, tmp, fw, @ah, 40)
      rs_box_cols(tmp, f, fw, @ah, 40)
      rs_box_rows(f, tmp, fw, @ah, 40)
      rs_box_cols(tmp, f, fw, @ah, 40)
      rs_normalize(f, fw * @ah)
      @fields["fog:" + it["id"]] = f
    f

  -> particle_table(it)
    t = @parts[it["id"]]
    if t == nil
      t = f64[240 * 5]
      rng_fill_uniform(rng_key(@seed, item_key(it), 0, P_PARTICLES), 240 * 5, t)
      @parts[it["id"]] = t
    t

  # ------------------------------------------------------------------------------------------ text

  # PIL anchor "lm" / "rm": the box's vertical middle between ascender and descender sits at y.
  -> text_mid(c, x, y, s, size, family, weight, col, anchor)
    m = c.measure_text(s, {size: size, family: family, weight: weight})
    base = y + (m[:ascent] - m[:descent]) / ~2.0
    c.text(x, base, s, {size: size, family: family, weight: weight, fill: col, anchor: anchor})

  -> draw_bars(c, bar, st)
    return nil if bar == nil
    bs = st["bars"]
    fam = bs["family"]
    wt = bs["weight"]
    place = dotted(bar["place"])
    text_mid(c, 64, 76, place, bs["place_size"], fam, wt, rgb([148, 158, 176]), "start") if place != ""
    lbl = dotted(bar["label"])
    col = status_color(lbl)
    gtxt = nil
    gap = 0
    if bar["ey"] != nil && bar["sy"] != nil
      gap = bar["sy"] - bar["ey"]
      gap = 0 if gap < 0
      gtxt = dotted(bar["src"]) + "   •   " + gap_text(gap)
    right_edge = ~1856.0
    right_edge = right_edge - c.text_width(gtxt, {size: bs["gap_size"], family: fam, weight: wt}) - ~48.0 if gtxt != nil
    if lbl != ""
      c.circle(~74.5, ~1012.5, ~7.5, {fill: rgb(col)})
      size = bs["label_size"]
      while c.text_width(lbl, {size: size, family: fam, weight: wt}) > right_edge - ~94.0 && size > 15
        size -= 1
      text_mid(c, 94, 1012, lbl, size, fam, wt, rgb([235, 230, 220]), "start")
    if gtxt != nil
      text_mid(c, 1856, 1000, gtxt, bs["gap_size"], fam, wt, rgb([195, 202, 215]), "end")
      bw = ~0.0
      if gap <= 300
        bw = gap * ~1.4
      else
        bw = ~420.0 + (gap - 300) * ~0.11
      bw = ~24.0 if bw < ~24.0
      bw = ~500.0 if bw > ~500.0
      x0 = 1856 - bw.to_i
      c.line(x0, ~1028.5, 1856, ~1028.5, {stroke: rgb(col), width: 3})
      c.circle(x0 + ~0.5, ~1028.5, ~4.5, {fill: rgb([239, 234, 225])})
      c.circle(~1856.5, ~1028.5, ~5.5, {fill: rgb(col)})
    nil

  # The letterbox of an item with its source bar, drawn once over black.
  -> bars_canvas(it, bar, st)
    c = @bars[it["id"]]
    if c == nil
      c = Canvas.new(@w, @h)
      c.clear("#000000")
      draw_bars(c, bar, st)
      c.data_pointer
      @bars[it["id"]] = c
    c

  -> put_letterbox(it, bar, st, layer_ptr)
    bc = bars_canvas(it, bar, st)
    src = bc.data_pointer
    rs_copy_rows(src, layer_ptr, @lstride, 0, @bar_y)
    rs_copy_rows(src, layer_ptr, @lstride, @bar_y + @ah, @h)

  -> draw_supers(layer, p, st, lt)
    sus = get(p, "supers", [])
    return nil if sus.size == 0
    ss = st["super"]
    cps = to_f(ss["cps_ms"]) / ~1000.0
    fade = to_f(ss["fade_ms"]) / ~1000.0
    sus.each ->(s)
      at = to_f(s[0]) / ~1000.0
      dur = to_f(s[1]) / ~1000.0
      ls = lt - at
      if ls >= ~0.0 && ls < dur
        text = s[2]
        nch = (ls / cps).floor.to_i + 1
        nch = text.size if nch > text.size
        alpha = ~1.0
        alpha = [~0.0, (dur - ls) / fade].max if ls >= dur - fade
        col = rgb_scaled([242, 215, 145], alpha)
        y = @bar_y + @ah - 66
        part = text.slice(0, nch)
        if alpha > ~0.25
          layer.text(88, y, part, {size: ss["size"], family: ss["family"], fill: col, stroke: "#000000", width: 8, linejoin: "round"})
        else
          layer.text(88, y, part, {size: ss["size"], family: ss["family"], fill: col})
    nil

  # ------------------------------------------------------------------------------------------ sources

  # render.py render_source(): a crop of zoom z around (cx, cy) (+ jitter in source pixels), resampled to the
  # active picture. Drawn as the whole image under a sub-pixel transform (a CoreGraphics crop rect would round to
  # whole source pixels and make slow moves step).
  -> draw_source(canvas, img, z, cx, cy, jx, jy, flip)
    iw = img.width + ~0.0
    ih = img.height + ~0.0
    ar = (@aw + ~0.0) / (@ah + ~0.0)
    bw = iw
    bh = iw / ar
    if bh > ih
      bh = ih
      bw = ih * ar
    z = ~1.012 if z < ~1.012
    cw = bw / z
    ch = bh / z
    x0 = cx * iw - cw / ~2.0 + jx
    y0 = cy * ih - ch / ~2.0 + jy
    x0 = [[x0, ~0.0].max, iw - cw].min
    y0 = [[y0, ~0.0].max, ih - ch].min
    s = (@aw + ~0.0) / cw
    if flip
      canvas.save
      canvas.translate(@aw, 0)
      canvas.scale_by(-1, 1)
    canvas.image(img, ~0.0 - x0 * s, ~0.0 - y0 * s, iw * s, ih * s, {fit: :fill, quality: :high})
    canvas.restore if flip
    nil

  # The triptych's tall panes (render.py pane_source): a pw x ph crop at zoom z around (cx, cy).
  -> draw_pane_source(canvas, img, pw, ph, z, cx, cy)
    iw = img.width + ~0.0
    ih = img.height + ~0.0
    bw = iw
    bh = iw * ph / pw
    if bh > ih
      bh = ih
      bw = ih * pw / ph
    z = ~1.01 if z < ~1.01
    cw = bw / z
    ch = bh / z
    x0 = [[cx * iw - cw / ~2.0, ~0.0].max, iw - cw].min
    y0 = [[cy * ih - ch / ~2.0, ~0.0].max, ih - ch].min
    s = (pw + ~0.0) / cw
    canvas.image(img, ~0.0 - x0 * s, ~0.0 - y0 * s, iw * s, ih * s, {fit: :fill, quality: :high})
    nil

  # ------------------------------------------------------------------------------------------ items

  -> render_item(it, k, layer, lptr)
    kind = it["kind"]
    if kind == "still" || kind == "clip"
      draw_still(it, k, layer, lptr)
    elsif kind == "frames" || kind == "program"
      draw_frames(it, k, layer, lptr)
    elsif kind == "card"
      draw_card(it, layer, lptr)
    elsif kind == "group"
      draw_group(it, k, layer, lptr)
    else
      rs_fill_rows(lptr, @lstride, @w, 0, @h, 0, 0, 0)
    nil

  -> draw_frames(it, k, layer, lptr)
    p = it["params"]
    cnt = p["count"]
    idx = k
    idx = 0 if idx < 0
    idx = cnt - 1 if idx > cnt - 1
    path = ""
    if it["kind"] == "program"
      path = seq_path(@proj.build + "/programs/" + p["source_sha"], "%05d.png", 0, idx)
    else
      path = asset_seq_path(p["src"], idx)
    img = seq_image(path)
    rs_fill_rows(lptr, @lstride, @w, 0, @h, 0, 0, 0) if img.width != @w || img.height != @h
    layer.image(img, 0, 0, @w, @h, {fit: :fill, quality: :high})
    layer.data_pointer
    nil

  -> draw_card(it, layer, lptr)
    c = @cards[it["recipe"]]
    if c == nil
      c = make_card(it)
      @cards[it["recipe"]] = c
    rs_copy_rows(c.data_pointer, lptr, @lstride, 0, @h)
    nil

  # render.py make_cards(): ink paper (a 1/4-size random field, up-sampled and blurred ~3 px) and spaced type.
  -> make_card(it)
    p = it["params"]
    lay = p["layout"]
    st = p["style"]
    c = Canvas.new(@w, @h)
    n = @w * @h
    paper = f32[n]
    tmp = f32[n]
    small = f64[(@w / 4) * (@h / 4)]
    rng_fill_uniform(rng_key(@seed, id60("card-paper"), get(st, "paper_seed", 3), P_PAPER), (@w / 4) * (@h / 4), small)
    rs_upsample(small, @w / 4, @h / 4, @w, @h, paper)
    rs_box_rows(paper, tmp, @w, @h, 3)
    rs_box_cols(tmp, paper, @w, @h, 3)
    rs_box_rows(paper, tmp, @w, @h, 3)
    rs_box_cols(tmp, paper, @w, @h, 3)
    rs_box_rows(paper, tmp, @w, @h, 2)
    rs_box_cols(tmp, paper, @w, @h, 2)
    rs_card_base(paper, @w, @h, c.data_pointer, c.stride)
    fam = get(st, "family", "Baskerville")
    cx = (@w + ~0.0) / ~2.0
    cy = (@h + ~0.0) / ~2.0
    gold = rgb([242, 193, 78])
    cream = rgb([236, 232, 225])
    muted = rgb([150, 160, 175])
    if lay["layout"] == "title"
      spaced(c, cx, cy - ~70.0, lay["kicker"], 26, fam, gold, 8)
      spaced(c, cx, cy + ~12.0, lay["title"], 66, fam, cream, 12)
      c.line(cx - ~140.0, cy + ~48.5, cx + ~140.0, cy + ~48.5, {stroke: gold, width: 2})
      spaced(c, cx, cy + ~104.0, lay["subtitle"], 28, fam, muted, 7)
    else
      rows = lay["rows"]
      y = cy - (rows.size - 1) * ~36.0
      rows.each ->(r)
        c.text(cx - ~28.0, y, r[0], {size: 24, family: fam, fill: muted, anchor: "end"})
        c.text(cx + ~28.0, y, r[1], {size: 32, family: fam, style: "italic", fill: cream, anchor: "start"})
        y += ~72.0
    c.data_pointer
    c

  # render.py draw_spaced: letter-spaced type centred on cx, baseline y (PIL drew it glyph by glyph, so the
  # width is the advances plus spacing between, not after, the glyphs).
  -> spaced(c, cx, y, s, size, fam, col, sp)
    tw = c.text_width(s, {size: size, family: fam, spacing: sp})
    total = tw - sp
    c.text(cx - total / ~2.0, y, s, {size: size, family: fam, fill: col, spacing: sp, anchor: "start"})

  -> draw_still(it, k, layer, lptr)
    p = it["params"]
    st = p["style"]
    lt = (k + ~0.0) / @fps
    dur = [to_f(p["dur_ms"]) / ~1000.0, ~0.5].max
    u = clamp01(lt / dur)
    cam = p["camera"]
    move = get(cam, "move", "push")
    foc = get(cam, "focus", [~0.5, ~0.45])
    fx = to_f(foc[0])
    fy = to_f(foc[1])
    flip = get(cam, "flip", false)
    ik = item_key(it)
    jk = rng_key(@seed, ik, k, P_JITTER)
    jit = to_f(get(st, "jitter_px", ~0.3))
    jx = rng_n(jk, 0) * jit
    jy = rng_n(jk, 1) * jit
    get(p, "shakes", []).each ->(sm)
      ds = lt - to_f(sm) / ~1000.0
      if ds >= ~0.0 && ds < ~0.65
        kk = (~1.0 - ds / ~0.65) * (~1.0 - ds / ~0.65)
        jx += Math.sin(ds * ~85.0) * ~14.0 * kk
        jy += Math.cos(ds * ~73.0) * ~9.0 * kk
    fxl = get(p, "fx", [])
    if fxl.include?("shake") && lt < ~0.6
      kk = (~1.0 - lt / ~0.6) * (~1.0 - lt / ~0.6)
      jx += Math.sin(lt * ~80.0) * ~10.0 * kk
      jy += Math.cos(lt * ~70.0) * ~7.0 * kk
    clip = p["clip"]
    wipe = p["wipe"]
    if clip != nil
      n = clip["count"]
      cfps = to_f(get(clip, "fps", 24))
      at = to_f(clip["at_ms"]) / ~1000.0
      avail = [dur - at, ~0.5].max
      speed = (n + ~0.0) / cfps / avail
      speed = to_f(clip["min_speed"]) if speed < to_f(clip["min_speed"])
      speed = to_f(clip["max_speed"]) if speed > to_f(clip["max_speed"])
      if lt >= at
        pos = (lt - at) * cfps * speed
        pos = (n - 1) + ~0.0 if pos > (n - 1) + ~0.0
        k0 = pos.floor.to_i
        k1 = [n - 1, k0 + 1].min
        wgt = pos - k0
        z = ~1.0 + ~0.02 * ease(clamp01((lt - at) / avail))
        draw_source(@act_a, seq_image(asset_seq_path(clip["src"], k0)), z, ~0.5, ~0.5, jx, jy, false)
        if get(clip, "blend", true) && wgt > ~0.02 && k1 != k0
          draw_source(@act_b, seq_image(asset_seq_path(clip["src"], k1)), z, ~0.5, ~0.5, jx, jy, false)
          rs_lerp2(@act_a.data_pointer, @act_b.data_pointer, @astride, @aw, @ah, wgt, @wb)
        else
          rs_load(@act_a.data_pointer, @astride, @aw, @ah, @wb)
      else
        z = ~1.0 + ~0.07 * (~1.0 - ease(clamp01(lt / [at, ~0.5].max)))
        draw_source(@act_a, still(p["src"]), z, ~0.5, ~0.5, jx, jy, false)
        xf = to_f(get(clip, "xf_in_ms", 500)) / ~1000.0
        if lt > at - xf
          a = smooth((lt - (at - xf)) / xf)
          draw_source(@act_b, seq_image(asset_seq_path(clip["src"], 0)), ~1.0, ~0.5, ~0.5, jx, jy, false)
          rs_lerp2(@act_a.data_pointer, @act_b.data_pointer, @astride, @aw, @ah, a, @wb)
        else
          rs_load(@act_a.data_pointer, @astride, @aw, @ah, @wb)
    elsif wipe != nil
      zc = camera_at(move, u, dur, fx, fy)
      draw_source(@act_a, still(p["src"]), zc[0], zc[1], zc[2], jx, jy, false)
      draw_source(@act_b, still(wipe["src"]), zc[0], zc[1], zc[2], jx, jy, false)
      t0 = to_f(wipe["at_ms"]) / ~1000.0
      pw = smooth((lt - t0) / (to_f(wipe["ms"]) / ~1000.0))
      pos = (~0.0 - ~80.0) + pw * (@aw + ~160.0)
      glow = 0
      glow = 1 if pw > ~0.0 && pw < ~1.0
      rs_wipe(@act_a.data_pointer, @act_b.data_pointer, @astride, @aw, @ah, pos, glow, @wb)
    else
      zc = camera_at(move, u, dur, fx, fy)
      draw_source(@act_a, still(p["src"]), zc[0], zc[1], zc[2], jx, jy, flip)
      rs_load(@act_a.data_pointer, @astride, @aw, @ah, @wb)
    nn = @aw * @ah * 3
    if fxl.include?("flicker")
      fl = ~1.0 - ~0.06 * (~0.5 + ~0.5 * Math.sin(lt * ~21.0 + Math.sin(lt * ~6.5) * ~3.0))
      fl = fl - ~0.14 if rng_bits(rng_key(@seed, ik, k, P_FLICKER), 0) % 97 < 3
      rs_scale(@wb, nn, fl)
    if fxl.include?("rain")
      h2 = @ah * 2
      off = (lt * ~1400.0).floor.to_i % h2
      rs_rain(@wb, @aw, @ah, rain_field(it), h2, off)
    if fxl.include?("fog")
      off = (lt * ~22.0).floor.to_i % @aw
      rs_fog(@wb, @aw, @ah, fog_field(it), @aw * 2, off)
    if fxl.include?("snow")
      rs_particles(@wb, @aw, @ah, particle_table(it), 240, lt, 1, @pbuf, @bbuf, @gk)
    if fxl.include?("dust") || fxl.include?("embers")
      rs_particles(@wb, @aw, @ah, particle_table(it), 110, lt, 0, @pbuf, @bbuf, @gk)
    rs_clip(@wb, nn)
    grade_into(st, it, k, 0, @aw, @ah, 0, 0, ~1.0, lptr, @ax0, @bar_y)
    put_letterbox(it, p["bar"], st, lptr)
    draw_supers(layer, p, st, lt)
    nil

  # Grade the working image (w x h, sampling vignette/grain from column vx0) into the layer at (ox, oy).
  -> grade_into(st, it, k, salt, w, h, vx0, fade_rows, fade_to, lptr, ox, oy)
    pl = planes(st)
    sigma = load_gp(st)
    gw = w / 8
    gh = h / 8
    rs_grade1(@wb, w, h, @lb, @grid, @gcnt, gw, gh, @gp[15])
    rs_blur_grid(@grid, @gtmp, gw, gh, sigma)
    gk = rng_key(@seed, item_key(it), k, P_GRAIN)
    grains = pl[1]
    gi = rng_bits(gk, salt * 3) % grains.size
    gi = gi + grains.size if gi < 0
    gox = rng_bits(gk, salt * 3 + 1) % @aw
    gox = gox + @aw if gox < 0
    goy = rng_bits(gk, salt * 3 + 2) % @ah
    goy = goy + @ah if goy < 0
    rs_grade2(@wb, @lb, w, h, @grid, gw, gh, @gp, pl[0], grains[gi], @aw, @ah, vx0, gox, goy, fade_rows, fade_to, ~1.0, lptr, @lstride, ox, oy)
    nil

  -> pane_canvas(pw, ph)
    key = pw.to_s + "x" + ph.to_s
    c = @panes[key]
    if c == nil
      c = Canvas.new(pw, ph)
      @panes[key] = c
    c

  # render.py render_triptych: three tall panes fading in on their phrases, each graded alone, with labels.
  -> draw_group(it, k, layer, lptr)
    p = it["params"]
    st = p["style"]
    lt = (k + ~0.0) / @fps
    dur = [to_f(p["dur_ms"]) / ~1000.0, ~0.5].max
    rs_fill_rows(lptr, @lstride, @w, 0, @h, 0, 0, 0)
    bs = st["bars"]
    kids = p["children"]
    ci = 0
    while ci < kids.size
      ch = kids[ci]
      pane = ch["pane"]
      pw = pane[2]
      ph = pane[3]
      t0 = ~0.0
      t0 = to_f(ch["at_ms"]) / ~1000.0 - ~0.4 if ch["at_ms"] != 0
      a = smooth((lt - t0) / ~0.8)
      if a > ~0.0
        pc = pane_canvas(pw, ph)
        z = ~1.03 + ~0.06 * ease(clamp01((lt - t0) / [dur - t0, ~1.0].max))
        draw_pane_source(pc, still(ch["src"]), pw, ph, z, ~0.5, ~0.42)
        rs_load(pc.data_pointer, pc.stride, pw, ph, @wb)
        grade_into_alpha(st, it, k, ci + 1, pw, ph, a, lptr, pane[0], @bar_y + pane[1])
        cdot = rgb_scaled([255, 138, 91], a)
        ctxt = rgb_scaled([238, 234, 225], a)
        layer.circle(pane[0] + ~24.5, @bar_y + ph - ~35.5, ~6.5, {fill: cdot})
        text_mid(layer, pane[0] + 40, @bar_y + ph - 36, ch["label"], bs["pane_size"], bs["family"], bs["weight"], ctxt, "start")
      ci += 1
    layer.data_pointer
    put_letterbox(it, p["bar"], st, lptr)
    nil

  -> grade_into_alpha(st, it, k, salt, w, h, alpha, lptr, ox, oy)
    pl = planes(st)
    sigma = load_gp(st)
    gw = w / 8
    gh = h / 8
    rs_grade1(@wb, w, h, @lb, @grid, @gcnt, gw, gh, @gp[15])
    rs_blur_grid(@grid, @gtmp, gw, gh, sigma)
    gk = rng_key(@seed, item_key(it), k, P_GRAIN)
    grains = pl[1]
    gi = rng_bits(gk, salt * 3) % grains.size
    gi = gi + grains.size if gi < 0
    gox = rng_bits(gk, salt * 3 + 1) % @aw
    gox = gox + @aw if gox < 0
    goy = rng_bits(gk, salt * 3 + 2) % @ah
    goy = goy + @ah if goy < 0
    rs_grade2(@wb, @lb, w, h, @grid, gw, gh, @gp, pl[0], grains[gi], @aw, @ah, 0, gox, goy, 96, ~0.2, alpha, lptr, @lstride, ox, oy)
    nil

  # ------------------------------------------------------------------------------------------ frame

  # Composite frame f into @out (RGB24, rows packed). Returns @out.
  -> frame_into(f)
    x = interval_at(f)
    ents = x[2]
    v1e = []
    fades = []
    ents.each ->(e)
      if e[1] == "V1"
        v1e.push(e)
      else
        fades.push(e)
    main = v1e[v1e.size - 1]
    it = @v1[main[0]]
    k = f - it["f0"]
    render_item(it, k, @layer0, @l0)
    role = main[2]
    n3 = @w * @h * 3
    if v1e.size == 2
      pe = v1e[0]
      pit = @v1[pe[0]]
      render_item(pit, f - pit["f0"], @layer1, @l1)
      nd = role.split(":")[1].to_i
      a = smooth((k + ~0.0) / (nd + ~0.0))
      rs_mix_rgb(@l1, @l0, @lstride, @w, @h, a, @out)
    else
      rs_copy_rgb(@l0, @lstride, @w, @h, @out)
      if role.starts_with?("fadein:")
        nd = role.split(":")[1].to_i
        q = (k + ~0.0) / (nd + ~0.0)
        rs_scale_rgb(@out, n3, q * Math.sqrt(q))
    fades.each ->(e)
      fit = @v4[e[0]]
      nd = fit["params"]["frames"]
      rem = (fit["f1"] - f + ~0.0) / (nd + ~0.0)
      pw = to_f(fit["params"]["power"])
      rs_scale_rgb(@out, n3, Math.exp(pw * Math.log(rem)))
    @frames_rendered += 1
    @out

  # The current @out as a PNG (through a canvas, so the file carries the sRGB chunk).
  -> write_png(path)
    c = Canvas.new(@w, @h)
    rs_rgb_to_canvas(@out, @w, @h, c.data_pointer, c.stride)
    c.write_png(path)
    c.close
    path

-> rs_rgb_to_canvas(src, w, h, dst, stride) (u8[] i64 i64 i64 i64) i64
  y = 0
  while y < h
    x = 0
    while x < w
      i = (y * w + x) * 3
      p = y * stride + x * 4
      raw_store_u8(dst, p, src[i])
      raw_store_u8(dst, p + 1, src[i + 1])
      raw_store_u8(dst, p + 2, src[i + 2])
      raw_store_u8(dst, p + 3, 255)
      x += 1
    y += 1
  0

# studio selftest: guards against a compiled-engine bug found here (2026-10-22): in a typed function,
# `v = (a[i] ## f64) * s` followed by a store to `a[i]` reads 0 when a is u8[] (f32[] is fine). Loading the
# element into an integer local first is correct; rs_scale_rgb does that.
-> st_u8_inplace_cast(out, n, s) (u8[] i64 f64) i64
  i = 0
  while i < n
    v = (out[i] ## f64) * s
    out[i] = Math.floor(v + ~0.5) ## i64
    i += 1
  0

-> selftest
  a = u8[2]
  a[0] = 200
  a[1] = 100
  rs_scale_rgb(a, 2, ~0.5)
  b = u8[2]
  b[0] = 200
  b[1] = 100
  st_u8_inplace_cast(b, 2, ~0.5)
  << "rs_scale_rgb 200/100 x0.5 -> " + a[0].to_s + "/" + a[1].to_s + " (want 100/50); direct cast form -> " + b[0].to_s + "/" + b[1].to_s + (b[0] == 100 ? " (compiler bug fixed)" : " (compiler bug present)")
  a[0] == 100 && a[1] == 50 ? 0 : 1
