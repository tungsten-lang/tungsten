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

in Tungsten

+ JSON
  -> .parse(s)
    n = s.size
    tokens = i32[n]
    # Phase 0.1 fix (compiler/lib/lowering.w) makes ccall_nobox
    # results survive local-variable stores without being NaN-box
    # re-tagged. We use that here to capture the classifier's
    # return value (the offset count) and reuse the source ptr/len
    # locals — patterns that were unsafe before Phase 0.1 landed.
    src_ptr = ccall_nobox("w_string_byte_ptr", s)
    src_len = ccall_nobox("w_string_byte_length", s)
    out_ptr = ccall_nobox("w_array_data_ptr", tokens)
    n_off = ccall_nobox("w_json_simd_classify", src_ptr, src_len, out_ptr)
    state = {idx: 0, n_off: n_off, pos: 0, tokens: tokens, chars: s.chars}
    walk_simd_value(s, state)

  -> .walk_simd_value(s, state)
    idx = state[:idx]
    n_off = state[:n_off]
    chars = state[:chars]

    # Fast path: if there's a structural token ahead, peek its char.
    # `{`, `[`, `"` are value-starters → descend / parse string.
    # `,`, `:`, `}`, `]` mean the value is a scalar between the
    # current pos and that structural — fall through to skip_ws +
    # parse_number / keyword.
    if idx < n_off
      tokens = state[:tokens]
      next_struct = tokens[idx]
      if next_struct < chars.size
        ch = chars[next_struct]
        if ch == "{"
          state[:idx] = idx + 1
          state[:pos] = next_struct + 1
          return walk_simd_object(s, state)
        if ch == "\["
          state[:idx] = idx + 1
          state[:pos] = next_struct + 1
          return walk_simd_array(s, state)
        if ch == "\""
          state[:idx] = idx + 1
          result = parse_string_chars(chars, next_struct)
          state[:pos] = result[1]
          return result[0]

    # Scalar (number / keyword) fallback. Skip whitespace from the
    # current source position. We can't use offset jumps here
    # because scalars don't generate structural tokens.
    pos = skip_ws_chars(chars, state[:pos])
    if pos >= chars.size
      return nil
    ch = chars[pos]
    if ch == "t"
      state[:pos] = pos + 4
      return true
    if ch == "f"
      state[:pos] = pos + 5
      return false
    if ch == "n"
      state[:pos] = pos + 4
      return nil
    # Number
    result = parse_number_chars(s, chars, pos)
    state[:pos] = result[1]
    return result[0]

  -> .walk_simd_object(s, state)
    # Caller has consumed `{` and set idx/pos past it.
    chars = state[:chars]
    tokens = state[:tokens]
    result = {}

    # Check for empty object: next non-whitespace from pos must be `}`.
    # Can't just check the next token — for nested structures, the next
    # token could be a `}` from an OUTER object's content (e.g., parsing
    # the inner `{}` of `{"a":{}}` — after consuming inner `{`, pos is
    # past it, and the next non-ws char IS `}`).
    idx = state[:idx]
    n_off = state[:n_off]
    nxt = skip_ws_chars(chars, state[:pos])
    if nxt < chars.size && chars[nxt] == "}"
      # Find the `}` token (must be at position `nxt`) and consume it.
      if idx < n_off && tokens[idx] == nxt
        state[:idx] = idx + 1
      state[:pos] = nxt + 1
      return result

    while true
      # Key: must be a string. The next structural token should be
      # the opening `"` of the key. walk_simd_value handles the
      # string parse and advances state.
      key = walk_simd_value(s, state)

      # Colon: next structural should be `:`.
      colon_idx = state[:idx]
      if colon_idx < state[:n_off]
        colon_pos = tokens[colon_idx]
        if colon_pos < chars.size && chars[colon_pos] == ":"
          state[:idx] = colon_idx + 1
          state[:pos] = colon_pos + 1

      # Value: recursive walk advances state past the value's
      # structural tokens (and pos past any trailing scalar).
      val = walk_simd_value(s, state)
      result[key] = val

      # Separator: `,` to continue, `}` to close.
      sep_idx = state[:idx]
      if sep_idx >= state[:n_off]
        break
      sep_pos = tokens[sep_idx]
      if sep_pos >= chars.size
        break
      sep_ch = chars[sep_pos]
      if sep_ch == "}"
        state[:idx] = sep_idx + 1
        state[:pos] = sep_pos + 1
        return result
      if sep_ch == ","
        state[:idx] = sep_idx + 1
        state[:pos] = sep_pos + 1
      else
        break
    result

  -> .walk_simd_array(s, state)
    # Caller has consumed `[` and set idx/pos past it.
    chars = state[:chars]
    tokens = state[:tokens]
    result = []

    # Check for empty array: next non-whitespace from pos must be `]`.
    # (Same reasoning as walk_simd_object — the next token alone isn't
    # sufficient because scalars don't generate tokens, so `[3]` would
    # otherwise be misread as empty when the next token is the closing
    # `]` and the `3` content is between pos and that `]`.)
    idx = state[:idx]
    n_off = state[:n_off]
    nxt = skip_ws_chars(chars, state[:pos])
    if nxt < chars.size && chars[nxt] == "\]"
      if idx < n_off && tokens[idx] == nxt
        state[:idx] = idx + 1
      state[:pos] = nxt + 1
      return result

    while true
      val = walk_simd_value(s, state)
      result.push(val)

      sep_idx = state[:idx]
      if sep_idx >= state[:n_off]
        break
      sep_pos = tokens[sep_idx]
      if sep_pos >= chars.size
        break
      sep_ch = chars[sep_pos]
      if sep_ch == "\]"
        state[:idx] = sep_idx + 1
        state[:pos] = sep_pos + 1
        return result
      if sep_ch == ","
        state[:idx] = sep_idx + 1
        state[:pos] = sep_pos + 1
      else
        break
    result
