# core/codec/image/jxl_modular — JPEG XL modular mode: MA trees, predictors (including
# the self-correcting weighted predictor), and the RCT / palette / squeeze
# transforms. Channels are JxCh objects holding an i32[] plane.

use jxl_ans

+ JxCh
  rw :w, :h, :hs, :vs, :d

  -> new(@w, @h, @hs = 0, @vs = 0)
    n = @w * @h
    n = 1 if n < 1
    @d = i32[n]

  -> copy_meta
    JxCh.new(@w, @h, @hs, @vs)

# A modular image: channel list, meta channel count, transforms, bit depth.
+ JxMImg
  rw :ch, :nb_meta, :tr, :bitdepth, :wpp, :use_global

  -> new(@ch, @bitdepth)
    @nb_meta = 0
    @tr = []
    @wpp = nil
    @use_global = false

JX_DIV24 = [0x1000000, 0x800000, 0x555555, 0x400000, 0x333333, 0x2aaaaa, 0x249249, 0x200000, 0x1c71c7, 0x199999, 0x1745d1, 0x155555, 0x13b13b, 0x124924, 0x111111, 0x100000, 0xf0f0f, 0xe38e3, 0xd7943, 0xccccc, 0xc30c3, 0xba2e8, 0xb2164, 0xaaaaa, 0xa3d70, 0x9d89d, 0x97b42, 0x92492, 0x8d3dc, 0x88888, 0x84210, 0x80000, 0x7c1f0, 0x78787, 0x75075, 0x71c71, 0x6eb3e, 0x6bca1, 0x69069, 0x66666, 0x63e70, 0x61861, 0x5f417, 0x5d174, 0x5b05b, 0x590b2, 0x57262, 0x55555, 0x53978, 0x51eb8, 0x50505, 0x4ec4e, 0x4d487, 0x4bda1, 0x4a790, 0x49249, 0x47dc1, 0x469ee, 0x456c7, 0x44444, 0x4325c, 0x42108, 0x41041, 0x40000]

JXM_STATE = [nil]

-> jxm_div24
  if JXM_STATE[0] == nil
    t = i64[64]
    i = 0
    while i < 64
      t[i] = JX_DIV24[i]
      i += 1
    JXM_STATE[0] = t
  JXM_STATE[0]

JXM_LG = [nil]

-> jxm_ans_sym(src, br, cs, es, base, ta, lbs, bmask) (u8[] i64[] i32[] i64[] i64 i64 i64 i64) i64
  state = es[0]
  index = state & 0xfff
  bi = index >> lbs
  bpos = index & bmask
  sym = bi
  boff = 0 ## i64
  if bpos >= cs[base + ta + bi]
    sym = cs[base + 3 * ta + bi]
    boff = cs[base + 2 * ta + bi]
  state = cs[base + sym] * (state >> 12) + boff + bpos
  if state < 65536
    if br[2] < 16
      jb_fill(src, br)
    state = (state << 16) | (br[1] & 0xffff)
    br[1] = br[1] >> 16
    br[2] = br[2] - 16
  es[0] = state
  sym

-> jxm_lg
  if JXM_LG[0] == nil
    t = i64[65536]
    jxm_fill_lg(t)
    JXM_LG[0] = t
  JXM_LG[0]

-> jxm_fill_lg(t) (i64[]) i64
  i = 1 ## i64
  while i < 65536
    t[i] = jxm_flog2(i)
    i += 1
  0

-> jxm_flog2(x) (i64) i64
  r = 0 ## i64
  if x >= 4294967296
    x = x >> 32
    r += 32
  if x >= 65536
    x = x >> 16
    r += 16
  if x >= 256
    x = x >> 8
    r += 8
  if x >= 16
    x = x >> 4
    r += 4
  if x >= 4
    x = x >> 2
    r += 2
  if x >= 2
    r += 1
  r

# ---------------------------------------------------------------- MA tree

# Tree nodes, 6 i64 each: branch [prop, value, left, right, 0, 0];
# leaf [-1, ctx, predictor, offset, multiplier, 0].
-> jxm_read_tree(src, br, limit)
  cs = jx_read_code(src, br, 6)
  es = jx_stream(src, br, cs)
  win = jx_window(cs)
  nodes = []
  ctx_id = 0
  left = 1
  idx = 0
  while left > 0
    left -= 1
    prop = jx_decode(src, br, cs, es, win, 1, 0)
    if prop > 0
      val = jx_unpack_signed(jx_decode(src, br, cs, es, win, 0, 0))
      nodes.push([prop - 1, val, idx + left + 1, idx + left + 2, 0, 0])
      left += 2
    else
      pred = jx_decode(src, br, cs, es, win, 2, 0)
      off = jx_unpack_signed(jx_decode(src, br, cs, es, win, 3, 0))
      sh = jx_decode(src, br, cs, es, win, 4, 0)
      mv = jx_decode(src, br, cs, es, win, 5, 0)
      jxl_fail("tree multiplier") if sh >= 31
      jxl_fail("tree predictor") if pred > 13
      nodes.push([-1, ctx_id, pred, off, (mv + 1) << sh, 0])
      ctx_id += 1
    idx += 1
    jxl_fail("tree too large") if idx + left > limit
  jx_finish(src, br, cs, es)
  # children were numbered in BFS order relative to the queue; convert:
  # node idx's children are the next two entries appended after all nodes
  # queued before them, which is exactly idx+left+1 at the time of reading.
  t = i64[nodes.size * 6]
  i = 0
  while i < nodes.size
    nd = nodes[i]
    k = 0
    while k < 6
      t[i * 6 + k] = nd[k]
      k += 1
    i += 1
  code = jx_read_code(src, br, ctx_id)
  [t, code, ctx_id]

