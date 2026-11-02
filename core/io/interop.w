# Standard scientific interchange formats (HDF5, Apache Parquet, Apache Arrow IPC)
# implemented natively in pure Tungsten — no Python, h5py, or PyArrow runtime dependency.
use core/io
use core/file
use core/base64
use core/math

+ SciByteBuf
  rw :buf, :len

  -> new(cap = 256)
    @buf = u8[cap]
    @len = 0

  -> ensure_cap(extra)
    need = @len + extra
    if need <= @buf.size
      return self
    ncap = @buf.size * 2
    if ncap < need
      ncap = need + 256
    nb = u8[ncap]
    sci_copy_bytes(nb, 0, @buf, 0, @len)
    @buf = nb
    self

  -> push(b)
    ensure_cap(1)
    @buf[@len] = b & 255
    @len += 1
    self

  -> extend(bytes)
    n = bytes.size
    ensure_cap(n)
    sci_copy_bytes(@buf, @len, bytes, 0, n)
    @len += n
    self

  -> extend_zeros(n)
    ensure_cap(n)
    i = 0
    while i < n
      @buf[@len + i] = 0
      i += 1
    @len += n
    self

  -> align(mult)
    rem = @len % mult
    if rem != 0
      extend_zeros(mult - rem)
    self

  -> put_u16_le(v)
    ensure_cap(2)
    @buf[@len] = v & 255
    @buf[@len + 1] = (v >> 8) & 255
    @len += 2
    self

  -> put_u32_le(v)
    ensure_cap(4)
    @buf[@len] = v & 255
    @buf[@len + 1] = (v >> 8) & 255
    @buf[@len + 2] = (v >> 16) & 255
    @buf[@len + 3] = (v >> 24) & 255
    @len += 4
    self

  -> put_u64_le(v)
    ensure_cap(8)
    if v < 0
      # signed negative i64
      u = v + (2 ** 64)
      i = 0
      while i < 8
        @buf[@len + i] = (u % 256).to_i
        u = u / 256
        i += 1
    else
      u = v
      i = 0
      while i < 8
        @buf[@len + i] = (u % 256).to_i
        u = u / 256
        i += 1
    @len += 8
    self

  -> set_u8(pos, v)
    @buf[pos] = v & 255

  -> set_u16_le(pos, v)
    @buf[pos] = v & 255
    @buf[pos + 1] = (v >> 8) & 255

  -> set_u32_le(pos, v)
    @buf[pos] = v & 255
    @buf[pos + 1] = (v >> 8) & 255
    @buf[pos + 2] = (v >> 16) & 255
    @buf[pos + 3] = (v >> 24) & 255

  -> set_u64_le(pos, v)
    u = v < 0 ? v + (2 ** 64) : v
    i = 0
    while i < 8
      @buf[pos + i] = (u % 256).to_i
      u = u / 256
      i += 1

  -> to_bytes
    if @len == @buf.size
      return @buf
    out = u8[@len]
    sci_copy_bytes(out, 0, @buf, 0, @len)
    out

