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
RX_STRSET = 20

+ RxNode
  rw :kind, :nxt, :c, :str, :alts, :body, :min, :max, :greedy, :group, :ranges, :neg, :ahead, :negate_look, :name, :props, :mflags
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
    @mflags = -1

+ Regex
  rw :source, :flags, :prog, :ngroups, :names, :icase, :multiline, :dotall, :unicode, :sticky, :global, :has_indices, :first_char, :vmode, :jit_fp, :jit_tried, :rep_lo, :rep_hi, :legacy_ok, :has_mods, :has_dup_names

-> js_rx_syntax(msg, src)
  js_throw_syntax("Invalid regular expression: /" + src + "/: " + msg)

# ---- parser: pattern units/code points → node fragments ----

+ RxParser
  rw :ngroups, :names, :has_mods, :has_dup_names

  -> new(@src, @u, @flags)
    @unicode = @flags.index("u") != nil || @flags.index("v") != nil
    @vmode = @flags.index("v") != nil
    @icase = @flags.index("i") != nil
    @multiline = @flags.index("m") != nil
    @dotall = @flags.index("s") != nil
    @has_mods = false
    @has_dup_names = false
    @p = @unicode ? js_rx_codepoints(@src) : js_units(@src)
    @i = 0
    @n = @p.size
    @ngroups = 0
    @names = []
    @group_names = {}
    @cur_names = {}
    @backref_names = []
    @max_backref = 0
    @has_named = js_rx_has_named(@src)
    @dir = 1

  -> cur_mflags
    (@icase ? 1 : 0) | (@multiline ? 2 : 0) | (@dotall ? 4 : 0)

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
    outer = @cur_names
    @cur_names = outer.dup
    alts = [alternative()]
    branch_union = {}
    @cur_names.keys.each ->(k) branch_union[k] = true if !outer.has_key?(k)
    while eat(124)
      @cur_names = outer.dup
      alts.push(alternative())
      @cur_names.keys.each ->(k) branch_union[k] = true if !outer.has_key?(k)
    branch_union.keys.each ->(k) outer[k] = true
    @cur_names = outer
    return alts[0] if alts.size == 1
    node = JS:RxNode.new(RX_ALT)
    join = JS:RxNode.new(RX_EMPTY)
    node.alts = alts.map(->(a) js_rx_link(a, join))
    [node, join]

  -> alternative
    terms = []
    while @i < @n && peek() != 124 && peek() != 41
      t = term()
      terms.push(t) if t != nil
    if terms.size == 0
      e = JS:RxNode.new(RX_EMPTY)
      return [e, e]
    if @dir == 1
      k = 0
      while k + 1 < terms.size
        terms[k][1].nxt = terms[k + 1][0]
        k += 1
      return [terms[0][0], terms[terms.size - 1][1]]
    # Right-to-left (lookbehind): link terms from last to first!
    k = terms.size - 1
    while k > 0
      terms[k][1].nxt = terms[k - 1][0]
      k -= 1
    [terms[terms.size - 1][0], terms[0][1]]

  -> term
    c = peek()
    if c == 94
      @i += 1
      n = JS:RxNode.new(RX_BOL)
      n.mflags = cur_mflags()
      return [n, n]
    if c == 36
      @i += 1
      n = JS:RxNode.new(RX_EOL)
      n.mflags = cur_mflags()
      return [n, n]
    if c == 92 && (peek_at(1) == 98 || peek_at(1) == 66)
      @i += 2
      n = JS:RxNode.new(peek_at(-1) == 98 ? RX_WORDB : RX_NWORDB)
      n.mflags = cur_mflags()
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
      saved_dir = @dir
      @dir = behind ? -1 : 1
      d = disjunction()
      @dir = saved_dir
      fail("Unterminated group") if !eat(41)
      n = JS:RxNode.new(RX_LOOK)
      n.ahead = !behind
      n.negate_look = negl
      fin = JS:RxNode.new(RX_MATCH)
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
    if a[0] == a[1] && (head.kind == RX_CHAR || head.kind == RX_ANY || head.kind == RX_CLASS || head.kind == RX_STRSET)
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
      n.mflags = cur_mflags()
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
          fail("Duplicate capture group name") if @cur_names.has_key?(nm)
          @has_dup_names = true if @group_names.has_key?(nm)
          @ngroups += 1
          g = @ngroups
          @group_names[nm] = true
          @cur_names[nm] = true
          @names.push([nm, g])
          return group(g, nm)
        # RegExp modifiers: (?ims-ims:...)
        add_m = 0
        rem_m = 0
        while true
          mc = peek()
          if mc == 105
            fail("Duplicate modifier flag") if (add_m & 1) != 0
            add_m = add_m | 1
            @i += 1
          elsif mc == 109
            fail("Duplicate modifier flag") if (add_m & 2) != 0
            add_m = add_m | 2
            @i += 1
          elsif mc == 115
            fail("Duplicate modifier flag") if (add_m & 4) != 0
            add_m = add_m | 4
            @i += 1
          else
            break
        if eat(45)
          while true
            mc = peek()
            if mc == 105
              fail("Duplicate modifier flag") if ((add_m | rem_m) & 1) != 0
              rem_m = rem_m | 1
              @i += 1
            elsif mc == 109
              fail("Duplicate modifier flag") if ((add_m | rem_m) & 2) != 0
              rem_m = rem_m | 2
              @i += 1
            elsif mc == 115
              fail("Duplicate modifier flag") if ((add_m | rem_m) & 4) != 0
              rem_m = rem_m | 4
              @i += 1
            else
              break
        if (add_m | rem_m) != 0 && eat(58)
          sav_i = @icase
          sav_m = @multiline
          sav_s = @dotall
          @icase = true if (add_m & 1) != 0
          @icase = false if (rem_m & 1) != 0
          @multiline = true if (add_m & 2) != 0
          @multiline = false if (rem_m & 2) != 0
          @dotall = true if (add_m & 4) != 0
          @dotall = false if (rem_m & 4) != 0
          @has_mods = true
          d = disjunction()
          @icase = sav_i
          @multiline = sav_m
          @dotall = sav_s
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
    if @dir == 1
      o.nxt = d[0]
      d[1].nxt = cl
      return [o, cl]
    # Lookbehind: enter group from the right (CLOSE) and exit on the left (OPEN).
    cl.nxt = d[0]
    d[1].nxt = o
    [cl, o]

  -> group_name
    sb = []
    while @i < @n && @p[@i] != 62
      c = @p[@i]
      if c == 92
        fail("Invalid capture group name") if peek_at(1) != 117
        @i += 2
        cp = unicode_escape_value(true)
        fail("Invalid capture group name") if cp >= 0xD800 && cp <= 0xDFFF
        sb.push(cp)
      else
        if !@unicode && c >= 0xD800 && c <= 0xDBFF && @i + 1 < @n && @p[@i + 1] >= 0xDC00 && @p[@i + 1] <= 0xDFFF
          cp = 0x10000 + ((c - 0xD800) << 10) + (@p[@i + 1] - 0xDC00)
          sb.push(cp)
          @i += 2
        else
          fail("Invalid capture group name") if c >= 0xD800 && c <= 0xDFFF
          sb.push(c)
          @i += 1
    fail("Invalid capture group name") if !eat(62) || sb.size == 0
    # Validate RegExpIdentifierName: RegExpIdentifierStart RegExpIdentifierPart*
    c0 = sb[0]
    ok0 = c0 == 36 || c0 == 95 || (c0 >= 65 && c0 <= 90) || (c0 >= 97 && c0 <= 122) || (c0 >= 128 && js_rx_is_id_start?(c0))
    fail("Invalid capture group name") if !ok0
    k = 1
    while k < sb.size
      ck = sb[k]
      okk = ck == 36 || ck == 95 || ck == 0x200C || ck == 0x200D || (ck >= 48 && ck <= 57) || (ck >= 65 && ck <= 90) || (ck >= 97 && ck <= 122) || (ck >= 128 && js_rx_is_id_continue?(ck))
      fail("Invalid capture group name") if !okk
      k += 1
    js_from_units(js_rx_to_units(sb, true))

  -> char_node(c)
    n = JS:RxNode.new(RX_CHAR)
    n.c = c
    n.mflags = cur_mflags()
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
        n.mflags = cur_mflags()
        return [n, n]
      @i = save
      if c >= 56
        @i += 1
        return char_node(c)
      return char_node(legacy_octal())
    if c == 107 && (@unicode || @has_named)
      @i += 1
      fail("Invalid named reference") if !eat(60)
      nm = group_name()
      @backref_names.push(nm)
      n = JS:RxNode.new(RX_BACKREF)
      n.name = nm
      n.mflags = cur_mflags()
      return [n, n]
    cls = class_escape()
    if cls != nil
      res = rx_make_class_escape_node(cls, @icase, @unicode, @vmode)
      res[0].mflags = cur_mflags()
      return res
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

  # \d \D \w \W \s \S \p{..} \P{..}:
  # Returns [:ranges, flat_ranges, negated] or [:strings, flat_ranges, strs_arr] or nil.
  -> class_escape
    c = peek()
    if c == 100 || c == 68
      @i += 1
      return [:ranges, [48, 57], c == 68]
    if c == 119 || c == 87
      @i += 1
      r = [48, 57, 65, 90, 95, 95, 97, 122]
      if @icase && @unicode
        r = [48, 57, 65, 90, 95, 95, 97, 122, 0x017F, 0x017F, 0x212A, 0x212A]
      return [:ranges, r, c == 87]
    if c == 115 || c == 83
      @i += 1
      return [:ranges, js_rx_space_ranges(), c == 83]
    if (c == 112 || c == 80) && @unicode
      neg = c == 80
      @i += 1
      fail("Invalid property name") if !eat(123)
      st = @i
      while @i < @n && @p[@i] != 125
        @i += 1
      fail("Invalid property name") if !eat(125)
      spec = js_from_units(js_arr_copy(@p, st, @i - 1 - st))
      res = js_rx_lookup_prop(spec, @vmode)
      fail("Invalid property name") if res == nil
      if res[0] == :strings
        fail("Cannot negate property of strings") if neg
        return res
      return [:ranges, res[1], neg]
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
      if @unicode && !js_rx_syntax_char?(c)
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
    if @vmode
      cs = parse_v_class_contents(neg)
      fail("Unterminated character class") if !eat(93)
      res = rx_charset_to_node(cs, @icase)
      res[0].mflags = cur_mflags()
      return res
    ranges = []
    max_cp = @unicode ? 0x10FFFF : 0xFFFF
    while @i < @n && peek() != 93
      a = class_atom(ranges, max_cp)
      if peek() == 45 && peek_at(1) != 93 && peek_at(1) != -1
        @i += 1
        b = class_atom(ranges, max_cp)
        if a < 0 || b < 0
          fail("Invalid character class") if @unicode
          if a >= 0
            ranges.push(a)
            ranges.push(a)
          ranges.push(45)
          ranges.push(45)
          if b >= 0
            ranges.push(b)
            ranges.push(b)
        else
          fail("Range out of order in character class") if b < a
          ranges.push(a)
          ranges.push(b)
      elsif a >= 0
        ranges.push(a)
        ranges.push(a)
    fail("Unterminated character class") if !eat(93)
    n = JS:RxNode.new(RX_CLASS)
    n.ranges = rx_r_normalize_flat(ranges)
    n.neg = neg
    n.props = nil
    n.mflags = cur_mflags()
    [n, n]

  # One non-v class atom: a code point, or -1 when it added a class escape to flat ranges.
  -> class_atom(ranges, max_cp)
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
        rs = cls[1]
        rs = rx_r_complement(rs, max_cp) if cls[2]
        k = 0
        while k < rs.size
          ranges.push(rs[k])
          k += 1
        return -1
      if d == 107 && !@unicode
        @i += 1
        return 107
      return char_escape()
    @i += 1
    c

  # ---- ES2024 v-flag ClassSetExpression parser ----
  # A v-mode CharSet is [flat_ranges, strings_arr, may_have_strings].

  -> parse_v_class_contents(neg)
    if peek() == 93
      return neg ? [[0, 0x10FFFF], [], false] : [[], [], false]
    first = parse_v_item_or_range()
    cs = first[0]
    was_range = first[1]
    if !was_range && peek() == 38 && peek_at(1) == 38
      while peek() == 38 && peek_at(1) == 38
        @i += 2
        rhs = parse_v_operand()
        cs = rx_cs_intersect(cs, rhs)
      fail("Invalid set operation in character class") if peek() != 93
    elsif !was_range && peek() == 45 && peek_at(1) == 45
      while peek() == 45 && peek_at(1) == 45
        @i += 2
        rhs = parse_v_operand()
        cs = rx_cs_subtract(cs, rhs)
      fail("Invalid set operation in character class") if peek() != 93
    else
      while peek() != 93 && peek() != -1
        fail("Invalid set operation in character class") if (peek() == 38 && peek_at(1) == 38) || (peek() == 45 && peek_at(1) == 45)
        nxt = parse_v_item_or_range()
        cs = rx_cs_union(cs, nxt[0])
    if neg
      fail("Negated character class may not contain strings") if cs[2] || cs[1].size > 0
      return [rx_r_complement(cs[0], 0x10FFFF), [], false]
    cs

  # Returns [cs, is_range]
  -> parse_v_item_or_range
    c = peek()
    if c == 91
      return [parse_v_nested(), false]
    if c == 92
      d = peek_at(1)
      if d == 113
        return [parse_v_q_string(), false]
      if d == 100 || d == 68 || d == 119 || d == 87 || d == 115 || d == 83 || d == 112 || d == 80
        return [parse_v_class_escape(), false]
    a = parse_v_char()
    if peek() == 45 && peek_at(1) != 45
      @i += 1
      b = parse_v_char()
      fail("Range out of order in character class") if b < a
      r = [a, b]
      r = rx_r_case_fold(r, true) if @icase
      return [[r, [], false], true]
    r = [a, a]
    r = rx_r_case_fold(r, true) if @icase
    [[r, [], false], false]

  # ClassSetOperand (no ranges allowed)
  -> parse_v_operand
    c = peek()
    fail("Invalid character class") if c == -1 || c == 93
    if c == 91
      return parse_v_nested()
    if c == 92
      d = peek_at(1)
      if d == 113
        return parse_v_q_string()
      if d == 100 || d == 68 || d == 119 || d == 87 || d == 115 || d == 83 || d == 112 || d == 80
        return parse_v_class_escape()
    a = parse_v_char()
    r = [a, a]
    r = rx_r_case_fold(r, true) if @icase
    [r, [], false]

  -> parse_v_nested
    @i += 1
    sub_neg = eat(94)
    cs = parse_v_class_contents(sub_neg)
    fail("Unterminated character class") if !eat(93)
    cs

  -> parse_v_class_escape
    @i += 1
    cls = class_escape()
    fail("Invalid escape") if cls == nil
    if cls[0] == :strings
      rs = cls[1]
      ss = cls[2]
      if @icase
        rs = rx_r_case_fold(rs, true)
        ss = rx_s_case_fold(ss)
      return [rs, ss, true]
    rs = cls[1]
    rs = rx_r_case_fold(rs, true) if @icase
    rs = rx_r_complement(rs, 0x10FFFF) if cls[2]
    [rs, [], false]

  # \q{ alt1 | alt2 | ... }
  -> parse_v_q_string
    @i += 2
    fail("Invalid \\q escape") if !eat(123)
    ranges = []
    strs = []
    mhs = false
    while true
      cps = []
      while @i < @n && peek() != 124 && peek() != 125
        cps.push(parse_v_char())
      if @icase
        k = 0
        while k < cps.size
          cps[k] = js_rx_canon(cps[k], true)
          k += 1
      if cps.size == 1
        ranges.push(cps[0])
        ranges.push(cps[0])
      else
        mhs = true
        strs.push(cps)
      break if !eat(124)
    fail("Unterminated \\q escape") if !eat(125)
    rn = rx_r_normalize_flat(ranges)
    rn = rx_r_case_fold(rn, true) if @icase
    [rn, rx_s_dedup(strs), mhs]

  # Parse a single v-mode ClassSetCharacter (escaping allowed; syntax chars and double punctuators rejected).
  -> parse_v_char
    c = peek()
    fail("Unterminated character class") if c < 0
    if c == 92
      @i += 1
      fail("\\ at end of pattern") if @i >= @n
      d = peek()
      if d == 98
        @i += 1
        return 8
      if d == 116
        @i += 1
        return 9
      if d == 110
        @i += 1
        return 10
      if d == 118
        @i += 1
        return 11
      if d == 102
        @i += 1
        return 12
      if d == 114
        @i += 1
        return 13
      if d == 48
        @i += 1
        fail("Invalid decimal escape") if peek() >= 48 && peek() <= 57
        return 0
      if d == 99
        @i += 1
        e = peek()
        fail("Invalid control escape") if !((e >= 65 && e <= 90) || (e >= 97 && e <= 122))
        @i += 1
        return e % 32
      if d == 120
        @i += 1
        h1 = js_rx_hex(peek())
        h2 = js_rx_hex(peek_at(1))
        fail("Invalid hex escape") if h1 < 0 || h2 < 0
        @i += 2
        return h1 * 16 + h2
      if d == 117
        @i += 1
        return unicode_escape_value(false)
      if rx_v_class_punct?(d)
        @i += 1
        return d
      fail("Invalid escape in character class")
    fail("Invalid syntax character in character class") if rx_v_syntax_char?(c)
    fail("Invalid reserved double punctuator in character class") if rx_v_double_punct?(c) && peek_at(1) == c
    @i += 1
    c

