# blade/brotli — a Brotli (RFC 7932) decoder.
#
# Brotli.decompress(data) takes a String or u8[] and returns the decoded
# bytes as u8[] (raises on corrupt input). Used for WOFF2 fonts; it also
# serves Content-Encoding: br.
#
# The bit reader works on a u8[] with the bit position in st[0]. Prefix codes
# are canonical Huffman codes stored as counts per length (cnt, 16 per tree)
# and symbols sorted by (length, value) (sym, `alpha` per tree), decoded one
# bit at a time the way zlib's puff does.

use core/brotli_dict

BR_STATE = [nil, nil, nil, nil]

-> br_dict
  if BR_STATE[0] == nil
    d = Base64.decode(BROTLI_DICT_B64)
    BR_STATE[1] = d
    if d.is_a?(String)
      BR_STATE[0] = ccall("w_string_bytes_view", d) ## u8[]
    else
      BR_STATE[0] = d
  BR_STATE[0]

-> br_lut
  if BR_STATE[2] == nil
    a = i64[2048]
    k = 0
    while k < 2048
      a[k] = BROTLI_CONTEXT_LUT[k]
      k += 1
    BR_STATE[2] = a
  BR_STATE[2]

BR_NDBITS = [0, 0, 0, 0, 10, 10, 11, 11, 10, 10, 10, 10, 10, 9, 9, 8, 7, 7, 8, 7, 7, 6, 6, 5, 5]
BR_INS_BASE = [0, 1, 2, 3, 4, 5, 6, 8, 10, 14, 18, 26, 34, 50, 66, 98, 130, 194, 322, 578, 1090, 2114, 6210, 22594]
BR_INS_EXTRA = [0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 7, 8, 9, 10, 12, 14, 24]
BR_COPY_BASE = [2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 18, 22, 30, 38, 54, 70, 102, 134, 198, 326, 582, 1094, 2118]
BR_COPY_EXTRA = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 7, 8, 9, 10, 24]
BR_BLEN_BASE = [1, 5, 9, 13, 17, 25, 33, 41, 49, 65, 81, 97, 113, 145, 177, 209, 241, 305, 369, 497, 753, 1265, 2289, 4337, 8433, 16625]
BR_BLEN_EXTRA = [2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 7, 8, 9, 10, 11, 12, 13, 24]
# cell (command >> 6) -> insert code offset, copy code offset
BR_CELL_INS = [0, 0, 0, 0, 8, 8, 0, 16, 8, 16, 16]
BR_CELL_COPY = [0, 8, 0, 8, 0, 8, 16, 0, 16, 8, 16]
BR_CL_ORDER = [1, 2, 3, 4, 0, 5, 17, 6, 16, 7, 8, 9, 10, 11, 12, 13, 14, 15]
BR_CL_PLEN = [2, 2, 2, 3, 2, 2, 2, 4, 2, 2, 2, 3, 2, 2, 2, 4]
BR_CL_PVAL = [0, 4, 3, 2, 0, 4, 3, 1, 0, 4, 3, 2, 0, 4, 3, 5]

+ BrotliError < StandardError

-> br_fail(msg)
  raise BrotliError, "brotli: " + msg

# Fast unaligned 64-bit load/store for Brotli bit reader and bulk match copy (1 ARM64 ldr/str).
fn br_load64(ptr, off) (i64 i64) i64
  ll <<~IR
    %base = inttoptr i64 %ptr to ptr
    %p = getelementptr i8, ptr %base, i64 %off
    %v = load i64, ptr %p, align 1
    ret i64 %v
  IR

fn br_store64(ptr, off, val) (i64 i64 i64) i64
  ll <<~IR
    %base = inttoptr i64 %ptr to ptr
    %p = getelementptr i8, ptr %base, i64 %off
    store i64 %val, ptr %p, align 1
    ret i64 0
  IR

