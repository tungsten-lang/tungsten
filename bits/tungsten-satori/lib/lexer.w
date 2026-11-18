# Satori lexer: tokens plus layout.
#
# Physical lines are joined into logical lines while brackets are open, a
# line ends with an infix operator, `:`, `:=` or `,`, or the next line starts
# with an infix operator such as `=`, `→`, `∧`, `≤` or `:=`. Each logical line keeps
# the indentation of its first physical line; the parser builds blocks from
# indentation. `--` starts a comment.

+ Tok
  ro :kind, :text, :line, :col
  # kind: :id :num :dec :str :sym :kw
  -> new(@kind, @text, @line, @col)

  -> to_s
    @text

+ LLine
  ro :indent, :toks, :line
  -> new(@indent, @toks, @line)

SAT_KEYWORDS_LIST = ["opaque", "def", "theorem", "lemma", "example", "axiom", "inductive", "structure", "import",
   "fun", "λ", "if", "then", "else", "by", "have", "show", "calc", "let", "in",
   "instance", "notation", "variable", "open", "section", "end", "where", "at", "using", "with", "from", "match"]

SAT_SYMBOLS_LIST = ["<;>", "⊢", ":=", "=>", "->", "<->", "<=", ">=", "!=", "/\\", "\\/", "::", "++", "..",
   "→", "↔", "∧", "∨", "¬", "≠", "≤", "≥", "∀", "∃", "∈", "∉", "⊆", "∣", "×", "⟨", "⟩",
   "←", "·", "∘", "∑", "∏", "∪", "∩", "⁻¹", "√", "|",
   "(", ")", "\[", "\]", "{", "}", ",", ":", ";", "+", "-", "*", "/", "%", "^", "<", ">", "=", "!", "_", "@", "#", "."]

-> normalize_sym(s)
  case s
  when "->"
    "→"
  when "<->"
    "↔"
  when "<="
    "≤"
  when ">="
    "≥"
  when "!="
    "≠"
  when "/\\"
    "∧"
  when "\\/"
    "∨"
  else
    s

-> build_kw_set
  h = {}
  SAT_KEYWORDS_LIST.each -> (w)
    h[w] = true
  h

-> build_str_set(items)
  h = {}
  items.each -> (w)
    h[w] = true
  h

# Per-first-byte dispatch table: b0 -> [[bytes, byte_len, char_len, norm_text, is_lam_kw], ...]
-> build_sym_by_b0
  tbl = Array.new(256)
  i = 0
  while i < 256
    tbl[i] = []
    i += 1
  SAT_SYMBOLS_LIST.each -> (s)
    bytes = ccall("w_string_bytes_view", s) ## u8[]
    b0 = bytes[0]
    clen = s.chars.size
    tbl[b0].push([bytes, bytes.size, clen, normalize_sym(s), s == "λ"])
  tbl

SAT_KW_SET = build_kw_set()
SAT_SYM_BY_B0 = build_sym_by_b0()

SAT_CONT_AFTER = build_str_set(["→", "↔", "∧", "∨", ":=", ":", ",", "+", "-", "*", "/", "=", "<", ">", "≤", "≥", "≠", "∈", "=>", "::", "++", "^", "(", "\[", "{", "⟨", "×", "∣", "⊆"])
SAT_CONT_BEFORE = build_str_set(["=", "→", "↔", "∧", "∨", "≤", "≥", "<", ">", "≠", "∈", "*", "/", "++", "::", "∣", "⊆", "×", ":="])
SAT_HDR_KW = build_str_set(["theorem", "lemma", "axiom", "def", "opaque"])

-> sat_keywords
  SAT_KEYWORDS_LIST

-> sat_symbols
  SAT_SYMBOLS_LIST

-> utf8_len(b0)
  if b0 < 128
    return 1
  if b0 < 224
    return 2
  if b0 < 240
    return 3
  4

-> decode_cp(src, i, limit, bytes = nil)
  if bytes == nil
    bytes = ccall("w_string_bytes_view", src)
  b0 = bytes[i]
  if b0 < 128
    return b0
  if b0 < 224
    if i + 1 < limit
      return ((b0 & 31) << 6) | (bytes[i + 1] & 63)
    return b0
  if b0 < 240
    if i + 2 < limit
      return ((b0 & 15) << 12) | ((bytes[i + 1] & 63) << 6) | (bytes[i + 2] & 63)
    return b0
  if i + 3 < limit
    return ((b0 & 7) << 18) | ((bytes[i + 1] & 63) << 12) | ((bytes[i + 2] & 63) << 6) | (bytes[i + 3] & 63)
  b0

