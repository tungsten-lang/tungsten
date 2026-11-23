# runtime/regexp — a backtracking regular-expression engine with ECMAScript semantics
# (flags d g i m s u v y, named groups, lookahead and lookbehind, backreferences,
# \p{…} property escapes) and the RegExp builtin.
#
# The pattern compiles to a linked program of RxNode; matching is a recursive walk with
# captures saved and restored on backtrack. Input is read as UTF-16 code units (ASCII
# strings straight from their bytes); with u or v a surrogate pair reads as one code point.
# Repeats of a single-character node scan iteratively, so `.*` over long input does not
# recurse once per character.
# (Ported from blade/js/regexp.w.) A RegExp object is a JS:Special (cls "RegExp") whose
# internal is its compiled JS:Regex.

in JS

RX_CHAR = 1
RX_STR = 2
RX_ANY = 3
RX_CLASS = 4
RX_ALT = 5
RX_OPEN = 6
RX_CLOSE = 7
RX_REP = 8
RX_REP_TAIL = 9
RX_REP1 = 10
RX_BOL = 11
RX_EOL = 12
RX_WORDB = 13
RX_NWORDB = 14
RX_BACKREF = 15
RX_LOOK = 16
RX_MATCH = 17
RX_END_AT = 18
RX_EMPTY = 19

+ RxNode
  rw :kind, :nxt, :c, :str, :alts, :body, :min, :max, :greedy, :group, :ranges, :neg, :ahead, :negate_look, :name, :props
  -> new(@kind)
    @nxt = nil
    @c = 0
    @str = nil
    @alts = nil
    @body = nil
    @min = 0
    @max = 0
    @greedy = true
    @group = 0
    @ranges = nil
    @neg = false
    @ahead = true
    @negate_look = false
    @name = nil
    @props = nil

+ Regex
  rw :source, :flags, :prog, :ngroups, :names, :icase, :multiline, :dotall, :unicode, :sticky, :global, :has_indices, :first_char, :vmode

-> js_rx_syntax(msg, src)
  js_throw_syntax("Invalid regular expression: /" + src + "/: " + msg)

# ---- parser: pattern units/code points → node fragments ----

