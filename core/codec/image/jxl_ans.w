# core/codec/image/jxl_ans — bit reader and entropy decoding for JPEG XL (ISO/IEC 18181-1).
#
# Bit reader: `br` is an i64[6] over the whole codestream (a u8[]):
#   br[0] next byte to load, br[1] bit buffer (LSB first), br[2] bits in the
#   buffer, br[3] end of the readable range, br[4] bytes read past the end.
# The buffer is kept at <= 56 bits so arithmetic shifts never see bit 63.
#
# Entropy codes (ANS or prefix, with context clustering and LZ77) are read
# into a flat i32[] "code spec" `cs`:
#   cs[0] use_prefix  cs[1] log_alpha_size  cs[2] num_clusters  cs[3] lz77
#   cs[4] min_symbol  cs[5] min_length  cs[6..8] lz77 length uint config
#   cs[9] num_dist (incl. the LZ77 distance context)  cs[11] cfg offset
#   cs[12] cluster-table index offset; the context map starts at cs[16].
# Per cluster: hybrid-uint config (split_exp, msb, lsb, max_token) and either
# an ANS table (D[], alias cutoff[], offset[], symbol[]) or a prefix table
# (fast_len, max_len, lookup entries + overflow entries).
# A decoding stream `es` is an i64[8]: es[0] ANS state, es[1] LZ77 copies
# left, es[2] copy position, es[3] symbols decoded; `win` is its LZ77 window.

use core/codec/image

-> jxl_fail(msg)
  << "jxl: " + msg if env("JXL_DEBUG") != nil
  raise ImageError, "jxl: " + msg

-> jb_new(pos, e)
  br = i64[6]
  br[0] = pos
  br[3] = e
  br

-> jb_fill(src, br) (u8[] i64[]) i64
  pos = br[0]
  buf = br[1]
  nb = br[2]
  e = br[3]
  # the readable end comes from sizes in the file: never past the buffer
  e = src.size if e > src.size
  while nb <= 48
    if pos < e && pos >= 0
      buf = buf | (src[pos] << nb)
    else
      br[4] = br[4] + 1
    pos += 1
    nb += 8
  br[0] = pos
  br[1] = buf
  br[2] = nb
  0

-> jb_u(src, br, n) (u8[] i64[] i64) i64
  if br[2] < n
    jb_fill(src, br)
  buf = br[1]
  one = 1 ## i64
  br[1] = buf >> n
  br[2] = br[2] - n
  buf & ((one << n) - 1)

-> jb_bool(src, br) (u8[] i64[]) bool
  jb_u(src, br, 1) == 1

# Bits consumed so far (absolute position in the codestream).
-> jb_tell(br) (i64[]) i64
  br[0] * 8 - br[2]

-> jb_align(br) (i64[]) i64
  k = br[2] & 7
  br[1] = br[1] >> k
  br[2] = br[2] - k
  0

# Jump to a byte offset (resets the buffer).
-> jb_seek(br, pos) (i64[] i64) i64
  br[0] = pos
  br[1] = 0
  br[2] = 0
  0

-> jb_skip_bits(src, br, n) (u8[] i64[] i64) i64
  if n <= br[2]
    br[1] = br[1] >> n
    br[2] = br[2] - n
    return 0
  rest = n - br[2]
  br[1] = 0
  br[2] = 0
  br[0] = br[0] + (rest >> 3)
  jb_u(src, br, rest & 7)
  0

-> jb_u32(src, br, o0, n0, o1, n1, o2, n2, o3, n3) (u8[] i64[] i64 i64 i64 i64 i64 i64 i64 i64) i64
  sel = jb_u(src, br, 2)
  if sel == 0
    return jb_u(src, br, n0) + o0
  if sel == 1
    return jb_u(src, br, n1) + o1
  if sel == 2
    return jb_u(src, br, n2) + o2
  jb_u(src, br, n3) + o3

