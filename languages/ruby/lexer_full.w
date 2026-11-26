# tungsten/languages/ruby/lexer_full.w — Complete Ruby 4.0 Lexer backed by
# Tungsten WValue LexChar (`String#lchs("ruby", bits: 64)`) and packed 64-bit
# `W_LEXICAL_TOKEN` WValues (`core/token.w`: W_TAG_CHAR subtype 00).
#
# Packed 64-bit Token layout (matches core/token.w):
#   bits 63..46  W_TAG_CHAR subtype 00 (0xFFFC << 48)
#   bits 45..38  type    (8 bits: RB_T_* token ID)
#   bits 37..26  length  (12 bits, max 4095 bytes; overflow stored in side table)
#   bits 25..2   offset  (24 bits, max 16MB source)
#   bit  1       reserved (has_extra flag: 1 if value lives in @extras)
#   bit  0       f_line_start (1 if first non-whitespace token on its line)
#
# Hot path scans `lc = @src.lchs("ruby", bits: 64)` (`i64[]` of 64-bit LexChar WValues)
# with bitflag dispatch (`v & 0xD7`: 0x10 ws, 0x80 nl, 0x40 ident-start, 0x20 ident-cont,
# 0x01 digit, 0x08 hex, 0x02 quote, 0x04 op/punct) and packs tokens straight into `i64[]`
# with ZERO per-token heap object allocation.

# ---- Integer token IDs (stored in bits 45..38 of W_LEXICAL_TOKEN) ----
RB_TOK_TAG      = 0xFFFC << 48
RB_TOK_TYPE_SH  = 38
RB_TOK_LEN_SH   = 26
RB_TOK_OFF_SH   = 2

RB_T_EOF        = 0
RB_T_NL         = 1
RB_T_SEMI       = 2
RB_T_IDENT      = 3
RB_T_CONST      = 4
RB_T_INT        = 5
RB_T_FLOAT      = 6
RB_T_RATIONAL   = 7
RB_T_COMPLEX    = 8
RB_T_STRING     = 9
RB_T_DSTR       = 10
RB_T_SYMBOL     = 11
RB_T_DSYM       = 12
RB_T_REGEX      = 13
RB_T_DREGEX     = 14
RB_T_WORD_ARRAY = 15
RB_T_SYM_ARRAY  = 16
RB_T_IVAR       = 17
RB_T_CVAR       = 18
RB_T_GVAR       = 19
RB_T_LABEL      = 20
RB_T_OP         = 21
RB_T_ASSIGN     = 22
RB_T_LPAREN     = 23
RB_T_RPAREN     = 24
RB_T_LBRACK     = 25
RB_T_RBRACK     = 26
RB_T_LBRACE     = 27
RB_T_RBRACE     = 28
RB_T_COMMA      = 29
RB_T_DOT        = 30
RB_T_DOT2       = 31
RB_T_DOT3       = 32
RB_T_COLON      = 33
RB_T_COLON2     = 34
RB_T_QMARK      = 35
RB_T_ARROW      = 36
RB_T_STABBY     = 37
RB_T_SAFE_DOT   = 38
RB_T_XSTR       = 39
RB_T_HEREDOC    = 40

# Ruby 4.0 keywords (IDs 50..90)
RB_T_KW_ENCODING = 50
RB_T_KW_LINE     = 51
RB_T_KW_FILE     = 52
RB_T_KW_BEGIN_UP = 53
RB_T_KW_END_UP   = 54
RB_T_KW_ALIAS    = 55
RB_T_KW_AND      = 56
RB_T_KW_BEGIN    = 57
RB_T_KW_BREAK    = 58
RB_T_KW_CASE     = 59
RB_T_KW_CLASS    = 60
RB_T_KW_DEF      = 61
RB_T_KW_DEFINED  = 62
RB_T_KW_DO       = 63
RB_T_KW_ELSE     = 64
RB_T_KW_ELSIF    = 65
RB_T_KW_END      = 66
RB_T_KW_ENSURE   = 67
RB_T_KW_FALSE    = 68
RB_T_KW_FOR      = 69
RB_T_KW_IF       = 70
RB_T_KW_IN       = 71
RB_T_KW_MODULE   = 72
RB_T_KW_NEXT     = 73
RB_T_KW_NIL      = 74
RB_T_KW_NOT      = 75
RB_T_KW_OR       = 76
RB_T_KW_REDO     = 77
RB_T_KW_RESCUE   = 78
RB_T_KW_RETRY    = 79
RB_T_KW_RETURN   = 80
RB_T_KW_SELF     = 81
RB_T_KW_SUPER    = 82
RB_T_KW_THEN     = 83
RB_T_KW_TRUE     = 84
RB_T_KW_UNDEF    = 85
RB_T_KW_UNLESS   = 86
RB_T_KW_UNTIL    = 87
RB_T_KW_WHEN     = 88
RB_T_KW_WHILE    = 89
RB_T_KW_YIELD    = 90

RB_KW_IDS = {
  "__ENCODING__" => RB_T_KW_ENCODING,
  "__LINE__" => RB_T_KW_LINE,
  "__FILE__" => RB_T_KW_FILE,
  "BEGIN" => RB_T_KW_BEGIN_UP,
  "END" => RB_T_KW_END_UP,
  "alias" => RB_T_KW_ALIAS,
  "and" => RB_T_KW_AND,
  "begin" => RB_T_KW_BEGIN,
  "break" => RB_T_KW_BREAK,
  "case" => RB_T_KW_CASE,
  "class" => RB_T_KW_CLASS,
  "def" => RB_T_KW_DEF,
  "defined?" => RB_T_KW_DEFINED,
  "do" => RB_T_KW_DO,
  "else" => RB_T_KW_ELSE,
  "elsif" => RB_T_KW_ELSIF,
  "end" => RB_T_KW_END,
  "ensure" => RB_T_KW_ENSURE,
  "false" => RB_T_KW_FALSE,
  "for" => RB_T_KW_FOR,
  "if" => RB_T_KW_IF,
  "in" => RB_T_KW_IN,
  "module" => RB_T_KW_MODULE,
  "next" => RB_T_KW_NEXT,
  "nil" => RB_T_KW_NIL,
  "not" => RB_T_KW_NOT,
  "or" => RB_T_KW_OR,
  "redo" => RB_T_KW_REDO,
  "rescue" => RB_T_KW_RESCUE,
  "retry" => RB_T_KW_RETRY,
  "return" => RB_T_KW_RETURN,
  "self" => RB_T_KW_SELF,
  "super" => RB_T_KW_SUPER,
  "then" => RB_T_KW_THEN,
  "true" => RB_T_KW_TRUE,
  "undef" => RB_T_KW_UNDEF,
  "unless" => RB_T_KW_UNLESS,
  "until" => RB_T_KW_UNTIL,
  "when" => RB_T_KW_WHEN,
  "while" => RB_T_KW_WHILE,
  "yield" => RB_T_KW_YIELD
}

