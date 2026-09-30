use core/crypto/crc32

# GzipError - a gzip or Base64 stream that cannot be decoded (see Gzip).
+ GzipError < ParseError

# Gzip - gzip (RFC 1952) and DEFLATE (RFC 1951) in Tungsten.
#
# No zlib: the inflater, the compressor and the CRC framing are Tungsten
# source (CRC-32 comes from Crypto:CRC32).  Data is a ByteArray (u8[]) or a
# String; results are ByteArrays unless the name says text.
#
#   Gzip.decompress(data)        gzip stream -> ByteArray.  One or more
#                                members; zero padding after a member is
#                                skipped, anything else after the last one is
#                                an error.  Empty input gives an empty result.
#   Gzip.decompress_text(data)   the same, as a String
#   Gzip.compress(data, level = 6)
#                                -> ByteArray holding one gzip member.  Level
#                                0 stores, 1..9 trade speed for size as in
#                                zlib.  Deterministic: the header has mtime 0,
#                                XFL 2 (level 9), 4 (levels 0 and 1) or 0, and
#                                OS 255, the bytes Python's gzip.compress(...,
#                                mtime=0) writes.  The DEFLATE data is not
#                                zlib's, but any inflater accepts it, and on
#                                the whole it is as small as zlib's at the same
#                                level.
#   Gzip.encode_b64(data, level = 6, width = 76)
#                                gzip, then Base64 text in lines of `width`
#                                characters (a multiple of 4), each ended by a
#                                newline; width 0 writes one line.  Width 76
#                                is Python's base64.encodebytes layout, width
#                                0 is b64encode(...) + "\n".
#   Gzip.decode_b64(text)        inverse of encode_b64 -> ByteArray.  Newlines
#                                are ignored; anything else that is not
#                                strict Base64 is an error, exactly as Python's
#                                base64.b64decode(validate=True) after
#                                dropping newlines.
#   Gzip.decode_b64_text(text)   the same, as a String
#
# Errors.  Malformed input raises GzipError (a ParseError) whose `code` is a
# stable symbol and whose message starts with "gzip: ":
#   :not_gzip :bad_method :bad_flags :header_crc   the member header
#   :truncated                                     input ends too early
#   :bad_block :bad_stored :bad_huffman :bad_code  DEFLATE data
#   :bad_distance
#   :crc :size                                     trailer check failed
#   :too_large                                     output above 2 GiB
#   :base64                                        invalid Base64 text
# A wrong argument type or level raises ArgumentError.  Nothing is returned
# for corrupt data, and no partial result.
#
#   begin
#     text = Gzip.decode_b64_text(File.read(path))
#   rescue e: GzipError
#     << "cannot read [path]: [e.message]"
#
# Memory.  Typed arrays are not freed by the runtime; every scratch array
# (tables, hash chains, bit buffers) is released before a call returns.  The
# result belongs to the caller.  Output is limited by the u8[] size, 2 GiB - 1.
#
# Inflate follows the usual table-driven design: a 64-bit bit buffer refilled
# with one unaligned load, primary decode tables of 10 (literal/length) and 8
# (distance) bits with subtables for longer codes, table entries that already
# carry the literal, base value and extra-bit count, 8-byte match copies.  The
# output buffer is sized from the trailer's ISIZE, so a single member is never
# copied.  Deflate is zlib's algorithm family: hash chains over the 32 KiB
# window (3-byte hash, i32 head/prev tables), lazy matching with zlib's
# good/lazy/nice/chain settings per level, blocks of 16384 symbols coded as the
# smallest of stored, fixed-Huffman and dynamic-Huffman blocks (exact bit
# counts), optimal length-limited Huffman codes (two-queue construction, Kraft
# repair for the 15-bit limit).
+ Gzip
  # ---------------------------------------------------------------------------
  # Public entry points
  # ---------------------------------------------------------------------------

  -> .decompress(data)
    src = Gzip.__bytes(data, "decompress") ## u8[]
    n = src.size ## i64
    if n == 0
      return u8[0]
    # ISIZE of the last member is the output size of a single-member stream.
    # Trust it only within what DEFLATE can expand to (1032:1) and 256 MiB;
    # a larger or wrong guess costs nothing but a regrown buffer.
    cap = 0 ## i64
    if n >= 18
      cap = src[n - 4] | (src[n - 3] << 8) | (src[n - 2] << 16) | (src[n - 1] << 24)
      if cap > n * 1032
        cap = n * 1032
      if cap > 268435456
        cap = 268435456
    if cap < 64
      cap = 64
    out = u8[cap]
    st = i64[8]
    st[6] = cap
    pos = 0 ## i64
    while pos < n
      pos = Gzip.__header(src, pos)
      st[0] = pos
      st[5] = st[4]
      out = Gzip.__inflate(src, out, st)
      pos = st[0]
      if pos + 8 > n
        Gzip.__fail(:truncated, "gzip: truncated trailer")
      crc = src[pos] | (src[pos + 1] << 8) | (src[pos + 2] << 16) | (src[pos + 3] << 24)
      isize = src[pos + 4] | (src[pos + 5] << 8) | (src[pos + 6] << 16) | (src[pos + 7] << 24)
      lo = st[5] ## i64
      hi = st[4] ## i64
      if crc != Gzip.__crc(out, lo, hi)
        Gzip.__fail(:crc, "gzip: crc check failed")
      if isize != ((hi - lo) & 0xFFFFFFFF)
        Gzip.__fail(:size, "gzip: incorrect length of data produced")
      pos += 8
      while pos < n && src[pos] == 0
        pos += 1
    used = st[4] ## i64
    Gzip.__release(st)
    Gzip.__release_view(src, data)
    if used == out.size
      return out
    exact = Gzip.__sub(out, 0, used)
    Gzip.__release(out)
    exact

  # decompress, with the result as a String.
  -> .decompress_text(data)
    bytes = Gzip.decompress(data)
    text = ccall("w_string_from_byte_array", bytes)
    Gzip.__release(bytes)
    text

  -> .compress(data, level = 6)
    if !level.is_a?(Integer) || level < 0 || level > 9
      raise ArgumentError, "Gzip.compress level must be an Integer from 0 to 9"
    src = Gzip.__bytes(data, "compress") ## u8[]
    n = src.size ## i64
    out = u8[n / 3 + 4096]
    out[0] = 0x1F
    out[1] = 0x8B
    out[2] = 8
    xfl = 0 ## i64
    if level == 9
      xfl = 2
    elsif level <= 1
      xfl = 4
    out[8] = xfl
    out[9] = 0xFF
    st = i64[8]
    st[0] = 10
    out = Gzip.__deflate(src, level, out, st)
    out = Gzip.__reserve(out, st[0], 8)
    crc = Crypto:CRC32.checksum(src) ## i64
    op = st[0] ## i64
    i = 0 ## i64
    while i < 4
      out[op + i] = (crc >> (8 * i)) & 255
      out[op + 4 + i] = (n >> (8 * i)) & 255
      i += 1
    exact = Gzip.__sub(out, 0, op + 8)
    Gzip.__release(out)
    Gzip.__release(st)
    Gzip.__release_view(src, data)
    exact

  # gzip, then Base64 in lines of `width` characters (a multiple of four),
  # each ended by a newline; width 0 puts everything on one line.  This is the
  # layout of Python's base64.encodebytes (76) and of b64encode(...) + "\n" (0).
  -> .encode_b64(data, level = 6, width = 76)
    if !width.is_a?(Integer) || width < 0 || width % 4 != 0
      raise ArgumentError, "Gzip.encode_b64 width must be 0 or a multiple of 4"
    packed = Gzip.compress(data, level)
    n = packed.size ## i64
    quads = (n + 2) / 3 ## i64
    per_line = width / 4 ## i64
    if per_line == 0
      per_line = quads
    lines = 0 ## i64
    if quads > 0
      lines = (quads + per_line - 1) / per_line
    buf = u8[quads * 4 + lines]
    alphabet = i64[64]
    i = 0 ## i64
    while i < 26
      alphabet[i] = 65 + i
      alphabet[26 + i] = 97 + i
      i += 1
    i = 0
    while i < 10
      alphabet[52 + i] = 48 + i
      i += 1
    alphabet[62] = 43
    alphabet[63] = 47
    i = 0
    o = 0 ## i64
    q = 0 ## i64
    while i < n
      b0 = packed[i] ## i64
      b1 = 0 ## i64
      b2 = 0 ## i64
      if i + 1 < n
        b1 = packed[i + 1]
      if i + 2 < n
        b2 = packed[i + 2]
      v = (b0 << 16) | (b1 << 8) | b2 ## i64
      buf[o] = alphabet[v >> 18]
      buf[o + 1] = alphabet[(v >> 12) & 63]
      buf[o + 2] = 61
      buf[o + 3] = 61
      if i + 1 < n
        buf[o + 2] = alphabet[(v >> 6) & 63]
      if i + 2 < n
        buf[o + 3] = alphabet[v & 63]
      o += 4
      i += 3
      q += 1
      if q == per_line || i >= n
        buf[o] = 10
        o += 1
        q = 0
    text = ccall("w_string_from_byte_array", buf)
    Gzip.__release(buf)
    Gzip.__release(alphabet)
    Gzip.__release(packed)
    text

  # Inverse of encode_b64: newlines are ignored, anything else that is not
  # strict Base64 is an error, as in Python's b64decode(validate=True).
  -> .decode_b64(text)
    packed = Gzip.__unbase64(text)
    out = Gzip.decompress(packed)
    Gzip.__release(packed)
    out

  -> .decode_b64_text(text)
    packed = Gzip.__unbase64(text)
    out = Gzip.decompress_text(packed)
    Gzip.__release(packed)
    out

  # ---------------------------------------------------------------------------
  # Plumbing
  # ---------------------------------------------------------------------------

  # Bytes of a String (borrowed view) or a ByteArray (returned unchanged).
  -> .__bytes(data, who)
    if data.is_a?(String)
      return ccall("w_string_bytes_view", data) ## u8[]
    if data.is_a?(Array) && data.ebits == 8
      return data
    raise ArgumentError, "Gzip.[who] expects a String or a ByteArray"

  # The runtime never frees typed arrays on its own: every scratch array is
  # released here.  (The tree-walking interpreter has no explicit free and
  # leaves the arrays to the process.)
  -> .__release(arr)
    begin
      ccall("w_value_free_w", arr)
    rescue e
      nil
    nil

  # Views made by __bytes are released too (their header only).
  -> .__release_view(src, data)
    Gzip.__release(src) if data.is_a?(String)
    nil

  -> .__fail(code, message)
    raise GzipError.new(message).with_code(code)

  # CRC-32 of out[lo, hi).
  -> .__crc(out, lo, hi) (u8[] i64 i64) i64
    if lo == 0 && hi == out.size
      return Crypto:CRC32.checksum(out)
    part = Gzip.__sub(out, lo, hi)
    crc = Crypto:CRC32.checksum(part)
    Gzip.__release(part)
    crc

  # Copy n bytes src[soff ...] to dst[doff ...] (ranges must not overlap).
  -> .__copy(dst, doff, src, soff, n) (u8[] i64 u8[] i64 i64) i64
    i = 0 ## i64
    while i + 8 <= n
      array_store_u64(dst, doff + i, array_load_u64(src, soff + i))
      i += 8
    while i < n
      dst[doff + i] = src[soff + i]
      i += 1
    n

  # A fresh copy of arr[lo, hi).  (`Array#slice` would be a view registered
  # against its parent, and the parents here are freed explicitly.)
  -> .__sub(arr, lo, hi) (u8[] i64 i64) u8[]
    part = u8[hi - lo]
    Gzip.__copy(part, 0, arr, lo, hi - lo)
    part

  # A copy of `out` with room for at least `used + want` bytes (the old array
  # is released).
  -> .__grow(out, used, want) (u8[] i64 i64) u8[]
    cap = out.size * 2 ## i64
    if cap < used + want
      cap = used + want
    if cap > 2147483647
      Gzip.__fail(:too_large, "gzip: output larger than 2 GiB")
    bigger = u8[cap]
    Gzip.__copy(bigger, 0, out, 0, used)
    Gzip.__release(out)
    bigger

  # `out` with at least `need` free bytes after `op` (plus slack for the bit
  # writers' 8-byte stores).
  -> .__reserve(out, op, need) (u8[] i64 i64) u8[]
    if out.size - op >= need + 16
      return out
    Gzip.__grow(out, op, need + 16)

  # Bytes of strict Base64 text: newlines dropped, the rest must be a whole
  # number of four-character groups from the standard alphabet, with at most
  # two '=' at the very end.  Unused bits of the last character are not
  # checked.
  -> .__unbase64(text)
    src = Gzip.__bytes(text, "decode_b64") ## u8[]
    n = src.size ## i64
    sp = ccall_nobox("w_u8_live_data_ptr", src) ## i64
    chars = u8[n]
    cp = ccall_nobox("w_u8_live_data_ptr", chars) ## i64
    m = 0 ## i64
    i = 0 ## i64
    while i < n
      b = raw_load_u8(sp, i) ## i64
      if b != 10
        raw_store_u8(cp, m, b)
        m += 1
      i += 1
    if m % 4 != 0
      Gzip.__fail(:base64, "gzip: base64 text is not a whole number of groups")
    pad = 0 ## i64
    if m > 0 && raw_load_u8(cp, m - 1) == 61
      pad = 1
      if raw_load_u8(cp, m - 2) == 61
        pad = 2
    digit = i64[256]
    i = 0
    while i < 256
      digit[i] = -1
      i += 1
    i = 0
    while i < 26
      digit[65 + i] = i
      digit[97 + i] = 26 + i
      i += 1
    i = 0
    while i < 10
      digit[48 + i] = 52 + i
      i += 1
    digit[43] = 62
    digit[47] = 63
    digit[61] = 64
    out = u8[m / 4 * 3 - pad]
    op = ccall_nobox("w_u8_live_data_ptr", out) ## i64
    quads = m / 4 ## i64
    q = 0 ## i64
    bad = 0 ## i64
    # '=' has the out-of-range digit 64, so one test of the accumulated bits
    # catches invalid characters (negative) and misplaced padding (bit 6).
    while q < quads - 1
      a = digit[raw_load_u8(cp, 4 * q)] ## i64
      b = digit[raw_load_u8(cp, 4 * q + 1)] ## i64
      c = digit[raw_load_u8(cp, 4 * q + 2)] ## i64
      d = digit[raw_load_u8(cp, 4 * q + 3)] ## i64
      bad = bad | a | b | c | d
      v = (a << 18) | (b << 12) | (c << 6) | d ## i64
      raw_store_u8(op, 3 * q, v >> 16)
      raw_store_u8(op, 3 * q + 1, (v >> 8) & 255)
      raw_store_u8(op, 3 * q + 2, v & 255)
      q += 1
    if quads > 0
      # The last group: its padding characters count as zero digits.
      last = 4 * (quads - 1) ## i64
      a = digit[raw_load_u8(cp, last)] ## i64
      b = digit[raw_load_u8(cp, last + 1)] ## i64
      c = 0 ## i64
      d = 0 ## i64
      if pad < 2
        c = digit[raw_load_u8(cp, last + 2)]
      if pad < 1
        d = digit[raw_load_u8(cp, last + 3)]
      bad = bad | a | b | c | d
      v = (a << 18) | (b << 12) | (c << 6) | d ## i64
      raw_store_u8(op, 3 * (quads - 1), v >> 16)
      if pad < 2
        raw_store_u8(op, 3 * (quads - 1) + 1, (v >> 8) & 255)
      if pad < 1
        raw_store_u8(op, 3 * (quads - 1) + 2, v & 255)
    if bad < 0 || (bad & 64) != 0
      Gzip.__fail(:base64, "gzip: invalid base64 character")
    Gzip.__release(digit)
    Gzip.__release(chars)
    Gzip.__release_view(src, text)
    out

  # ---------------------------------------------------------------------------
  # Huffman codes, shared by both directions
  # ---------------------------------------------------------------------------

  # Reverse the low `len` bits of `code` (Huffman codes are sent MSB first,
  # the bit stream is LSB first).
  -> .__reverse(code, len) (i64 i64) i64
    x = code ## i64
    x = ((x & 0x5555) << 1) | ((x >> 1) & 0x5555)
    x = ((x & 0x3333) << 2) | ((x >> 2) & 0x3333)
    x = ((x & 0x0F0F) << 4) | ((x >> 4) & 0x0F0F)
    x = ((x & 0x00FF) << 8) | ((x >> 8) & 0x00FF)
    x >> (16 - len)

  # The order in which the code lengths of the code-length alphabet are sent:
  # 16 17 18 0 8 7 9 6 10 5 11 4 12 3 13 2 14 1 15, five bits each, the first
  # twelve in `lo` and the last seven in `hi`.
  -> .__order(i) (i64) i64
    lo = 0x22CAA324E804A30 ## i64
    hi = 0x3C2E1346C ## i64
    if i < 12
      return (lo >> (5 * i)) & 31
    (hi >> (5 * (i - 12))) & 31

  # Canonical codes (RFC 1951 3.2.2) for the code lengths lens[first ...
  # first + n): out[obase + i] = reversed code | length << 16, or 0 for an
  # unused symbol.  Leaves the number of codes of each length in wk[0..16)
  # (wk is 32 scratch words).
  -> .__canonical(lens, first, n, out, obase, wk) (i64[] i64 i64 i64[] i64 i64[]) i64
    i = 0 ## i64
    while i < 32
      wk[i] = 0
      i += 1
    i = 0
    while i < n
      l = lens[first + i] ## i64
      wk[l] = wk[l] + 1
      i += 1
    wk[0] = 0
    code = 0 ## i64
    l = 1 ## i64
    while l <= 15
      code = (code + wk[l - 1]) << 1
      wk[16 + l] = code
      l += 1
    i = 0
    while i < n
      l = lens[first + i]
      if l == 0
        out[obase + i] = 0
      else
        c = wk[16 + l] ## i64
        wk[16 + l] = c + 1
        out[obase + i] = Gzip.__reverse(c, l) | (l << 16)
      i += 1
    0

  # ---------------------------------------------------------------------------
  # gzip container (RFC 1952)
  # ---------------------------------------------------------------------------

  # Parse the member header at src[pos]; returns the offset of the DEFLATE data.
  -> .__header(src, pos) (u8[] i64) i64
    n = src.size ## i64
    if n - pos < 10
      if n - pos >= 2 && (src[pos] != 0x1F || src[pos + 1] != 0x8B)
        Gzip.__fail(:not_gzip, "gzip: not a gzip stream")
      Gzip.__fail(:truncated, "gzip: truncated header")
    if src[pos] != 0x1F || src[pos + 1] != 0x8B
      Gzip.__fail(:not_gzip, "gzip: not a gzip stream")
    if src[pos + 2] != 8
      Gzip.__fail(:bad_method, "gzip: unknown compression method")
    flags = src[pos + 3] ## i64
    if (flags & 0xE0) != 0
      Gzip.__fail(:bad_flags, "gzip: reserved header flags set")
    p = pos + 10 ## i64
    if (flags & 4) != 0
      if p + 2 > n
        Gzip.__fail(:truncated, "gzip: truncated header")
      p = p + 2 + (src[p] | (src[p + 1] << 8))
    # FNAME and FCOMMENT are zero-terminated strings.
    if (flags & 8) != 0
      while p < n && src[p] != 0
        p += 1
      p += 1
    if (flags & 16) != 0
      while p < n && src[p] != 0
        p += 1
      p += 1
    if (flags & 2) != 0
      if p + 2 > n
        Gzip.__fail(:truncated, "gzip: truncated header")
      head = Gzip.__sub(src, pos, p)
      want = Crypto:CRC32.checksum(head) & 0xFFFF
      Gzip.__release(head)
      if (src[p] | (src[p + 1] << 8)) != want
        Gzip.__fail(:header_crc, "gzip: header crc check failed")
      p += 2
    if p > n
      Gzip.__fail(:truncated, "gzip: truncated header")
    p

  # ---------------------------------------------------------------------------
  # Inflate (RFC 1951)
  # ---------------------------------------------------------------------------

  # The bit reader state lives in an i64[] `st` outside the hot loop:
  #   st[0] ip    next input byte to load
  #   st[1] bb    bit buffer (exactly `bc` valid bits, nothing above)
  #   st[2] bc    number of valid bits
  #   st[3] pad   zero bytes appended past the end of the input
  #   st[4] op    next output byte to write
  #   st[5] ms    output index where this member began (farthest distance)
  #   st[6] cap   usable output capacity
  #   st[7] fixed 1 when ll/dd currently hold the fixed-Huffman tables

  # Symbol templates: what each Huffman symbol decodes to, less the code
  # length.  Entry = value << 16 | type << 8 | extra << 4 | length, with type
  # 1 literal, 2 length/distance base, 3 end of block, 4 subtable link and 0
  # invalid.  `lt` gets 288 literal/length symbols, `dt` 32 distance symbols
  # and `ct` the 19 code-length symbols.
  -> .__templates(lt, dt, ct) (i64[] i64[] i64[]) i64
    i = 0 ## i64
    while i < 256
      lt[i] = (i << 16) | 0x100
      i += 1
    lt[256] = 0x300
    base = 3 ## i64
    i = 257
    while i < 285
      c = i - 257 ## i64
      extra = 0 ## i64
      if c >= 8
        extra = (c >> 2) - 1
      lt[i] = (base << 16) | 0x200 | (extra << 4)
      base += 1 << extra
      i += 1
    lt[285] = (258 << 16) | 0x200
    lt[286] = 0
    lt[287] = 0
    i = 0
    base = 1
    while i < 30
      extra = 0 ## i64
      if i >= 4
        extra = (i >> 1) - 1
      dt[i] = (base << 16) | 0x200 | (extra << 4)
      base += 1 << extra
      i += 1
    dt[30] = 0
    dt[31] = 0
    i = 0
    while i < 19
      ct[i] = (i << 16) | 0x200
      i += 1
    0

  # Build a decode table for the code lengths lens[first ... first + n).
  # `tmpl` maps each symbol to its table entry (less the code length); `root`
  # is the width of the first-level table; `partial` allows an incomplete code
  # made of one 1-bit symbol (or no symbol at all), as zlib does for the
  # literal/length and distance alphabets.  Codes longer than `root` bits go
  # to subtables after the first level.  `wk` is 640 scratch words.  Returns
  # the number of entries used, or -1 for an over-subscribed or incomplete set
  # of lengths.
  -> .__build(lens, first, n, tmpl, table, root, partial, wk) (i64[] i64 i64 i64[] i64[] i64 i64 i64[]) i64
    Gzip.__canonical(lens, first, n, wk, 320, wk)
    longest = 15 ## i64
    while longest > 0 && wk[longest] == 0
      longest -= 1
    size = 1 << root ## i64
    i = 0 ## i64
    while i < size
      table[i] = 0
      i += 1
    if longest == 0
      return size
    left = 1 ## i64
    l = 1 ## i64
    while l <= 15
      left = (left << 1) - wk[l]
      if left < 0
        return -1
      l += 1
    if left > 0 && (partial == 0 || longest != 1)
      return -1
    # Pass 1: codes of at most `root` bits fill the first level; longer codes
    # widen the subtable of their prefix.
    i = 0
    while i < n
      c = wk[320 + i] ## i64
      l = c >> 16 ## i64
      if l != 0
        r = c & 0xFFFF ## i64
        if l <= root
          e = tmpl[i] | l ## i64
          k = r ## i64
          step = 1 << l ## i64
          while k < size
            table[k] = e
            k += step
        else
          p = r & (size - 1) ## i64
          w = l - root ## i64
          if w > ((table[p] >> 4) & 15)
            table[p] = 0x400 | (w << 4)
      i += 1
    # Pass 2: place the subtables after the first level.
    spill = size ## i64
    i = 0
    while i < n
      c = wk[320 + i] ## i64
      if (c >> 16) > root
        p = c & (size - 1) ## i64
        t = table[p] ## i64
        if (t >> 16) == 0
          table[p] = t | (spill << 16)
          spill += 1 << ((t >> 4) & 15)
      i += 1
    if spill > table.size
      return -1
    # Pass 3: fill the subtables.
    i = 0
    while i < n
      c = wk[320 + i] ## i64
      l = c >> 16 ## i64
      if l > root
        r = c & 0xFFFF ## i64
        t = table[r & (size - 1)] ## i64
        base = t >> 16 ## i64
        top = 1 << ((t >> 4) & 15) ## i64
        e = tmpl[i] | l ## i64
        step = 1 << (l - root) ## i64
        k = r >> root ## i64
        while k < top
          table[base + k] = e
          k += step
      i += 1
    spill

  # Load more input bytes into the bit buffer (byte at a time; not the hot
  # path).  Reading past the end supplies zero bytes and counts them in `pad`.
  -> .__refill(st, src) (i64[] u8[]) i64
    ip = st[0] ## i64
    bb = st[1] ## i64
    bc = st[2] ## i64
    pad = st[3] ## i64
    n = src.size ## i64
    while bc <= 55
      if ip < n
        bb = bb | (src[ip] << bc)
        ip += 1
      else
        pad += 1
      bc += 8
    st[0] = ip
    st[1] = bb
    st[2] = bc
    st[3] = pad
    0

  # Read n <= 16 bits.
  -> .__bits(st, src, n) (i64[] u8[] i64) i64
    if st[2] < n
      Gzip.__refill(st, src)
    v = st[1] & ((1 << n) - 1) ## i64
    st[1] = st[1] >> n
    st[2] = st[2] - n
    if st[2] < 8 * st[3]
      Gzip.__fail(:truncated, "gzip: truncated stream")
    v

  # The fixed Huffman codes of RFC 1951 section 3.2.6.
  -> .__fixed(ll, dd, lt, dt, lens, wk, st) (i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
    if st[7] == 1
      return 0
    i = 0 ## i64
    while i < 288
      l = 8 ## i64
      if i >= 144 && i < 256
        l = 9
      elsif i >= 256 && i < 280
        l = 7
      lens[i] = l
      i += 1
    while i < 320
      lens[i] = 5
      i += 1
    Gzip.__build(lens, 0, 288, lt, ll, 10, 1, wk)
    Gzip.__build(lens, 288, 32, dt, dd, 8, 1, wk)
    st[7] = 1
    0

  # Read the code lengths of a dynamic block and build both decode tables.
  -> .__dynamic(src, ll, dd, cl, lt, dt, ct, lens, wk, st) (u8[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
    hlit = Gzip.__bits(st, src, 5) + 257 ## i64
    hdist = Gzip.__bits(st, src, 5) + 1 ## i64
    hclen = Gzip.__bits(st, src, 4) + 4 ## i64
    if hlit > 286 || hdist > 30
      Gzip.__fail(:bad_huffman, "gzip: too many length or distance symbols")
    i = 0 ## i64
    while i < 19
      lens[i] = 0
      i += 1
    i = 0
    while i < hclen
      lens[Gzip.__order(i)] = Gzip.__bits(st, src, 3)
      i += 1
    if Gzip.__build(lens, 0, 19, ct, cl, 7, 0, wk) < 0
      Gzip.__fail(:bad_huffman, "gzip: invalid code lengths set")
    total = hlit + hdist ## i64
    i = 0
    while i < total
      if st[2] < 7
        Gzip.__refill(st, src)
      e = cl[st[1] & 127] ## i64
      k = e & 15 ## i64
      st[1] = st[1] >> k
      st[2] = st[2] - k
      sym = e >> 16 ## i64
      if sym < 16
        lens[i] = sym
        i += 1
      else
        prev = 0 ## i64
        rep = 0 ## i64
        if sym == 16
          if i == 0
            Gzip.__fail(:bad_huffman, "gzip: invalid bit length repeat")
          prev = lens[i - 1]
          rep = 3 + Gzip.__bits(st, src, 2)
        elsif sym == 17
          rep = 3 + Gzip.__bits(st, src, 3)
        else
          rep = 11 + Gzip.__bits(st, src, 7)
        if i + rep > total
          Gzip.__fail(:bad_huffman, "gzip: invalid bit length repeat")
        while rep > 0
          lens[i] = prev
          i += 1
          rep -= 1
    if st[2] < 8 * st[3]
      Gzip.__fail(:truncated, "gzip: truncated stream")
    if lens[256] == 0
      Gzip.__fail(:bad_huffman, "gzip: missing end-of-block code")
    if Gzip.__build(lens, 0, hlit, lt, ll, 10, 1, wk) < 0
      Gzip.__fail(:bad_huffman, "gzip: invalid literal/length code lengths")
    if Gzip.__build(lens, hlit, hdist, dt, dd, 8, 1, wk) < 0
      Gzip.__fail(:bad_huffman, "gzip: invalid distance code lengths")
    st[7] = 0
    0

  # A stored block: LEN and NLEN, then LEN raw bytes.
  -> .__stored(src, out0, st) (u8[] u8[] i64[]) u8[]
    out = out0
    real = st[2] - 8 * st[3] ## i64
    if real < 0
      Gzip.__fail(:truncated, "gzip: truncated stream")
    drop = real & 7 ## i64
    real -= drop
    pos = st[0] - (real >> 3) ## i64
    n = src.size ## i64
    if pos + 4 > n
      Gzip.__fail(:truncated, "gzip: truncated stored block")
    len = src[pos] | (src[pos + 1] << 8) ## i64
    nlen = src[pos + 2] | (src[pos + 3] << 8) ## i64
    if len != (nlen ^ 0xFFFF)
      Gzip.__fail(:bad_stored, "gzip: invalid stored block lengths")
    pos += 4
    if pos + len > n
      Gzip.__fail(:truncated, "gzip: truncated stored block")
    if st[4] + len > st[6]
      out = Gzip.__grow(out, st[4], len)
      st[6] = out.size
    Gzip.__copy(out, st[4], src, pos, len)
    st[4] = st[4] + len
    st[0] = pos + len
    st[1] = 0
    st[2] = 0
    st[3] = 0
    out

  # Decode Huffman-coded symbols until the end-of-block code.  Returns 0 at
  # the end of the block, 1 when the output is full (grow it and call again;
  # nothing of the pending symbol has been consumed), or a negative error:
  # -1 bad literal/length code, -2 bad distance code, -3 distance too far
  # back, -4 truncated input.
  -> .__codes(src, out, ll, dd, st) (u8[] u8[] i64[] i64[] i64[]) i64
    n = src.size ## i64
    ip = st[0] ## i64
    bb = st[1] ## i64
    bc = st[2] ## i64
    pad = st[3] ## i64
    op = st[4] ## i64
    ms = st[5] ## i64
    cap = st[6] ## i64
    status = 0 ## i64
    while true
      # Refill to at least 56 bits: one unaligned 8-byte load while there is
      # input, single bytes (then zeros, counted in `pad`) at the very end.
      if ip + 8 <= n
        bb = bb | ((array_load_u64(src, ip) << bc) & 0x7FFFFFFFFFFFFFFF)
        ip += (63 - bc) >> 3
        bc = bc | 56
      else
        while bc <= 55
          if ip < n
            bb = bb | (src[ip] << bc)
            ip += 1
          else
            pad += 1
          bc += 8
        if pad > 7
          status = -4
          break
      e = ll[bb & 1023] ## i64
      if (e & 0x400) != 0
        w = (e >> 4) & 15 ## i64
        j = (e >> 16) + ((bb >> 10) & ((1 << w) - 1)) ## i64
        e = ll[j]
      k = e & 15 ## i64
      kind = e & 0x700 ## i64
      if kind == 0x100
        if op >= cap
          status = 1
          break
        bb = bb >> k
        bc -= k
        out[op] = e >> 16
        op += 1
      elsif kind == 0x200
        b = bb >> k ## i64
        x = (e >> 4) & 15 ## i64
        len = (e >> 16) + (b & ((1 << x) - 1)) ## i64
        b = b >> x
        d = dd[b & 255] ## i64
        if (d & 0x400) != 0
          w = (d >> 4) & 15 ## i64
          j = (d >> 16) + ((b >> 8) & ((1 << w) - 1)) ## i64
          d = dd[j]
        if (d & 0x700) != 0x200
          status = -2
          break
        y = d & 15 ## i64
        b = b >> y
        z = (d >> 4) & 15 ## i64
        dist = (d >> 16) + (b & ((1 << z) - 1)) ## i64
        b = b >> z
        if dist > op - ms
          status = -3
          break
        if op + len > cap
          status = 1
          break
        bb = b
        bc -= k + x + y + z
        stop = op + len ## i64
        if stop + 8 > cap
          while op < stop
            out[op] = out[op - dist]
            op += 1
        elsif dist == 1
          fill = out[op - 1] * 72340172838076673 ## i64
          while op < stop
            array_store_u64(out, op, fill)
            op += 8
          op = stop
        else
          # Room to store whole words past the end.  A period shorter than a
          # word is first copied byte by byte, then read at a multiple of it.
          if dist < 8
            lead = op + 8 ## i64
            if lead > stop
              lead = stop
            while op < lead
              out[op] = out[op - dist]
              op += 1
            period = dist ## i64
            while dist < 8
              dist += period
          while op < stop
            array_store_u64(out, op, array_load_u64(out, op - dist))
            op += 8
          op = stop
      elsif kind == 0x300
        bb = bb >> k
        bc -= k
        if bc < 8 * pad
          status = -4
        break
      else
        status = -1
        break
    st[0] = ip
    st[1] = bb & ((1 << bc) - 1)
    st[2] = bc
    st[3] = pad
    st[4] = op
    status

  # Inflate one DEFLATE stream starting at src[st[0]], appending to out at
  # st[4] (growing it as needed).  Returns the output buffer; st[0] is left at
  # the first byte after the stream and st[4] after its last output byte.
  -> .__inflate(src, out0, st) (u8[] u8[] i64[]) u8[]
    out = out0
    ll = i64[4096]
    dd = i64[2048]
    cl = i64[128]
    lt = i64[288]
    dt = i64[32]
    ct = i64[19]
    lens = i64[320]
    wk = i64[640]
    Gzip.__templates(lt, dt, ct)
    st[1] = 0
    st[2] = 0
    st[3] = 0
    st[7] = 0
    done = 0 ## i64
    while done == 0
      header = Gzip.__bits(st, src, 3) ## i64
      done = header & 1
      kind = header >> 1 ## i64
      if kind == 0
        out = Gzip.__stored(src, out, st)
      elsif kind == 3
        Gzip.__fail(:bad_block, "gzip: invalid block type")
      else
        if kind == 1
          Gzip.__fixed(ll, dd, lt, dt, lens, wk, st)
        else
          Gzip.__dynamic(src, ll, dd, cl, lt, dt, ct, lens, wk, st)
        status = Gzip.__codes(src, out, ll, dd, st) ## i64
        while status == 1
          out = Gzip.__grow(out, st[4], 65536)
          st[6] = out.size
          status = Gzip.__codes(src, out, ll, dd, st)
        if status < 0
          Gzip.__inflate_error(status)
    real = st[2] - 8 * st[3] ## i64
    if real < 0
      Gzip.__fail(:truncated, "gzip: truncated stream")
    st[0] = st[0] - (real >> 3)
    Gzip.__release(ll)
    Gzip.__release(dd)
    Gzip.__release(cl)
    Gzip.__release(lt)
    Gzip.__release(dt)
    Gzip.__release(ct)
    Gzip.__release(lens)
    Gzip.__release(wk)
    out

  -> .__inflate_error(status) (i64) i64
    if status == -1
      Gzip.__fail(:bad_code, "gzip: invalid literal/length code")
    if status == -2
      Gzip.__fail(:bad_code, "gzip: invalid distance code")
    if status == -3
      Gzip.__fail(:bad_distance, "gzip: invalid distance too far back")
    Gzip.__fail(:truncated, "gzip: truncated stream")
    0

  # ---------------------------------------------------------------------------
  # Deflate (RFC 1951)
  # ---------------------------------------------------------------------------

  # Constant tables of the encoder, all in one i64[1232]:
  #   tb[0..29)      length base of length code c (symbol 257 + c)
  #   tb[32..61)     its extra bits
  #   tb[64..94)     distance base of distance code c
  #   tb[96..126)    its extra bits
  #   tb[128..387)   length (3..258) -> length code
  #   tb[400..912)   distance -> distance code, as zlib: tb[400 + d - 1] for
  #                  d <= 256, tb[656 + (d - 1) / 128] above
  #   tb[912..1200)  fixed literal/length codes (reversed code | length << 16)
  #   tb[1200..1232) fixed distance codes
  -> .__enc_tables(tb) (i64[]) i64
    base = 3 ## i64
    c = 0 ## i64
    while c < 28
      extra = 0 ## i64
      if c >= 8
        extra = (c >> 2) - 1
      tb[c] = base
      tb[32 + c] = extra
      k = base ## i64
      while k < base + (1 << extra)
        tb[128 + k] = c
        k += 1
      base += 1 << extra
      c += 1
    tb[28] = 258
    tb[60] = 0
    tb[128 + 258] = 28
    base = 1
    c = 0
    while c < 30
      extra = 0 ## i64
      if c >= 4
        extra = (c >> 1) - 1
      tb[64 + c] = base
      tb[96 + c] = extra
      d0 = base - 1 ## i64
      stop = d0 + (1 << extra) ## i64
      while d0 < stop
        if d0 < 256
          tb[400 + d0] = c
          d0 += 1
        else
          tb[656 + (d0 >> 7)] = c
          d0 += 128
      base += 1 << extra
      c += 1
    lens = i64[320]
    wk = i64[32]
    i = 0 ## i64
    while i < 288
      l = 8 ## i64
      if i >= 144 && i < 256
        l = 9
      elsif i >= 256 && i < 280
        l = 7
      lens[i] = l
      i += 1
    while i < 320
      lens[i] = 5
      i += 1
    Gzip.__canonical(lens, 0, 288, tb, 912, wk)
    Gzip.__canonical(lens, 288, 32, tb, 1200, wk)
    Gzip.__release(lens)
    Gzip.__release(wk)
    0

  # Code lengths of an optimal prefix code for freq[fbase ... fbase + n), none
  # longer than `maxbits`, written to lens[lbase ...] (0 for unused symbols).
  # At least two symbols always get a code (unused ones stand in when fewer
  # are used) so the code is complete and every decoder accepts it.
  -> .__lengths(freq, fbase, n, maxbits, lens, lbase) (i64[] i64 i64 i64 i64[] i64) i64
    m = 0 ## i64
    i = 0 ## i64
    while i < n
      lens[lbase + i] = 0
      if freq[fbase + i] > 0
        m += 1
      i += 1
    count = m ## i64
    if count < 2
      count = 2
    # Symbols sorted by (frequency, index), packed as frequency << 9 | index.
    ks = i64[count]
    k = 0 ## i64
    i = 0
    while i < n
      f = freq[fbase + i] ## i64
      if f > 0
        ks[k] = (f << 9) | i
        k += 1
      i += 1
    j = 0 ## i64
    while k < 2
      if freq[fbase + j] == 0
        ks[k] = (1 << 9) | j
        k += 1
      j += 1
    ks.sort!
    # Two-queue Huffman construction: leaves are the sorted symbols, internal
    # nodes come out in nondecreasing weight and queue up behind them.
    # sc: weights [0, 2 count), parents [2 count, 4 count), depths
    # [4 count, 6 count), leaf counts per depth from 6 count.
    sc = i64[8 * count + 40]
    wt = 0 ## i64
    par = 2 * count ## i64
    dep = 4 * count ## i64
    cnt = 6 * count ## i64
    i = 0
    while i < count
      sc[wt + i] = ks[i] >> 9
      i += 1
    li = 0 ## i64
    ii = count ## i64
    ni = count ## i64
    while ni < 2 * count - 1
      a = 0 ## i64
      b = 0 ## i64
      if li < count && (ii >= ni || sc[wt + li] <= sc[wt + ii])
        a = li
        li += 1
      else
        a = ii
        ii += 1
      if li < count && (ii >= ni || sc[wt + li] <= sc[wt + ii])
        b = li
        li += 1
      else
        b = ii
        ii += 1
      sc[wt + ni] = sc[wt + a] + sc[wt + b]
      sc[par + a] = ni
      sc[par + b] = ni
      ni += 1
    i = 2 * count - 3
    while i >= 0
      sc[dep + i] = sc[dep + sc[par + i]] + 1
      i -= 1
    maxd = 0 ## i64
    i = 0
    while i < count
      d = sc[dep + i] ## i64
      sc[cnt + d] = sc[cnt + d] + 1
      if d > maxd
        maxd = d
      i += 1
    # Too deep: move leaves up until the code fits (Kraft sum unchanged).
    d = maxd
    while d > maxbits
      while sc[cnt + d] > 0
        j = d - 2
        while sc[cnt + j] == 0
          j -= 1
        sc[cnt + d] = sc[cnt + d] - 2
        sc[cnt + d - 1] = sc[cnt + d - 1] + 1
        sc[cnt + j + 1] = sc[cnt + j + 1] + 2
        sc[cnt + j] = sc[cnt + j] - 1
      d -= 1
    # The rarest symbols get the longest codes.
    idx = 0 ## i64
    d = maxbits
    while d >= 1
      c = sc[cnt + d] ## i64
      while c > 0
        lens[lbase + (ks[idx] & 511)] = d
        idx += 1
        c -= 1
      d -= 1
    Gzip.__release(ks)
    Gzip.__release(sc)
    0

  # Append the low `nbits` (<= 16) bits of `value` to the output.  Not the
  # hot path (headers only).
  -> .__put(out, st, value, nbits) (u8[] i64[] i64 i64) i64
    bb = st[1] | (value << st[2]) ## i64
    bc = st[2] + nbits ## i64
    op = st[0] ## i64
    while bc >= 8
      out[op] = bb & 255
      op += 1
      bb = bb >> 8
      bc -= 8
    st[0] = op
    st[1] = bb
    st[2] = bc
    0

  # Stored blocks covering src[lo, hi).  Zero-length input still needs one
  # block.  The last chunk carries BFINAL when `last` is 1.
  -> .__stored_out(src, out0, st, lo, hi, last) (u8[] u8[] i64[] i64 i64 i64) u8[]
    out = out0
    total = hi - lo ## i64
    chunks = (total + 65534) / 65535 ## i64
    if chunks == 0
      chunks = 1
    out = Gzip.__reserve(out, st[0], total + 5 * chunks + 16)
    pos = lo ## i64
    k = 0 ## i64
    while k < chunks
      len = hi - pos ## i64
      if len > 65535
        len = 65535
      bfinal = 0 ## i64
      if last == 1 && k == chunks - 1
        bfinal = 1
      Gzip.__put(out, st, bfinal, 3)
      Gzip.__put(out, st, 0, (8 - st[2]) & 7)
      op = st[0] ## i64
      out[op] = len & 255
      out[op + 1] = len >> 8
      out[op + 2] = (len ^ 0xFFFF) & 255
      out[op + 3] = (len ^ 0xFFFF) >> 8
      Gzip.__copy(out, op + 4, src, pos, len)
      st[0] = op + 4 + len
      pos += len
      k += 1
    out

  # Write the symbols of a block (dist << 8 | literal, or length - 3) with the
  # given codes (entries at lle[lb ...] and dde[db ...]), then the end-of-block
  # code.
  -> .__emit(out, st, syms, sn, lle, lb, dde, db, tb) (u8[] i64[] i32[] i64 i64[] i64 i64[] i64 i64[]) i64
    op = st[0] ## i64
    bb = st[1] ## i64
    bc = st[2] ## i64
    i = 0 ## i64
    while i <= sn
      c = 0 ## i64
      if i == sn
        c = lle[lb + 256]
        bb = bb | ((c & 0xFFFF) << bc)
        bc += c >> 16
      else
        v = syms[i] ## i64
        x = v & 255 ## i64
        d = v >> 8 ## i64
        if d == 0
          c = lle[lb + x]
          bb = bb | ((c & 0xFFFF) << bc)
          bc += c >> 16
        else
          lc = tb[131 + x] ## i64
          c = lle[lb + 257 + lc]
          bb = bb | ((c & 0xFFFF) << bc)
          bc += c >> 16
          bb = bb | ((x + 3 - tb[lc]) << bc)
          bc += tb[32 + lc]
          dc = 0 ## i64
          if d <= 256
            dc = tb[399 + d]
          else
            dc = tb[656 + ((d - 1) >> 7)]
          c = dde[db + dc]
          bb = bb | ((c & 0xFFFF) << bc)
          bc += c >> 16
          bb = bb | ((d - tb[64 + dc]) << bc)
          bc += tb[96 + dc]
      array_store_u64(out, op, bb)
      op += bc >> 3
      bb = bb >> (bc & 56)
      bc = bc & 7
      i += 1
    st[0] = op
    st[1] = bb
    st[2] = bc
    0

  # Encode one block: the symbols in syms[0, sn), covering src[lo, hi), as
  # whichever of a stored, fixed-Huffman or dynamic-Huffman block is smallest.
  -> .__block(src, out0, st, syms, sn, lo, hi, last, tb) (u8[] u8[] i64[] i32[] i64 i64 i64 i64 i64[]) u8[]
    out = out0
    fl = i64[288]
    fd = i64[32]
    xb = 0 ## i64
    i = 0 ## i64
    while i < sn
      v = syms[i] ## i64
      x = v & 255 ## i64
      d = v >> 8 ## i64
      if d == 0
        fl[x] = fl[x] + 1
      else
        c = tb[131 + x] ## i64
        fl[257 + c] = fl[257 + c] + 1
        xb += tb[32 + c]
        dc = 0 ## i64
        if d <= 256
          dc = tb[399 + d]
        else
          dc = tb[656 + ((d - 1) >> 7)]
        fd[dc] = fd[dc] + 1
        xb += tb[96 + dc]
      i += 1
    fl[256] = 1
    # Dynamic trees and the run-length coded code lengths that describe them.
    ll_len = i64[288]
    d_len = i64[32]
    Gzip.__lengths(fl, 0, 286, 15, ll_len, 0)
    Gzip.__lengths(fd, 0, 30, 15, d_len, 0)
    hlit = 286 ## i64
    while hlit > 257 && ll_len[hlit - 1] == 0
      hlit -= 1
    hdist = 30 ## i64
    while hdist > 1 && d_len[hdist - 1] == 0
      hdist -= 1
    seq = i64[320]
    i = 0
    while i < hlit
      seq[i] = ll_len[i]
      i += 1
    i = 0
    while i < hdist
      seq[hlit + i] = d_len[i]
      i += 1
    total = hlit + hdist ## i64
    tk = i64[320]
    cf = i64[19]
    nt = 0 ## i64
    i = 0
    while i < total
      v = seq[i] ## i64
      run = 1 ## i64
      while i + run < total && seq[i + run] == v
        run += 1
      i += run
      if v == 0
        while run >= 11
          t = run ## i64
          if t > 138
            t = 138
          tk[nt] = 18 | ((t - 11) << 8)
          cf[18] = cf[18] + 1
          nt += 1
          run -= t
        if run >= 3
          tk[nt] = 17 | ((run - 3) << 8)
          cf[17] = cf[17] + 1
          nt += 1
          run = 0
        while run > 0
          tk[nt] = 0
          cf[0] = cf[0] + 1
          nt += 1
          run -= 1
      else
        tk[nt] = v
        cf[v] = cf[v] + 1
        nt += 1
        run -= 1
        while run >= 3
          t = run ## i64
          if t > 6
            t = 6
          tk[nt] = 16 | ((t - 3) << 8)
          cf[16] = cf[16] + 1
          nt += 1
          run -= t
        while run > 0
          tk[nt] = v
          cf[v] = cf[v] + 1
          nt += 1
          run -= 1
    cl_len = i64[32]
    Gzip.__lengths(cf, 0, 19, 7, cl_len, 0)
    hclen = 19 ## i64
    while hclen > 4 && cl_len[Gzip.__order(hclen - 1)] == 0
      hclen -= 1
    # Exact sizes in bits.
    header_bits = 14 + 3 * hclen ## i64
    i = 0
    while i < 19
      extra = 0 ## i64
      if i == 16
        extra = 2
      elsif i == 17
        extra = 3
      elsif i == 18
        extra = 7
      header_bits += cf[i] * (cl_len[i] + extra)
      i += 1
    dyn_bits = 3 + header_bits + xb ## i64
    fixed_bits = 3 + xb ## i64
    i = 0
    while i < 286
      dyn_bits += fl[i] * ll_len[i]
      fixed_bits += fl[i] * (tb[912 + i] >> 16)
      i += 1
    i = 0
    while i < 30
      dyn_bits += fd[i] * d_len[i]
      fixed_bits += fd[i] * 5
      i += 1
    span = hi - lo ## i64
    chunks = (span + 65534) / 65535 ## i64
    if chunks == 0
      chunks = 1
    stored_bits = 3 + ((8 - ((st[2] + 3) & 7)) & 7) + 32 * chunks + 8 * (chunks - 1) + 8 * span ## i64
    need = 6 * sn + 1024 ## i64
    if span + 5 * chunks + 16 > need
      need = span + 5 * chunks + 16
    out = Gzip.__reserve(out, st[0], need)
    if stored_bits <= fixed_bits && stored_bits <= dyn_bits
      out = Gzip.__stored_out(src, out, st, lo, hi, last)
    elsif fixed_bits <= dyn_bits
      Gzip.__put(out, st, last | 2, 3)
      Gzip.__emit(out, st, syms, sn, tb, 912, tb, 1200, tb)
    else
      lle = i64[288]
      dde = i64[32]
      cle = i64[32]
      wk = i64[32]
      Gzip.__canonical(ll_len, 0, 286, lle, 0, wk)
      Gzip.__canonical(d_len, 0, 30, dde, 0, wk)
      Gzip.__canonical(cl_len, 0, 19, cle, 0, wk)
      Gzip.__put(out, st, last | 4, 3)
      Gzip.__put(out, st, hlit - 257, 5)
      Gzip.__put(out, st, hdist - 1, 5)
      Gzip.__put(out, st, hclen - 4, 4)
      i = 0
      while i < hclen
        Gzip.__put(out, st, cl_len[Gzip.__order(i)], 3)
        i += 1
      i = 0
      while i < nt
        t = tk[i] ## i64
        code = t & 255 ## i64
        e = cle[code] ## i64
        Gzip.__put(out, st, e & 0xFFFF, e >> 16)
        if code == 16
          Gzip.__put(out, st, t >> 8, 2)
        elsif code == 17
          Gzip.__put(out, st, t >> 8, 3)
        elsif code == 18
          Gzip.__put(out, st, t >> 8, 7)
        i += 1
      Gzip.__emit(out, st, syms, sn, lle, 0, dde, 0, tb)
      Gzip.__release(lle)
      Gzip.__release(dde)
      Gzip.__release(cle)
      Gzip.__release(wk)
    Gzip.__release(fl)
    Gzip.__release(fd)
    Gzip.__release(ll_len)
    Gzip.__release(d_len)
    Gzip.__release(seq)
    Gzip.__release(tk)
    Gzip.__release(cf)
    Gzip.__release(cl_len)
    out

  # The longest match for src[pos ...] among the hash chain that starts at
  # cand0, and only if longer than `floor`.  The distance goes to st[3].
  -> .__longest(src, sp, pos, cand0, prev, floor, chain0, nice0, st) (u8[] i64 i64 i64 i32[] i64 i64 i64 i64[]) i64
    maxlen = src.size - pos ## i64
    if maxlen > 258
      maxlen = 258
    nice = nice0 ## i64
    if nice > maxlen
      nice = maxlen
    best = floor ## i64
    dist = 0 ## i64
    if best >= maxlen
      return best
    limit = pos - 32767 ## i64
    cand = cand0 ## i64
    chain = chain0 ## i64
    while true
      if raw_load_u8(sp, cand + best) == raw_load_u8(sp, pos + best)
        l = 0 ## i64
        more = 1 ## i64
        while more == 1 && l + 8 <= maxlen
          x = array_load_u64(src, cand + l) ^ array_load_u64(src, pos + l) ## i64
          if x != 0
            l += cttz(x) >> 3
            more = 0
          else
            l += 8
        while more == 1 && l < maxlen && raw_load_u8(sp, cand + l) == raw_load_u8(sp, pos + l)
          l += 1
        if l > best
          best = l
          dist = pos - cand
          if l >= nice
            break
      cand = prev[cand & 32767]
      chain -= 1
      if cand < limit || cand < 0 || chain <= 0
        break
    st[3] = dist
    best

  # Deflate src at `level` 0..9 into out at st[0] (growing it as needed); the
  # stream ends at st[0] on return.  Hash chains over the 32 KiB window, lazy
  # matching as in zlib, blocks of 16384 symbols.
  -> .__deflate(src, level, out0, st) (u8[] i64 u8[] i64[]) u8[]
    out = out0
    n = src.size ## i64
    st[1] = 0
    st[2] = 0
    if level == 0
      return Gzip.__stored_out(src, out, st, 0, n, 1)
    sp = ccall_nobox("w_u8_live_data_ptr", src) ## i64
    tb = i64[1232]
    Gzip.__enc_tables(tb)
    head = i32[32768]
    prev = i32[32768]
    syms = i32[16384]
    i = 0 ## i64
    while i < 32768
      head[i] = -1
      i += 1
    # zlib's configuration table: a previous match of `good` or more searches
    # a quarter of `chain` candidates, one of `lazy_limit` or more is taken
    # without looking for a longer one, `nice` ends a search.
    good = 8 ## i64
    lazy_limit = 16 ## i64
    nice = 128 ## i64
    chain = 128 ## i64
    if level == 1
      good = 4
      lazy_limit = 4
      nice = 8
      chain = 4
    elsif level == 2
      good = 4
      lazy_limit = 5
      nice = 16
      chain = 8
    elsif level == 3
      good = 4
      lazy_limit = 6
      nice = 32
      chain = 32
    elsif level == 4
      good = 4
      lazy_limit = 4
      nice = 16
      chain = 16
    elsif level == 5
      good = 8
      lazy_limit = 16
      nice = 32
      chain = 32
    elsif level == 7
      good = 8
      lazy_limit = 32
      nice = 128
      chain = 256
    elsif level == 8
      good = 32
      lazy_limit = 128
      nice = 258
      chain = 1024
    elsif level == 9
      good = 32
      lazy_limit = 258
      nice = 258
      chain = 4096
    pos = 0 ## i64
    plen = 2 ## i64
    pdist = 0 ## i64
    pending = 0 ## i64
    sn = 0 ## i64
    lo = 0 ## i64
    hi = 0 ## i64
    while pos < n
      clen = 2 ## i64
      cdist = 0 ## i64
      if pos + 3 <= n
        h = (((raw_load_u8(sp, pos) | (raw_load_u8(sp, pos + 1) << 8) | (raw_load_u8(sp, pos + 2) << 16)) * 2654435761) & 0xFFFFFFFF) >> 17 ## i64
        cand = head[h] ## i64
        prev[pos & 32767] = cand
        head[h] = pos
        if cand >= 0 && plen < lazy_limit && pos - cand <= 32767
          budget = chain ## i64
          if plen >= good
            budget = chain >> 2
          clen = Gzip.__longest(src, sp, pos, cand, prev, plen, budget, nice, st)
          cdist = st[3]
          if clen == 3 && cdist > 4096
            clen = 2
      if plen >= 3 && clen <= plen
        syms[sn] = (pdist << 8) | (plen - 3)
        sn += 1
        stop = pos - 1 + plen ## i64
        hi = stop
        p = pos + 1 ## i64
        while p < stop
          if p + 3 <= n
            h2 = (((raw_load_u8(sp, p) | (raw_load_u8(sp, p + 1) << 8) | (raw_load_u8(sp, p + 2) << 16)) * 2654435761) & 0xFFFFFFFF) >> 17 ## i64
            prev[p & 32767] = head[h2]
            head[h2] = p
          p += 1
        pos = stop
        plen = 2
        pending = 0
      elsif pending == 1
        syms[sn] = raw_load_u8(sp, pos - 1)
        sn += 1
        hi = pos
        plen = clen
        pdist = cdist
        pos += 1
      else
        pending = 1
        plen = clen
        pdist = cdist
        pos += 1
      if sn == 16384
        out = Gzip.__block(src, out, st, syms, sn, lo, hi, 0, tb)
        lo = hi
        sn = 0
    if pending == 1
      syms[sn] = raw_load_u8(sp, n - 1)
      sn += 1
    out = Gzip.__block(src, out, st, syms, sn, lo, n, 1, tb)
    if st[2] > 0
      out = Gzip.__reserve(out, st[0], 2)
      opos = st[0] ## i64
      out[opos] = st[1] & 255
      st[0] = opos + 1
      st[1] = 0
      st[2] = 0
    Gzip.__release(tb)
    Gzip.__release(head)
    Gzip.__release(prev)
    Gzip.__release(syms)
    out
