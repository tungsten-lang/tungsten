# core/codec/audio/alac — Apple Lossless (ALAC) decoder, a port of Apple's open-source
# reference decoder (ALACDecoder.cpp / ag_dec.c / dp_dec.c / matrix_dec.c).
#
#   acodec_register("alac", …): cfg.extra is the 24-byte ALACSpecificConfig
#   (MP4 'alac' box body after its version/flags, or the CAF 'kuki' cookie).
#
# 16/20/24/32-bit, any channel count built from SCE/CPE/LFE elements (DSE and
# FIL skipped), adaptive Golomb residuals, the adaptive FIR predictor, stereo
# un-mixing and shifted low bytes. Output channels are reordered from ALAC's
# layout (C L R …) to the usual L R C LFE Ls Rs order.

use core/codec/media

+ AlacDec
  -> new(cfg)
    x = cfg.extra
    raise MediaError.new("alac: missing ALACSpecificConfig") if x == nil || x.size < 24
    @flen = dm_be32(x, 0)
    @depth = x[5]
    @pb = x[6]
    @mb = x[7]
    @kb = x[8]
    @nch = x[9]
    @rate = dm_be32(x, 20)
    @rate = cfg.sample_rate if @rate == 0
    @nch = cfg.channels if @nch == 0
    raise MediaError.new("alac: bad config") if @flen <= 0 || @flen > 65536 || @nch < 1 || @nch > 8
    @pred = i64[@flen + 32]
    @mixu = i64[@flen + 32]
    @mixv = i64[@flen + 32]
    @shift = i64[@flen * 2 + 32]
    @st = i64[8]
    @prm = i64[8]
    @coefu = i64[32]
    @coefv = i64[32]

  -> flush
    nil

  -> reset
    nil

  -> decode(s)
    d = s.data
    nch = @nch
    out = i64[@flen * nch]
    st = @st
    st[0] = 0             # bit position
    st[1] = d.size * 8    # bit size
    ci = 0
    nsamp = @flen
    done = false
    while !done && st[0] + 3 <= st[1]
      tag = alac_bits(d, st, 3)
      if tag == 0 || tag == 3
        break if ci + 1 > nch
        n = element(d, st, false, nsamp)
        break if n < 0
        nsamp = n
        alac_store1(@mixu, out, ci, nch, n, @depth, @shift, st[4])
        ci += 1
      elsif tag == 1
        break if ci + 2 > nch
        n = element(d, st, true, nsamp)
        break if n < 0
        nsamp = n
        alac_store2(@mixu, @mixv, out, ci, nch, n, @depth, st[5], st[6], @shift, st[4])
        ci += 2
      elsif tag == 4
        alac_bits(d, st, 4)
        al = alac_bits(d, st, 1)
        cnt = alac_bits(d, st, 8)
        cnt += alac_bits(d, st, 8) if cnt == 255
        st[0] = ((st[0] + 7) >> 3) << 3 if al == 1
        st[0] += cnt * 8
      elsif tag == 6
        cnt = alac_bits(d, st, 4)
        cnt += alac_bits(d, st, 8) - 1 if cnt == 15
        st[0] += cnt * 8
      elsif tag == 7
        done = true
      else
        break
    frames = nsamp
    res = f32[frames * nch]
    alac_to_f32(out, res, frames, nch, @depth, ALAC_ORDER[nch])
    AudioBlock.new(res, frames, nch, @rate, s.pts)

  # One SCE (pair false) or CPE element; returns the sample count (-1 on error).
  # Leaves mixres/mixbits in st[5]/st[6] and bytesShifted in st[4].
  -> element(d, st, pair, nsamp)
    alac_bits(d, st, 4)
    unused = alac_bits(d, st, 12)
    return -1 if unused != 0
    hb = alac_bits(d, st, 4)
    partial = hb >> 3
    bshift = (hb >> 1) & 3
    return -1 if bshift == 3
    esc = hb & 1
    cbits = @depth - bshift * 8 + (pair ? 1 : 0)
    if partial != 0
      nsamp = (alac_bits(d, st, 16) << 16) | alac_bits(d, st, 16)
      return -1 if nsamp > @flen
    st[4] = bshift
    st[5] = 0
    st[6] = 0
    if esc == 0
      mixbits = alac_bits(d, st, 8)
      mixres = alac_bits(d, st, 8)
      mixres -= 256 if mixres >= 128
      hb = alac_bits(d, st, 8)
      modeu = hb >> 4
      denu = hb & 15
      hb = alac_bits(d, st, 8)
      pbu = hb >> 5
      numu = hb & 31
      k = 0
      while k < numu
        c = alac_bits(d, st, 16)
        @coefu[k] = c >= 32768 ? c - 65536 : c
        k += 1
      modev = 0
      denv = 0
      pbv = 0
      numv = 0
      if pair
        hb = alac_bits(d, st, 8)
        modev = hb >> 4
        denv = hb & 15
        hb = alac_bits(d, st, 8)
        pbv = hb >> 5
        numv = hb & 31
        k = 0
        while k < numv
          c = alac_bits(d, st, 16)
          @coefv[k] = c >= 32768 ? c - 65536 : c
          k += 1
      shpos = st[0]
      st[0] += bshift * 8 * nsamp * (pair ? 2 : 1) if bshift != 0
      # left / mono
      @prm[0] = @mb
      @prm[1] = (@pb * pbu) / 4
      @prm[2] = @kb
      r = alac_dyn_decomp(d, st, @prm, @pred, nsamp, cbits)
      return -1 if r != 0
      alac_unpc_mode(@pred, @mixu, nsamp, @coefu, numu, cbits, denu, modeu)
      if pair
        @prm[1] = (@pb * pbv) / 4
        r = alac_dyn_decomp(d, st, @prm, @pred, nsamp, cbits)
        return -1 if r != 0
        alac_unpc_mode(@pred, @mixv, nsamp, @coefv, numv, cbits, denv, modev)
      st[5] = mixres
      st[6] = mixbits
      if bshift != 0
        save = st[0]
        st[0] = shpos
        k = 0
        n = nsamp * (pair ? 2 : 1)
        while k < n
          @shift[k] = alac_bits(d, st, bshift * 8)
          k += 1
        st[0] = save
    else
      cb = @depth
      k = 0
      while k < nsamp
        @mixu[k] = alac_sbits(d, st, cb)
        @mixv[k] = alac_sbits(d, st, cb) if pair
        k += 1
      st[4] = 0
    nsamp