-> ident_start_cp?(o)
  if o < 128
    return (o >= 97 && o <= 122) || (o >= 65 && o <= 90) || o == 95
  if o >= 913 && o <= 1023
    return o != 955 && o != 931 && o != 928
  if o == 8469 || o == 8484 || o == 8474 || o == 8477 || o == 8450
    return true
  if o >= 8320 && o <= 8329
    return true
  if o >= 119808 && o <= 120831
    return true
  false

-> ident_char_cp?(o)
  if o < 128
    return (o >= 97 && o <= 122) || (o >= 65 && o <= 90) || (o >= 48 && o <= 57) || o == 95 || o == 39 || o == 33 || o == 63
  if ident_start_cp?(o)
    return true
  o >= 8304 && o <= 8329 && o != 8314 && o != 8315

-> digit_byte?(b)
  b >= 48 && b <= 57

# Lexes bytes [line_start, limit) of src for physical line `lineno`.
-> lex_line_bytes(src, line_start, limit, lineno, bytes = nil)
  if bytes == nil
    bytes = ccall("w_string_bytes_view", src)
  toks = []
  i = line_start
  col = 0
  while i < limit
    b = bytes[i]
    if b == 32 || b == 9
      i += 1
      col += 1
    else
      break
  indent = col
  while i < limit
    b = bytes[i]
    if b == 32 || b == 9 || b == 13
      i += 1
      col += 1
    elsif b == 45 && i + 1 < limit && bytes[i + 1] == 45
      i = limit
    elsif digit_byte?(b)
      j = i + 1
      has_us = false
      while j < limit
        bj = bytes[j]
        if digit_byte?(bj)
          j += 1
        elsif bj == 95
          has_us = true
          j += 1
        else
          break
      kind = :num
      if j + 1 < limit && bytes[j] == 46 && digit_byte?(bytes[j + 1])
        j += 2
        while j < limit && digit_byte?(bytes[j])
          j += 1
        kind = :dec
      num_txt = src.slice(i, j - i)
      if has_us
        num_txt = num_txt.gsub("_", "")
      toks.push(Tok.new(kind, num_txt, lineno, col))
      col += j - i
      i = j
    elsif b == 34
      j = i + 1
      scol = col + 1
      while j < limit && bytes[j] != 34
        step = utf8_len(bytes[j])
        j += step
        scol += 1
      toks.push(Tok.new(:str, src.slice(i + 1, j - i - 1), lineno, col))
      if j < limit
        i = j + 1
        col = scol + 1
      else
        i = j
        col = scol
    elsif (b < 128 && ((b >= 97 && b <= 122) || (b >= 65 && b <= 90) || b == 95)) || (b >= 128 && ident_start_cp?(decode_cp(src, i, limit, bytes)))
      j = i
      jcol = col
      while j < limit
        bj = bytes[j]
        if bj < 128
          if (bj >= 97 && bj <= 122) || (bj >= 65 && bj <= 90) || (bj >= 48 && bj <= 57) || bj == 95 || bj == 39 || bj == 33 || bj == 63
            j += 1
            jcol += 1
          elsif bj == 46 && j > i && j + 1 < limit
            bn = bytes[j + 1]
            ok_next = false
            if bn < 128
              ok_next = (bn >= 97 && bn <= 122) || (bn >= 65 && bn <= 90) || (bn >= 48 && bn <= 57) || bn == 95
            else
              ok_next = ident_start_cp?(decode_cp(src, j + 1, limit, bytes))
            if ok_next
              j += 1
              jcol += 1
            else
              break
          else
            break
        else
          cp = decode_cp(src, j, limit, bytes)
          if ident_char_cp?(cp)
            j += utf8_len(bj)
            jcol += 1
          else
            break
      w = src.slice(i, j - i)
      if SAT_KW_SET.has_key?(w)
        toks.push(Tok.new(:kw, w, lineno, col))
      else
        toks.push(Tok.new(:id, w, lineno, col))
      i = j
      col = jcol
    else
      cands = SAT_SYM_BY_B0[b]
      nc = cands.size
      ci = 0
      matched = nil
      while ci < nc
        ent = cands[ci]
        blen = ent[1]
        if i + blen <= limit
          sym_bytes = ent[0]
          ok = true
          k = 1
          while k < blen
            if bytes[i + k] != sym_bytes[k]
              ok = false
              break
            k += 1
          if ok
            matched = ent
            break
        ci += 1
      if matched == nil
        bad_len = utf8_len(b)
        if i + bad_len > limit
          bad_len = limit - i
        raise "lexer: unexpected character '" + src.slice(i, bad_len) + "' at line " + lineno.to_s
      if matched[4]
        toks.push(Tok.new(:kw, "fun", lineno, col))
      else
        toks.push(Tok.new(:sym, matched[3], lineno, col))
      i += matched[1]
      col += matched[2]
  [indent, toks]

