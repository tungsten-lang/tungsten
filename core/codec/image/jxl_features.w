# core/codec/image/jxl_features — JPEG XL patches, splines, noise, restoration filters
# (Gaborish, EPF) and upsampling. (in progress)

use jxl_ans

# Patch dictionary → [[ref, rx0, ry0, w, h, [[x, y, blends], …]], …]
# where blends = [[mode, alpha, clamp] for colour, then each extra channel].
-> jxr_read_patches(d, br)
  src = d.src
  m = d.m
  f = d.f
  nec = m.ec.size
  cs = jx_read_code(src, br, 10)
  es = jx_stream(src, br, cs)
  win = jx_window(cs)
  nref = jx_decode(src, br, cs, es, win, 0, 0)
  jxl_fail("too many patches") if nref > 1024 + f.fw * f.fh / 4
  out = []
  i = 0
  while i < nref
    ref = jx_decode(src, br, cs, es, win, 1, 0)
    rx0 = jx_decode(src, br, cs, es, win, 3, 0)
    ry0 = jx_decode(src, br, cs, es, win, 3, 0)
    pw = jx_decode(src, br, cs, es, win, 2, 0) + 1
    ph = jx_decode(src, br, cs, es, win, 2, 0) + 1
    cnt = jx_decode(src, br, cs, es, win, 7, 0) + 1
    jxl_fail("bad patch reference") if ref > 3 || d.refs[ref] == nil
    poss = []
    px = 0
    py = 0
    k = 0
    while k < cnt
      if k == 0
        px = jx_decode(src, br, cs, es, win, 4, 0)
        py = jx_decode(src, br, cs, es, win, 4, 0)
      else
        px += jx_unpack_signed(jx_decode(src, br, cs, es, win, 6, 0))
        py += jx_unpack_signed(jx_decode(src, br, cs, es, win, 6, 0))
      blends = []
      j = 0
      while j < nec + 1
        mode = jx_decode(src, br, cs, es, win, 5, 0)
        jxl_fail("patch blend mode") if mode > 7
        alpha = 0
        clamp = 0
        uses_alpha = mode >= 4
        alpha = jx_decode(src, br, cs, es, win, 8, 0) if uses_alpha && nec > 1
        clamp = jx_decode(src, br, cs, es, win, 9, 0) if uses_alpha || mode == 3
        blends.push([mode, alpha, clamp])
        j += 1
      poss.push([px, py, blends])
      k += 1
    out.push([ref, rx0, ry0, pw, ph, poss])
    i += 1
  jx_finish(src, br, cs, es)
  out
# Splines → [quant_adjust, [[start_x, start_y, ctrl (deltas boxed), dct(4x32 boxed)], …]]
-> jxr_read_splines(d, br)
  src = d.src
  f = d.f
  cs = jx_read_code(src, br, 6)
  es = jx_stream(src, br, cs)
  win = jx_window(cs)
  nsp = jx_decode(src, br, cs, es, win, 2, 0) + 1
  maxcp = f.fw * f.fh / 2
  maxcp = 1048576 if maxcp > 1048576
  jxl_fail("too many splines") if nsp > maxcp
  starts = []
  lx = 0
  ly = 0
  i = 0
  while i < nsp
    dx = jx_decode(src, br, cs, es, win, 1, 0)
    dy = jx_decode(src, br, cs, es, win, 1, 0)
    if i > 0
      lx = jx_unpack_signed(dx) + lx
      ly = jx_unpack_signed(dy) + ly
    else
      lx = dx
      ly = dy
    starts.push([lx, ly])
    i += 1
  qa = jx_unpack_signed(jx_decode(src, br, cs, es, win, 0, 0))
  out = []
  total = nsp
  i = 0
  while i < nsp
    ncp = jx_decode(src, br, cs, es, win, 3, 0)
    total += ncp
    jxl_fail("too many spline points") if total > maxcp
    ctrl = []
    k = 0
    while k < ncp
      ax = jx_unpack_signed(jx_decode(src, br, cs, es, win, 4, 0))
      ay = jx_unpack_signed(jx_decode(src, br, cs, es, win, 4, 0))
      ctrl.push([ax, ay])
      k += 1
    dcts = []
    c = 0
    while c < 4
      v = []
      k = 0
      while k < 32
        v.push(jx_unpack_signed(jx_decode(src, br, cs, es, win, 5, 0)))
        k += 1
      dcts.push(v)
      c += 1
    out.push([starts[i][0], starts[i][1], ctrl, dcts])
    i += 1
  jx_finish(src, br, cs, es)
  [qa, out]
-> jxr_read_noise(src, br)
  lut = f64[8]
  k = 0
  while k < 8
    lut[k] = jb_u(src, br, 10) / ~1024.0
    k += 1
  lut
