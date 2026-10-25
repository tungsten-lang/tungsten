# tungsten-json: high-throughput JSON parser.
#
# Conforms to the JSON contract defined in core/json.w. When this
# bit is loaded, its `+ JSON` block overrides the recursive-descent
# `JSON.parse` with a 16-byte NEON SIMD classifier + offset-stream
# walker. Same return type, same value tree — callers don't change.
#
# How it works:
#
#   1. The SIMD classifier (`w_json_simd_classify` in
#      runtime/json_simd.c) processes 64 source bytes per iteration
#      via NEON, producing an `i32[]` offset stream — one offset per
#      structural character (`{ } [ ] , :`) and one per opening
#      string quote `"`.
#
#   2. `walk_simd_value` consumes the offset stream to drive tree
#      construction. Object/array structural traversal jumps directly
#      between structural characters instead of char-by-char. String
#      contents and numeric/keyword literals fall through to
#      `parse_string` / `parse_number` / `skip_ws` from core/json.w
#      (loaded via `use core/json` below), which handle escapes,
#      scientific notation, and whitespace correctly.
#
# Why hybrid: the classifier finds structural positions fast but
# can't decode string escapes or parse numeric formats — those
# still need char-level work. The walker uses offsets where they
# help (outer loop structure, whitespace skipping) and the existing
# core helpers where they don't (inner content extraction).
#
# State carried through recursive calls:
#   :idx     — next token index in `tokens` to consume
#   :n_off   — total tokens emitted by the classifier
#   :pos     — current source byte position (drives scalar fallback)
#   :tokens  — i32[] offset array (positions of structural chars)
#
# Per-token consumption: when the walker handles a structural char
# at `tokens[idx]`, it advances `idx += 1` and sets `pos` to one
# past the structural's byte position. For scalars (numbers,
# true/false/null) that don't generate tokens, the walker falls
# back to `skip_ws` + `parse_number` / keyword-skip from `pos`.

use core/json