-> jb_u64(src, br) (u8[] i64[]) i64
  sel = jb_u(src, br, 2)
  if sel == 0
    return 0
  if sel == 1
    return 1 + jb_u(src, br, 4)
  if sel == 2
    return 17 + jb_u(src, br, 8)
  v = jb_u(src, br, 12)
  shift = 12 ## i64
  while shift < 60 && jb_u(src, br, 1) == 1
    if shift < 56
      v = v | (jb_u(src, br, 8) << shift)
      shift += 8
    else
      v = v | (jb_u(src, br, 4) << shift)
      shift = 64
  v

-> jb_enum(src, br) (u8[] i64[]) i64
  jb_u32(src, br, 0, 0, 1, 0, 2, 4, 18, 6)

-> jb_f16(src, br) (u8[] i64[]) f64
  bits = jb_u(src, br, 16)
  e = (bits >> 10) & 31
  m = bits & 1023
  v = ~0.0
  if e == 0
    v = m * ~0.000000059604644775390625
  else
    v = (m + 1024) * ~1.0
    k = e - 25
    while k > 0
      v = v * ~2.0
      k -= 1
    while k < 0
      v = v * ~0.5
      k += 1
  if (bits >> 15) == 1
    v = ~0.0 - v
  v

-> jb_u8(src, br) (u8[] i64[]) i64
  if jb_u(src, br, 1) == 1
    n = jb_u(src, br, 3)
    return jb_u(src, br, n) + (1 << n)
  0

-> jx_ceil_log2(x) (i64) i64
  n = 0 ## i64
  while (1 << n) < x
    n += 1
  n

-> jb_at_most(src, br, mx) (u8[] i64[] i64) i64
  if mx <= 0
    return 0
  jb_u(src, br, jx_ceil_log2(mx + 1))

-> jx_unpack_signed(x) (i64) i64
  if (x & 1) == 1
    return 0 - (x >> 1) - 1
  x >> 1

# Skip an Extensions bundle.
-> jb_extensions(src, br)
  ext = jb_u64(src, br)
  total = 0
  i = 0
  while i < 64
    if ((ext >> i) & 1) == 1
      total += jb_u64(src, br)
    i += 1
  jb_skip_bits(src, br, total)

# ---------------------------------------------------------------- prefix codes

JX_L0TABLE = [0x00002, 0x40002, 0x30002, 0x20003, 0x00002, 0x40002, 0x30002, 0x10004, 0x00002, 0x40002, 0x30002, 0x20003, 0x00002, 0x40002, 0x30002, 0x50004]
JX_L1ZIGZAG = [1, 2, 3, 4, 0, 5, 17, 6, 16, 7, 8, 9, 10, 11, 12, 13, 14, 15]
JX_REV5 = [0, 16, 8, 24, 4, 20, 12, 28, 2, 18, 10, 26, 6, 22, 14, 30, 1, 17, 9, 25, 5, 21, 13, 29, 3, 19, 11, 27, 7, 23, 15, 31]

# Decode a symbol with a small (no-overflow) lookup table held in a boxed array.
-> jx_small_prefix(src, br, table, fast)
  jb_fill(src, br) if br[2] < fast
  e = table[br[1] & ((1 << fast) - 1)]
  l = e & 15
  br[1] = br[1] >> l
  br[2] = br[2] - l
  e >> 16