# ---------------------------------------------------------------- group header

-> jxm_wp_header(src, br)
  w = i64[11]
  if jb_u(src, br, 1) == 1
    w[0] = 16
    w[1] = 10
    w[2] = 7
    w[3] = 7
    w[4] = 7
    w[5] = 0
    w[6] = 0
    w[7] = 13
    w[8] = 12
    w[9] = 12
    w[10] = 12
  else
    w[0] = jb_u(src, br, 5)
    w[1] = jb_u(src, br, 5)
    k = 2
    while k < 7
      w[k] = jb_u(src, br, 5)
      k += 1
    k = 7
    while k < 11
      w[k] = jb_u(src, br, 4)
      k += 1
  w

# Reads GroupHeader into img (use_global, wp params, transforms) and applies
# the transforms' effect on the channel list (MetaApply).
-> jxm_read_header(src, br, img)
  img.use_global = jb_u(src, br, 1) == 1
  img.wpp = jxm_wp_header(src, br)
  ntr = jb_u32(src, br, 0, 0, 1, 0, 2, 4, 18, 8)
  i = 0
  while i < ntr
    kind = jb_u(src, br, 2)
    if kind == 0
      bc = jb_u32(src, br, 0, 3, 8, 6, 72, 10, 1096, 13)
      rt = jb_u32(src, br, 6, 0, 0, 2, 2, 4, 10, 6)
      jxl_fail("rct type") if rt >= 42
      jxl_fail("rct channels") if bc + 3 > img.ch.size
      img.tr.push([0, bc, rt])
    elsif kind == 1
      bc = jb_u32(src, br, 0, 3, 8, 6, 72, 10, 1096, 13)
      nc = jb_u32(src, br, 1, 0, 3, 0, 4, 0, 1, 13)
      ncol = jb_u32(src, br, 0, 8, 256, 10, 1280, 12, 5376, 16)
      ndel = jb_u32(src, br, 0, 0, 1, 8, 257, 10, 1281, 16)
      dp = jb_u(src, br, 4)
      jxl_fail("palette predictor") if dp > 13
      jxl_fail("palette channels") if bc + nc > img.ch.size || nc < 1
      img.tr.push([1, bc, nc, ncol, ndel, dp])
      jxm_meta_palette(img, bc, nc, ncol, ndel)
    elsif kind == 2
      nsq = jb_u32(src, br, 0, 0, 1, 4, 9, 6, 41, 8)
      sqs = []
      k = 0
      while k < nsq
        hz = jb_u(src, br, 1)
        ip = jb_u(src, br, 1)
        bc = jb_u32(src, br, 0, 3, 8, 6, 72, 10, 1096, 13)
        nc = jb_u32(src, br, 1, 0, 2, 0, 3, 0, 4, 4)
        sqs.push([hz, ip, bc, nc])
        k += 1
      sqs = jxm_default_squeeze(img) if sqs.size == 0
      img.tr.push([2, sqs])
      jxm_meta_squeeze(img, sqs)
    else
      jxl_fail("unknown transform")
    i += 1
  img

-> jxm_meta_palette(img, bc, nc, ncol, ndel)
  if bc >= img.nb_meta
    img.nb_meta = img.nb_meta + 1
  else
    jxl_fail("palette meta range") if bc + nc - 1 >= img.nb_meta
    img.nb_meta = img.nb_meta + 2 - nc
  chs = img.ch
  out = []
  out.push(JxCh.new(ncol + ndel, nc, -1, -1))
  i = 0
  while i < chs.size
    out.push(chs[i]) if i <= bc || i > bc + nc - 1
    i += 1
  img.ch = out

-> jxm_default_squeeze(img)
  out = []
  nm = img.nb_meta
  nch = img.ch.size - nm
  w = img.ch[nm].w
  h = img.ch[nm].h
  if nch > 2 && img.ch[nm + 1].w == w && img.ch[nm + 1].h == h
    out.push([1, 0, nm + 1, 2])
    out.push([0, 0, nm + 1, 2])
  wide = w > h
  if !wide && h > 8
    out.push([0, 1, nm, nch])
    h = (h + 1) / 2
  while w > 8 || h > 8
    if w > 8
      out.push([1, 1, nm, nch])
      w = (w + 1) / 2
    if h > 8
      out.push([0, 1, nm, nch])
      h = (h + 1) / 2
  out

-> jxm_meta_squeeze(img, sqs)
  sqs.each ->(sq)
    hz = sq[0]
    ip = sq[1]
    bc = sq[2]
    ec = bc + sq[3] - 1
    jxl_fail("squeeze range") if ec >= img.ch.size || bc < 0
    if bc < img.nb_meta
      jxl_fail("squeeze meta") if ec >= img.nb_meta || ip == 0
      img.nb_meta = img.nb_meta + sq[3]
    offset = img.ch.size
    offset = ec + 1 if ip == 1
    c = bc
    while c <= ec
      ch = img.ch[c]
      w = ch.w
      h = ch.h
      jxl_fail("squeezing empty channel") if w == 0 || h == 0
      rw = w
      rh = h
      if hz == 1
        ch.w = (w + 1) / 2
        ch.hs = ch.hs + 1 if ch.hs >= 0
        rw = w - (w + 1) / 2
      else
        ch.h = (h + 1) / 2
        ch.vs = ch.vs + 1 if ch.vs >= 0
        rh = h - (h + 1) / 2
      res = JxCh.new(rw, rh, ch.hs, ch.vs)
      img.ch.insert(offset + (c - bc), res)
      c += 1