-> jxf_patches(d, pl, ec)
  m = d.m
  nec = ec.size
  d.patches.each ->(rp)
    refc = d.refs[rp[0]]
    rw = m.width
    rp[5].each ->(pos)
      fw = pl[0][1]
      fh = pl[0][2]
      w = rp[3]
      h = rp[4]
      w = fw - pos[0] if pos[0] + w > fw
      h = fh - pos[1] if pos[1] + h > fh
      if w > 0 && h > 0
        bgs = []
        fgs = []
        k = 0
        while k < 3 + nec
          plane = nil
          pwid = 0
          if k < 3
            plane = pl[k][0]
            pwid = pl[k][1]
          else
            plane = ec[k - 3][0]
            pwid = ec[k - 3][1]
          b = f64[w * h]
          jxf_get_rect(b, plane, pwid, pos[0], pos[1], w, h)
          bgs.push(b)
          g = f64[w * h]
          jxf_get_rect(g, refc[k], rw, rp[1], rp[2], w, h)
          fgs.push(g)
          k += 1
        outs = jxf_perform_blending(bgs, fgs, pos[2], m, w * h)
        k = 0
        while k < 3 + nec
          if k < 3
            jxf_put_rect(pl[k][0], pl[k][1], pos[0], pos[1], w, h, outs[k])
          else
            jxf_put_rect(ec[k - 3][0], ec[k - 3][1], pos[0], pos[1], w, h, outs[k])
          k += 1
  0

-> jxf_get_rect(d, s, sw, x0, y0, w, h) (f64[] f64[] i64 i64 i64 i64 i64) i64
  y = 0 ## i64
  while y < h
    x = 0 ## i64
    while x < w
      d[y * w + x] = s[(y0 + y) * sw + x0 + x]
      x += 1
    y += 1
  0

-> jxf_put_rect(d, dw, x0, y0, w, h, s) (f64[] i64 i64 i64 i64 i64 f64[]) i64
  y = 0 ## i64
  while y < h
    x = 0 ## i64
    while x < w
      d[(y0 + y) * dw + x0 + x] = s[y * w + x]
      x += 1
    y += 1
  0

-> jxf_clamp01(v) (f64) f64
  return ~0.0 if v < ~0.0
  return ~1.0 if v > ~1.0
  v

-> jxf_op_add(o, a, b, n) (f64[] f64[] f64[] i64) i64
  i = 0 ## i64
  while i < n
    o[i] = a[i] + b[i]
    i += 1
  0

-> jxf_op_mul(o, bg, fg, n, cl) (f64[] f64[] f64[] i64 i64) i64
  i = 0 ## i64
  while i < n
    v = fg[i]
    v = jxf_clamp01(v) if cl == 1
    o[i] = bg[i] * v
    i += 1
  0

# PerformAlphaBlending (single channel); same == 1 when the channel is the alpha.
-> jxf_op_ablend(o, bg, bga, fg, fga, n, premul, cl, same) (f64[] f64[] f64[] f64[] f64[] i64 i64 i64 i64) i64
  i = 0 ## i64
  while i < n
    fa = fga[i]
    fa = jxf_clamp01(fa) if cl == 1
    if same == 1
      o[i] = ~1.0 - (~1.0 - fa) * (~1.0 - bga[i])
    elsif premul == 1
      o[i] = fg[i] + bg[i] * (~1.0 - fa)
    else
      na = ~1.0 - (~1.0 - fa) * (~1.0 - bga[i])
      r = ~0.0
      r = ~1.0 / na if na > ~0.0
      o[i] = (fg[i] * fa + bg[i] * bga[i] * (~1.0 - fa)) * r
    i += 1
  0

-> jxf_op_awadd(o, bg, fg, fga, n, cl, same) (f64[] f64[] f64[] f64[] i64 i64 i64) i64
  i = 0 ## i64
  while i < n
    if same == 1
      o[i] = bg[i]
    else
      a = fga[i]
      a = jxf_clamp01(a) if cl == 1
      o[i] = bg[i] + fg[i] * a
    i += 1
  0

# libjxl PerformBlending on flat region arrays; infos [[mode, alpha, clamp], …]
# with patch blend modes (0 none, 1 replace, 2 add, 3 mul, 4/5 blend
# above/below, 6/7 alpha-weighted add above/below).
-> jxf_perform_blending(bg, fg, infos, m, n)
  nec = m.ec.size
  has_alpha = false
  m.ec.each ->(e)
    has_alpha = true if e[:type] == 0
  tmp = []
  k = 0
  while k < 3 + nec
    tmp.push(f64[n])
    k += 1
  i = 0
  while i < nec
    inf = infos[1 + i]
    mode = inf[0]
    a = inf[1]
    cl = inf[2]
    o = tmp[3 + i]
    if mode == 2
      jxf_op_add(o, bg[3 + i], fg[3 + i], n)
    elsif mode == 4 || mode == 5
      pm = m.ec[a][:premul] ? 1 : 0
      same = (a == i) ? 1 : 0
      if mode == 4
        jxf_op_ablend(o, bg[3 + i], bg[3 + a], fg[3 + i], fg[3 + a], n, pm, cl, same)
      else
        jxf_op_ablend(o, fg[3 + i], fg[3 + a], bg[3 + i], bg[3 + a], n, pm, cl, same)
    elsif mode == 6
      jxf_op_awadd(o, bg[3 + i], fg[3 + i], fg[3 + a], n, cl, (a == i) ? 1 : 0)
    elsif mode == 7
      jxf_op_awadd(o, fg[3 + i], bg[3 + i], bg[3 + a], n, cl, (a == i) ? 1 : 0)
    elsif mode == 3
      jxf_op_mul(o, bg[3 + i], fg[3 + i], n, cl)
    elsif mode == 1
      jxr_copy_f(o, fg[3 + i], n)
    else
      jxr_copy_f(o, bg[3 + i], n)
    i += 1
  inf = infos[0]
  mode = inf[0]
  a = inf[1]
  cl = inf[2]
  if (mode == 6 || mode == 7) && !has_alpha
    mode = 2
  if (mode == 4 || mode == 5) && !has_alpha
    mode = 1
  c = 0
  while c < 3
    if mode == 2
      jxf_op_add(tmp[c], bg[c], fg[c], n)
    elsif mode == 6
      jxf_op_awadd(tmp[c], bg[c], fg[c], fg[3 + a], n, cl, 0)
    elsif mode == 7
      jxf_op_awadd(tmp[c], fg[c], bg[c], bg[3 + a], n, cl, 0)
    elsif mode == 4 || mode == 5
      pm = m.ec[a][:premul] ? 1 : 0
      if mode == 4
        jxf_op_ablend(tmp[c], bg[c], bg[3 + a], fg[c], fg[3 + a], n, pm, cl, 0)
      else
        jxf_op_ablend(tmp[c], fg[c], fg[3 + a], bg[c], bg[3 + a], n, pm, cl, 0)
    elsif mode == 3
      jxf_op_mul(tmp[c], bg[c], fg[c], n, cl)
    elsif mode == 1
      jxr_copy_f(tmp[c], fg[c], n)
    else
      jxr_copy_f(tmp[c], bg[c], n)
    c += 1
  if mode == 4 || mode == 5
    if mode == 4
      jxf_op_ablend(tmp[3 + a], bg[3 + a], bg[3 + a], fg[3 + a], fg[3 + a], n, 0, cl, 1)
    else
      jxf_op_ablend(tmp[3 + a], fg[3 + a], fg[3 + a], bg[3 + a], bg[3 + a], n, 0, cl, 1)
  tmp