+ RxParser
  rw :ngroups, :names

  -> new(@src, @u, @flags)
    @unicode = @flags.index("u") != nil || @flags.index("v") != nil
    @vmode = @flags.index("v") != nil
    @icase = @flags.index("i") != nil
    @p = @unicode ? js_rx_codepoints(@src) : js_units(@src)
    @i = 0
    @n = @p.size
    @ngroups = 0
    @names = []
    @group_names = {}
    @backref_names = []
    @max_backref = 0
    @has_named = js_rx_has_named(@src)

  -> fail(msg)
    js_rx_syntax(msg, @src)

  -> peek
    @i < @n ? @p[@i] : -1

  -> peek_at(k)
    @i + k < @n ? @p[@i + k] : -1

  -> eat(c)
    if @i < @n && @p[@i] == c
      @i += 1
      return true
    false

  # Returns [head, tail] of a node chain.
  -> parse
    r = disjunction()
    fail("Unmatched ')'") if @i < @n
    @backref_names.each ->(nm)
      fail("Invalid named capture referenced") if !@group_names.has_key?(nm)
    fail("Invalid escape") if @unicode && @max_backref > @ngroups
    r

  -> disjunction
    alts = [alternative()]
    while eat(124)
      alts.push(alternative())
    return alts[0] if alts.size == 1
    node = JS:RxNode.new(RX_ALT)
    join = JS:RxNode.new(RX_EMPTY)
    node.alts = alts.map(->(a) js_rx_link(a, join))
    [node, join]

  -> alternative
    head = nil
    tail = nil
    while @i < @n && peek() != 124 && peek() != 41
      t = term()
      if t != nil
        if head == nil
          head = t[0]
          tail = t[1]
        else
          tail.nxt = t[0]
          tail = t[1]
    if head == nil
      e = JS:RxNode.new(RX_EMPTY)
      return [e, e]
    [head, tail]

  -> term
    c = peek()
    if c == 94
      @i += 1
      n = JS:RxNode.new(RX_BOL)
      return [n, n]
    if c == 36
      @i += 1
      n = JS:RxNode.new(RX_EOL)
      return [n, n]
    if c == 92 && (peek_at(1) == 98 || peek_at(1) == 66)
      @i += 2
      n = JS:RxNode.new(peek_at(-1) == 98 ? RX_WORDB : RX_NWORDB)
      return [n, n]
    if c == 40 && peek_at(1) == 63 && (peek_at(2) == 61 || peek_at(2) == 33 || (peek_at(2) == 60 && (peek_at(3) == 61 || peek_at(3) == 33)))
      # lookaround
      @i += 2
      behind = false
      if peek() == 60
        behind = true
        @i += 1
      negl = peek() == 33
      @i += 1
      d = disjunction()
      fail("Unterminated group") if !eat(41)
      n = JS:RxNode.new(RX_LOOK)
      n.ahead = !behind
      n.negate_look = negl
      fin = JS:RxNode.new(behind ? RX_END_AT : RX_MATCH)
      n.body = js_rx_link(d, fin)
      # lookaheads may be quantified in Annex B (non-unicode) mode
      if !behind && !@unicode && js_rx_quant_start?(peek(), self)
        return quantify([n, n])
      return [n, n]
    a = atom()
    return nil if a == nil
    quantify(a)

  -> quantify(a)
    c = peek()
    min = -1
    max = -1
    if c == 42
      min = 0
      max = -1
      @i += 1
    elsif c == 43
      min = 1
      max = -1
      @i += 1
    elsif c == 63
      min = 0
      max = 1
      @i += 1
    elsif c == 123
      save = @i
      b = braces()
      if b == nil
        fail("Incomplete quantifier") if @unicode
        @i = save
        return a
      min = b[0]
      max = b[1]
    else
      return a
    greedy = true
    if eat(63)
      greedy = false
    fail("numbers out of order in {} quantifier") if max >= 0 && max < min
    head = a[0]
    if (head.kind == RX_BOL || head.kind == RX_EOL || head.kind == RX_WORDB || head.kind == RX_NWORDB) && a[0] == a[1]
      fail("Nothing to repeat")
    if a[0] == a[1] && (head.kind == RX_CHAR || head.kind == RX_ANY || head.kind == RX_CLASS)
      n = JS:RxNode.new(RX_REP1)
      n.body = head
      n.min = min
      n.max = max
      n.greedy = greedy
      return [n, n]
    n = JS:RxNode.new(RX_REP)
    tailn = JS:RxNode.new(RX_REP_TAIL)
    tailn.body = n
    a[1].nxt = tailn
    n.body = a[0]
    n.min = min
    n.max = max
    n.greedy = greedy
    n.group = js_rx_first_group(a[0], a[1])
    n.c = @ngroups
    [n, n]

  # {n}, {n,}, {n,m} → [min, max] or nil (then a literal brace in Annex B).
  -> braces
    @i += 1
    a = digits()
    return nil if a < 0
    b = a
    if eat(44)
      b = peek() == 125 ? -1 : digits()
      return nil if b == -2
    return nil if !eat(125)
    [a, b]

  -> digits
    st = @i
    v = 0
    while @i < @n && @p[@i] >= 48 && @p[@i] <= 57
      v = v * 10 + (@p[@i] - 48)
      v = 1000000000 if v > 1000000000
      @i += 1
    return -2 if @i == st && peek() != 125
    return -1 if @i == st
    v

  -> atom
    c = peek()
    if c == 46
      @i += 1
      n = JS:RxNode.new(RX_ANY)
      return [n, n]
    if c == 40
      @i += 1
      if eat(63)
        if eat(58)
          d = disjunction()
          fail("Unterminated group") if !eat(41)
          return d
        if peek() == 60
          @i += 1
          nm = group_name()
          fail("Duplicate capture group name") if @group_names.has_key?(nm) && !@has_dup_ok
          @ngroups += 1
          g = @ngroups
          @group_names[nm] = g
          @names.push([nm, g])
          return group(g, nm)
        # modifiers (?i:...) — accept and ignore unknown
        while peek() >= 97 && peek() <= 122 || peek() == 45
          @i += 1
        if eat(58)
          d = disjunction()
          fail("Unterminated group") if !eat(41)
          return d
        fail("Invalid group")
      @ngroups += 1
      return group(@ngroups, nil)
    if c == 41
      fail("Unmatched ')'")
    if c == 91
      return char_class()
    if c == 92
      return atom_escape()
    if c == 42 || c == 43 || c == 63
      fail("Nothing to repeat")
    if c == 123
      if @unicode
        fail("Lone quantifier brackets")
      save = @i
      b = braces()
      @i = save
      fail("Nothing to repeat") if b != nil
    if (c == 125 || c == 93) && @unicode
      fail("Lone quantifier brackets")
    @i += 1
    char_node(c)

  -> group(g, nm)
    d = disjunction()
    fail("Unterminated group") if !eat(41)
    o = JS:RxNode.new(RX_OPEN)
    o.group = g
    cl = JS:RxNode.new(RX_CLOSE)
    cl.group = g
    o.nxt = d[0]
    d[1].nxt = cl
    [o, cl]

  -> group_name
    sb = []
    while @i < @n && @p[@i] != 62
      c = @p[@i]
      if c == 92 && peek_at(1) == 117
        @i += 2
        sb.push(unicode_escape_value(true))
      else
        sb.push(c)
        @i += 1
    fail("Invalid capture group name") if !eat(62) || sb.size == 0
    js_from_units(js_rx_to_units(sb, @unicode))

  -> char_node(c)
    n = JS:RxNode.new(RX_CHAR)
    n.c = c
    [n, n]

  -> atom_escape
    @i += 1
    fail("\\ at end of pattern") if @i >= @n
    c = peek()
    if c >= 49 && c <= 57
      save = @i
      v = 0
      while @i < @n && @p[@i] >= 48 && @p[@i] <= 57
        v = v * 10 + (@p[@i] - 48)
        @i += 1
      if @unicode || v <= js_rx_count_groups(@src)
        @max_backref = v if v > @max_backref
        n = JS:RxNode.new(RX_BACKREF)
        n.group = v
        return [n, n]
      @i = save
      if c >= 56
        @i += 1
        return char_node(c)
      return char_node(legacy_octal())
    if c == 107 && (@unicode || @has_named)
      @i += 1
      fail("Invalid named reference") if !eat(60)
      st = @i
      while @i < @n && @p[@i] != 62
        @i += 1
      fail("Invalid named reference") if !eat(62)
      nm = js_from_units(js_rx_to_units(@p.slice(st, @i - 1 - st), @unicode))
      @backref_names.push(nm)
      n = JS:RxNode.new(RX_BACKREF)
      n.name = nm
      return [n, n]
    cls = class_escape()
    if cls != nil
      n = JS:RxNode.new(RX_CLASS)
      n.ranges = cls[0]
      n.neg = cls[1]
      n.props = cls[2]
      return [n, n]
    char_node(char_escape())

  -> legacy_octal
    v = 0
    k = 0
    while k < 3 && @i < @n && @p[@i] >= 48 && @p[@i] <= 55
      nv = v * 8 + (@p[@i] - 48)
      break if nv > 255
      v = nv
      @i += 1
      k += 1
    v

  # \d \D \w \W \s \S \p{..} \P{..}: [ranges, negated, props] or nil.
  -> class_escape
    c = peek()
    if c == 100 || c == 68
      @i += 1
      return [[[48, 57]], c == 68, nil]
    if c == 119 || c == 87
      @i += 1
      r = [[48, 57], [65, 90], [95, 95], [97, 122]]
      if @icase && @unicode
        r.push([0x017F, 0x017F])
        r.push([0x212A, 0x212A])
      return [r, c == 87, nil]
    if c == 115 || c == 83
      @i += 1
      return [js_rx_space_ranges(), c == 83, nil]
    if (c == 112 || c == 80) && @unicode
      @i += 1
      fail("Invalid property name") if !eat(123)
      st = @i
      while @i < @n && @p[@i] != 125
        @i += 1
      fail("Invalid property name") if !eat(125)
      spec = js_from_units(@p.slice(st, @i - 1 - st))
      pr = js_rx_property(spec, @src)
      return [[], c == 80, [pr]]
    nil

  -> char_escape
    c = peek()
    @i += 1
    case c
    when 116
      9
    when 110
      10
    when 118
      11
    when 102
      12
    when 114
      13
    when 48
      if peek() >= 48 && peek() <= 57
        fail("Invalid decimal escape") if @unicode
        @i -= 1
        return legacy_octal()
      0
    when 99
      d = peek()
      if (d >= 65 && d <= 90) || (d >= 97 && d <= 122)
        @i += 1
        return d % 32
      fail("Invalid unicode escape") if @unicode
      @i -= 1
      92
    when 120
      h1 = js_rx_hex(peek())
      h2 = js_rx_hex(peek_at(1))
      if h1 >= 0 && h2 >= 0
        @i += 2
        return h1 * 16 + h2
      fail("Invalid escape") if @unicode
      120
    when 117
      unicode_escape_value(false)
    else
      if @unicode && !js_rx_syntax_char?(c) && c != 45
        fail("Invalid escape")
      c

  # After "\u": the code unit or code point.
  -> unicode_escape_value(in_name)
    if peek() == 123 && (@unicode || in_name)
      @i += 1
      v = 0
      st = @i
      while @i < @n && js_rx_hex(@p[@i]) >= 0
        v = v * 16 + js_rx_hex(@p[@i])
        fail("Invalid Unicode escape") if v > 0x10FFFF
        @i += 1
      fail("Invalid Unicode escape") if @i == st || !eat(125)
      return v
    k = 0
    v = 0
    while k < 4
      h = js_rx_hex(peek_at(k))
      if h < 0
        fail("Invalid Unicode escape") if @unicode || in_name
        return 117
      v = v * 16 + h
      k += 1
    @i += 4
    if (@unicode || in_name) && v >= 0xD800 && v <= 0xDBFF && peek() == 92 && peek_at(1) == 117
      save = @i
      @i += 2
      k = 0
      lo = 0
      ok = true
      while k < 4
        h = js_rx_hex(peek_at(k))
        ok = false if h < 0
        lo = lo * 16 + (h < 0 ? 0 : h)
        k += 1
      if ok && lo >= 0xDC00 && lo <= 0xDFFF
        @i += 4
        return 0x10000 + ((v - 0xD800) << 10) + (lo - 0xDC00)
      @i = save
    v

  -> char_class
    @i += 1
    neg = eat(94)
    ranges = []
    props = []
    if @vmode
      js_rx_parse_vclass(self, ranges, props)
      fail("Unterminated character class") if !eat(93)
    else
      while @i < @n && peek() != 93
        a = class_atom(ranges, props)
        if peek() == 45 && peek_at(1) != 93 && peek_at(1) != -1
          @i += 1
          b = class_atom(ranges, props)
          if a < 0 || b < 0
            fail("Invalid character class") if @unicode
            ranges.push([a, a]) if a >= 0
            ranges.push([45, 45])
            ranges.push([b, b]) if b >= 0
          else
            fail("Range out of order in character class") if b < a
            ranges.push([a, b])
        elsif a >= 0
          ranges.push([a, a])
      fail("Unterminated character class") if !eat(93)
    n = JS:RxNode.new(RX_CLASS)
    n.ranges = ranges
    n.neg = neg
    n.props = props.size == 0 ? nil : props
    [n, n]

  # One class atom: a code point, or -1 when it added a class escape to ranges/props.
  -> class_atom(ranges, props)
    c = peek()
    if c == 92
      @i += 1
      d = peek()
      if d == 98
        @i += 1
        return 8
      if d == 45 && @unicode
        @i += 1
        return 45
      if !@unicode && d == 99
        e = peek_at(1)
        if (e >= 48 && e <= 57) || e == 95
          @i += 2
          return e % 32
      if d >= 48 && d <= 57 && !@unicode
        return legacy_octal()
      cls = class_escape()
      if cls != nil
        if cls[1]
          props.push(["neg", cls[0], cls[2]])
        else
          cls[0].each ->(r) ranges.push(r)
          if cls[2] != nil
            cls[2].each ->(pp) props.push(pp)
        return -1
      if d == 107 && !@unicode
        @i += 1
        return 107
      return char_escape()
    @i += 1
    c

