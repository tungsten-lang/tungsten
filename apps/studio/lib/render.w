# studio/render — frame(f) = F(resolved timeline, assets, f).
#
# Binary-search the interval table, render each active item at its item-local frame into a layer canvas, and
# composite (dissolve, fade-in, the V4 fades) into packed RGB24. Nothing carries from one frame to the next except
# caches of pure precomputations keyed by their owners (decoded images, grain and vignette planes per style, the
# rain/fog/particle fields per item, the mattes and cards per item), so any worker renders any frame in any order
# with identical bits.
#
# The primitives are generic: a still under a camera move, a clip (frame sequences joined by crossfades, played
# against the item's time), a group of panes, a frame sequence, a program's frames, a card (background + overlay
# elements), black; dissolves, fades and wipes; a parameterised grade (grain, vignette, bloom); overlay elements on
# the matte and timed text over the picture (lib/overlay.w). Everything that makes a series look like itself (the
# grade's numbers, the camera curves, the bars, the supers, the cards) arrives as data in the episode's styles and
# items.

use base
use raster
use overlay
use grade

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

# One axis of a travelling move: its base (the centre, the focus, or the centre pulled toward the focus by a
# weight) plus a travel: "span" (s0 + s1 * dur, across e - 0.5) or "edge" (a fraction of the margin the zoom
# leaves, (1 - 1/z) / 2, across 2e - 1), times dir.
-> cam_axis(ax, f, z, e, dur)
  return ~0.5 if ax == nil
  b = get(ax, "base", "center")
  base = ~0.5
  if b == "focus"
    base = f
  elsif b != "center"
    base = ~0.5 + (f - ~0.5) * to_f(b)
  d = to_f(get(ax, "dir", 1))
  if ax["span"] != nil
    sp = ax["span"]
    span = to_f(sp[0]) + to_f(sp[1]) * dur
    return base + d * span * (e - ~0.5)
  if ax["edge"] != nil
    r = (~1.0 - ~1.0 / z) / ~2.0 * to_f(ax["edge"])
    return base + d * r * (~2.0 * e - ~1.0)
  base

# A camera move at progress u over a shot of dur seconds: [zoom, centre x, centre y]. The curves come from the
# style's "camera" table, one entry per move: zoom moves {amp: [base, per second, max], focus_k, reverse} drift
# toward the focus as they zoom; travelling moves {z: [z0, z1], x: axis, y: axis} (see cam_axis).
-> camera_at(cs, move, u, dur, fx, fy)
  die("the style has no camera table") if cs == nil
  m = cs[move]
  m = cs["static"] if m == nil
  die("no camera move " + move.to_s + " in the style") if m == nil
  e = ease(u)
  if m["amp"] != nil
    am = m["amp"]
    amp = to_f(am[0]) + to_f(am[1]) * dur
    amp = to_f(am[2]) if amp > to_f(am[2])
    z = ~1.0 + amp * e
    z = ~1.0 + amp * (~1.0 - e) if get(m, "reverse", false)
    k = (z - ~1.0) / [amp, ~0.000001].max
    fk = to_f(m["focus_k"])
    return [z, ~0.5 + (fx - ~0.5) * fk * k, ~0.5 + (fy - ~0.5) * fk * k]
  zz = m["z"]
  z = to_f(zz[0]) + to_f(zz[1]) * e
  [z, cam_axis(m["x"], fx, z, e, dur), cam_axis(m["y"], fy, z, e, dur)]

# Position k of a clip's sequence: its parts played in order, each seam a crossfade of xf frames (the outgoing
# part's last xf frames under the incoming part's first xf). Returns [[part, frame index, weight], ...].
-> seq_len(parts, xf)
  n = 0
  parts.each ->(pt)
    n += pt["count"]
  n - xf * (parts.size - 1)