# Allocate planes for the channels' (possibly changed) sizes.
-> jxm_alloc(img)
  img.ch.each ->(c)
    n = c.w * c.h
    n = 1 if n < 1
    c.d = i32[n] if c.d.size != n
  img

# ---------------------------------------------------------------- channel decode

# Decode one channel with an MA tree. refs holds nref previous channels of the
# same size (w*h each), used by properties 16+.
-> jxm_channel(src, br, cs, es, win, tree, d, w, h, cidx, sidx, dm, wpp, refs, nref, use_wp, div, lg) (u8[] i64[] i32[] i64[] i32[] i64[] i32[] i64 i64 i64 i64 i64 i64[] i32[] i64 i64 i64[] i64[]) i64
  err = i64[1]
  one = 1 ## i64
  fast = 0 ## i64
  if cs[0] == 0 && cs[3] == 0
    fast = 1
  if cs[0] == 1 && cs[3] == 0
    fast = 2
  las = cs[1] ## i64
  lbs = 12 - las
  bmask = (one << lbs) - 1
  ta = one << las
  tix = cs[12] ## i64
  cfgo = cs[11] ## i64
  if use_wp == 1
    err = i64[w * 2 * 5 + 10]
  p1 = wpp[0]
  p2 = wpp[1]
  p30 = wpp[2]
  p31 = wpp[3]
  p32 = wpp[4]
  p33 = wpp[5]
  p34 = wpp[6]
  ww0 = wpp[7]
  ww1 = wpp[8]
  ww2 = wpp[9]
  ww3 = wpp[10]
  plane = w * h
  y = 0 ## i64
  while y < h
    row = y * w
    erow = (y & 1) * w
    nerow = ((y & 1) ^ 1) * w
    last9 = 0 ## i64
    x = 0 ## i64
    while x < w
      i = row + x
      # neighbours (J40 edge rules)
      pw = 0 ## i64
      pn = 0 ## i64
      if x > 0
        pw = d[i - 1]
      elsif y > 0
        pw = d[i - w]
      if y > 0
        pn = d[i - w]
      else
        pn = pw
      pnw = pw
      if x > 0 && y > 0
        pnw = d[i - w - 1]
      pne = pn
      if x + 1 < w && y > 0
        pne = d[i - w + 1]
      pnn = pn
      if y > 1
        pnn = d[i - 2 * w]
      pnee = pne
      if x + 2 < w && y > 0
        pnee = d[i - w + 2]
      pww = pw
      if x > 1
        pww = d[i - 2]
      pnww = pww
      if x > 1 && y > 0
        pnww = d[i - w - 2]
      # weighted predictor state
      pr0 = 0 ## i64
      pr1 = 0 ## i64
      pr2 = 0 ## i64
      pr3 = 0 ## i64
      pr4 = 0 ## i64
      tw = 0 ## i64
      tn = 0 ## i64
      tnw = 0 ## i64
      tne = 0 ## i64
      if use_wp == 1
        ew = (erow + x - 1) * 5
        en = (nerow + x) * 5
        enw = (nerow + x - 1) * 5
        ene = (nerow + x + 1) * 5
        eww = (erow + x - 2) * 5
        if x > 0
          tw = err[ew + 4]
        if y > 0
          tn = err[en + 4]
        tnw = tn
        if x > 0 && y > 0
          tnw = err[enw + 4]
        tne = tn
        if x + 1 < w && y > 0
          tne = err[ene + 4]
        pr0 = (pw + pne - pn) * 8
        pr1 = pn * 8 - (((tw + tn + tne) * p1) >> 5)
        pr2 = pw * 8 - (((tw + tn + tnw) * p2) >> 5)
        pr3 = pn * 8 - ((tnw * p30 + tn * p31 + tne * p32 + (pnn - pn) * 8 * p33 + (pnw - pw) * 8 * p34) >> 5)
        wsum4 = 0 ## i64
        wt0 = 0 ## i64
        wt1 = 0 ## i64
        wt2 = 0 ## i64
        wt3 = 0 ## i64
        k = 0 ## i64
        while k < 4
          e_w = 0 ## i64
          e_n = 0 ## i64
          e_ww = 0 ## i64
          if x > 0
            e_w = err[ew + k]
          if y > 0
            e_n = err[en + k]
          e_nw = e_n
          if x > 0 && y > 0
            e_nw = err[enw + k]
          e_ne = e_n
          if x + 1 < w && y > 0
            e_ne = err[ene + k]
          if x > 1
            e_ww = err[eww + k]
          e_w2 = 0 ## i64
          if x + 1 >= w
            e_w2 = e_w
          es_ = (e_n + e_w + e_nw + e_ww + e_ne + e_w2) & 0xFFFFFFFF
          e1 = es_ + 1
          sh = 0 ## i64
          if e1 < 65536
            sh = lg[e1] - 5
          else
            sh = jxm_flog2(e1) - 5
          sh = 0 if sh < 0
          wk = 0 ## i64
          if k == 0
            wk = 4 + ((ww0 * div[es_ >> sh]) >> sh)
            wt0 = wk
          elsif k == 1
            wk = 4 + ((ww1 * div[es_ >> sh]) >> sh)
            wt1 = wk
          elsif k == 2
            wk = 4 + ((ww2 * div[es_ >> sh]) >> sh)
            wt2 = wk
          else
            wk = 4 + ((ww3 * div[es_ >> sh]) >> sh)
            wt3 = wk
          k += 1
        wtt = wt0 + wt1 + wt2 + wt3
        logw = 0 ## i64
        if wtt < 65536
          logw = lg[wtt] - 4
        else
          logw = jxm_flog2(wtt) - 4
        wt0 = wt0 >> logw
        wt1 = wt1 >> logw
        wt2 = wt2 >> logw
        wt3 = wt3 >> logw
        wsum4 = wt0 + wt1 + wt2 + wt3
        sum = pr0 * wt0 + pr1 * wt1 + pr2 * wt2 + pr3 * wt3
        pr4 = ((sum + (wsum4 >> 1) - 1) * div[wsum4 - 1]) >> 24
        if ((tn ^ tw) | (tn ^ tnw)) <= 0
          lo = pw
          lo = pn if pn < lo
          lo = pne if pne < lo
          hi = pw
          hi = pn if pn > hi
          hi = pne if pne > hi
          lo = lo * 8
          hi = hi * 8
          pr4 = lo if pr4 < lo
          pr4 = hi if pr4 > hi
      # walk the tree
      n = 0 ## i64
      cur9 = ((pw + pn - pnw + 2147483648) & 0xFFFFFFFF) - 2147483648
      while tree[n * 6] >= 0
        pp = tree[n * 6]
        v = 0 ## i64
        if pp < 16
          if pp == 0
            v = cidx
          elsif pp == 1
            v = sidx
          elsif pp == 2
            v = y
          elsif pp == 3
            v = x
          elsif pp == 4
            v = pn
            v = 0 - v if v < 0
          elsif pp == 5
            v = pw
            v = 0 - v if v < 0
          elsif pp == 6
            v = pn
          elsif pp == 7
            v = pw
          elsif pp == 8
            v = pw - last9
          elsif pp == 9
            v = pw + pn - pnw
          elsif pp == 10
            v = pw - pnw
          elsif pp == 11
            v = pnw - pn
          elsif pp == 12
            v = pn - pne
          elsif pp == 13
            v = pn - pnn
          elsif pp == 14
            v = pw - pww
          else
            v = tw
            av = v
            av = 0 - av if av < 0
            t2 = tn
            t2 = 0 - t2 if t2 < 0
            if av < t2
              v = tn
              av = t2
            t2 = tnw
            t2 = 0 - t2 if t2 < 0
            if av < t2
              v = tnw
              av = t2
            t2 = tne
            t2 = 0 - t2 if t2 < 0
            if av < t2
              v = tne
        else
          rk = (pp - 16) >> 2
          if rk >= nref
            v = 0
          else
            rb = rk * plane
            v = refs[rb + i]
            if (pp & 2) != 0
              rw_ = 0 ## i64
              if x > 0
                rw_ = refs[rb + i - 1]
              rn = rw_
              if y > 0
                rn = refs[rb + i - w]
              rnw = rw_
              if x > 0 && y > 0
                rnw = refs[rb + i - w - 1]
              glo = rw_
              ghi = rn
              if rn < rw_
                glo = rn
                ghi = rw_
              g = rw_ + rn - rnw
              g = glo if g < glo
              g = ghi if g > ghi
              v = v - g
            if (pp & 1) == 0
              v = 0 - v if v < 0
        v = ((v + 2147483648) & 0xFFFFFFFF) - 2147483648
        if v > tree[n * 6 + 1]
          n = tree[n * 6 + 2]
        else
          n = tree[n * 6 + 3]
      last9 = cur9
      nb = n * 6
      tok = 0 ## i64
      if fast > 0 && es[1] == 0
        cl = cs[16 + tree[nb + 1]] ## i64
        base = cs[tix + cl] ## i64
        sym = 0 ## i64
        if fast == 2
          pfl = cs[base] ## i64
          pml = cs[base + 1] ## i64
          if br[2] < pml
            jb_fill(src, br)
          pe = cs[base + 2 + (br[1] & ((one << pfl) - 1))] ## i64
          if pe < 0 && pfl < pml
            sym = jx_read_sym(src, br, cs, es, cl)
          else
            pl_ = pe & 15
            br[1] = br[1] >> pl_
            br[2] = br[2] - pl_
            sym = pe >> 16
        else
          sym = jxm_ans_sym(src, br, cs, es, base, ta, lbs, bmask)
        cfg = cfgo + cl * 4
        se = cs[cfg] ## i64
        if sym < (one << se)
          tok = sym
        else
          msb = cs[cfg + 1] ## i64
          lsb = cs[cfg + 2] ## i64
          nbt = msb + lsb
          mb = (se - nbt + ((sym - (one << se)) >> nbt)) & 31
          if br[2] < mb
            jb_fill(src, br)
          mid = br[1] & ((one << mb) - 1)
          br[1] = br[1] >> mb
          br[2] = br[2] - mb
          top = one << msb
          lo = sym & ((one << lsb) - 1)
          hi = (sym >> lsb) & (top - 1)
          tok = (((top | hi) << (mb + lsb)) | (mid << lsb) | lo) & 0xFFFFFFFF
      else
        tok = jx_decode(src, br, cs, es, win, tree[nb + 1], dm)
      val = 0 ## i64
      if (tok & 1) == 1
        val = 0 - (tok >> 1) - 1
      else
        val = tok >> 1
      val = val * tree[nb + 4] + tree[nb + 3]
      pred = tree[nb + 2]
      pv = 0 ## i64
      if pred == 0
        pv = 0
      elsif pred == 1
        pv = pw
      elsif pred == 2
        pv = pn
      elsif pred == 3
        pv = (pw + pn) / 2
      elsif pred == 4
        a1 = pn - pnw
        a1 = 0 - a1 if a1 < 0
        a2 = pw - pnw
        a2 = 0 - a2 if a2 < 0
        if a1 < a2
          pv = pw
        else
          pv = pn
      elsif pred == 5
        glo = pw
        ghi = pn
        if pn < pw
          glo = pn
          ghi = pw
        pv = pw + pn - pnw
        pv = glo if pv < glo
        pv = ghi if pv > ghi
      elsif pred == 6
        pv = (pr4 + 3) >> 3
      elsif pred == 7
        pv = pne
      elsif pred == 8
        pv = pnw
      elsif pred == 9
        pv = pww
      elsif pred == 10
        pv = (pw + pnw) / 2
      elsif pred == 11
        pv = (pn + pnw) / 2
      elsif pred == 12
        pv = (pn + pne) / 2
      else
        pv = (6 * pn - 2 * pnn + 7 * pw + pww + pnee + 3 * pne + 8) / 16
      val = val + pv
      d[i] = val
      if use_wp == 1
        val = d[i]
        eb = (erow + x) * 5
        v8 = val * 8
        e0 = pr0 - v8
        e0 = 0 - e0 if e0 < 0
        err[eb] = ((e0 + 3) >> 3) & 0xFFFFFFFF
        e0 = pr1 - v8
        e0 = 0 - e0 if e0 < 0
        err[eb + 1] = ((e0 + 3) >> 3) & 0xFFFFFFFF
        e0 = pr2 - v8
        e0 = 0 - e0 if e0 < 0
        err[eb + 2] = ((e0 + 3) >> 3) & 0xFFFFFFFF
        e0 = pr3 - v8
        e0 = 0 - e0 if e0 < 0
        err[eb + 3] = ((e0 + 3) >> 3) & 0xFFFFFFFF
        te = (pr4 - v8 + 2147483648) & 0xFFFFFFFF
        err[eb + 4] = te - 2147483648
      x += 1
    y += 1
  0