-> js_rx_codepoints(s)
  u = js_units(s)
  out = []
  i = 0
  while i < u.size
    c = u[i]
    if c >= 0xD800 && c <= 0xDBFF && i + 1 < u.size && u[i + 1] >= 0xDC00 && u[i + 1] <= 0xDFFF
      out.push(0x10000 + ((c - 0xD800) << 10) + (u[i + 1] - 0xDC00))
      i += 2
    else
      out.push(c)
      i += 1
  out

-> js_rx_to_units(a, unicode)
  return a if !unicode
  out = []
  a.each ->(c)
    if c >= 0x10000
      d = c - 0x10000
      out.push(0xD800 + (d >> 10))
      out.push(0xDC00 + (d & 0x3FF))
    else
      out.push(c)
  out

-> js_rx_has_named(src)
  i = src.index("(?<")
  while i != nil
    if i + 3 < src.size
      c = src.byte_at(i + 3)
      return true if c != 61 && c != 33
    i = src.index("(?<", i + 1)
  false

# Capturing groups in the pattern (for deciding \N backreference vs octal).
-> js_rx_count_groups(src)
  n = 0
  i = 0
  in_class = false
  while i < src.size
    b = src.byte_at(i)
    if b == 92
      i += 2
    else
      if b == 91
        in_class = true
      elsif b == 93
        in_class = false
      elsif b == 40 && !in_class
        if i + 1 < src.size && src.byte_at(i + 1) == 63
          n += 1 if i + 2 < src.size && src.byte_at(i + 2) == 60 && i + 3 < src.size && src.byte_at(i + 3) != 61 && src.byte_at(i + 3) != 33
        else
          n += 1
      i += 1
  n

-> js_rx_quant_start?(c, p)
  c == 42 || c == 43 || c == 63 || c == 123

-> js_rx_hex(c)
  return c - 48 if c >= 48 && c <= 57
  return c - 87 if c >= 97 && c <= 102
  return c - 55 if c >= 65 && c <= 70
  -1

-> js_rx_syntax_char?(c)
  c == 94 || c == 36 || c == 92 || c == 46 || c == 42 || c == 43 || c == 63 || c == 40 || c == 41 || c == 91 || c == 93 || c == 123 || c == 125 || c == 124 || c == 47

-> js_rx_space_ranges
  [[9, 13], [32, 32], [0xA0, 0xA0], [0x1680, 0x1680], [0x2000, 0x200A], [0x2028, 0x2029], [0x202F, 0x202F], [0x205F, 0x205F], [0x3000, 0x3000], [0xFEFF, 0xFEFF]]

# A \p{...} spec → [kind, value]: kind :gc (category prefix), :script, :binary.
-> js_rx_property(spec, src)
  eq = spec.index("=")
  if eq != nil
    k = spec.slice(0, eq)
    v = spec.slice(eq + 1, spec.size - eq - 1)
    if k == "General_Category" || k == "gc"
      return [:gc, js_rx_gc_code(v, src)]
    if k == "Script" || k == "sc" || k == "Script_Extensions" || k == "scx"
      return [:script, v]
    js_rx_syntax("Invalid property name", src)
  return [:any, ""] if spec == "Any"
  return [:ascii, ""] if spec == "ASCII"
  return [:assigned, ""] if spec == "Assigned"
  bin = ["Alphabetic", "Alpha", "White_Space", "space", "Uppercase", "Upper", "Lowercase", "Lower", "ASCII_Hex_Digit", "AHex", "Hex_Digit", "ID_Start", "IDS", "ID_Continue", "IDC", "Emoji", "Emoji_Presentation", "Extended_Pictographic", "Ideographic", "Math", "Dash"]
  return [:binary, spec] if bin.include?(spec)
  [:gc, js_rx_gc_code(spec, src)]

JS_GC_LONG = {"Letter" => "L", "Cased_Letter" => "LC", "Uppercase_Letter" => "Lu", "Lowercase_Letter" => "Ll", "Titlecase_Letter" => "Lt", "Modifier_Letter" => "Lm", "Other_Letter" => "Lo", "Mark" => "M", "Combining_Mark" => "M", "Nonspacing_Mark" => "Mn", "Spacing_Mark" => "Mc", "Enclosing_Mark" => "Me", "Number" => "N", "Decimal_Number" => "Nd", "digit" => "Nd", "Letter_Number" => "Nl", "Other_Number" => "No", "Punctuation" => "P", "punct" => "P", "Connector_Punctuation" => "Pc", "Dash_Punctuation" => "Pd", "Open_Punctuation" => "Ps", "Close_Punctuation" => "Pe", "Initial_Punctuation" => "Pi", "Final_Punctuation" => "Pf", "Other_Punctuation" => "Po", "Symbol" => "S", "Math_Symbol" => "Sm", "Currency_Symbol" => "Sc", "Modifier_Symbol" => "Sk", "Other_Symbol" => "So", "Separator" => "Z", "Space_Separator" => "Zs", "Line_Separator" => "Zl", "Paragraph_Separator" => "Zp", "Other" => "C", "Control" => "Cc", "cntrl" => "Cc", "Format" => "Cf", "Surrogate" => "Cs", "Private_Use" => "Co", "Unassigned" => "Cn"}

-> js_rx_gc_code(v, src)
  return JS_GC_LONG[v] if JS_GC_LONG.has_key?(v)
  ok = ["L", "LC", "Lu", "Ll", "Lt", "Lm", "Lo", "M", "Mn", "Mc", "Me", "N", "Nd", "Nl", "No", "P", "Pc", "Pd", "Ps", "Pe", "Pi", "Pf", "Po", "S", "Sm", "Sc", "Sk", "So", "Z", "Zs", "Zl", "Zp", "C", "Cc", "Cf", "Cs", "Co", "Cn"]
  return v if ok.include?(v)
  js_rx_syntax("Invalid property name", src)

