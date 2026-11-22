# core/codec/image/jp2_t1 — JPEG 2000 tier 1: the MQ arithmetic decoder and EBCOT
# code-block decoding (ITU-T T.800 Annexes C and D).
#
# A code-block is decoded from its codeword segments into signed magnitudes
# carrying one extra fraction bit: bit plane p is stored at bit p+1, so a
# coefficient that became significant (or was refined) at plane p sits at the
# midpoint of its uncertainty interval. Callers shift right by one for
# reversible data and multiply by step/2 for irreversible data.
#
# Mode switches (code-block style bits): 1 BYPASS (raw passes after the
# fourth bit plane), 2 RESET (contexts reset after every pass), 4 RESTART
# (each pass is its own segment — handled by the segment table), 8 VCAUSAL
# (stripe-causal contexts), 16 ERTERM (predictable termination; nothing to
# do when decoding), 32 SEGSYM (a segmentation symbol after each cleanup).
#
# Flags per sample (i64, with a one-sample border): 1 significant,
# 2 negative, 4 coded in the current plane's significance pass,
# 8 refined at least once; bits 4-11 say which neighbours (W E N S NW NE
# SW SE) are significant and bits 12-15 which of W E N S are negative, so a
# context is one load. They are kept up to date as samples become
# significant.
#
# The MQ state lives in s: s[0]=A s[1]=C s[2]=CT s[3]=BP s[4]=segment end,
# s[5]/s[6] = raw-mode byte and bit count. Contexts are cx[k] = I*2 + MPS.

J2_QE_RAW = [0x5601, 1, 1, 1, 0x3401, 2, 6, 0, 0x1801, 3, 9, 0, 0x0AC1, 4, 12, 0,
  0x0521, 5, 29, 0, 0x0221, 38, 33, 0, 0x5601, 7, 6, 1, 0x5401, 8, 14, 0,
  0x4801, 9, 14, 0, 0x3801, 10, 14, 0, 0x3001, 11, 17, 0, 0x2401, 12, 18, 0,
  0x1C01, 13, 20, 0, 0x1601, 29, 21, 0, 0x5601, 15, 14, 1, 0x5401, 16, 14, 0,
  0x5101, 17, 15, 0, 0x4801, 18, 16, 0, 0x3801, 19, 17, 0, 0x3401, 20, 18, 0,
  0x3001, 21, 19, 0, 0x2801, 22, 19, 0, 0x2401, 23, 20, 0, 0x2201, 24, 21, 0,
  0x1C01, 25, 22, 0, 0x1801, 26, 23, 0, 0x1601, 27, 24, 0, 0x1401, 28, 25, 0,
  0x1201, 29, 26, 0, 0x1101, 30, 27, 0, 0x0AC1, 31, 28, 0, 0x09C1, 32, 29, 0,
  0x08A1, 33, 30, 0, 0x0521, 34, 31, 0, 0x0441, 35, 32, 0, 0x02A1, 36, 33, 0,
  0x0221, 37, 34, 0, 0x0141, 38, 35, 0, 0x0111, 39, 36, 0, 0x0085, 40, 37, 0,
  0x0049, 41, 38, 0, 0x0025, 42, 39, 0, 0x0015, 43, 40, 0, 0x0009, 44, 41, 0,
  0x0005, 45, 42, 0, 0x0001, 45, 43, 0, 0x5601, 46, 46, 0]

# (h+1)*3 + (v+1) -> context*2 + xor bit (Table D.3)
J2_SIGN_RAW = [27, 25, 23, 21, 18, 20, 22, 24, 26]

J2_T1_STATE = [nil]

-> j2_zc_label(o, h0, v0, d)
  h = h0
  v = v0
  if o == 1
    h = v0
    v = h0
  if o == 3
    hv = h + v
    return 8 if d >= 3
    if d == 2
      return 7 if hv >= 1
      return 6
    if d == 1
      return 5 if hv >= 2
      return 4 if hv == 1
      return 3
    return 2 if hv >= 2
    return 1 if hv == 1
    return 0
  return 8 if h == 2
  if h == 1
    return 7 if v >= 1
    return 6 if d >= 1
    return 5
  return 4 if v == 2
  return 3 if v == 1
  return 2 if d >= 2
  return 1 if d == 1
  0