-> rx_v_syntax_char?(c)
  c == 40 || c == 41 || c == 91 || c == 93 || c == 123 || c == 125 || c == 47 || c == 45 || c == 92 || c == 124

-> rx_v_double_punct?(c)
  c == 38 || c == 33 || c == 35 || c == 36 || c == 37 || c == 42 || c == 43 || c == 44 || c == 46 || c == 58 || c == 59 || c == 60 || c == 61 || c == 62 || c == 63 || c == 64 || c == 94 || c == 96 || c == 126

-> rx_v_class_punct?(c)
  rx_v_syntax_char?(c) || rx_v_double_punct?(c)

-> rx_s_key(seq)
  sb = StringBuffer()
  k = 0
  while k < seq.size
    sb.append(",") if k > 0
    sb.append(seq[k].to_s)
    k += 1
  r = sb.to_s
  ccall("w_value_free_w", sb)
  r

-> rx_s_dedup(strs)
  return [] if strs.size == 0
  seen = {}
  out = []
  k = 0
  while k < strs.size
    key = rx_s_key(strs[k])
    if !seen.has_key?(key)
      seen[key] = true
      out.push(strs[k])
    k += 1
  out

-> rx_s_case_fold(strs)
  return [] if strs.size == 0
  out = []
  k = 0
  while k < strs.size
    s = strs[k]
    f = []
    j = 0
    while j < s.size
      f.push(js_rx_canon(s[j], true))
      j += 1
    out.push(f)
    k += 1
  rx_s_dedup(out)