# Reads one prefix code (RFC 7932 §3.4/3.5 framing) and returns a boxed array
# [fast_len, max_len, entries…].
-> jx_prefix_tree(src, br, l2size)
  if l2size == 1
    return [0, 0, 0]
  hskip = jb_u(src, br, 2)
  if hskip == 1
    nsym = jb_u(src, br, 2) + 1
    syms = [0, 0, 0, 0]
    i = 0
    while i < nsym
      syms[i] = jb_at_most(src, br, l2size - 1)
      i += 1
    if nsym == 4 && jb_u(src, br, 1) == 1
      nsym = 0
    # templates: maxlen, sortfrom, sortto, len[8], symref[8]
    maxlen = 0
    sf = 0
    st_ = 0
    lens = [0, 0, 0, 0, 0, 0, 0, 0]
    refs = [0, 0, 0, 0, 0, 0, 0, 0]
    if nsym == 0
      maxlen = 3
      sf = 2
      st_ = 4
      lens = [1, 2, 1, 3, 1, 2, 1, 3]
      refs = [0, 1, 0, 2, 0, 1, 0, 3]
    elsif nsym == 2
      maxlen = 1
      sf = 0
      st_ = 2
      lens = [1, 1]
      refs = [0, 1]
    elsif nsym == 3
      maxlen = 2
      sf = 1
      st_ = 3
      lens = [1, 2, 1, 2]
      refs = [0, 1, 0, 2]
    elsif nsym == 4
      maxlen = 2
      sf = 0
      st_ = 4
      lens = [2, 2, 2, 2]
      refs = [0, 2, 1, 3]
    i = sf + 1
    while i < st_
      j = i
      while j > sf && syms[j - 1] > syms[j]
        tmp = syms[j - 1]
        syms[j - 1] = syms[j]
        syms[j] = tmp
        j -= 1
      i += 1
    out = [maxlen, maxlen]
    i = 0
    while i < (1 << maxlen)
      out.push((syms[refs[i]] << 16) | lens[i])
      i += 1
    return out

  # complex prefix code: layer 1 code lengths with the fixed layer 0 code
  l1lengths = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  l1counts = [0, 0, 0, 0, 0, 0]
  l1counts[0] = hskip
  total = 0
  i = hskip
  while i < 18 && total < 32
    code = jx_small_prefix(src, br, JX_L0TABLE, 4)
    l1lengths[JX_L1ZIGZAG[i]] = code
    l1counts[code] = l1counts[code] + 1
    total += 32 >> code if code > 0
    i += 1
  jxl_fail("bad prefix code") if (total != 32 && l1counts[0] != i - 1) || l1counts[0] == i
  l1table = []
  k = 0
  while k < 32
    l1table.push(0)
    k += 1
  if l1counts[0] == i - 1
    s = 0
    while l1lengths[s] == 0
      s += 1
    k = 0
    while k < 32
      l1table[k] = s << 16
      k += 1
    l1lengths[s] = 0
  else
    l1starts = [0, 0, 0, 0, 0, 0]
    k = 2
    while k <= 5
      l1starts[k] = l1starts[k - 1] + (l1counts[k - 1] << (5 - (k - 1)))
      k += 1
    s = 0
    while s < 18
      n = l1lengths[s]
      if n > 0
        code = JX_REV5[l1starts[n]]
        while code < 32
          l1table[code] = (s << 16) | n
          code += 1 << n
        l1starts[n] = l1starts[n] + (32 >> n)
      s += 1

  # layer 2 code lengths
  l2lengths = i64[l2size]
  l2counts = i64[16]
  prev = 8
  prev_rep = 0
  total = 0
  i = 0
  while i < l2size && total < 32768
    code = jx_small_prefix(src, br, l1table, 5)
    if code < 16
      l2lengths[i] = code
      i += 1
      l2counts[code] = l2counts[code] + 1
      if code > 0
        total += 32768 >> code
        prev = code
      prev_rep = 0
    elsif code == 16
      prev_rep = 0 if prev_rep < 0
      rep = 3
      rep = 4 * prev_rep - 5 if prev_rep > 0
      rep += jb_u(src, br, 2)
      jxl_fail("bad prefix code") if i + (rep - prev_rep) > l2size
      total += (32768 * (rep - prev_rep)) >> prev
      l2counts[prev] = l2counts[prev] + rep - prev_rep
      while prev_rep < rep
        l2lengths[i] = prev
        i += 1
        prev_rep += 1
    else
      prev_rep = 0 if prev_rep > 0
      rep = -3
      rep = 8 * prev_rep + 13 if prev_rep < 0
      rep -= jb_u(src, br, 3)
      jxl_fail("bad prefix code") if i + (prev_rep - rep) > l2size
      while prev_rep > rep
        l2lengths[i] = 0
        i += 1
        prev_rep -= 1
  jxl_fail("bad prefix code sum") if total != 32768

  l2starts = i64[17]
  l2over = i64[17]
  max_len = 1
  k = 2
  while k <= 15
    l2starts[k] = l2starts[k - 1] + (l2counts[k - 1] << (15 - (k - 1)))
    max_len = k if l2counts[k] > 0
    k += 1
  fast_len = max_len
  fast_len = 10 if fast_len > 10
  size = 1 << fast_len
  k = fast_len + 1
  while k <= max_len
    size += l2counts[k]
    k += 1
  if max_len > fast_len
    l2over[fast_len + 1] = 1 << fast_len
    k = fast_len + 2
    while k <= max_len
      l2over[k] = l2over[k - 1] + l2counts[k - 1]
      k += 1
  table = i64[size + 1]
  s = 0
  while s < l2size
    n = l2lengths[s]
    if n > 0
      st0 = l2starts[n]
      code = (JX_REV5[st0 & 31] << 10) | (JX_REV5[(st0 >> 5) & 31] << 5) | JX_REV5[st0 >> 10]
      if n <= fast_len
        while code < (1 << fast_len)
          table[code] = (s << 16) | n
          code += 1 << n
      else
        table[code] = 0 - l2over[n] if (code >> fast_len) == 0
        table[l2over[n]] = (s << 16) | ((code >> fast_len) << 4) | (n - fast_len)
        l2over[n] = l2over[n] + 1
      l2starts[n] = st0 + (32768 >> n)
    s += 1
  out = [fast_len, max_len]
  k = 0
  while k <= size
    out.push(table[k])
    k += 1
  out