# tb layout: [0, 188) MQ table (qe, nmps, nlps, switch) per state;
# [256, 1280) zero-coding label by orientation*256 + neighbour mask
# (bits W E N S NW NE SW SE); [1280, 1289) sign context by (h, v);
# [1300, 1556) sign context by neighbour significance/sign bits.
-> j2_tables
  if J2_T1_STATE[0] == nil
    tb = i64[1600]
    i = 0
    while i < J2_QE_RAW.size
      tb[i] = J2_QE_RAW[i]
      i += 1
    o = 0
    while o < 4
      m = 0
      while m < 256
        h = (m & 1) + ((m >> 1) & 1)
        v = ((m >> 2) & 1) + ((m >> 3) & 1)
        d = ((m >> 4) & 1) + ((m >> 5) & 1) + ((m >> 6) & 1) + ((m >> 7) & 1)
        tb[256 + o * 256 + m] = j2_zc_label(o, h, v, d)
        m += 1
      o += 1
    i = 0
    while i < 9
      tb[1280 + i] = J2_SIGN_RAW[i]
      i += 1
    # sign context by sample flags: bits 0-3 W E N S significant, 4-7 negative
    i = 0
    while i < 256
      hc = 0
      vv = 0
      hc += 1 - 2 * ((i >> 4) & 1) if (i & 1) != 0
      hc += 1 - 2 * ((i >> 5) & 1) if (i & 2) != 0
      vv += 1 - 2 * ((i >> 6) & 1) if (i & 4) != 0
      vv += 1 - 2 * ((i >> 7) & 1) if (i & 8) != 0
      hc = 1 if hc > 1
      hc = -1 if hc < -1
      vv = 1 if vv > 1
      vv = -1 if vv < -1
      tb[1300 + i] = J2_SIGN_RAW[(hc + 1) * 3 + vv + 1]
      i += 1
    J2_T1_STATE[0] = tb
  J2_T1_STATE[0]

-> j2_ctx_reset(cx) (i64[]) i64
  k = 0 ## i64
  while k < 19
    cx[k] = 0
    k += 1
  cx[0] = 4 << 1
  cx[17] = 3 << 1
  cx[18] = 46 << 1
  0

-> j2_bytein(s, d) (i64[] u8[]) i64
  bp = s[3]
  e = s[4]
  b = 0xFF ## i64
  b = d[bp] if bp < e
  b1 = 0xFF ## i64
  b1 = d[bp + 1] if bp + 1 < e
  if b == 0xFF
    if b1 > 0x8F
      s[1] = s[1] + 0xFF00
      s[2] = 8
    else
      s[3] = bp + 1
      s[1] = s[1] + (b1 << 9)
      s[2] = 7
  else
    s[3] = bp + 1
    s[1] = s[1] + (b1 << 8)
    s[2] = 8
  0

-> j2_mq_init(s, d, start, e) (i64[] u8[] i64 i64) i64
  s[3] = start
  s[4] = e
  b = 0xFF ## i64
  b = d[start] if start < e
  s[1] = b << 16
  s[2] = 0
  j2_bytein(s, d)
  s[1] = (s[1] << 7) & 0xFFFFFFFF
  s[2] = s[2] - 7
  s[0] = 0x8000
  0

-> j2_mqd(s, cx, d, tb, k) (i64[] i64[] u8[] i64[] i64) i64
  st = cx[k]
  i4 = (st >> 1) * 4
  mps = st & 1
  qe = tb[i4]
  a = s[0] - qe
  c = s[1]
  r = 0 ## i64
  if (c >> 16) < qe
    if a < qe
      r = mps
      cx[k] = (tb[i4 + 1] << 1) | mps
    else
      r = 1 - mps
      nm = mps
      nm = 1 - mps if tb[i4 + 3] == 1
      cx[k] = (tb[i4 + 2] << 1) | nm
    a = qe
  else
    c = c - (qe << 16)
    if (a & 0x8000) != 0
      s[0] = a
      s[1] = c
      return mps
    if a < qe
      r = 1 - mps
      nm = mps
      nm = 1 - mps if tb[i4 + 3] == 1
      cx[k] = (tb[i4 + 2] << 1) | nm
    else
      r = mps
      cx[k] = (tb[i4 + 1] << 1) | mps
  ct = s[2]
  while (a & 0x8000) == 0
    if ct == 0
      s[1] = c
      j2_bytein(s, d)
      c = s[1]
      ct = s[2]
    a = a << 1
    c = (c << 1) & 0xFFFFFFFF
    ct -= 1
  s[0] = a
  s[1] = c
  s[2] = ct
  r