-> continues_after?(t)
  if t.kind == :kw
    return t.text == "then" || t.text == "else" || t.text == "in"
  t.kind == :sym && SAT_CONT_AFTER.has_key?(t.text)

-> continues_before?(t)
  t.kind == :sym && SAT_CONT_BEFORE.has_key?(t.text)

-> line_continues_after?(toks)
  n = toks.size
  # A wildcard tactic location is complete; its star is not multiplication.
  if n >= 2 && toks[n - 2].text == "at" && toks[n - 1].text == "*"
    return false
  continues_after?(toks[n - 1])

-> header_start_tok?(indent, t)
  if indent != 0
    return false
  if t.kind == :sym
    return t.text == "+" || t.text == "→"
  t.kind == :kw && SAT_HDR_KW.has_key?(t.text)

# Updates [depth, hdr_closed] across a slice of newly added tokens.
-> scan_layout_state(toks, depth, hdr_closed)
  n = toks.size
  i = 0
  while i < n
    t = toks[i]
    if t.kind == :sym
      tx = t.text
      if tx == "(" || tx == "\[" || tx == "{" || tx == "⟨"
        depth += 1
      elsif tx == ")" || tx == "\]" || tx == "}" || tx == "⟩"
        depth -= 1
      elsif depth == 0 && !hdr_closed && (tx == ":" || tx == ":=" || tx == "|")
        hdr_closed = true
    i += 1
  [depth, hdr_closed]

# Source text -> array of LLine (logical lines, comments and blanks removed).
-> lex_source(src)
  # Scan one read-only UTF-8 view. Keep src for slicing original token text.
  bytes = ccall("w_string_bytes_view", src) ## u8[]
  out = []
  cur = nil
  depth = 0
  hdr_cand = false
  hdr_closed = true
  lineno = 0
  total = src.size
  pos = 0
  while pos <= total
    line_end = pos
    while line_end < total && bytes[line_end] != 10
      line_end += 1
    lineno += 1
    r = nil
    begin
      r = lex_line_bytes(src, pos, line_end, lineno, bytes)
    rescue err
      ind = 0
      while pos + ind < line_end && bytes[pos + ind] == 32
        ind += 1
      r = [ind, [Tok.new(:lexerr, err.to_s, lineno, ind)]]
    toks = r[1]
    nt = toks.size
    if nt > 0
      t0 = toks[0]
      is_pipe = t0.kind == :sym && t0.text == "|" && depth == 0
      # After an operator, a leading bar starts an absolute-value operand.
      # Otherwise keep pattern clauses and inductive constructors separate.
      if cur != nil && (depth > 0 || line_continues_after?(cur.toks) || (!is_pipe && r[0] > 0 && (continues_before?(t0) || (hdr_cand && !hdr_closed))))
        j = 0
        while j < nt
          cur.toks.push(toks[j])
          j += 1
        st = scan_layout_state(toks, depth, hdr_closed)
        depth = st[0]
        hdr_closed = st[1]
      else
        if cur != nil
          out.push(cur)
        cur = LLine.new(r[0], toks, lineno)
        hdr_cand = header_start_tok?(r[0], t0)
        hdr_closed = !hdr_cand
        st = scan_layout_state(toks, 0, hdr_closed)
        depth = st[0]
        hdr_closed = st[1]
    if line_end == total
      break
    pos = line_end + 1
  if cur != nil
    out.push(cur)
  out