-> js_rx_cp_category(c)
  return "Cs" if c >= 0xD800 && c <= 0xDFFF
  begin
    return Codepoint.new(c).category.to_s
  rescue e
    return "Cn"
  "Cn"

-> js_rx_prop_match?(pr, c)
  k = pr[0]
  if k == :gc
    cat = js_rx_cp_category(c)
    v = pr[1]
    return cat == "Lu" || cat == "Ll" || cat == "Lt" if v == "LC"
    return cat.starts_with?(v)
  return true if k == :any
  return c < 128 if k == :ascii
  return js_rx_cp_category(c) != "Cn" if k == :assigned
  if k == :script
    begin
      return Unicode.script(c).to_s.downcase == pr[1].downcase || (pr[1].size == 4 && Unicode.script(c).to_s.downcase.starts_with?(pr[1].downcase))
    rescue e
      return false
  # binary properties
  v = pr[1]
  cat = js_rx_cp_category(c)
  return cat.starts_with?("L") || cat == "Nl" if v == "Alphabetic" || v == "Alpha"
  return js_is_trim_cp(c) || c == 0x85 if v == "White_Space" || v == "space"
  return cat == "Lu" if v == "Uppercase" || v == "Upper"
  return cat == "Ll" if v == "Lowercase" || v == "Lower"
  return (c >= 48 && c <= 57) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102) if v == "ASCII_Hex_Digit" || v == "AHex" || v == "Hex_Digit"
  return cat.starts_with?("L") || cat == "Nl" if v == "ID_Start" || v == "IDS"
  return cat.starts_with?("L") || cat == "Nl" || cat == "Mn" || cat == "Mc" || cat == "Nd" || cat == "Pc" if v == "ID_Continue" || v == "IDC"
  return (c >= 0x1F300 && c <= 0x1FAFF) || (c >= 0x2600 && c <= 0x27BF) if v == "Emoji" || v == "Emoji_Presentation" || v == "Extended_Pictographic"
  return (c >= 0x4E00 && c <= 0x9FFF) || (c >= 0x3400 && c <= 0x4DBF) if v == "Ideographic"
  return cat == "Sm" if v == "Math"
  return cat == "Pd" if v == "Dash"
  false

# v-flag classes: nested classes, && intersection, -- subtraction, \q{..} (strings ignored).
-> js_rx_parse_vclass(p, ranges, props)
  while p.peek() != 93 && p.peek() != -1
    if p.peek() == 91
      p.eat(91)
      neg = p.eat(94)
      sub_r = []
      sub_p = []
      js_rx_parse_vclass(p, sub_r, sub_p)
      p.fail("Unterminated character class") if !p.eat(93)
      if neg
        props.push(["neg", sub_r, sub_p.size == 0 ? nil : sub_p])
      else
        sub_r.each ->(r) ranges.push(r)
        sub_p.each ->(x) props.push(x)
    elsif p.peek() == 38 && p.peek_at(1) == 38
      p.eat(38)
      p.eat(38)
      rest_r = []
      rest_p = []
      js_rx_parse_vclass(p, rest_r, rest_p)
      left_r = ranges.map(->(x) x)
      left_p = props.map(->(x) x)
      ranges.clear
      props.clear
      props.push(["and", [left_r, left_p], [rest_r, rest_p]])
    elsif p.peek() == 45 && p.peek_at(1) == 45
      p.eat(45)
      p.eat(45)
      rest_r = []
      rest_p = []
      js_rx_parse_vclass(p, rest_r, rest_p)
      left_r = ranges.map(->(x) x)
      left_p = props.map(->(x) x)
      ranges.clear
      props.clear
      props.push(["sub", [left_r, left_p], [rest_r, rest_p]])
    else
      a = p.class_atom(ranges, props)
      if a >= 0
        if p.peek() == 45 && p.peek_at(1) != 45 && p.peek_at(1) != 93
          p.eat(45)
          b = p.class_atom(ranges, props)
          ranges.push([a, b]) if b >= a
        else
          ranges.push([a, a])
  nil

-> js_rx_link(frag, target)
  frag[1].nxt = target
  frag[0]

-> js_rx_first_group(head, tail)
  0

# ---- compile ----

JS_RX_CACHE = {}

-> js_rx_compile(source, flags)
  key = flags + "/" + source
  c = JS_RX_CACHE[key]
  return c if c != nil
  js_rx_check_flags(flags, source)
  p = JS:RxParser.new(source, false, flags)
  frag = p.parse
  m = JS:RxNode.new(RX_MATCH)
  rx = JS:Regex.new
  rx.source = source
  rx.flags = flags
  rx.prog = js_rx_link(frag, m)
  rx.ngroups = p.ngroups
  rx.names = p.names
  rx.icase = flags.index("i") != nil
  rx.multiline = flags.index("m") != nil
  rx.dotall = flags.index("s") != nil
  rx.unicode = flags.index("u") != nil || flags.index("v") != nil
  rx.vmode = flags.index("v") != nil
  rx.sticky = flags.index("y") != nil
  rx.global = flags.index("g") != nil
  rx.has_indices = flags.index("d") != nil
  rx.first_char = (rx.prog.kind == RX_CHAR && !rx.icase) ? rx.prog.c : -1
  JS_RX_CACHE[key] = rx if JS_RX_CACHE.size < 2000
  rx

-> js_rx_check_flags(flags, src)
  seen = ""
  i = 0
  while i < flags.size
    f = flags.slice(i, 1)
    js_throw_syntax("Invalid regular expression flags '" + flags + "'") if "dgimsuvy".index(f) == nil || seen.index(f) != nil
    seen = seen + f
    i += 1
  js_throw_syntax("Invalid regular expression flags '" + flags + "'") if seen.index("u") != nil && seen.index("v") != nil
  nil

# ---- matcher ----