# n bits, least significant first (single 64-bit load on the 99.9% interior path).
-> br_bits(src, st, n) (u8[] i64[] i64) i64
  return 0 if n == 0
  pos = st[0]
  size = src.size
  by = pos >> 3
  v = 0 ## i64
  if by + 8 <= size
    sp = ccall_nobox("w_array_data_ptr", src) ## i64
    w = br_load64(sp, by)
    v = (w >> (pos & 7)) & ((1 << n) - 1)
    pos += n
  else
    i = 0 ## i64
    while i < n
      b2 = pos >> 3
      bit = 0 ## i64
      if b2 < size
        bit = (src[b2] >> (pos & 7)) & 1
      v = v | (bit << i)
      pos += 1
      i += 1
  st[0] = pos
  if (pos >> 3) > size + 4
    st[1] = 1
  v

# Build the canonical code for lens[0...alpha] into tree t of (cnt, sym).
-> br_build(lens, alpha, cnt, sym, t) (i64[] i64 i64[] i64[] i64) i64
  cb = t * 16
  sb = t * alpha
  k = 0 ## i64
  while k < 16
    cnt[cb + k] = 0
    k += 1
  used = 0 ## i64
  last = 0 ## i64
  k = 0
  while k < alpha
    l = lens[k]
    if l > 0
      cnt[cb + l] = cnt[cb + l] + 1
      used += 1
      last = k
    k += 1
  if used == 1
    cnt[cb] = 1
    sym[sb] = last
    return 1
  # symbols ordered by length, then value
  offs = i64[16]
  acc = 0 ## i64
  l = 1 ## i64
  while l < 16
    offs[l] = acc
    acc += cnt[cb + l]
    l += 1
  k = 0
  while k < alpha
    l = lens[k]
    if l > 0
      sym[sb + offs[l]] = k
      offs[l] = offs[l] + 1
    k += 1
  used

-> br_decode(src, st, cnt, sym, t, alpha) (u8[] i64[] i64[] i64[] i64 i64) i64
  cb = t * 16
  sb = t * alpha
  if cnt[cb] == 1
    return sym[sb]
  code = 0 ## i64
  first = 0 ## i64
  index = 0 ## i64
  len = 1 ## i64
  while len < 16
    code = code | br_bits(src, st, 1)
    count = cnt[cb + len]
    if code - first < count
      return sym[sb + index + code - first]
    index += count
    first += count
    first = first << 1
    code = code << 1
    len += 1
  -1

# perf: a 10-bit root lookup table per tree (1024 entries): tab[t * 1024 + next 10 input bits]
# is sym << 4 | code length for codes of up to 10 bits (~98% of Brotli symbols), -1 for longer ones.
-> br_table(cnt, sym, t, alpha, tab) (i64[] i64[] i64 i64 i64[]) i64
  cb = t * 16
  sb = t * alpha
  tb = t * 1024
  k = 0 ## i64
  if cnt[cb] == 1
    e1 = sym[sb] << 4
    while k < 1024
      tab[tb + k] = e1
      k += 1
    return 0
  while k < 1024
    tab[tb + k] = -1
    k += 1
  first = 0 ## i64
  index = 0 ## i64
  len = 1 ## i64
  while len <= 10
    c = cnt[cb + len]
    j = 0 ## i64
    while j < c
      code = first + j
      r = 0 ## i64
      b = 0 ## i64
      while b < len
        r = (r << 1) | ((code >> b) & 1)
        b += 1
      e = (sym[sb + index + j] << 4) | len
      f = r
      step = 1 << len
      while f < 1024
        tab[tb + f] = e
        f += step
      j += 1
    index += c
    first = (first + c) << 1
    len += 1
  0