# ---------------------------------------------------------------- ANS tables

JX_LOGCOUNT = [0xa0003, -16, 0x70003, 0x30004, 0x60003, 0x80003, 0x90003, 0x50004, 0xa0003, 0x40004, 0x70003, 0x10004, 0x60003, 0x80003, 0x90003, 0x20004, 0x00011, 0xb0022, 0xc0003, 0xd0043]

# Prefix decode with J40-style overflow entries in a boxed table (used for
# the ANS distribution's log-count code only).
-> jx_overflow_prefix(src, br, table, fast, maxl)
  jb_fill(src, br) if br[2] < maxl
  e = table[br[1] & ((1 << fast) - 1)]
  if e < 0
    br[1] = br[1] >> fast
    br[2] = br[2] - fast
    idx = 0 - e
    found = false
    while !found
      e = table[idx]
      code = (e >> 4) & 0xfff
      l = e & 15
      if code == (br[1] & ((1 << l) - 1))
        found = true
      else
        idx += 1
  l = e & 15
  br[1] = br[1] >> l
  br[2] = br[2] - l
  e >> 16

-> jx_ans_dist(src, br, las)
  ts = 1 << las
  d = []
  k = 0
  while k < ts
    d.push(0)
    k += 1
  kind = jb_u(src, br, 2)
  if kind == 1
    v = jb_u8(src, br)
    jxl_fail("ans dist") if v >= ts
    d[v] = 4096
  elsif kind == 3
    v1 = jb_u8(src, br)
    v2 = jb_u8(src, br)
    jxl_fail("ans dist") if v1 == v2 || v1 >= ts || v2 >= ts
    d[v1] = jb_u(src, br, 12)
    d[v2] = 4096 - d[v1]
  elsif kind == 2
    asz = jb_u8(src, br) + 1
    jxl_fail("ans dist") if asz > ts
    dd = 4096 / asz
    bias = 4096 % asz
    k = 0
    while k < asz
      d[k] = dd
      d[k] = dd + 1 if k < bias
      k += 1
  else
    len = 0
    if jb_u(src, br, 1) == 1
      len = 1
      if jb_u(src, br, 1) == 1
        len = 2
        len = 3 if jb_u(src, br, 1) == 1
    shift = jb_u(src, br, len) + (1 << len) - 1
    jxl_fail("ans dist shift") if shift > 13
    asz = jb_u8(src, br) + 3
    omit_log = -1
    codes = []
    i = 0
    while i < asz
      code = jx_overflow_prefix(src, br, JX_LOGCOUNT, 4, 7)
      if code < 13
        i += 1
        codes.push(code)
        omit_log = code if omit_log < code
      else
        code = jb_u8(src, br) + 4
        i += code
        codes.push(0 - code)
    jxl_fail("ans dist rle") if i != asz || omit_log < 0
    omit_pos = -1
    total = 0
    n = 0
    i = 0
    while i < codes.size && n < ts
      code = codes[i]
      if code < 0
        pv = 0
        pv = d[n - 1] if n > 0
        jxl_fail("ans dist") if pv < 0
        cnt = 0 - code
        cnt = ts - n if cnt > ts - n
        total += pv * cnt
        while cnt > 0
          d[n] = pv
          n += 1
          cnt -= 1
      elsif code == omit_log
        omit_pos = n
        omit_log = -1
        d[n] = -1
        n += 1
      elsif code < 2
        total += code
        d[n] = code
        n += 1
      else
        code -= 1
        bc = shift - ((12 - code) >> 1)
        bc = 0 if bc < 0
        bc = code if bc > code
        v = (1 << code) + (jb_u(src, br, bc) << (code - bc))
        total += v
        d[n] = v
        n += 1
      i += 1
    jxl_fail("ans dist omit") if omit_pos < 0 || total > 4096
    d[omit_pos] = 4096 - total
  d