# Does this tree need the weighted predictor (property 15 or predictor 6)?
-> jxm_tree_uses_wp(tree)
  n = tree.size / 6
  i = 0
  while i < n
    return 1 if tree[i * 6] == 15
    return 1 if tree[i * 6] < 0 && tree[i * 6 + 2] == 6
    i += 1
  0

-> jxm_tree_max_ref(tree)
  n = tree.size / 6
  mx = 0
  i = 0
  while i < n
    p = tree[i * 6]
    if p >= 16
      r = (p - 16) / 4 + 1
      mx = r if r > mx
    i += 1
  mx

# Decode all channels of img (that fit max_size, unless meta) from one stream.
# gtree: [tree, code, nctx] of the global tree or nil.
-> jxm_decode_channels(src, br, img, sidx, max_size, gtree)
  chs = img.ch
  dm = 0
  i = 0
  nchans = 0
  while i < chs.size
    c = chs[i]
    break if i >= img.nb_meta && (c.w > max_size || c.h > max_size)
    if c.w > 0 && c.h > 0
      dm = c.w if c.w > dm
      nchans += 1
    i += 1
  return 0 if nchans == 0
  tr = nil
  if img.use_global
    jxl_fail("no global tree") if gtree == nil
    tr = gtree
  else
    lim = 1024
    i = 0
    while i < chs.size
      c = chs[i]
      break if i >= img.nb_meta && (c.w > max_size || c.h > max_size)
      lim += c.w * c.h
      i += 1
    lim = 1048576 if lim > 1048576
    tr = jxm_read_tree(src, br, lim)
  tree = tr[0]
  cs = tr[1]
  es = jx_stream(src, br, cs)
  win = jx_window(cs)
  use_wp = jxm_tree_uses_wp(tree)
  maxref = jxm_tree_max_ref(tree)
  div = jxm_div24()
  i = 0
  while i < chs.size
    c = chs[i]
    break if i >= img.nb_meta && (c.w > max_size || c.h > max_size)
    if c.w > 0 && c.h > 0
      jxm_alloc_one(c)
      refs = i32[1]
      nref = 0
      if maxref > 0
        cand = []
        j = i - 1
        while j >= 0 && cand.size < maxref
          r = chs[j]
          cand.push(r) if r.w == c.w && r.h == c.h && r.hs == c.hs && r.vs == c.vs
          j -= 1
        nref = cand.size
        if nref > 0
          pl = c.w * c.h
          refs = i32[pl * nref]
          k = 0
          while k < nref
            jxm_copy_into(refs, k * pl, cand[k].d, pl)
            k += 1
      jxm_channel(src, br, cs, es, win, tree, c.d, c.w, c.h, i, sidx, dm, img.wpp, refs, nref, use_wp, div, jxm_lg())
    i += 1
  jx_finish(src, br, cs, es)
  0