# br_decode through tree t's 10-bit root table (1 unaligned 64-bit load on interior path).
-> br_fdec(src, st, cnt, sym, t, alpha, tab) (u8[] i64[] i64[] i64[] i64 i64 i64[]) i64
  pos = st[0]
  by = pos >> 3
  size = src.size
  v = 0 ## i64
  if by + 8 <= size
    sp = ccall_nobox("w_array_data_ptr", src) ## i64
    v = br_load64(sp, by) >> (pos & 7)
  elsif by + 2 < size
    b0 = src[by] ## i64
    b1 = src[by + 1] ## i64
    b2 = src[by + 2] ## i64
    v = (b0 | (b1 << 8) | (b2 << 16)) >> (pos & 7)
  elsif by + 1 < size
    b0 = src[by] ## i64
    b1 = src[by + 1] ## i64
    v = (b0 | (b1 << 8)) >> (pos & 7)
  elsif by < size
    b0 = src[by] ## i64
    v = b0 >> (pos & 7)
  e = tab[t * 1024 + (v & 1023)]
  if e >= 0
    np = pos + (e & 15)
    st[0] = np
    if (np >> 3) > size + 4
      st[1] = 1
    return e >> 4
  br_decode(src, st, cnt, sym, t, alpha)

# Read one prefix code (RFC 7932 section 3.4/3.5) for an alphabet into tree t.
-> br_read_code(src, st, alpha, cnt, sym, t)
  lens = i64[alpha]
  hskip = br_bits(src, st, 2)
  if hskip == 1
    nsym = br_bits(src, st, 2) + 1
    abits = 0
    while (1 << abits) < alpha
      abits += 1
    s = []
    nsym.times ->(i)
      v = br_bits(src, st, abits)
      br_fail("bad simple code symbol") if v >= alpha
      s.push(v)
    if nsym == 1
      lens[s[0]] = 1
    elsif nsym == 2
      lens[s[0]] = 1
      lens[s[1]] = 1
    elsif nsym == 3
      lens[s[0]] = 1
      lens[s[1]] = 2
      lens[s[2]] = 2
    else
      if br_bits(src, st, 1) == 0
        4.times ->(i) lens[s[i]] = 2
      else
        lens[s[0]] = 1
        lens[s[1]] = 2
        lens[s[2]] = 3
        lens[s[3]] = 3
    br_build(lens, alpha, cnt, sym, t)
    return nil
  # complex: first the code length code lengths
  cll = i64[18]
  space = 32
  num = 0
  i = hskip
  while i < 18 && space > 0
    peek = br_peek4(src, st)
    v = BR_CL_PVAL[peek]
    st[0] = st[0] + BR_CL_PLEN[peek]
    cll[BR_CL_ORDER[i]] = v
    if v != 0
      space -= 32 >> v
      num += 1
    i += 1
  br_fail("bad code length code") if num != 1 && space != 0
  ccnt = i64[16]
  csym = i64[18]
  br_build(cll, 18, ccnt, csym, 0)
  symbol = 0
  prev = 8
  rep = 0
  rep_len = 0
  space = 32768
  while symbol < alpha && space > 0
    p = br_decode(src, st, ccnt, csym, 0, 18)
    br_fail("bad code length") if p < 0
    if p < 16
      rep = 0
      lens[symbol] = p
      symbol += 1
      if p != 0
        prev = p
        space -= 32768 >> p
    else
      eb = p == 16 ? 2 : 3
      nl = p == 16 ? prev : 0
      if rep_len != nl
        rep = 0
        rep_len = nl
      old = rep
      if rep > 0
        rep = (rep - 2) << eb
      rep = rep + br_bits(src, st, eb) + 3
      delta = rep - old
      br_fail("code length repeat overflow") if symbol + delta > alpha
      k = 0
      while k < delta
        lens[symbol] = rep_len
        symbol += 1
        k += 1
      space -= delta << (15 - rep_len) if rep_len != 0
  br_fail("bad prefix code") if space != 0 && space != 32768
  br_build(lens, alpha, cnt, sym, t)
  nil

-> br_peek4(src, st) (u8[] i64[]) i64
  save = st[0]
  v = br_bits(src, st, 4)
  st[0] = save
  v

# 1..256 (NBLTYPES / NTREES encoding).
-> br_var256(src, st)
  return 1 if br_bits(src, st, 1) == 0
  n = br_bits(src, st, 3)
  return 2 if n == 0
  (1 << n) + br_bits(src, st, n) + 1