# Alias table for distribution d: returns [cutoff[], offset[], symbol[]] (boxed).
-> jx_alias(d, las)
  lbs = 12 - las
  bsz = 1 << lbs
  ts = 1 << las
  cut = []
  off = []
  sym = []
  k = 0
  while k < ts
    cut.push(0)
    off.push(0)
    sym.push(0)
    k += 1
  i = 0
  while i < ts && d[i] == 0
    i += 1
  j = i + 1
  while j < ts && d[j] == 0
    j += 1
  if i < ts && j >= ts
    k = 0
    while k < ts
      sym[k] = i
      off[k] = k << lbs
      cut[k] = 0
      k += 1
    return [cut, off, sym]
  u = -1
  o = -1
  # off doubles as the stack link ("next") while a bucket is unsettled
  k = 0
  while k < ts
    c = d[k]
    cut[k] = c
    if c > bsz
      off[k] = o
      o = k
    elsif c < bsz
      off[k] = u
      u = k
    else
      sym[k] = k
      off[k] = 0
    k += 1
  while o >= 0
    jxl_fail("alias table") if u < 0
    by = bsz - cut[u]
    tmp = off[u]
    cut[o] = cut[o] - by
    sym[u] = o
    off[u] = cut[o] - cut[u]
    u = tmp
    if cut[o] < bsz
      tmp = off[o]
      off[o] = u
      u = o
      o = tmp
    elsif cut[o] == bsz
      tmp = off[o]
      off[o] = 0
      o = tmp
  [cut, off, sym]

# ---------------------------------------------------------------- code specs

-> jx_hybrid_cfg(src, br, las)
  se = jb_at_most(src, br, las)
  msb = 0
  lsb = 0
  if se != las
    msb = jb_at_most(src, br, se)
    lsb = jb_at_most(src, br, se - msb)
  [se, msb, lsb]