-> jxm_alloc_one(c)
  n = c.w * c.h
  n = 1 if n < 1
  c.d = i32[n] if c.d.size != n
  c

-> jxm_copy_into(dst, off, s, n) (i32[] i64 i32[] i64) i64
  i = 0 ## i64
  while i < n
    dst[off + i] = s[i]
    i += 1
  0

# ---------------------------------------------------------------- inverse transforms

-> jxm_inverse(img)
  k = img.tr.size - 1
  while k >= 0
    t = img.tr[k]
    if t[0] == 0
      jxm_inv_rct(img, t[1], t[2])
    elsif t[0] == 1
      jxm_inv_palette(img, t[1], t[2], t[3], t[4], t[5])
    else
      jxm_inv_squeeze(img, t[1])
    k -= 1
  img.tr = []
  img

-> jxm_rct_loop(a, b, c, n, kind) (i32[] i32[] i32[] i64 i64) i64
  i = 0 ## i64
  if kind == 6
    while i < n
      y_ = a[i] ## i64
      co = b[i] ## i64
      cg = c[i] ## i64
      tmp = y_ - (cg >> 1)
      g = cg + tmp
      bb = tmp - (co >> 1)
      a[i] = bb + co
      b[i] = g
      c[i] = bb
      i += 1
    return 0
  third = kind & 1
  second = kind >> 1
  while i < n
    f = a[i] ## i64
    t = c[i] ## i64
    if third == 1
      t = t + f
      c[i] = t
    if second == 1
      b[i] = b[i] + f
    elsif second == 2
      b[i] = b[i] + ((f + t) >> 1)
    i += 1
  0