# Fast O(1) ID -> symbol lookup table (size 96)
RB_ID_TO_SYM = [
  :eof, :nl, :semi, :ident, :const, :int, :float, :rational, :complex, :string,
  :dstr, :symbol, :dsym, :regex, :dregex, :word_array, :sym_array, :ivar, :cvar, :gvar,
  :label, :op, :assign, :lparen, :rparen, :lbrack, :rbrack, :lbrace, :rbrace, :comma,
  :dot, :dot2, :dot3, :colon, :colon2, :qmark, :arrow, :stabby, :safe_dot, :xstr,
  :heredoc, nil, nil, nil, nil, nil, nil, nil, nil, nil,
  :kw_encoding, :kw_line, :kw_file, :kw_BEGIN, :kw_END, :kw_alias, :kw_and, :kw_begin, :kw_break, :kw_case,
  :kw_class, :kw_def, :kw_defined, :kw_do, :kw_else, :kw_elsif, :kw_end, :kw_ensure, :kw_false, :kw_for,
  :kw_if, :kw_in, :kw_module, :kw_next, :kw_nil, :kw_not, :kw_or, :kw_redo, :kw_rescue, :kw_retry,
  :kw_return, :kw_self, :kw_super, :kw_then, :kw_true, :kw_undef, :kw_unless, :kw_until, :kw_when, :kw_while,
  :kw_yield
]

RB_SYM_TO_ID = {
  eof: 0, nl: 1, semi: 2, ident: 3, const: 4, int: 5, float: 6, rational: 7, complex: 8, string: 9,
  dstr: 10, symbol: 11, dsym: 12, regex: 13, dregex: 14, word_array: 15, sym_array: 16, ivar: 17, cvar: 18, gvar: 19,
  label: 20, op: 21, assign: 22, lparen: 23, rparen: 24, lbrack: 25, rbrack: 26, lbrace: 27, rbrace: 28, comma: 29,
  dot: 30, dot2: 31, dot3: 32, colon: 33, colon2: 34, qmark: 35, arrow: 36, stabby: 37, safe_dot: 38, xstr: 39,
  heredoc: 40,
  kw_encoding: 50, kw_line: 51, kw_file: 52, :kw_BEGIN => 53, :kw_END => 54, kw_alias: 55, kw_and: 56, kw_begin: 57, kw_break: 58, kw_case: 59,
  kw_class: 60, kw_def: 61, kw_defined: 62, kw_do: 63, kw_else: 64, kw_elsif: 65, kw_end: 66, kw_ensure: 67, kw_false: 68, kw_for: 69,
  kw_if: 70, kw_in: 71, kw_module: 72, kw_next: 73, kw_nil: 74, kw_not: 75, kw_or: 76, kw_redo: 77, kw_rescue: 78, kw_retry: 79,
  kw_return: 80, kw_self: 81, kw_super: 82, kw_then: 83, kw_true: 84, kw_undef: 85, kw_unless: 86, kw_until: 87, kw_when: 88, kw_while: 89,
  kw_yield: 90
}

## i64: pos
## i64[]: lc
fn rb_lc_at(lc, pos)
  lc[pos]

## i64: idx, tid, len, off, flags
## i64[]: arr
fn rb_packed_emit(arr, idx, tid, len, off, flags)
  clen = len > 4095 ? 4095 : (len < 0 ? 0 : len)
  coff = off > 16777215 ? 16777215 : (off < 0 ? 0 : off)
  arr[idx] = (0xFFFC << 48) | ((tid & 0xFF) << 38) | (clen << 26) | (coff << 2) | (flags & 3)
  0

## i64: idx
## i64[]: arr
fn rb_packed_id(arr, idx)
  (arr[idx] >> 38) & 0xFF

## i64: idx
## i64[]: arr
fn rb_packed_len(arr, idx)
  (arr[idx] >> 26) & 0xFFF

## i64: idx
## i64[]: arr
fn rb_packed_off(arr, idx)
  (arr[idx] >> 2) & 0xFFFFFF

## i64: idx
## i64[]: arr
fn rb_packed_has_extra(arr, idx)
  (arr[idx] >> 1) & 1

## i64: idx
## i64[]: arr
fn rb_packed_line_start(arr, idx)
  arr[idx] & 1

## i64: lc_val
fn rb_lc_cp(lc_val)
  (lc_val >> 18) & 0x1FFFFF

-> rb_parse_int(s, base = 10)
  return 0 if s == nil || s.size == 0
  neg = false
  i = 0
  if s.byte_at(0) == 45
    neg = true
    i = 1
  elsif s.byte_at(0) == 43
    i = 1
  acc = 0
  while i < s.size
    b = s.byte_at(i)
    d = -1
    if b >= 48 && b <= 57
      d = b - 48
    elsif b >= 65 && b <= 90
      d = b - 55
    elsif b >= 97 && b <= 122
      d = b - 87
    break if d < 0 || d >= base
    acc = acc * base + d
    i += 1
  neg ? -acc : acc