# Reads a context map for num_dist contexts → [map(boxed), num_clusters].
-> jx_cluster_map(src, br, num_dist, max_allowed)
  max_allowed = num_dist if max_allowed > num_dist
  map = []
  if num_dist == 1
    return [[0], 1]
  if jb_u(src, br, 1) == 1
    nbits = jb_u(src, br, 2)
    i = 0
    while i < num_dist
      v = jb_u(src, br, nbits)
      jxl_fail("cluster map") if v >= max_allowed
      map.push(v)
      i += 1
  else
    use_mtf = jb_u(src, br, 1)
    nd = 1
    nd = -1 if num_dist <= 2
    cs = jx_read_code(src, br, nd)
    es = jx_stream(src, br, cs)
    win = jx_window(cs)
    i = 0
    while i < num_dist
      v = jx_decode(src, br, cs, es, win, 0, 0)
      jxl_fail("cluster map") if v >= max_allowed
      map.push(v)
      i += 1
    jx_finish(src, br, cs, es)
    if use_mtf == 1
      mtf = []
      k = 0
      while k < 256
        mtf.push(k)
        k += 1
      i = 0
      while i < num_dist
        j = map[i]
        mv = mtf[j]
        map[i] = mv
        while j > 0
          mtf[j] = mtf[j - 1]
          j -= 1
        mtf[0] = mv
        i += 1
  seen = []
  k = 0
  while k < 256
    seen.push(false)
    k += 1
  map.each ->(v)
    seen[v] = true
  nc = 0
  while nc < 256 && seen[nc]
    nc += 1
  k = nc
  while k < 256
    jxl_fail("cluster map gap") if seen[k]
    k += 1
  [map, nc]

# Read an entropy code for num_dist contexts (negative: LZ77 not allowed).
-> jx_read_code(src, br, num_dist)
  allow_lz = num_dist > 0
  num_dist = 0 - num_dist if num_dist < 0
  lz = jb_u(src, br, 1)
  min_sym = 0x7fffffff
  min_len = 0
  lzc = [0, 0, 0]
  if lz == 1
    jxl_fail("lz77 not allowed") if !allow_lz
    min_sym = jb_u32(src, br, 224, 0, 512, 0, 4096, 0, 8, 15)
    min_len = jb_u32(src, br, 3, 0, 4, 0, 5, 2, 9, 8)
    lzc = jx_hybrid_cfg(src, br, 8)
    num_dist += 1
  cm = jx_cluster_map(src, br, num_dist, 256)
  map = cm[0]
  nc = cm[1]
  use_prefix = jb_u(src, br, 1)
  cfgs = []
  tables = []
  las = 15
  if use_prefix == 1
    i = 0
    while i < nc
      cfgs.push(jx_hybrid_cfg(src, br, 15))
      i += 1
    counts = []
    i = 0
    while i < nc
      if jb_u(src, br, 1) == 1
        n = jb_u(src, br, 4)
        counts.push(1 + (1 << n) + jb_u(src, br, n))
      else
        counts.push(1)
      i += 1
    i = 0
    while i < nc
      tables.push(jx_prefix_tree(src, br, counts[i]))
      i += 1
  else
    las = 5 + jb_u(src, br, 2)
    i = 0
    while i < nc
      cfgs.push(jx_hybrid_cfg(src, br, las))
      i += 1
    i = 0
    while i < nc
      d = jx_ans_dist(src, br, las)
      al = jx_alias(d, las)
      t = []
      d.each ->(v)
        t.push(v)
      al[0].each ->(v)
        t.push(v)
      al[1].each ->(v)
        t.push(v)
      al[2].each ->(v)
        t.push(v)
      tables.push(t)
      i += 1
  # assemble the flat spec
  off_cfg = 16 + num_dist
  off_tidx = off_cfg + 4 * nc
  size = off_tidx + nc
  tables.each ->(t)
    size += t.size
  cs = i32[size]
  cs[0] = use_prefix
  cs[1] = las
  cs[2] = nc
  cs[3] = lz
  cs[4] = min_sym
  cs[5] = min_len
  cs[6] = lzc[0]
  cs[7] = lzc[1]
  cs[8] = lzc[2]
  cs[9] = num_dist
  cs[11] = off_cfg
  cs[12] = off_tidx
  i = 0
  while i < num_dist
    cs[16 + i] = map[i]
    i += 1
  i = 0
  while i < nc
    c = cfgs[i]
    cs[off_cfg + 4 * i] = c[0]
    cs[off_cfg + 4 * i + 1] = c[1]
    cs[off_cfg + 4 * i + 2] = c[2]
    i += 1
  p = off_tidx + nc
  i = 0
  while i < nc
    cs[off_tidx + i] = p
    t = tables[i]
    k = 0
    while k < t.size
      cs[p + k] = t[k]
      k += 1
    p += t.size
    i += 1
  cs