JXM_PERM = [[0, 1, 2], [1, 2, 0], [2, 0, 1], [0, 2, 1], [1, 0, 2], [2, 1, 0]]

-> jxm_inv_rct(img, bc, rt)
  c0 = img.ch[bc]
  c1 = img.ch[bc + 1]
  c2 = img.ch[bc + 2]
  kind = rt % 7
  n = c0.w * c0.h
  jxm_rct_loop(c0.d, c1.d, c2.d, n, kind) if kind > 0 && n > 0
  cc = [c0, c1, c2]
  p = JXM_PERM[rt / 7]
  img.ch[bc + p[0]] = cc[0]
  img.ch[bc + p[1]] = cc[1]
  img.ch[bc + p[2]] = cc[2]

JXM_DELTA_PAL = [[0, 0, 0], [4, 4, 4], [11, 0, 0], [0, 0, -13], [0, -12, 0], [-10, -10, -10], [-18, -18, -18], [-27, -27, -27], [-18, -18, 0], [0, 0, -32], [-32, 0, 0], [-37, -37, -37], [0, -32, -32], [24, 24, 45], [50, 50, 50], [-45, -24, -24], [-24, -45, -45], [0, -24, -24], [-34, -34, 0], [-24, 0, -24], [-45, -45, -24], [64, 64, 64], [-32, 0, -32], [0, -32, 0], [-32, 0, 32], [-24, -45, -24], [45, 24, 45], [24, -24, -45], [-45, -24, 24], [80, 80, 80], [64, 0, 0], [0, 0, -64], [0, -64, -64], [-24, -24, 45], [96, 96, 96], [64, 64, 0], [45, -24, -24], [34, -34, 0], [112, 112, 112], [24, -45, -45], [45, 45, -24], [0, -32, 32], [24, -24, 45], [0, 96, 96], [45, -24, 24], [24, -45, -24], [-24, -45, 24], [0, -64, 0], [96, 0, 0], [128, 128, 128], [64, 0, 64], [144, 144, 144], [96, 96, 0], [-36, -36, 36], [45, -24, -45], [45, -45, -24], [0, 0, -96], [0, 128, 128], [0, 96, 0], [45, 24, -45], [-128, 0, 0], [24, -45, 24], [-45, 24, -45], [64, 0, -64], [64, -64, -64], [96, 0, 96], [45, -45, 24], [24, 45, -45], [64, 64, -64], [128, 128, 0], [0, 0, -128], [-24, 45, -45]]

-> jxm_pal_value(pal, pw, index, c, bd)
  if index < 0
    return 0 if c >= 3
    index = 0 - (index + 1)
    index = index % 143
    r = JXM_DELTA_PAL[(index + 1) >> 1][c]
    r = 0 - r if (index & 1) == 0
    r = r * (1 << (bd - 8)) if bd > 8
    return r
  if index >= pw && index < pw + 64
    return 0 if c >= 3
    index -= pw
    index = index >> (c * 2)
    return ((index % 4) * ((1 << bd) - 1)) / 4 + (1 << (bd - 3 > 0 ? bd - 3 : 0))
  if index >= pw + 64
    return 0 if c >= 3
    index -= pw + 64
    index = index / 5 if c == 1
    index = index / 25 if c == 2
    return ((index % 5) * ((1 << bd) - 1)) / 4
  pal[c * pw + index]

-> jxm_inv_palette(img, bc, nc, ncol, ndel, dp)
  pal_ch = img.ch[0]
  nb = pal_ch.h
  pw = pal_ch.w
  c0 = bc + 1
  idxc = img.ch[c0]
  w = idxc.w
  h = idxc.h
  bd = img.bitdepth
  bd = 24 if bd > 24
  # build output channels
  outs = []
  i = 0
  while i < nb
    outs.push(JxCh.new(w, h, idxc.hs, idxc.vs))
    i += 1
  if w > 0 && h > 0
    n = w * h
    # precompute palette values for all in-range indices; others computed per pixel
    pal = pal_ch.d
    c = 0
    while c < nb
      od = outs[c].d
      jxm_pal_fill(img, pal, pw, nb, c, idxc.d, od, n, bd, ndel, dp, w, h, nb == 1 && ndel == 0 && dp == 0)
      c += 1
  # replace: remove palette channel 0, index channel -> nb channels
  newch = []
  i = 1
  while i < img.ch.size
    if i == c0
      outs.each ->(o)
        newch.push(o)
    else
      newch.push(img.ch[i])
    i += 1
  img.ch = newch
  if c0 >= img.nb_meta
    img.nb_meta = img.nb_meta - 1
  else
    img.nb_meta = img.nb_meta - (2 - nb)

-> jxm_pal_fill(img, pal, pw, nb, c, idx, od, n, bd, ndel, dp, w, h, clampit)
  # table for indices in [-1024, pw + 64*?): compute lazily via a cache
  lut_lo = -1024
  lut_hi = pw + 64 + 125
  lut = i32[lut_hi - lut_lo]
  k = lut_lo
  while k < lut_hi
    lut[k - lut_lo] = jxm_pal_value(pal, pw, k, c, bd)
    k += 1
  if ndel == 0 && dp == 0
    jxm_pal_map(idx, od, n, lut, lut_lo, lut_hi, clampit ? 1 : 0, pw)
    return 0
  # delta palette: prediction from already reconstructed neighbours
  vals = i32[n]
  i = 0
  while i < n
    v = idx[i]
    vals[i] = (v >= lut_lo && v < lut_hi) ? lut[v - lut_lo] : jxm_pal_value(pal, pw, v, c, bd)
    i += 1
  jxm_delta_pred(idx, vals, od, w, h, ndel, dp, img.wpp, jxm_div24())
  0