-> j2_rawbit(s, d) (i64[] u8[]) i64
  ct = s[6]
  c = s[5]
  if ct == 0
    bp = s[3]
    b = 0xFF ## i64
    b = d[bp] if bp < s[4]
    if c == 0xFF
      if b > 0x8F
        c = 0xFF
        ct = 8
      else
        c = b
        s[3] = bp + 1
        ct = 7
    else
      c = b
      s[3] = bp + 1
      ct = 8
  ct -= 1
  s[5] = c
  s[6] = ct
  (c >> ct) & 1

-> j2_nmask(fl, p, fw, south) (i64[] i64 i64 i64) i64
  m = (fl[p - 1] & 1) | ((fl[p + 1] & 1) << 1) | ((fl[p - fw] & 1) << 2) | ((fl[p - fw - 1] & 1) << 4) | ((fl[p - fw + 1] & 1) << 5)
  if south == 1
    m = m | ((fl[p + fw] & 1) << 3) | ((fl[p + fw - 1] & 1) << 6) | ((fl[p + fw + 1] & 1) << 7)
  m

-> j2_sc(f) (i64) i64
  return 0 if (f & 1) == 0
  return -1 if (f & 2) != 0
  1

# The call-per-symbol helpers below (j2_mqd, j2_sgn, j2_spp, j2_mrp, j2_cup)
# are the reference formulation; the *_mq passes inline the MQ decoder for
# speed and the plain ones are only used for raw (BYPASS) passes.

# Decode one sign bit; returns 1 for negative.
-> j2_sgn(s, cx, d, tb, fl, p, fw, south, raw) (i64[] i64[] u8[] i64[] i64[] i64 i64 i64 i64) i64
  if raw == 1
    return j2_rawbit(s, d)
  hc = j2_sc(fl[p - 1]) + j2_sc(fl[p + 1])
  hc = 1 if hc > 1
  hc = -1 if hc < -1
  vv = j2_sc(fl[p - fw])
  vv = vv + j2_sc(fl[p + fw]) if south == 1
  vv = 1 if vv > 1
  vv = -1 if vv < -1
  e = tb[1280 + (hc + 1) * 3 + vv + 1]
  j2_mqd(s, cx, d, tb, e >> 1) ^ (e & 1)

# Mark sample p significant (sign sg) and record it in its neighbours' flags.
-> j2_setsig(fl, p, fw, sg, extra) (i64[] i64 i64 i64 i64) i64
  fl[p] = fl[p] | extra | (sg << 1)
  fl[p - 1] = fl[p - 1] | 32 | (sg << 13)
  fl[p + 1] = fl[p + 1] | 16 | (sg << 12)
  fl[p - fw] = fl[p - fw] | 128 | (sg << 15)
  fl[p + fw] = fl[p + fw] | 64 | (sg << 14)
  fl[p - fw - 1] = fl[p - fw - 1] | 2048
  fl[p - fw + 1] = fl[p - fw + 1] | 1024
  fl[p + fw - 1] = fl[p + fw - 1] | 512
  fl[p + fw + 1] = fl[p + fw + 1] | 256
  0

-> j2_spp(s, cx, d, tb, v, fl, w, h, q, ob, vc, raw) (i64[] i64[] u8[] i64[] i64[] i64[] i64 i64 i64 i64 i64 i64) i64
  fw = w + 2
  oh = (1 << q) | (1 << (q - 1))
  zb = 256 + ob * 256
  y0 = 0 ## i64
  while y0 < h
    ye = y0 + 4
    ye = h if ye > h
    x = 0 ## i64
    while x < w
      y = y0
      while y < ye
        pj = (y + 1) * fw + x + 1
        f = fl[pj]
        if (f & 1) == 0
          south = 1 ## i64
          south = 0 if vc == 1 && (y & 3) == 3
          m = j2_nmask(fl, pj, fw, south)
          if m != 0
            bit = 0 ## i64
            if raw == 1
              bit = j2_rawbit(s, d)
            else
              bit = j2_mqd(s, cx, d, tb, tb[zb + m])
            if bit == 1
              sg = j2_sgn(s, cx, d, tb, fl, pj, fw, south, raw)
              v[y * w + x] = oh
              j2_setsig(fl, pj, fw, sg, 5)
            else
              fl[pj] = f | 4
        y += 1
      x += 1
    y0 += 4
  0

