# C Lexer Profiling — token and operator frequency analysis
#
# Scans a token array produced by c_tokenize_fast and reports:
# - Token type frequency (optimal branch order)
# - Operator breakdown by starting character
# - Compound operator breakdown (->  ==  &&  etc.)

# Profile token type frequencies from a c_tokenize_fast output array.
# Returns an array of [type_id, count, name] sorted by frequency (descending).
# Use this to determine optimal branch ordering in the hot loop.
## i64: i, tc, tval, ttype
## i64[]: tokens
fn c_token_profile(tokens, tc)
  # Count array: index = type ID (0-14)
  counts = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  names = ["EOF", "IDENT", "KEYWORD", "INT", "FLOAT", "STRING", "CHAR", "OP", "PREPROC", "COMMENT", "WS", "NL", "HEADER", "ERROR", "PPNUM"]

  i = 0
  while i < tc
    tval = tokens[i]
    ttype = (tval >> 38) & 15    # type is in bits 38-41
    if ttype >= 0 && ttype < 15
      counts[ttype] = counts[ttype].to_i + 1
    i += 1

  # Sort indices by count (descending)
  order = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]
  j = 0
  while j < 15
    max_idx = j
    k = j + 1
    while k < 12
      if counts[order[k]] > counts[order[max_idx]]
        max_idx = k
      k += 1
    if max_idx != j
      tmp = order[j]
      order[j] = order[max_idx]
      order[max_idx] = tmp
    j += 1

  # Sum all counts for accurate total
  total_tokens = 0
  j = 0
  while j < 15
    total_tokens = total_tokens + counts[j].to_i
    j += 1

  << ""
  << "  Token frequency (optimal branch order):"
  << "  ─────────────────────────────────────────"
  j = 0
  while j < 15
    idx = order[j]
    cnt = counts[idx].to_i
    if cnt > 0
      pct = cnt * 1000 / total_tokens   # permille for 1 decimal
      pct_whole = pct / 10
      pct_frac = pct - (pct_whole * 10)
      << "    [j + 1]. [names[idx]]  [cnt]  ([pct_whole].[pct_frac]%)"
    j += 1
  << "  ─────────────────────────────────────────"
  << "  total: [total_tokens] tokens"
  << ""

  order

