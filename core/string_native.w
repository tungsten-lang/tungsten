# Native String methods that are safe to express over the WValue itself.
#
# The legacy core/string.w file remains the long-form API/design scaffold.
# Keep this file deliberately small and parseable so primitive String values
# can register their 0xF9 type-class dispatch without loading that scaffold.

+ String
  # Strings and Symbols share runtime dispatch key 0xF9. String WValues
  # already have bit 0 clear; Symbol WValues use that bit as their only type
  # distinction. This is identity for every String storage mode and the exact
  # historical Symbol -> String conversion. Rope receivers are flattened at
  # the established dispatch boundary before this body runs.
  -> to_s
    wvalue_from_bits($value & -2)

  # String modes 0..5 store their byte count directly in bits 1..3. Modes 6
  # and 7 are slab/heap strings and are only constructed for non-empty data;
  # rope receivers are flattened before String type-class dispatch. Therefore
  # mode 0 is exactly the canonical empty string (and empty symbol) encoding.
  -> empty?
    ($value & 14) == 0

  # Preserve the runtime's canonical byte-count boundary, then reproduce
  # w_int exactly. The current result is u32-sized, but the full signed-i48
  # check keeps this source body correct if String storage grows later.
  -> size
    n = ccall_nobox("w_string_byte_length", self) ## i64
    if n >= -140_737_488_355_328 && n <= 140_737_488_355_327
      tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
      mask = 0xFFFFFFFFFFFF ## i64
      return wvalue_from_bits((tag | (n & mask)) ## i64)
    ccall("w_int", n)

  # Keep both aliases independently dispatchable. Forwarding length to size
  # would add another public method lookup to this leaf operation.
  -> length
    n = ccall_nobox("w_string_byte_length", self) ## i64
    if n >= -140_737_488_355_328 && n <= 140_737_488_355_327
      tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
      mask = 0xFFFFFFFFFFFF ## i64
      return wvalue_from_bits((tag | (n & mask)) ## i64)
    ccall("w_int", n)

  # ASCII case transforms, ported from the former runtime IC handlers.
  # Inline-mode receivers (modes 0..5: length in bits 1..3, byte i at bits
  # 4+8i) transform entirely in registers — no allocation at all, where the
  # C handler malloc'd even for "a". Slab/heap receivers walk the raw bytes
  # into one u8[n+1] buffer whose storage the result String then steals
  # (w_string_take_byte_array), matching the C handler's single-buffer
  # cost. Multibyte UTF-8 (bytes >= 0x80) passes through untouched, and a
  # Symbol receiver yields a String (bit 0 cleared), byte-identical to the
  # former C loops.
  -> swapcase
    sw_v = ($value & -2) ## i64
    sw_mode = (sw_v >> 1) & 7
    if sw_mode <= 5
      sw_i = 0
      while sw_i < sw_mode
        sw_sh = 4 + 8 * sw_i
        sw_b = (sw_v >> sw_sh) & 0xFF
        if (sw_b >= 97 && sw_b <= 122) || (sw_b >= 65 && sw_b <= 90)
          sw_v = sw_v ^ (32 << sw_sh)
        sw_i += 1
      return wvalue_from_bits(sw_v)
    sw_n = ccall_nobox("w_string_byte_length", self) ## i64
    sw_out = u8[sw_n + 1]
    sw_src = ccall_nobox("w_string_data_ptr", self) ## i64
    sw_dst = ccall_nobox("w_u8_live_data_ptr", sw_out) ## i64
    sw_i = 0
    while sw_i < sw_n
      sw_b = raw_load_u8(sw_src, sw_i) ## i64
      if sw_b >= 97 && sw_b <= 122
        sw_b -= 32
      elsif sw_b >= 65 && sw_b <= 90
        sw_b += 32
      raw_store_u8(sw_dst, sw_i, sw_b)
      sw_i += 1
    ccall("w_string_take_byte_array", sw_out, sw_n)

  # First byte upcased, every later byte downcased — the former C handler's
  # exact ASCII semantics ("hello World" -> "Hello world").
  -> capitalize
    cp_v = ($value & -2) ## i64
    cp_mode = (cp_v >> 1) & 7
    if cp_mode <= 5
      cp_i = 0
      while cp_i < cp_mode
        cp_sh = 4 + 8 * cp_i
        cp_b = (cp_v >> cp_sh) & 0xFF
        if cp_i == 0 && cp_b >= 97 && cp_b <= 122
          cp_v = cp_v ^ (32 << cp_sh)
        elsif cp_i > 0 && cp_b >= 65 && cp_b <= 90
          cp_v = cp_v ^ (32 << cp_sh)
        cp_i += 1
      return wvalue_from_bits(cp_v)
    cp_n = ccall_nobox("w_string_byte_length", self) ## i64
    cp_out = u8[cp_n + 1]
    cp_src = ccall_nobox("w_string_data_ptr", self) ## i64
    cp_dst = ccall_nobox("w_u8_live_data_ptr", cp_out) ## i64
    cp_i = 0
    while cp_i < cp_n
      cp_b = raw_load_u8(cp_src, cp_i) ## i64
      if cp_i == 0 && cp_b >= 97 && cp_b <= 122
        cp_b -= 32
      elsif cp_i > 0 && cp_b >= 65 && cp_b <= 90
        cp_b += 32
      raw_store_u8(cp_dst, cp_i, cp_b)
      cp_i += 1
    ccall("w_string_take_byte_array", cp_out, cp_n)

  # Reverse by CODEPOINT (multibyte UTF-8 sequences keep their byte order),
  # ported from the former C IC handler. Inline receivers (<= 5 bytes)
  # rebuild the reversed payload directly in $value bits — no allocation;
  # slab/heap receivers walk raw bytes into one u8[n+1] buffer the result
  # steals. The lead byte gives each codepoint's length (0xF0+ = 4, 0xE0+ =
  # 3, 0xC0+ = 2, else 1), clamped to the remaining bytes exactly as the C
  # loop did, so malformed tails degrade identically.
  -> reverse
    rv_v = ($value & -2) ## i64
    rv_mode = (rv_v >> 1) & 7
    if rv_mode <= 5
      rv_res = 0 ## i64
      rv_i = 0
      rv_w = rv_mode
      while rv_i < rv_mode
        rv_b0 = (rv_v >> (4 + 8 * rv_i)) & 0xFF
        rv_clen = 1
        if rv_b0 >= 240
          rv_clen = 4
        elsif rv_b0 >= 224
          rv_clen = 3
        elsif rv_b0 >= 192
          rv_clen = 2
        if rv_clen > rv_mode - rv_i
          rv_clen = rv_mode - rv_i
        rv_w -= rv_clen
        rv_k = 0
        while rv_k < rv_clen
          rv_byte = (rv_v >> (4 + 8 * (rv_i + rv_k))) & 0xFF
          rv_res = rv_res | (rv_byte << (4 + 8 * (rv_w + rv_k)))
          rv_k += 1
        rv_i += rv_clen
      rv_base = (rv_v & -281474976710641) ## i64  # keep tag(48-63) + low nibble(0-3), clear payload
      return wvalue_from_bits((rv_base | rv_res) ## i64)
    # Slab/heap: delegate the codepoint walk to C, which reverses on a single
    # malloc + intern. Building a Tungsten u8[] here would add a WArray-header
    # allocation per call that pushes long strings over budget vs the former
    # handler; the inline fast path above already wins the common short case.
    ccall("w_string_reverse", self)