-> j2_mrp(s, cx, d, tb, v, fl, w, h, q, vc, raw) (i64[] i64[] u8[] i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  fw = w + 2
  half = 1 << (q - 1)
  y0 = 0 ## i64
  while y0 < h
    ye = y0 + 4
    ye = h if ye > h
    x = 0 ## i64
    while x < w
      y = y0
      while y < ye
        pj = (y + 1) * fw + x + 1
        f = fl[pj]
        if (f & 5) == 1
          bit = 0 ## i64
          if raw == 1
            bit = j2_rawbit(s, d)
          else
            c = 14 ## i64
            if (f & 8) != 0
              c = 16
            else
              south = 1 ## i64
              south = 0 if vc == 1 && (y & 3) == 3
              c = 15 if j2_nmask(fl, pj, fw, south) != 0
            bit = j2_mqd(s, cx, d, tb, c)
          i = y * w + x
          if bit == 1
            v[i] = v[i] + half
          else
            v[i] = v[i] - half
          fl[pj] = f | 8
        y += 1
      x += 1
    y0 += 4
  0

# ---- MQ-inlined passes. Every decode site is the same MQ DECODE (Annex C)
# written out in place, because calls between typed functions box their
# scalar arguments; keep the copies identical when changing one. ----

# Significance propagation pass (MQ-coded), MQ decoder inlined.
-> j2_spp_mq(s, cx, d, tb, v, fl, w, h, q, ob, vc) (i64[] i64[] u8[] i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  a = s[0]
  c = s[1]
  ct = s[2]
  bp = s[3]
  one = 1 ## i64
  fw = w + 2
  oh = (one << q) | (one << (q - 1))
  zb = 256 + ob * 256
  y0 = 0 ## i64
  while y0 < h
    ye = y0 + 4
    ye = h if ye > h
    x = 0 ## i64
    while x < w
      y = y0
      pj = (y0 + 1) * fw + x + 1
      if ye - y0 == 4
        # nothing in this stripe column has a significant neighbour
        y = ye if ((fl[pj] | fl[pj + fw] | fl[pj + 2 * fw] | fl[pj + 3 * fw]) & 0xFF0) == 0
      while y < ye
        f = fl[pj]
        if (f & 1) == 0
          south = 1 ## i64
          south = 0 if vc == 1 && (y & 3) == 3
          m = (fl[pj] >> 4) & 255
          m = m & 0x37 if south == 0
          if m != 0
            k = tb[zb + m]
            bit = 0 ## i64
            st = cx[k]
            i4 = (st >> 1) << 2
            mps = st & 1
            qe = tb[i4]
            a = a - qe
            rn = 0 ## i64
            if (c >> 16) < qe
              if a < qe
                bit = mps
                cx[k] = (tb[i4 + 1] << 1) | mps
              else
                bit = 1 - mps
                cx[k] = (tb[i4 + 2] << 1) | (mps ^ tb[i4 + 3])
              a = qe
              rn = 1
            else
              c = c - (qe << 16)
              if (a & 0x8000) == 0
                if a < qe
                  bit = 1 - mps
                  cx[k] = (tb[i4 + 2] << 1) | (mps ^ tb[i4 + 3])
                else
                  bit = mps
                  cx[k] = (tb[i4 + 1] << 1) | mps
                rn = 1
              else
                bit = mps
            if rn == 1
              while (a & 0x8000) == 0
                if ct == 0
                  s[1] = c
                  s[3] = bp
                  j2_bytein(s, d)
                  c = s[1]
                  ct = s[2]
                  bp = s[3]
                a = a << 1
                c = (c << 1) & 0xFFFFFFFF
                ct -= 1
            if bit == 1
              sg = 0 ## i64
              fa = fl[pj]
              sx = ((fa >> 4) & 15) | ((fa >> 8) & 0xF0)
              sx = sx & 0x77 if south == 0
              se = tb[1300 + sx]
              sk = se >> 1
              st = cx[sk]
              i4 = (st >> 1) << 2
              mps = st & 1
              qe = tb[i4]
              a = a - qe
              rn = 0 ## i64
              if (c >> 16) < qe
                if a < qe
                  sg = mps
                  cx[sk] = (tb[i4 + 1] << 1) | mps
                else
                  sg = 1 - mps
                  cx[sk] = (tb[i4 + 2] << 1) | (mps ^ tb[i4 + 3])
                a = qe
                rn = 1
              else
                c = c - (qe << 16)
                if (a & 0x8000) == 0
                  if a < qe
                    sg = 1 - mps
                    cx[sk] = (tb[i4 + 2] << 1) | (mps ^ tb[i4 + 3])
                  else
                    sg = mps
                    cx[sk] = (tb[i4 + 1] << 1) | mps
                  rn = 1
                else
                  sg = mps
              if rn == 1
                while (a & 0x8000) == 0
                  if ct == 0
                    s[1] = c
                    s[3] = bp
                    j2_bytein(s, d)
                    c = s[1]
                    ct = s[2]
                    bp = s[3]
                  a = a << 1
                  c = (c << 1) & 0xFFFFFFFF
                  ct -= 1
              sg = sg ^ (se & 1)
              v[y * w + x] = oh
              fl[pj] = f | 5 | (sg << 1)
              fl[pj - 1] = fl[pj - 1] | 32 | (sg << 13)
              fl[pj + 1] = fl[pj + 1] | 16 | (sg << 12)
              fl[pj - fw] = fl[pj - fw] | 128 | (sg << 15)
              fl[pj + fw] = fl[pj + fw] | 64 | (sg << 14)
              fl[pj - fw - 1] = fl[pj - fw - 1] | 2048
              fl[pj - fw + 1] = fl[pj - fw + 1] | 1024
              fl[pj + fw - 1] = fl[pj + fw - 1] | 512
              fl[pj + fw + 1] = fl[pj + fw + 1] | 256
            else
              fl[pj] = f | 4
        y += 1
        pj += fw
      x += 1
    y0 += 4
  s[0] = a
  s[1] = c
  s[2] = ct
  s[3] = bp
  0

# Magnitude refinement pass (MQ-coded).
-> j2_mrp_mq(s, cx, d, tb, v, fl, w, h, q, ob, vc) (i64[] i64[] u8[] i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  a = s[0]
  c = s[1]
  ct = s[2]
  bp = s[3]
  one = 1 ## i64
  fw = w + 2
  half = one << (q - 1)
  y0 = 0 ## i64
  while y0 < h
    ye = y0 + 4
    ye = h if ye > h
    x = 0 ## i64
    while x < w
      y = y0
      pj = (y0 + 1) * fw + x + 1
      if ye - y0 == 4
        y = ye if ((fl[pj] | fl[pj + fw] | fl[pj + 2 * fw] | fl[pj + 3 * fw]) & 1) == 0
      while y < ye
        f = fl[pj]
        if (f & 5) == 1
          k = 14 ## i64
          if (f & 8) != 0
            k = 16
          else
            south = 1 ## i64
            south = 0 if vc == 1 && (y & 3) == 3
            m = (fl[pj] >> 4) & 255
            m = m & 0x37 if south == 0
            k = 15 if m != 0
          bit = 0 ## i64
          st = cx[k]
          i4 = (st >> 1) << 2
          mps = st & 1
          qe = tb[i4]
          a = a - qe
          rn = 0 ## i64
          if (c >> 16) < qe
            if a < qe
              bit = mps
              cx[k] = (tb[i4 + 1] << 1) | mps
            else
              bit = 1 - mps
              cx[k] = (tb[i4 + 2] << 1) | (mps ^ tb[i4 + 3])
            a = qe
            rn = 1
          else
            c = c - (qe << 16)
            if (a & 0x8000) == 0
              if a < qe
                bit = 1 - mps
                cx[k] = (tb[i4 + 2] << 1) | (mps ^ tb[i4 + 3])
              else
                bit = mps
                cx[k] = (tb[i4 + 1] << 1) | mps
              rn = 1
            else
              bit = mps
          if rn == 1
            while (a & 0x8000) == 0
              if ct == 0
                s[1] = c
                s[3] = bp
                j2_bytein(s, d)
                c = s[1]
                ct = s[2]
                bp = s[3]
              a = a << 1
              c = (c << 1) & 0xFFFFFFFF
              ct -= 1
          i = y * w + x
          if bit == 1
            v[i] = v[i] + half
          else
            v[i] = v[i] - half
          fl[pj] = f | 8
        y += 1
        pj += fw
      x += 1
    y0 += 4
  s[0] = a
  s[1] = c
  s[2] = ct
  s[3] = bp
  0

# Cleanup pass, with the run-length mode for empty stripe columns.
-> j2_cup_mq(s, cx, d, tb, v, fl, w, h, q, ob, vc) (i64[] i64[] u8[] i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  a = s[0]
  c = s[1]
  ct = s[2]
  bp = s[3]
  one = 1 ## i64
  fw = w + 2
  oh = (one << q) | (one << (q - 1))
  zb = 256 + ob * 256
  y0 = 0 ## i64
  while y0 < h
    ye = y0 + 4
    ye = h if ye > h
    x = 0 ## i64
    while x < w
      p = (y0 + 1) * fw + x + 1
      y = y0
      forced = -1 ## i64
      if ye - y0 == 4
        rl = 1 ## i64
        j = 0 ## i64
        while j < 4 && rl == 1
          pk = p + j * fw
          south = 1 ## i64
          south = 0 if vc == 1 && j == 3
          fk = fl[pk]
          fk = fk & 0xF37F if south == 0
          rl = 0 if (fk & 0xFF5) != 0
          j += 1
        if rl == 1
          bit = 0 ## i64
          k = 17 ## i64
          st = cx[k]
          i4 = (st >> 1) << 2
          mps = st & 1
          qe = tb[i4]
          a = a - qe
          rn = 0 ## i64
          if (c >> 16) < qe
            if a < qe
              bit = mps
              cx[k] = (tb[i4 + 1] << 1) | mps
            else
              bit = 1 - mps
              cx[k] = (tb[i4 + 2] << 1) | (mps ^ tb[i4 + 3])
            a = qe
            rn = 1
          else
            c = c - (qe << 16)
            if (a & 0x8000) == 0
              if a < qe
                bit = 1 - mps
                cx[k] = (tb[i4 + 2] << 1) | (mps ^ tb[i4 + 3])
              else
                bit = mps
                cx[k] = (tb[i4 + 1] << 1) | mps
              rn = 1
            else
              bit = mps
          if rn == 1
            while (a & 0x8000) == 0
              if ct == 0
                s[1] = c
                s[3] = bp
                j2_bytein(s, d)
                c = s[1]
                ct = s[2]
                bp = s[3]
              a = a << 1
              c = (c << 1) & 0xFFFFFFFF
              ct -= 1
          if bit == 0
            y = ye
          else
            r = 0 ## i64
            j = 0
            while j < 2
              k = 18
              st = cx[k]
              i4 = (st >> 1) << 2
              mps = st & 1
              qe = tb[i4]
              a = a - qe
              rn = 0 ## i64
              if (c >> 16) < qe
                if a < qe
                  bit = mps
                  cx[k] = (tb[i4 + 1] << 1) | mps
                else
                  bit = 1 - mps
                  cx[k] = (tb[i4 + 2] << 1) | (mps ^ tb[i4 + 3])
                a = qe
                rn = 1
              else
                c = c - (qe << 16)
                if (a & 0x8000) == 0
                  if a < qe
                    bit = 1 - mps
                    cx[k] = (tb[i4 + 2] << 1) | (mps ^ tb[i4 + 3])
                  else
                    bit = mps
                    cx[k] = (tb[i4 + 1] << 1) | mps
                  rn = 1
                else
                  bit = mps
              if rn == 1
                while (a & 0x8000) == 0
                  if ct == 0
                    s[1] = c
                    s[3] = bp
                    j2_bytein(s, d)
                    c = s[1]
                    ct = s[2]
                    bp = s[3]
                  a = a << 1
                  c = (c << 1) & 0xFFFFFFFF
                  ct -= 1
              r = (r << 1) | bit
              j += 1
            y = y0 + r
            forced = y
      pj = (y + 1) * fw + x + 1
      while y < ye
        f = fl[pj]
        if (f & 5) == 0
          south = 1 ## i64
          south = 0 if vc == 1 && (y & 3) == 3
          bit = 1 ## i64
          if y != forced
            m = (fl[pj] >> 4) & 255
            m = m & 0x37 if south == 0
            k = tb[zb + m]
            st = cx[k]
            i4 = (st >> 1) << 2
            mps = st & 1
            qe = tb[i4]
            a = a - qe
            rn = 0 ## i64
            if (c >> 16) < qe
              if a < qe
                bit = mps
                cx[k] = (tb[i4 + 1] << 1) | mps
              else
                bit = 1 - mps
                cx[k] = (tb[i4 + 2] << 1) | (mps ^ tb[i4 + 3])
              a = qe
              rn = 1
            else
              c = c - (qe << 16)
              if (a & 0x8000) == 0
                if a < qe
                  bit = 1 - mps
                  cx[k] = (tb[i4 + 2] << 1) | (mps ^ tb[i4 + 3])
                else
                  bit = mps
                  cx[k] = (tb[i4 + 1] << 1) | mps
                rn = 1
              else
                bit = mps
            if rn == 1
              while (a & 0x8000) == 0
                if ct == 0
                  s[1] = c
                  s[3] = bp
                  j2_bytein(s, d)
                  c = s[1]
                  ct = s[2]
                  bp = s[3]
                a = a << 1
                c = (c << 1) & 0xFFFFFFFF
                ct -= 1
          if bit == 1
            sg = 0 ## i64
            fa = fl[pj]
            sx = ((fa >> 4) & 15) | ((fa >> 8) & 0xF0)
            sx = sx & 0x77 if south == 0
            se = tb[1300 + sx]
            sk = se >> 1
            st = cx[sk]
            i4 = (st >> 1) << 2
            mps = st & 1
            qe = tb[i4]
            a = a - qe
            rn = 0 ## i64
            if (c >> 16) < qe
              if a < qe
                sg = mps
                cx[sk] = (tb[i4 + 1] << 1) | mps
              else
                sg = 1 - mps
                cx[sk] = (tb[i4 + 2] << 1) | (mps ^ tb[i4 + 3])
              a = qe
              rn = 1
            else
              c = c - (qe << 16)
              if (a & 0x8000) == 0
                if a < qe
                  sg = 1 - mps
                  cx[sk] = (tb[i4 + 2] << 1) | (mps ^ tb[i4 + 3])
                else
                  sg = mps
                  cx[sk] = (tb[i4 + 1] << 1) | mps
                rn = 1
              else
                sg = mps
            if rn == 1
              while (a & 0x8000) == 0
                if ct == 0
                  s[1] = c
                  s[3] = bp
                  j2_bytein(s, d)
                  c = s[1]
                  ct = s[2]
                  bp = s[3]
                a = a << 1
                c = (c << 1) & 0xFFFFFFFF
                ct -= 1
            sg = sg ^ (se & 1)
            v[y * w + x] = oh
            fl[pj] = f | 1 | (sg << 1)
            fl[pj - 1] = fl[pj - 1] | 32 | (sg << 13)
            fl[pj + 1] = fl[pj + 1] | 16 | (sg << 12)
            fl[pj - fw] = fl[pj - fw] | 128 | (sg << 15)
            fl[pj + fw] = fl[pj + fw] | 64 | (sg << 14)
            fl[pj - fw - 1] = fl[pj - fw - 1] | 2048
            fl[pj - fw + 1] = fl[pj - fw + 1] | 1024
            fl[pj + fw - 1] = fl[pj + fw - 1] | 512
            fl[pj + fw + 1] = fl[pj + fw + 1] | 256
        y += 1
        pj += fw
      pj = p
      y = y0
      while y < ye
        fl[pj] = fl[pj] & 0xFFFB
        y += 1
        pj += fw
      x += 1
    y0 += 4
  s[0] = a
  s[1] = c
  s[2] = ct
  s[3] = bp
  0

# The four-symbol segmentation marker after a cleanup pass (SEGSYM).
-> j2_segsym_mq(s, cx, d, tb) (i64[] i64[] u8[] i64[]) i64
  a = s[0]
  c = s[1]
  ct = s[2]
  bp = s[3]
  one = 1 ## i64
  j = 0 ## i64
  while j < 4
    k = 18 ## i64
    bit = 0 ## i64
    st = cx[k]
    i4 = (st >> 1) << 2
    mps = st & 1
    qe = tb[i4]
    a = a - qe
    rn = 0 ## i64
    if (c >> 16) < qe
      if a < qe
        bit = mps
        cx[k] = (tb[i4 + 1] << 1) | mps
      else
        bit = 1 - mps
        cx[k] = (tb[i4 + 2] << 1) | (mps ^ tb[i4 + 3])
      a = qe
      rn = 1
    else
      c = c - (qe << 16)
      if (a & 0x8000) == 0
        if a < qe
          bit = 1 - mps
          cx[k] = (tb[i4 + 2] << 1) | (mps ^ tb[i4 + 3])
        else
          bit = mps
          cx[k] = (tb[i4 + 1] << 1) | mps
        rn = 1
      else
        bit = mps
    if rn == 1
      while (a & 0x8000) == 0
        if ct == 0
          s[1] = c
          s[3] = bp
          j2_bytein(s, d)
          c = s[1]
          ct = s[2]
          bp = s[3]
        a = a << 1
        c = (c << 1) & 0xFFFFFFFF
        ct -= 1
    j += 1
  s[0] = a
  s[1] = c
  s[2] = ct
  s[3] = bp
  0


# Decode one code-block. d holds its segments back to back: segment i is
# segl[i] bytes and carries segp[i] coding passes. p0 is the bit plane of the
# first (cleanup) pass. Writes w*h signed values to out; v, fl, cx and s are
# scratch (v >= w*h, fl >= (w+2)*(h+2)). Returns the passes decoded.
-> j2_t1_decode(d, segl, segp, nseg, w, h, ob, sty, p0, npasses, out, v, fl, cx, s, tb) (u8[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  n = w * h
  i = 0 ## i64
  while i < n
    v[i] = 0
    i += 1
  nf = (w + 2) * (h + 2)
  i = 0
  while i < nf
    fl[i] = 0
    i += 1
  j2_ctx_reset(cx)
  bypass = sty & 1
  reset = sty & 2
  vc = 0 ## i64
  vc = 1 if (sty & 8) != 0
  segsym = sty & 32
  seg = 0 ## i64
  segstart = 0 ## i64
  left = 0 ## i64
  k = 0 ## i64
  done = 0 ## i64
  while k < npasses && done == 0
    typ = 2 ## i64
    plane = p0
    if k > 0
      typ = (k - 1) % 3
      plane = p0 - 1 - (k - 1) / 3
    if plane < 0
      done = 1
    else
      raw = 0 ## i64
      raw = 1 if bypass != 0 && k >= 10 && typ != 2
      if left == 0
        if seg >= nseg
          done = 1
        else
          segstart = segstart + segl[seg - 1] if seg > 0
          left = segp[seg]
          if raw == 1
            s[3] = segstart
            s[4] = segstart + segl[seg]
            s[5] = 0
            s[6] = 0
          else
            j2_mq_init(s, d, segstart, segstart + segl[seg])
          seg += 1
      if done == 0
        q = plane + 1
        if typ == 0
          if raw == 1
            j2_spp(s, cx, d, tb, v, fl, w, h, q, ob, vc, raw)
          else
            j2_spp_mq(s, cx, d, tb, v, fl, w, h, q, ob, vc)
        elsif typ == 1
          if raw == 1
            j2_mrp(s, cx, d, tb, v, fl, w, h, q, vc, raw)
          else
            j2_mrp_mq(s, cx, d, tb, v, fl, w, h, q, ob, vc)
        else
          j2_cup_mq(s, cx, d, tb, v, fl, w, h, q, ob, vc)
          j2_segsym_mq(s, cx, d, tb) if segsym != 0
        j2_ctx_reset(cx) if reset != 0
        left -= 1
        k += 1
  fw = w + 2
  y = 0 ## i64
  while y < h
    x = 0 ## i64
    while x < w
      vi = v[y * w + x]
      if (fl[(y + 1) * fw + x + 1] & 2) != 0
        vi = 0 - vi
      out[y * w + x] = vi
      x += 1
    y += 1
  k