# Default ALAC layouts → L R C LFE Ls Rs (Cs) order: ALAC_ORDER[n][i] is the
# decoded channel that goes to output position i.
ALAC_ORDER = [[0], [0], [0, 1], [1, 2, 0], [1, 2, 0, 3], [1, 2, 0, 3, 4], [1, 2, 0, 5, 3, 4], [1, 2, 0, 6, 3, 4, 5], [3, 4, 0, 7, 5, 6, 1, 2]]

-> alac_bits(d, st, n) (u8[] i64[] i64) i64
  return 0 if n == 0
  p = st[0]
  st[0] = p + n
  v = 0 ## i64
  o = p >> 3
  k = 0 ## i64
  while k < 5
    b = 0 ## i64
    b = d[o + k] if o + k < d.size
    v = (v << 8) | b
    k += 1
  (v >> (40 - (p & 7) - n)) & ((1 << n) - 1)

-> alac_sbits(d, st, n) (u8[] i64[] i64) i64
  v = 0 ## i64
  if n > 24
    hi = alac_bits(d, st, 16)
    v = (hi << (n - 16)) | alac_bits(d, st, n - 16)
  else
    v = alac_bits(d, st, n)
  v >= (1 << (n - 1)) ? v - (1 << n) : v

# Count of leading zeros of a 32-bit value.
-> alac_lead(m) (i64) i64
  m = m & 0xFFFFFFFF
  return 32 if m == 0
  n = 0 ## i64
  while (m & 0x80000000) == 0
    m = m << 1
    n += 1
  n

