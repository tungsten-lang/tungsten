# Satori lexer: tokens plus layout.
#
# Physical lines are joined into logical lines while brackets are open or a
# line ends with an infix operator, `:`, `:=` or `,`. Each logical line keeps
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

-> sat_keywords
  ["def", "theorem", "lemma", "example", "axiom", "inductive", "structure", "import",
   "fun", "λ", "if", "then", "else", "by", "have", "show", "calc", "let", "in",
   "instance", "notation", "variable", "open", "section", "end", "where", "at", "using", "with", "from", "match"]

-> sat_symbols
  [":=", "=>", "->", "<->", "<=", ">=", "!=", "/\\", "\\/", "::", "++", "..",
   "→", "↔", "∧", "∨", "¬", "≠", "≤", "≥", "∀", "∃", "∈", "∉", "⊆", "∣", "×", "⟨", "⟩",
   "←", "·", "∘", "∑", "∏", "∪", "∩", "⁻¹", "√", "|",
   "(", ")", "\[", "\]", "{", "}", ",", ":", ";", "+", "-", "*", "/", "%", "^", "<", ">", "=", "!", "_", "@", "#", "."]

-> ident_start?(c)
  o = c.ord
  if (o >= 97 && o <= 122) || (o >= 65 && o <= 90) || o == 95
    return true
  if o >= 913 && o <= 1023
    return c != "λ" && c != "Σ" && c != "Π"
  if c == "ℕ" || c == "ℤ" || c == "ℚ" || c == "ℝ" || c == "ℂ" || c == "χ" || c == "ω"
    return true
  if o >= 8320 && o <= 8329
    return true
  if o >= 119808 && o <= 120831
    return true
  false

-> ident_char?(c)
  if ident_start?(c)
    return true
  o = c.ord
  if o >= 48 && o <= 57
    return true
  c == "'" || c == "!" || c == "?" || c == "₀" || c == "₁" || c == "₂" || c == "₃" || (o >= 8304 && o <= 8329)

-> digit?(c)
  o = c.ord
  o >= 48 && o <= 57

# Returns an array of raw tokens per physical line: [indent, [Tok...]]
-> lex_line(chars, lineno)
  toks = []
  i = 0
  n = chars.size
  indent = 0
  while i < n && (chars[i] == " " || chars[i] == "\t")
    indent += 1
    i += 1
  syms = sat_symbols
  kws = sat_keywords
  while i < n
    c = chars[i]
    if c == " " || c == "\t" || c == "\r"
      i += 1
    elsif c == "-" && i + 1 < n && chars[i + 1] == "-"
      i = n
    elsif digit?(c)
      j = i
      while j < n && (digit?(chars[j]) || chars[j] == "_")
        j += 1
      kind = :num
      if j + 1 < n && chars[j] == "." && digit?(chars[j + 1])
        j += 1
        while j < n && digit?(chars[j])
          j += 1
        kind = :dec
      toks.push(Tok.new(kind, arr_sub(chars, i, j - i).join("").gsub("_", ""), lineno, i))
      i = j
    elsif c == "\""
      j = i + 1
      while j < n && chars[j] != "\""
        j += 1
      toks.push(Tok.new(:str, arr_sub(chars, i + 1, j - i - 1).join(""), lineno, i))
      i = j + 1
    elsif ident_start?(c)
      j = i
      while j < n && (ident_char?(chars[j]) || (chars[j] == "." && j + 1 < n && (ident_start?(chars[j + 1]) || digit?(chars[j + 1])) && j > i))
        j += 1
      w = arr_sub(chars, i, j - i).join("")
      if kws.include?(w)
        toks.push(Tok.new(:kw, w, lineno, i))
      else
        toks.push(Tok.new(:id, w, lineno, i))
      i = j
    else
      matched = nil
      syms.each -> (s)
        if matched == nil
          sc = s.chars
          if i + sc.size <= n
            ok = true
            k = 0
            while ok && k < sc.size
              if chars[i + k] != sc[k]
                ok = false
              k += 1
            if ok
              matched = s
      if matched == nil
        raise "lexer: unexpected character '" + c + "' at line " + lineno.to_s
      if matched == "λ"
        toks.push(Tok.new(:kw, "fun", lineno, i))
      else
        toks.push(Tok.new(:sym, normalize_sym(matched), lineno, i))
      i += matched.chars.size
  [indent, toks]

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

-> continues_after?(t)
  if t.kind == :kw
    return t.text == "then" || t.text == "else" || t.text == "in"
  if t.kind != :sym
    return false
  ["→", "↔", "∧", "∨", ":=", ":", ",", "+", "-", "*", "/", "=", "<", ">", "≤", "≥", "≠", "∈", "=>", "::", "++", "^", "(", "\[", "{", "⟨", "×", "∣", "⊆"].include?(t.text)

-> bracket_delta(toks)
  d = 0
  toks.each -> (t)
    if t.kind == :sym
      if t.text == "(" || t.text == "\[" || t.text == "{" || t.text == "⟨"
        d += 1
      elsif t.text == ")" || t.text == "\]" || t.text == "}" || t.text == "⟩"
        d -= 1
  d

# Source text -> array of LLine (logical lines, comments and blanks removed).
-> lex_source(src)
  out = []
  lines = src.split("\n")
  cur = nil
  depth = 0
  lineno = 0
  lines.each -> (raw)
    lineno += 1
    r = lex_line(raw.chars, lineno)
    toks = r[1]
    if toks.size > 0
      if cur != nil && (depth > 0 || continues_after?(cur.toks[cur.toks.size - 1])) && !(toks[0].kind == :sym && toks[0].text == "|" && depth == 0)
        toks.each -> (t)
          cur.toks.push(t)
      else
        if cur != nil
          out.push(cur)
        cur = LLine.new(r[0], toks, lineno)
        depth = 0
      depth += bracket_delta(toks)
  if cur != nil
    out.push(cur)
  out
