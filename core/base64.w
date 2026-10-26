# Base64 and Base64URL codecs (RFC 4648).
#
# The transforms live in Tungsten. C is used only to expose immutable String
# storage as a borrowed u8[] view and to construct a String from the encoded
# output bytes. Decode returns its native u8[] buffer directly.

+ Base64
  # Return -1 for bytes outside the selected alphabet.
  -> .__decode_digit(byte, url_safe) (i64 bool) i64
    if byte >= 65 && byte <= 90
      return byte - 65
    if byte >= 97 && byte <= 122
      return byte - 71
    if byte >= 48 && byte <= 57
      return byte + 4
    if url_safe
      return 62 if byte == 45
      return 63 if byte == 95
    else
      return 62 if byte == 43
      return 63 if byte == 47
    -1

  -> .__alpha_table(url_safe)
    if url_safe
      if @@alpha_url == nil
        @@alpha_url = ccall("w_base64_decode_input", "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
      return @@alpha_url
    if @@alpha_std == nil
      @@alpha_std = ccall("w_base64_decode_input", "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
    @@alpha_std

  -> .__dec_table(url_safe)
    if url_safe
      if @@dec_url == nil
        tbl = u8[256]
        k = 0
        while k < 256
          v = Base64.__decode_digit(k, true)
          tbl[k] = v < 0 ? 255 : v
          k += 1
        @@dec_url = tbl
      return @@dec_url
    if @@dec_std == nil
      tbl = u8[256]
      k = 0
      while k < 256
        v = Base64.__decode_digit(k, false)
        tbl[k] = v < 0 ? 255 : v
        k += 1
      @@dec_std = tbl
    @@dec_std

  -> .__encode(data, url_safe, padded)
    b64_mode = padded ? (url_safe ? -10 : -8) : (url_safe ? -9 : -11)
    return ccall("w_string_take_byte_array", data, b64_mode)
    # Strings become a borrowed byte view; u8[] inputs are returned unchanged.
    # The view uses the String's stored byte count, so embedded NUL is data.
    b64_input = ccall("w_base64_encode_input", data) ## u8[]
    b64_alphabet = Base64.__alpha_table(url_safe) ## u8[]
    b64_n = b64_input.size ## i64
    if padded
      b64_out_n = ((b64_n + 2) / 3) * 4 ## i64
    else
      b64_out_n = (b64_n / 3) * 4 ## i64
      if b64_n % 3 != 0
        b64_out_n += b64_n % 3 + 1

    b64_output = u8[b64_out_n]
    # Acquire start-adjusted pointers only after every loop-owned allocation.
    # These are raw i64 locals (never boxed or captured), and the loop performs
    # no allocation on its successful path.
    b64_input_ptr = ccall_nobox("w_u8_live_data_ptr", b64_input) ## i64
    b64_alphabet_ptr = ccall_nobox("w_u8_live_data_ptr", b64_alphabet) ## i64
    b64_output_ptr = ccall_nobox("w_u8_live_data_ptr", b64_output) ## i64
    b64_i = 0 ## i64
    b64_j = 0 ## i64
    while b64_i + 12 <= b64_n
      t0 = (raw_load_u8(b64_input_ptr, b64_i) << 16) | (raw_load_u8(b64_input_ptr, b64_i + 1) << 8) | raw_load_u8(b64_input_ptr, b64_i + 2) ## i64
      t1 = (raw_load_u8(b64_input_ptr, b64_i + 3) << 16) | (raw_load_u8(b64_input_ptr, b64_i + 4) << 8) | raw_load_u8(b64_input_ptr, b64_i + 5) ## i64
      t2 = (raw_load_u8(b64_input_ptr, b64_i + 6) << 16) | (raw_load_u8(b64_input_ptr, b64_i + 7) << 8) | raw_load_u8(b64_input_ptr, b64_i + 8) ## i64
      t3 = (raw_load_u8(b64_input_ptr, b64_i + 9) << 16) | (raw_load_u8(b64_input_ptr, b64_i + 10) << 8) | raw_load_u8(b64_input_ptr, b64_i + 11) ## i64
      raw_store_u8(b64_output_ptr, b64_j, raw_load_u8(b64_alphabet_ptr, (t0 >> 18) & 0x3F))
      raw_store_u8(b64_output_ptr, b64_j + 1, raw_load_u8(b64_alphabet_ptr, (t0 >> 12) & 0x3F))
      raw_store_u8(b64_output_ptr, b64_j + 2, raw_load_u8(b64_alphabet_ptr, (t0 >> 6) & 0x3F))
      raw_store_u8(b64_output_ptr, b64_j + 3, raw_load_u8(b64_alphabet_ptr, t0 & 0x3F))
      raw_store_u8(b64_output_ptr, b64_j + 4, raw_load_u8(b64_alphabet_ptr, (t1 >> 18) & 0x3F))
      raw_store_u8(b64_output_ptr, b64_j + 5, raw_load_u8(b64_alphabet_ptr, (t1 >> 12) & 0x3F))
      raw_store_u8(b64_output_ptr, b64_j + 6, raw_load_u8(b64_alphabet_ptr, (t1 >> 6) & 0x3F))
      raw_store_u8(b64_output_ptr, b64_j + 7, raw_load_u8(b64_alphabet_ptr, t1 & 0x3F))
      raw_store_u8(b64_output_ptr, b64_j + 8, raw_load_u8(b64_alphabet_ptr, (t2 >> 18) & 0x3F))
      raw_store_u8(b64_output_ptr, b64_j + 9, raw_load_u8(b64_alphabet_ptr, (t2 >> 12) & 0x3F))
      raw_store_u8(b64_output_ptr, b64_j + 10, raw_load_u8(b64_alphabet_ptr, (t2 >> 6) & 0x3F))
      raw_store_u8(b64_output_ptr, b64_j + 11, raw_load_u8(b64_alphabet_ptr, t2 & 0x3F))
      raw_store_u8(b64_output_ptr, b64_j + 12, raw_load_u8(b64_alphabet_ptr, (t3 >> 18) & 0x3F))
      raw_store_u8(b64_output_ptr, b64_j + 13, raw_load_u8(b64_alphabet_ptr, (t3 >> 12) & 0x3F))
      raw_store_u8(b64_output_ptr, b64_j + 14, raw_load_u8(b64_alphabet_ptr, (t3 >> 6) & 0x3F))
      raw_store_u8(b64_output_ptr, b64_j + 15, raw_load_u8(b64_alphabet_ptr, t3 & 0x3F))
      b64_i += 12
      b64_j += 16
    while b64_i + 3 <= b64_n
      b64_triple = (raw_load_u8(b64_input_ptr, b64_i) << 16) | (raw_load_u8(b64_input_ptr, b64_i + 1) << 8) | raw_load_u8(b64_input_ptr, b64_i + 2) ## i64
      raw_store_u8(b64_output_ptr, b64_j, raw_load_u8(b64_alphabet_ptr, (b64_triple >> 18) & 0x3F))
      raw_store_u8(b64_output_ptr, b64_j + 1, raw_load_u8(b64_alphabet_ptr, (b64_triple >> 12) & 0x3F))
      raw_store_u8(b64_output_ptr, b64_j + 2, raw_load_u8(b64_alphabet_ptr, (b64_triple >> 6) & 0x3F))
      raw_store_u8(b64_output_ptr, b64_j + 3, raw_load_u8(b64_alphabet_ptr, b64_triple & 0x3F))
      b64_i += 3
      b64_j += 4
    if b64_i < b64_n
      b64_triple = raw_load_u8(b64_input_ptr, b64_i) << 16 ## i64
      if b64_i + 1 < b64_n
        b64_triple = b64_triple | (raw_load_u8(b64_input_ptr, b64_i + 1) << 8)
      raw_store_u8(b64_output_ptr, b64_j, raw_load_u8(b64_alphabet_ptr, (b64_triple >> 18) & 0x3F))
      raw_store_u8(b64_output_ptr, b64_j + 1, raw_load_u8(b64_alphabet_ptr, (b64_triple >> 12) & 0x3F))
      if b64_i + 1 < b64_n
        raw_store_u8(b64_output_ptr, b64_j + 2, raw_load_u8(b64_alphabet_ptr, (b64_triple >> 6) & 0x3F))
      elsif padded
        raw_store_u8(b64_output_ptr, b64_j + 2, 61)
      if padded
        raw_store_u8(b64_output_ptr, b64_j + 3, 61)

    ccall("w_string_from_byte_array", b64_output)

  -> .__decode(text, url_safe)
    return ccall("w_string_take_byte_array", text, url_safe ? -13 : -12)
    # Decode deliberately accepts String only, matching the historical API.
    b64_input = ccall("w_base64_decode_input", text) ## u8[]
    b64_dec = Base64.__dec_table(url_safe) ## u8[]
    b64_n = b64_input.size ## i64

    # Both variants accept optional trailing padding. Padding anywhere else is
    # rejected by __decode_digit, exactly like the former runtime codec.
    while b64_n > 0 && b64_input[b64_n - 1] == 61
      b64_n -= 1

    b64_out_n = b64_n * 3 / 4 ## i64
    b64_output = u8[b64_out_n]
    b64_input_ptr = ccall_nobox("w_u8_live_data_ptr", b64_input) ## i64
    b64_dec_ptr = ccall_nobox("w_u8_live_data_ptr", b64_dec) ## i64
    b64_output_ptr = ccall_nobox("w_u8_live_data_ptr", b64_output) ## i64
    b64_i = 0 ## i64
    b64_j = 0 ## i64
    while b64_i + 16 <= b64_n
      a0 = raw_load_u8(b64_dec_ptr, raw_load_u8(b64_input_ptr, b64_i)) ## i64
      b0 = raw_load_u8(b64_dec_ptr, raw_load_u8(b64_input_ptr, b64_i + 1)) ## i64
      c0 = raw_load_u8(b64_dec_ptr, raw_load_u8(b64_input_ptr, b64_i + 2)) ## i64
      d0 = raw_load_u8(b64_dec_ptr, raw_load_u8(b64_input_ptr, b64_i + 3)) ## i64
      a1 = raw_load_u8(b64_dec_ptr, raw_load_u8(b64_input_ptr, b64_i + 4)) ## i64
      b1 = raw_load_u8(b64_dec_ptr, raw_load_u8(b64_input_ptr, b64_i + 5)) ## i64
      c1 = raw_load_u8(b64_dec_ptr, raw_load_u8(b64_input_ptr, b64_i + 6)) ## i64
      d1 = raw_load_u8(b64_dec_ptr, raw_load_u8(b64_input_ptr, b64_i + 7)) ## i64
      a2 = raw_load_u8(b64_dec_ptr, raw_load_u8(b64_input_ptr, b64_i + 8)) ## i64
      b2 = raw_load_u8(b64_dec_ptr, raw_load_u8(b64_input_ptr, b64_i + 9)) ## i64
      c2 = raw_load_u8(b64_dec_ptr, raw_load_u8(b64_input_ptr, b64_i + 10)) ## i64
      d2 = raw_load_u8(b64_dec_ptr, raw_load_u8(b64_input_ptr, b64_i + 11)) ## i64
      a3 = raw_load_u8(b64_dec_ptr, raw_load_u8(b64_input_ptr, b64_i + 12)) ## i64
      b3 = raw_load_u8(b64_dec_ptr, raw_load_u8(b64_input_ptr, b64_i + 13)) ## i64
      c3 = raw_load_u8(b64_dec_ptr, raw_load_u8(b64_input_ptr, b64_i + 14)) ## i64
      d3 = raw_load_u8(b64_dec_ptr, raw_load_u8(b64_input_ptr, b64_i + 15)) ## i64
      if ((a0 | b0 | c0 | d0 | a1 | b1 | c1 | d1 | a2 | b2 | c2 | d2 | a3 | b3 | c3 | d3) & 0xC0) != 0
        message = url_safe ? "base64url: invalid character" : "base64: invalid character"
        raise message
      t0 = (a0 << 18) | (b0 << 12) | (c0 << 6) | d0 ## i64
      t1 = (a1 << 18) | (b1 << 12) | (c1 << 6) | d1 ## i64
      t2 = (a2 << 18) | (b2 << 12) | (c2 << 6) | d2 ## i64
      t3 = (a3 << 18) | (b3 << 12) | (c3 << 6) | d3 ## i64
      raw_store_u8(b64_output_ptr, b64_j, (t0 >> 16) & 0xFF)
      raw_store_u8(b64_output_ptr, b64_j + 1, (t0 >> 8) & 0xFF)
      raw_store_u8(b64_output_ptr, b64_j + 2, t0 & 0xFF)
      raw_store_u8(b64_output_ptr, b64_j + 3, (t1 >> 16) & 0xFF)
      raw_store_u8(b64_output_ptr, b64_j + 4, (t1 >> 8) & 0xFF)
      raw_store_u8(b64_output_ptr, b64_j + 5, t1 & 0xFF)
      raw_store_u8(b64_output_ptr, b64_j + 6, (t2 >> 16) & 0xFF)
      raw_store_u8(b64_output_ptr, b64_j + 7, (t2 >> 8) & 0xFF)
      raw_store_u8(b64_output_ptr, b64_j + 8, t2 & 0xFF)
      raw_store_u8(b64_output_ptr, b64_j + 9, (t3 >> 16) & 0xFF)
      raw_store_u8(b64_output_ptr, b64_j + 10, (t3 >> 8) & 0xFF)
      raw_store_u8(b64_output_ptr, b64_j + 11, t3 & 0xFF)
      b64_i += 16
      b64_j += 12
    while b64_i + 4 <= b64_n
      b64_a = raw_load_u8(b64_dec_ptr, raw_load_u8(b64_input_ptr, b64_i)) ## i64
      b64_b = raw_load_u8(b64_dec_ptr, raw_load_u8(b64_input_ptr, b64_i + 1)) ## i64
      b64_c = raw_load_u8(b64_dec_ptr, raw_load_u8(b64_input_ptr, b64_i + 2)) ## i64
      b64_d = raw_load_u8(b64_dec_ptr, raw_load_u8(b64_input_ptr, b64_i + 3)) ## i64
      if ((b64_a | b64_b | b64_c | b64_d) & 0xC0) != 0
        message = url_safe ? "base64url: invalid character" : "base64: invalid character"
        raise message
      b64_triple = (b64_a << 18) | (b64_b << 12) | (b64_c << 6) | b64_d ## i64
      raw_store_u8(b64_output_ptr, b64_j, (b64_triple >> 16) & 0xFF)
      raw_store_u8(b64_output_ptr, b64_j + 1, (b64_triple >> 8) & 0xFF)
      raw_store_u8(b64_output_ptr, b64_j + 2, b64_triple & 0xFF)
      b64_i += 4
      b64_j += 3
    if b64_i < b64_n
      b64_a = raw_load_u8(b64_dec_ptr, raw_load_u8(b64_input_ptr, b64_i)) ## i64
      b64_b = (b64_i + 1 < b64_n ? raw_load_u8(b64_dec_ptr, raw_load_u8(b64_input_ptr, b64_i + 1)) : 0) ## i64
      b64_c = (b64_i + 2 < b64_n ? raw_load_u8(b64_dec_ptr, raw_load_u8(b64_input_ptr, b64_i + 2)) : 0) ## i64
      if ((b64_a | b64_b | b64_c) & 0xC0) != 0
        message = url_safe ? "base64url: invalid character" : "base64: invalid character"
        raise message
      b64_triple = (b64_a << 18) | (b64_b << 12) | (b64_c << 6) ## i64
      if b64_j < b64_out_n
        raw_store_u8(b64_output_ptr, b64_j, (b64_triple >> 16) & 0xFF)
        b64_j += 1
      if b64_j < b64_out_n
        raw_store_u8(b64_output_ptr, b64_j, (b64_triple >> 8) & 0xFF)
        b64_j += 1
      if b64_j < b64_out_n
        raw_store_u8(b64_output_ptr, b64_j, b64_triple & 0xFF)

    b64_output

  -> .encode(data)
    Base64.__encode(data, false, true)

  -> .decode(text)
    Base64.__decode(text, false)

  -> .url_encode(data)
    Base64.__encode(data, true, false)

  -> .url_decode(text)
    Base64.__decode(text, true)

# Legacy global spellings are real Tungsten functions. The loader autoloads
# this file when it sees any of these calls, so compiled code no longer jumps
# around the source implementation to a C codec.
-> base64_encode(data)
  Base64.encode(data)

-> base64_decode(text)
  Base64.decode(text)

-> base64url_encode(data)
  Base64.url_encode(data)

-> base64url_decode(text)
  Base64.url_decode(text)