# 32 bits of the stream starting at bit position p (zero past the end).
-> alac_peek32(d, p) (u8[] i64) i64
  o = p >> 3
  v = 0 ## i64
  k = 0 ## i64
  while k < 5
    b = 0 ## i64
    b = d[o + k] if o + k < d.size
    v = (v << 8) | b
    k += 1
  (v >> (8 - (p & 7))) & 0xFFFFFFFF

-> alac_getbits(d, p, n) (u8[] i64 i64) i64
  (alac_peek32(d, p) >> (32 - n)) & ((1 << n) - 1)

# Adaptive Golomb decoding of n residuals into pc. prm: 0 mb0, 1 pb, 2 kb.
-> alac_dyn_decomp(d, st, prm, pc, n, maxsize) (u8[] i64[] i64[] i64[] i64 i64) i64
  bitpos = st[0]
  maxpos = st[1]
  mb = prm[0]
  pb = prm[1]
  kb = prm[2]
  wb = (1 << kb) - 1
  zmode = 0 ## i64
  c = 0 ## i64
  while c < n
    return 1 if bitpos >= maxpos
    m = mb >> 9
    k = 31 - alac_lead(m + 3)
    k = kb if k > kb
    m = (1 << k) - 1
    # dyn_get_32bit
    sl = alac_peek32(d, bitpos)
    res = alac_lead(sl ^ 0xFFFFFFFF)
    if res >= 9
      res = alac_getbits(d, bitpos + 9, maxsize)
      bitpos += 9 + maxsize
    else
      bitpos += res + 1
      if k != 1
        v = ((sl << (res + 1)) & 0xFFFFFFFF) >> (32 - k)
        bitpos += k - 1
        res = res * m
        if v >= 2
          res += v - 1
          bitpos += 1
    nv = res
    nd = nv + zmode
    del = (nd + 1) >> 1
    del = 0 - del if (nd & 1) == 1
    pc[c] = del
    c += 1
    mb = pb * (nv + zmode) + mb - ((pb * mb) >> 9)
    mb = 0xFFFF if nv > 0xFFFF
    zmode = 0
    if (mb << 2) < 512 && c < n
      zmode = 1
      k = alac_lead(mb) - 24 + ((mb + 16) >> 6)
      mz = ((1 << k) - 1) & wb
      # dyn_get
      sl = alac_peek32(d, bitpos)
      pre = alac_lead(sl ^ 0xFFFFFFFF)
      r = 0 ## i64
      if pre >= 9
        r = alac_getbits(d, bitpos + 9, 16)
        bitpos += 9 + 16
      else
        bitpos += pre + 1
        v = ((sl << (pre + 1)) & 0xFFFFFFFF) >> (32 - k)
        bitpos += k
        r = pre * mz + v - 1
        if v < 2
          r -= v - 1
          bitpos -= 1
      return 1 if c + r > n
      j = 0 ## i64
      while j < r
        pc[c] = 0
        c += 1
        j += 1
      zmode = 0 if r >= 65535
      mb = 0
  st[0] = bitpos
  0

-> alac_s32(v) (i64) i64
  v = v & 0xFFFFFFFF
  v >= 2147483648 ? v - 4294967296 : v

-> alac_s16(v) (i64) i64
  v = v & 0xFFFF
  v >= 32768 ? v - 65536 : v

-> alac_sext(v, chanbits) (i64 i64) i64
  sh = 32 - chanbits
  return alac_s32(v) if sh <= 0
  x = (v << sh) & 0xFFFFFFFF
  alac_s32(x) >> sh

-> alac_unpc_mode(pc, out, num, coefs, numactive, chanbits, den, mode) (i64[] i64[] i64 i64[] i64 i64 i64 i64) i64
  if mode != 0
    alac_unpc(pc, pc, num, coefs, 31, chanbits, 0)
  alac_unpc(pc, out, num, coefs, numactive, chanbits, den)
  0

