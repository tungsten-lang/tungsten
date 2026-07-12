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

  -> .__encode(data, url_safe, padded)
    # Strings become a borrowed byte view; u8[] inputs are returned unchanged.
    # The view uses the String's stored byte count, so embedded NUL is data.
    b64_input = ccall("w_base64_encode_input", data) ## u8[]
    alphabet = url_safe ? "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_" : "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    b64_alphabet = ccall("w_base64_decode_input", alphabet) ## u8[]
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
    while b64_i < b64_n
      b64_triple = raw_load_u8(b64_input_ptr, b64_i) << 16 ## i64
      if b64_i + 1 < b64_n
        b64_triple = b64_triple | (raw_load_u8(b64_input_ptr, b64_i + 1) << 8)
      if b64_i + 2 < b64_n
        b64_triple = b64_triple | raw_load_u8(b64_input_ptr, b64_i + 2)

      raw_store_u8(b64_output_ptr, b64_j, raw_load_u8(b64_alphabet_ptr, (b64_triple >> 18) & 0x3F))
      raw_store_u8(b64_output_ptr, b64_j + 1, raw_load_u8(b64_alphabet_ptr, (b64_triple >> 12) & 0x3F))
      if b64_i + 1 < b64_n
        raw_store_u8(b64_output_ptr, b64_j + 2, raw_load_u8(b64_alphabet_ptr, (b64_triple >> 6) & 0x3F))
      elsif padded
        raw_store_u8(b64_output_ptr, b64_j + 2, 61)
      if b64_i + 2 < b64_n
        raw_store_u8(b64_output_ptr, b64_j + 3, raw_load_u8(b64_alphabet_ptr, b64_triple & 0x3F))
      elsif padded
        raw_store_u8(b64_output_ptr, b64_j + 3, 61)

      b64_i += 3
      b64_j += 4

    ccall("w_string_from_byte_array", b64_output)

  -> .__decode(text, url_safe)
    # Decode deliberately accepts String only, matching the historical API.
    b64_input = ccall("w_base64_decode_input", text) ## u8[]
    b64_n = b64_input.size ## i64

    # Both variants accept optional trailing padding. Padding anywhere else is
    # rejected by __decode_digit, exactly like the former runtime codec.
    while b64_n > 0 && b64_input[b64_n - 1] == 61
      b64_n -= 1

    b64_out_n = b64_n * 3 / 4 ## i64
    b64_output = u8[b64_out_n]
    b64_input_ptr = ccall_nobox("w_u8_live_data_ptr", b64_input) ## i64
    b64_output_ptr = ccall_nobox("w_u8_live_data_ptr", b64_output) ## i64
    b64_i = 0 ## i64
    b64_j = 0 ## i64
    while b64_i < b64_n
      b64_a = Base64.__decode_digit(raw_load_u8(b64_input_ptr, b64_i), url_safe) ## i64
      b64_b = (b64_i + 1 < b64_n ? Base64.__decode_digit(raw_load_u8(b64_input_ptr, b64_i + 1), url_safe) : 0) ## i64
      b64_c = (b64_i + 2 < b64_n ? Base64.__decode_digit(raw_load_u8(b64_input_ptr, b64_i + 2), url_safe) : 0) ## i64
      b64_d = (b64_i + 3 < b64_n ? Base64.__decode_digit(raw_load_u8(b64_input_ptr, b64_i + 3), url_safe) : 0) ## i64

      if b64_a < 0 || b64_b < 0 || b64_c < 0 || b64_d < 0
        message = url_safe ? "base64url: invalid character" : "base64: invalid character"
        raise message

      b64_triple = (b64_a << 18) | (b64_b << 12) | (b64_c << 6) | b64_d ## i64
      if b64_j < b64_out_n
        raw_store_u8(b64_output_ptr, b64_j, (b64_triple >> 16) & 0xFF)
        b64_j += 1
      if b64_j < b64_out_n
        raw_store_u8(b64_output_ptr, b64_j, (b64_triple >> 8) & 0xFF)
        b64_j += 1
      if b64_j < b64_out_n
        raw_store_u8(b64_output_ptr, b64_j, b64_triple & 0xFF)
        b64_j += 1
      b64_i += 4

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