-> seq_entry(parts, xf, k)
  last = parts.size - 1
  i = 0
  while i <= last
    pt = parts[i]
    st = 0
    st = xf if i > 0
    en = pt["count"]
    en = pt["count"] - xf if i < last
    solo = en - st
    return [[i, pt["first"] + st + k, ~1.0]] if k < solo
    k -= solo
    if i < last
      if k < xf
        w = (k + 1 + ~0.0) / (xf + 1 + ~0.0)
        return [[i, pt["first"] + pt["count"] - xf + k, ~1.0 - w], [i + 1, parts[i + 1]["first"] + k, w]]
      k -= xf
    i += 1
  lp = parts[last]
  [[last, lp["first"] + lp["count"] - 1, ~1.0]]

-> rgb(c)
  [(c[0] + ~0.0) / ~255.0, (c[1] + ~0.0) / ~255.0, (c[2] + ~0.0) / ~255.0]

+ Engine
  ro :out, :w, :h, :frames_rendered

  -> new(@proj, @r)
    @w = @r["w"]
    @h = @r["h"]
    @num = @r["rate"][0]
    @den = @r["rate"][1]
    @fps = (@num + ~0.0) / (@den + ~0.0)
    @seed = @r["seed"]
    act = [0, 0, @w, @h]
    pic = @proj.cut_cfg(@r["cut"])["picture"]
    act = pic["active"] if pic != nil && pic["active"] != nil
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
    # the per-pixel look (lib/grade.w): the CPU reference or the Metal kernels, as GRADE says
    @fx = CpuGrade.new(@aw, @ah, @wb, @lb, @grid, @gcnt, @gtmp, @gp, @pbuf, @bbuf, @gk)
    @fx = MetalGrade.new(@aw, @ah, @gk, @gp) if GRADE["id"] != "cpu"
    @planes = {}
    @fields = {}
    @parts = {}
    @mattes = {}
    @cards = {}
    @panes = {}
    @plates = {}
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
    @mattes.values.each ->(c)
      c.close
    @cards.values.each ->(c)
      c.close
    @panes.values.each ->(c)
      c.close
    @plates.values.each ->(c)
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

  -> overlay_image(key)
    still(key)

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

  -> asset_seq_path(key, idx)
    a = @proj.ep["assets"][key]
    seq_path(@proj.asset_path(key), a["pattern"], a["first"], idx)

  # ------------------------------------------------------------------------------------------ planes

  # Grain (count planes) and vignette for a style. The grain's random field is keyed by the grain's own
  # parameters, so an unrelated change to the style (a camera curve) leaves it alone.
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
      var = to_f(get(gr, "blur_var", ~0.49))
      gkey = id60("grain:" + hash_of(gr))
      tmp = f32[n]
      grains = []
      g = 0
      while g < cnt
        buf = f32[n]
        rs_grain_tex(rng_key(@seed, gkey, g, P_GRAIN), @aw, @ah, var, buf, tmp)
        grains.push(buf)
        g += 1
      pl = [vig, grains, sk]
      @planes[sk] = pl
    pl

  -> load_gp(st)
    gd = st["grade"]
    st_t = gd["shadow_tint"]
    hl_t = gd["highlight_tint"]
    bl = gd["bloom"]
    die("the grade's bloom grid is fixed at 1/8 size (bloom.down = 8)") if get(bl, "down", 8) != 8
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

  # ------------------------------------------------------------------------------------------ matte

  # The full frame around the active picture (the letterbox) with its static overlay elements, drawn once over
  # the matte colour.
  -> matte_canvas(it, matte)
    c = @mattes[it["id"]]
    if c == nil
      c = Canvas.new(@w, @h)
      c.clear(get(matte, "fill", "#000000"))
      ov_draw(c, get(matte, "elements", nil), ~1.0, self) if matte != nil
      c.data_pointer
      @mattes[it["id"]] = c
    c

  -> put_matte(it, matte, layer_ptr)
    return nil if @bar_y == 0 && @ah == @h
    src = matte_canvas(it, matte).data_pointer
    rs_copy_rows(src, layer_ptr, @lstride, 0, @bar_y)
    rs_copy_rows(src, layer_ptr, @lstride, @bar_y + @ah, @h)

  # ------------------------------------------------------------------------------------------ sources

  # A crop of zoom z around (cx, cy) (+ jitter in source pixels), resampled to the active picture. Drawn as the
  # whole image under a sub-pixel transform (a CoreGraphics crop rect would round to whole source pixels and make
  # slow moves step).
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

  # A pw x ph crop at zoom z around (cx, cy), framed for the pane's own aspect (tall triptych panes).
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
    idx = k + get(p, "in", 0)
    idx = 0 if idx < 0
    idx = cnt - 1 if idx > cnt - 1
    path = ""
    if it["kind"] == "program"
      path = @proj.program_frame(p, idx)
    else
      path = asset_seq_path(p["src"], idx)
    img = seq_image(path)
    rs_fill_rows(lptr, @lstride, @w, 0, @h, 0, 0, 0) if img.width != @w || img.height != @h
    layer.image(img, 0, 0, @w, @h, {fit: :fill, quality: :high})
    layer.data_pointer
    rp = p["replace"]
    if rp != nil
      m = plate_canvas(rp["match"])
      wc = plate_canvas(rp["with"])
      rs_replace_px(lptr, @lstride, m.data_pointer, m.stride, wc.data_pointer, wc.stride, @w, @h)
    nil

  # A full-frame image as a canvas, drawn once (the replace plates of frame sequences).
  -> plate_canvas(key)
    c = @plates[key]
    if c == nil
      c = Canvas.new(@w, @h)
      c.clear("#000000")
      img = Canvas.load_image(@proj.asset_path(key))
      c.image(img, 0, 0, @w, @h, {fit: :fill})
      img.release
      c.data_pointer
      @plates[key] = c
    c

  -> draw_card(it, layer, lptr)
    c = @cards[it["recipe"]]
    if c == nil
      c = make_card(it)
      @cards[it["recipe"]] = c
    rs_copy_rows(c.data_pointer, lptr, @lstride, 0, @h)
    nil

  # A card: a background (a colour, optionally with an ink-paper texture: a 1/down-size random field, up-sampled,
  # box-blurred by the listed radii, tinted and added) and overlay elements.
  -> make_card(it)
    p = it["params"]
    bg = p["bg"]
    c = Canvas.new(@w, @h)
    col = get(bg, "color", [~0.0, ~0.0, ~0.0])
    pp = bg["paper"]
    if pp != nil
      n = @w * @h
      paper = f32[n]
      tmp = f32[n]
      dn = get(pp, "down", 4)
      sw = @w / dn
      sh = @h / dn
      small = f64[sw * sh]
      rng_fill_uniform(rng_key(@seed, id60(get(pp, "key", "card-paper")), get(pp, "seed", 3), P_PAPER), sw * sh, small)
      rs_upsample(small, sw, sh, @w, @h, paper)
      get(pp, "blur", []).each ->(r)
        rs_box_rows(paper, tmp, @w, @h, r)
        rs_box_cols(tmp, paper, @w, @h, r)
      tint = pp["tint"]
      rs_card_base(paper, @w, @h, c.data_pointer, c.stride, to_f(col[0]), to_f(col[1]), to_f(col[2]), to_f(pp["amount"]), to_f(tint[0]), to_f(tint[1]), to_f(tint[2]))
    else
      c.clear([to_f(col[0]), to_f(col[1]), to_f(col[2])])
    ov_draw(c, p["elements"], ~1.0, self)
    c.data_pointer
    c

  # Jitter (style jitter_px, a counter-based normal per frame) plus the style's shakes: "hit" after each shake
  # cue near the item, "open" at the item's start when its fx list has "shake".
  -> jitter(it, st, p, k, lt)
    jk = rng_key(@seed, item_key(it), k, P_JITTER)
    jit = to_f(get(st, "jitter_px", ~0.3))
    jx = rng_n(jk, 0) * jit
    jy = rng_n(jk, 1) * jit
    sk = get(st, "shake", nil)
    if sk != nil
      h = sk["hit"]
      if h != nil
        hs = to_f(h["s"])
        get(p, "shakes", []).each ->(sm)
          ds = lt - to_f(sm) / ~1000.0
          if ds >= ~0.0 && ds < hs
            kk = (~1.0 - ds / hs) * (~1.0 - ds / hs)
            jx += Math.sin(ds * to_f(h["fx"])) * to_f(h["ax"]) * kk
            jy += Math.cos(ds * to_f(h["fy"])) * to_f(h["ay"]) * kk
      o = sk["open"]
      if o != nil && get(p, "fx", []).include?("shake")
        os = to_f(o["s"])
        if lt < os
          kk = (~1.0 - lt / os) * (~1.0 - lt / os)
          jx += Math.sin(lt * to_f(o["fx"])) * to_f(o["ax"]) * kk
          jy += Math.cos(lt * to_f(o["fy"])) * to_f(o["ay"]) * kk
    [jx, jy]

  # Draw clip sequence entries (lists of [part, frame, weight]) blended, and load them into the grade module.
  -> clip_frame_path(clip, e)
    asset_seq_path(clip["parts"][e[0]]["src"], e[1])

  -> load_clip_mix(clip, ws, z, jx, jy)
    if ws.size == 1
      draw_source(@act_a, seq_image(clip_frame_path(clip, ws[0])), z, ~0.5, ~0.5, jx, jy, false)
      @fx.load(@act_a.data_pointer, @astride, @aw, @ah)
      return nil
    if ws.size == 2
      draw_source(@act_a, seq_image(clip_frame_path(clip, ws[0])), z, ~0.5, ~0.5, jx, jy, false)
      draw_source(@act_b, seq_image(clip_frame_path(clip, ws[1])), z, ~0.5, ~0.5, jx, jy, false)
      @fx.lerp2(@act_a.data_pointer, @act_b.data_pointer, @astride, @aw, @ah, to_f(ws[1][2]))
      return nil
    # three or four frames (a crossfaded seam blended with the next position): each drawn over the running mix at
    # its share of the weight so far, so the canvas holds the weighted average
    acc = ~0.0
    ws.each ->(e)
      w = to_f(e[2])
      if w > ~0.0
        acc += w
        draw_source_alpha(@act_a, seq_image(clip_frame_path(clip, e)), z, jx, jy, w / acc)
    @fx.load(@act_a.data_pointer, @astride, @aw, @ah)
    nil

  # draw_source at an opacity (the camera of a clip: centred, no flip)
  -> draw_source_alpha(canvas, img, z, jx, jy, alpha)
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
    x0 = [[~0.5 * iw - cw / ~2.0 + jx, ~0.0].max, iw - cw].min
    y0 = [[~0.5 * ih - ch / ~2.0 + jy, ~0.0].max, ih - ch].min
    s = (@aw + ~0.0) / cw
    canvas.image(img, ~0.0 - x0 * s, ~0.0 - y0 * s, iw * s, ih * s, {fit: :fill, quality: :high, opacity: alpha})
    nil

  # The weights of position pos of the sequence: entry k0 alone, or k0 and k0 + 1 mixed by the fraction.
  -> clip_weights(clip, n, k0, k1, wgt, blend)
    xf = clip["xf"]
    a = seq_entry(clip["parts"], xf, k0)
    return a if !(blend && wgt > ~0.02 && k1 != k0)
    b = seq_entry(clip["parts"], xf, k1)
    if a.size == 1 && b.size == 1
      # two plain frames: the pair blend (lerp a -> b by wgt)
      return [[a[0][0], a[0][1], ~1.0 - wgt], [b[0][0], b[0][1], wgt]]
    out = []
    a.each ->(e)
      out.push([e[0], e[1], e[2] * (~1.0 - wgt)])
    b.each ->(e)
      out.push([e[0], e[1], e[2] * wgt])
    out

  -> draw_clip(it, p, clip, lt, dur, jx, jy)
    n = seq_len(clip["parts"], clip["xf"])
    cfps = to_f(get(clip, "fps", 24))
    at = to_f(clip["at_ms"]) / ~1000.0
    avail = [dur - at + to_f(get(clip, "add_ms", 0)) / ~1000.0, ~0.5].max
    sp = clip["speed"]
    speed = (n + ~0.0) / cfps / avail
    speed = to_f(sp[0]) if speed < to_f(sp[0])
    speed = to_f(sp[1]) if speed > to_f(sp[1])
    if lt >= at
      pos = (lt - at) * cfps * speed
      hold = clip["hold"]
      if hold != nil && pos >= (n - 1) + ~0.0
        # past its last frame: hold it, pushing in slowly
        t_end = (n - 1 + ~0.0) / cfps / speed
        v = clamp01((lt - at - t_end) / [avail - t_end, ~0.5].max)
        ec = ease(clamp01((n - 1 + ~0.0) / cfps / speed / avail))
        z = to_f(hold["z0"]) + to_f(hold["dz"]) * ec + to_f(hold["push"]) * (~0.5 - ~0.5 * Math.cos(~3.141592653589793 * v))
        load_clip_mix(clip, seq_entry(clip["parts"], clip["xf"], n - 1), z, jx, jy)
        return nil
      pos = (n - 1) + ~0.0 if pos > (n - 1) + ~0.0
      k0 = pos.floor.to_i
      k1 = [n - 1, k0 + 1].min
      wgt = pos - k0
      if get(clip, "nearest", false)
        # the nearest source frame, never a blend of two
        k0 = (pos + ~0.5).floor.to_i
        k0 = n - 1 if k0 > n - 1
        k1 = k0
        wgt = ~0.0
      zm = clip["zoom"]
      e = ease(clamp01((lt - at) / avail))
      z = to_f(zm["z0"]) + to_f(zm["dz"]) * e
      z = to_f(zm["z0"]) + to_f(zm["dz"]) * (~1.0 - e) if get(zm, "reverse", false)
      load_clip_mix(clip, clip_weights(clip, n, k0, k1, wgt, get(clip, "blend", true)), z, jx, jy)
      return nil
    # before the clip starts: the still, pulling back so that it lands on the clip's first frame at `at`
    pre = get(clip, "pre", {})
    z = ~1.0 + to_f(get(pre, "zoom", ~0.0)) * (~1.0 - ease(clamp01(lt / [at, ~0.5].max)))
    draw_source(@act_a, still(p["src"]), z, ~0.5, ~0.5, jx, jy, false)
    xf = to_f(get(pre, "xf_ms", 500)) / ~1000.0
    if lt > at - xf
      a = smooth((lt - (at - xf)) / xf)
      draw_source(@act_b, seq_image(clip_frame_path(clip, seq_entry(clip["parts"], clip["xf"], 0)[0])), ~1.0, ~0.5, ~0.5, jx, jy, false)
      @fx.lerp2(@act_a.data_pointer, @act_b.data_pointer, @astride, @aw, @ah, a)
    else
      @fx.load(@act_a.data_pointer, @astride, @aw, @ah)
    nil

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
    jj = jitter(it, st, p, k, lt)
    jx = jj[0]
    jy = jj[1]
    fxl = get(p, "fx", [])
    clip = p["clip"]
    wipe = p["wipe"]
    if clip != nil
      draw_clip(it, p, clip, lt, dur, jx, jy)
    elsif wipe != nil
      zc = camera_at(st["camera"], move, u, dur, fx, fy)
      draw_source(@act_a, still(p["src"]), zc[0], zc[1], zc[2], jx, jy, false)
      draw_source(@act_b, still(wipe["src"]), zc[0], zc[1], zc[2], jx, jy, false)
      t0 = to_f(wipe["at_ms"]) / ~1000.0
      pw = smooth((lt - t0) / (to_f(wipe["ms"]) / ~1000.0))
      pos = (~0.0 - ~80.0) + pw * (@aw + ~160.0)
      glow = 0
      glow = 1 if pw > ~0.0 && pw < ~1.0
      @fx.wipe(@act_a.data_pointer, @act_b.data_pointer, @astride, @aw, @ah, pos, glow)
    else
      zc = camera_at(st["camera"], move, u, dur, fx, fy)
      draw_source(@act_a, still(p["src"]), zc[0], zc[1], zc[2], jx, jy, flip)
      @fx.load(@act_a.data_pointer, @astride, @aw, @ah)
    nn = @aw * @ah * 3
    if fxl.include?("flicker")
      fl = ~1.0 - ~0.06 * (~0.5 + ~0.5 * Math.sin(lt * ~21.0 + Math.sin(lt * ~6.5) * ~3.0))
      fl = fl - ~0.14 if rng_bits(rng_key(@seed, ik, k, P_FLICKER), 0) % 97 < 3
      @fx.scale(nn, fl)
    if fxl.include?("rain")
      h2 = @ah * 2
      off = (lt * ~1400.0).floor.to_i % h2
      @fx.rain(rain_field(it), "rain:" + it["id"], h2, off)
    if fxl.include?("fog")
      off = (lt * ~22.0).floor.to_i % @aw
      @fx.fog(fog_field(it), "fog:" + it["id"], @aw * 2, off)
    if fxl.include?("snow")
      @fx.particles(particle_table(it), 240, lt, 1)
    if fxl.include?("dust") || fxl.include?("embers")
      @fx.particles(particle_table(it), 110, lt, 0)
    @fx.clip(nn)
    grade_into(st, it, k, 0, @aw, @ah, 0, 0, ~1.0, lptr, @ax0, @bar_y)
    put_matte(it, p["matte"], lptr)
    ov_draw_timed(layer, p["overlays"], lt)
    nil

  # Grade the working image (w x h, sampling vignette/grain from column vx0) into the layer at (ox, oy).
  -> grade_into(st, it, k, salt, w, h, vx0, fade_rows, fade_to, lptr, ox, oy)
    pl = planes(st)
    sigma = load_gp(st)
    gk = rng_key(@seed, item_key(it), k, P_GRAIN)
    grains = pl[1]
    gi = rng_bits(gk, salt * 3) % grains.size
    gi = gi + grains.size if gi < 0
    gox = rng_bits(gk, salt * 3 + 1) % @aw
    gox = gox + @aw if gox < 0
    goy = rng_bits(gk, salt * 3 + 2) % @ah
    goy = goy + @ah if goy < 0
    @fx.grade(pl, gi, gox, goy, sigma, w, h, vx0, fade_rows, fade_to, ~1.0, lptr, @lstride, ox, oy)
    nil

  -> pane_canvas(pw, ph)
    key = pw.to_s + "x" + ph.to_s
    c = @panes[key]
    if c == nil
      c = Canvas.new(pw, ph)
      @panes[key] = c
    c

  # A group of panes (the triptych): each pane fades in at its phrase (less a lead), its source framed for the
  # pane ("pane") or for the whole picture with a window cut out of it ("picture"), graded alone with its bottom
  # rows shaded, and its overlay elements (a dot, a label) drawn at the pane's alpha.
  -> draw_group(it, k, layer, lptr)
    p = it["params"]
    st = p["style"]
    lt = (k + ~0.0) / @fps
    dur = [to_f(p["dur_ms"]) / ~1000.0, ~0.5].max
    rs_fill_rows(lptr, @lstride, @w, 0, @h, 0, 0, 0)
    kids = p["panes"]
    ci = 0
    while ci < kids.size
      ch = kids[ci]
      pane = ch["pane"]
      pw = pane[2]
      ph = pane[3]
      t0 = ~0.0
      t0 = to_f(ch["at_ms"]) / ~1000.0 - to_f(get(ch, "lead_ms", 0)) / ~1000.0 if ch["at_ms"] != 0
      a = smooth((lt - t0) / (to_f(get(ch, "fade_ms", 800)) / ~1000.0))
      if a > ~0.0
        zm = ch["zoom"]
        u = clamp01(lt / dur)
        u = clamp01((lt - t0) / [dur - t0, ~1.0].max) if get(zm, "basis", "t0") == "t0"
        z = to_f(zm["z0"]) + to_f(zm["dz"]) * ease(u)
        foc = get(ch, "focus", [~0.5, ~0.45])
        fr = get(ch, "frame", {})
        vx0 = 0
        pc = pane_canvas(pw, ph)
        if get(fr, "mode", "pane") == "picture"
          vx0 = fr["x"]
          draw_source(@act_a, still(ch["src"]), z, to_f(foc[0]), to_f(foc[1]), ~0.0, ~0.0, false)
          rs_copy_window(@act_a.data_pointer, @astride, vx0, pc.data_pointer, pc.stride, pw, ph)
        else
          draw_pane_source(pc, still(ch["src"]), pw, ph, z, to_f(foc[0]), to_f(foc[1]))
        @fx.load(pc.data_pointer, pc.stride, pw, ph)
        sh = get(ch, "shade", {"rows" => 0, "to" => ~1.0})
        grade_into_alpha(st, it, k, ci + 1, pw, ph, a, vx0, sh["rows"], to_f(sh["to"]), lptr, pane[0], @bar_y + pane[1])
        ov_draw(layer, ch["elements"], a, self)
      ci += 1
    layer.data_pointer
    put_matte(it, p["matte"], lptr)
    nil

  -> grade_into_alpha(st, it, k, salt, w, h, alpha, vx0, fade_rows, fade_to, lptr, ox, oy)
    pl = planes(st)
    sigma = load_gp(st)
    gk = rng_key(@seed, item_key(it), k, P_GRAIN)
    grains = pl[1]
    gi = rng_bits(gk, salt * 3) % grains.size
    gi = gi + grains.size if gi < 0
    gox = rng_bits(gk, salt * 3 + 1) % @aw
    gox = gox + @aw if gox < 0
    goy = rng_bits(gk, salt * 3 + 2) % @ah
    goy = goy + @ah if goy < 0
    @fx.grade(pl, gi, gox, goy, sigma, w, h, vx0, fade_rows, fade_to, alpha, lptr, @lstride, ox, oy)
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

# Where the layer's pixel equals the match plate's exactly (R, G, B), take the with plate's pixel.
-> rs_replace_px(dst, ds, mp, ms, wp, ws, w, h) (i64 i64 i64 i64 i64 i64 i64 i64) i64
  n = 0
  y = 0
  while y < h
    a = dst + y * ds
    b = mp + y * ms
    c = wp + y * ws
    x = 0
    while x < w * 4
      if raw_load_u8(a, x) == raw_load_u8(b, x) && raw_load_u8(a, x + 1) == raw_load_u8(b, x + 1) && raw_load_u8(a, x + 2) == raw_load_u8(b, x + 2)
        raw_store_u8(a, x, raw_load_u8(c, x))
        raw_store_u8(a, x + 1, raw_load_u8(c, x + 1))
        raw_store_u8(a, x + 2, raw_load_u8(c, x + 2))
        n += 1
      x += 4
    y += 1
  n

# Path of frame idx of a sequence: pattern "%05d.png" (digits and extension), numbered from first.
-> seq_path(dir, pattern, first, idx)
  digits = pattern.slice(2, 1).to_i
  ext = pattern.slice(4, pattern.size - 4)
  dir + "/" + pad_int(first + idx, digits) + ext

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