-> rx_cs_union(a, b)
  r = rx_r_union(a[0], b[0])
  sa = a[1]
  sb = b[1]
  s = sa.size == 0 ? sb : (sb.size == 0 ? sa : rx_s_dedup(sa + sb))
  [r, s, a[2] || b[2]]

-> rx_cs_intersect(a, b)
  r = rx_r_intersect(a[0], b[0])
  sa = a[1]
  sb = b[1]
  s = []
  if sa.size > 0 && sb.size > 0
    h = {}
    k = 0
    while k < sb.size
      h[rx_s_key(sb[k])] = true
      k += 1
    k = 0
    while k < sa.size
      s.push(sa[k]) if h.has_key?(rx_s_key(sa[k]))
      k += 1
  [r, s, a[2] && b[2]]

-> rx_cs_subtract(a, b)
  r = rx_r_subtract(a[0], b[0])
  sa = a[1]
  sb = b[1]
  s = sa
  if sa.size > 0 && sb.size > 0
    h = {}
    k = 0
    while k < sb.size
      h[rx_s_key(sb[k])] = true
      k += 1
    s = []
    k = 0
    while k < sa.size
      s.push(sa[k]) if !h.has_key?(rx_s_key(sa[k]))
      k += 1
  [r, s, a[2]]

# Build an RX_CLASS (when no strings) or O(1)-indexed RX_STRSET (when strings present).
-> rx_charset_to_node(cs, icase)
  rs = cs[0]
  ss = cs[1]
  if ss.size == 0
    n = JS:RxNode.new(RX_CLASS)
    n.ranges = rs
    n.neg = false
    n.props = nil
    return [n, n]
  has_empty = false
  non_empty = []
  k = 0
  while k < ss.size
    if ss[k].size == 0
      has_empty = true
    else
      non_empty.push(ss[k])
    k += 1
  # Sort non-empty strings longest-first (ES2024 CharacterSetMatcher requires longest match first!)
  rx_sort_seqs_desc(non_empty)
  by_first = {}
  by_last = {}
  k = 0
  while k < non_empty.size
    seq = non_empty[k]
    f0 = icase ? js_rx_canon(seq[0], true) : seq[0]
    lst = by_first[f0]
    if lst == nil
      by_first[f0] = [seq]
    else
      lst.push(seq)
    l0 = icase ? js_rx_canon(seq[seq.size - 1], true) : seq[seq.size - 1]
    llst = by_last[l0]
    if llst == nil
      by_last[l0] = [seq]
    else
      llst.push(seq)
    k += 1
  n = JS:RxNode.new(RX_STRSET)
  n.ranges = rs
  n.str = [by_first, by_last, has_empty]
  [n, n]

-> rx_sort_seqs_desc(a)
  n = a.size
  return nil if n <= 1
  # Bucket sort by length (emoji sequences have length 2..15)
  max_len = 0
  k = 0
  while k < n
    max_len = a[k].size if a[k].size > max_len
    k += 1
  buckets = Array.new(max_len + 1, nil)
  k = 0
  while k < n
    l = a[k].size
    b = buckets[l]
    if b == nil
      buckets[l] = [a[k]]
    else
      b.push(a[k])
    k += 1
  out_i = 0
  l = max_len
  while l >= 0
    b = buckets[l]
    if b != nil
      j = 0
      while j < b.size
        a[out_i] = b[j]
        out_i += 1
        j += 1
    l -= 1
  nil

-> rx_make_class_escape_node(cls, icase, unicode, vmode)
  if cls[0] == :strings
    rs = cls[1]
    ss = cls[2]
    if icase
      rs = rx_r_case_fold(rs, true)
      ss = rx_s_case_fold(ss)
    return rx_charset_to_node([rs, ss, true], icase)
  rs = cls[1]
  neg = cls[2]
  if vmode
    rs = rx_r_case_fold(rs, true) if icase
    rs = rx_r_complement(rs, 0x10FFFF) if neg
    n = JS:RxNode.new(RX_CLASS)
    n.ranges = rs
    n.neg = false
    n.props = nil
    return [n, n]
  if neg
    # Stand-alone negated escape (\D \W \S \P{...}): in /iu mode, complement BEFORE case folding!
    n = JS:RxNode.new(RX_CLASS)
    n.ranges = rx_r_complement(rs, unicode ? 0x10FFFF : 0xFFFF)
    n.neg = false
    n.props = nil
    return [n, n]
  n = JS:RxNode.new(RX_CLASS)
  n.ranges = rs
  n.neg = false
  n.props = nil
  [n, n]

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
  [9, 13, 32, 32, 0xA0, 0xA0, 0x1680, 0x1680, 0x2000, 0x200A, 0x2028, 0x2029, 0x202F, 0x202F, 0x205F, 0x205F, 0x3000, 0x3000, 0xFEFF, 0xFEFF]

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
  rx.has_mods = p.has_mods
  rx.has_dup_names = p.has_dup_names
  rx.first_char = (!rx.has_mods && rx.prog.kind == RX_CHAR && !rx.icase) ? rx.prog.c : -1
  rx.jit_fp = 0
  rx.jit_tried = rx.has_mods || rx.has_dup_names
  rx.rep_lo = -1
  rx.rep_hi = -1
  rx.legacy_ok = true
  # Detect single-range greedy `+` pattern (e.g. /\d+/g, /[a-z]+/g) for single-pass native replace!
  if !rx.has_mods && !rx.icase && !rx.unicode && !rx.sticky && rx.prog.kind == RX_REP1 && rx.prog.min == 1 && rx.prog.max == -1 && rx.prog.greedy && rx.prog.nxt != nil && rx.prog.nxt.kind == RX_MATCH
    rb = rx.prog.body
    if rb.kind == RX_CLASS && !rb.neg && rb.props == nil && rb.ranges.size == 2 && rb.ranges[0] >= 0 && rb.ranges[1] < 128
      rx.rep_lo = rb.ranges[0]
      rx.rep_hi = rb.ranges[1]
    elsif rb.kind == RX_CHAR && rb.c >= 0 && rb.c < 128
      rx.rep_lo = rb.c
      rx.rep_hi = rb.c
  JS_RX_CACHE[key] = rx if JS_RX_CACHE.size < 2000
  rx

