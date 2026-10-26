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
      step = 1 << l
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
      length = lbase[lidx] + (buf & ((1 << le) - 1))
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
      dist = dbase[didx] + (buf & ((1 << de) - 1))
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

# ---- Standard HDF5 Reader & Writer ----
+ SciHDF5
  -> .is_undef_addr?(b, pos, so)
    i = 0
    while i < so
      if b[pos + i] != 255
        return false
      i += 1
    true

  -> .read_addr(b, pos, so)
    if SciHDF5.is_undef_addr?(b, pos, so)
      return -1
    if so == 8
      return SciBin.u64_le(b, pos)
    if so == 4
      return SciBin.u32_le(b, pos)
    v = 0
    i = 0
    while i < so
      v = v | ((b[pos + i] ## i64) << (8 * i))
      i += 1
    v

  -> .read_cstr(b, pos)
    end_pos = pos
    while end_pos < b.size && b[end_pos] != 0
      end_pos += 1
    SciBin.bytes_to_str(SciBin.slice(b, pos, end_pos - pos))

  # Collect all messages in an OHDR v1 or v2 object header (following 0x0010 continuations).
  # Each item is [mtype, mflags, body_u8].
  -> .collect_oh_messages(b, oh_addr, so, sl)
    msgs = []
    if oh_addr < 0 || oh_addr + 6 > b.size
      raise "invalid HDF5 object header address"
    if b[oh_addr] == 79 && b[oh_addr + 1] == 72 && b[oh_addr + 2] == 68 && b[oh_addr + 3] == 82
      # OHDR v2
      ver = b[oh_addr + 4]
      if ver != 2
        raise "unsupported OHDR version"
      fl = b[oh_addr + 5]
      pos = oh_addr + 6
      if (fl & 32) != 0
        pos += 16
      if (fl & 16) != 0
        pos += 4
      csz_len = 1 << (fl & 3)
      csz = SciHDF5.read_addr(b, pos, csz_len)
      pos += csz_len
      chunks = [[pos, pos + csz - 4]]
      ci = 0
      while ci < chunks.size
        cpos = chunks[ci][0]
        cend = chunks[ci][1]
        while cpos + 4 <= cend
          mtype = b[cpos]
          msize = SciBin.u16_le(b, cpos + 1)
          mflags = b[cpos + 3]
          cpos += 4
          if (fl & 4) != 0
            cpos += 2
          body = SciBin.slice(b, cpos, msize)
          cpos += msize
          if mtype == 16
            # Object Header Continuation: addr(so) + len(sl) -> "OCHK" + messages + 4-byte checksum
            cont_addr = SciHDF5.read_addr(b, 0, so)
            cont_len = SciHDF5.read_addr(body, so, sl)
            cont_addr = SciHDF5.read_addr(body, 0, so)
            chunks.push([cont_addr + 4, cont_addr + cont_len - 4])
          elsif mtype != 0
            msgs.push([mtype, mflags, body])
        ci += 1
    else
      # OHDR v1
      ver = b[oh_addr]
      if ver != 1
        raise "unsupported HDF5 object header v1"
      nmsgs = SciBin.u16_le(b, oh_addr + 2)
      hdr_sz = SciBin.u32_le(b, oh_addr + 8)
      chunks = [[oh_addr + 16, oh_addr + 16 + hdr_sz]]
      ci = 0
      seen = 0
      while ci < chunks.size
        cpos = chunks[ci][0]
        cend = chunks[ci][1]
        while cpos + 8 <= cend && seen < nmsgs
          mtype = SciBin.u16_le(b, cpos)
          msize = SciBin.u16_le(b, cpos + 2)
          mflags = b[cpos + 4]
          cpos += 8
          body = SciBin.slice(b, cpos, msize)
          cpos += msize
          seen += 1
          if mtype == 16
            cont_addr = SciHDF5.read_addr(body, 0, so)
            cont_len = SciHDF5.read_addr(body, so, sl)
            chunks.push([cont_addr, cont_addr + cont_len])
          elsif mtype != 0
            msgs.push([mtype, mflags, body])
        ci += 1
    msgs

  -> .collect_group_btree(b, tree_addr, heap_data_seg, so, sl, links)
    if tree_addr < 0 || tree_addr + 8 > b.size
      return links
    if b[tree_addr] != 84 || b[tree_addr + 1] != 82 || b[tree_addr + 2] != 69 || b[tree_addr + 3] != 69
      return links
    ntype = b[tree_addr + 4]
    nlevel = b[tree_addr + 5]
    entries = SciBin.u16_le(b, tree_addr + 6)
    if ntype != 0
      return links
    pos = tree_addr + 8 + 2 * so
    i = 0
    while i < entries
      pos += sl
      child_addr = SciHDF5.read_addr(b, pos, so)
      pos += so
      if nlevel > 0
        SciHDF5.collect_group_btree(b, child_addr, heap_data_seg, so, sl, links)
      else
        # SNOD at child_addr
        if child_addr >= 0 && child_addr + 8 <= b.size && b[child_addr] == 83 && b[child_addr + 1] == 78 && b[child_addr + 2] == 79 && b[child_addr + 3] == 68
          nsyms = SciBin.u16_le(b, child_addr + 6)
          spos = child_addr + 8
          s = 0
          while s < nsyms
            name_off = SciHDF5.read_addr(b, spos, so)
            obj_oh = SciHDF5.read_addr(b, spos + so, so)
            name = SciHDF5.read_cstr(b, heap_data_seg + name_off)
            if name.size > 0 && obj_oh >= 0
              links[name] = obj_oh
            spos += 2 * so + 24
            s += 1
      i += 1
    links

  -> .group_links(b, oh_addr, so, sl)
    msgs = SciHDF5.collect_oh_messages(b, oh_addr, so, sl)
    links = {}
    i = 0
    while i < msgs.size
      mtype = msgs[i][0]
      body = msgs[i][2]
      if mtype == 6
        # Link message
        lver = body[0]
        lfl = body[1]
        off = 2
        ltype = 0
        if (lfl & 8) != 0
          ltype = body[off]
          off += 1
        if (lfl & 4) != 0
          off += 8
        if (lfl & 16) != 0
          off += 1
        nlen_sz = 1 << (lfl & 3)
        nlen = SciHDF5.read_addr(body, off, nlen_sz)
        off += nlen_sz
        name = SciBin.bytes_to_str(SciBin.slice(body, off, nlen))
        off += nlen
        if ltype == 0
          targ = SciHDF5.read_addr(body, off, so)
          links[name] = targ
      elsif mtype == 17
        # Symbol table message (btree_addr + heap_addr)
        btree_addr = SciHDF5.read_addr(body, 0, so)
        heap_addr = SciHDF5.read_addr(body, so, so)
        if heap_addr >= 0 && b[heap_addr] == 72 && b[heap_addr + 1] == 69 && b[heap_addr + 2] == 65 && b[heap_addr + 3] == 80
          heap_data_seg = SciHDF5.read_addr(body.size >= 0 ? b : b, heap_addr + 8 + 2 * sl, so)
          SciHDF5.collect_group_btree(b, btree_addr, heap_data_seg, so, sl, links)
      i += 1
    links

  -> .parse_dtype_msg(body)
    cls_ver = body[0]
    tcls = cls_ver & 15
    bf0 = body[1]
    bf1 = body[2]
    bf2 = body[3]
    tsz = SciBin.u32_le(body, 4)
    le = (bf0 & 1) == 0
    if tcls == 0
      # Fixed-point integer
      sgn = (bf0 & 8) != 0
      if tsz == 4
        return [sgn ? "int32" : "uint32", 4, le, 0]
      if tsz == 8
        return [sgn ? "int64" : "uint64", 8, le, 0]
      if tsz == 1 && !sgn
        return ["uint8", 1, le, 0]
      raise "unsupported integer byte width [tsz]"
    if tcls == 1
      if tsz == 4
        return ["float32", 4, le, 1]
      if tsz == 8
        return ["float64", 8, le, 1]
      raise "unsupported float byte width [tsz]"
    if tcls == 3
      return ["fixed_string", tsz, true, 3]
    if tcls == 8
      if tsz == 1
        return ["bool", 1, true, 8]
      raise "unsupported enum datatype"
    if tcls == 9
      # Variable-length: bf0 & 15 == 1 means string
      if (bf0 & 15) == 1
        return ["vlen_string", tsz, true, 9]
      raise "unsupported variable-length datatype"
    raise "unsupported HDF5 datatype class [tcls]"

  -> .parse_dataspace_msg(body)
    ver = body[0]
    rank = body[1]
    flags = body[2]
    off = ver == 1 ? 8 : 4
    if ver == 2 && body.size > 3 && body[3] == 2
      # null dataspace
      return [[], 0]
    shape = []
    nelem = 1
    i = 0
    while i < rank
      d = SciBin.u64_le(body, off + i * 8)
      shape.push(d)
      nelem = nelem * d
      i += 1
    [shape, nelem]

  -> .read_gcol_object(b, gcol_addr, obj_idx, so, sl)
    if gcol_addr < 0 || gcol_addr + 16 > b.size
      raise "invalid GCOL address"
    if b[gcol_addr] != 71 || b[gcol_addr + 1] != 67 || b[gcol_addr + 2] != 79 || b[gcol_addr + 3] != 76
      raise "missing GCOL signature"
    col_sz = SciHDF5.read_addr(b, gcol_addr + 8, sl)
    pos = gcol_addr + 8 + sl
    end_pos = gcol_addr + col_sz
    while pos + 8 + sl <= end_pos
      idx = SciBin.u16_le(b, pos)
      if idx == 0
        break
      osz = SciHDF5.read_addr(b, pos + 8, sl)
      pos += 8 + sl
      if idx == obj_idx
        return SciBin.slice(b, pos, osz)
      pad = (8 - (osz % 8)) % 8
      pos += osz + pad
    raise "GCOL object not found"

  -> .parse_attribute_msg(b, body, so, sl)
    ver = body[0]
    flags = body[1]
    name_sz = SciBin.u16_le(body, 2)
    dt_sz = SciBin.u16_le(body, 4)
    ds_sz = SciBin.u16_le(body, 6)
    pos = 8
    if ver == 3
      pos += 1
    name_raw = SciBin.slice(body, pos, name_sz)
    # Trim trailing NUL
    nlen = name_raw.size
    while nlen > 0 && name_raw[nlen - 1] == 0
      nlen -= 1
    name = SciBin.bytes_to_str(SciBin.slice(name_raw, 0, nlen))
    if ver == 1
      pos += name_sz + ((8 - (name_sz % 8)) % 8)
    else
      pos += name_sz
    dt_body = SciBin.slice(body, pos, dt_sz)
    if ver == 1
      pos += dt_sz + ((8 - (dt_sz % 8)) % 8)
    else
      pos += dt_sz
    ds_body = SciBin.slice(body, pos, ds_sz)
    if ver == 1
      pos += ds_sz + ((8 - (ds_sz % 8)) % 8)
    else
      pos += ds_sz
    dt_info = SciHDF5.parse_dtype_msg(dt_body)
    ds_info = SciHDF5.parse_dataspace_msg(ds_body)
    dtype = dt_info[0]
    tsz = dt_info[1]
    le = dt_info[2]
    if dtype == "vlen_string"
      vlen = SciBin.u32_le(body, pos)
      gcol_addr = SciHDF5.read_addr(body, pos + 4, so)
      gcol_idx = SciBin.u32_le(body, pos + 4 + so)
      raw_str = SciHDF5.read_gcol_object(b, gcol_addr, gcol_idx, so, sl)
      return [name, SciBin.bytes_to_str(SciBin.slice(raw_str, 0, vlen))]
    if dtype == "fixed_string"
      raw_str = SciBin.slice(body, pos, tsz)
      slen = raw_str.size
      while slen > 0 && raw_str[slen - 1] == 0
        slen -= 1
      return [name, SciBin.bytes_to_str(SciBin.slice(raw_str, 0, slen))]
    [name, SciValidate.unpack_scalar(body, pos, dtype, le)]

  -> .collect_chunk_btree_v1(b, tree_addr, rank, so, out_chunks)
    # Each entry in out_chunks is [coords_array, chunk_addr, chunk_nbytes, filter_mask]
    if tree_addr < 0 || tree_addr + 8 > b.size
      return out_chunks
    if b[tree_addr] != 84 || b[tree_addr + 1] != 82 || b[tree_addr + 2] != 69 || b[tree_addr + 3] != 69
      raise "missing TREE signature in chunk B-tree"
    nlevel = b[tree_addr + 5]
    entries = SciBin.u16_le(b, tree_addr + 6)
    pos = tree_addr + 8 + 2 * so
    ndims = rank + 1
    i = 0
    while i < entries
      nbytes = SciBin.u32_le(b, pos)
      fmask = SciBin.u32_le(b, pos + 4)
      pos += 8
      coords = []
      d = 0
      while d < ndims
        coords.push(SciBin.u64_le(b, pos))
        pos += 8
        d += 1
      child_addr = SciHDF5.read_addr(b, pos, so)
      pos += so
      if nlevel > 0
        SciHDF5.collect_chunk_btree_v1(b, child_addr, rank, so, out_chunks)
      else
        out_chunks.push([coords, child_addr, nbytes, fmask])
      i += 1
    out_chunks

  -> .scatter_chunk(raw_chunk, coords, chunk_dims, shape, tsz, dtype, le, values)
    rank = shape.size
    if rank == 1
      c0 = coords[0]
      n0 = chunk_dims[0]
      i = 0
      while i < n0 && (c0 + i) < shape[0]
        values[c0 + i] = SciValidate.unpack_scalar(raw_chunk, i * tsz, dtype, le)
        i += 1
      return values
    # General rank-N scatter from chunk coordinates into C-order flat array
    chunk_nelem = 1
    d = 0
    while d < rank
      chunk_nelem = chunk_nelem * chunk_dims[d]
      d += 1
    idx = 0
    while idx < chunk_nelem
      rem = idx
      in_bounds = true
      flat_dst = 0
      dst_stride = 1
      d = rank - 1
      while d >= 0
        cd = chunk_dims[d]
        local_c = rem % cd
        rem = rem / cd
        global_c = coords[d] + local_c
        if global_c >= shape[d]
          in_bounds = false
        flat_dst = flat_dst + global_c * dst_stride
        dst_stride = dst_stride * shape[d]
        d -= 1
      if in_bounds
        values[flat_dst] = SciValidate.unpack_scalar(raw_chunk, idx * tsz, dtype, le)
      idx += 1
    values

  -> .index_to_chunk_coords(chunk_idx, shape, chunk_dims)
    rank = shape.size
    grid = i64[rank]
    d = 0
    while d < rank
      grid[d] = (shape[d] + chunk_dims[d] - 1) / chunk_dims[d]
      d += 1
    coords = i64[rank]
    rem = chunk_idx
    d = rank - 1
    while d >= 0
      coords[d] = (rem % grid[d]) * chunk_dims[d]
      rem = rem / grid[d]
      d -= 1
    coords

  -> .read_dataset(path, dataset_path)
    b = File.read_bytes(path)
    if b.size < 16 || b[0] != 137 || b[1] != 72 || b[2] != 68 || b[3] != 70 || b[4] != 13 || b[5] != 10 || b[6] != 26 || b[7] != 10
      raise "not a valid HDF5 file"
    sb_ver = b[8]
    so = 8
    sl = 8
    root_oh = -1
    if sb_ver == 0 || sb_ver == 1
      so = b[13]
      sl = b[14]
      off = sb_ver == 1 ? 28 : 24
      root_oh = SciHDF5.read_addr(b, off + 5 * so, so)
    elsif sb_ver == 2 || sb_ver == 3
      so = b[9]
      sl = b[10]
      root_oh = SciHDF5.read_addr(b, 12 + 3 * so, so)
    else
      raise "unsupported HDF5 superblock version [sb_ver]"

    parts = dataset_path.split("/")
    cur_oh = root_oh
    pi = 0
    while pi < parts.size
      part = parts[pi]
      if part.size > 0
        links = SciHDF5.group_links(b, cur_oh, so, sl)
        if links.has_key?(part) == false
          raise "HDF5 dataset or group not found: [dataset_path]"
        cur_oh = links[part]
      pi += 1

    msgs = SciHDF5.collect_oh_messages(b, cur_oh, so, sl)
    shape = []
    nelem = 0
    dtype = nil
    tsz = 0
    le = true
    compression = nil
    chunks = nil
    layout_body = nil
    attrs = {}

    i = 0
    while i < msgs.size
      mtype = msgs[i][0]
      body = msgs[i][2]
      if mtype == 1
        ds_info = SciHDF5.parse_dataspace_msg(body)
        shape = ds_info[0]
        nelem = ds_info[1]
      elsif mtype == 3
        dt_info = SciHDF5.parse_dtype_msg(body)
        dtype = dt_info[0]
        tsz = dt_info[1]
        le = dt_info[2]
      elsif mtype == 8
        layout_body = body
      elsif mtype == 11
        # Filter pipeline (v1 or v2)
        fver = body[0]
        nfilt = body[1]
        if nfilt > 0
          fid = fver == 1 ? SciBin.u16_le(body, 8) : SciBin.u16_le(body, 2)
          if fid == 1
            compression = "gzip"
          else
            raise "unsupported HDF5 filter id [fid]"
      elsif mtype == 12
        kv = SciHDF5.parse_attribute_msg(b, body, so, sl)
        attrs[kv[0]] = kv[1]
      i += 1

    if dtype == nil || layout_body == nil
      raise "incomplete HDF5 dataset header"
    if nelem > 1000000
      raise "dataset exceeds 1000000 value limit"

    values = []
    i = 0
    while i < nelem
      values.push(0)
      i += 1

    lver = layout_body[0]
    lcls = layout_body[1]
    if lcls == 0
      # Compact layout
      csz = SciBin.u16_le(layout_body, 2)
      cpos = 4
      i = 0
      while i < nelem
        values[i] = SciValidate.unpack_scalar(layout_body, cpos + i * tsz, dtype, le)
        i += 1
    elsif lcls == 1
      # Contiguous layout
      data_addr = SciHDF5.read_addr(layout_body, 2, so)
      if nelem > 0 && data_addr >= 0
        i = 0
        while i < nelem
          values[i] = SciValidate.unpack_scalar(b, data_addr + i * tsz, dtype, le)
          i += 1
    elsif lcls == 2
      # Chunked layout
      if lver == 3
        ndims = layout_body[2]
        btree_addr = SciHDF5.read_addr(layout_body, 3, so)
        chunks = []
        d = 0
        while d < shape.size
          chunks.push(SciBin.u32_le(layout_body, 3 + so + d * 4))
          d += 1
        if nelem > 0 && btree_addr >= 0
          clist = []
          SciHDF5.collect_chunk_btree_v1(b, btree_addr, shape.size, so, clist)
          ci = 0
          while ci < clist.size
            ce = clist[ci]
            c_coords = ce[0]
            c_addr = ce[1]
            c_nbytes = ce[2]
            c_fmask = ce[3]
            raw_c = SciBin.slice(b, c_addr, c_nbytes)
            if compression == "gzip" && (c_fmask & 1) == 0
              raw_c = SciDeflate.zlib_decompress(raw_c)
            SciHDF5.scatter_chunk(raw_c, c_coords, chunks, shape, tsz, dtype, le, values)
            ci += 1
      elsif lver == 4 || lver == 5
        lflags = layout_body[2]
        ndims = layout_body[3]
        enc_len = layout_body[4]
        chunks = []
        pos = 5
        d = 0
        while d < shape.size
          chunks.push(SciHDF5.read_addr(layout_body, pos, enc_len))
          pos += enc_len
          d += 1
        pos += enc_len # skip element size dimension
        idx_type = layout_body[pos]
        pos += 1
        if idx_type == 1
          # Single Chunk
          if (lflags & 2) != 0
            c_nbytes = SciHDF5.read_addr(layout_body, pos, sl)
            c_fmask = SciBin.u32_le(layout_body, pos + sl)
            pos += sl + 4
            c_addr = SciHDF5.read_addr(layout_body, pos, so)
            if nelem > 0 && c_addr >= 0
              raw_c = SciBin.slice(b, c_addr, c_nbytes)
              if compression == "gzip" && (c_fmask & 1) == 0
                raw_c = SciDeflate.zlib_decompress(raw_c)
              zero_coords = i64[shape.size]
              SciHDF5.scatter_chunk(raw_c, zero_coords, chunks, shape, tsz, dtype, le, values)
          else
            c_addr = SciHDF5.read_addr(layout_body, pos, so)
            if nelem > 0 && c_addr >= 0
              chunk_bytes = nelem * tsz
              raw_c = SciBin.slice(b, c_addr, chunk_bytes)
              zero_coords = i64[shape.size]
              SciHDF5.scatter_chunk(raw_c, zero_coords, chunks, shape, tsz, dtype, le, values)
        elsif idx_type == 3
          # Fixed Array (FAHD -> FADB)
          pos += 1 # page_bits
          fahd_addr = SciHDF5.read_addr(layout_body, pos, so)
          if nelem > 0 && fahd_addr >= 0
            if b[fahd_addr] != 70 || b[fahd_addr + 1] != 65 || b[fahd_addr + 2] != 72 || b[fahd_addr + 3] != 68
              raise "missing FAHD signature"
            client_id = b[fahd_addr + 5]
            entry_sz = b[fahd_addr + 6]
            nelts = SciHDF5.read_addr(b, fahd_addr + 8, sl)
            fadb_addr = SciHDF5.read_addr(b, fahd_addr + 8 + sl, so)
            if fadb_addr >= 0
              if b[fadb_addr] != 70 || b[fadb_addr + 1] != 65 || b[fadb_addr + 2] != 68 || b[fadb_addr + 3] != 66
                raise "missing FADB signature"
              epos = fadb_addr + 6 + so
              ci = 0
              while ci < nelts
                c_addr = SciHDF5.read_addr(b, epos, so)
                c_nbytes = 0
                c_fmask = 0
                if client_id == 1
                  nbytes_len = entry_sz - so - 4
                  c_nbytes = SciHDF5.read_addr(b, epos + so, nbytes_len)
                  c_fmask = SciBin.u32_le(b, epos + so + nbytes_len)
                else
                  c_nbytes = entry_sz
                epos += entry_sz
                if c_addr >= 0
                  raw_c = SciBin.slice(b, c_addr, c_nbytes)
                  if compression == "gzip" && (c_fmask & 1) == 0
                    raw_c = SciDeflate.zlib_decompress(raw_c)
                  coords = SciHDF5.index_to_chunk_coords(ci, shape, chunks)
                  SciHDF5.scatter_chunk(raw_c, coords, chunks, shape, tsz, dtype, le, values)
                ci += 1
        else
          raise "unsupported HDF5 v4 chunk index type [idx_type]"
    else
      raise "unsupported HDF5 layout class [lcls]"

    {"dtype" => dtype, "shape" => shape, "order" => "C", "values" => values, "attributes" => attrs, "chunks" => chunks, "compression" => compression}

  -> .encode_dtype_msg(dtype)
    out = SciByteBuf.new(36)
    if dtype == "float32"
      bytes = [17, 32, 31, 0, 4, 0, 0, 0, 0, 0, 32, 0, 23, 8, 0, 23, 127, 0, 0, 0]
      i = 0
      while i < bytes.size
        out.push(bytes[i])
        i += 1
    elsif dtype == "float64"
      bytes = [17, 32, 63, 0, 8, 0, 0, 0, 0, 0, 64, 0, 52, 11, 0, 52, 255, 3, 0, 0]
      i = 0
      while i < bytes.size
        out.push(bytes[i])
        i += 1
    elsif dtype == "int32"
      bytes = [16, 8, 0, 0, 4, 0, 0, 0, 0, 0, 32, 0]
      i = 0
      while i < bytes.size
        out.push(bytes[i])
        i += 1
    elsif dtype == "uint32"
      bytes = [16, 0, 0, 0, 4, 0, 0, 0, 0, 0, 32, 0]
      i = 0
      while i < bytes.size
        out.push(bytes[i])
        i += 1
    elsif dtype == "int64"
      bytes = [16, 8, 0, 0, 8, 0, 0, 0, 0, 0, 64, 0]
      i = 0
      while i < bytes.size
        out.push(bytes[i])
        i += 1
    elsif dtype == "uint64"
      bytes = [16, 0, 0, 0, 8, 0, 0, 0, 0, 0, 64, 0]
      i = 0
      while i < bytes.size
        out.push(bytes[i])
        i += 1
    elsif dtype == "bool"
      bytes = [88, 2, 0, 0, 1, 0, 0, 0, 16, 8, 0, 0, 1, 0, 0, 0, 0, 0, 8, 0, 70, 65, 76, 83, 69, 0, 84, 82, 85, 69, 0, 0, 1]
      i = 0
      while i < bytes.size
        out.push(bytes[i])
        i += 1
    else
      raise "unsupported HDF5 dtype [dtype]"
    out.to_bytes

  -> .wrap_oh1_msg(mtype, flags, body)
    out = SciByteBuf.new(body.size + 16)
    pad = (8 - (body.size % 8)) % 8
    out.put_u16_le(mtype)
    out.put_u16_le(body.size + pad)
    out.push(flags)
    out.extend_zeros(3)
    out.extend(body)
    out.extend_zeros(pad)
    out.to_bytes

  -> .build_oh1(msgs)
    total = 0
    i = 0
    while i < msgs.size
      total += msgs[i].size
      i += 1
    out = SciByteBuf.new(16 + total)
    out.push(1)
    out.push(0)
    out.put_u16_le(msgs.size)
    out.put_u32_le(1)
    out.put_u32_le(total)
    out.put_u32_le(0)
    i = 0
    while i < msgs.size
      out.extend(msgs[i])
      i += 1
    out.to_bytes

  -> .build_link_msg(name, target_addr)
    nb = SciBin.str_to_bytes(name)
    body = SciByteBuf.new(nb.size + 16)
    body.push(1)
    body.push(0)
    body.push(nb.size)
    body.extend(nb)
    body.put_u64_le(target_addr)
    SciHDF5.wrap_oh1_msg(6, 0, body.to_bytes)

  -> .build_group_oh1(child_pairs)
    msgs = []
    # Link Info message (0x0002)
    li = SciByteBuf.new(18)
    li.push(0)
    li.push(0)
    li.put_u64_le(-1)
    li.put_u64_le(-1)
    msgs.push(SciHDF5.wrap_oh1_msg(2, 0, li.to_bytes))
    # Group Info message (0x000A)
    gi = SciByteBuf.new(2)
    gi.push(0)
    gi.push(0)
    msgs.push(SciHDF5.wrap_oh1_msg(10, 1, gi.to_bytes))
    i = 0
    while i < child_pairs.size
      msgs.push(SciHDF5.build_link_msg(child_pairs[i][0], child_pairs[i][1]))
      i += 1
    SciHDF5.build_oh1(msgs)

  -> .write_standard(path, datasets)
    if File.exist?(path)
      raise "refusing to overwrite existing HDF5 file: [path]"
    if !SciValidate.is_hash?(datasets) || datasets.keys.size == 0
      raise "datasets must be a non-empty hash"

    # 1. Validate all dataset specs first before touching disk
    prepared = []
    gcol_strings = []
    dkeys = datasets.keys
    di = 0
    while di < dkeys.size
      raw_key = dkeys[di]
      dname = SciValidate.check_utf8_text(raw_key.to_s, "dataset name")
      parts = []
      raw_parts = dname.split("/")
      pi = 0
      while pi < raw_parts.size
        if raw_parts[pi].size > 0
          parts.push(raw_parts[pi])
        pi += 1
      if parts.size == 0
        raise "invalid dataset path [dname]"
      spec = datasets[raw_key]
      dtype = SciValidate.get_field(spec, "dtype", :dtype)
      shape = SciValidate.get_field(spec, "shape", :shape)
      vals = SciValidate.get_field(spec, "values", :values)
      attrs = SciValidate.get_field(spec, "attributes", :attributes)
      comp = SciValidate.get_field(spec, "compression", :compression)
      if !SciValidate.is_string?(dtype)
        raise "dataset dtype must be a string"
      tsz = SciValidate.dtype_byte_size(dtype)
      if !SciValidate.is_array?(shape) || !SciValidate.is_array?(vals)
        raise "dataset shape and values must be arrays"
      nelem = 1
      si = 0
      while si < shape.size
        dim = shape[si]
        if !SciValidate.is_int?(dim) || dim < 0
          raise "invalid shape dimension"
        nelem = nelem * dim
        si += 1
      if nelem > 1000000
        raise "dataset exceeds 1000000 value limit"
      if vals.size != nelem
        raise "dataset values length ([vals.size]) does not match shape product ([nelem])"
      if comp != nil && comp != "gzip"
        raise "unsupported compression [comp]"
      if comp == "gzip" && shape.size == 0
        raise "gzip compression is not supported on scalar datasets"

      raw_buf = SciByteBuf.new(nelem * tsz + 8)
      vi = 0
      while vi < nelem
        cv = SciValidate.validate_scalar(vals[vi], dtype)
        SciValidate.pack_scalar_le(raw_buf, cv, dtype)
        vi += 1

      prep_attrs = []
      if attrs != nil
        if !SciValidate.is_hash?(attrs)
          raise "attributes must be a hash"
        akeys = attrs.keys
        ai = 0
        while ai < akeys.size
          ak = akeys[ai]
          aname = SciValidate.check_utf8_text(ak.to_s, "attribute name")
          aval = attrs[ak]
          if SciValidate.is_string?(aval)
            SciValidate.check_utf8_string(aval, "attribute string")
            gcol_strings.push(SciBin.str_to_bytes(aval))
            prep_attrs.push([aname, "vlen_string", aval, gcol_strings.size])
          elsif SciValidate.is_bool?(aval)
            prep_attrs.push([aname, "bool", aval, 0])
          elsif SciValidate.is_int?(aval)
            SciValidate.validate_scalar(aval, "int64")
            prep_attrs.push([aname, "int64", aval, 0])
          elsif SciValidate.is_float?(aval)
            SciValidate.validate_scalar(aval, "float64")
            prep_attrs.push([aname, "float64", aval, 0])
          else
            raise "unsupported attribute value type"
          ai += 1

      prepared.push([parts, dtype, tsz, shape, nelem, raw_buf.to_bytes, comp, prep_attrs])
      di += 1

    # 2. Layout file:
    #    0..96: Superblock v0 placeholder
    #    Then data payloads, B-trees, and GCOL collection so we know their exact addresses!
    file_buf = SciByteBuf.new(4096)
    file_buf.extend_zeros(96)

    gcol_addr = 0
    if gcol_strings.size > 0
      file_buf.align(8)
      gcol_addr = file_buf.len
      # Compute GCOL size (at least 4096 bytes)
      objs_buf = SciByteBuf.new(512)
      gi = 0
      while gi < gcol_strings.size
        sb = gcol_strings[gi]
        objs_buf.put_u16_le(gi + 1)
        objs_buf.put_u16_le(0)
        objs_buf.put_u32_le(0)
        objs_buf.put_u64_le(sb.size)
        objs_buf.extend(sb)
        objs_buf.align(8)
        gi += 1
      col_sz = 4096
      while col_sz < 16 + objs_buf.len + 16
        col_sz = col_sz * 2
      free_rem = col_sz - 16 - objs_buf.len
      file_buf.extend(SciBin.str_to_bytes("GCOL"))
      file_buf.push(1)
      file_buf.extend_zeros(3)
      file_buf.put_u64_le(col_sz)
      file_buf.extend(objs_buf.to_bytes)
      # Object 0 free space header
      file_buf.put_u16_le(0)
      file_buf.put_u16_le(0)
      file_buf.put_u32_le(0)
      file_buf.put_u64_le(free_rem)
      file_buf.extend_zeros(free_rem - 16)

    # 3. Emit dataset payloads, B-trees, and dataset OHDR v1 blocks
    ds_addrs = []
    pi = 0
    while pi < prepared.size
      item = prepared[pi]
      parts = item[0]
      dtype = item[1]
      tsz = item[2]
      shape = item[3]
      nelem = item[4]
      raw_bytes = item[5]
      comp = item[6]
      prep_attrs = item[7]

      msgs = []
      # Dataspace v1
      ds_msg = SciByteBuf.new(16 + shape.size * 16)
      ds_msg.push(1)
      ds_msg.push(shape.size)
      ds_msg.push(0)
      ds_msg.extend_zeros(5)
      si = 0
      while si < shape.size
        ds_msg.put_u64_le(shape[si])
        si += 1
      msgs.push(SciHDF5.wrap_oh1_msg(1, 0, ds_msg.to_bytes))

      # Datatype
      msgs.push(SciHDF5.wrap_oh1_msg(3, 1, SciHDF5.encode_dtype_msg(dtype)))

      # Fill value (v2: space alloc late, default fill)
      fv_msg = SciByteBuf.new(8)
      fv_msg.push(2)
      fv_msg.push(3)
      fv_msg.push(2)
      fv_msg.push(0)
      msgs.push(SciHDF5.wrap_oh1_msg(5, 1, fv_msg.to_bytes))

      if comp == "gzip" && shape.size > 0
        # Filter pipeline v1: deflate (id=1)
        fp_bytes = [1, 1, 0, 0, 0, 0, 0, 0, 1, 0, 8, 0, 1, 0, 1, 0, 100, 101, 102, 108, 97, 116, 101, 0, 4, 0, 0, 0, 0, 0, 0, 0]
        fp_buf = SciByteBuf.new(32)
        fi = 0
        while fi < fp_bytes.size
          fp_buf.push(fp_bytes[fi])
          fi += 1
        msgs.push(SciHDF5.wrap_oh1_msg(11, 1, fp_buf.to_bytes))

        # Compress single chunk covering shape (or 1 element per dim if empty)
        cdims = []
        si = 0
        while si < shape.size
          cdims.push(shape[si] > 0 ? shape[si] : 1)
          si += 1
        comp_bytes = SciDeflate.zlib_compress(raw_bytes)
        file_buf.align(8)
        chunk_addr = file_buf.len
        file_buf.extend(comp_bytes)

        # B-tree v1 node (must reserve 2*K = 64 entries for libhdf5 default K=32!)
        file_buf.align(8)
        btree_addr = file_buf.len
        ndims = shape.size + 1
        key_sz = 8 + ndims * 8
        tree_total_sz = 24 + 64 * (key_sz + 8) + key_sz
        tbuf = SciByteBuf.new(tree_total_sz)
        tbuf.extend(SciBin.str_to_bytes("TREE"))
        tbuf.push(1)
        tbuf.push(0)
        tbuf.put_u16_le(nelem > 0 ? 1 : 0)
        tbuf.put_u64_le(-1)
        tbuf.put_u64_le(-1)
        if nelem > 0
          tbuf.put_u32_le(comp_bytes.size)
          tbuf.put_u32_le(0)
          di2 = 0
          while di2 < ndims
            tbuf.put_u64_le(0)
            di2 += 1
          tbuf.put_u64_le(chunk_addr)
          tbuf.put_u32_le(0)
          tbuf.put_u32_le(0)
          si = 0
          while si < shape.size
            tbuf.put_u64_le(cdims[si])
            si += 1
          tbuf.put_u64_le(tsz)
        tbuf.extend_zeros(tree_total_sz - tbuf.len)
        file_buf.extend(tbuf.to_bytes)

        # Layout v3 chunked
        lbuf = SciByteBuf.new(16 + ndims * 4)
        lbuf.push(3)
        lbuf.push(2)
        lbuf.push(ndims)
        lbuf.put_u64_le(nelem > 0 ? btree_addr : -1)
        si = 0
        while si < cdims.size
          lbuf.put_u32_le(cdims[si])
          si += 1
        lbuf.put_u32_le(tsz)
        msgs.push(SciHDF5.wrap_oh1_msg(8, 0, lbuf.to_bytes))
      else
        # Contiguous layout v3
        data_addr = -1
        if nelem > 0
          file_buf.align(8)
          data_addr = file_buf.len
          file_buf.extend(raw_bytes)
        lbuf = SciByteBuf.new(18)
        lbuf.push(3)
        lbuf.push(1)
        lbuf.put_u64_le(data_addr)
        lbuf.put_u64_le(nelem * tsz)
        msgs.push(SciHDF5.wrap_oh1_msg(8, 0, lbuf.to_bytes))

      # Attributes (v1)
      ai = 0
      while ai < prep_attrs.size
        pa = prep_attrs[ai]
        aname = pa[0]
        atype = pa[1]
        aval = pa[2]
        gidx = pa[3]
        nb = SciBin.str_to_bytes(aname)
        name_len = nb.size + 1
        name_pad = (8 - (name_len % 8)) % 8
        dt_bytes = nil
        val_buf = SciByteBuf.new(16)
        if atype == "vlen_string"
          # 20-byte vlen UTF-8 string datatype
          vdt = [25, 1, 1, 0, 16, 0, 0, 0, 16, 0, 0, 0, 1, 0, 0, 0, 0, 0, 8, 0]
          dtb = SciByteBuf.new(20)
          vi = 0
          while vi < vdt.size
            dtb.push(vdt[vi])
            vi += 1
          dt_bytes = dtb.to_bytes
          sb = SciBin.str_to_bytes(aval)
          val_buf.put_u32_le(sb.size)
          val_buf.put_u64_le(gcol_addr)
          val_buf.put_u32_le(gidx)
        else
          dt_bytes = SciHDF5.encode_dtype_msg(atype)
          SciValidate.pack_scalar_le(val_buf, aval, atype)
        dt_pad = (8 - (dt_bytes.size % 8)) % 8
        abuf = SciByteBuf.new(64)
        abuf.push(1)
        abuf.push(0)
        abuf.put_u16_le(name_len)
        abuf.put_u16_le(dt_bytes.size)
        abuf.put_u16_le(8)
        abuf.extend(nb)
        abuf.push(0)
        abuf.extend_zeros(name_pad)
        abuf.extend(dt_bytes)
        abuf.extend_zeros(dt_pad)
        # scalar dataspace v1 (8 bytes)
        abuf.push(1)
        abuf.extend_zeros(7)
        abuf.extend(val_buf.to_bytes)
        msgs.push(SciHDF5.wrap_oh1_msg(12, 0, abuf.to_bytes))
        ai += 1

      file_buf.align(8)
      ds_addr = file_buf.len
      file_buf.extend(SciHDF5.build_oh1(msgs))
      ds_addrs.push([parts, ds_addr])
      pi += 1

    # 4. Build nested groups bottom-up
    root_addr = SciHDF5.emit_group_tree(file_buf, ds_addrs, 0)

    # 5. Patch Superblock v0 at offset 0
    eof_addr = file_buf.len
    sb = SciByteBuf.new(96)
    sig = [137, 72, 68, 70, 13, 10, 26, 10]
    si = 0
    while si < 8
      sb.push(sig[si])
      si += 1
    sb.push(0)
    sb.push(0)
    sb.push(0)
    sb.push(0)
    sb.push(0)
    sb.push(8)
    sb.push(8)
    sb.push(0)
    sb.put_u16_le(4)
    sb.put_u16_le(16)
    sb.put_u32_le(0)
    sb.put_u64_le(0)
    sb.put_u64_le(-1)
    sb.put_u64_le(eof_addr)
    sb.put_u64_le(-1)
    sb.put_u64_le(0)
    sb.put_u64_le(root_addr)
    sb.put_u32_le(0)
    sb.put_u32_le(0)
    sb.put_u64_le(0)
    sb.put_u64_le(0)
    sb_bytes = sb.to_bytes
    i = 0
    while i < 96
      file_buf.set_u8(i, sb_bytes[i])
      i += 1

    File.write_bytes(path, file_buf.to_bytes)
    {"written" => true, "path" => path}

  -> .emit_group_tree(file_buf, entries, depth)
    child_pairs = []
    subgroups = {}
    sub_order = []
    i = 0
    while i < entries.size
      parts = entries[i][0]
      addr = entries[i][1]
      head = parts[depth]
      if parts.size == depth + 1
        child_pairs.push([head, addr])
      else
        if subgroups.has_key?(head) == false
          subgroups[head] = []
          sub_order.push(head)
        subgroups[head].push(entries[i])
      i += 1
    si = 0
    while si < sub_order.size
      gname = sub_order[si]
      gaddr = SciHDF5.emit_group_tree(file_buf, subgroups[gname], depth + 1)
      child_pairs.push([gname, gaddr])
      si += 1
    file_buf.align(8)
    oh_addr = file_buf.len
    file_buf.extend(SciHDF5.build_group_oh1(child_pairs))
    oh_addr

# ---- FlatBuffers Helper & Arrow IPC Reader/Writer ----
+ SciFB
  rw :buf

  -> new
    @buf = SciByteBuf.new(256)
    @buf.put_u32_le(0)

  -> align(n)
    @buf.align(n)

  -> align_plus4(n)
    while ((@buf.len + 4) % n) != 0
      @buf.push(0)

  -> start_table(field_offs, table_size, align_to = 4)
    @buf.align(4)
    vlen = 4 + 2 * field_offs.size
    vt_pos = @buf.len
    @buf.put_u16_le(vlen)
    @buf.put_u16_le(table_size)
    i = 0
    while i < field_offs.size
      @buf.put_u16_le(field_offs[i])
      i += 1
    @buf.align(align_to)
    t_pos = @buf.len
    @buf.put_u32_le(t_pos - vt_pos)
    @buf.extend_zeros(table_size - 4)
    t_pos

  -> set_u8(t_pos, off, val)
    @buf.set_u8(t_pos + off, val)

  -> set_i16(t_pos, off, val)
    @buf.set_u16_le(t_pos + off, val)

  -> set_i32(t_pos, off, val)
    @buf.set_u32_le(t_pos + off, val)

  -> set_i64(t_pos, off, val)
    @buf.set_u64_le(t_pos + off, val)

  -> set_ref(field_pos, target_pos)
    @buf.set_u32_le(field_pos, target_pos - field_pos)

  -> bytes_obj(raw_bytes)
    @buf.align(4)
    pos = @buf.len
    @buf.put_u32_le(raw_bytes.size)
    @buf.extend(raw_bytes)
    @buf.push(0)
    @buf.align(4)
    pos

  # Read helpers on a u8[] FlatBuffer slice
  -> .table_field_pos(b, t_pos, field_idx)
    vt_rel = SciBin.i32_le(b, t_pos)
    vt_pos = t_pos - vt_rel
    vlen = SciBin.u16_le(b, vt_pos)
    off_pos = vt_pos + 4 + 2 * field_idx
    if off_pos + 2 > vt_pos + vlen
      return 0
    f_off = SciBin.u16_le(b, off_pos)
    f_off == 0 ? 0 : t_pos + f_off

  -> .deref(b, pos)
    pos + SciBin.u32_le(b, pos)

  -> .read_bytes_obj(b, ref_pos)
    p = SciFB.deref(b, ref_pos)
    n = SciBin.u32_le(b, p)
    SciBin.slice(b, p + 4, n)

  -> .read_str_obj(b, ref_pos)
    SciBin.bytes_to_str(SciFB.read_bytes_obj(b, ref_pos))

+ SciArrow
  -> .validate_meta_b64(meta)
    out = []
    if meta == nil
      return out
    if !SciValidate.is_hash?(meta)
      raise "metadata_base64 must be a hash"
    keys = meta.keys
    i = 0
    while i < keys.size
      k = keys[i]
      kstr = SciValidate.check_utf8_text(k.to_s, "metadata key")
      vstr = meta[k]
      if !SciValidate.is_string?(vstr)
        raise "metadata_base64 value must be a base64 string"
      out.push([SciBin.str_to_bytes(kstr), Base64.decode(vstr)])
      i += 1
    out

  -> .validate_table(table)
    if !SciValidate.is_hash?(table)
      raise "table must be a hash"
    cols = SciValidate.get_field(table, "columns", :columns)
    if !SciValidate.is_array?(cols) || cols.size == 0
      raise "table columns must be a non-empty array"
    has_rows = SciValidate.has_field?(table, "rows", :rows)
    declared_rows = SciValidate.get_field(table, "rows", :rows)
    meta_b64 = SciValidate.get_field(table, "metadata_base64", :metadata_base64)
    meta_kv = SciArrow.validate_meta_b64(meta_b64)

    seen_names = {}
    prep_cols = []
    nrows = -1
    ci = 0
    while ci < cols.size
      col = cols[ci]
      name = SciValidate.check_utf8_text(SciValidate.get_field(col, "name", :name), "column name")
      if seen_names.has_key?(name)
        raise "duplicate column name [name]"
      seen_names[name] = true
      dtype = SciValidate.get_field(col, "dtype", :dtype)
      if !SciValidate.is_string?(dtype)
        raise "column dtype must be a string"
      if dtype != "float32" && dtype != "float64" && dtype != "int32" && dtype != "int64" && dtype != "uint32" && dtype != "uint64" && dtype != "bool" && dtype != "string"
        raise "unsupported column dtype [dtype]"
      nullable = true
      if SciValidate.has_field?(col, "nullable", :nullable)
        nb = SciValidate.get_field(col, "nullable", :nullable)
        if !SciValidate.is_bool?(nb)
          raise "column nullable must be a bool"
        nullable = nb
      vals = SciValidate.get_field(col, "values", :values)
      if !SciValidate.is_array?(vals)
        raise "column values must be an array"
      if nrows < 0
        nrows = vals.size
      elsif vals.size != nrows
        raise "column length mismatch"
      if nrows > 1000000
        raise "table exceeds 1000000 row limit"
      cvals = []
      vi = 0
      while vi < vals.size
        v = vals[vi]
        if v == nil
          if !nullable
            raise "null value in non-nullable column [name]"
          cvals.push(nil)
        else
          cvals.push(SciValidate.validate_scalar(v, dtype))
        vi += 1
      cmeta = SciArrow.validate_meta_b64(SciValidate.get_field(col, "metadata_base64", :metadata_base64))
      prep_cols.push([name, dtype, nullable, cvals, cmeta])
      ci += 1

    if has_rows && declared_rows != nil
      if !SciValidate.is_int?(declared_rows) || declared_rows != nrows
        raise "declared rows does not match column length"
    [nrows, prep_cols, meta_kv]

  -> .write_kv_vec(fb, kv_list)
    fb.align(4)
    vec_pos = fb.buf.len
    fb.buf.put_u32_le(kv_list.size)
    fb.buf.extend_zeros(4 * kv_list.size)
    i = 0
    while i < kv_list.size
      t = fb.start_table([4, 8], 12)
      fb.set_ref(vec_pos + 4 + 4 * i, t)
      kp = fb.bytes_obj(kv_list[i][0])
      vp = fb.bytes_obj(kv_list[i][1])
      fb.set_ref(t + 4, kp)
      fb.set_ref(t + 8, vp)
      i += 1
    vec_pos

  -> .write_schema_table(fb, prep_cols, meta_kv)
    st = fb.start_table([0, 4, meta_kv.size > 0 ? 8 : 0], 12)
    fb.align(4)
    fvec = fb.buf.len
    fb.buf.put_u32_le(prep_cols.size)
    fb.buf.extend_zeros(4 * prep_cols.size)
    fb.set_ref(st + 4, fvec)
    i = 0
    while i < prep_cols.size
      col = prep_cols[i]
      name = col[0]
      dt = col[1]
      nullable = col[2]
      cmeta = col[4]
      has_meta = cmeta.size > 0
      ft = fb.start_table([4, 8, 9, 12, 0, 16, has_meta ? 20 : 0], 24)
      fb.set_ref(fvec + 4 + 4 * i, ft)
      fb.set_u8(ft, 8, nullable ? 1 : 0)
      tt = 0
      if dt == "int32" || dt == "int64" || dt == "uint32" || dt == "uint64"
        fb.set_u8(ft, 9, 2)
        tt = fb.start_table([4, 8], 12)
        fb.set_i32(tt, 4, (dt == "int32" || dt == "uint32") ? 32 : 64)
        fb.set_u8(tt, 8, (dt == "uint32" || dt == "uint64") ? 0 : 1)
      elsif dt == "float32" || dt == "float64"
        fb.set_u8(ft, 9, 3)
        tt = fb.start_table([4], 8)
        fb.set_i16(tt, 4, dt == "float32" ? 1 : 2)
      elsif dt == "string"
        fb.set_u8(ft, 9, 5)
        tt = fb.start_table([], 4)
      elsif dt == "bool"
        fb.set_u8(ft, 9, 6)
        tt = fb.start_table([], 4)
      fb.set_ref(ft + 12, tt)
      np_pos = fb.bytes_obj(SciBin.str_to_bytes(name))
      fb.set_ref(ft + 4, np_pos)
      fb.align(4)
      cvec = fb.buf.len
      fb.buf.put_u32_le(0)
      fb.set_ref(ft + 16, cvec)
      if has_meta
        mvec = SciArrow.write_kv_vec(fb, cmeta)
        fb.set_ref(ft + 20, mvec)
      i += 1
    if meta_kv.size > 0
      mvec = SciArrow.write_kv_vec(fb, meta_kv)
      fb.set_ref(st + 8, mvec)
    st

  -> .serialize_schema_msg(prep_cols, meta_kv)
    fb = SciFB.new
    mt = fb.start_table([4, 6, 8], 12)
    fb.set_ref(0, mt)
    fb.set_i16(mt, 4, 4)
    fb.set_u8(mt, 6, 1)
    st = SciArrow.write_schema_table(fb, prep_cols, meta_kv)
    fb.set_ref(mt + 8, st)
    fb.align(8)
    out = SciByteBuf.new(fb.buf.len + 8)
    out.put_u32_le(4294967295)
    out.put_u32_le(fb.buf.len)
    out.extend(fb.buf.to_bytes)
    out.to_bytes

  -> .read_kv_vec(b, ref_pos)
    out = {}
    if ref_pos == 0
      return out
    vec = SciFB.deref(b, ref_pos)
    cnt = SciBin.u32_le(b, vec)
    i = 0
    while i < cnt
      kv_pos = SciFB.deref(b, vec + 4 + 4 * i)
      kp = SciFB.table_field_pos(b, kv_pos, 0)
      vp = SciFB.table_field_pos(b, kv_pos, 1)
      kstr = kp != 0 ? SciFB.read_str_obj(b, kp) : ""
      vbytes = vp != 0 ? SciFB.read_bytes_obj(b, vp) : u8[0]
      out[kstr] = Base64.encode(vbytes)
      i += 1
    out

  # Returns [fields_array_of_[name, dtype, nullable, meta_hash], schema_meta_hash]
  -> .parse_schema_table(b, st_pos)
    f_ref = SciFB.table_field_pos(b, st_pos, 1)
    m_ref = SciFB.table_field_pos(b, st_pos, 2)
    schema_meta = SciArrow.read_kv_vec(b, m_ref)
    fields = []
    if f_ref != 0
      fvec = SciFB.deref(b, f_ref)
      nf = SciBin.u32_le(b, fvec)
      i = 0
      while i < nf
        ft = SciFB.deref(b, fvec + 4 + 4 * i)
        np = SciFB.table_field_pos(b, ft, 0)
        null_p = SciFB.table_field_pos(b, ft, 1)
        ttype_p = SciFB.table_field_pos(b, ft, 2)
        tpos_p = SciFB.table_field_pos(b, ft, 3)
        dict_p = SciFB.table_field_pos(b, ft, 4)
        fmeta_p = SciFB.table_field_pos(b, ft, 6)
        if dict_p != 0
          raise "dictionary-encoded Arrow IPC fields not supported"
        name = SciFB.read_str_obj(b, np)
        nullable = null_p == 0 ? false : (b[null_p] != 0)
        ttype = ttype_p == 0 ? 0 : b[ttype_p]
        tt = SciFB.deref(b, tpos_p)
        dtype = nil
        if ttype == 2
          bw_p = SciFB.table_field_pos(b, tt, 0)
          sg_p = SciFB.table_field_pos(b, tt, 1)
          bw = bw_p == 0 ? 0 : SciBin.i32_le(b, bw_p)
          sg = sg_p == 0 ? false : (b[sg_p] != 0)
          if bw == 32
            dtype = sg ? "int32" : "uint32"
          elsif bw == 64
            dtype = sg ? "int64" : "uint64"
          else
            raise "unsupported Arrow Int bitWidth [bw]"
        elsif ttype == 3
          pr_p = SciFB.table_field_pos(b, tt, 0)
          pr = pr_p == 0 ? 0 : SciBin.i16_le(b, pr_p)
          if pr == 1
            dtype = "float32"
          elsif pr == 2
            dtype = "float64"
          else
            raise "unsupported Arrow FloatingPoint precision [pr]"
        elsif ttype == 5
          dtype = "string"
        elsif ttype == 6
          dtype = "bool"
        else
          raise "unsupported Arrow type id [ttype]"
        fmeta = SciArrow.read_kv_vec(b, fmeta_p)
        fields.push([name, dtype, nullable, fmeta])
        i += 1
    [fields, schema_meta]

  -> .write_ipc(path, table)
    if File.exist?(path)
      raise "refusing to overwrite existing Arrow IPC file: [path]"
    validated = SciArrow.validate_table(table)
    nrows = validated[0]
    prep_cols = validated[1]
    meta_kv = validated[2]

    schema_msg = SciArrow.serialize_schema_msg(prep_cols, meta_kv)

    body = SciByteBuf.new(512)
    nodes = []
    buffers = []
    ci = 0
    while ci < prep_cols.size
      col = prep_cols[ci]
      dt = col[1]
      vals = col[3]
      nc = 0
      vi = 0
      while vi < nrows
        if vals[vi] == nil
          nc += 1
        vi += 1
      nodes.push([nrows, nc])
      if nc == 0
        buffers.push([0, 0])
      else
        voff = body.len
        vlen = (nrows + 7) / 8
        vbytes = u8[vlen]
        vi = 0
        while vi < nrows
          if vals[vi] != nil
            vbytes[vi / 8] = vbytes[vi / 8] | (1 << (vi % 8))
          vi += 1
        body.extend(vbytes)
        buffers.push([voff, vlen])
        body.align(8)

      if dt == "string"
        ooff = body.len
        sbuf = SciByteBuf.new(nrows * 8 + 8)
        body.put_u32_le(0)
        vi = 0
        while vi < nrows
          if vals[vi] != nil
            sbuf.extend(SciBin.str_to_bytes(vals[vi]))
          body.put_u32_le(sbuf.len)
          vi += 1
        buffers.push([ooff, (nrows + 1) * 4])
        body.align(8)
        doff = body.len
        body.extend(sbuf.to_bytes)
        buffers.push([doff, sbuf.len])
        body.align(8)
      elsif dt == "bool"
        doff = body.len
        dlen = (nrows + 7) / 8
        dbytes = u8[dlen]
        vi = 0
        while vi < nrows
          if vals[vi] == true
            dbytes[vi / 8] = dbytes[vi / 8] | (1 << (vi % 8))
          vi += 1
        body.extend(dbytes)
        buffers.push([doff, dlen])
        body.align(8)
      else
        doff = body.len
        esz = SciValidate.dtype_byte_size(dt)
        vi = 0
        while vi < nrows
          SciValidate.pack_scalar_le(body, vals[vi] == nil ? 0 : vals[vi], dt)
          vi += 1
        buffers.push([doff, nrows * esz])
        body.align(8)
      ci += 1

    fb_rb = SciFB.new
    mt_rb = fb_rb.start_table([4, 6, 8, 16], 24, 8)
    fb_rb.set_ref(0, mt_rb)
    fb_rb.set_i16(mt_rb, 4, 4)
    fb_rb.set_u8(mt_rb, 6, 3)
    fb_rb.set_i64(mt_rb, 16, body.len)
    rbt = fb_rb.start_table([8, 16, 20], 24, 8)
    fb_rb.set_ref(mt_rb + 8, rbt)
    fb_rb.set_i64(rbt, 8, nrows)
    fb_rb.align_plus4(8)
    nvec = fb_rb.buf.len
    fb_rb.buf.put_u32_le(nodes.size)
    ni = 0
    while ni < nodes.size
      fb_rb.buf.put_u64_le(nodes[ni][0])
      fb_rb.buf.put_u64_le(nodes[ni][1])
      ni += 1
    fb_rb.set_ref(rbt + 16, nvec)
    fb_rb.align_plus4(8)
    bvec = fb_rb.buf.len
    fb_rb.buf.put_u32_le(buffers.size)
    bi = 0
    while bi < buffers.size
      fb_rb.buf.put_u64_le(buffers[bi][0])
      fb_rb.buf.put_u64_le(buffers[bi][1])
      bi += 1
    fb_rb.set_ref(rbt + 20, bvec)
    fb_rb.align(8)
    rb_msg = SciByteBuf.new(fb_rb.buf.len + 8)
    rb_msg.put_u32_le(4294967295)
    rb_msg.put_u32_le(fb_rb.buf.len)
    rb_msg.extend(fb_rb.buf.to_bytes)
    rb_msg_bytes = rb_msg.to_bytes

    rb_offset = 8 + schema_msg.size
    rb_meta_len = rb_msg_bytes.size
    fb_f = SciFB.new
    ft = fb_f.start_table([4, 8, 12, 16], 20)
    fb_f.set_ref(0, ft)
    fb_f.set_i16(ft, 4, 4)
    st_f = SciArrow.write_schema_table(fb_f, prep_cols, meta_kv)
    fb_f.set_ref(ft + 8, st_f)
    fb_f.align_plus4(8)
    dvec = fb_f.buf.len
    fb_f.buf.put_u32_le(0)
    fb_f.set_ref(ft + 12, dvec)
    fb_f.align_plus4(8)
    rbvec = fb_f.buf.len
    fb_f.buf.put_u32_le(1)
    fb_f.buf.put_u64_le(rb_offset)
    fb_f.buf.put_u32_le(rb_meta_len)
    fb_f.buf.put_u32_le(0)
    fb_f.buf.put_u64_le(body.len)
    fb_f.set_ref(ft + 16, rbvec)
    fb_f.align(8)
    footer_bytes = fb_f.buf.to_bytes

    file_out = SciByteBuf.new(rb_offset + rb_meta_len + body.len + footer_bytes.size + 32)
    file_out.extend(SciBin.str_to_bytes("ARROW1"))
    file_out.push(0)
    file_out.push(0)
    file_out.extend(schema_msg)
    file_out.extend(rb_msg_bytes)
    file_out.extend(body.to_bytes)
    file_out.put_u32_le(4294967295)
    file_out.put_u32_le(0)
    file_out.extend(footer_bytes)
    file_out.put_u32_le(footer_bytes.size)
    file_out.extend(SciBin.str_to_bytes("ARROW1"))
    File.write_bytes(path, file_out.to_bytes)
    {"written" => true, "path" => path}

  -> .read_ipc(path)
    b = File.read_bytes(path)
    if b.size < 18 || b[0] != 65 || b[1] != 82 || b[2] != 82 || b[3] != 79 || b[4] != 87 || b[5] != 49
      raise "not a valid Arrow IPC file"
    n = b.size
    if b[n - 6] != 65 || b[n - 5] != 82 || b[n - 4] != 82 || b[n - 3] != 79 || b[n - 2] != 87 || b[n - 1] != 49
      raise "missing trailing ARROW1 magic"
    flen = SciBin.i32_le(b, n - 10)
    fbuf = SciBin.slice(b, n - 10 - flen, flen)
    fpos = SciBin.u32_le(fbuf, 0)
    st_ref = SciFB.table_field_pos(fbuf, fpos, 1)
    st_pos = SciFB.deref(fbuf, st_ref)
    parsed_schema = SciArrow.parse_schema_table(fbuf, st_pos)
    fields = parsed_schema[0]
    schema_meta = parsed_schema[1]

    col_values = []
    i = 0
    while i < fields.size
      col_values.push([])
      i += 1
    total_rows = 0

    rb_ref = SciFB.table_field_pos(fbuf, fpos, 3)
    if rb_ref != 0
      rb_vec = SciFB.deref(fbuf, rb_ref)
      nblocks = SciBin.u32_le(fbuf, rb_vec)
      bi = 0
      while bi < nblocks
        bpos = rb_vec + 4 + 24 * bi
        blk_off = SciBin.i64_le(fbuf, bpos)
        meta_len = SciBin.i32_le(fbuf, bpos + 8)
        body_len = SciBin.i64_le(fbuf, bpos + 16)
        hdr_skip = SciBin.u32_le(b, blk_off) == 4294967295 ? 8 : 4
        mbuf = SciBin.slice(b, blk_off + hdr_skip, meta_len - hdr_skip)
        mpos = SciBin.u32_le(mbuf, 0)
        comp_p = SciFB.table_field_pos(mbuf, SciFB.deref(mbuf, SciFB.table_field_pos(mbuf, mpos, 2)), 3)
        if comp_p != 0
          raise "compressed Arrow IPC buffers not supported"
        rbt = SciFB.deref(mbuf, SciFB.table_field_pos(mbuf, mpos, 2))
        len_p = SciFB.table_field_pos(mbuf, rbt, 0)
        batch_rows = len_p == 0 ? 0 : SciBin.i64_le(mbuf, len_p)
        total_rows += batch_rows
        if total_rows > 1000000
          raise "Arrow table exceeds 1000000 row limit"
        nodes_vec = SciFB.deref(mbuf, SciFB.table_field_pos(mbuf, rbt, 1))
        bufs_vec = SciFB.deref(mbuf, SciFB.table_field_pos(mbuf, rbt, 2))
        body_start = blk_off + meta_len
        buf_idx = 0
        fi = 0
        while fi < fields.size
          dt = fields[fi][1]
          vals = col_values[fi]
          node_pos = nodes_vec + 4 + 16 * fi
          null_cnt = SciBin.i64_le(mbuf, node_pos + 8)
          vbuf_pos = bufs_vec + 4 + 16 * buf_idx
          v_off = SciBin.i64_le(mbuf, vbuf_pos)
          v_len = SciBin.i64_le(mbuf, vbuf_pos + 8)
          buf_idx += 1

          if dt == "string"
            obuf_pos = bufs_vec + 4 + 16 * buf_idx
            o_off = SciBin.i64_le(mbuf, obuf_pos)
            buf_idx += 1
            dbuf_pos = bufs_vec + 4 + 16 * buf_idx
            d_off = SciBin.i64_le(mbuf, dbuf_pos)
            buf_idx += 1
            ri = 0
            while ri < batch_rows
              is_valid = true
              if null_cnt > 0 && v_len > 0
                is_valid = ((b[body_start + v_off + (ri / 8)] >> (ri % 8)) & 1) != 0
              if !is_valid
                vals.push(nil)
              else
                s0 = SciBin.i32_le(b, body_start + o_off + ri * 4)
                s1 = SciBin.i32_le(b, body_start + o_off + (ri + 1) * 4)
                sstr = SciBin.bytes_to_str(SciBin.slice(b, body_start + d_off + s0, s1 - s0))
                SciValidate.check_utf8_string(sstr, "Arrow string")
                vals.push(sstr)
              ri += 1
          elsif dt == "bool"
            dbuf_pos = bufs_vec + 4 + 16 * buf_idx
            d_off = SciBin.i64_le(mbuf, dbuf_pos)
            buf_idx += 1
            ri = 0
            while ri < batch_rows
              is_valid = true
              if null_cnt > 0 && v_len > 0
                is_valid = ((b[body_start + v_off + (ri / 8)] >> (ri % 8)) & 1) != 0
              if !is_valid
                vals.push(nil)
              else
                bit = ((b[body_start + d_off + (ri / 8)] >> (ri % 8)) & 1) != 0
                vals.push(bit)
              ri += 1
          else
            dbuf_pos = bufs_vec + 4 + 16 * buf_idx
            d_off = SciBin.i64_le(mbuf, dbuf_pos)
            buf_idx += 1
            esz = SciValidate.dtype_byte_size(dt)
            ri = 0
            while ri < batch_rows
              is_valid = true
              if null_cnt > 0 && v_len > 0
                is_valid = ((b[body_start + v_off + (ri / 8)] >> (ri % 8)) & 1) != 0
              if !is_valid
                vals.push(nil)
              else
                vals.push(SciValidate.unpack_scalar(b, body_start + d_off + ri * esz, dt, true))
              ri += 1
          fi += 1
        bi += 1

    out_cols = []
    fi = 0
    while fi < fields.size
      f = fields[fi]
      out_cols.push({"name" => f[0], "dtype" => f[1], "nullable" => f[2], "values" => col_values[fi], "metadata_base64" => f[3]})
      fi += 1
    {"columns" => out_cols, "rows" => total_rows, "metadata_base64" => schema_meta}

# ---- Thrift Compact Protocol & Standard Parquet Reader/Writer ----
+ SciParquet
  -> .read_uvarint(b, st)
    pos = st[0]
    res = 0
    shift = 0
    while true
      byte = b[pos] ## i64
      pos += 1
      res = res | ((byte & 127) << shift)
      if (byte & 128) == 0
        st[0] = pos
        return res
      shift += 7

  -> .read_ivarint(b, st)
    u = SciParquet.read_uvarint(b, st)
    (u >> 1) ^ (0 - (u & 1))

  -> .parse_thrift_struct(b, st)
    fields = {}
    fid = 0
    while true
      hdr = b[st[0]] ## i64
      st[0] = st[0] + 1
      if hdr == 0
        return fields
      delta = hdr >> 4
      ttype = hdr & 15
      if delta == 0
        fid = SciParquet.read_ivarint(b, st)
      else
        fid += delta
      fields[fid] = SciParquet.parse_thrift_val(b, st, ttype)

  -> .parse_thrift_val(b, st, ttype)
    if ttype == 1
      return true
    if ttype == 2
      return false
    if ttype == 3
      v = b[st[0]] ## i64
      st[0] = st[0] + 1
      return v
    if ttype == 4 || ttype == 5 || ttype == 6
      return SciParquet.read_ivarint(b, st)
    if ttype == 7
      pos = st[0]
      st[0] = pos + 8
      return SciBin.slice(b, pos, 8)
    if ttype == 8
      n = SciParquet.read_uvarint(b, st)
      pos = st[0]
      st[0] = pos + n
      return SciBin.slice(b, pos, n)
    if ttype == 9 || ttype == 10
      hdr = b[st[0]] ## i64
      st[0] = st[0] + 1
      cnt = hdr >> 4
      etype = hdr & 15
      if cnt == 15
        cnt = SciParquet.read_uvarint(b, st)
      lst = []
      i = 0
      while i < cnt
        lst.push(SciParquet.parse_thrift_val(b, st, etype))
        i += 1
      return lst
    if ttype == 11
      cnt = SciParquet.read_uvarint(b, st)
      if cnt == 0
        return []
      kv = b[st[0]] ## i64
      st[0] = st[0] + 1
      ktype = kv >> 4
      vtype = kv & 15
      lst = []
      i = 0
      while i < cnt
        k = SciParquet.parse_thrift_val(b, st, ktype)
        v = SciParquet.parse_thrift_val(b, st, vtype)
        lst.push([k, v])
        i += 1
      return lst
    if ttype == 12
      return SciParquet.parse_thrift_struct(b, st)
    raise "unsupported Thrift compact type [ttype]"

  -> .put_uvarint(out, n)
    v = n
    while true
      byte = (v % 128).to_i
      v = v / 128
      if v > 0
        out.push(byte | 128)
      else
        out.push(byte)
        return out

  -> .put_ivarint(out, n)
    u = n >= 0 ? (n * 2) : ((0 - n) * 2 - 1)
    SciParquet.put_uvarint(out, u)

  -> .put_field_hdr(out, fid, prev_fid, ttype)
    delta = fid - prev_fid
    if delta >= 1 && delta <= 15
      out.push((delta << 4) | ttype)
    else
      out.push(ttype)
      SciParquet.put_ivarint(out, fid)
    fid

  -> .put_i32_field(out, fid, prev_fid, val)
    SciParquet.put_field_hdr(out, fid, prev_fid, 5)
    SciParquet.put_ivarint(out, val)
    fid

  -> .put_i64_field(out, fid, prev_fid, val)
    SciParquet.put_field_hdr(out, fid, prev_fid, 6)
    SciParquet.put_ivarint(out, val)
    fid

  -> .put_bin_field(out, fid, prev_fid, bytes)
    SciParquet.put_field_hdr(out, fid, prev_fid, 8)
    SciParquet.put_uvarint(out, bytes.size)
    out.extend(bytes)
    fid

  -> .put_list_hdr(out, fid, prev_fid, etype, cnt)
    SciParquet.put_field_hdr(out, fid, prev_fid, 9)
    if cnt < 15
      out.push((cnt << 4) | etype)
    else
      out.push(240 | etype)
      SciParquet.put_uvarint(out, cnt)
    fid

  # Decode RLE / bit-packed hybrid values (used for definition levels and dictionary indices)
  -> .decode_rle_hybrid(b, st, bit_width, count, max_end)
    out = []
    if bit_width == 0
      i = 0
      while i < count
        out.push(0)
        i += 1
      return out
    byte_width = (bit_width + 7) / 8
    mask = (1 << bit_width) - 1
    while out.size < count && st[0] < max_end
      hdr = SciParquet.read_uvarint(b, st)
      if (hdr & 1) == 0
        # RLE run
        run_len = hdr >> 1
        val = 0
        bi = 0
        while bi < byte_width
          val = val | ((b[st[0]] ## i64) << (8 * bi))
          st[0] = st[0] + 1
          bi += 1
        k = 0
        while k < run_len && out.size < count
          out.push(val)
          k += 1
      else
        # Bit-packed run of (hdr >> 1) groups of 8 values
        ngroups = hdr >> 1
        nvals = ngroups * 8
        bit_buf = 0
        bit_cnt = 0
        k = 0
        while k < nvals
          while bit_cnt < bit_width
            if st[0] < max_end
              bit_buf = bit_buf | ((b[st[0]] ## i64) << bit_cnt)
              st[0] = st[0] + 1
            bit_cnt += 8
          if out.size < count
            out.push(bit_buf & mask)
          bit_buf = bit_buf >> bit_width
          bit_cnt -= bit_width
          k += 1
    out

  -> .decode_plain_value(b, st, ptype, dtype)
    pos = st[0]
    if ptype == 0
      # BOOLEAN in PLAIN is bit-packed; handled at array level
      raise "use bit-packed reader for PLAIN BOOLEAN"
    if ptype == 1 || ptype == 4
      st[0] = pos + 4
      return SciValidate.unpack_scalar(b, pos, dtype, true)
    if ptype == 2 || ptype == 5
      st[0] = pos + 8
      return SciValidate.unpack_scalar(b, pos, dtype, true)
    if ptype == 6
      blen = SciBin.u32_le(b, pos)
      st[0] = pos + 4 + blen
      s = SciBin.bytes_to_str(SciBin.slice(b, pos + 4, blen))
      return SciValidate.check_utf8_string(s, "Parquet string")
    raise "unsupported Parquet physical type [ptype]"

  -> .read_standard(path)
    b = File.read_bytes(path)
    n = b.size
    if n < 12 || b[0] != 80 || b[1] != 65 || b[2] != 82 || b[3] != 49 || b[n - 4] != 80 || b[n - 3] != 65 || b[n - 2] != 82 || b[n - 1] != 49
      raise "not a valid Parquet file"
    flen = SciBin.i32_le(b, n - 8)
    fpos = n - 8 - flen
    st = i64[1]
    st[0] = fpos
    fmeta = SciParquet.parse_thrift_struct(b, st)
    schema_elts = fmeta[2]
    num_rows = fmeta[3]
    row_groups = fmeta.has_key?(4) ? fmeta[4] : []
    kv_list = fmeta.has_key?(5) ? fmeta[5] : []
    if num_rows > 1000000
      raise "Parquet table exceeds 1000000 row limit"

    table_meta = {}
    arrow_fields = nil
    ki = 0
    while ki < kv_list.size
      kv = kv_list[ki]
      kstr = SciBin.bytes_to_str(kv[1])
      vbytes = kv.has_key?(2) ? kv[2] : u8[0]
      if kstr == "ARROW:schema"
        s_raw = Base64.decode(SciBin.bytes_to_str(vbytes))
        hskip = SciBin.u32_le(s_raw, 0) == 4294967295 ? 8 : 4
        mbuf = SciBin.slice(s_raw, hskip, s_raw.size - hskip)
        mpos = SciBin.u32_le(mbuf, 0)
        st_pos = SciFB.deref(mbuf, SciFB.table_field_pos(mbuf, mpos, 2))
        parsed_s = SciArrow.parse_schema_table(mbuf, st_pos)
        arrow_fields = parsed_s[0]
      else
        table_meta[kstr] = Base64.encode(vbytes)
      ki += 1

    # Leaf columns are schema_elts[1..]
    ncols = schema_elts.size - 1
    col_defs = []
    ci = 0
    while ci < ncols
      se = schema_elts[ci + 1]
      ptype = se[1]
      rep = se.has_key?(3) ? se[3] : 1
      cname = SciBin.bytes_to_str(se[4])
      ctype = se.has_key?(6) ? se[6] : -1
      ltype = se.has_key?(10) ? se[10] : nil
      nullable = rep != 0
      dtype = nil
      fmeta = {}
      if arrow_fields != nil && ci < arrow_fields.size
        dtype = arrow_fields[ci][1]
        nullable = arrow_fields[ci][2]
        fmeta = arrow_fields[ci][3]
      else
        if ptype == 0
          dtype = "bool"
        elsif ptype == 1
          dtype = (ctype == 13 || (ltype != nil && ltype.has_key?(8) && ltype[8].has_key?(2) && ltype[8][2] == false)) ? "uint32" : "int32"
        elsif ptype == 2
          dtype = (ctype == 14 || (ltype != nil && ltype.has_key?(8) && ltype[8].has_key?(2) && ltype[8][2] == false)) ? "uint64" : "int64"
        elsif ptype == 4
          dtype = "float32"
        elsif ptype == 5
          dtype = "float64"
        elsif ptype == 6
          dtype = "string"
        else
          raise "unsupported Parquet physical type [ptype]"
      col_defs.push([cname, dtype, nullable, fmeta, ptype, rep, []])
      ci += 1

    rgi = 0
    while rgi < row_groups.size
      rg = row_groups[rgi]
      chunks = rg[1]
      ci = 0
      while ci < ncols
        cdef = col_defs[ci]
        dtype = cdef[1]
        ptype = cdef[4]
        rep = cdef[5]
        vals_out = cdef[6]

        cmeta = chunks[ci][3]
        codec = cmeta[4]
        if codec != 0 && codec != 2
          raise "unsupported Parquet compression codec [codec]"
        start_off = cmeta.has_key?(11) ? cmeta[11] : cmeta[9]
        end_off = start_off + cmeta[7]
        pst = i64[1]
        pst[0] = start_off
        dict_vals = []

        while pst[0] < end_off
          phdr = SciParquet.parse_thrift_struct(b, pst)
          page_type = phdr[1]
          usz = phdr[2]
          csz = phdr[3]
          raw_page = SciBin.slice(b, pst[0], csz)
          pst[0] = pst[0] + csz
          if codec == 2
            raw_page = SciDeflate.gzip_decompress(raw_page)

          if page_type == 2
            # DICTIONARY_PAGE
            dhdr = phdr[7]
            dcount = dhdr[1]
            dst = i64[1]
            dst[0] = 0
            di = 0
            while di < dcount
              dict_vals.push(SciParquet.decode_plain_value(raw_page, dst, ptype, dtype))
              di += 1
          elsif page_type == 0
            # DATA_PAGE v1
            dphdr = phdr[5]
            nvals = dphdr[1]
            enc = dphdr[2]
            dst = i64[1]
            dst[0] = 0
            def_levels = nil
            if rep == 1
              rle_len = SciBin.i32_le(raw_page, dst[0])
              dst[0] = dst[0] + 4
              rle_end = dst[0] + rle_len
              def_levels = SciParquet.decode_rle_hybrid(raw_page, dst, 1, nvals, rle_end)
              dst[0] = rle_end
            non_null_cnt = 0
            if def_levels == nil
              non_null_cnt = nvals
            else
              vi = 0
              while vi < nvals
                if def_levels[vi] > 0
                  non_null_cnt += 1
                vi += 1

            non_null_vals = []
            if enc == 0
              if ptype == 0
                # Bit-packed booleans
                bpos = dst[0]
                bi = 0
                while bi < non_null_cnt
                  bit = ((raw_page[bpos + (bi / 8)] >> (bi % 8)) & 1) != 0
                  non_null_vals.push(bit)
                  bi += 1
              else
                bi = 0
                while bi < non_null_cnt
                  non_null_vals.push(SciParquet.decode_plain_value(raw_page, dst, ptype, dtype))
                  bi += 1
            elsif enc == 2 || enc == 8
              bw = raw_page[dst[0]] ## i64
              dst[0] = dst[0] + 1
              idxs = SciParquet.decode_rle_hybrid(raw_page, dst, bw, non_null_cnt, raw_page.size)
              bi = 0
              while bi < non_null_cnt
                non_null_vals.push(dict_vals[idxs[bi]])
                bi += 1
            else
              raise "unsupported Parquet page encoding [enc]"

            nni = 0
            vi = 0
            while vi < nvals
              if def_levels != nil && def_levels[vi] == 0
                vals_out.push(nil)
              else
                vals_out.push(non_null_vals[nni])
                nni += 1
              vi += 1
          else
            raise "unsupported Parquet page type [page_type]"
        ci += 1
      rgi += 1

    out_cols = []
    ci = 0
    while ci < ncols
      cdef = col_defs[ci]
      out_cols.push({"name" => cdef[0], "dtype" => cdef[1], "nullable" => cdef[2], "values" => cdef[6], "metadata_base64" => cdef[3]})
      ci += 1
    {"columns" => out_cols, "rows" => num_rows, "metadata_base64" => table_meta}

  -> .write_standard(path, table)
    if File.exist?(path)
      raise "refusing to overwrite existing Parquet file: [path]"
    validated = SciArrow.validate_table(table)
    nrows = validated[0]
    prep_cols = validated[1]
    meta_kv = validated[2]

    schema_msg = SciArrow.serialize_schema_msg(prep_cols, meta_kv)
    schema_b64 = SciBin.str_to_bytes(Base64.encode(schema_msg))

    file_buf = SciByteBuf.new(1024)
    file_buf.extend(SciBin.str_to_bytes("PAR1"))

    col_chunks_info = []
    total_byte_sz = 0
    ci = 0
    while ci < prep_cols.size
      col = prep_cols[ci]
      cname = col[0]
      dt = col[1]
      nullable = col[2]
      vals = col[3]

      ptype = 0
      if dt == "bool"
        ptype = 0
      elsif dt == "int32" || dt == "uint32"
        ptype = 1
      elsif dt == "int64" || dt == "uint64"
        ptype = 2
      elsif dt == "float32"
        ptype = 4
      elsif dt == "float64"
        ptype = 5
      elsif dt == "string"
        ptype = 6

      page_payload = SciByteBuf.new(256)
      if nullable && nrows > 0
        # RLE definition levels (bit_width=1): 1 bit-packed run of ceil(nrows/8) groups of 8
        ngroups = (nrows + 7) / 8
        rle_body = SciByteBuf.new(ngroups + 8)
        SciParquet.put_uvarint(rle_body, (ngroups << 1) | 1)
        gi = 0
        while gi < ngroups
          byte = 0
          bi = 0
          while bi < 8
            idx = gi * 8 + bi
            if idx < nrows && vals[idx] != nil
              byte = byte | (1 << bi)
            bi += 1
          rle_body.push(byte)
          gi += 1
        page_payload.put_u32_le(rle_body.len)
        page_payload.extend(rle_body.to_bytes)

      if dt == "bool"
        non_nulls = []
        vi = 0
        while vi < nrows
          if vals[vi] != nil
            non_nulls.push(vals[vi])
          vi += 1
        bbytes = u8[(non_nulls.size + 7) / 8]
        bi = 0
        while bi < non_nulls.size
          if non_nulls[bi] == true
            bbytes[bi / 8] = bbytes[bi / 8] | (1 << (bi % 8))
          bi += 1
        page_payload.extend(bbytes)
      elsif dt == "string"
        vi = 0
        while vi < nrows
          if vals[vi] != nil
            sb = SciBin.str_to_bytes(vals[vi])
            page_payload.put_u32_le(sb.size)
            page_payload.extend(sb)
          vi += 1
      else
        vi = 0
        while vi < nrows
          if vals[vi] != nil
            SciValidate.pack_scalar_le(page_payload, vals[vi], dt)
          vi += 1

      # Write PageHeader (type=0 DATA_PAGE, uncompressed_page_size, compressed_page_size, data_page_header)
      col_offset = file_buf.len
      phdr = SciByteBuf.new(32)
      prev = 0
      prev = SciParquet.put_i32_field(phdr, 1, prev, 0)
      prev = SciParquet.put_i32_field(phdr, 2, prev, page_payload.len)
      prev = SciParquet.put_i32_field(phdr, 3, prev, page_payload.len)
      prev = SciParquet.put_field_hdr(phdr, 5, prev, 12)
      dprev = 0
      dprev = SciParquet.put_i32_field(phdr, 1, dprev, nrows)
      dprev = SciParquet.put_i32_field(phdr, 2, dprev, 0)
      dprev = SciParquet.put_i32_field(phdr, 3, dprev, 3)
      dprev = SciParquet.put_i32_field(phdr, 4, dprev, 3)
      phdr.push(0)
      phdr.push(0)

      file_buf.extend(phdr.to_bytes)
      file_buf.extend(page_payload.to_bytes)
      col_sz = file_buf.len - col_offset
      total_byte_sz += col_sz
      col_chunks_info.push([cname, dt, nullable, ptype, col_offset, col_sz])
      ci += 1

    # Build FileMetaData Thrift struct
    footer = SciByteBuf.new(512)
    fprev = 0
    fprev = SciParquet.put_i32_field(footer, 1, fprev, 1)
    # field 2: schema (list of SchemaElement: 1 root + ncols)
    fprev = SciParquet.put_list_hdr(footer, 2, fprev, 12, 1 + prep_cols.size)
    # Root SchemaElement
    sprev = 0
    sprev = SciParquet.put_bin_field(footer, 4, sprev, SciBin.str_to_bytes("schema"))
    sprev = SciParquet.put_i32_field(footer, 5, sprev, prep_cols.size)
    footer.push(0)
    ci = 0
    while ci < col_chunks_info.size
      cinfo = col_chunks_info[ci]
      cname = cinfo[0]
      dt = cinfo[1]
      nullable = cinfo[2]
      ptype = cinfo[3]
      sprev = 0
      sprev = SciParquet.put_i32_field(footer, 1, sprev, ptype)
      sprev = SciParquet.put_i32_field(footer, 3, sprev, nullable ? 1 : 0)
      sprev = SciParquet.put_bin_field(footer, 4, sprev, SciBin.str_to_bytes(cname))
      if dt == "string"
        sprev = SciParquet.put_i32_field(footer, 6, sprev, 0)
      elsif dt == "uint32"
        sprev = SciParquet.put_i32_field(footer, 6, sprev, 13)
      elsif dt == "uint64"
        sprev = SciParquet.put_i32_field(footer, 6, sprev, 14)
      footer.push(0)
      ci += 1

    # field 3: num_rows
    fprev = SciParquet.put_i64_field(footer, 3, fprev, nrows)
    # field 4: row_groups (1 RowGroup)
    fprev = SciParquet.put_list_hdr(footer, 4, fprev, 12, 1)
    rgprev = 0
    rgprev = SciParquet.put_list_hdr(footer, 1, rgprev, 12, col_chunks_info.size)
    ci = 0
    while ci < col_chunks_info.size
      cinfo = col_chunks_info[ci]
      cname = cinfo[0]
      ptype = cinfo[3]
      col_off = cinfo[4]
      col_sz = cinfo[5]
      ccprev = 0
      ccprev = SciParquet.put_i64_field(footer, 2, ccprev, col_off)
      ccprev = SciParquet.put_field_hdr(footer, 3, ccprev, 12)
      cmprev = 0
      cmprev = SciParquet.put_i32_field(footer, 1, cmprev, ptype)
      cmprev = SciParquet.put_list_hdr(footer, 2, cmprev, 5, 2)
      SciParquet.put_ivarint(footer, 0)
      SciParquet.put_ivarint(footer, 3)
      cmprev = SciParquet.put_list_hdr(footer, 3, cmprev, 8, 1)
      nb = SciBin.str_to_bytes(cname)
      SciParquet.put_uvarint(footer, nb.size)
      footer.extend(nb)
      cmprev = SciParquet.put_i32_field(footer, 4, cmprev, 0)
      cmprev = SciParquet.put_i64_field(footer, 5, cmprev, nrows)
      cmprev = SciParquet.put_i64_field(footer, 6, cmprev, col_sz)
      cmprev = SciParquet.put_i64_field(footer, 7, cmprev, col_sz)
      cmprev = SciParquet.put_i64_field(footer, 9, cmprev, col_off)
      footer.push(0)
      footer.push(0)
      ci += 1
    rgprev = SciParquet.put_i64_field(footer, 2, rgprev, total_byte_sz)
    rgprev = SciParquet.put_i64_field(footer, 3, rgprev, nrows)
    footer.push(0)

    # field 5: key_value_metadata (user meta_kv + ARROW:schema)
    fprev = SciParquet.put_list_hdr(footer, 5, fprev, 12, meta_kv.size + 1)
    ki = 0
    while ki < meta_kv.size
      kvprev = 0
      kvprev = SciParquet.put_bin_field(footer, 1, kvprev, meta_kv[ki][0])
      kvprev = SciParquet.put_bin_field(footer, 2, kvprev, meta_kv[ki][1])
      footer.push(0)
      ki += 1
    kvprev = 0
    kvprev = SciParquet.put_bin_field(footer, 1, kvprev, SciBin.str_to_bytes("ARROW:schema"))
    kvprev = SciParquet.put_bin_field(footer, 2, kvprev, schema_b64)
    footer.push(0)

    fprev = SciParquet.put_bin_field(footer, 6, fprev, SciBin.str_to_bytes("tungsten-sciio"))
    footer.push(0)

    footer_bytes = footer.to_bytes
    file_buf.extend(footer_bytes)
    file_buf.put_u32_le(footer_bytes.size)
    file_buf.extend(SciBin.str_to_bytes("PAR1"))
    File.write_bytes(path, file_buf.to_bytes)
    {"written" => true, "path" => path}

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