+ SciBin
  -> .str_to_bytes(s)
    ccall("w_base64_encode_input", s)

  -> .bytes_to_str(b)
    ccall("w_string_from_byte_array", b)

  -> .slice(b, start, len)
    out = u8[len]
    i = 0
    while i < len
      out[i] = b[start + i]
      i += 1
    out

  -> .u16_le(b, pos)
    (b[pos] ## i64) | ((b[pos + 1] ## i64) << 8)

  -> .i16_le(b, pos)
    v = SciBin.u16_le(b, pos)
    v >= 32768 ? v - 65536 : v

  -> .u32_le(b, pos)
    (b[pos] ## i64) | ((b[pos + 1] ## i64) << 8) | ((b[pos + 2] ## i64) << 16) | ((b[pos + 3] ## i64) << 24)

  -> .i32_le(b, pos)
    v = SciBin.u32_le(b, pos)
    v >= 2147483648 ? v - 4294967296 : v

  -> .u32_be(b, pos)
    ((b[pos] ## i64) << 24) | ((b[pos + 1] ## i64) << 16) | ((b[pos + 2] ## i64) << 8) | (b[pos + 3] ## i64)

  -> .i32_be(b, pos)
    v = SciBin.u32_be(b, pos)
    v >= 2147483648 ? v - 4294967296 : v

  -> .u64_le(b, pos)
    lo = SciBin.u32_le(b, pos)
    hi = SciBin.u32_le(b, pos + 4)
    if hi >= 2147483648
      (hi * (2 ** 32)) + lo
    else
      (hi << 32) | lo

  -> .i64_le(b, pos)
    lo = SciBin.u32_le(b, pos)
    hi = SciBin.u32_le(b, pos + 4)
    if hi >= 2147483648
      ((hi - 4294967296) * 4294967296) + lo
    else
      (hi << 32) | lo

  -> .u64_be(b, pos)
    hi = SciBin.u32_be(b, pos)
    lo = SciBin.u32_be(b, pos + 4)
    if hi >= 2147483648
      (hi * (2 ** 32)) + lo
    else
      (hi << 32) | lo

  -> .i64_be(b, pos)
    hi = SciBin.u32_be(b, pos)
    lo = SciBin.u32_be(b, pos + 4)
    if hi >= 2147483648
      ((hi - 4294967296) * 4294967296) + lo
    else
      (hi << 32) | lo

  -> .unpack_f32(b, pos, le)
    u = le ? SciBin.u32_le(b, pos) : SciBin.u32_be(b, pos)
    sign = (u >> 31) & 1
    exp = (u >> 23) & 255
    mant = u & 8388607
    if exp == 0 && mant == 0
      return ~0.0
    if exp == 255
      raise "nonfinite float32 in dataset"
    val = exp == 0 ? Math.ldexp(mant + ~0.0, -149) : Math.ldexp((8388608 + mant) + ~0.0, exp - 150)
    sign == 1 ? ~0.0 - val : val

  -> .unpack_f64(b, pos, le)
    lo = le ? SciBin.u32_le(b, pos) : SciBin.u32_be(b, pos + 4)
    hi = le ? SciBin.u32_le(b, pos + 4) : SciBin.u32_be(b, pos)
    sign = (hi >> 31) & 1
    exp = (hi >> 20) & 2047
    mant_hi = hi & 1048575
    mant = (mant_hi << 32) | lo
    if exp == 0 && mant == 0
      return ~0.0
    if exp == 2047
      raise "nonfinite float64 in dataset"
    val = exp == 0 ? Math.ldexp(mant + ~0.0, -1074) : Math.ldexp((4503599627370496 + mant) + ~0.0, exp - 1075)
    sign == 1 ? ~0.0 - val : val

  -> .pack_f32_le(out, v)
    x = v + ~0.0
    if x != x || x.infinite?
      raise "float32 value must be finite"
    if x == ~0.0
      out.put_u32_le(0)
      return out
    sign = 0
    if x < ~0.0
      sign = 1
      x = ~0.0 - x
    if x > ~3.4028234663852886e38
      raise "float32 overflow"
    e = Math.log2(x).floor.to_i
    if Math.ldexp(~1.0, e) > x
      e -= 1
    elsif Math.ldexp(~1.0, e + 1) <= x
      e += 1
    if e < -126
      mant = Math.ldexp(x, 149).round.to_i
      if mant >= 8388608
        out.put_u32_le((sign << 31) | (1 << 23))
      else
        out.put_u32_le((sign << 31) | mant)
      return out
    mant = Math.ldexp(x, 23 - e).round.to_i - 8388608
    if mant >= 8388608
      mant = 0
      e += 1
    if e > 127
      raise "float32 overflow"
    u = (sign << 31) | ((e + 127) << 23) | (mant & 8388607)
    out.put_u32_le(u)

  -> .pack_f64_le(out, v)
    x = v + ~0.0
    if x != x || x.infinite?
      raise "float64 value must be finite"
    if x == ~0.0
      out.put_u32_le(0)
      out.put_u32_le(0)
      return out
    sign = 0
    if x < ~0.0
      sign = 1
      x = ~0.0 - x
    e = Math.log2(x).floor.to_i
    if Math.ldexp(~1.0, e) > x
      e -= 1
    elsif Math.ldexp(~1.0, e + 1) <= x
      e += 1
    if e < -1022
      mant = Math.ldexp(x, 1074).round.to_i
      lo = mant & 4294967295
      hi = (sign << 31) | ((mant >> 32) & 1048575)
      out.put_u32_le(lo)
      out.put_u32_le(hi)
      return out
    mant = Math.ldexp(x, 52 - e).round.to_i - 4503599627370496
    if mant >= 4503599627370496
      mant = 0
      e += 1
    lo = mant & 4294967295
    hi = (sign << 31) | ((e + 1023) << 20) | ((mant >> 32) & 1048575)
    out.put_u32_le(lo)
    out.put_u32_le(hi)

# ---- RFC 1951 DEFLATE / RFC 1950 zlib / RFC 1952 gzip ----
-> sci_copy_bytes(dst, dst_off, src, src_off, n) (u8[] i64 u8[] i64 i64) i64
  i = 0
  while i < n
    dst[dst_off + i] = src[src_off + i]
    i += 1
  n

-> sci_zlib_compress_kernel(src, n, out) (u8[] i64 u8[]) i64
  out[0] = 120
  out[1] = 1
  out_pos = 2
  pos = 0
  while pos < n || n == 0
    chunk = n - pos
    if chunk > 65535
      chunk = 65535
    last = (pos + chunk >= n) ? 1 : 0
    nchunk = chunk ^ 65535
    out[out_pos] = last
    out[out_pos + 1] = chunk & 255
    out[out_pos + 2] = (chunk >> 8) & 255
    out[out_pos + 3] = nchunk & 255
    out[out_pos + 4] = (nchunk >> 8) & 255
    out_pos += 5
    i = 0
    while i < chunk
      out[out_pos + i] = src[pos + i]
      i += 1
    out_pos += chunk
    pos += chunk
    if n == 0
      break
  s1 = 1
  s2 = 0
  i = 0
  while i < n
    lim = i + 5552
    if lim > n
      lim = n
    while i < lim
      s1 += src[i] ## i64
      s2 += s1
      i += 1
    s1 = s1 % 65521
    s2 = s2 % 65521
  out[out_pos] = (s2 >> 8) & 255
  out[out_pos + 1] = s2 & 255
  out[out_pos + 2] = (s1 >> 8) & 255
  out[out_pos + 3] = s1 & 255
  out_pos + 4

-> sci_build_huffman_kernel(lengths, n, counts, next_code, tab) (i64[] i64 i64[] i64[] i32[]) i64
  i = 0
  while i < n
    l = lengths[i]
    if l > 0
      counts[l] += 1
    i += 1
  code = 0
  bits = 1
  while bits <= 15
    code = (code + counts[bits - 1]) << 1
    next_code[bits] = code
    bits += 1
  i = 0
  while i < n
    l = lengths[i]
    if l > 0
      c = next_code[l]
      next_code[l] = c + 1
      rev = 0
      b = 0
      tmp = c
      while b < l
        rev = (rev << 1) | (tmp & 1)
        tmp = tmp >> 1
        b += 1
      entry = ((i + 1) << 4) | l
      step = (1 ## i64) << l
      idx = rev
      while idx < 32768
        tab[idx] = entry
        idx += step
    i += 1
  0

-> sci_inflate_huffman_kernel(src, src_n, st, lit_tab, dist_tab, lbase, lextra, dbase, dextra, out_buf, out_len, out_cap) (u8[] i64 i64[] i32[] i32[] i64[] i64[] i64[] i64[] u8[] i64 i64) i64
  pos = st[0]
  buf = st[1]
  cnt = st[2]
  while true
    if out_len + 258 > out_cap
      st[0] = pos
      st[1] = buf
      st[2] = cnt
      return 0 - 1 - out_len
    while cnt < 15 && pos < src_n
      buf = buf | ((src[pos] ## i64) << cnt)
      pos += 1
      cnt += 8
    entry = lit_tab[buf & 32767] ## i64
    blen = entry & 15
    if blen == 0 || cnt < blen
      return 0 - 2000000000
    buf = buf >> blen
    cnt -= blen
    sym = (entry >> 4) - 1
    if sym < 256
      out_buf[out_len] = sym
      out_len += 1
    elsif sym == 256
      st[0] = pos
      st[1] = buf
      st[2] = cnt
      return out_len
    else
      lidx = sym - 257
      le = lextra[lidx]
      while cnt < le
        if pos >= src_n
          return 0 - 2000000001
        buf = buf | ((src[pos] ## i64) << cnt)
        pos += 1
        cnt += 8
      length = lbase[lidx] + (buf & (((1 ## i64) << le) - 1))
      buf = buf >> le
      cnt -= le
      while cnt < 15 && pos < src_n
        buf = buf | ((src[pos] ## i64) << cnt)
        pos += 1
        cnt += 8
      dentry = dist_tab[buf & 32767] ## i64
      dblen = dentry & 15
      if dblen == 0 || cnt < dblen
        return 0 - 2000000000
      buf = buf >> dblen
      cnt -= dblen
      didx = (dentry >> 4) - 1
      de = dextra[didx]
      while cnt < de
        if pos >= src_n
          return 0 - 2000000001
        buf = buf | ((src[pos] ## i64) << cnt)
        pos += 1
        cnt += 8
      dist = dbase[didx] + (buf & (((1 ## i64) << de) - 1))
      buf = buf >> de
      cnt -= de
      start = out_len - dist
      k = 0
      while k < length
        out_buf[out_len + k] = out_buf[start + k]
        k += 1
      out_len += length
  out_len

+ SciDeflate
  -> .zlib_compress(src)
    # Use stored DEFLATE blocks inside RFC 1950 zlib framing (valid for any size, exact & fast).
    n = src.size ## i64
    num_blocks = n == 0 ? 1 : (n + 65534) / 65535
    out = u8[2 + num_blocks * 5 + n + 4]
    sci_zlib_compress_kernel(src, n, out)
    out

  -> .zlib_decompress(src)
    if src.size < 6
      raise "zlib stream too short"
    SciDeflate.inflate_raw(src, 2)

  -> .gzip_decompress(src)
    if src.size < 18 || src[0] != 31 || src[1] != 139 || src[2] != 8
      raise "invalid gzip header"
    flg = src[3]
    pos = 10
    if (flg & 4) != 0
      xlen = SciBin.u16_le(src, pos)
      pos += 2 + xlen
    if (flg & 8) != 0
      while pos < src.size && src[pos] != 0
        pos += 1
      pos += 1
    if (flg & 16) != 0
      while pos < src.size && src[pos] != 0
        pos += 1
      pos += 1
    if (flg & 2) != 0
      pos += 2
    SciDeflate.inflate_raw(src, pos)

  -> .build_huffman(lengths, nsyms)
    counts = i64[16]
    next_code = i64[16]
    tab = i32[32768]
    sci_build_huffman_kernel(lengths, nsyms, counts, next_code, tab)
    tab

  -> .read_bits(src, st, nbits)
    # st[0]=byte_pos, st[1]=bit_buf, st[2]=bit_cnt
    buf = st[1]
    cnt = st[2]
    pos = st[0]
    nb = nbits ## i64
    src_n = src.size ## i64
    while cnt < nb
      if pos >= src_n
        raise "unexpected EOF in deflate stream"
      buf = buf | ((src[pos] ## i64) << cnt)
      pos += 1
      cnt += 8
    val = buf & ((1 << nb) - 1)
    st[0] = pos
    st[1] = buf >> nb
    st[2] = cnt - nb
    val

  -> .decode_sym(src, st, table)
    buf = st[1]
    cnt = st[2]
    pos = st[0]
    src_n = src.size ## i64
    while cnt < 15 && pos < src_n
      buf = buf | ((src[pos] ## i64) << cnt)
      pos += 1
      cnt += 8
    entry = table[buf & 32767] ## i64
    blen = entry & 15
    if blen == 0 || cnt < blen
      raise "invalid Huffman code in deflate stream"
    st[0] = pos
    st[1] = buf >> blen
    st[2] = cnt - blen
    (entry >> 4) - 1

  -> .inflate_raw(src, start_pos)
    src_n = src.size ## i64
    st = i64[3]
    st[0] = start_pos ## i64
    st[1] = 0
    st[2] = 0
    init_cap = src_n * 2 + 512
    out = SciByteBuf.new(init_cap)

    if @@fixed_lit == nil
      lbase = i64[29]
      lextra = i64[29]
      lbase_lit = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
      lextra_lit = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
      i = 0
      while i < 29
        lbase[i] = lbase_lit[i] ## i64
        lextra[i] = lextra_lit[i] ## i64
        i += 1
      @@lbase = lbase
      @@lextra = lextra

      dbase = i64[30]
      dextra = i64[30]
      dbase_lit = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
      dextra_lit = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
      i = 0
      while i < 30
        dbase[i] = dbase_lit[i] ## i64
        dextra[i] = dextra_lit[i] ## i64
        i += 1
      @@dbase = dbase
      @@dextra = dextra

      ll = i64[288]
      i = 0
      while i < 144
        ll[i] = 8
        i += 1
      while i < 256
        ll[i] = 9
        i += 1
      while i < 280
        ll[i] = 7
        i += 1
      while i < 288
        ll[i] = 8
        i += 1
      @@fixed_lit = SciDeflate.build_huffman(ll, 288)
      dl = i64[32]
      i = 0
      while i < 32
        dl[i] = 5
        i += 1
      @@fixed_dist = SciDeflate.build_huffman(dl, 32)

    lbase = @@lbase
    lextra = @@lextra
    dbase = @@dbase
    dextra = @@dextra
    cl_order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    bfinal = 0
    while bfinal == 0
      bfinal = SciDeflate.read_bits(src, st, 1)
      btype = SciDeflate.read_bits(src, st, 2)
      if btype == 0
        # Align to byte boundary
        st[1] = 0
        st[2] = 0
        pos = st[0]
        len = SciBin.u16_le(src, pos) ## i64
        nlen = SciBin.u16_le(src, pos + 2) ## i64
        if (len ^ nlen) != 65535
          raise "corrupt stored block length"
        pos += 4
        out.ensure_cap(len)
        sci_copy_bytes(out.buf, out.len, src, pos, len)
        out.len = out.len + len
        st[0] = pos + len
      elsif btype == 1 || btype == 2
        lit_tab = nil
        dist_tab = nil
        if btype == 1
          lit_tab = @@fixed_lit
          dist_tab = @@fixed_dist
        else
          hlit = SciDeflate.read_bits(src, st, 5) + 257
          hdist = SciDeflate.read_bits(src, st, 5) + 1
          hclen = SciDeflate.read_bits(src, st, 4) + 4
          cl_lens = i64[19]
          i = 0
          while i < hclen
            cl_lens[cl_order[i]] = SciDeflate.read_bits(src, st, 3)
            i += 1
          cl_tab = SciDeflate.build_huffman(cl_lens, 19)
          total = hlit + hdist
          lens = i64[total]
          idx = 0
          while idx < total
            s = SciDeflate.decode_sym(src, st, cl_tab)
            if s < 16
              lens[idx] = s
              idx += 1
            elsif s == 16
              rep = SciDeflate.read_bits(src, st, 2) + 3
              prev = lens[idx - 1]
              k = 0
              while k < rep
                lens[idx] = prev
                idx += 1
                k += 1
            elsif s == 17
              rep = SciDeflate.read_bits(src, st, 3) + 3
              k = 0
              while k < rep
                lens[idx] = 0
                idx += 1
                k += 1
            else
              rep = SciDeflate.read_bits(src, st, 7) + 11
              k = 0
              while k < rep
                lens[idx] = 0
                idx += 1
                k += 1
          ll = i64[hlit]
          i = 0
          while i < hlit
            ll[i] = lens[i]
            i += 1
          dl = i64[hdist]
          i = 0
          while i < hdist
            dl[i] = lens[hlit + i]
            i += 1
          lit_tab = SciDeflate.build_huffman(ll, hlit)
          dist_tab = SciDeflate.build_huffman(dl, hdist)

        while true
          if out.len + 258 > out.buf.size
            out.ensure_cap(out.buf.size + 4096)
          res = sci_inflate_huffman_kernel(src, src_n, st, lit_tab, dist_tab, lbase, lextra, dbase, dextra, out.buf, out.len, out.buf.size)
          if res >= 0
            out.len = res
            break
          elsif res == 0 - 2000000000
            raise "invalid Huffman code in deflate stream"
          elsif res == 0 - 2000000001
            raise "unexpected EOF in deflate stream"
          else
            out.len = 0 - 1 - res
            out.ensure_cap(out.buf.size + 4096)
      else
        raise "invalid deflate block type"
    out.to_bytes

# ---- Validation & Value Normalization ----
+ SciValidate
  -> .is_hash?(v)
    type(v) == "Hash"

  -> .is_array?(v)
    type(v) == "Array"

  -> .is_string?(v)
    type(v) == "String"

  -> .is_bool?(v)
    type(v) == "Boolean" || v == true || v == false

  -> .is_int?(v)
    return false if SciValidate.is_bool?(v)
    t = type(v)
    t == "Int" || t == "Fixnum" || t == "BigInt" || t == "Integer"

  -> .is_float?(v)
    type(v) == "Float"

  -> .get_field(rec, kstr, ksym)
    if !SciValidate.is_hash?(rec)
      raise "expected record hash"
    if rec.has_key?(kstr)
      return rec[kstr]
    if rec.has_key?(ksym)
      return rec[ksym]
    nil

  -> .has_field?(rec, kstr, ksym)
    SciValidate.is_hash?(rec) && (rec.has_key?(kstr) || rec.has_key?(ksym))

  -> .check_utf8_text(s, label)
    if !SciValidate.is_string?(s) || s.size == 0
      raise "[label] must be a non-empty string"
    SciValidate.check_utf8_string(s, label)

  -> .check_utf8_string(s, label)
    if !SciValidate.is_string?(s)
      raise "[label] must be a string"
    b = SciBin.str_to_bytes(s)
    i = 0
    while i < b.size
      c = b[i]
      if c < 32 && c != 9 && c != 10 && c != 13
        raise "[label] contains disallowed control character"
      i += 1
    s

  -> .parse_int_val(v)
    if SciValidate.is_bool?(v)
      raise "boolean is not a valid integer"
    if SciValidate.is_int?(v)
      return v
    if SciValidate.is_string?(v)
      if v.size == 0
        raise "empty integer string"
      neg = false
      i = 0
      if v[0] == "-"
        neg = true
        i = 1
      if i >= v.size
        raise "invalid integer string"
      acc = 0
      while i < v.size
        ch = v[i].ord
        if ch < 48 || ch > 57
          raise "invalid integer string"
        acc = acc * 10 + (ch - 48)
        i += 1
      return neg ? 0 - acc : acc
    raise "expected integer value"

  -> .validate_scalar(v, dtype)
    if dtype == "bool"
      if !SciValidate.is_bool?(v)
        raise "expected bool value"
      return v
    if dtype == "float32" || dtype == "float64"
      if SciValidate.is_bool?(v) || (!SciValidate.is_float?(v) && !SciValidate.is_int?(v))
        raise "expected numeric float value"
      f = v + ~0.0
      if f != f || f.infinite?
        raise "float value must be finite"
      if dtype == "float32" && (f > ~3.4028234663852886e38 || f < ~-3.4028234663852886e38)
        raise "float32 value out of range"
      return f
    if dtype == "int32"
      iv = SciValidate.parse_int_val(v)
      if iv < -2147483648 || iv > 2147483647
        raise "int32 value out of range"
      return iv
    if dtype == "int64"
      iv = SciValidate.parse_int_val(v)
      if iv < -9223372036854775808 || iv > 9223372036854775807
        raise "int64 value out of range"
      return iv
    if dtype == "uint32"
      iv = SciValidate.parse_int_val(v)
      if iv < 0 || iv > 4294967295
        raise "uint32 value out of range"
      return iv
    if dtype == "uint64"
      iv = SciValidate.parse_int_val(v)
      max_u64 = (2 ** 64) - 1
      if iv < 0 || iv > max_u64
        raise "uint64 value out of range"
      return iv
    if dtype == "string"
      return SciValidate.check_utf8_string(v, "string value")
    raise "unsupported dtype [dtype]"

  -> .pack_scalar_le(out, v, dtype)
    if dtype == "float32"
      SciBin.pack_f32_le(out, v)
    elsif dtype == "float64"
      SciBin.pack_f64_le(out, v)
    elsif dtype == "int32" || dtype == "uint32"
      out.put_u32_le(v)
    elsif dtype == "int64" || dtype == "uint64"
      out.put_u64_le(v)
    elsif dtype == "bool"
      out.push(v ? 1 : 0)
    else
      raise "unsupported numeric dtype [dtype]"

  -> .unpack_scalar(b, pos, dtype, le)
    if dtype == "float32"
      return SciBin.unpack_f32(b, pos, le)
    if dtype == "float64"
      return SciBin.unpack_f64(b, pos, le)
    if dtype == "int32"
      return le ? SciBin.i32_le(b, pos) : SciBin.i32_be(b, pos)
    if dtype == "uint32"
      return le ? SciBin.u32_le(b, pos) : SciBin.u32_be(b, pos)
    if dtype == "int64"
      return le ? SciBin.i64_le(b, pos) : SciBin.i64_be(b, pos)
    if dtype == "uint64"
      return le ? SciBin.u64_le(b, pos) : SciBin.u64_be(b, pos)
    if dtype == "bool"
      return b[pos] != 0
    raise "unsupported dtype [dtype]"

  -> .dtype_byte_size(dtype)
    if dtype == "bool"
      return 1
    if dtype == "float32" || dtype == "int32" || dtype == "uint32"
      return 4
    if dtype == "float64" || dtype == "int64" || dtype == "uint64"
      return 8
    raise "unsupported dtype [dtype]"


use core/io/interop/hdf5
use core/io/interop/columnar

+ SciIO
  -> .interop_request(request)
    op = SciValidate.get_field(request, "operation", :operation)
    path = SciValidate.get_field(request, "path", :path)
    if op == "hdf5_read"
      return SciHDF5.read_dataset(path, SciValidate.get_field(request, "dataset", :dataset))
    if op == "hdf5_write"
      return SciHDF5.write_standard(path, SciValidate.get_field(request, "datasets", :datasets))
    if op == "parquet_read"
      return SciParquet.read_standard(path)
    if op == "parquet_write"
      return SciParquet.write_standard(path, SciValidate.get_field(request, "table", :table))
    if op == "arrow_read"
      return SciArrow.read_ipc(path)
    if op == "arrow_write"
      return SciArrow.write_ipc(path, SciValidate.get_field(request, "table", :table))
    raise "unknown scientific I/O operation [op]"

  # Result is a shape/dtype/order/values/attributes record. Values are C-order.
  -> .read_hdf5_dataset(path, dataset)
    SciHDF5.read_dataset(path, dataset)

  # Standard HDF5, exclusive create. Existing destinations are never replaced.
  -> .write_hdf5_standard(path, datasets)
    SciHDF5.write_standard(path, datasets)

  -> .read_parquet_standard(path)
    SciParquet.read_standard(path)

  -> .write_parquet_standard(path, table)
    SciParquet.write_standard(path, table)

  -> .read_arrow_ipc(path)
    SciArrow.read_ipc(path)

  -> .write_arrow_ipc(path, table)
    SciArrow.write_ipc(path, table)