-> js_rx_ensure_jit(rx)
  if !rx.jit_tried
    rx.jit_tried = true
    rx.jit_fp = rx_jit_compile(rx)
  rx.jit_fp

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
    @icase = @rx.icase
    @uni = @rx.unicode
    @multi = @rx.multiline
    @dotall = @rx.dotall
    @steps = 0
    @w = 1
    @dir = 1

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

  -> node_icase(n)
    n.mflags >= 0 ? ((n.mflags & 1) != 0) : @icase

  -> node_multi(n)
    n.mflags >= 0 ? ((n.mflags & 2) != 0) : @multi

  -> node_dotall(n)
    n.mflags >= 0 ? ((n.mflags & 4) != 0) : @dotall

  -> word_at?(i, ic = @icase)
    return false if i < 0 || i >= @len
    c = unit(i)
    w = (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95
    return w if w || !(ic && @uni)
    c == 0x017F || c == 0x212A

  # Does the single-char node n match at i (in current @dir)? Returns width consumed or 0.
  -> char_match(n, i)
    if @dir == 1
      return 0 if i >= @len
      c = cp_at(i)
    else
      return 0 if i <= 0
      c = cp_before(i)
    w = @w
    k = n.kind
    ic = node_icase(n)
    if k == RX_CHAR
      if c == n.c
        return w
      if ic && canon(c) == canon(n.c)
        return w
      return 0
    if k == RX_ANY
      return 0 if !node_dotall(n) && line_term?(c)
      return w
    hit = js_rx_class_has?(n, c, ic, @uni)
    hit = !hit if n.neg
    hit ? w : 0

  # Match a codepoint sequence `seq` starting at i (dir=1) or ending at i (dir=-1).
  # Returns end position or -1.
  -> match_cp_seq(seq, i, ic = @icase)
    sn = seq.size
    if @dir == 1
      pos = i
      k = 0
      while k < sn
        return -1 if pos >= @len
        c = cp_at(pos)
        sc = seq[k]
        if c != sc
          return -1 if !ic || canon(c) != sc
        pos += @w
        k += 1
      return pos
    pos = i
    k = sn - 1
    while k >= 0
      return -1 if pos <= 0
      c = cp_before(pos)
      sc = seq[k]
      if c != sc
        return -1 if !ic || canon(c) != sc
      pos -= @w
      k -= 1
    pos

  # Ordered candidate next-positions for RX_STRSET at position i (longest-first, then 1-cp range, then empty).
  -> strset_matches(n, i, forbid_empty)
    info = n.str
    by_map = @dir == 1 ? info[0] : info[1]
    has_empty = info[2]
    ic = node_icase(n)
    out = []
    if (@dir == 1 && i < @len) || (@dir == -1 && i > 0)
      c0 = @dir == 1 ? cp_at(i) : cp_before(i)
      w0 = @w
      key = ic ? canon(c0) : c0
      cands = by_map[key]
      if cands != nil
        k = 0
        while k < cands.size
          ep = match_cp_seq(cands[k], i, ic)
          out.push(ep) if ep >= 0
          k += 1
      if n.ranges.size > 0 && js_rx_class_has?(n, c0, ic, @uni)
        out.push(i + @dir * w0)
    if has_empty && !forbid_empty
      out.push(i)
    out

  -> run_strset(n, i)
    ends = strset_matches(n, i, false)
    k = 0
    while k < ends.size
      r = run(n.nxt, ends[k])
      return r if r >= 0
      k += 1
    -1

  -> rep_strset(n, i)
    body = n.body
    mn = n.min
    mx = n.max
    stk = [[i, 0, nil, 0, false]]
    if n.greedy
      while stk.size > 0
        @steps += 1
        js_throw_range("Maximum regular expression backtracking exceeded") if @steps > 50000000
        f = stk.last
        pos = f[0]
        cnt = f[1]
        if f[2] == nil
          f[2] = (mx < 0 || cnt < mx) ? strset_matches(body, pos, cnt >= mn) : []
          f[3] = 0
        ends = f[2]
        idx = f[3]
        if idx < ends.size
          f[3] = idx + 1
          stk.push([ends[idx], cnt + 1, nil, 0, false])
        else
          stk.pop
          if cnt >= mn
            r = run(n.nxt, pos)
            return r if r >= 0
      return -1
    while stk.size > 0
      @steps += 1
      js_throw_range("Maximum regular expression backtracking exceeded") if @steps > 50000000
      f = stk.last
      pos = f[0]
      cnt = f[1]
      if !f[4]
        f[4] = true
        if cnt >= mn
          r = run(n.nxt, pos)
          return r if r >= 0
      if f[2] == nil
        f[2] = (mx < 0 || cnt < mx) ? strset_matches(body, pos, cnt >= mn) : []
        f[3] = 0
      ends = f[2]
      idx = f[3]
      if idx < ends.size
        f[3] = idx + 1
        stk.push([ends[idx], cnt + 1, nil, 0, false])
      else
        stk.pop
    -1

  -> run(n, i)
    while true
      @steps += 1
      js_throw_range("Maximum regular expression backtracking exceeded") if @steps > 50000000
      k = n.kind
      if k == RX_CHAR || k == RX_ANY || k == RX_CLASS
        w = char_match(n, i)
        return -1 if w == 0
        i += @dir * w
        n = n.nxt
      elsif k == RX_EMPTY
        n = n.nxt
      elsif k == RX_MATCH
        return i
      elsif k == RX_STR
        if @dir == 1
          return -1 if !str_at(n.str, i)
          i += n.str.size
        else
          return -1 if i < n.str.size || !str_at(n.str, i - n.str.size)
          i -= n.str.size
        n = n.nxt
      elsif k == RX_STRSET
        return run_strset(n, i)
      elsif k == RX_OPEN
        g = n.group * 2
        if @dir == 1
          old = @caps[g]
          olde = @caps[g + 1]
          @caps[g] = i
          r = run(n.nxt, i)
          if r < 0
            @caps[g] = old
            @caps[g + 1] = olde
          return r
        old = @caps[g]
        @caps[g] = i
        r = run(n.nxt, i)
        @caps[g] = old if r < 0
        return r
      elsif k == RX_CLOSE
        g = n.group * 2
        if @dir == 1
          old = @caps[g + 1]
          @caps[g + 1] = i
          r = run(n.nxt, i)
          @caps[g + 1] = old if r < 0
          return r
        old = @caps[g]
        olde = @caps[g + 1]
        @caps[g] = -1
        @caps[g + 1] = i
        r = run(n.nxt, i)
        if r < 0
          @caps[g] = old
          @caps[g + 1] = olde
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
        return rep_strset(n, i) if n.body.kind == RX_STRSET
        return rep1(n, i)
      elsif k == RX_REP
        return rep_enter(n, i)
      elsif k == RX_REP_TAIL
        return rep_tail(n, i)
      elsif k == RX_BOL
        if i != 0
          return -1 if !node_multi(n) || !line_term?(unit(i - 1))
        n = n.nxt
      elsif k == RX_EOL
        if i != @len
          return -1 if !node_multi(n) || !line_term?(unit(i))
        n = n.nxt
      elsif k == RX_WORDB || k == RX_NWORDB
        ic = node_icase(n)
        b = word_at?(i - 1, ic) != word_at?(i, ic)
        return -1 if b != (k == RX_WORDB)
        n = n.nxt
      elsif k == RX_BACKREF
        r = backref(n, i)
        return -1 if r < 0
        i = r
        n = n.nxt
      elsif k == RX_LOOK
        return look(n, i)
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

  # Greedy/lazy repeat of a one-character node: O(1) memory, zero position-array allocation!
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
        pos += @dir * w
        cnt += 1
      return -1
    pos = i
    cnt = 0
    while mx < 0 || cnt < mx
      w = char_match(body, pos)
      break if w == 0
      pos += @dir * w
      cnt += 1
    return -1 if cnt < n.min
    while cnt >= n.min
      r = run(n.nxt, pos)
      return r if r >= 0
      break if cnt == n.min
      # Step back one code point/unit toward i in O(1) space!
      if @dir == 1
        step = 1
        if @uni && pos - 2 >= i
          lo = unit(pos - 1)
          if lo >= 0xDC00 && lo <= 0xDFFF
            hi = unit(pos - 2)
            step = 2 if hi >= 0xD800 && hi <= 0xDBFF
        pos -= step
      else
        step = 1
        if @uni && pos + 2 <= i
          hi = unit(pos)
          if hi >= 0xD800 && hi <= 0xDBFF
            lo = unit(pos + 1)
            step = 2 if lo >= 0xDC00 && lo <= 0xDFFF
        pos += step
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
        g = pr[1] if pr[0] == n.name && @caps[pr[1] * 2 + 1] >= 0 && @caps[pr[1] * 2] >= 0
      if g == 0
        @rx.names.each ->(pr)
          g = pr[1] if pr[0] == n.name && g == 0
    s = @caps[g * 2]
    e = @caps[g * 2 + 1]
    return i if s < 0 || e < 0
    l = e - s
    if @dir == 1
      return -1 if i + l > @len
      dst = i
    else
      return -1 if i - l < 0
      dst = i - l
    if @uni && l > 0
      # Backreference in /u or /v mode cannot split a surrogate pair in the input!
      if dst > 0
        u_first = unit(dst)
        if u_first >= 0xDC00 && u_first <= 0xDFFF
          u_prev = unit(dst - 1)
          return -1 if u_prev >= 0xD800 && u_prev <= 0xDBFF
      if dst + l < @len
        u_last = unit(dst + l - 1)
        if u_last >= 0xD800 && u_last <= 0xDBFF
          u_next = unit(dst + l)
          return -1 if u_next >= 0xDC00 && u_next <= 0xDFFF
    ic = node_icase(n)
    if ic && @uni
      # Compare code point by code point in /iu or /iv mode!
      ps = s
      pd = dst
      while ps < e
        return -1 if pd >= dst + l
        cs = cp_at(ps)
        ws = @w
        cd = cp_at(pd)
        wd = @w
        return -1 if cs != cd && canon(cs) != canon(cd)
        ps += ws
        pd += wd
      return -1 if pd != dst + l
      return @dir == 1 ? i + l : i - l
    k = 0
    while k < l
      a = unit(s + k)
      b = unit(dst + k)
      if a != b
        return -1 if !ic || canon(a) != canon(b)
      k += 1
    @dir == 1 ? i + l : i - l

  -> look(n, i)
    saved = @caps.map(->(x) x)
    saved_loops = @loops
    saved_dir = @dir
    @loops = []
    @dir = n.ahead ? 1 : -1
    r = run(n.body, i)
    @loops = saved_loops
    @dir = saved_dir
    ok = r >= 0
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
    @loops.clear
    @dir = 1
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

-> js_rx_class_has?(n, c, icase, uni)
  return true if rx_r_has?(n.ranges, c)
  if icase
    eq = js_rx_case_equiv(c, uni)
    if eq != nil
      k = 0
      while k < eq.size
        return true if rx_r_has?(n.ranges, eq[k])
        k += 1
  false

# Search s from unit index start; [match_start, matcher] or nil.
-> js_rx_search(rx, s, start, sticky)
  m = JS:RxMatcher.new(rx, s)
  n = m.len
  i = start
  fc = rx.first_char
  ascii = js_ascii?(s)
  uni = rx.unicode
  while i <= n
    if fc >= 0 && !sticky && fc < 128 && ascii
      j = s.index(fc.chr, i)
      return nil if j == nil
      i = j
    r = m.match_at(i)
    return [i, m] if r >= 0
    return nil if sticky
    if uni && !ascii && i + 1 < n
      c = m.unit(i)
      if c >= 0xD800 && c <= 0xDBFF
        d = m.unit(i + 1)
        if d >= 0xDC00 && d <= 0xDFFF
          i += 2
          next
    i += 1
  nil

# ---- the RegExp builtin ----

-> js_rx_clone_nolegacy(rx)
  nr = JS:Regex.new
  nr.source = rx.source
  nr.flags = rx.flags
  nr.prog = rx.prog
  nr.ngroups = rx.ngroups
  nr.names = rx.names
  nr.icase = rx.icase
  nr.multiline = rx.multiline
  nr.dotall = rx.dotall
  nr.unicode = rx.unicode
  nr.sticky = rx.sticky
  nr.global = rx.global
  nr.has_indices = rx.has_indices
  nr.first_char = rx.first_char
  nr.vmode = rx.vmode
  nr.jit_fp = rx.jit_fp
  nr.jit_tried = rx.jit_tried
  nr.rep_lo = rx.rep_lo
  nr.rep_hi = rx.rep_hi
  nr.has_mods = rx.has_mods
  nr.has_dup_names = rx.has_dup_names
  nr.legacy_ok = false
  nr

-> js_regexp_alloc(proto)
  r = js_realm()
  if proto == r.regexp_proto && r.regexp_shape != nil
    o = JS:Special.new(r.regexp_shape, "RegExp")
    o.s0 = ~0.0
    return o
  o = js_new_special(proto, "RegExp")
  o.define("lastIndex", ~0.0, ATTR_W)
  o

-> js_regexp_from_rx(rx)
  r = js_realm()
  o = JS:Special.new(r.regexp_shape, "RegExp")
  o.internal = rx
  o.s0 = ~0.0
  o

-> js_regexp_init(o, pattern, flags, legacy_ok = true)
  rx = js_rx_compile(pattern, flags)
  rx = js_rx_clone_nolegacy(rx) if !legacy_ok
  o.internal = rx
  ok = jset(o, "lastIndex", ~0.0)
  js_throw_type("Cannot assign to read only property 'lastIndex'") if !ok
  o

JS_RX_REALM = {}

# A regex literal: a fresh object each evaluation, sharing the compiled program.
-> js_regexp_create(pattern, flags)
  r = js_realm()
  rx = js_rx_compile(pattern, flags)
  if r.regexp_shape != nil
    o = JS:Special.new(r.regexp_shape, "RegExp")
    o.internal = rx
    o.s0 = ~0.0
    JS_RX_REALM[(wvalue_bits(o) ## i64) & 140737488355312] = r if JS_MULTI_REALM[0]
    return o
  o = js_regexp_alloc(r.intrinsic("RegExp.prototype"))
  o.internal = rx
  JS_RX_REALM[(wvalue_bits(o) ## i64) & 140737488355312] = r if JS_MULTI_REALM[0]
  o

-> js_regexp_ctor(args, nt)
  r = js_realm()
  rc = r.intrinsic("RegExp")
  pat = js_arg(args, 0)
  fl = js_arg(args, 1)
  pattern_is_re = js_is_regexp?(pat)
  if nt == nil
    nt = rc
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
  JS_RX_REALM[(wvalue_bits(o) ## i64) & 140737488355312] = r if JS_MULTI_REALM[0]
  ps = src == nil ? "" : js_to_string(src)
  fs = fl == nil ? "" : js_to_string(fl)
  js_regexp_init(o, ps, fs, nt == rc)

-> js_this_rx(v, what)
  js_throw_type("RegExp.prototype." + what + " requires that 'this' be a RegExp object") if !js_internal(v).is_a?(JS:Regex)
  v.internal

JS_RX_CAPS = i64[32]
# Dynamic ivar byte offsets for inline ARM64 SRA regex exec:
#   [0]=Special.@internal, [1]=Special.@s0 (lastIndex), [2]=Regex.@jit_fp, [3]=Regex.@global, [4]=Regex.@sticky
JS_RX_OFFS = i64[5]
# 1-entry pinned ASCII string cache: [s_bits, sp, byte_len] (pins both String and optional bytes_view!)
JS_RX_STR_CACHE = i64[3]
JS_RX_STR_KEEP = [nil, nil]
JS_RX_R1 = ByteArray.new(1)
# Epoch-cached pristine check for RegExp.prototype.{exec, [Symbol.replace]}: [epoch, ok]
JS_RX_PRISTINE = i64[2]

-> js_rx_offs_init
  return nil if JS_RX_OFFS[0] != 0
  o = JS:Special.new(nil, "RegExp")
  o.internal = :__rx_int_probe
  o.s0 = :__rx_s0_probe
  ob = wvalue_bits(o) ## i64
  JS_RX_OFFS[0] = js_find_ivar_off(ob, wvalue_bits(:__rx_int_probe) ## i64)
  JS_RX_OFFS[1] = js_find_ivar_off(ob, wvalue_bits(:__rx_s0_probe) ## i64)
  rx = JS:Regex.new
  rx.jit_fp = 24680
  rx.global = :__rx_gl_probe
  rx.sticky = :__rx_st_probe
  rb = wvalue_bits(rx) ## i64
  JS_RX_OFFS[2] = js_find_ivar_off(rb, wvalue_bits(24680) ## i64)
  JS_RX_OFFS[3] = js_find_ivar_off(rb, wvalue_bits(:__rx_gl_probe) ## i64)
  JS_RX_OFFS[4] = js_find_ivar_off(rb, wvalue_bits(:__rx_st_probe) ## i64)
  nil

-> js_rx_getter_ok?(rp, name, orig)
  d = rp.get_own_property(name)
  d != nil && d.accessor? && d.getter == orig

-> js_rx_pristine?(r)
  ep = JS_EPOCH[0]
  return true if JS_RX_PRISTINE[0] == ep && JS_RX_PRISTINE[1] != 0
  rp = r.regexp_proto
  return false if rp == nil
  ok = rp.get_own("exec") == r.regexp_exec_fn && rp.get_own(SYM_REPLACE) == r.intrinsics["%RegExpProto_replace%"]
  if ok
    ok = js_rx_getter_ok?(rp, "flags", r.intrinsics["%RegExpProto_flags%"]) &&
         js_rx_getter_ok?(rp, "global", r.intrinsics["%RegExpProto_global%"]) &&
         js_rx_getter_ok?(rp, "unicode", r.intrinsics["%RegExpProto_unicode%"]) &&
         js_rx_getter_ok?(rp, "unicodeSets", r.intrinsics["%RegExpProto_unicodeSets%"]) &&
         js_rx_getter_ok?(rp, "sticky", r.intrinsics["%RegExpProto_sticky%"]) &&
         js_rx_getter_ok?(rp, "dotAll", r.intrinsics["%RegExpProto_dotAll%"]) &&
         js_rx_getter_ok?(rp, "hasIndices", r.intrinsics["%RegExpProto_hasIndices%"]) &&
         js_rx_getter_ok?(rp, "ignoreCase", r.intrinsics["%RegExpProto_ignoreCase%"]) &&
         js_rx_getter_ok?(rp, "multiline", r.intrinsics["%RegExpProto_multiline%"])
  JS_RX_PRISTINE[0] = ep
  JS_RX_PRISTINE[1] = ok ? 1 : 0
  ok

# Fast JIT regex exec writing capture byte offsets directly into `caps_ptr`.
# Returns: match_end (>= 0) on match, -1 on no match, -2 on slow fallback needed.
-> js_rx_exec_caps_raw(o, s, caps_ptr)
  r = js_realm()
  return -2 if !o.is_a?(JS:Special) || o.shape != r.regexp_shape
  rx = o.internal
  return -2 if !rx.is_a?(JS:Regex) || !js_string?(s) || !s.ascii?
  fp = rx.jit_tried ? rx.jit_fp : js_rx_ensure_jit(rx)
  return -2 if fp == 0
  global = rx.global
  sticky = rx.sticky
  liv = o.s0
  return -2 if !js_number?(liv)
  li = 0
  if global || sticky
    li = liv.to_i
    if li < 0 || li.to_f != liv
      li = js_to_length(liv)
  n = s.size
  if li > n
    o.s0 = ~0.0 if global || sticky
    return -1
  sb = wvalue_bits(s) ## i64
  sp = 0 ## i64
  if sb == JS_RX_STR_CACHE[0] && sb != 0
    sp = JS_RX_STR_CACHE[1]
  else
    sp = jp_flat_str_ptr(sb)
    if sp != 0
      JS_RX_STR_CACHE[0] = sb
      JS_RX_STR_CACHE[1] = sp
      JS_RX_STR_CACHE[2] = n ## i64
      JS_RX_STR_KEEP[0] = s
      JS_RX_STR_KEEP[1] = nil
    elsif n > 0
      bv = ccall("w_string_bytes_view", s) ## u8[]
      sp = jit_bytearray_ptr(wvalue_bits(bv) ## i64)
      JS_RX_STR_CACHE[0] = sb
      JS_RX_STR_CACHE[1] = sp
      JS_RX_STR_CACHE[2] = n ## i64
      JS_RX_STR_KEEP[0] = s
      JS_RX_STR_KEEP[1] = bv
  en = jit_raw_call5(fp ## i64, sp, n ## i64, li ## i64, caps_ptr, sticky ? 1 : 0)
  if en < 0
    o.s0 = ~0.0 if global || sticky
    return -1
  o.s0 = en + ~0.0 if global || sticky
  en

# Runtime entry called by JIT SRA `re.exec(s)` (returns boxed Int: >= 0 match, -1 miss, -2 deopt).
-> js_rx_exec_caps_rt(o, s, caps_arr)
  r = js_realm()
  return -2 if !js_rx_pristine?(r)
  js_rx_exec_caps_raw(o, s, jit_arr_slots_ptr(wvalue_bits(caps_arr) ## i64))

# Fast ASCII substring slice using inline WStrings (<= 5 bytes) & JS_S7 (6..7 bytes).
-> js_rx_slice_ascii(s, sp, st, en)
  len = en - st
  return "" if len == 0
  if len <= 5 && sp != 0
    return wvalue_from_bits(jp_pack_inline(sp, st ## i64, len ## i64))
  if len >= 6 && len <= 15 && sp != 0
    s7k_p = jit_arr_slots_ptr(wvalue_bits(JS_S7_KEYS) ## i64)
    s7v_p = jit_arr_slots_ptr(wvalue_bits(JS_S7_VALS) ## i64)
    hit = wvalue_from_bits(js_s7_probe_bits(sp, st ## i64, len ## i64, s7k_p, s7v_p))
    return hit if hit != nil
    str = s.slice(st, len)
    js_s7_cache_set(sp, st ## i64, len ## i64, str)
    return str
  s.slice(st, len)

# Record legacy RegExp static properties lazily (zero allocations on hot exec path!).
-> js_rx_record_legacy(r, rx, s, caps)
  return nil if !rx.legacy_ok
  r.rx_leg_s = s
  ng = rx.ngroups
  ng = 9 if ng > 9
  r.rx_leg_ng = ng
  lc = r.rx_leg_caps
  k = 0
  lim = (ng + 1) * 2
  while k < lim
    lc[k] = caps[k] ## i64
    k += 1
  nil

-> js_rx_materialize_legacy(r)
  s = r.rx_leg_s
  return nil if s == nil
  r.rx_leg_s = nil
  r.rx_last_input = s
  lc = r.rx_leg_caps
  st0 = lc[0] ## int
  en0 = lc[1] ## int
  r.rx_last_match = st0 >= 0 && en0 >= 0 ? js_substring(s, st0, en0) : ""
  r.rx_left_ctx = st0 > 0 ? js_substring(s, 0, st0) : ""
  slen = js_len(s)
  r.rx_right_ctx = en0 >= 0 && en0 < slen ? js_substring(s, en0, slen) : ""
  ng = r.rx_leg_ng
  lp = ""
  ps = r.rx_parens
  g = 1
  while g <= 9
    if g <= ng
      sg = lc[g * 2] ## int
      eg = lc[g * 2 + 1] ## int
      v = sg >= 0 && eg >= 0 ? js_substring(s, sg, eg) : ""
      ps[g - 1] = v
      lp = v if g == ng
    else
      ps[g - 1] = ""
    g += 1
  r.rx_last_paren = lp
  nil

# RegExpBuiltinExec: the match array or JS_NULL.
-> js_regexp_builtin_exec(o, s)
  r = js_realm()
  if o.is_a?(JS:Special) && o.shape == r.regexp_shape && js_string?(s) && s.ascii?
    rx = o.internal
    if rx.is_a?(JS:Regex)
      fp = rx.jit_tried ? rx.jit_fp : js_rx_ensure_jit(rx)
      if fp != 0
        caps = JS_RX_CAPS
        caps_p = jit_arr_slots_ptr(wvalue_bits(caps) ## i64)
        en = js_rx_exec_caps_raw(o, s, caps_p)
        return JS_NULL if en == -1
        if en >= 0
          js_rx_record_legacy(r, rx, s, caps)
          return js_rx_match_array_fast(rx, s, caps)
  rx = js_this_rx(o, "exec")
  li = js_to_length(jget(o, "lastIndex"))
  rx = o.internal if o.internal.is_a?(JS:Regex)
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
  js_rx_record_legacy(r, rx, s, m.caps)
  js_rx_match_array(rx, s, m.caps)

-> js_rx_match_array_fast(rx, s, caps)
  r = js_realm()
  sp = jp_flat_str_ptr(wvalue_bits(s) ## i64)
  ng = rx.ngroups
  items = Array.new(ng + 1, nil)
  g = 0
  while g <= ng
    st = caps[g * 2]
    en = caps[g * 2 + 1]
    items[g] = st >= 0 && en >= 0 ? js_rx_slice_ascii(s, sp, st, en) : nil
    g += 1
  a = js_mark_array(items)
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
  if !rx.has_indices && r.rx_match_shape != nil
    ext = JS:Object.new(r.rx_match_shape)
    ext.s0 = caps[0] + ~0.0
    ext.s1 = s
    ext.s2 = groups
    ab = wvalue_bits(a) ## i64
    key = ab & 140737488355312
    JS_AEXT[key] = ext
    JS_AEXT_KEEP[key] = a
    jsr_set_aflags(ab, JS_AF_ARRAY | JS_AF_EXT)
    return a
  jdefine(a, "index", caps[0] + ~0.0, ATTR_ALL)
  jdefine(a, "input", s, ATTR_ALL)
  jdefine(a, "groups", groups, ATTR_ALL)
  if rx.has_indices
    ind = Array.new(ng + 1, nil)
    g = 0
    while g <= ng
      st = caps[g * 2]
      en = caps[g * 2 + 1]
      ind[g] = st >= 0 && en >= 0 ? r.adopt_array([st + ~0.0, en + ~0.0]) : nil
      g += 1
    ia = js_mark_array(ind)
    ig = nil
    if rx.names.size > 0
      ig = js_new_object(nil)
      q = 0
      while q < rx.names.size
        pr = rx.names[q]
        iv = ind[pr[1]]
        ig.define(pr[0], iv, ATTR_ALL) if iv != nil || !ig.has_own?(pr[0])
        q += 1
    jdefine(ia, "groups", ig, ATTR_ALL)
    jdefine(a, "indices", ia, ATTR_ALL)
  a

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
        iv = ind[pr[1]]
        ig.define(pr[0], iv, ATTR_ALL) if iv != nil || !ig.has_own?(pr[0])
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
  n = s.size
  while i < n
    b = s.byte_at(i)
    if b == 92 && i + 1 < n
      b2 = s.byte_at(i + 1)
      if b2 == 10
        out.append("\\n")
        i += 2
      elsif b2 == 13
        out.append("\\r")
        i += 2
      elsif b2 == 226 && i + 3 < n && s.byte_at(i + 2) == 128 && (s.byte_at(i + 3) == 168 || s.byte_at(i + 3) == 169)
        out.append(s.byte_at(i + 3) == 168 ? "\\u2028" : "\\u2029")
        i += 4
      else
        out.append(s.slice(i, 2))
        i += 2
    else
      if b == 47 && !in_class
        out.append("\\/")
        i += 1
      elsif b == 10
        out.append("\\n")
        i += 1
      elsif b == 13
        out.append("\\r")
        i += 1
      elsif b == 226 && i + 2 < n && s.byte_at(i + 1) == 128 && (s.byte_at(i + 2) == 168 || s.byte_at(i + 2) == 169)
        out.append(s.byte_at(i + 2) == 168 ? "\\u2028" : "\\u2029")
        i += 3
      else
        in_class = true if b == 91
        in_class = false if b == 93
        out.append(s.slice(i, 1))
        i += 1
  r = out.to_s
  ccall("w_value_free_w", out)
  r

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

# Pure-LLVM single-pass ASCII range-repeat replace (e.g. /\d+/g -> "#"): ZERO per-match calls!
fn rx_replace_range_ll(sp, n, lo, hi, rp, rlen, out_p, out_cap, is_global) (i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %src = inttoptr i64 %sp to ptr
    %rep = inttoptr i64 %rp to ptr
    %dst = inttoptr i64 %out_p to ptr
    %span = sub i64 %hi, %lo
    br label %lp
  lp:
    %i = phi i64 [ 0, %0 ], [ %ni_lit, %lit_ok ], [ %ni_rep, %rep_done ]
    %op = phi i64 [ 0, %0 ], [ %nop_lit, %lit_ok ], [ %nop_rep, %rep_done ]
    %done = icmp sge i64 %i, %n
    br i1 %done, label %ret_ok, label %chk
  chk:
    %p_b = getelementptr i8, ptr %src, i64 %i
    %b8 = load i8, ptr %p_b, align 1
    %b = zext i8 %b8 to i64
    %d = sub i64 %b, %lo
    %in_rng = icmp ule i64 %d, %span
    br i1 %in_rng, label %skip_lp, label %lit
  lit:
    %lit_ovf = icmp sge i64 %op, %out_cap
    br i1 %lit_ovf, label %ret_ovf, label %lit_ok
  lit_ok:
    %p_o = getelementptr i8, ptr %dst, i64 %op
    store i8 %b8, ptr %p_o, align 1
    %ni_lit = add i64 %i, 1
    %nop_lit = add i64 %op, 1
    br label %lp
  skip_lp:
    %si = phi i64 [ %i, %chk ], [ %si1, %skip_next ]
    %si1 = add i64 %si, 1
    %s_end = icmp sge i64 %si1, %n
    br i1 %s_end, label %emit_rep, label %skip_chk
  skip_chk:
    %p_sb = getelementptr i8, ptr %src, i64 %si1
    %sb8 = load i8, ptr %p_sb, align 1
    %sb = zext i8 %sb8 to i64
    %sd = sub i64 %sb, %lo
    %s_in = icmp ule i64 %sd, %span
    br i1 %s_in, label %skip_next, label %emit_rep
  skip_next:
    br label %skip_lp
  emit_rep:
    %ni_rep = phi i64 [ %si1, %skip_lp ], [ %si1, %skip_chk ]
    %nop_rep = add i64 %op, %rlen
    %rep_ovf = icmp sgt i64 %nop_rep, %out_cap
    br i1 %rep_ovf, label %ret_ovf, label %copy_rep
  copy_rep:
    %r1 = icmp eq i64 %rlen, 1
    br i1 %r1, label %rep_one, label %rep_lp_hdr
  rep_one:
    %rb0 = load i8, ptr %rep, align 1
    %p_ro = getelementptr i8, ptr %dst, i64 %op
    store i8 %rb0, ptr %p_ro, align 1
    br label %rep_done
  rep_lp_hdr:
    br label %rep_lp
  rep_lp:
    %ri = phi i64 [ 0, %rep_lp_hdr ], [ %ri1, %rep_body ]
    %rdone = icmp sge i64 %ri, %rlen
    br i1 %rdone, label %rep_done, label %rep_body
  rep_body:
    %p_rs = getelementptr i8, ptr %rep, i64 %ri
    %rb = load i8, ptr %p_rs, align 1
    %op_r = add i64 %op, %ri
    %p_rd = getelementptr i8, ptr %dst, i64 %op_r
    store i8 %rb, ptr %p_rd, align 1
    %ri1 = add i64 %ri, 1
    br label %rep_lp
  rep_done:
    %is_g = icmp ne i64 %is_global, 0
    br i1 %is_g, label %lp, label %tail_chk
  tail_chk:
    %tlen = sub i64 %n, %ni_rep
    %tend = add i64 %nop_rep, %tlen
    %tovf = icmp sgt i64 %tend, %out_cap
    br i1 %tovf, label %ret_ovf, label %tail_lp
  tail_lp:
    %ti = phi i64 [ 0, %tail_chk ], [ %ti1, %tail_body ]
    %tdone = icmp sge i64 %ti, %tlen
    br i1 %tdone, label %ret_tail, label %tail_body
  tail_body:
    %ts_i = add i64 %ni_rep, %ti
    %p_ts = getelementptr i8, ptr %src, i64 %ts_i
    %tb = load i8, ptr %p_ts, align 1
    %td_i = add i64 %nop_rep, %ti
    %p_td = getelementptr i8, ptr %dst, i64 %td_i
    store i8 %tb, ptr %p_td, align 1
    %ti1 = add i64 %ti, 1
    br label %tail_lp
  ret_tail:
    ret i64 %tend
  ret_ok:
    ret i64 %op
  ret_ovf:
    ret i64 -1
  IR

# Pure-LLVM general flat ASCII regex replace loop: zero Match arrays, zero Tungsten loop overhead!
fn rx_replace_ascii_flat_ll(rx_fp, sp, n, rp, rlen, out_p, out_cap, caps_p, is_global) (i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %rx_fp to ptr
    %src = inttoptr i64 %sp to ptr
    %rep = inttoptr i64 %rp to ptr
    %dst = inttoptr i64 %out_p to ptr
    %cp = inttoptr i64 %caps_p to ptr
    br label %lp
  lp:
    %op = phi i64 [ 0, %0 ], [ %op2, %adv ]
    %cpos = phi i64 [ 0, %0 ], [ %en, %adv ]
    %spos = phi i64 [ 0, %0 ], [ %nspos, %adv ]
    %s_ok = icmp sle i64 %spos, %n
    br i1 %s_ok, label %do_exec, label %tail_chk
  do_exec:
    %en = call i64 %f(i64 %sp, i64 %n, i64 %spos, i64 %caps_p, i64 0)
    %no_m = icmp slt i64 %en, 0
    br i1 %no_m, label %tail_chk, label %got_m
  got_m:
    %st = load i64, ptr %cp, align 8
    %unm = sub i64 %st, %cpos
    %op1 = add i64 %op, %unm
    %op2 = add i64 %op1, %rlen
    %ovf = icmp sgt i64 %op2, %out_cap
    br i1 %ovf, label %ret_ovf, label %cp_unm
  cp_unm:
    %ui = phi i64 [ 0, %got_m ], [ %ui1, %cp_unm_b ]
    %udone = icmp sge i64 %ui, %unm
    br i1 %udone, label %cp_rep, label %cp_unm_b
  cp_unm_b:
    %us_i = add i64 %cpos, %ui
    %p_us = getelementptr i8, ptr %src, i64 %us_i
    %ub = load i8, ptr %p_us, align 1
    %ud_i = add i64 %op, %ui
    %p_ud = getelementptr i8, ptr %dst, i64 %ud_i
    store i8 %ub, ptr %p_ud, align 1
    %ui1 = add i64 %ui, 1
    br label %cp_unm
  cp_rep:
    %ri = phi i64 [ 0, %cp_unm ], [ %ri1, %cp_rep_b ]
    %rdone = icmp sge i64 %ri, %rlen
    br i1 %rdone, label %chk_glob, label %cp_rep_b
  cp_rep_b:
    %p_rs = getelementptr i8, ptr %rep, i64 %ri
    %rb = load i8, ptr %p_rs, align 1
    %rd_i = add i64 %op1, %ri
    %p_rd = getelementptr i8, ptr %dst, i64 %rd_i
    store i8 %rb, ptr %p_rd, align 1
    %ri1 = add i64 %ri, 1
    br label %cp_rep
  chk_glob:
    %is_g = icmp ne i64 %is_global, 0
    br i1 %is_g, label %adv, label %tail_chk
  adv:
    %empty = icmp eq i64 %en, %st
    %en1 = add i64 %en, 1
    %nspos = select i1 %empty, i64 %en1, i64 %en
    br label %lp
  tail_chk:
    %f_op = phi i64 [ %op, %lp ], [ %op, %do_exec ], [ %op2, %chk_glob ]
    %f_cp = phi i64 [ %cpos, %lp ], [ %cpos, %do_exec ], [ %en, %chk_glob ]
    %tlen = sub i64 %n, %f_cp
    %tend = add i64 %f_op, %tlen
    %tovf = icmp sgt i64 %tend, %out_cap
    br i1 %tovf, label %ret_ovf, label %tail_lp
  tail_lp:
    %ti = phi i64 [ 0, %tail_chk ], [ %ti1, %tail_b ]
    %tdone = icmp sge i64 %ti, %tlen
    br i1 %tdone, label %ret_ok, label %tail_b
  tail_b:
    %ts_i = add i64 %f_cp, %ti
    %p_ts = getelementptr i8, ptr %src, i64 %ts_i
    %tb = load i8, ptr %p_ts, align 1
    %td_i = add i64 %f_op, %ti
    %p_td = getelementptr i8, ptr %dst, i64 %td_i
    store i8 %tb, ptr %p_td, align 1
    %ti1 = add i64 %ti, 1
    br label %tail_lp
  ret_ok:
    ret i64 %tend
  ret_ovf:
    ret i64 -1
  IR

-> js_str_replace_fast(s, pat, repl)
  r = js_realm()
  if js_string?(s) && pat.is_a?(JS:Special) && pat.shape == r.regexp_shape && js_rx_pristine?(r)
    return js_regexp_replace(pat, s, repl)
  js_str_replace(s, pat, repl, false)

-> js_regexp_replace(o, sv, repl)
  js_throw_type("RegExp.prototype\[Symbol.replace] called on non-object") if !js_object?(o)
  s = js_to_string(sv)
  fun = js_callable?(repl) ? repl : nil
  rs = fun == nil ? js_to_string(repl) : nil
  r = js_realm()
  # Ultra-fast native ARM64 ASCII replace path (zero Match arrays, zero StringBuffer!)
  if fun == nil && o.is_a?(JS:Special) && o.shape == r.regexp_shape && js_rx_pristine?(r) && rs.ascii? && rs.index("$") == nil
    s_bits = wvalue_bits(s) ## i64
    cached_s = s_bits == JS_RX_STR_CACHE[0] && s_bits != 0
    if cached_s || s.ascii?
      rx = o.internal
      if rx.is_a?(JS:Regex) && !rx.sticky && (rx.global || js_number?(o.s0))
        is_rng = rx.rep_lo >= 0
        fp = is_rng ? 0 : (rx.jit_tried ? rx.jit_fp : js_rx_ensure_jit(rx))
        if is_rng || fp != 0
          o.s0 = ~0.0 if rx.global
          n = cached_s ? (JS_RX_STR_CACHE[2] ## int) : s.size
          sp = 0 ## i64
          if cached_s
            sp = JS_RX_STR_CACHE[1]
          else
            sp = jp_flat_str_ptr(s_bits)
            if sp != 0
              JS_RX_STR_CACHE[0] = s_bits
              JS_RX_STR_CACHE[1] = sp
              JS_RX_STR_CACHE[2] = n ## i64
              JS_RX_STR_KEEP[0] = s
              JS_RX_STR_KEEP[1] = nil
            elsif n > 0
              sbv = ccall("w_string_bytes_view", s) ## u8[]
              sp = jit_bytearray_ptr(wvalue_bits(sbv) ## i64)
              JS_RX_STR_CACHE[0] = s_bits
              JS_RX_STR_CACHE[1] = sp
              JS_RX_STR_CACHE[2] = n ## i64
              JS_RX_STR_KEEP[0] = s
              JS_RX_STR_KEEP[1] = sbv
          rlen = rs.size
          rp = 0 ## i64
          rbv = nil
          if rlen == 1
            JS_RX_R1[0] = rs.byte_at(0)
            rp = jit_bytearray_ptr(wvalue_bits(JS_RX_R1) ## i64)
          elsif rlen > 1
            rp = jp_flat_str_ptr(wvalue_bits(rs) ## i64)
            if rp == 0
              rbv = ccall("w_string_bytes_view", rs) ## u8[]
              rp = jit_bytearray_ptr(wvalue_bits(rbv) ## i64)
          caps_p = is_rng ? (0 ## i64) : jit_arr_slots_ptr(wvalue_bits(JS_RX_CAPS) ## i64)
          gflag = rx.global ? (1 ## i64) : (0 ## i64)
          if rlen <= 1 && !rx.sticky
            # Output can never exceed n + 1 bytes -> allocate exact ByteArray and steal zero-copy!
            out = ByteArray.new(n + 2)
            out_p = jit_bytearray_ptr(wvalue_bits(out) ## i64)
            opos = is_rng ? rx_replace_range_ll(sp, n ## i64, rx.rep_lo ## i64, rx.rep_hi ## i64, rp, rlen ## i64, out_p, (n + 1) ## i64, gflag) : rx_replace_ascii_flat_ll(fp ## i64, sp, n ## i64, rp, rlen ## i64, out_p, (n + 1) ## i64, caps_p, gflag)
            if opos >= 0
              return opos == 0 ? "" : ccall("w_string_take_byte_array", out, opos)
          else
            # General length replacement: write into growable ByteArray then take!
            cap = n * 2 + rlen + 64
            out = ByteArray.new(cap + 1)
            out_p = jit_bytearray_ptr(wvalue_bits(out) ## i64)
            opos = is_rng ? rx_replace_range_ll(sp, n ## i64, rx.rep_lo ## i64, rx.rep_hi ## i64, rp, rlen ## i64, out_p, cap ## i64, gflag) : rx_replace_ascii_flat_ll(fp ## i64, sp, n ## i64, rp, rlen ## i64, out_p, cap ## i64, caps_p, gflag)
            while opos < 0
              cap = cap * 2
              out = ByteArray.new(cap + 1)
              out_p = jit_bytearray_ptr(wvalue_bits(out) ## i64)
              opos = is_rng ? rx_replace_range_ll(sp, n ## i64, rx.rep_lo ## i64, rx.rep_hi ## i64, rp, rlen ## i64, out_p, cap ## i64, gflag) : rx_replace_ascii_flat_ll(fp ## i64, sp, n ## i64, rp, rlen ## i64, out_p, cap ## i64, caps_p, gflag)
            return opos == 0 ? "" : ccall("w_string_take_byte_array", out, opos)
  n = js_len(s)
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
  r = sb.to_s
  ccall("w_value_free_w", sb)
  r

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
  fg = r.getter(rp, "flags", ->(this, args, nt) js_regexp_flags(this))
  r.set_intrinsic("%RegExpProto_flags%", rp.get_own_property("flags").getter)
  r.getter(rp, "source", ->(this, args, nt) js_regexp_source(this))
  fls = [["hasIndices", "d"], ["global", "g"], ["ignoreCase", "i"], ["multiline", "m"], ["dotAll", "s"], ["unicode", "u"], ["unicodeSets", "v"], ["sticky", "y"]]
  i = 0
  while i < fls.size
    js_install_rx_flag(r, rp, fls[i][0], fls[i][1])
    r.set_intrinsic("%RegExpProto_" + fls[i][0] + "%", rp.get_own_property(fls[i][0]).getter)
    i += 1
  r.method(rp, SYM_MATCH, 1, ->(this, args, nt) js_regexp_match(this, js_arg(args, 0)))
  r.method(rp, SYM_MATCH_ALL, 1, ->(this, args, nt) js_regexp_match_all(this, js_arg(args, 0)))
  rep_m = r.method(rp, SYM_REPLACE, 2, ->(this, args, nt) js_regexp_replace(this, js_arg(args, 0), js_arg(args, 1)))
  r.set_intrinsic("%RegExpProto_replace%", rep_m)
  r.regexp_proto = rp
  r.regexp_exec_fn = ex
  r.regexp_shape = js_root_shape(rp, SP_INLINE, SP_IBASE).add("lastIndex", ATTR_W)
  r.rx_match_shape = js_root_shape(nil, OBJ_INLINE, OBJ_IBASE).add("index", ATTR_ALL).add("input", ATTR_ALL).add("groups", ATTR_ALL)
  JS_RX_PRISTINE[0] = -1
  JS_RX_PRISTINE[1] = 0
  r.method(rp, SYM_SEARCH, 1, ->(this, args, nt) js_regexp_search(this, js_arg(args, 0)))
  r.method(rp, SYM_SPLIT, 2, ->(this, args, nt) js_regexp_split(this, js_arg(args, 0), js_arg(args, 1)))
  ip = r.intrinsics["%IteratorPrototype%"]
  sip = js_new_object(ip == nil ? r.object_proto : ip)
  r.set_intrinsic("%RegExpStringIteratorPrototype%", sip)
  r.method(sip, "next", 0, ->(this, args, nt) js_regexp_string_iter_next(this))
  sip.define(SYM_TO_STRING_TAG, "RegExp String Iterator", ATTR_C)
  r.method(rc, "escape", 1, ->(this, args, nt) js_regexp_escape(js_arg(args, 0)))
  r.rx_ctor = rc
  js_install_rx_legacy_accessors(r, rc)
  nil

-> js_install_rx_legacy_accessors(r, rc)
  in_get = ->(this, args, nt)
    js_throw_type("RegExp legacy accessor requires %RegExp% receiver") if this != rc
    js_rx_materialize_legacy(r)
    r.rx_last_input
  in_set = ->(this, args, nt)
    js_throw_type("RegExp legacy accessor requires %RegExp% receiver") if this != rc
    js_rx_materialize_legacy(r)
    r.rx_last_input = js_to_string(js_arg(args, 0))
    nil
  r.getter(rc, "input", in_get, in_set)
  r.getter(rc, "$_", in_get, in_set)
  lm_get = ->(this, args, nt)
    js_throw_type("RegExp legacy accessor requires %RegExp% receiver") if this != rc
    js_rx_materialize_legacy(r)
    r.rx_last_match
  r.getter(rc, "lastMatch", lm_get)
  r.getter(rc, "$&", lm_get)
  lp_get = ->(this, args, nt)
    js_throw_type("RegExp legacy accessor requires %RegExp% receiver") if this != rc
    js_rx_materialize_legacy(r)
    r.rx_last_paren
  r.getter(rc, "lastParen", lp_get)
  r.getter(rc, "$+", lp_get)
  lc_get = ->(this, args, nt)
    js_throw_type("RegExp legacy accessor requires %RegExp% receiver") if this != rc
    js_rx_materialize_legacy(r)
    r.rx_left_ctx
  r.getter(rc, "leftContext", lc_get)
  r.getter(rc, "$`", lc_get)
  rc_get = ->(this, args, nt)
    js_throw_type("RegExp legacy accessor requires %RegExp% receiver") if this != rc
    js_rx_materialize_legacy(r)
    r.rx_right_ctx
  r.getter(rc, "rightContext", rc_get)
  r.getter(rc, "$'", rc_get)
  g = 1
  while g <= 9
    js_install_rx_paren_getter(r, rc, g)
    g += 1
  nil

-> js_install_rx_paren_getter(r, rc, idx)
  fn = ->(this, args, nt)
    js_throw_type("RegExp legacy accessor requires %RegExp% receiver") if this != rc
    js_rx_materialize_legacy(r)
    r.rx_parens[idx - 1]
  r.getter(rc, "$" + idx.to_s, fn)

-> js_regexp_compile(o, pat, fl)
  rx = js_this_rx(o, "compile")
  js_throw_type("RegExp.prototype.compile cannot be called on a RegExp subclass instance") if !rx.legacy_ok
  if JS_MULTI_REALM[0]
    rr = JS_RX_REALM[(wvalue_bits(o) ## i64) & 140737488355312]
    rr = JS_FIRST_REALM[0] if rr == nil
    js_throw_type("RegExp.prototype.compile cannot be called on a cross-realm RegExp") if rr != nil && rr != js_realm()
  if js_internal(pat).is_a?(JS:Regex)
    js_throw_type("Invalid flags supplied to RegExp constructor") if fl != nil
    return js_regexp_init(o, pat.internal.source, pat.internal.flags)
  js_regexp_init(o, pat == nil ? "" : js_to_string(pat), fl == nil ? "" : js_to_string(fl))

-> js_install_rx_flag(r, rp, name, f)
  r.getter(rp, name, ->(this, args, nt) js_regexp_flag_getter(this, f, name))

-> js_rx_hex4(c)
  JS_DIGITS36.slice((c >> 12) & 15, 1) + JS_DIGITS36.slice((c >> 8) & 15, 1) + JS_DIGITS36.slice((c >> 4) & 15, 1) + JS_DIGITS36.slice(c & 15, 1)

-> js_rx_escape_ws?(c)
  c == 32 || c == 0xA0 || c == 0x1680 || (c >= 0x2000 && c <= 0x200A) || c == 0x2028 || c == 0x2029 || c == 0x202F || c == 0x205F || c == 0x3000 || c == 0xFEFF

-> js_regexp_escape(v)
  js_throw_type("RegExp.escape requires a string") if !js_string?(v)
  sb = StringBuffer()
  u = js_units(v)
  i = 0
  n = u.size
  while i < n
    c = u[i]
    # Valid surrogate pair -> pass through both units unescaped!
    if c >= 0xD800 && c <= 0xDBFF && i + 1 < n && u[i + 1] >= 0xDC00 && u[i + 1] <= 0xDFFF
      sb.append(js_from_units([c, u[i + 1]]))
      i += 2
      next
    if i == 0 && ((c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122))
      sb.append("\\x" + JS_DIGITS36.slice(c >> 4, 1) + JS_DIGITS36.slice(c & 15, 1))
    elsif c == 9
      sb.append("\\t")
    elsif c == 10
      sb.append("\\n")
    elsif c == 11
      sb.append("\\v")
    elsif c == 12
      sb.append("\\f")
    elsif c == 13
      sb.append("\\r")
    elsif js_rx_syntax_char?(c)
      sb.append("\\" + js_cp_str(c))
    elsif (c < 128 && ",-=<>#&!%:;@~'`\"".index(js_cp_str(c)) != nil) || js_rx_escape_ws?(c) || (c >= 0xD800 && c <= 0xDFFF)
      if c <= 0xFF
        sb.append("\\x" + JS_DIGITS36.slice(c >> 4, 1) + JS_DIGITS36.slice(c & 15, 1))
      else
        sb.append("\\u" + js_rx_hex4(c))
    else
      sb.append(js_from_units([c]))
    i += 1
  r = sb.to_s
  ccall("w_value_free_w", sb)
  r