-> alac_sign(v) (i64) i64
  return 1 if v > 0
  return -1 if v < 0
  0

-> alac_unpc(pc, out, num, coefs, numactive, chanbits, den) (i64[] i64[] i64 i64[] i64 i64 i64) i64
  denhalf = den > 0 ? (1 << (den - 1)) : 0
  out[0] = pc[0]
  if numactive == 0
    j = 1 ## i64
    while j < num
      out[j] = pc[j]
      j += 1
    return 0
  if numactive == 31
    prev = out[0]
    j = 1 ## i64
    while j < num
      prev = alac_sext(pc[j] + prev, chanbits)
      out[j] = prev
      j += 1
    return 0
  j = 1 ## i64
  while j <= numactive && j < num
    out[j] = alac_sext(pc[j] + out[j - 1], chanbits)
    j += 1
  lim = numactive + 1
  j = lim
  while j < num
    sum1 = 0 ## i64
    top = out[j - lim]
    k = 0 ## i64
    while k < numactive
      sum1 += coefs[k] * (out[j - 1 - k] - top)
      k += 1
    sum1 = alac_s32(sum1)
    del = pc[j]
    del0 = del
    sg = alac_sign(del)
    del = alac_s32(del + top + ((sum1 + denhalf) >> den))
    out[j] = alac_sext(del, chanbits)
    if sg > 0
      k = numactive - 1
      while k >= 0
        dd = top - out[j - 1 - k]
        sgn = alac_sign(dd)
        coefs[k] = alac_s16(coefs[k] - sgn)
        del0 -= (numactive - k) * ((sgn * dd) >> den)
        break if del0 <= 0
        k -= 1
    elsif sg < 0
      k = numactive - 1
      while k >= 0
        dd = top - out[j - 1 - k]
        sgn = alac_sign(dd)
        coefs[k] = alac_s16(coefs[k] + sgn)
        del0 -= (numactive - k) * ((0 - sgn * dd) >> den)
        break if del0 >= 0
        k -= 1
    j += 1
  0

# Mono element → interleaved integer output at channel ci.
-> alac_store1(u, out, ci, nch, n, depth, sh, bshift) (i64[] i64[] i64 i64 i64 i64 i64[] i64) i64
  i = 0 ## i64
  while i < n
    v = u[i]
    v = (v << (bshift * 8)) | sh[i] if bshift != 0
    out[i * nch + ci] = v
    i += 1
  0

-> alac_store2(u, v, out, ci, nch, n, depth, mixres, mixbits, sh, bshift) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64[] i64) i64
  i = 0 ## i64
  while i < n
    l = u[i]
    r = v[i]
    if mixres != 0
      l = u[i] + v[i] - ((mixres * v[i]) >> mixbits)
      r = l - v[i]
    if bshift != 0
      l = (l << (bshift * 8)) | sh[i * 2]
      r = (r << (bshift * 8)) | sh[i * 2 + 1]
    out[i * nch + ci] = l
    out[i * nch + ci + 1] = r
    i += 1
  0

-> alac_to_f32(src, dst, frames, nch, depth, order)
  alac_to_f32_k(src, dst, frames, nch, depth, alac_order_arr(order, nch))

-> alac_order_arr(order, nch)
  a = i64[nch]
  i = 0
  while i < nch
    a[i] = order == nil || i >= order.size ? i : order[i]
    i += 1
  a

-> alac_to_f32_k(src, dst, frames, nch, depth, ord) (i64[] f32[] i64 i64 i64 i64[]) i64
  sc = ~1.0 / (1 << (depth - 1)).to_f
  i = 0 ## i64
  while i < frames
    c = 0 ## i64
    while c < nch
      xi = src[i * nch + ord[c]]
      x = xi.to_f
      dst[i * nch + c] = (x * sc) ## f32
      c += 1
    i += 1
  0

acodec_register("alac", ->(cfg) AlacDec.new(cfg))