JXF_CHW = [~0.0042, ~0.075, ~0.07, ~0.3333]

-> jxf_cidct(dct, t)
  r = ~0.0
  i = 0
  while i < 32
    r += dct[i] * Math.cos(~3.141592653589793 / ~32.0 * i * (t + ~0.5))
    i += 1
  r * ~1.4142135623730951

-> jxf_erf(x) (f64) f64
  ax = x
  ax = ~0.0 - ax if ax < ~0.0
  d1 = ax * ~0.0777394369 + ~0.000205260015
  d2 = d1 * ax + ~0.232120216
  d3 = d2 * ax + ~0.277820801
  d4 = d3 * ax + ~1.0
  d5 = d4 * d4
  inv = ~1.0 / d5
  r = ~1.0 - inv * inv
  r = ~0.0 - r if x <= ~0.0
  r

-> jxf_draw_seg(px, py, pb, w, h, cx, cy, c0, c1, c2, isig, s4i, maxd) (f64[] f64[] f64[] i64 i64 f64 f64 f64 f64 f64 f64 f64 f64) i64
  y0 = (cy - maxd + ~0.5).floor ## i64
  y1 = (cy + maxd + ~0.5).floor ## i64
  y1 += 1
  y0 = 0 if y0 < 0
  y1 = h if y1 > h
  x0 = (cx - maxd + ~0.5).floor ## i64
  x1 = (cx + maxd + ~0.5).floor ## i64
  x1 += 1
  x0 = 0 if x0 < 0
  x1 = w if x1 > w
  y = y0
  while y < y1
    dy = (y ## f64) - cy
    x = x0
    while x < x1
      dx = (x ## f64) - cx
      dist = Math.sqrt(dx * dx + dy * dy)
      f1 = jxf_erf((dist * ~0.5 + ~0.353553391) * isig) - jxf_erf((dist * ~0.5 - ~0.353553391) * isig)
      li = s4i * f1 * f1
      i = y * w + x
      px[i] = px[i] + c0 * li
      py[i] = py[i] + c1 * li
      pb[i] = pb[i] + c2 * li
      x += 1
    y += 1
  0

-> jxf_catmull(pts)
  return pts if pts.size == 1
  p = [[pts[0][0] * ~2.0 - pts[1][0], pts[0][1] * ~2.0 - pts[1][1]]]
  pts.each ->(q)
    p.push(q)
  nl = pts.size
  p.push([pts[nl - 1][0] * ~2.0 - pts[nl - 2][0], pts[nl - 1][1] * ~2.0 - pts[nl - 2][1]])
  res = []
  st = 0
  while st < p.size - 3
    res.push(p[st + 1])
    dd = [~0.0, ~0.0, ~0.0]
    t = [~0.0, ~0.0, ~0.0, ~0.0]
    k = 0
    while k < 3
      ex = p[st + k + 1][0] - p[st + k][0]
      ey = p[st + k + 1][1] - p[st + k][1]
      dd[k] = Math.sqrt(Math.sqrt(ex * ex + ey * ey))
      t[k + 1] = t[k] + dd[k]
      k += 1
    i = 1
    while i < 16
      tt = dd[0] + (i / ~16.0) * dd[1]
      a = []
      k = 0
      while k < 3
        fk = (tt - t[k]) / dd[k]
        a.push([p[st + k][0] + fk * (p[st + k + 1][0] - p[st + k][0]), p[st + k][1] + fk * (p[st + k + 1][1] - p[st + k][1])])
        k += 1
      b = []
      k = 0
      while k < 2
        fk = (tt - t[k]) / (dd[k] + dd[k + 1])
        b.push([a[k][0] + fk * (a[k + 1][0] - a[k][0]), a[k][1] + fk * (a[k + 1][1] - a[k][1])])
        k += 1
      fk = (tt - t[1]) / dd[1]
      res.push([b[0][0] + fk * (b[1][0] - b[0][0]), b[0][1] + fk * (b[1][1] - b[0][1])])
      i += 1
    st += 1
  res.push(p[p.size - 2])
  res

-> jxf_splines(d, pl)
  qa = d.splines[0]
  inv_q = ~1.0
  if qa >= 0
    inv_q = ~1.0 / (~1.0 + ~0.125 * qa)
  else
    inv_q = ~1.0 - ~0.125 * qa
  ytox = ~0.0
  ytob = ~1.0
  if d.vd != nil
    ytox = d.vd.base_x
    ytob = d.vd.base_b
  w = pl[0][1]
  h = pl[0][2]
  d.splines[1].each ->(sp)
    # control points
    cx = sp[0]
    cy = sp[1]
    pts = [[cx * ~1.0, cy * ~1.0]]
    ddx = 0
    ddy = 0
    sp[2].each ->(c)
      ddx += c[0]
      ddy += c[1]
      cx += ddx
      cy += ddy
      pts.push([cx * ~1.0, cy * ~1.0])
    dct = [[], [], [], []]
    c = 0
    while c < 4
      i = 0
      while i < 32
        fct = ~1.0
        fct = ~0.7071067811865476 if i == 0
        dct[c].push(sp[3][c][i] * fct * JXF_CHW[c] * inv_q)
        i += 1
      c += 1
    i = 0
    while i < 32
      dct[0][i] = dct[0][i] + ytox * dct[1][i]
      dct[2][i] = dct[2][i] + ytob * dct[1][i]
      i += 1
    ipts = jxf_catmull(pts)
    # equally spaced points with multipliers
    draw = []
    cur = ipts[0]
    draw.push([cur, ~1.0])
    nxt = 0
    done = false
    while !done && nxt < ipts.size
      prev = cur
      arc = ~0.0
      found = false
      while !found && !done
        if nxt >= ipts.size
          draw.push([prev, arc])
          done = true
        else
          ex = ipts[nxt][0] - prev[0]
          ey = ipts[nxt][1] - prev[1]
          an = Math.sqrt(ex * ex + ey * ey)
          if arc + an >= ~1.0
            fk = (~1.0 - arc) / an
            cur = [prev[0] + fk * ex, prev[1] + fk * ey]
            draw.push([cur, ~1.0])
            found = true
          else
            arc += an
            prev = ipts[nxt]
            nxt += 1
    arc_len = (draw.size - 2) * ~1.0 + draw[draw.size - 1][1]
    if arc_len > ~0.0
      k = 0
      draw.each ->(dp)
        prog = (k * ~1.0) / arc_len
        prog = ~1.0 if prog > ~1.0
        k += 1
        col = [jxf_cidct(dct[0], ~31.0 * prog), jxf_cidct(dct[1], ~31.0 * prog), jxf_cidct(dct[2], ~31.0 * prog)]
        sig = jxf_cidct(dct[3], ~31.0 * prog)
        mult = dp[1]
        if sig != ~0.0 && sig == sig
          mc = ~0.01
          col.each ->(cv)
            av = cv * mult
            av = ~0.0 - av if av < ~0.0
            mc = av if av > mc
          md = Math.sqrt(~-2.0 * sig * sig * (Math.log(~0.1) * ~3.0 - Math.log(mc)))
          jxf_draw_seg(pl[0][0], pl[1][0], pl[2][0], w, h, dp[0][0], dp[0][1], col[0], col[1], col[2], ~1.0 / sig, ~0.25 * sig * mult, md)
  0

JXF_UP2 = [~-0.01716200, ~-0.03452303, ~-0.04022174, ~-0.02921014, ~-0.00624645, ~0.14111091, ~0.28896755, ~0.00278718, ~-0.01610267, ~0.56661550, ~0.03777607, ~-0.01986694, ~-0.03144731, ~-0.01185068, ~-0.00213539]
JXF_UP4 = [~-0.02419067, ~-0.03491987, ~-0.03693351, ~-0.03094285, ~-0.00529785, ~-0.01663432, ~-0.03556863, ~-0.03888905, ~-0.03516850, ~-0.00989469, ~0.23651958, ~0.33392945, ~-0.01073543, ~-0.01313181, ~-0.03556694, ~0.13048175, ~0.40103025, ~0.03951150, ~-0.02077584, ~0.46914198, ~-0.00209270, ~-0.01484589, ~-0.04064806, ~0.18942530, ~0.56279892, ~0.06674400, ~-0.02335494, ~-0.03551682, ~-0.00754830, ~-0.02267919, ~-0.02363578, ~0.00315804, ~-0.03399098, ~-0.01359519, ~-0.00091653, ~-0.00335467, ~-0.01163294, ~-0.01610294, ~-0.00974088, ~-0.00191622, ~-0.01095446, ~-0.03198464, ~-0.04455121, ~-0.02799790, ~-0.00645912, ~0.06390599, ~0.22963888, ~0.00630981, ~-0.01897349, ~0.67537268, ~0.08483369, ~-0.02534994, ~-0.02205197, ~-0.01667999, ~-0.00384443]
JXF_UP8 = [~-0.02928613, ~-0.03706353, ~-0.03783812, ~-0.03324558, ~-0.00447632, ~-0.02519406, ~-0.03752601, ~-0.03901508, ~-0.03663285, ~-0.00646649, ~-0.02066407, ~-0.03838633, ~-0.04002101, ~-0.03900035, ~-0.00901973, ~-0.01626393, ~-0.03954148, ~-0.04046620, ~-0.03979621, ~-0.01224485, ~0.29895328, ~0.35757708, ~-0.02447552, ~-0.01081748, ~-0.04314594, ~0.23903219, ~0.41119301, ~-0.00573046, ~-0.01450239, ~-0.04246845, ~0.17567618, ~0.45220643, ~0.02287757, ~-0.01936783, ~-0.03583255, ~0.11572472, ~0.47416733, ~0.06284440, ~-0.02685066, ~0.42720050, ~-0.02248939, ~-0.01155273, ~-0.04562755, ~0.28689496, ~0.49093869, ~-0.00007891, ~-0.01545926, ~-0.04562659, ~0.21238920, ~0.53980934, ~0.03369474, ~-0.02070211, ~-0.03866988, ~0.14229550, ~0.56593398, ~0.08045181, ~-0.02888298, ~-0.03680918, ~-0.00542229, ~-0.02920477, ~-0.02788574, ~-0.02118180, ~-0.03942402, ~-0.00775547, ~-0.02433614, ~-0.03193943, ~-0.02030828, ~-0.04044014, ~-0.01074016, ~-0.01930822, ~-0.03620399, ~-0.01974125, ~-0.03919545, ~-0.01456093, ~-0.00045072, ~-0.00360110, ~-0.01020207, ~-0.01231907, ~-0.00638988, ~-0.00071592, ~-0.00279122, ~-0.00957115, ~-0.01288327, ~-0.00730937, ~-0.00107783, ~-0.00210156, ~-0.00890705, ~-0.01317668, ~-0.00813895, ~-0.00153491, ~-0.02128481, ~-0.04173044, ~-0.04831487, ~-0.03293190, ~-0.00525260, ~-0.01720322, ~-0.04052736, ~-0.05045706, ~-0.03607317, ~-0.00738030, ~-0.01341764, ~-0.03965629, ~-0.05151616, ~-0.03814886, ~-0.01005819, ~0.18968273, ~0.33063684, ~-0.01300105, ~-0.01372950, ~-0.04017465, ~0.13727832, ~0.36402234, ~0.01027890, ~-0.01832107, ~-0.03365072, ~0.08734506, ~0.38194295, ~0.04338228, ~-0.02525993, ~0.56408126, ~0.00458352, ~-0.01648227, ~-0.04887868, ~0.24585519, ~0.62026135, ~0.04314807, ~-0.02213737, ~-0.04158014, ~0.16637289, ~0.65027023, ~0.09621636, ~-0.03101388, ~-0.04082742, ~-0.00904519, ~-0.02790922, ~-0.02117818, ~0.00798662, ~-0.03995711, ~-0.01243427, ~-0.02231705, ~-0.02946266, ~0.00992055, ~-0.03600283, ~-0.01684920, ~-0.00111684, ~-0.00411204, ~-0.01297130, ~-0.01723725, ~-0.01022545, ~-0.00165306, ~-0.00313110, ~-0.01218016, ~-0.01763266, ~-0.01125620, ~-0.00231663, ~-0.01374149, ~-0.03797620, ~-0.05142937, ~-0.03117307, ~-0.00581914, ~-0.01064003, ~-0.03608089, ~-0.05272168, ~-0.03375670, ~-0.00795586, ~0.09628104, ~0.27129991, ~-0.00353779, ~-0.01734151, ~-0.03153981, ~0.05686230, ~0.28500998, ~0.02230594, ~-0.02374955, ~0.68214326, ~0.05018048, ~-0.02320852, ~-0.04383616, ~0.18459474, ~0.71517975, ~0.10805613, ~-0.03263677, ~-0.03637639, ~-0.01394373, ~-0.02511203, ~-0.01728636, ~0.05407331, ~-0.02867568, ~-0.01893131, ~-0.00240854, ~-0.00446511, ~-0.01636187, ~-0.02377053, ~-0.01522848, ~-0.00333334, ~-0.00819975, ~-0.02964169, ~-0.04499287, ~-0.02745350, ~-0.00612408, ~0.02727416, ~0.19446600, ~0.00159832, ~-0.02232473, ~0.74982506, ~0.11452620, ~-0.03348048, ~-0.01605681, ~-0.02070339, ~-0.00458223]

# ---------------------------------------------------------------- helpers

-> jxf_mirror(c, n) (i64 i64) i64
  while c < 0 || c >= n
    if c < 0
      c = 0 - c - 1
    else
      c = 2 * n - 1 - c
  c

# Pad a plane by b pixels on each side with mirroring → (w+2b) x (h+2b).
-> jxf_pad(s, w, h, b, o) (f64[] i64 i64 i64 f64[]) i64
  pw = w + 2 * b
  y = 0 ## i64
  while y < h + 2 * b
    sy = jxf_mirror(y - b, h)
    x = 0 ## i64
    while x < pw
      sx = jxf_mirror(x - b, w)
      o[y * pw + x] = s[sy * w + sx]
      x += 1
    y += 1
  0

# ---------------------------------------------------------------- Gaborish

-> jxf_gab_plane(s, o, w, h, w0, w1, w2) (f64[] f64[] i64 i64 f64 f64 f64) i64
  pw = w + 2
  y = 0 ## i64
  while y < h
    r = (y + 1) * pw + 1
    x = 0 ## i64
    while x < w
      i = r + x
      o[y * w + x] = s[i] * w0 + (s[i - 1] + s[i + 1] + s[i - pw] + s[i + pw]) * w1 + (s[i - pw - 1] + s[i - pw + 1] + s[i + pw - 1] + s[i + pw + 1]) * w2
      x += 1
    y += 1
  0

-> jxr_gaborish(d, pl)
  f = d.f
  c = 0
  while c < 3
    p = pl[c]
    w = p[1]
    h = p[2]
    w1 = f.gab_w[c * 2]
    w2 = f.gab_w[c * 2 + 1]
    sum = ~1.0 + ~4.0 * w1 + ~4.0 * w2
    pad = f64[(w + 2) * (h + 2)]
    jxf_pad(p[0], w, h, 1, pad)
    jxf_gab_plane(pad, p[0], w, h, ~1.0 / sum, w1 / sum, w2 / sum)
    c += 1
  0

# ---------------------------------------------------------------- EPF

# Per-block 1/sigma (negative), or values < kMinSigma to skip.
-> jxf_sigma(d)
  f = d.f
  vd = d.vd
  if f.modular || vd == nil
    return nil
  bw = vd.bw
  bh = vd.bh
  sg = f64[bw * bh]
  lut = f64[8]
  k = 0
  while k < 8
    lut[k] = f.epf_sharp[k]
    k += 1
  jxf_sigma_fill(sg, vd.qf, vd.sharp, bw * bh, f.epf_qm, vd.global_scale / ~65536.0, lut)
  sg

-> jxf_sigma_fill(sg, qf, sharp, n, qm, qscale, lut) (f64[] i32[] i32[] i64 f64 f64 f64[]) i64
  i = 0 ## i64
  while i < n
    qi = qf[i] ## i64
    sq = qm / (qscale * (qi ## f64) * ~-1.1715728752538099)
    s = sq * lut[sharp[i]]
    s = ~-0.0001 if s > ~-0.0001
    sg[i] = ~1.0 / s
    i += 1
  0

# One EPF step. kind 0: 12 neighbours, plus-shaped SAD; 1: 4 neighbours,
# plus-shaped SAD; 2: 4 neighbours, pixel SAD.
-> jxf_epf_step(px, py, pb, ox, oy, ob, w, h, sg, bw, msig, kind, sm, bsm, cs0, cs1, cs2) (f64[] f64[] f64[] f64[] f64[] f64[] i64 i64 f64[] i64 f64 i64 f64 f64 f64 f64 f64) i64
  b = 3
  pw = w + 2 * b
  dr = i64[12]
  dc = i64[12]
  nk = 4 ## i64
  if kind == 0
    nk = 12
    dr[0] = -2
    dc[0] = 0
    dr[1] = -1
    dc[1] = -1
    dr[2] = -1
    dc[2] = 0
    dr[3] = -1
    dc[3] = 1
    dr[4] = 0
    dc[4] = -2
    dr[5] = 0
    dc[5] = -1
    dr[6] = 0
    dc[6] = 1
    dr[7] = 0
    dc[7] = 2
    dr[8] = 1
    dc[8] = -1
    dr[9] = 1
    dc[9] = 0
    dr[10] = 1
    dc[10] = 1
    dr[11] = 2
    dc[11] = 0
  else
    dr[0] = -1
    dc[0] = 0
    dr[1] = 0
    dc[1] = -1
    dr[2] = 0
    dc[2] = 1
    dr[3] = 1
    dc[3] = 0
  y = 0 ## i64
  while y < h
    x = 0 ## i64
    while x < w
      ci = (y + b) * pw + x + b
      oi = y * w + x
      s = msig
      if bw > 0
        s = sg[(y >> 3) * bw + (x >> 3)]
      if s < ~-3.90524291751269967
        ox[oi] = px[ci]
        oy[oi] = py[ci]
        ob[oi] = pb[ci]
      else
        mul = sm
        yr = y & 7
        xr = x & 7
        if yr == 0 || yr == 7 || xr == 0 || xr == 7
          mul = bsm
        isg = s * mul
        sw = ~1.0
        sx = px[ci]
        sy = py[ci]
        sb = pb[ci]
        k = 0 ## i64
        while k < nk
          ni = ci + dr[k] * pw + dc[k]
          sad = ~0.0
          if kind == 2
            a = px[ni] - px[ci]
            a = ~0.0 - a if a < ~0.0
            sad = a * cs0
            a = py[ni] - py[ci]
            a = ~0.0 - a if a < ~0.0
            sad += a * cs1
            a = pb[ni] - pb[ci]
            a = ~0.0 - a if a < ~0.0
            sad += a * cs2
          else
            s0 = ~0.0
            s1 = ~0.0
            s2 = ~0.0
            t = 0 ## i64
            while t < 5
              o = 0 ## i64
              if t == 1
                o = 0 - pw
              elsif t == 2
                o = -1
              elsif t == 3
                o = pw
              elsif t == 4
                o = 1
              a = px[ci + o] - px[ni + o]
              a = ~0.0 - a if a < ~0.0
              s0 += a
              a = py[ci + o] - py[ni + o]
              a = ~0.0 - a if a < ~0.0
              s1 += a
              a = pb[ci + o] - pb[ni + o]
              a = ~0.0 - a if a < ~0.0
              s2 += a
              t += 1
            sad = s0 * cs0 + s1 * cs1 + s2 * cs2
          wt = ~1.0 + sad * isg
          if wt > ~0.0
            sw += wt
            sx += px[ni] * wt
            sy += py[ni] * wt
            sb += pb[ni] * wt
          k += 1
        ox[oi] = sx / sw
        oy[oi] = sy / sw
        ob[oi] = sb / sw
      x += 1
    y += 1
  0

-> jxr_epf(d, pl)
  f = d.f
  w = pl[0][1]
  h = pl[0][2]
  sg = jxf_sigma(d)
  bw = 0
  msig = ~0.0
  if sg == nil
    return 0 if f.epf_sigma_mod < ~0.3
    msig = ~-1.1715728752538099 / f.epf_sigma_mod
    sg = f64[1]
  else
    bw = d.vd.bw
  n = (w + 6) * (h + 6)
  pads = [f64[n], f64[n], f64[n]]
  steps = []
  steps.push([0, f.epf_p0 * ~1.65]) if f.epf_iters >= 3
  steps.push([1, ~1.65]) if f.epf_iters >= 1
  steps.push([2, f.epf_p2 * ~1.65]) if f.epf_iters >= 2
  steps.each ->(stp)
    c = 0
    while c < 3
      jxf_pad(pl[c][0], w, h, 3, pads[c])
      c += 1
    sm = stp[1]
    jxf_epf_step(pads[0], pads[1], pads[2], pl[0][0], pl[1][0], pl[2][0], w, h, sg, bw, msig, stp[0], sm, sm * f.epf_bsad, f.epf_cs[0], f.epf_cs[1], f.epf_cs[2])
  0

# ---------------------------------------------------------------- upsampling

-> jxf_up_kernel(weights, n)
  hh = n / 2
  k = f64[n * n * 25]
  ky = 0
  while ky < hh
    kx = 0
    while kx < hh
      o0 = (ky * n + kx) * 25
      o1 = (ky * n + (n - 1 - kx)) * 25
      o2 = ((n - 1 - ky) * n + kx) * 25
      o3 = ((n - 1 - ky) * n + (n - 1 - kx)) * 25
      py = 0
      while py < 5
        px = 0
        while px < 5
          j = 5 * ky + py
          i = 5 * kx + px
          my = i
          my = j if j < i
          mx = i
          mx = j if j > i
          wv = weights[5 * hh * my - my * (my - 1) / 2 + mx - my]
          k[o0 + py * 5 + px] = wv
          k[o1 + py * 5 + (4 - px)] = wv
          k[o2 + (4 - py) * 5 + px] = wv
          k[o3 + (4 - py) * 5 + (4 - px)] = wv
          px += 1
        py += 1
      kx += 1
    ky += 1
  k

-> jxf_up_plane(s, w, h, o, ow, oh, n, k) (f64[] i64 i64 f64[] i64 i64 i64 f64[]) i64
  pw = w + 4
  y = 0 ## i64
  while y < h
    x = 0 ## i64
    while x < w
      ci = (y + 2) * pw + x + 2
      mn = s[ci]
      mx = mn
      iy = -2 ## i64
      while iy <= 2
        ix = -2 ## i64
        while ix <= 2
          v = s[ci + iy * pw + ix]
          mn = v if v < mn
          mx = v if v > mx
          ix += 1
        iy += 1
      oy = 0 ## i64
      while oy < n
        ty = y * n + oy
        if ty < oh
          ox = 0 ## i64
          while ox < n
            tx = x * n + ox
            if tx < ow
              kb = (oy * n + ox) * 25
              acc = ~0.0
              iy = 0
              while iy < 5
                ix = 0
                while ix < 5
                  acc += s[ci + (iy - 2) * pw + (ix - 2)] * k[kb + iy * 5 + ix]
                  ix += 1
                iy += 1
              acc = mn if acc < mn
              acc = mx if acc > mx
              o[ty * ow + tx] = acc
            ox += 1
        oy += 1
      x += 1
    y += 1
  0

# Upsample plane [arr, w, h] by factor k (2/4/8) to at most (tw, th).
-> jxr_upsample(d, pl, k, tw, th)
  return pl if k <= 1
  m = d.m
  wts = nil
  if k == 2
    wts = m.up2
    wts = JXF_UP2 if wts == nil
  elsif k == 4
    wts = m.up4
    wts = JXF_UP4 if wts == nil
  else
    wts = m.up8
    wts = JXF_UP8 if wts == nil
  kern = jxf_up_kernel(wts, k)
  w = pl[1]
  h = pl[2]
  ow = w * k
  oh = h * k
  ow = tw if tw < ow
  oh = th if th < oh
  pad = f64[(w + 4) * (h + 4)]
  jxf_pad(pl[0], w, h, 2, pad)
  o = f64[ow * oh]
  jxf_up_plane(pad, w, h, o, ow, oh, k, kern)
  [o, ow, oh]

# ---------------------------------------------------------------- noise

-> jxf_lsr(x, k) (i64 i64) i64
  (x >> k) & ((1 << (64 - k)) - 1)

-> jxf_splitmix(z) (i64) i64
  z = (z ^ jxf_lsr(z, 30)) * -4658895280553007687
  z = (z ^ jxf_lsr(z, 27)) * -7723592293110705685
  z ^ jxf_lsr(z, 31)

# Xorshift128+ x8 seeded as libjxl's (seed1..4); st: i64[16] (s0[8], s1[8]).
-> jxf_rng_seed(st, a, b, c, e) (i64[] i64 i64 i64 i64) i64
  st[0] = jxf_splitmix(((a << 32) + b) + -7046029254386353131)
  st[8] = jxf_splitmix(((c << 32) + e) + -7046029254386353131)
  i = 1 ## i64
  while i < 8
    st[i] = jxf_splitmix(st[i - 1])
    st[8 + i] = jxf_splitmix(st[8 + i - 1])
    i += 1
  0

# One Fill: 16 floats in [1, 2) into out.
-> jxf_rng_fill(st, out) (i64[] f64[]) i64
  i = 0 ## i64
  while i < 8
    s1 = st[i]
    s0 = st[8 + i]
    bits = s1 + s0
    st[i] = s0
    s1 = s1 ^ (s1 << 23)
    s1 = s1 ^ (s0 ^ (jxf_lsr(s1, 18) ^ jxf_lsr(s0, 5)))
    st[8 + i] = s1
    lo = bits & 0xFFFFFFFF
    hi = jxf_lsr(bits, 32)
    l9 = lo >> 9
    h9 = hi >> 9
    out[2 * i] = ~1.0 + (l9 ## f64) / ~8388608.0
    out[2 * i + 1] = ~1.0 + (h9 ## f64) / ~8388608.0
    i += 1
  0

-> jxf_rng_rect(st, p, pw, x0, y0, rw, rh, buf) (i64[] f64[] i64 i64 i64 i64 i64 f64[]) i64
  y = 0 ## i64
  while y < rh
    x = 0 ## i64
    while x < rw
      jxf_rng_fill(st, buf)
      k = 0 ## i64
      while k < 16 && x + k < rw
        p[(y0 + y) * pw + x0 + x + k] = buf[k]
        k += 1
      x += 16
    y += 1
  0

-> jxf_conv_noise(s, o, w, h) (f64[] f64[] i64 i64) i64
  pw = w + 4
  y = 0 ## i64
  while y < h
    x = 0 ## i64
    while x < w
      ci = (y + 2) * pw + x + 2
      sum = ~0.0
      dy = -2 ## i64
      while dy <= 2
        dx = -2 ## i64
        while dx <= 2
          sum += s[ci + dy * pw + dx]
          dx += 1
        dy += 1
      c = s[ci]
      o[y * w + x] = (sum - c) * ~0.16 - c * ~3.84
      x += 1
    y += 1
  0

-> jxf_strength(v, lut) (f64 f64[]) f64
  sx = v * ~6.0
  sx = ~0.0 if sx < ~0.0
  fl = sx.floor
  fr = sx - fl
  if sx >= ~7.0
    fl = ~6.0
    fr = ~1.0
  fi = fl ## i64
  r = lut[fi] + (lut[fi + 1] - lut[fi]) * fr
  r = ~0.0 if r < ~0.0
  r = ~1.0 if r > ~1.0
  r

-> jxf_add_noise(px, py, pb, nr, ng, nc, n, lut, ytox, ytob) (f64[] f64[] f64[] f64[] f64[] f64[] i64 f64[] f64 f64) i64
  i = 0 ## i64
  while i < n
    vx = px[i]
    vy = py[i]
    sg = jxf_strength((vy - vx) * ~0.5, lut)
    sr = jxf_strength((vy + vx) * ~0.5, lut)
    rr = nr[i] * ~0.22
    rg = ng[i] * ~0.22
    rc = nc[i] * ~0.22
    red = sr * (~0.0078125 * rr + ~0.9921875 * rc)
    green = sg * (~0.0078125 * rg + ~0.9921875 * rc)
    rgn = red + green
    px[i] = vx + ytox * rgn + red - green
    py[i] = vy + rgn
    pb[i] = pb[i] + ytob * rgn
    i += 1
  0

-> jxf_noise(d, pl)
  f = d.f
  w = pl[0][1]
  h = pl[0][2]
  n = w * h
  g = f.gdim
  planes = [f64[n], f64[n], f64[n]]
  st = i64[16]
  buf = f64[16]
  ty = 0
  while ty * g < h
    tx = 0
    while tx * g < w
      jxf_rng_seed(st, d.vis_idx, d.nonvis_idx, tx * g, ty * g)
      rw = w - tx * g
      rw = g if rw > g
      rh = h - ty * g
      rh = g if rh > g
      c = 0
      while c < 3
        jxf_rng_rect(st, planes[c], w, tx * g, ty * g, rw, rh, buf)
        c += 1
      tx += 1
    ty += 1
  conv = []
  pad = f64[(w + 4) * (h + 4)]
  c = 0
  while c < 3
    jxf_pad(planes[c], w, h, 2, pad)
    o = f64[n]
    jxf_conv_noise(pad, o, w, h)
    conv.push(o)
    c += 1
  ytox = ~0.0
  ytob = ~1.0
  if d.vd != nil
    ytox = d.vd.base_x
    ytob = d.vd.base_b
  jxf_add_noise(pl[0][0], pl[1][0], pl[2][0], conv[0], conv[1], conv[2], n, d.noise, ytox, ytob)
  0