-> jxm_pal_map(idx, od, n, lut, lo, hi, clampit, pw) (i32[] i32[] i64 i32[] i64 i64 i64 i64) i64
  i = 0 ## i64
  while i < n
    v = idx[i] ## i64
    if clampit == 1
      v = 0 if v < 0
      v = pw - 1 if v >= pw
    if v >= lo && v < hi
      od[i] = lut[v - lo]
    else
      od[i] = 0
    i += 1
  0

# Delta-palette reconstruction: out = palette value (+ prediction when the
# index is a delta entry), predicting from out's own neighbours.
-> jxm_delta_pred(idx, vals, d, w, h, ndel, pred, wpp, div) (i32[] i32[] i32[] i64 i64 i64 i64 i64[] i64[]) i64
  use_wp = 0 ## i64
  use_wp = 1 if pred == 6
  err = i64[1]
  if use_wp == 1
    err = i64[w * 2 * 5 + 10]
  y = 0 ## i64
  while y < h
    row = y * w
    erow = (y & 1) * w
    nerow = ((y & 1) ^ 1) * w
    x = 0 ## i64
    while x < w
      i = row + x
      pw = 0 ## i64
      pn = 0 ## i64
      if x > 0
        pw = d[i - 1]
      elsif y > 0
        pw = d[i - w]
      if y > 0
        pn = d[i - w]
      else
        pn = pw
      pnw = pw
      if x > 0 && y > 0
        pnw = d[i - w - 1]
      pne = pn
      if x + 1 < w && y > 0
        pne = d[i - w + 1]
      pnn = pn
      if y > 1
        pnn = d[i - 2 * w]
      pnee = pne
      if x + 2 < w && y > 0
        pnee = d[i - w + 2]
      pww = pw
      if x > 1
        pww = d[i - 2]
      pr0 = 0 ## i64
      pr1 = 0 ## i64
      pr2 = 0 ## i64
      pr3 = 0 ## i64
      pr4 = 0 ## i64
      if use_wp == 1
        ew = (erow + x - 1) * 5
        en = (nerow + x) * 5
        enw = (nerow + x - 1) * 5
        ene = (nerow + x + 1) * 5
        eww = (erow + x - 2) * 5
        tw = 0 ## i64
        tn = 0 ## i64
        if x > 0
          tw = err[ew + 4]
        if y > 0
          tn = err[en + 4]
        tnw = tn
        if x > 0 && y > 0
          tnw = err[enw + 4]
        tne = tn
        if x + 1 < w && y > 0
          tne = err[ene + 4]
        pr0 = (pw + pne - pn) * 8
        pr1 = pn * 8 - (((tw + tn + tne) * wpp[0]) >> 5)
        pr2 = pw * 8 - (((tw + tn + tnw) * wpp[1]) >> 5)
        pr3 = pn * 8 - ((tnw * wpp[2] + tn * wpp[3] + tne * wpp[4] + (pnn - pn) * 8 * wpp[5] + (pnw - pw) * 8 * wpp[6]) >> 5)
        wts = i64[4]
        k = 0 ## i64
        while k < 4
          e_w = 0 ## i64
          e_n = 0 ## i64
          e_ww = 0 ## i64
          if x > 0
            e_w = err[ew + k]
          if y > 0
            e_n = err[en + k]
          e_nw = e_n
          if x > 0 && y > 0
            e_nw = err[enw + k]
          e_ne = e_n
          if x + 1 < w && y > 0
            e_ne = err[ene + k]
          if x > 1
            e_ww = err[eww + k]
          e_w2 = 0 ## i64
          if x + 1 >= w
            e_w2 = e_w
          es_ = (e_n + e_w + e_nw + e_ww + e_ne + e_w2) & 0xFFFFFFFF
          sh = jxm_flog2(es_ + 1) - 5
          sh = 0 if sh < 0
          wts[k] = 4 + ((wpp[7 + k] * div[es_ >> sh]) >> sh)
          k += 1
        logw = jxm_flog2(wts[0] + wts[1] + wts[2] + wts[3]) - 4
        wsum = 0 ## i64
        sum = 0 ## i64
        k = 0
        while k < 4
          wts[k] = wts[k] >> logw
          wsum += wts[k]
          k += 1
        sum = pr0 * wts[0] + pr1 * wts[1] + pr2 * wts[2] + pr3 * wts[3]
        pr4 = ((sum + (wsum >> 1) - 1) * div[wsum - 1]) >> 24
        if ((tn ^ tw) | (tn ^ tnw)) <= 0
          lo = pw
          lo = pn if pn < lo
          lo = pne if pne < lo
          hi = pw
          hi = pn if pn > hi
          hi = pne if pne > hi
          pr4 = lo * 8 if pr4 < lo * 8
          pr4 = hi * 8 if pr4 > hi * 8
      val = vals[i] ## i64
      if idx[i] < ndel
        pv = 0 ## i64
        if pred == 1
          pv = pw
        elsif pred == 2
          pv = pn
        elsif pred == 3
          pv = (pw + pn) / 2
        elsif pred == 4
          a1 = pn - pnw
          a1 = 0 - a1 if a1 < 0
          a2 = pw - pnw
          a2 = 0 - a2 if a2 < 0
          if a1 < a2
            pv = pw
          else
            pv = pn
        elsif pred == 5
          glo = pw
          ghi = pn
          if pn < pw
            glo = pn
            ghi = pw
          pv = pw + pn - pnw
          pv = glo if pv < glo
          pv = ghi if pv > ghi
        elsif pred == 6
          pv = (pr4 + 3) >> 3
        elsif pred == 7
          pv = pne
        elsif pred == 8
          pv = pnw
        elsif pred == 9
          pv = pww
        elsif pred == 10
          pv = (pw + pnw) / 2
        elsif pred == 11
          pv = (pn + pnw) / 2
        elsif pred == 12
          pv = (pn + pne) / 2
        elsif pred == 13
          pv = (6 * pn - 2 * pnn + 7 * pw + pww + pnee + 3 * pne + 8) / 16
        val = val + pv
      d[i] = val
      if use_wp == 1
        val = d[i]
        eb = (erow + x) * 5
        v8 = val * 8
        e0 = pr0 - v8
        e0 = 0 - e0 if e0 < 0
        err[eb] = ((e0 + 3) >> 3) & 0xFFFFFFFF
        e0 = pr1 - v8
        e0 = 0 - e0 if e0 < 0
        err[eb + 1] = ((e0 + 3) >> 3) & 0xFFFFFFFF
        e0 = pr2 - v8
        e0 = 0 - e0 if e0 < 0
        err[eb + 2] = ((e0 + 3) >> 3) & 0xFFFFFFFF
        e0 = pr3 - v8
        e0 = 0 - e0 if e0 < 0
        err[eb + 3] = ((e0 + 3) >> 3) & 0xFFFFFFFF
        te = (pr4 - v8 + 2147483648) & 0xFFFFFFFF
        err[eb + 4] = te - 2147483648
      x += 1
    y += 1
  0