-> br_block_len(src, st, cnt, sym, t)
  c = br_decode(src, st, cnt, sym, t, 26)
  br_fail("bad block length") if c < 0
  BR_BLEN_BASE[c] + br_bits(src, st, BR_BLEN_EXTRA[c])

# Context map (section 7.3) of size n over ntrees.
-> br_context_map(src, st, n, ntrees)
  m = i64[n]
  return m if ntrees < 2
  rlemax = 0
  rlemax = br_bits(src, st, 4) + 1 if br_bits(src, st, 1) == 1
  alpha = ntrees + rlemax
  cnt = i64[16]
  sym = i64[alpha]
  br_read_code(src, st, alpha, cnt, sym, 0)
  i = 0
  while i < n
    c = br_decode(src, st, cnt, sym, 0, alpha)
    br_fail("bad context map") if c < 0
    if c == 0
      m[i] = 0
      i += 1
    elsif c <= rlemax
      run = (1 << c) + br_bits(src, st, c)
      br_fail("context map run overflow") if i + run > n
      run.times ->(k) m[i + k] = 0
      i += run
    else
      m[i] = c - rlemax
      i += 1
  if br_bits(src, st, 1) == 1
    # inverse move-to-front
    mtf = i64[256]
    k = 0
    while k < 256
      mtf[k] = k
      k += 1
    k = 0
    while k < n
      idx = m[k]
      v = mtf[idx]
      m[k] = v
      j = idx
      while j > 0
        mtf[j] = mtf[j - 1]
        j -= 1
      mtf[0] = v
      k += 1
  m