# A fresh decoding stream for a code spec (reads the initial ANS state).
-> jx_stream(src, br, cs)
  es = i64[8]
  if cs[0] == 0
    es[0] = jb_u(src, br, 32)
  es

-> jx_window(cs)
  return i32[1 << 20] if cs[3] == 1
  i32[1]

-> jx_finish(src, br, cs, es)
  if cs[0] == 0 && es[0] != 0x130000
    jxl_fail("ans final state")
  0

-> jx_read_sym(src, br, cs, es, cl) (u8[] i64[] i32[] i64[] i64) i64
  one = 1 ## i64
  base = cs[cs[12] + cl] ## i64
  if cs[0] == 1
    fast = cs[base] ## i64
    maxl = cs[base + 1] ## i64
    if br[2] < maxl
      jb_fill(src, br)
    buf = br[1]
    e = cs[base + 2 + (buf & ((one << fast) - 1))] ## i64
    if e < 0 && fast < maxl
      buf = buf >> fast
      idx = base + 2 - e
      e = cs[idx]
      while ((e >> 4) & 0xfff) != (buf & ((one << (e & 15)) - 1))
        idx += 1
        e = cs[idx]
      l = (e & 15) + fast
      br[1] = br[1] >> l
      br[2] = br[2] - l
      return e >> 16
    l = e & 15
    br[1] = buf >> l
    br[2] = br[2] - l
    return e >> 16
  las = cs[1] ## i64
  lbs = 12 - las
  ta = one << las
  state = es[0]
  index = state & 0xfff
  i = index >> lbs
  pos = index & ((one << lbs) - 1)
  sym = i
  off = 0 ## i64
  if pos >= cs[base + ta + i]
    sym = cs[base + 3 * ta + i]
    off = cs[base + 2 * ta + i]
  state = cs[base + sym] * (state >> 12) + off + pos
  if state < 65536
    state = (state << 16) | jb_u(src, br, 16)
  es[0] = state
  sym

-> jx_hybrid(src, br, tok, se, msb, lsb) (u8[] i64[] i64 i64 i64 i64) i64
  one = 1 ## i64
  split = one << se
  if tok < split
    return tok
  nb = msb + lsb
  mid_bits = (se - nb + ((tok - split) >> nb)) & 31
  mid = jb_u(src, br, mid_bits)
  top = 1 << msb
  lo = tok & ((one << lsb) - 1)
  hi = (tok >> lsb) & (top - 1)
  (((top | hi) << (mid_bits + lsb)) | (mid << lsb) | lo) & 0xFFFFFFFF

JX_SPECIAL_DIST = [0x71, 0x80, 0x81, 0x61, 0x72, 0x90, 0x82, 0x62, 0x91, 0x51, 0x92, 0x52, 0x73, 0xa0, 0x83, 0x63, 0xa1, 0x41, 0x93, 0x53, 0xa2, 0x42, 0x74, 0xb0, 0x84, 0x64, 0xb1, 0x31, 0xa3, 0x43, 0x94, 0x54, 0xb2, 0x32, 0x75, 0xa4, 0x44, 0xb3, 0x33, 0xc0, 0x85, 0x65, 0xc1, 0x21, 0x95, 0x55, 0xc2, 0x22, 0xb4, 0x34, 0xa5, 0x45, 0xc3, 0x23, 0x76, 0xd0, 0x86, 0x66, 0xd1, 0x11, 0x96, 0x56, 0xd2, 0x12, 0xb5, 0x35, 0xc4, 0x24, 0xa6, 0x46, 0xd3, 0x13, 0x77, 0xe0, 0x87, 0x67, 0xc5, 0x25, 0xe1, 0x01, 0xb6, 0x36, 0xd4, 0x14, 0x97, 0x57, 0xe2, 0x02, 0xa7, 0x47, 0xe3, 0x03, 0xc6, 0x26, 0xd5, 0x15, 0xf0, 0xb7, 0x37, 0xe4, 0x04, 0xf1, 0xf2, 0xd6, 0x16, 0xf3, 0xc7, 0x27, 0xe5, 0x05, 0xf4, 0xd7, 0x17, 0xe6, 0x06, 0xf5, 0xe7, 0x07, 0xf6, 0xf7]