-> jxm_tendency(b, a, n) (i64 i64 i64) i64
  diff = 0 ## i64
  if b >= a && a >= n
    diff = (4 * b - 3 * n - a + 6) / 12
    if diff - (diff & 1) > 2 * (b - a)
      diff = 2 * (b - a) + 1
    if diff + (diff & 1) > 2 * (a - n)
      diff = 2 * (a - n)
  elsif b <= a && a <= n
    diff = (4 * b - 3 * n - a - 6) / 12
    if diff + (diff & 1) < 2 * (b - a)
      diff = 2 * (b - a) - 1
    if diff - (diff & 1) < 2 * (a - n)
      diff = 2 * (a - n)
  diff

-> jxm_hsq(avg, res, out, aw, rw, h, ow) (i32[] i32[] i32[] i64 i64 i64 i64) i64
  y = 0 ## i64
  while y < h
    ar = y * aw
    rr = y * rw
    orow = y * ow
    x = 0 ## i64
    while x < rw
      a = avg[ar + x] ## i64
      na = a
      if x + 1 < aw
        na = avg[ar + x + 1]
      left = a
      if x > 0
        left = out[orow + (x << 1) - 1]
      diff = res[rr + x] + jxm_tendency(left, a, na)
      av = a + (diff / 2)
      out[orow + (x << 1)] = av
      out[orow + (x << 1) + 1] = av - diff
      x += 1
    if (ow & 1) == 1
      out[orow + ow - 1] = avg[ar + aw - 1]
    y += 1
  0

-> jxm_vsq(avg, res, out, w, ah, rh) (i32[] i32[] i32[] i64 i64 i64) i64
  y = 0 ## i64
  while y < rh
    x = 0 ## i64
    while x < w
      a = avg[y * w + x] ## i64
      na = a
      if y + 1 < ah
        na = avg[(y + 1) * w + x]
      top = a
      if y > 0
        top = out[((y << 1) - 1) * w + x]
      diff = res[y * w + x] + jxm_tendency(top, a, na)
      o = a + (diff / 2)
      out[(y << 1) * w + x] = o
      out[((y << 1) + 1) * w + x] = o - diff
      x += 1
    y += 1
  oh = ah + rh
  if (oh & 1) == 1
    y = ah - 1
    x = 0
    while x < w
      out[(y << 1) * w + x] = avg[y * w + x]
      x += 1
  0

-> jxm_inv_squeeze(img, sqs)
  i = sqs.size - 1
  while i >= 0
    sq = sqs[i]
    hz = sq[0]
    ip = sq[1]
    bc = sq[2]
    ec = bc + sq[3] - 1
    offset = 0
    if ip == 1
      offset = ec + 1
    else
      offset = img.ch.size + bc - ec - 1
    if bc < img.nb_meta
      img.nb_meta = img.nb_meta - sq[3]
    c = bc
    while c <= ec
      rc = offset + c - bc
      chin = img.ch[c]
      res = img.ch[rc]
      if hz == 1
        nhs = chin.hs
        nhs = chin.hs - 1 if chin.hs > 0
        if res.w == 0
          chin.hs = nhs
        else
          out = JxCh.new(chin.w + res.w, chin.h, nhs, chin.vs)
          jxm_hsq(chin.d, res.d, out.d, chin.w, res.w, chin.h, out.w) if res.h > 0
          img.ch[c] = out
      else
        nvs = chin.vs
        nvs = chin.vs - 1 if chin.vs > 0
        if res.h == 0
          chin.vs = nvs
        else
          out = JxCh.new(chin.w, chin.h + res.h, chin.hs, nvs)
          jxm_vsq(chin.d, res.d, out.d, chin.w, chin.h, res.h) if res.w > 0
          img.ch[c] = out
      c += 1
    k = 0
    while k <= ec - bc
      img.ch.delete_at(offset)
      k += 1
    i -= 1
  img