# Profile operator sub-types by starting character.
# Reads the LexChar at each OP token's offset to categorize operators.
## i64: i, tc, tval, ttype, offset, op_lc, cp, op_total
## i64[]: tokens, lc
fn c_operator_profile(tokens, tc, lc)
  # Count by starting codepoint — flat array for printable ASCII (32..126)
  op_counts = []
  i = 0
  while i < 95
    op_counts.push(0)
    i += 1

  op_total = 0
  i = 0
  while i < tc
    tval = tokens[i]
    ttype = (tval >> 38) & 15
    if ttype == 7                                      # T_OP
      offset = tval & 16777215                         # lower 24 bits = offset
      op_lc = lc[offset]
      cp = (op_lc >> 18) & 2097151
      if cp >= 32 && cp < 127
        op_counts[cp - 32] = op_counts[cp - 32].to_i + 1
        op_total += 1
    i += 1

  # Sort by count (descending)
  idx_order = []
  i = 0
  while i < 95
    idx_order.push(i)
    i += 1

  j = 0
  while j < 95
    max_idx = j
    k = j + 1
    while k < 95
      if op_counts[idx_order[k]].to_i > op_counts[idx_order[max_idx]].to_i
        max_idx = k
      k += 1
    if max_idx != j
      tmp = idx_order[j]
      idx_order[j] = idx_order[max_idx]
      idx_order[max_idx] = tmp
    j += 1

  << ""
  << "  Operator breakdown (by starting char):"
  << "  ─────────────────────────────────────────"
  j = 0
  while j < 95
    idx = idx_order[j]
    cnt = op_counts[idx].to_i
    if cnt > 0
      cp = idx + 32
      ch = cp.chr()
      pct = cnt * 1000 / op_total
      pct_whole = pct / 10
      pct_frac = pct - (pct_whole * 10)
      << "    [ch]  [cnt]  ([pct_whole].[pct_frac]%)"
    j += 1
  << "  ─────────────────────────────────────────"
  << "  total operators: [op_total]"

  # Compound operator breakdown: reconstruct each multi-char op from lc array
  compound_names = ["==", "--", "-=", "->", "*=", "&&", "&=", "!=", "++", "+=", "||", "|=", "<<", "<=", ">>", ">=", "<<=", ">>=", "...", "^=", "/=", "%=", "##"]
  compound_counts = []
  ci = 0
  while ci < 23
    compound_counts.push(0)
    ci += 1
  single_count = 0

  i = 0
  while i < tc
    tval = tokens[i]
    ttype = (tval >> 38) & 15
    if ttype == 7
      len = (tval >> 24) & 0x3FFF
      offset = tval & 0xFFFFFF
      if len == 1
        single_count = single_count + 1
      elsif len >= 2
        c1 = (lc[offset] >> 18) & 0x1FFFFF
        c2 = (lc[offset + 1] >> 18) & 0x1FFFFF
        # Map to compound index
        idx = -1
        if c1 == 0x3D && c2 == 0x3D      # ==
          idx = 0
        elsif c1 == 0x2D && c2 == 0x2D    # --
          idx = 1
        elsif c1 == 0x2D && c2 == 0x3D    # -=
          idx = 2
        elsif c1 == 0x2D && c2 == 0x3E    # ->
          idx = 3
        elsif c1 == 0x2A && c2 == 0x3D    # *=
          idx = 4
        elsif c1 == 0x26 && c2 == 0x26    # &&
          idx = 5
        elsif c1 == 0x26 && c2 == 0x3D    # &=
          idx = 6
        elsif c1 == 0x21 && c2 == 0x3D    # !=
          idx = 7
        elsif c1 == 0x2B && c2 == 0x2B    # ++
          idx = 8
        elsif c1 == 0x2B && c2 == 0x3D    # +=
          idx = 9
        elsif c1 == 0x7C && c2 == 0x7C    # ||
          idx = 10
        elsif c1 == 0x7C && c2 == 0x3D    # |=
          idx = 11
        elsif c1 == 0x3C && c2 == 0x3C    # << (or <<=)
          if len == 3
            idx = 16                       # <<=
          else
            idx = 12
        elsif c1 == 0x3C && c2 == 0x3D    # <=
          idx = 13
        elsif c1 == 0x3E && c2 == 0x3E    # >> (or >>=)
          if len == 3
            idx = 17                       # >>=
          else
            idx = 14
        elsif c1 == 0x3E && c2 == 0x3D    # >=
          idx = 15
        elsif c1 == 0x2E && c2 == 0x2E    # ...
          idx = 18
        elsif c1 == 0x5E && c2 == 0x3D    # ^=
          idx = 19
        elsif c1 == 0x2F && c2 == 0x3D    # /=
          idx = 20
        elsif c1 == 0x25 && c2 == 0x3D    # %=
          idx = 21
        elsif c1 == 0x23 && c2 == 0x23    # ##
          idx = 22
        if idx >= 0
          compound_counts[idx] = compound_counts[idx].to_i + 1
    i += 1

  # Sort compound ops by frequency
  comp_order = []
  ci = 0
  while ci < 23
    comp_order.push(ci)
    ci += 1
  j = 0
  while j < 23
    max_idx = j
    k = j + 1
    while k < 24
      if compound_counts[comp_order[k]].to_i > compound_counts[comp_order[max_idx]].to_i
        max_idx = k
      k += 1
    if max_idx != j
      tmp = comp_order[j]
      comp_order[j] = comp_order[max_idx]
      comp_order[max_idx] = tmp
    j += 1

  << ""
  << "  Compound operator breakdown:"
  << "  ─────────────────────────────────────────"
  << "    (single-char)  [single_count]"
  j = 0
  while j < 23
    idx = comp_order[j]
    cnt = compound_counts[idx].to_i
    if cnt > 0
      << "    [compound_names[idx]]   [cnt]"
    j += 1
  << "  ─────────────────────────────────────────"
  << ""