+ RbTok
  ro :type, :val, :line, :extra

  -> new(@type, @val, @line, @extra = nil)

# Packed 64-bit W_LEXICAL_TOKEN stream produced by RbLexer using LexChar (`lchs("ruby", bits: 64)`).
+ RbTokenStream
  ro :src, :packed, :lines, :extra_idx, :extras, :count, :frozen_strings

  -> new(@src, @packed, @lines, @extra_idx, @extras, @count, @frozen_strings = false)

  -> size
    @count

  -> id_at(i)
    k = i < @count ? i : @count - 1
    rb_packed_id(@packed, k)

  -> sym_at(i)
    RB_ID_TO_SYM[id_at(i)]

  -> line_at(i)
    k = i < @count ? i : @count - 1
    @lines[k]

  -> raw_slice(i)
    k = i < @count ? i : @count - 1
    @src.slice(rb_packed_off(@packed, k), rb_packed_len(@packed, k))

  -> val_at(i)
    k = i < @count ? i : @count - 1
    if rb_packed_has_extra(@packed, k) != 0
      ei = @extra_idx[k]
      e = @extras[ei]
      return e[0]
    tid = rb_packed_id(@packed, k)
    return "" if tid == RB_T_EOF
    return "\n" if tid == RB_T_NL
    s = @src.slice(rb_packed_off(@packed, k), rb_packed_len(@packed, k))
    if tid == RB_T_INT
      return rb_parse_int(s, 10)
    if tid == RB_T_FLOAT
      return s.to_f
    s

  -> extra_at(i)
    k = i < @count ? i : @count - 1
    if rb_packed_has_extra(@packed, k) != 0
      ei = @extra_idx[k]
      return @extras[ei][1]
    nil

  # Materialize an RbTok view on demand (e.g., for diagnostics or legacy callers).
  -> tok_at(i)
    k = i < @count ? i : @count - 1
    RbTok.new(sym_at(k), val_at(k), @lines[k], extra_at(k))

  -> [](i)
    tok_at(i)

# Constant lookup table for expr_beg? on integer token IDs (0..90).
RB_EXPR_BEG_TBL = [
  0, 1, 1, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  1, 1, 1, 1, 0, 1, 0, 1, 0, 1,
  0, 0, 0, 1, 0, 1, 1, 1, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 1, 1, 1, 1,
  0, 0, 0, 1, 1, 1, 0, 1, 0, 0,
  1, 1, 0, 1, 0, 1, 1, 0, 1, 0,
  1, 0, 0, 1, 0, 0, 1, 1, 1, 1,
  1
]

# Fast native LexChar scan helper for identifiers (ASCII/Unicode via 0x20 flag in ruby.lex64).
## i64: pos, count
## i64[]: lc
fn rb_scan_ident_end(lc, pos, count)
  p = pos + 1
  while p < count && (lc[p] & 0x20) != 0
    p += 1
  p

## i64: pos, count
## i64[]: lc
fn rb_scan_ws_end(lc, pos, count)
  p = pos + 1
  while p < count && (lc[p] & 0x10) != 0
    p += 1
  p

## i64: pos, count
## i64[]: lc
fn rb_scan_comment_end(lc, pos, count)
  p = pos + 1
  while p < count && (lc[p] & 0x80) == 0
    p += 1
  p

## i64: pos, count
## i64[]: lc
fn rb_scan_digits_end(lc, pos, count)
  p = pos
  while p < count
    v = lc[p]
    if (v & 0x01) != 0 || ((v >> 18) & 0x1FFFFF) == 95
      p += 1
    else
      break
  p

## i64: pos, count
## i64[]: lc
fn rb_scan_hex_end(lc, pos, count)
  p = pos
  while p < count
    v = lc[p]
    if (v & 0x08) != 0 || ((v >> 18) & 0x1FFFFF) == 95
      p += 1
    else
      break
  p