+ RxMatcher
  rw :caps, :steps

  -> new(@rx, @s)
    @u = js_ascii?(@s) ? nil : js_units(@s)
    @len = @u == nil ? @s.size : @u.size
    @caps = Array.new((@rx.ngroups + 1) * 2, -1)
    @loops = []
    @ends = []
    @icase = @rx.icase
    @uni = @rx.unicode
    @multi = @rx.multiline
    @dotall = @rx.dotall
    @steps = 0
    @w = 1

  -> len
    @len

  -> unit(i)
    @u == nil ? @s.byte_at(i) : @u[i]

  # Code point at i (u mode joins surrogate pairs); sets @w to its width in units.
  -> cp_at(i)
    c = @u == nil ? @s.byte_at(i) : @u[i]
    @w = 1
    if @uni && c >= 0xD800 && c <= 0xDBFF && i + 1 < @len
      d = @u[i + 1]
      if d >= 0xDC00 && d <= 0xDFFF
        @w = 2
        return 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00)
    c

  # Code point ending at i (for lookbehind / word boundary); sets @w.
  -> cp_before(i)
    c = unit(i - 1)
    @w = 1
    if @uni && c >= 0xDC00 && c <= 0xDFFF && i - 2 >= 0
      h = unit(i - 2)
      if h >= 0xD800 && h <= 0xDBFF
        @w = 2
        return 0x10000 + ((h - 0xD800) << 10) + (c - 0xDC00)
    c

  -> canon(c)
    js_rx_canon(c, @uni)

  -> line_term?(c)
    c == 10 || c == 13 || c == 0x2028 || c == 0x2029

  -> word_at?(i)
    return false if i < 0 || i >= @len
    c = unit(i)
    w = (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95
    return w if w || !(@icase && @uni)
    c == 0x017F || c == 0x212A

  # Does the single-char node n match at i? Returns the width consumed or 0.
  -> char_match(n, i)
    return 0 if i >= @len
    k = n.kind
    if k == RX_CHAR
      c = cp_at(i)
      if c == n.c
        return @w
      if @icase && canon(c) == canon(n.c)
        return @w
      return 0
    if k == RX_ANY
      c = cp_at(i)
      return 0 if !@dotall && line_term?(c)
      return @w
    c = cp_at(i)
    w = @w
    hit = js_rx_class_has?(n, c, @icase, @uni)
    hit = !hit if n.neg
    hit ? w : 0

  -> run(n, i)
    while true
      @steps += 1
      js_throw_range("Maximum regular expression backtracking exceeded") if @steps > 50000000
      k = n.kind
      if k == RX_CHAR || k == RX_ANY || k == RX_CLASS
        w = char_match(n, i)
        return -1 if w == 0
        i += w
        n = n.nxt
      elsif k == RX_EMPTY
        n = n.nxt
      elsif k == RX_MATCH
        return i
      elsif k == RX_STR
        return -1 if !str_at(n.str, i)
        i += n.str.size
        n = n.nxt
      elsif k == RX_OPEN
        g = n.group * 2
        old = @caps[g]
        olde = @caps[g + 1]
        @caps[g] = i
        r = run(n.nxt, i)
        if r < 0
          @caps[g] = old
          @caps[g + 1] = olde
        return r
      elsif k == RX_CLOSE
        g = n.group * 2 + 1
        old = @caps[g]
        @caps[g] = i
        r = run(n.nxt, i)
        @caps[g] = old if r < 0
        return r
      elsif k == RX_ALT
        alts = n.alts
        j = 0
        while j < alts.size
          r = run(alts[j], i)
          return r if r >= 0
          j += 1
        return -1
      elsif k == RX_REP1
        return rep1(n, i)
      elsif k == RX_REP
        return rep_enter(n, i)
      elsif k == RX_REP_TAIL
        return rep_tail(n, i)
      elsif k == RX_BOL
        if i != 0
          return -1 if !@multi || !line_term?(unit(i - 1))
        n = n.nxt
      elsif k == RX_EOL
        if i != @len
          return -1 if !@multi || !line_term?(unit(i))
        n = n.nxt
      elsif k == RX_WORDB || k == RX_NWORDB
        b = word_at?(i - 1) != word_at?(i)
        return -1 if b != (k == RX_WORDB)
        n = n.nxt
      elsif k == RX_BACKREF
        r = backref(n, i)
        return -1 if r < 0
        i = r
        n = n.nxt
      elsif k == RX_LOOK
        return look(n, i)
      elsif k == RX_END_AT
        return @ends.last == i ? i : -1
      else
        return -1
    -1

  -> str_at(units, i)
    return false if i + units.size > @len
    k = 0
    while k < units.size
      return false if unit(i + k) != units[k]
      k += 1
    true

  # Greedy/lazy repeat of a one-character node: scan iteratively.
  -> rep1(n, i)
    body = n.body
    mx = n.max
    if !n.greedy
      cnt = 0
      pos = i
      while true
        if cnt >= n.min
          r = run(n.nxt, pos)
          return r if r >= 0
        return -1 if mx >= 0 && cnt >= mx
        w = char_match(body, pos)
        return -1 if w == 0
        pos += w
        cnt += 1
      return -1
    positions = nil
    pos = i
    cnt = 0
    while mx < 0 || cnt < mx
      w = char_match(body, pos)
      break if w == 0
      if w != 1 && positions == nil
        positions = [i]
        # rebuild positions for the narrow prefix scanned so far
        k = 1
        while k <= cnt
          positions.push(i + k)
          k += 1
      pos += w
      cnt += 1
      positions.push(pos) if positions != nil
    return -1 if cnt < n.min
    while cnt >= n.min
      p = positions == nil ? i + cnt : positions[cnt]
      r = run(n.nxt, p)
      return r if r >= 0
      cnt -= 1
    -1

  -> rep_enter(n, i)
    @loops.push([n, 0, i])
    r = rep_try(n, i, 0)
    @loops.pop
    r

  # Try iteration count+1 of n at i, or leave the loop.
  -> rep_try(n, i, count)
    if n.greedy
      if n.max < 0 || count < n.max
        r = rep_body(n, i, count)
        return r if r >= 0
      return -1 if count < n.min
      return run_after_loop(n, i)
    if count >= n.min
      r = run_after_loop(n, i)
      return r if r >= 0
    return -1 if n.max >= 0 && count >= n.max
    rep_body(n, i, count)

  -> run_after_loop(n, i)
    top = @loops.pop
    r = run(n.nxt, i)
    @loops.push(top)
    r

  -> rep_body(n, i, count)
    # captures inside the body reset at the start of each iteration
    saved = clear_body_caps(n)
    top = @loops.last
    old_count = top[1]
    old_start = top[2]
    top[1] = count
    top[2] = i
    r = run(n.body, i)
    top[1] = old_count
    top[2] = old_start
    restore_caps(saved) if r < 0
    r

  -> rep_tail(t, i)
    top = @loops.last
    n = top[0]
    count = top[1] + 1
    # an iteration that matched empty ends the loop
    return -1 if i == top[2] && count > n.min
    rep_try(n, i, count)

  -> clear_body_caps(n)
    lo = n.ranges
    if lo == nil
      lo = js_rx_body_groups(n)
      lo = [] if lo == nil
      n.ranges = lo
    return nil if lo.size == 0
    saved = []
    g = lo[0]
    while g <= lo[1]
      saved.push(g)
      saved.push(@caps[g * 2])
      saved.push(@caps[g * 2 + 1])
      @caps[g * 2] = -1
      @caps[g * 2 + 1] = -1
      g += 1
    saved

  -> restore_caps(saved)
    return nil if saved == nil
    k = 0
    while k < saved.size
      g = saved[k]
      @caps[g * 2] = saved[k + 1]
      @caps[g * 2 + 1] = saved[k + 2]
      k += 3
    nil

  -> backref(n, i)
    g = n.group
    if n.name != nil
      g = 0
      @rx.names.each ->(pr)
        g = pr[1] if pr[0] == n.name && @caps[pr[1] * 2 + 1] >= 0
      if g == 0
        @rx.names.each ->(pr)
          g = pr[1] if pr[0] == n.name && g == 0
    s = @caps[g * 2]
    e = @caps[g * 2 + 1]
    return i if s < 0 || e < 0
    l = e - s
    return -1 if i + l > @len
    k = 0
    while k < l
      a = unit(s + k)
      b = unit(i + k)
      if a != b
        return -1 if !@icase || canon(a) != canon(b)
      k += 1
    i + l

  -> look(n, i)
    saved = @caps.map(->(x) x)
    ok = false
    if n.ahead
      saved_loops = @loops
      @loops = []
      r = run(n.body, i)
      @loops = saved_loops
      ok = r >= 0
    else
      @ends.push(i)
      saved_loops = @loops
      @loops = []
      # leftmost start first: the longest body match ending at i, which is what backward
      # evaluation (§22.2.2.4.1) gives for greedy bodies. TODO: lazy bodies need a
      # right-to-left matcher.
      j = 0
      while j <= i && !ok
        r = run(n.body, j)
        ok = true if r >= 0
        j += 1
      @loops = saved_loops
      @ends.pop
    if n.negate_look
      @caps = saved
      return -1 if ok
      return run(n.nxt, i)
    if !ok
      @caps = saved
      return -1
    r2 = run(n.nxt, i)
    @caps = saved if r2 < 0
    r2

  # Try a match starting exactly at i: end index or -1.
  -> match_at(i)
    k = 0
    while k < @caps.size
      @caps[k] = -1
      k += 1
    @loops = []
    r = run(@rx.prog, i)
    if r >= 0
      @caps[0] = i
      @caps[1] = r
    r

-> js_rx_body_groups(n)
  b = n.body
  lo = -1
  hi = -1
  seen = 0
  stack = [b]
  visited = {}
  while stack.size > 0 && seen < 10000
    x = stack.pop
    if x != nil && !visited.has_key?(x)
      visited[x] = true
      seen += 1
      if x.kind == RX_OPEN
        lo = x.group if lo < 0 || x.group < lo
        hi = x.group if x.group > hi
      if x.kind != RX_REP_TAIL
        stack.push(x.nxt)
      stack.push(x.body) if x.kind == RX_REP || x.kind == RX_REP1 || x.kind == RX_LOOK
      x.alts.each(->(a) stack.push(a)) if x.alts != nil
  return nil if lo < 0
  [lo, hi]

# Simple case folding for /i: ECMAScript Canonicalize (uppercase in non-unicode mode).
JS_RX_CANON_CACHE = {}

-> js_rx_canon(c, uni)
  if c < 128
    return (c >= 65 && c <= 90) ? c + 32 : c
  key = uni ? 0 - c : c
  v = JS_RX_CANON_CACHE[key]
  return v if v != nil
  r = c
  begin
    s = js_cp_str(c)
    l = s.unicode_downcase
    if l.size > 0
      d = js_utf8_decode_at(l, 0)
      r = d if js_utf8_width(l, 0) == l.size
  rescue e
    r = c
  # non-unicode mode never maps a non-ASCII char to ASCII
  r = c if !uni && r < 128
  JS_RX_CANON_CACHE[key] = r
  r

-> js_rx_class_has?(n, c, icase, uni)
  if js_rx_ranges_has?(n.ranges, c)
    return true
  if icase
    cc = js_rx_canon(c, uni)
    rs = n.ranges
    k = 0
    while k < rs.size
      r = rs[k]
      if r[1] - r[0] < 400
        x = r[0]
        while x <= r[1]
          return true if js_rx_canon(x, uni) == cc
          x += 1
      elsif cc >= r[0] && cc <= r[1]
        return true
      k += 1
  return false if n.props == nil
  js_rx_props_has?(n.props, c)

-> js_rx_ranges_has?(rs, c)
  k = 0
  while k < rs.size
    r = rs[k]
    return true if c >= r[0] && c <= r[1]
    k += 1
  false

-> js_rx_props_has?(props, c)
  q = 0
  while q < props.size
    p = props[q]
    if p[0] == "neg"
      inner = js_rx_ranges_has?(p[1], c) || (p[2] != nil && js_rx_props_has?(p[2], c))
      return true if !inner
    elsif p[0] == "and"
      a = js_rx_ranges_has?(p[1][0], c) || js_rx_props_has?(p[1][1], c)
      b = js_rx_ranges_has?(p[2][0], c) || js_rx_props_has?(p[2][1], c)
      return true if a && b
    elsif p[0] == "sub"
      a = js_rx_ranges_has?(p[1][0], c) || js_rx_props_has?(p[1][1], c)
      b = js_rx_ranges_has?(p[2][0], c) || js_rx_props_has?(p[2][1], c)
      return true if a && !b
    else
      return true if js_rx_prop_match?(p, c)
    q += 1
  false

# Search s from unit index start; [match_start, matcher] or nil.
-> js_rx_search(rx, s, start, sticky)
  m = JS:RxMatcher.new(rx, s)
  n = m.len
  i = start
  fc = rx.first_char
  ascii = js_ascii?(s)
  while i <= n
    if fc >= 0 && !sticky && fc < 128 && ascii
      j = s.index(fc.chr, i)
      return nil if j == nil
      i = j
    r = m.match_at(i)
    return [i, m] if r >= 0
    return nil if sticky
    i += 1
  nil

# ---- the RegExp builtin ----

-> js_regexp_alloc(proto)
  o = js_new_special(proto, "RegExp")
  o.define("lastIndex", ~0.0, ATTR_W)
  o

-> js_regexp_init(o, pattern, flags)
  rx = js_rx_compile(pattern, flags)
  o.internal = rx
  ok = jset(o, "lastIndex", ~0.0)
  js_throw_type("Cannot assign to read only property 'lastIndex'") if !ok
  o

# A regex literal: a fresh object each evaluation, sharing the compiled program.
-> js_regexp_create(pattern, flags)
  o = js_regexp_alloc(js_realm().intrinsic("RegExp.prototype"))
  o.internal = js_rx_compile(pattern, flags)
  o

-> js_regexp_ctor(args, nt)
  r = js_realm()
  pat = js_arg(args, 0)
  fl = js_arg(args, 1)
  pattern_is_re = js_is_regexp?(pat)
  if nt == nil
    nt = r.intrinsic("RegExp")
    if pattern_is_re && fl == nil
      c = jget(pat, "constructor")
      return pat if c == nt
  src = nil
  if js_internal(pat).is_a?(JS:Regex)
    src = pat.internal.source
    fl = pat.internal.flags if fl == nil
  elsif pattern_is_re
    src = jget(pat, "source")
    fl = jget(pat, "flags") if fl == nil
  else
    src = pat
  o = js_regexp_alloc(r.proto_from(nt, "RegExp"))
  ps = src == nil ? "" : js_to_string(src)
  fs = fl == nil ? "" : js_to_string(fl)
  js_regexp_init(o, ps, fs)

-> js_this_rx(v, what)
  js_throw_type("RegExp.prototype." + what + " requires that 'this' be a RegExp object") if !js_internal(v).is_a?(JS:Regex)
  v.internal

# RegExpBuiltinExec: the match array or JS_NULL.
-> js_regexp_builtin_exec(o, s)
  rx = js_this_rx(o, "exec")
  li = js_to_length(jget(o, "lastIndex"))
  global = rx.global
  sticky = rx.sticky
  li = 0 if !global && !sticky
  n = js_len(s)
  if li > n
    js_rx_set_last_index(o, ~0.0) if global || sticky
    return JS_NULL
  res = js_rx_search(rx, s, li, sticky)
  if res == nil
    js_rx_set_last_index(o, ~0.0) if global || sticky
    return JS_NULL
  m = res[1]
  e = m.caps[1]
  js_rx_set_last_index(o, e + ~0.0) if global || sticky
  js_rx_match_array(rx, s, m.caps)

-> js_rx_set_last_index(o, v)
  ok = jset(o, "lastIndex", v)
  js_throw_type("Cannot assign to read only property 'lastIndex' of object") if !ok

-> js_rx_match_array(rx, s, caps)
  r = js_realm()
  items = []
  g = 0
  while g <= rx.ngroups
    st = caps[g * 2]
    en = caps[g * 2 + 1]
    items.push(st >= 0 && en >= 0 ? js_substring(s, st, en) : nil)
    g += 1
  a = r.adopt_array(items.dup)
  jdefine(a, "index", caps[0] + ~0.0, ATTR_ALL)
  jdefine(a, "input", s, ATTR_ALL)
  groups = nil
  if rx.names.size > 0
    groups = js_new_object(nil)
    q = 0
    while q < rx.names.size
      pr = rx.names[q]
      v = items[pr[1]]
      if v != nil || !groups.has_own?(pr[0])
        groups.define(pr[0], v, ATTR_ALL)
      q += 1
  jdefine(a, "groups", groups, ATTR_ALL)
  if rx.has_indices
    ind = []
    g = 0
    while g <= rx.ngroups
      st = caps[g * 2]
      en = caps[g * 2 + 1]
      ind.push(st >= 0 && en >= 0 ? r.adopt_array([st + ~0.0, en + ~0.0]) : nil)
      g += 1
    ia = r.adopt_array(ind.dup)
    ig = nil
    if rx.names.size > 0
      ig = js_new_object(nil)
      q = 0
      while q < rx.names.size
        pr = rx.names[q]
        ig.define(pr[0], ind[pr[1]], ATTR_ALL)
        q += 1
    jdefine(ia, "groups", ig, ATTR_ALL)
    jdefine(a, "indices", ia, ATTR_ALL)
  a

# RegExpExec: a user exec wins over the builtin.
-> js_regexp_exec(o, s)
  ex = jget(o, "exec")
  if js_callable?(ex) && ex != js_realm().intrinsic("%RegExpProto_exec%")
    res = js_call_arr(ex, o, [s])
    js_throw_type("exec result must be an object or null") if !(js_object?(res) || res == JS_NULL)
    return res
  js_regexp_builtin_exec(o, s)

-> js_regexp_test(o, sv)
  js_throw_type("RegExp.prototype.test called on incompatible receiver") if !js_object?(o)
  s = js_to_string(sv)
  js_regexp_exec(o, s) != JS_NULL

-> js_regexp_flags(o)
  js_throw_type("RegExp.prototype.flags getter called on non-object") if !js_object?(o)
  out = ""
  out = out + "d" if js_to_boolean(jget(o, "hasIndices"))
  out = out + "g" if js_to_boolean(jget(o, "global"))
  out = out + "i" if js_to_boolean(jget(o, "ignoreCase"))
  out = out + "m" if js_to_boolean(jget(o, "multiline"))
  out = out + "s" if js_to_boolean(jget(o, "dotAll"))
  out = out + "u" if js_to_boolean(jget(o, "unicode"))
  out = out + "v" if js_to_boolean(jget(o, "unicodeSets"))
  out = out + "y" if js_to_boolean(jget(o, "sticky"))
  out

-> js_regexp_flag_getter(o, f, name)
  return o.internal.flags.index(f) != nil if js_internal(o).is_a?(JS:Regex)
  return nil if o == js_realm().intrinsic("RegExp.prototype")
  js_throw_type("RegExp.prototype." + name + " getter called on non-RegExp object")

-> js_regexp_source(o)
  return js_rx_escape_source(o.internal.source) if js_internal(o).is_a?(JS:Regex)
  return "(?:)" if o == js_realm().intrinsic("RegExp.prototype")
  js_throw_type("RegExp.prototype.source getter called on non-RegExp object")

-> js_rx_escape_source(s)
  return "(?:)" if s == ""
  out = StringBuffer()
  in_class = false
  i = 0
  while i < s.size
    b = s.byte_at(i)
    if b == 92 && i + 1 < s.size
      out.append(s.slice(i, 2))
      i += 2
    else
      if b == 47 && !in_class
        out.append("\\/")
      elsif b == 10
        out.append("\\n")
      elsif b == 13
        out.append("\\r")
      else
        in_class = true if b == 91
        in_class = false if b == 93
        out.append(s.slice(i, 1))
      i += 1
  out.to_s

-> js_regexp_to_string(o)
  js_throw_type("RegExp.prototype.toString called on incompatible receiver") if !js_object?(o)
  "/" + js_to_string(jget(o, "source")) + "/" + js_to_string(jget(o, "flags"))

-> js_regexp_match(o, sv)
  js_throw_type("RegExp.prototype\[Symbol.match] called on non-object") if !js_object?(o)
  s = js_to_string(sv)
  fl = js_to_string(jget(o, "flags"))
  return js_regexp_exec(o, s) if fl.index("g") == nil
  full = fl.index("u") != nil || fl.index("v") != nil
  js_rx_set_last_index(o, ~0.0)
  out = []
  while true
    res = js_regexp_exec(o, s)
    break if res == JS_NULL
    ms = js_to_string(jget(res, "0"))
    out.push(ms)
    if ms == ""
      li = js_to_length(jget(o, "lastIndex"))
      js_rx_set_last_index(o, js_rx_advance(s, li, full) + ~0.0)
  return JS_NULL if out.size == 0
  js_realm().adopt_array(out)

-> js_rx_advance(s, i, full)
  return i + 1 if !full || js_ascii?(s)
  u = js_units(s)
  return i + 1 if i + 1 >= u.size
  c = u[i]
  return i + 2 if c >= 55296 && c <= 56319 && u[i + 1] >= 56320 && u[i + 1] <= 57343
  i + 1

-> js_regexp_replace(o, sv, repl)
  js_throw_type("RegExp.prototype\[Symbol.replace] called on non-object") if !js_object?(o)
  s = js_to_string(sv)
  n = js_len(s)
  fun = js_callable?(repl) ? repl : nil
  rs = fun == nil ? js_to_string(repl) : nil
  fl = js_to_string(jget(o, "flags"))
  global = fl.index("g") != nil
  full = fl.index("u") != nil || fl.index("v") != nil
  js_rx_set_last_index(o, ~0.0) if global
  results = []
  while true
    res = js_regexp_exec(o, s)
    break if res == JS_NULL
    results.push(res)
    break if !global
    ms = js_to_string(jget(res, "0"))
    if ms == ""
      li = js_to_length(jget(o, "lastIndex"))
      js_rx_set_last_index(o, js_rx_advance(s, li, full) + ~0.0)
  sb = StringBuffer()
  next_pos = 0
  ri = 0
  while ri < results.size
    res = results[ri]
    ri += 1
    nc = js_len_of(res)
    nc = 1 if nc < 1
    matched = js_to_string(jget(res, "0"))
    ml = js_len(matched)
    pos = js_to_integer(jget(res, "index"))
    pos = ~0.0 if pos < ~0.0
    pos = n + ~0.0 if pos > n + ~0.0
    p = pos.to_i
    caps = []
    k = 1
    while k < nc
      cv = jget(res, k.to_s)
      caps.push(cv == nil ? nil : js_to_string(cv))
      k += 1
    named = jget(res, "groups")
    rep = nil
    if fun != nil
      args = [matched] + caps + [pos]
      args.push(s)
      args.push(named) if named != nil
      rep = js_to_string(js_call_arr(fun, nil, args))
    else
      nobj = named == nil ? nil : js_to_obj(named)
      rep = js_get_substitution(matched, s, p, caps, nobj, rs)
    if p >= next_pos
      sb.append(js_substring(s, next_pos, p))
      sb.append(rep)
      next_pos = p + ml
  sb.append(js_substring(s, next_pos, n)) if next_pos < n
  sb.to_s

-> js_regexp_search(o, sv)
  js_throw_type("RegExp.prototype\[Symbol.search] called on non-object") if !js_object?(o)
  s = js_to_string(sv)
  prev = jget(o, "lastIndex")
  js_rx_set_last_index(o, ~0.0) if !js_same_value(prev, ~0.0)
  res = js_regexp_exec(o, s)
  cur = jget(o, "lastIndex")
  js_rx_set_last_index(o, prev) if !js_same_value(cur, prev)
  idx = ~-1.0
  idx = jget(res, "index") if res != JS_NULL
  idx

-> js_regexp_split(o, sv, limit)
  js_throw_type("RegExp.prototype\[Symbol.split] called on non-object") if !js_object?(o)
  r = js_realm()
  s = js_to_string(sv)
  c = js_species_ctor(o, r.intrinsic("RegExp"))
  fl = js_to_string(jget(o, "flags"))
  full = fl.index("u") != nil || fl.index("v") != nil
  nfl = fl.index("y") == nil ? fl + "y" : fl
  splitter = js_construct(c, [o, nfl], nil)
  lim = limit == nil ? 4294967295 : js_to_uint32(limit)
  out = []
  return r.adopt_array([]) if lim == 0
  size = js_len(s)
  if size == 0
    z = js_regexp_exec(splitter, s)
    return r.adopt_array(z == JS_NULL ? [s] : [])
  p = 0
  q = 0
  while q < size
    js_rx_set_last_index(splitter, q + ~0.0)
    z = js_regexp_exec(splitter, s)
    if z == JS_NULL
      q = js_rx_advance(s, q, full)
    else
      e = js_to_length(jget(splitter, "lastIndex"))
      e = size if e > size
      if e == p
        q = js_rx_advance(s, q, full)
      else
        out.push(js_substring(s, p, q))
        return r.adopt_array(out) if out.size == lim
        p = e
        nc = js_len_of(z)
        k = 1
        while k < nc
          out.push(jget(z, k.to_s))
          return r.adopt_array(out) if out.size == lim
          k += 1
        q = p
  out.push(js_substring(s, p, size))
  r.adopt_array(out)

# A RegExp String Iterator's state (its internal).
+ RxIterState
  rw :rx, :s, :global, :full, :done
  -> new(@rx, @s, @global, @full)
    @done = false

-> js_regexp_match_all(o, sv)
  js_throw_type("RegExp.prototype\[Symbol.matchAll] called on non-object") if !js_object?(o)
  r = js_realm()
  s = js_to_string(sv)
  c = js_species_ctor(o, r.intrinsic("RegExp"))
  fl = js_to_string(jget(o, "flags"))
  m = js_construct(c, [o, fl], nil)
  js_rx_set_last_index(m, js_to_length(jget(o, "lastIndex")) + ~0.0)
  it = js_new_special(r.intrinsic("%RegExpStringIteratorPrototype%"), "RegExp String Iterator")
  it.internal = JS:RxIterState.new(m, s, fl.index("g") != nil, fl.index("u") != nil || fl.index("v") != nil)
  it

-> js_regexp_string_iter_next(this)
  js_throw_type("not a RegExp String Iterator") if !(js_special?(this, "RegExp String Iterator") && this.internal.is_a?(JS:RxIterState))
  it = this.internal
  return js_iter_result(nil, true) if it.done
  res = js_regexp_exec(it.rx, it.s)
  if res == JS_NULL
    it.done = true
    return js_iter_result(nil, true)
  if !it.global
    it.done = true
    return js_iter_result(res, false)
  ms = js_to_string(jget(res, "0"))
  if ms == ""
    li = js_to_length(jget(it.rx, "lastIndex"))
    js_rx_set_last_index(it.rx, js_rx_advance(it.s, li, it.full) + ~0.0)
  js_iter_result(res, false)

js_install(->(r) js_install_regexp(r))

-> js_install_regexp(r)
  rp = js_new_object(r.object_proto)
  rc = r.constructor("RegExp", 2, ->(this, args, nt) js_regexp_ctor(args, nt), rp)
  r.getter(rc, SYM_SPECIES, ->(this, args, nt) this)
  ex = r.method(rp, "exec", 1, ->(this, args, nt) js_regexp_builtin_exec(this, js_to_string(js_arg(args, 0))))
  r.set_intrinsic("%RegExpProto_exec%", ex)
  r.method(rp, "test", 1, ->(this, args, nt) js_regexp_test(this, js_arg(args, 0)))
  r.method(rp, "toString", 0, ->(this, args, nt) js_regexp_to_string(this))
  r.method(rp, "compile", 2, ->(this, args, nt) js_regexp_compile(this, js_arg(args, 0), js_arg(args, 1)))
  r.getter(rp, "flags", ->(this, args, nt) js_regexp_flags(this))
  r.getter(rp, "source", ->(this, args, nt) js_regexp_source(this))
  fls = [["hasIndices", "d"], ["global", "g"], ["ignoreCase", "i"], ["multiline", "m"], ["dotAll", "s"], ["unicode", "u"], ["unicodeSets", "v"], ["sticky", "y"]]
  i = 0
  while i < fls.size
    js_install_rx_flag(r, rp, fls[i][0], fls[i][1])
    i += 1
  r.method(rp, SYM_MATCH, 1, ->(this, args, nt) js_regexp_match(this, js_arg(args, 0)))
  r.method(rp, SYM_MATCH_ALL, 1, ->(this, args, nt) js_regexp_match_all(this, js_arg(args, 0)))
  r.method(rp, SYM_REPLACE, 2, ->(this, args, nt) js_regexp_replace(this, js_arg(args, 0), js_arg(args, 1)))
  r.method(rp, SYM_SEARCH, 1, ->(this, args, nt) js_regexp_search(this, js_arg(args, 0)))
  r.method(rp, SYM_SPLIT, 2, ->(this, args, nt) js_regexp_split(this, js_arg(args, 0), js_arg(args, 1)))
  ip = r.intrinsics["%IteratorPrototype%"]
  sip = js_new_object(ip == nil ? r.object_proto : ip)
  r.set_intrinsic("%RegExpStringIteratorPrototype%", sip)
  r.method(sip, "next", 0, ->(this, args, nt) js_regexp_string_iter_next(this))
  sip.define(SYM_TO_STRING_TAG, "RegExp String Iterator", ATTR_C)
  r.method(rc, "escape", 1, ->(this, args, nt) js_regexp_escape(js_arg(args, 0)))
  nil

-> js_regexp_compile(o, pat, fl)
  js_this_rx(o, "compile")
  if js_internal(pat).is_a?(JS:Regex)
    js_throw_type("Invalid flags supplied to RegExp constructor") if fl != nil
    return js_regexp_init(o, pat.internal.source, pat.internal.flags)
  js_regexp_init(o, pat == nil ? "" : js_to_string(pat), fl == nil ? "" : js_to_string(fl))

-> js_install_rx_flag(r, rp, name, f)
  r.getter(rp, name, ->(this, args, nt) js_regexp_flag_getter(this, f, name))

-> js_regexp_escape(v)
  js_throw_type("RegExp.escape requires a string") if !js_string?(v)
  sb = StringBuffer()
  u = js_units(v)
  i = 0
  while i < u.size
    c = u[i]
    if i == 0 && ((c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122))
      sb.append("\\x" + JS_DIGITS36.slice(c >> 4, 1) + JS_DIGITS36.slice(c & 15, 1))
    elsif js_rx_syntax_char?(c)
      sb.append("\\" + js_cp_str(c))
    elsif c < 128 && ",-=<>#&!%:;@~'`\"".index(js_cp_str(c)) != nil
      sb.append("\\x" + JS_DIGITS36.slice(c >> 4, 1) + JS_DIGITS36.slice(c & 15, 1))
    elsif c == 32
      sb.append("\\x20")
    else
      sb.append(js_from_units([c]))
    i += 1
  sb.to_s