+ JSON
  -> .parse(s_in)
    s = s_in ## String
    view = ccall("w_string_bytes_view", s) ## u8[]
    n = view.size ## i64
    pbox = [0]
    if n < 128
      return parse_fast_value_b(s, view, n, 0, pbox)
    tokens = i32[n + 1]
    src_ptr = ccall_nobox("w_string_byte_ptr", s)
    src_len = ccall_nobox("w_string_byte_length", s)
    out_ptr = ccall_nobox("w_array_data_ptr", tokens)
    n_off = ccall_nobox("w_json_simd_classify", src_ptr, src_len, out_ptr)
    st = i64[3]
    st[0] = 0
    st[1] = n_off
    st[2] = 0
    walk_simd_value(s, view, n, tokens, st, pbox)

  -> .parse_fast_value_b(s_in, view_in, n_in, pos_in, pbox)
    s = s_in ## String
    view = view_in ## u8[]
    n = n_in ## i64
    pos = skip_ws_b(view, n, pos_in) ## i64
    if pos >= n
      raise "JSON.parse: unexpected end of input"
    b = view[pos]
    if b == 34
      return parse_string_b(s, view, n, pos, pbox)
    if b == 123
      return parse_fast_object_b(s, view, n, pos, pbox)
    if b == 91
      return parse_fast_array_b(s, view, n, pos, pbox)
    parse_scalar_b(s, view, n, pos, pbox)

  -> .parse_fast_object_b(s_in, view_in, n_in, pos_in, pbox)
    s = s_in ## String
    view = view_in ## u8[]
    n = n_in ## i64
    pos = (pos_in + 1) ## i64
    result = {}
    pos = skip_ws_b(view, n, pos) ## i64
    if pos >= n
      raise "JSON.parse: unterminated object"
    if view[pos] == 125
      pbox[0] = pos + 1
      return result
    while true
      pos = skip_ws_b(view, n, pos) ## i64
      if pos >= n || view[pos] != 34
        raise "JSON.parse: expected a string key in object at byte " + pos.to_s
      key = parse_string_b(s, view, n, pos, pbox)
      pos = pbox[0] ## i64
      pos = skip_ws_b(view, n, pos) ## i64
      if pos >= n || view[pos] != 58
        raise "JSON.parse: expected ':' in object at byte " + pos.to_s
      pos += 1
      val = parse_fast_value_b(s, view, n, pos, pbox)
      result[key] = val
      pos = pbox[0] ## i64
      pos = skip_ws_b(view, n, pos) ## i64
      if pos >= n
        raise "JSON.parse: unterminated object"
      if view[pos] == 125
        pbox[0] = pos + 1
        return result
      if view[pos] != 44
        raise "JSON.parse: expected ',' or '}' in object at byte " + pos.to_s
      pos += 1
    result

  -> .parse_fast_array_b(s_in, view_in, n_in, pos_in, pbox)
    s = s_in ## String
    view = view_in ## u8[]
    n = n_in ## i64
    pos = (pos_in + 1) ## i64
    result = []
    pos = skip_ws_b(view, n, pos) ## i64
    if pos >= n
      raise "JSON.parse: unterminated array"
    if view[pos] == 93
      pbox[0] = pos + 1
      return result
    while true
      val = parse_fast_value_b(s, view, n, pos, pbox)
      result.push(val)
      pos = pbox[0] ## i64
      pos = skip_ws_b(view, n, pos) ## i64
      if pos >= n
        raise "JSON.parse: unterminated array"
      if view[pos] == 93
        pbox[0] = pos + 1
        return result
      if view[pos] != 44
        raise "JSON.parse: expected ',' or ']' in array at byte " + pos.to_s
      pos += 1
    result

  -> .parse_scalar_b(s_in, view_in, n_in, pos_in, pbox)
    s = s_in ## String
    view = view_in ## u8[]
    n = n_in ## i64
    pos = pos_in ## i64
    while pos < n
      b = view[pos]
      break if b != 32 && b != 9 && b != 10 && b != 13
      pos += 1
    if pos >= n
      raise "JSON.parse: unexpected end of input"
    b = view[pos]
    if b == 116
      pbox[0] = pos + 4
      return true
    if b == 102
      pbox[0] = pos + 5
      return false
    if b == 110
      pbox[0] = pos + 4
      return nil
    start = pos
    neg = false
    if b == 45
      neg = true
      pos += 1
    first_digit = pos
    int_val = 0 ## i64
    while pos < n
      d = view[pos]
      break if d < 48 || d > 57
      int_val = int_val * 10 + (d - 48)
      pos += 1
    if pos == first_digit
      raise "JSON.parse: unexpected byte at " + start.to_s
    is_float = false
    if pos < n && view[pos] == 46
      is_float = true
      pos += 1
      while pos < n && view[pos] >= 48 && view[pos] <= 57
        pos += 1
    if pos < n && (view[pos] == 101 || view[pos] == 69)
      is_float = true
      pos += 1
      if pos < n && (view[pos] == 43 || view[pos] == 45)
        pos += 1
      exp_digit = pos
      while pos < n && view[pos] >= 48 && view[pos] <= 57
        pos += 1
      if pos == exp_digit
        raise "JSON.parse: malformed exponent at byte " + start.to_s
    pbox[0] = pos
    if is_float
      return s.slice(start, pos - start).to_f
    if pos - first_digit <= 18
      return neg ? 0 - int_val : int_val
    s.slice(start, pos - start).to_i

  -> .walk_simd_value(s_in, view_in, n_in, tokens_in, st_in, pbox)
    s = s_in ## String
    view = view_in ## u8[]
    n = n_in ## i64
    tokens = tokens_in ## i32[]
    st = st_in ## i64[]
    idx = st[0] ## i64
    n_off = st[1] ## i64

    if idx < n_off
      next_struct = tokens[idx] ## i64
      if next_struct < n
        b = view[next_struct]
        if b == 34
          st[0] = idx + 1
          val = parse_string_b(s, view, n, next_struct, pbox)
          st[2] = pbox[0] ## i64
          return val
        if b == 123
          st[0] = idx + 1
          st[2] = next_struct + 1
          return walk_simd_object(s, view, n, tokens, st, pbox)
        if b == 91
          st[0] = idx + 1
          st[2] = next_struct + 1
          return walk_simd_array(s, view, n, tokens, st, pbox)

    val = parse_scalar_b(s, view, n, st[2], pbox)
    st[2] = pbox[0] ## i64
    val

  -> .walk_simd_object(s_in, view_in, n_in, tokens_in, st_in, pbox)
    s = s_in ## String
    view = view_in ## u8[]
    n = n_in ## i64
    tokens = tokens_in ## i32[]
    st = st_in ## i64[]
    result = {}

    idx = st[0] ## i64
    n_off = st[1] ## i64
    if idx < n_off
      first_pos = tokens[idx] ## i64
      if first_pos < n && view[first_pos] == 125
        st[0] = idx + 1
        st[2] = first_pos + 1
        return result

    while true
      idx = st[0] ## i64
      if idx >= n_off
        break
      key_pos = tokens[idx] ## i64
      st[0] = idx + 1
      key = parse_string_b(s, view, n, key_pos, pbox)

      colon_idx = st[0] ## i64
      if colon_idx < n_off
        colon_pos = tokens[colon_idx] ## i64
        st[0] = colon_idx + 1
        st[2] = colon_pos + 1

      val = walk_simd_value(s, view, n, tokens, st, pbox)
      result[key] = val

      sep_idx = st[0] ## i64
      if sep_idx >= n_off
        break
      sep_pos = tokens[sep_idx] ## i64
      if sep_pos >= n
        break
      sep_b = view[sep_pos]
      if sep_b == 125
        st[0] = sep_idx + 1
        st[2] = sep_pos + 1
        return result
      if sep_b == 44
        st[0] = sep_idx + 1
        st[2] = sep_pos + 1
      else
        break
    result

  -> .walk_simd_array(s_in, view_in, n_in, tokens_in, st_in, pbox)
    s = s_in ## String
    view = view_in ## u8[]
    n = n_in ## i64
    tokens = tokens_in ## i32[]
    st = st_in ## i64[]
    result = []

    idx = st[0] ## i64
    n_off = st[1] ## i64
    if idx < n_off
      first_pos = tokens[idx] ## i64
      if first_pos < n && view[first_pos] == 93
        nxt = skip_ws_b(view, n, st[2]) ## i64
        if nxt == first_pos
          st[0] = idx + 1
          st[2] = first_pos + 1
          return result

    while true
      val = walk_simd_value(s, view, n, tokens, st, pbox)
      result.push(val)

      sep_idx = st[0] ## i64
      if sep_idx >= n_off
        break
      sep_pos = tokens[sep_idx] ## i64
      if sep_pos >= n
        break
      sep_b = view[sep_pos]
      if sep_b == 93
        st[0] = sep_idx + 1
        st[2] = sep_pos + 1
        return result
      if sep_b == 44
        st[0] = sep_idx + 1
        st[2] = sep_pos + 1
      else
        break
    result