+ RbLexer
  ro :frozen_strings

  -> new(@src)
    @n = @src.size
    @ascii = @src.ascii?()
    @lc = @ascii ? @src.lchs("ruby", bits: 64) : nil
    @lc_n = @lc != nil ? @lc.size : 0
    @i = 0
    @line = 1
    @frozen_strings = false
    @prev_id = RB_T_NL
    @prev_space = false
    @line_start = 1
    @heredocs = []
    cap = @n / 2 + 16
    cap = 32 if cap < 32
    @packed = i64[cap]
    @lines = i64[cap]
    @extra_idx = i64[cap]
    @extras = []
    @tc = 0
    @cap = cap

  -> grow_toks
    ncap = @cap * 2
    np = i64[ncap]
    nl = i64[ncap]
    ne = i64[ncap]
    k = 0
    while k < @tc
      np[k] = @packed[k]
      nl[k] = @lines[k]
      ne[k] = @extra_idx[k]
      k += 1
    @packed = np
    @lines = nl
    @extra_idx = ne
    @cap = ncap
    nil

  -> emit(tid, off, len, ln)
    grow_toks() if @tc >= @cap
    rb_packed_emit(@packed, @tc, tid, len, off, @line_start)
    @lines[@tc] = ln
    @extra_idx[@tc] = -1
    @tc += 1
    @prev_id = tid
    @line_start = (tid == RB_T_NL) ? 1 : 0
    nil

  -> emit_val(tid, off, len, ln, val, extra = nil)
    grow_toks() if @tc >= @cap
    ei = @extras.size
    @extras.push([val, extra])
    rb_packed_emit(@packed, @tc, tid, len, off, 2 | @line_start)
    @lines[@tc] = ln
    @extra_idx[@tc] = ei
    @tc += 1
    @prev_id = tid
    @line_start = (tid == RB_T_NL) ? 1 : 0
    nil

  -> eof?
    @i >= @n

  -> peek(off = 0)
    k = @i + off
    return -1 if k < 0 || k >= @n
    @src.byte_at(k)

  -> adv
    b = @src.byte_at(@i)
    @i += 1
    @line += 1 if b == 10
    b

  -> is_alpha?(b)
    (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b == 95 || b >= 128

  -> is_digit?(b)
    b >= 48 && b <= 57

  -> is_hex?(b)
    (b >= 48 && b <= 57) || (b >= 65 && b <= 70) || (b >= 97 && b <= 102)

  -> is_ident?(b)
    is_alpha?(b) || is_digit?(b)

  # Whether a `/` or `%` at the current position starts a literal rather than a binary operator.
  -> expr_beg?
    return true if RB_EXPR_BEG_TBL[@prev_id] != 0
    if (@prev_id == RB_T_IDENT || @prev_id == RB_T_CONST) && @prev_space
      nxt = peek(1)
      return true if nxt != 32 && nxt != 9 && nxt != 61 && nxt != 10 && nxt != -1
    false

  -> read_escape_char
    return "" if eof?
    b = adv()
    case b
    when 110 then "\n"
    when 116 then "\t"
    when 114 then "\r"
    when 102 then "\f"
    when 98  then "\b"
    when 97  then "\a"
    when 118 then "\v"
    when 101 then "\e"
    when 115 then " "
    when 92  then "\\"
    when 34  then "\""
    when 39  then "'"
    when 35  then "#"
    when 32  then " "
    when 10  then ""
    when 120 # \xHH
      hex = ""
      k = 0
      while k < 2 && !eof? && is_hex?(peek())
        hex = hex + @src.slice(@i, 1)
        adv()
        k += 1
      return hex.size > 0 ? rb_parse_int(hex, 16).chr : "x"
    when 117 # \uHHHH or \u{...}
      if !eof? && peek() == 123
        adv()
        out = ""
        while !eof? && peek() != 125
          while !eof? && (peek() == 32 || peek() == 9)
            adv()
          break if eof? || peek() == 125
          hs = @i
          while !eof? && is_hex?(peek())
            adv()
          if @i > hs
            cp = rb_parse_int(@src.slice(hs, @i - hs), 16)
            out = out + Codepoint.new(cp).to_s
          else
            break
        adv() if !eof? && peek() == 125
        return out
      else
        hex = ""
        k = 0
        while k < 4 && !eof? && is_hex?(peek())
          hex = hex + @src.slice(@i, 1)
          adv()
          k += 1
        return hex.size > 0 ? Codepoint.new(rb_parse_int(hex, 16)).to_s : "u"
    else
      if b >= 48 && b <= 55
        oct = @src.slice(@i - 1, 1)
        k = 0
        while k < 2 && !eof? && peek() >= 48 && peek() <= 55
          oct = oct + @src.slice(@i, 1)
          adv()
          k += 1
        return rb_parse_int(oct, 8).chr
      @src.slice(@i - 1, 1)

  -> scan_dstr(close_b, open_b = -1)
    parts = []
    buf = StringBuffer()
    has_interp = false
    depth = 0
    while !eof?
      b = peek()
      if b == close_b && depth == 0
        adv()
        break
      if open_b >= 0 && b == open_b
        depth += 1
        buf << @src.slice(@i, 1)
        adv()
      elsif b == close_b && depth > 0
        depth -= 1
        buf << @src.slice(@i, 1)
        adv()
      elsif b == 92
        adv()
        buf << read_escape_char()
      elsif b == 35 && peek(1) == 123
        has_interp = true
        if buf.size > 0
          parts.push([:str, buf.to_s])
          buf = StringBuffer()
        @i += 2
        expr_start = @i
        brace_d = 1
        while !eof? && brace_d > 0
          cb = peek()
          if cb == 123
            brace_d += 1
            adv()
          elsif cb == 125
            brace_d -= 1
            if brace_d == 0
              expr_src = @src.slice(expr_start, @i - expr_start)
              adv()
              parts.push([:expr, expr_src])
              break
            adv()
          elsif cb == 34 || cb == 39
            q = adv()
            while !eof?
              sb = adv()
              if sb == 92 && !eof?
                adv()
              elsif sb == q
                break
          else
            adv()
      elsif b == 35 && (peek(1) == 64 || peek(1) == 36)
        has_interp = true
        if buf.size > 0
          parts.push([:str, buf.to_s])
          buf = StringBuffer()
        adv()
        vs = @i
        adv()
        adv() if peek(-1) == 64 && peek() == 64
        while !eof? && is_ident?(peek())
          adv()
        parts.push([:expr, @src.slice(vs, @i - vs)])
      else
        buf << @src.slice(@i, 1)
        adv()
    if !has_interp
      return [RB_T_STRING, buf.to_s]
    parts.push([:str, buf.to_s]) if buf.size > 0
    [RB_T_DSTR, parts]

  -> scan_sstr(close_b, open_b = -1)
    buf = StringBuffer()
    depth = 0
    while !eof?
      b = peek()
      if b == close_b && depth == 0
        adv()
        break
      if open_b >= 0 && b == open_b
        depth += 1
        buf << @src.slice(@i, 1)
        adv()
      elsif b == close_b && depth > 0
        depth -= 1
        buf << @src.slice(@i, 1)
        adv()
      elsif b == 92 && !eof?
        nxt = peek(1)
        if nxt == close_b || nxt == 92
          adv()
          buf << @src.slice(@i, 1)
          adv()
        else
          buf << "\\"
          adv()
      else
        buf << @src.slice(@i, 1)
        adv()
    buf.to_s

  -> matching_delim(b)
    return 41 if b == 40
    return 93 if b == 91
    return 125 if b == 123
    return 62 if b == 60
    b

  -> scan_regex(close_b, open_b = -1)
    parts = []
    buf = StringBuffer()
    has_interp = false
    depth = 0
    in_class = false
    while !eof?
      b = peek()
      if b == close_b && depth == 0 && !in_class
        adv()
        break
      if b == 92 && !eof?
        buf << @src.slice(@i, 1)
        adv()
        if !eof?
          buf << @src.slice(@i, 1)
          adv()
      elsif !in_class && b == 35 && peek(1) == 123
        has_interp = true
        if buf.size > 0
          parts.push([:str, buf.to_s])
          buf = StringBuffer()
        @i += 2
        es = @i
        bd = 1
        while !eof? && bd > 0
          cb = peek()
          if cb == 123
            bd += 1
            adv()
          elsif cb == 125
            bd -= 1
            if bd == 0
              parts.push([:expr, @src.slice(es, @i - es)])
              adv()
              break
            adv()
          elsif cb == 34 || cb == 39
            q = adv()
            while !eof?
              sb = adv()
              if sb == 92 && !eof?
                adv()
              elsif sb == q
                break
          else
            adv()
      else
        if b == 91 && !in_class
          in_class = true
        elsif b == 93 && in_class
          in_class = false
        elsif open_b >= 0 && b == open_b && !in_class
          depth += 1
        elsif b == close_b && depth > 0 && !in_class
          depth -= 1
        buf << @src.slice(@i, 1)
        adv()
    flags = ""
    while !eof? && is_alpha?(peek())
      flags = flags + @src.slice(@i, 1)
      adv()
    if has_interp
      parts.push([:str, buf.to_s]) if buf.size > 0
      return [true, parts, flags]
    [false, buf.to_s, flags]

  -> scan_heredocs
    while @heredocs.size > 0
      hd = @heredocs.shift
      term = hd[0]
      mode = hd[1]
      interp = hd[2]
      tok = hd[3]
      lines = []
      while !eof?
        ls = @i
        while !eof? && peek() != 10
          adv()
        line_str = @src.slice(ls, @i - ls)
        line_str = line_str.slice(0, line_str.size - 1) if line_str.ends_with?("\r")
        adv() if !eof? && peek() == 10
        check = (mode == :plain) ? line_str : line_str.strip
        break if check == term
        lines.push(line_str)
      if mode == :squiggly && lines.size > 0
        min_ind = 999999
        lines.each ->(l)
          next if l.strip.size == 0
          k = 0
          while k < l.size && (l.byte_at(k) == 32 || l.byte_at(k) == 9)
            k += 1
          min_ind = k if k < min_ind
        if min_ind > 0 && min_ind < 999999
          stripped = []
          lines.each ->(l)
            stripped.push(l.size > min_ind ? l.slice(min_ind, l.size - min_ind) : "")
          lines = stripped
      body = lines.join("\n") + (lines.size > 0 ? "\n" : "")
      if interp && body.index('#{') != nil
        sub = RbLexer.new(body + "\x00")
        res = sub.scan_dstr(0)
        tok[0] = res[0] == RB_T_DSTR ? :dstr : :string
        tok[1] = res[1]
      else
        tok[0] = :string
        tok[1] = body

  # Tokenize into an RbTokenStream backed by LexChar (`lchs("ruby", bits: 64)`)
  # and packed 64-bit W_LEXICAL_TOKEN WValues (`i64[]`).
  -> tokenize
    head_end = @src.index("\n")
    first_ln = head_end == nil ? @src : @src.slice(0, head_end)
    if first_ln.index("frozen_string_literal:") != nil && first_ln.index("true") != nil
      @frozen_strings = true

    lc = @lc
    lcn = @lc_n

    while @i < @n
      @prev_space = false
      # Fast LexChar whitespace + backslash-newline continuation skip
      if lc != nil && @i < lcn
        while @i < lcn
          v = rb_lc_at(lc, @i)
          if (v & 0x10) != 0
            @prev_space = true
            @i = rb_scan_ws_end(lc, @i, lcn)
          else
            b0 = (v >> 18) & 0x1FFFFF
            if b0 == 13
              @prev_space = true
              @i += 1
            elsif b0 == 92 && @i + 1 < @n && (peek(1) == 10 || (peek(1) == 13 && peek(2) == 10))
              @prev_space = true
              adv()
              adv() if peek() == 13
              adv()
            else
              break
      else
        while @i < @n
          b0 = @src.byte_at(@i)
          if b0 == 32 || b0 == 9 || b0 == 13
            @prev_space = true
            @i += 1
          elsif b0 == 92 && (peek(1) == 10 || (peek(1) == 13 && peek(2) == 10))
            @prev_space = true
            adv()
            adv() if peek() == 13
            adv()
          else
            break
      break if @i >= @n
      ln = @line
      st = @i

      # Classify using 64-bit LexChar WValue when ASCII (99.9% of Ruby source)
      flags = 0
      b = 0
      if lc != nil && @i < lcn
        lcv = rb_lc_at(lc, @i)
        flags = lcv & 0xD7
        b = (lcv >> 18) & 0x1FFFFF
      else
        b = @src.byte_at(@i)
        if b == 10
          flags = 0x80
        elsif b == 34 || b == 39
          flags = 0x02
        elsif b >= 48 && b <= 57
          flags = 0x01
        elsif is_alpha?(b)
          flags = 0x40
        else
          flags = 0x04

      # 1. Newline (LexChar 0x80)
      if flags == 0x80 || b == 10
        if b == 13 && @i + 1 < @n && @src.byte_at(@i + 1) == 10
          @i += 2
        else
          @i += 1
        @line += 1
        scan_heredocs() if @heredocs.size > 0
        emit(RB_T_NL, st, @i - st, ln) if @prev_id != RB_T_NL
        next

      # 2. Identifier / Keyword / Constant / Hash Label (LexChar 0x40)
      if flags == 0x40
        if lc != nil
          @i = rb_scan_ident_end(lc, @i, lcn)
        else
          @i += 1
          while @i < @n && is_ident?(@src.byte_at(@i))
            @i += 1
        # Trailing ? or ! (unless !=)
        if @i < @n
          nb = @src.byte_at(@i)
          if nb == 63 || (nb == 33 && (@i + 1 >= @n || @src.byte_at(@i + 1) != 61))
            @i += 1
        len = @i - st
        # Hash label key `foo:` (not `foo::`)
        if @i < @n && @src.byte_at(@i) == 58 && (@i + 1 >= @n || @src.byte_at(@i + 1) != 58)
          @i += 1
          emit(RB_T_LABEL, st, len, ln)
          next
        nm = @src.slice(st, len)
        kw_id = RB_KW_IDS[nm]
        if kw_id != nil && @prev_id != RB_T_DOT && @prev_id != RB_T_SAFE_DOT && @prev_id != RB_T_COLON2
          emit(kw_id, st, len, ln)
        elsif b >= 65 && b <= 90
          emit(RB_T_CONST, st, len, ln)
        else
          emit(RB_T_IDENT, st, len, ln)
        next

      # 3. Numbers: Int, Float, Rational (`r`), Complex (`i`), `ri` (LexChar 0x01)
      if flags == 0x01
        is_f = false
        base = 10
        has_us = false
        if b == 48 && @i + 1 < @n
          b2 = @src.byte_at(@i + 1)
          if b2 == 120 || b2 == 88
            base = 16
            @i += 2
            @i = lc != nil ? rb_scan_hex_end(lc, @i, lcn) : @i
            if lc == nil
              while @i < @n && (is_hex?(@src.byte_at(@i)) || @src.byte_at(@i) == 95)
                @i += 1
          elsif b2 == 98 || b2 == 66
            base = 2
            @i += 2
            while @i < @n && (@src.byte_at(@i) == 48 || @src.byte_at(@i) == 49 || @src.byte_at(@i) == 95)
              @i += 1
          elsif b2 == 111 || b2 == 79
            base = 8
            @i += 2
            while @i < @n && ((@src.byte_at(@i) >= 48 && @src.byte_at(@i) <= 55) || @src.byte_at(@i) == 95)
              @i += 1
          elsif b2 == 100 || b2 == 68 # 0d decimal prefix
            base = 10
            @i += 2
            while @i < @n && (is_digit?(@src.byte_at(@i)) || @src.byte_at(@i) == 95)
              @i += 1
            has_us = true
        if base == 10 && !has_us
          if lc != nil
            @i = rb_scan_digits_end(lc, @i, lcn)
          else
            while @i < @n && (is_digit?(@src.byte_at(@i)) || @src.byte_at(@i) == 95)
              @i += 1
          if @i + 1 < @n && @src.byte_at(@i) == 46 && is_digit?(@src.byte_at(@i + 1))
            is_f = true
            @i += 1
            @i = lc != nil ? rb_scan_digits_end(lc, @i, lcn) : @i
            if lc == nil
              while @i < @n && (is_digit?(@src.byte_at(@i)) || @src.byte_at(@i) == 95)
                @i += 1
          if @i < @n && (@src.byte_at(@i) == 101 || @src.byte_at(@i) == 69)
            if (@i + 1 < @n && is_digit?(@src.byte_at(@i + 1))) || (@i + 2 < @n && (@src.byte_at(@i + 1) == 43 || @src.byte_at(@i + 1) == 45) && is_digit?(@src.byte_at(@i + 2)))
              is_f = true
              @i += 1
              @i += 1 if @src.byte_at(@i) == 43 || @src.byte_at(@i) == 45
              @i = lc != nil ? rb_scan_digits_end(lc, @i, lcn) : @i
              if lc == nil
                while @i < @n && (is_digit?(@src.byte_at(@i)) || @src.byte_at(@i) == 95)
                  @i += 1
        num_end = @i
        is_r = false
        is_c = false
        # Ruby 4.0 numeric suffixes `r`, `i`, `ri` apply ONLY when not followed by an ident char (so `1if` / `1rescue` parse as `1` + `if` / `rescue`!)
        if @i < @n && @src.byte_at(@i) == 114
          nb_r = @i + 1 < @n ? @src.byte_at(@i + 1) : -1
          if nb_r == 105 && (@i + 2 >= @n || !is_ident?(@src.byte_at(@i + 2)))
            is_r = true
            is_c = true
            @i += 2
          elsif nb_r < 0 || !is_ident?(nb_r)
            is_r = true
            @i += 1
        elsif @i < @n && @src.byte_at(@i) == 105
          nb_i = @i + 1 < @n ? @src.byte_at(@i + 1) : -1
          if nb_i < 0 || !is_ident?(nb_i)
            is_c = true
            @i += 1
        # Fast zero-alloc packed token for plain decimal integers & floats without underscores!
        if !is_r && !is_c && base == 10 && !has_us
          raw = @src.slice(st, num_end - st)
          if raw.index("_") == nil
            emit(is_f ? RB_T_FLOAT : RB_T_INT, st, num_end - st, ln)
          elsif is_f
            emit_val(RB_T_FLOAT, st, @i - st, ln, raw.gsub("_", "").to_f)
          else
            emit_val(RB_T_INT, st, @i - st, ln, rb_parse_int(raw.gsub("_", ""), 10))
        else
          raw = @src.slice(st, num_end - st).gsub("_", "")
          clean_raw = has_us ? raw.slice(2, raw.size - 2) : raw
          if is_c
            emit_val(RB_T_COMPLEX, st, @i - st, ln, clean_raw, [is_f, is_r, base])
          elsif is_r
            emit_val(RB_T_RATIONAL, st, @i - st, ln, clean_raw, [is_f, base])
          else
            clean = (base == 10 && !has_us) ? raw : raw.slice(2, raw.size - 2)
            emit_val(RB_T_INT, st, @i - st, ln, rb_parse_int(clean, base))
        next

      # 4. Quoted strings (LexChar 0x02)
      if flags == 0x02 || b == 34 || b == 39
        if b == 34
          @i += 1
          r = scan_dstr(34)
          emit_val(r[0], st, @i - st, ln, r[1], @frozen_strings)
        else
          @i += 1
          s = scan_sstr(39)
          emit_val(RB_T_STRING, st, @i - st, ln, s, @frozen_strings)
        next

      # 5. Comment `#`
      if b == 35
        if lc != nil
          @i = rb_scan_comment_end(lc, @i, lcn)
        else
          while @i < @n && @src.byte_at(@i) != 10
            @i += 1
        next

      # 6. Semicolon
      if b == 59
        @i += 1
        emit(RB_T_SEMI, st, 1, ln)
        next

      # 7. Backtick command string
      if b == 96
        @i += 1
        r = scan_dstr(96)
        emit_val(RB_T_XSTR, st, @i - st, ln, [r[0] == RB_T_DSTR ? :dstr : :string, r[1]])
        next

      # 8. Percent literals (%w, %W, %i, %I, %q, %Q, %r, %s, %()) when in expr_beg?
      if b == 37 && expr_beg?()
        nxt = peek(1)
        kind = nil
        adv_n = 0
        if nxt == 119 || nxt == 87 || nxt == 105 || nxt == 73 || nxt == 113 || nxt == 81 || nxt == 114 || nxt == 115
          delim_b = peek(2)
          if delim_b > 0 && !is_ident?(delim_b)
            kind = @src.slice(@i + 1, 1)
            adv_n = 3
        elsif nxt > 0 && !is_ident?(nxt) && nxt != 32 && nxt != 61
          kind = "Q"
          delim_b = nxt
          adv_n = 2
        if kind != nil
          @i += adv_n
          close_b = matching_delim(delim_b)
          open_b = close_b != delim_b ? delim_b : -1
          if kind == "q" || kind == "s"
            s = scan_sstr(close_b, open_b)
            emit_val(kind == "s" ? RB_T_SYMBOL : RB_T_STRING, st, @i - st, ln, s, @frozen_strings)
          elsif kind == "Q"
            r = scan_dstr(close_b, open_b)
            emit_val(r[0], st, @i - st, ln, r[1], @frozen_strings)
          elsif kind == "r"
            rx = scan_regex(close_b, open_b)
            emit_val(rx[0] ? RB_T_DREGEX : RB_T_REGEX, st, @i - st, ln, rx[1], rx[2])
          elsif kind == "w" || kind == "W" || kind == "i" || kind == "I"
            s = (kind == "w" || kind == "i") ? scan_sstr(close_b, open_b) : scan_dstr(close_b, open_b)[1].to_s
            words = []
            wi = 0
            while wi < s.size
              while wi < s.size && (s.byte_at(wi) == 32 || s.byte_at(wi) == 9 || s.byte_at(wi) == 10 || s.byte_at(wi) == 13)
                wi += 1
              break if wi >= s.size
              ws = wi
              while wi < s.size && s.byte_at(wi) != 32 && s.byte_at(wi) != 9 && s.byte_at(wi) != 10 && s.byte_at(wi) != 13
                wi += 1
              words.push(s.slice(ws, wi - ws))
            emit_val((kind == "i" || kind == "I") ? RB_T_SYM_ARRAY : RB_T_WORD_ARRAY, st, @i - st, ln, words)
          next

      # 9. Regexp literal `/`
      if b == 47 && expr_beg?()
        @i += 1
        rx = scan_regex(47)
        emit_val(rx[0] ? RB_T_DREGEX : RB_T_REGEX, st, @i - st, ln, rx[1], rx[2])
        next

      # 10. Instance / Class variables (@x, @@x)
      if b == 64
        @i += 1
        is_cv = false
        if @i < @n && @src.byte_at(@i) == 64
          is_cv = true
          @i += 1
        if lc != nil && @i < lcn && (rb_lc_at(lc, @i) & 0x40) != 0
          @i = rb_scan_ident_end(lc, @i, lcn)
        else
          while @i < @n && is_ident?(@src.byte_at(@i))
            @i += 1
        emit(is_cv ? RB_T_CVAR : RB_T_IVAR, st, @i - st, ln)
        next

      # 11. Global variables ($foo, $1, $~, $&, $', $`, $!, $@, $?, $_, $$, $0)
      if b == 36
        @i += 1
        if @i < @n
          nb = @src.byte_at(@i)
          if is_digit?(nb)
            while @i < @n && is_digit?(@src.byte_at(@i))
              @i += 1
          elsif is_alpha?(nb)
            @i = lc != nil ? rb_scan_ident_end(lc, @i, lcn) : @i + 1
            if lc == nil
              while @i < @n && is_ident?(@src.byte_at(@i))
                @i += 1
          elsif nb == 126 || nb == 38 || nb == 39 || nb == 96 || nb == 33 || nb == 64 || nb == 63 || nb == 36 || nb == 43 || nb == 42 || nb == 58 || nb == 47 || nb == 92 || nb == 44 || nb == 59 || nb == 46 || nb == 60 || nb == 62 || nb == 61 || nb == 45
            @i += 1
            @i += 1 if nb == 45 && @i < @n && is_ident?(@src.byte_at(@i))
        emit(RB_T_GVAR, st, @i - st, ln)
        next

      # 12. Colon (`::`, `:sym`, `:"dsym"`, `:'sym'`, `:+`, ternary `:`)
      if b == 58
        if peek(1) == 58
          @i += 2
          emit(RB_T_COLON2, st, 2, ln)
          next
        nb = peek(1)
        if expr_beg?() || @prev_space || @prev_id == RB_T_LPAREN || @prev_id == RB_T_LBRACK || @prev_id == RB_T_LBRACE || @prev_id == RB_T_COMMA || @prev_id == RB_T_ARROW || @prev_id == RB_T_LABEL
          if nb == 34
            @i += 2
            r = scan_dstr(34)
            emit_val(r[0] == RB_T_STRING ? RB_T_SYMBOL : RB_T_DSYM, st, @i - st, ln, r[1])
            next
          elsif nb == 39
            @i += 2
            s = scan_sstr(39)
            emit_val(RB_T_SYMBOL, st, @i - st, ln, s)
            next
          elsif is_alpha?(nb) || nb == 64 || nb == 36
            @i += 1
            ss = @i
            @i += 1 if nb == 64 || nb == 36
            @i += 1 if nb == 64 && @i < @n && @src.byte_at(@i) == 64
            while @i < @n && is_ident?(@src.byte_at(@i))
              @i += 1
            if @i < @n && (@src.byte_at(@i) == 63 || @src.byte_at(@i) == 33 || (@src.byte_at(@i) == 61 && peek(1) != 61 && peek(1) != 62))
              @i += 1
            emit(RB_T_SYMBOL, ss, @i - ss, ln)
            next
          elsif nb == 43 || nb == 45 || nb == 42 || nb == 47 || nb == 37 || nb == 60 || nb == 62 || nb == 61 || nb == 38 || nb == 124 || nb == 94 || nb == 126 || nb == 91 || nb == 96
            @i += 1
            ss = @i
            if nb == 91 && peek(1) == 93
              @i += 2
              @i += 1 if @i < @n && @src.byte_at(@i) == 61
            elsif nb == 60 && peek(1) == 61 && peek(2) == 62
              @i += 3
            elsif nb == 61 && peek(1) == 61 && peek(2) == 61
              @i += 3
            elsif (nb == 42 && peek(1) == 42) || (nb == 60 && peek(1) == 60) || (nb == 62 && peek(1) == 62) || (nb == 61 && peek(1) == 61) || (nb == 60 && peek(1) == 61) || (nb == 62 && peek(1) == 61) || (nb == 61 && peek(1) == 126)
              @i += 2
            else
              @i += 1
            emit(RB_T_SYMBOL, ss, @i - ss, ln)
            next
        @i += 1
        emit(RB_T_COLON, st, 1, ln)
        next

      # 13. Heredoc `<<EOF`, `<<-EOF`, `<<~EOF`, `<<'EOF'`
      if b == 60 && peek(1) == 60 && expr_beg?()
        k = @i + 2
        mode = :plain
        if k < @n && @src.byte_at(k) == 45
          mode = :dash
          k += 1
        elsif k < @n && @src.byte_at(k) == 126
          mode = :squiggly
          k += 1
        interp = true
        q = 0
        if k < @n && (@src.byte_at(k) == 39 || @src.byte_at(k) == 34)
          q = @src.byte_at(k)
          interp = q == 34
          k += 1
        ts = k
        while k < @n && is_ident?(@src.byte_at(k))
          k += 1
        if k > ts && (q == 0 || (k < @n && @src.byte_at(k) == q))
          term = @src.slice(ts, k - ts)
          k += 1 if q != 0
          @i = k
          holder = [:string, ""]
          @heredocs.push([term, mode, interp, holder])
          emit_val(RB_T_HEREDOC, st, @i - st, ln, holder, @frozen_strings)
          @prev_id = RB_T_STRING
          next

      # 14. Character literal `?a` / `?\n` / `?\ `
      if b == 63 && expr_beg?() && @i + 1 < @n && peek(1) != 32 && peek(1) != 9 && peek(1) != 10
        @i += 1
        ch = ""
        if peek() == 92
          @i += 1
          ch = read_escape_char()
        else
          ch = @src.slice(@i, 1)
          @i += 1
        emit_val(RB_T_STRING, st, @i - st, ln, ch, @frozen_strings)
        next

      # 15. Operators & punctuation (packed ZERO-ALLOC tokens!)
      b1 = peek(1)
      b2 = peek(2)
      if b == 46 && b1 == 46 && b2 == 46
        @i += 3
        emit(RB_T_DOT3, st, 3, ln)
        @prev_id = RB_T_OP
        next
      if (b == 60 && b1 == 61 && b2 == 62) || (b == 61 && b1 == 61 && b2 == 61)
        @i += 3
        emit(RB_T_OP, st, 3, ln)
        next
      if b2 == 61 && ((b == 124 && b1 == 124) || (b == 38 && b1 == 38) || (b == 42 && b1 == 42) || (b == 60 && b1 == 60) || (b == 62 && b1 == 62))
        @i += 3
        emit(RB_T_ASSIGN, st, 3, ln)
        next

      if b == 46 && b1 == 46
        @i += 2
        emit(RB_T_DOT2, st, 2, ln)
        @prev_id = RB_T_OP
        next
      if b == 61 && b1 == 62
        @i += 2
        emit(RB_T_ARROW, st, 2, ln)
        next
      if b == 45 && b1 == 62
        @i += 2
        emit(RB_T_STABBY, st, 2, ln)
        next
      if b == 38 && b1 == 46
        @i += 2
        emit(RB_T_SAFE_DOT, st, 2, ln)
        next
      if b1 == 61 && (b == 43 || b == 45 || b == 42 || b == 47 || b == 37 || b == 38 || b == 124 || b == 94)
        @i += 2
        emit(RB_T_ASSIGN, st, 2, ln)
        next
      if (b == 61 && (b1 == 61 || b1 == 126)) || (b == 33 && (b1 == 61 || b1 == 126)) ||
         (b == 60 && (b1 == 61 || b1 == 60)) || (b == 62 && (b1 == 61 || b1 == 62)) ||
         (b == 38 && b1 == 38) || (b == 124 && b1 == 124) || (b == 42 && b1 == 42)
        @i += 2
        emit(RB_T_OP, st, 2, ln)
        next

      @i += 1
      case b
      when 40 then emit(RB_T_LPAREN, st, 1, ln)
      when 41 then emit(RB_T_RPAREN, st, 1, ln)
      when 91 then emit(RB_T_LBRACK, st, 1, ln)
      when 93 then emit(RB_T_RBRACK, st, 1, ln)
      when 123 then emit(RB_T_LBRACE, st, 1, ln)
      when 125 then emit(RB_T_RBRACE, st, 1, ln)
      when 44 then emit(RB_T_COMMA, st, 1, ln)
      when 46 then emit(RB_T_DOT, st, 1, ln)
      when 63 then emit(RB_T_QMARK, st, 1, ln)
      when 61 then emit(RB_T_ASSIGN, st, 1, ln)
      else emit(RB_T_OP, st, 1, ln)

    emit(RB_T_EOF, @n, 0, @line)
    RbTokenStream.new(@src, @packed, @lines, @extra_idx, @extras, @tc, @frozen_strings)