+ Brotli
  -> .decompress(data)
    src = data
    if data.is_a?(String)
      src = ccall("w_string_bytes_view", data) ## u8[]
    st = i64[4]
    out = u8[src.size * 4 + 1024]
    op = 0
    # window
    wbits = 16
    if br_bits(src, st, 1) == 1
      n = br_bits(src, st, 3)
      if n != 0
        wbits = 17 + n
      else
        m = br_bits(src, st, 3)
        br_fail("large window streams are not supported") if m == 1
        wbits = m == 0 ? 17 : 8 + m
    max_back = (1 << wbits) - 16
    dist_rb = [16, 15, 11, 4]
    dist_i = 3
    p1 = 0
    p2 = 0
    last = false
    while !last
      last = br_bits(src, st, 1) == 1
      if last && br_bits(src, st, 1) == 1
        break
      mn = br_bits(src, st, 2)
      if mn == 3
        # metadata block: skip it
        br_fail("reserved bit set") if br_bits(src, st, 1) != 0
        nb = br_bits(src, st, 2)
        skip = 0
        if nb > 0
          skip = br_bits(src, st, nb * 8) + 1
        st[0] = ((st[0] + 7) >> 3) << 3
        st[0] = st[0] + skip * 8
        next
      mlen = br_bits(src, st, (mn + 4) * 4) + 1
      if !last && br_bits(src, st, 1) == 1
        # uncompressed
        st[0] = ((st[0] + 7) >> 3) << 3
        bp = st[0] >> 3
        br_fail("truncated stored block") if bp + mlen > src.size
        out = br_reserve(out, op, mlen)
        op = op + br_move(out, op, src, bp, mlen)
        st[0] = (bp + mlen) * 8
        p1 = op > 0 ? out[op - 1] : 0
        p2 = op > 1 ? out[op - 2] : 0
        next
      r = Brotli.meta_block(src, st, out, op, mlen, max_back, dist_rb, dist_i, p1, p2)
      out = r[0]
      op = r[1]
      dist_i = r[2]
      p1 = op > 0 ? out[op - 1] : 0
      p2 = op > 1 ? out[op - 2] : 0
      br_fail("truncated input") if st[1] == 1
    exact = u8[op]
    br_move(exact, 0, out, 0, op)
    exact

  # One compressed meta-block of mlen bytes. Returns [out, op, dist_i].
  -> .meta_block(src, st, out, op, mlen, max_back, dist_rb, dist_i, p1, p2)
    # block types and counts for literals (0), commands (1), distances (2)
    nbl = [1, 1, 1]
    btype = [0, 0, 0]
    bprev = [1, 1, 1]
    blen = [1 << 28, 1 << 28, 1 << 28]
    tcnt = [nil, nil, nil]
    tsym = [nil, nil, nil]
    lcnt = [nil, nil, nil]
    lsym = [nil, nil, nil]
    3.times ->(c)
      n = br_var256(src, st)
      nbl[c] = n
      if n >= 2
        tc = i64[16]
        ts = i64[n + 2]
        br_read_code(src, st, n + 2, tc, ts, 0)
        lc = i64[16]
        ls = i64[26]
        br_read_code(src, st, 26, lc, ls, 0)
        tcnt[c] = tc
        tsym[c] = ts
        lcnt[c] = lc
        lsym[c] = ls
        blen[c] = br_block_len(src, st, lc, ls, 0)
    npostfix = br_bits(src, st, 2)
    ndirect = br_bits(src, st, 4) << npostfix
    cmodes = i64[nbl[0]]
    k = 0
    while k < nbl[0]
      cmodes[k] = br_bits(src, st, 2)
      k += 1
    ntl = br_var256(src, st)
    cmap_l = br_context_map(src, st, 64 * nbl[0], ntl)
    ntd = br_var256(src, st)
    cmap_d = br_context_map(src, st, 4 * nbl[2], ntd)
    # prefix code groups (10-bit root tables -> 1024 entries/tree)
    lit_cnt = i64[ntl * 16]
    lit_sym = i64[ntl * 256]
    ntl.times ->(t) br_read_code(src, st, 256, lit_cnt, lit_sym, t)
    lit_tab = i64[ntl * 1024]
    ntl.times ->(t) br_table(lit_cnt, lit_sym, t, 256, lit_tab)
    nci = nbl[1]
    cmd_cnt = i64[nci * 16]
    cmd_sym = i64[nci * 704]
    nci.times ->(t) br_read_code(src, st, 704, cmd_cnt, cmd_sym, t)
    cmd_tab = i64[nci * 1024]
    nci.times ->(t) br_table(cmd_cnt, cmd_sym, t, 704, cmd_tab)
    dalpha = 16 + ndirect + (48 << npostfix)
    dst_cnt = i64[ntd * 16]
    dst_sym = i64[ntd * dalpha]
    ntd.times ->(t) br_read_code(src, st, dalpha, dst_cnt, dst_sym, t)
    dst_tab = i64[ntd * 1024]
    ntd.times ->(t) br_table(dst_cnt, dst_sym, t, dalpha, dst_tab)
    lut = br_lut()
    kt = br_consts()
    dict = nil
    end_pos = op + mlen
    out = br_reserve(out, op, mlen)
    # perf: the command loop runs in typed code (br_run) on this machine state; it comes back
    # here for block switches and static-dictionary words
    ms = i64[28]
    ms[0] = op
    ms[1] = p1
    ms[2] = p2
    ms[3] = dist_i
    k = 0
    while k < 4
      ms[4 + k] = dist_rb[k]
      ms[8 + k] = blen[k] if k < 3
      ms[11 + k] = btype[k] if k < 3
      k += 1
    ms[14] = cmodes[btype[0]] * 512
    ms[19] = end_pos
    ms[20] = max_back
    ms[21] = npostfix
    ms[22] = ndirect
    ms[23] = dalpha
    done = false
    while !done
      r = br_run(src, st, out, ms, kt, lut, cmap_l, cmap_d, lit_cnt, lit_sym, lit_tab, cmd_cnt, cmd_sym, cmd_tab, dst_cnt, dst_sym, dst_tab)
      if r == 0
        done = true
      elsif r >= 1 && r <= 3
        k = 0
        while k < 3
          blen[k] = ms[8 + k]
          btype[k] = ms[11 + k]
          k += 1
        Brotli.switch_block(src, st, r - 1, nbl, btype, bprev, blen, tcnt, tsym, lcnt, lsym)
        k = 0
        while k < 3
          ms[8 + k] = blen[k]
          ms[11 + k] = btype[k]
          k += 1
        ms[14] = cmodes[btype[0]] * 512
      elsif r == 4
        # static dictionary reference
        op = ms[0]
        dist = ms[24]
        clen = ms[25]
        maxd = ms[26]
        br_fail("bad dictionary reference") if clen < 4 || clen > 24
        dict = br_dict() if dict == nil
        word_id = dist - maxd - 1
        nd = BR_NDBITS[clen]
        idx = word_id & ((1 << nd) - 1)
        tid = word_id >> nd
        br_fail("bad transform") if tid >= 121
        off = br_dict_offset(clen) + idx * clen
        w = br_transform(dict, off, clen, tid)
        br_fail("meta-block overrun") if op + w.size > end_pos
        wi = 0
        while wi < w.size
          out[op] = w[wi]
          op += 1
          wi += 1
        ms[0] = op
        ms[1] = out[op - 1]
        ms[2] = op > 1 ? out[op - 2] : 0
      else
        br_fail(["", "bad command code", "meta-block overrun", "bad literal", "bad distance code", "bad distance"][0 - r])
    k = 0
    while k < 4
      dist_rb[k] = ms[4 + k]
      k += 1
    [out, ms[0], ms[3]]

  -> .short_dist(dc, rb, i)
    last = rb[i]
    second = rb[(i + 3) & 3]
    case dc
    when 0
      return last
    when 1
      return second
    when 2
      return rb[(i + 2) & 3]
    when 3
      return rb[(i + 1) & 3]
    d = [0, 0, 0, 0, -1, 1, -2, 2, -3, 3, -1, 1, -2, 2, -3, 3]
    (dc < 10 ? last : second) + d[dc]

  -> .switch_block(src, st, c, nbl, btype, bprev, blen, tcnt, tsym, lcnt, lsym)
    n = nbl[c]
    code = br_decode(src, st, tcnt[c], tsym[c], 0, n + 2)
    br_fail("bad block type") if code < 0
    t = 0
    if code == 0
      t = bprev[c]
    elsif code == 1
      t = (btype[c] + 1) % n
    else
      t = code - 2
    t = t - n if t >= n
    bprev[c] = btype[c]
    btype[c] = t
    blen[c] = br_block_len(src, st, lcnt[c], lsym[c], 0)