-> jx_special_dist_table
  t = i32[120]
  i = 0
  while i < 120
    t[i] = JX_SPECIAL_DIST[i]
    i += 1
  t

JX_SPECIAL = [nil]

# The LZ77 copy path (rare): token >= min_symbol.
-> jx_lz77(src, br, cs, es, win, tok, dist_mult, spec) (u8[] i64[] i32[] i64[] i32[] i64 i64 i32[]) i64
  ms = cs[4] ## i64
  l0 = cs[6] ## i64
  l1 = cs[7] ## i64
  l2 = cs[8] ## i64
  ml = cs[5] ## i64
  ncopy = jx_hybrid(src, br, tok - ms, l0, l1, l2) + ml
  lzcl = cs[16 + cs[9] - 1] ## i64
  t2 = jx_read_sym(src, br, cs, es, lzcl)
  cfg = cs[11] + lzcl * 4
  c0 = cs[cfg] ## i64
  c1 = cs[cfg + 1] ## i64
  c2 = cs[cfg + 2] ## i64
  dist = jx_hybrid(src, br, t2, c0, c1, c2)
  if dist_mult == 0
    dist += 1
  elsif dist >= 120
    dist -= 119
  else
    sp = spec[dist] ## i64
    dist = ((sp >> 4) - 7) + dist_mult * (sp & 7)
    dist = 1 if dist < 1
  nd = es[3]
  dist = nd if dist > nd
  dist = 1048576 if dist > 1048576
  es[2] = nd - dist
  es[1] = ncopy - 1
  v = 0 ## i64
  if dist > 0
    v = win[es[2] & 0xfffff] & 0xFFFFFFFF
  es[2] = es[2] + 1
  win[nd & 0xfffff] = v
  es[3] = nd + 1
  v

-> jx_decode_lz(src, br, cs, es, win, tok, dist_mult)
  JX_SPECIAL[0] = jx_special_dist_table() if JX_SPECIAL[0] == nil
  jx_lz77(src, br, cs, es, win, tok, dist_mult, JX_SPECIAL[0])

# DecodeHybridVarLenUint: one value for context ctx.
-> jx_decode(src, br, cs, es, win, ctx, dist_mult) (u8[] i64[] i32[] i64[] i32[] i64 i64) i64
  if es[1] > 0
    es[1] = es[1] - 1
    v = win[es[2] & 0xfffff] & 0xFFFFFFFF
    es[2] = es[2] + 1
    win[es[3] & 0xfffff] = v
    es[3] = es[3] + 1
    return v
  cl = cs[16 + ctx] ## i64
  tok = jx_read_sym(src, br, cs, es, cl)
  if tok >= cs[4]
    return jx_decode_lz(src, br, cs, es, win, tok, dist_mult)
  cfg = cs[11] + cl * 4
  c0 = cs[cfg] ## i64
  c1 = cs[cfg + 1] ## i64
  c2 = cs[cfg + 2] ## i64
  v = jx_hybrid(src, br, tok, c0, c1, c2)
  if cs[3] == 1
    win[es[3] & 0xfffff] = v
    es[3] = es[3] + 1
  v