# BR_CELL_INS (0), BR_CELL_COPY (11), BR_INS_BASE (22), BR_INS_EXTRA (46), BR_COPY_BASE (70),
# BR_COPY_EXTRA (94) and the short distance deltas (118) as one i64[] for typed code.
-> br_consts
  if BR_STATE[3] == nil
    a = i64[134]
    k = 0
    while k < 24
      if k < 11
        a[k] = BR_CELL_INS[k]
        a[11 + k] = BR_CELL_COPY[k]
      a[22 + k] = BR_INS_BASE[k]
      a[46 + k] = BR_INS_EXTRA[k]
      a[70 + k] = BR_COPY_BASE[k]
      a[94 + k] = BR_COPY_EXTRA[k]
      k += 1
    d = [0, 0, 0, 0, -1, 1, -2, 2, -3, 3, -1, 1, -2, 2, -3, 3]
    k = 0
    while k < 16
      a[118 + k] = d[k]
      k += 1
    BR_STATE[3] = a
  BR_STATE[3]

# The meta-block command loop (insert literals, then copy) on machine state ms:
#   0 op, 1-2 last two bytes, 3 distance ring index, 4-7 distance ring, 8-10 block lengths
#   left (literal, command, distance), 11-13 block types, 14 literal context mode * 512,
#   15 phase (0 next command, 1 literals, 2 distance), 16 literals left, 17 copy length,
#   18 command cell, 19 end, 20 max backward distance, 21 NPOSTFIX, 22 NDIRECT,
#   23 distance alphabet, 24-26 dictionary reference (distance, length, max distance).
# Returns 0 when the meta-block is complete, 1-3 when block category r-1 must switch,
# 4 for a static dictionary word, < 0 for an error (resumable at the same phase).
-> br_run(src, st, out, ms, kt, lut, cmap_l, cmap_d, lc, ls, lt, cc, cs, ct, dc, ds, dt) (u8[] i64[] u8[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  op = ms[0]
  p1 = ms[1]
  p2 = ms[2]
  phase = ms[15]
  left = ms[16]
  clen = ms[17]
  cell = ms[18]
  end_pos = ms[19]
  rc = 0 ## i64
  go_on = 1 ## i64
  while go_on == 1
    if phase == 0
      if op >= end_pos
        go_on = 0
      elsif ms[9] == 0
        rc = 2
        go_on = 0
      else
        ms[9] = ms[9] - 1
        cmd = br_fdec(src, st, cc, cs, ms[12], 704, ct)
        if cmd < 0
          rc = -1
          go_on = 0
        else
          cell = cmd >> 6
          ic = kt[cell] + ((cmd >> 3) & 7)
          ci = kt[11 + cell] + (cmd & 7)
          left = kt[22 + ic] + br_bits(src, st, kt[46 + ic])
          clen = kt[70 + ci] + br_bits(src, st, kt[94 + ci])
          phase = 1
    if go_on == 1 && phase == 1
      while left > 0 && go_on == 1
        if ms[8] == 0
          rc = 1
          go_on = 0
        else
          m = left
          m = ms[8] if ms[8] < m
          if op + m > end_pos
            rc = -2
            go_on = 0
          else
            lmode = ms[14]
            cbase = ms[11] * 64
            src_ptr = ccall_nobox("w_array_data_ptr", src) ## i64
            src_lim = src.size - 8
            pos = st[0]
            i = 0 ## i64
            while i < m && go_on == 1
              ctx = lut[lmode + p1] | lut[lmode + 256 + p2]
              ltree = cmap_l[cbase + ctx]
              by = pos >> 3
              lit = -1 ## i64
              if by <= src_lim
                e = lt[ltree * 1024 + ((br_load64(src_ptr, by) >> (pos & 7)) & 1023)]
                if e >= 0
                  pos += e & 15
                  lit = e >> 4
                else
                  st[0] = pos
                  lit = br_decode(src, st, lc, ls, ltree, 256)
                  pos = st[0]
              else
                st[0] = pos
                lit = br_fdec(src, st, lc, ls, ltree, 256, lt)
                pos = st[0]
              if lit < 0
                rc = -3
                go_on = 0
              else
                out[op] = lit
                op += 1
                p2 = p1
                p1 = lit
                i += 1
            st[0] = pos
            ms[8] = ms[8] - m
            left -= m
      if go_on == 1
        if op >= end_pos
          go_on = 0
        else
          phase = 2
    if go_on == 1 && phase == 2
      di = ms[3]
      dist = 0 ## i64
      push = 1 ## i64
      ok = 1 ## i64
      if cell < 2
        dist = ms[4 + di]
        push = 0
      elsif ms[10] == 0
        rc = 3
        go_on = 0
        ok = 0
      else
        ms[10] = ms[10] - 1
        dctx = clen - 2
        dctx = 3 if clen > 4
        d = br_fdec(src, st, dc, ds, cmap_d[ms[13] * 4 + dctx], ms[23], dt)
        ndirect = ms[22]
        npostfix = ms[21]
        if d < 0
          rc = -4
          go_on = 0
          ok = 0
        elsif d < 16
          push = 0
          push = 1 if d != 0
          last = ms[4 + di]
          second = ms[4 + ((di + 3) & 3)]
          if d == 0
            dist = last
          elsif d == 1
            dist = second
          elsif d == 2
            dist = ms[4 + ((di + 2) & 3)]
          elsif d == 3
            dist = ms[4 + ((di + 1) & 3)]
          elsif d < 10
            dist = last + kt[118 + d]
          else
            dist = second + kt[118 + d]
        elsif d < 16 + ndirect
          dist = d - 15
        else
          dcode = d - ndirect - 16
          hcode = dcode >> npostfix
          lcode = dcode & ((1 << npostfix) - 1)
          nb = 1 + (hcode >> 1)
          offset = ((2 + (hcode & 1)) << nb) - 4
          dist = ((offset + br_bits(src, st, nb)) << npostfix) + lcode + ndirect + 1
        if ok == 1 && dist <= 0
          rc = -5
          go_on = 0
          ok = 0
      if ok == 1
        maxb = ms[20]
        maxd = op
        maxd = maxb if op >= maxb
        if dist > maxd
          ms[24] = dist
          ms[25] = clen
          ms[26] = maxd
          phase = 0
          rc = 4
          go_on = 0
        elsif op + clen > end_pos
          rc = -2
          go_on = 0
        else
          if push == 1
            di = (di + 1) & 3
            ms[3] = di
            ms[4 + di] = dist
          op = br_copy(out, op, dist, clen)
          p1 = out[op - 1] ## i64
          p2 = out[op - 2] ## i64
          phase = 0
  ms[0] = op
  ms[1] = p1
  ms[2] = p2
  ms[15] = phase
  ms[16] = left
  ms[17] = clen
  ms[18] = cell
  rc

-> br_dict_offset(len)
  off = 0
  l = 4
  while l < len
    off += l * (1 << BR_NDBITS[l])
    l += 1
  off

-> br_copy(out, op, dist, n) (u8[] i64 i64 i64) i64
  if dist >= 8 && n >= 8
    optr = ccall_nobox("w_array_data_ptr", out) ## i64
    k = 0 ## i64
    while k + 8 <= n
      br_store64(optr, op, br_load64(optr, op - dist))
      op += 8
      k += 8
    while k < n
      out[op] = out[op - dist]
      op += 1
      k += 1
    return op
  k = 0 ## i64
  while k < n
    out[op] = out[op - dist]
    op += 1
    k += 1
  op

# n bytes src[soff...] -> dst[doff...] (non-overlapping): a typed loop LLVM vectorizes.
-> br_move(dst, doff, src, soff, n) (u8[] i64 u8[] i64 i64) i64
  i = 0 ## i64
  while i < n
    dst[doff + i] = src[soff + i]
    i += 1
  n

-> br_reserve(out, op, need)
  return out if op + need <= out.size
  cap = out.size * 2
  cap = op + need + 1024 if cap < op + need + 1024
  nw = u8[cap]
  br_move(nw, 0, out, 0, op)
  nw

# A dictionary word with transform tid applied, as a list of bytes.
-> br_transform(dict, off, len, tid)
  pre = BROTLI_AFFIXES[BROTLI_TRANSFORMS[tid * 3]]
  ty = BROTLI_TRANSFORMS[tid * 3 + 1]
  suf = BROTLI_AFFIXES[BROTLI_TRANSFORMS[tid * 3 + 2]]
  w = []
  k = 0
  while k < len
    w.push(dict[off + k])
    k += 1
  if ty >= 1 && ty <= 9
    w = w.slice(0, w.size > ty ? w.size - ty : 0)
  elsif ty >= 12 && ty <= 20
    cut = ty - 11
    w = cut >= w.size ? [] : w.slice(cut, w.size - cut)
  elsif ty == 10
    br_upper(w, 0)
  elsif ty == 11
    i = 0
    while i < w.size
      i += br_upper(w, i)
  pre + w + suf

# Uppercase the UTF-8 character at w[i] the way RFC 7932 does; returns its byte length.
-> br_upper(w, i)
  b = w[i]
  if b < 0xc0
    w[i] = b ^ 32 if b >= 97 && b <= 122
    return 1
  if b < 0xe0
    w[i + 1] = w[i + 1] ^ 32 if i + 1 < w.size
    return 2
  w[i + 2] = w[i + 2] ^ 5 if i + 2 < w.size
  3
