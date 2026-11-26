# blade/js/lexer — the ECMAScript 2024 lexical grammar.
#
# JsLexer is a pull scanner: `next_token` advances to the next token and leaves
# it in plain fields (no token objects are allocated):
#
#   tt       token type (T_* constants below)
#   tstart   byte offset of the token's first byte; tend is one past its last
#   value    T_NAME: identifier name (escapes decoded); T_STRING: cooked value;
#            T_TEMPLATE: cooked value (nil when it holds an invalid escape, which
#            only tagged templates allow); T_REGEX: pattern body; T_PRIVATE:
#            name without '#'; T_BIGINT: digits without the 'n' or separators
#   raw      T_TEMPLATE: raw text (CR and CRLF normalized to LF); T_REGEX: flags
#   num      T_NUM: the Float value
#   tail     T_TEMPLATE: true when the piece ends with a backtick (no `${`)
#   nl       a line terminator precedes this token (for ASI)

use rx_unicode
use t/lexer_simd

JS_SIMD_LEX = [Env.get("BLADE_JS_SIMD_LEX", "1") != "0"]
#   escaped  a T_NAME or keyword was spelled with \u escapes
#   prev_end end offset of the previous token
#
# Strings are produced as UTF-8; lone surrogate escapes (\uD800) come out as
# their 3-byte WTF-8 encoding so no information is lost. U+0000 escapes
# ("\0", "\x00", "\u0000") rely on 0.chr being "\0", which needs a core with
# the chr-nul fix (older cores return "").
#
# Regex vs divide: the scanner guesses from the previous token (the standard
# heuristic), and the parser corrects it with `rescan_regex` / `rescan_div`
# when the grammar says otherwise, so the guess only has to be usually right.
#
# Template literals nest through a small stack: `{` pushes 0, `${` pushes 1,
# and a `}` that pops a 1 resumes scanning the template.
#
# Non-ASCII identifier characters: any non-ASCII code point that is not a
# space or line terminator is accepted (a superset of ID_Start/ID_Continue).
#
# Byte codes (no bracket literals in strings: `[` interpolates in Tungsten):
# 9 tab 10 LF 11 VT 12 FF 13 CR 32 sp 33 ! 34 " 35 # 36 $ 37 % 38 & 39 '
# 40 ( 41 ) 42 * 43 + 44 , 45 - 46 . 47 / 48-57 0-9 58 : 59 ; 60 < 61 =
# 62 > 63 ? 64 @ 65-90 A-Z 91 [ 92 \ 93 ] 94 ^ 95 _ 96 ` 97-122 a-z
# 123 { 124 | 125 } 126 ~

# One code point as UTF-8 (WTF-8 for lone surrogates). TODO(tungsten): the toolchain Blade
# builds with predates the chr-nul fix (6423288b: 0.chr is "\0", not ""); drop the special
# case once that lands.
-> js_chr(cp)
  cp == 0 ? "\0" : cp.chr

T_EOF = 0
T_NAME = 1
T_NUM = 2
T_BIGINT = 3
T_STRING = 4
T_TEMPLATE = 5
T_REGEX = 6
T_PRIVATE = 7

# reserved words
T_BREAK = 10
T_CASE = 11
T_CATCH = 12
T_CLASS = 13
T_CONST = 14
T_CONTINUE = 15
T_DEBUGGER = 16
T_DEFAULT = 17
T_DELETE = 18
T_DO = 19
T_ELSE = 20
T_EXPORT = 21
T_EXTENDS = 22
T_FINALLY = 23
T_FOR = 24
T_FUNCTION = 25
T_IF = 26
T_IMPORT = 27
T_IN = 28
T_INSTANCEOF = 29
T_NEW = 30
T_RETURN = 31
T_SUPER = 32
T_SWITCH = 33
T_THIS = 34
T_THROW = 35
T_TRY = 36
T_TYPEOF = 37
T_VAR = 38
T_VOID = 39
T_WHILE = 40
T_WITH = 41
T_NULL = 42
T_TRUE = 43
T_FALSE = 44
T_ENUM = 45
T_KW_LAST = 45

JS_KW_STR = [
  nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
  "break", "case", "catch", "class", "const", "continue", "debugger", "default",
  "delete", "do", "else", "export", "extends", "finally", "for", "function",
  "if", "import", "in", "instanceof", "new", "return", "super", "switch",
  "this", "throw", "try", "typeof", "var", "void", "while", "with",
  "null", "true", "false", "enum"
]

# punctuators
T_LBRACE = 60
T_RBRACE = 61
T_LPAREN = 62
T_RPAREN = 63
T_LBRACK = 64
T_RBRACK = 65
T_SEMI = 66
T_COMMA = 67
T_DOT = 68
T_ELLIPSIS = 69
T_QUESTION = 70
T_QDOT = 71
T_COLON = 72
T_ARROW = 73
T_TILDE = 74
T_BANG = 75
T_INC = 76
T_DEC = 77
T_AT = 78

# binary operators (precedence in JS_PREC)
T_NULLISH = 80
T_OROR = 81
T_ANDAND = 82
T_BITOR = 83
T_BITXOR = 84
T_BITAND = 85
T_EQ = 86
T_NE = 87
T_SEQ = 88
T_SNE = 89
T_LT = 90
T_GT = 91
T_LE = 92
T_GE = 93
T_SHL = 94
T_SHR = 95
T_USHR = 96
T_PLUS = 97
T_MINUS = 98
T_STAR = 99
T_SLASH = 100
T_PERCENT = 101
T_STARSTAR = 102

# assignment operators (contiguous: T_ASSIGN..T_NULLISH_ASSIGN)
T_ASSIGN = 110
T_PLUS_ASSIGN = 111
T_MINUS_ASSIGN = 112
T_STAR_ASSIGN = 113
T_SLASH_ASSIGN = 114
T_PERCENT_ASSIGN = 115
T_STARSTAR_ASSIGN = 116
T_SHL_ASSIGN = 117
T_SHR_ASSIGN = 118
T_USHR_ASSIGN = 119
T_BITAND_ASSIGN = 120
T_BITOR_ASSIGN = 121
T_BITXOR_ASSIGN = 122
T_ANDAND_ASSIGN = 123
T_OROR_ASSIGN = 124
T_NULLISH_ASSIGN = 125
T_COUNT = 126

JS_KEYWORDS = {"break" => 10, "case" => 11, "catch" => 12, "class" => 13, "const" => 14, "continue" => 15, "debugger" => 16, "default" => 17, "delete" => 18, "do" => 19, "else" => 20, "export" => 21, "extends" => 22, "finally" => 23, "for" => 24, "function" => 25, "if" => 26, "import" => 27, "in" => 28, "instanceof" => 29, "new" => 30, "return" => 31, "super" => 32, "switch" => 33, "this" => 34, "throw" => 35, "try" => 36, "typeof" => 37, "var" => 38, "void" => 39, "while" => 40, "with" => 41, "null" => 42, "true" => 43, "false" => 44, "enum" => 45}

# Source text of every token type that has a fixed spelling.
-> js_token_texts
  t = []
  i = 0
  while i < T_COUNT
    t.push(nil)
    i += 1
  JS_KEYWORDS.each ->(k, v)
    t[v] = k
  pairs = [[T_LBRACE, "{"], [T_RBRACE, "}"], [T_LPAREN, "("], [T_RPAREN, ")"], [T_LBRACK, "\["], [T_RBRACK, "]"], [T_SEMI, ";"], [T_COMMA, ","], [T_DOT, "."], [T_ELLIPSIS, "..."], [T_QUESTION, "?"], [T_QDOT, "?."], [T_COLON, ":"], [T_ARROW, "=>"], [T_TILDE, "~"], [T_BANG, "!"], [T_INC, "++"], [T_DEC, "--"], [T_AT, "@"], [T_NULLISH, "??"], [T_OROR, "||"], [T_ANDAND, "&&"], [T_BITOR, "|"], [T_BITXOR, "^"], [T_BITAND, "&"], [T_EQ, "=="], [T_NE, "!="], [T_SEQ, "==="], [T_SNE, "!=="], [T_LT, "<"], [T_GT, ">"], [T_LE, "<="], [T_GE, ">="], [T_SHL, "<<"], [T_SHR, ">>"], [T_USHR, ">>>"], [T_PLUS, "+"], [T_MINUS, "-"], [T_STAR, "*"], [T_SLASH, "/"], [T_PERCENT, "%"], [T_STARSTAR, "**"], [T_ASSIGN, "="], [T_PLUS_ASSIGN, "+="], [T_MINUS_ASSIGN, "-="], [T_STAR_ASSIGN, "*="], [T_SLASH_ASSIGN, "/="], [T_PERCENT_ASSIGN, "%="], [T_STARSTAR_ASSIGN, "**="], [T_SHL_ASSIGN, "<<="], [T_SHR_ASSIGN, ">>="], [T_USHR_ASSIGN, ">>>="], [T_BITAND_ASSIGN, "&="], [T_BITOR_ASSIGN, "|="], [T_BITXOR_ASSIGN, "^="], [T_ANDAND_ASSIGN, "&&="], [T_OROR_ASSIGN, "||="], [T_NULLISH_ASSIGN, "??="]]
  pairs.each ->(p)
    t[p[0]] = p[1]
  t

JS_TOKEN_TEXT = js_token_texts()

-> js_token_name(tt)
  return "end of input" if tt == T_EOF
  return "identifier" if tt == T_NAME
  return "number" if tt == T_NUM || tt == T_BIGINT
  return "string" if tt == T_STRING
  return "template" if tt == T_TEMPLATE
  return "regular expression" if tt == T_REGEX
  return "private name" if tt == T_PRIVATE
  t = JS_TOKEN_TEXT[tt]
  t == nil ? "token " + tt.to_s : "'" + t + "'"

# 1-based line and column (in bytes) of a byte offset.
-> js_line_col(src, pos)
  line = 1
  ls = 0
  i = 0
  n = src.size
  pos = n if pos > n
  while i < pos
    b = src.byte_at(i)
    if b == 10
      line += 1
      ls = i + 1
    elsif b == 13
      if i + 1 < n && src.byte_at(i + 1) == 10
        i += 1
      line += 1
      ls = i + 1
    elsif b == 0xE2 && i + 2 < n && src.byte_at(i + 1) == 0x80 && (src.byte_at(i + 2) == 0xA8 || src.byte_at(i + 2) == 0xA9)
      i += 2
      line += 1
      ls = i + 1
    i += 1
  [line, pos - ls + 1]

-> js_hex_val(b)
  return b - 48 if b >= 48 && b <= 57
  return b - 87 if b >= 97 && b <= 102
  return b - 55 if b >= 65 && b <= 70
  -1

-> js_ident_start_ascii?(b)
  (b >= 97 && b <= 122) || (b >= 65 && b <= 90) || b == 36 || b == 95

-> js_ident_part_ascii?(b)
  (b >= 97 && b <= 122) || (b >= 65 && b <= 90) || (b >= 48 && b <= 57) || b == 36 || b == 95

+ JsSyntaxError
  rw :msg, :pos, :line, :col
  -> new(@msg, @pos, @line, @col)
  -> to_s
    "SyntaxError: [@msg] (line [@line], column [@col])"

+ JsLexer
  rw :src, :n, :pos, :tt, :tstart, :tend, :value, :raw, :num, :tail, :nl, :escaped, :prev_end, :module, :error, :skip_args, :sp, :legacy_octal, :simd_toks, :simd_nt, :simd_ti, :simd_pos

  -> new(@src)
    @n = @src.size
    @pos = 0
    @tt = -1
    @tstart = 0
    @tend = 0
    @value = nil
    @raw = nil
    @num = ~0.0
    @tail = false
    @nl = false
    @escaped = false
    @legacy_octal = false
    @prev_end = 0
    @module = false
    @error = nil
    @stack = []
    @sp = 0
    @skip_buf = nil
    @skip_stack = nil
    @simd_toks = nil
    @simd_nt = 0
    @simd_ti = 0
    @simd_pos = -1
    # hashbang comment
    if @n >= 2 && @src.byte_at(0) == 35 && @src.byte_at(1) == 33
      while @pos < @n && !lt_at?(@pos)
        @pos += 1
    init_simd_lex() if JS_SIMD_LEX[0]

  # Pre-tokenize UTF-8 & ASCII scripts using SIMD Lex16 -> Tungsten Token WValues.
  # Annex-B HTML comments (`<!--`/`-->`) and illegal top-level chars are detected in-scanner
  # with zero upfront full-buffer scans, falling back cleanly to the pull scanner only if hit.
  -> init_simd_lex
    return false if @n < 64 || @n > 16000000
    lc = js_pack_lex16_utf8(@src)
    return false if lc == nil
    toks = js_simd_acquire_toks(@n + 4)
    nt = js_tokenize_lex16(lc, @n, toks)
    js_simd_trim_lc()
    if nt < 0
      js_simd_release_toks(toks)
      return false
    @simd_nt = nt
    @simd_toks = toks
    @simd_ti = 0
    @simd_pos = @pos
    true

  -> release_simd_lex
    if @simd_toks != nil
      js_simd_release_toks(@simd_toks)
      @simd_toks = nil
      @simd_pos = -1
    nil

  -> resync_simd
    return nil if @simd_toks == nil
    @simd_pos = -1
    while @simd_ti > 0 && ((jt_payload(@simd_toks, @simd_ti - 1) >> 2) & 0xFFFFFF) >= @pos
      @simd_ti -= 1
    while @simd_ti < @simd_nt
      off = (jt_payload(@simd_toks, @simd_ti) >> 2) & 0xFFFFFF
      if off >= @pos
        @simd_pos = @pos if off == @pos
        return nil
      @simd_ti += 1
    nil

  # ---- errors ----

  -> fail(msg, at)
    release_simd_lex()
    lc = js_line_col(@src, at)
    @error = JsSyntaxError.new(msg, at, lc[0], lc[1])
    raise @error.to_s

  -> unexpected
    if @tt == T_EOF
      fail("Unexpected end of input", @tstart)
    fail("Unexpected " + js_token_name(@tt), @tstart)

  # ---- character classes ----

  # Line terminator starting at i: LF, CR, LS (E2 80 A8), PS (E2 80 A9).
  -> lt_at?(i)
    b = @src.byte_at(i)
    return true if b == 10 || b == 13
    b == 0xE2 && i + 2 < @n && @src.byte_at(i + 1) == 0x80 && (@src.byte_at(i + 2) == 0xA8 || @src.byte_at(i + 2) == 0xA9)

  # Byte length of a non-ASCII whitespace or line-terminator sequence at i (0 if none).
  -> uspace_len(i)
    b = @src.byte_at(i)
    if b == 0xC2
      return 2 if i + 1 < @n && @src.byte_at(i + 1) == 0xA0
      return 0
    return 0 if i + 2 >= @n
    b1 = @src.byte_at(i + 1)
    b2 = @src.byte_at(i + 2)
    if b == 0xE2
      return 3 if b1 == 0x80 && ((b2 >= 0x80 && b2 <= 0x8A) || b2 == 0xA8 || b2 == 0xA9 || b2 == 0xAF)
      return 3 if b1 == 0x81 && b2 == 0x9F
      return 0
    return 3 if b == 0xEF && b1 == 0xBB && b2 == 0xBF
    return 3 if b == 0xE1 && b1 == 0x9A && b2 == 0x80
    return 3 if b == 0xE3 && b1 == 0x80 && b2 == 0x80
    0

  # Decode the UTF-8 code point at i; returns [cp, length].
  -> utf8_at(i)
    b = @src.byte_at(i)
    if b < 0x80
      return [b, 1]
    if b < 0xE0 && i + 1 < @n
      return [((b & 0x1F) << 6) | (@src.byte_at(i + 1) & 0x3F), 2]
    if b < 0xF0 && i + 2 < @n
      return [((b & 0x0F) << 12) | ((@src.byte_at(i + 1) & 0x3F) << 6) | (@src.byte_at(i + 2) & 0x3F), 3]
    if i + 3 < @n
      return [((b & 0x07) << 18) | ((@src.byte_at(i + 1) & 0x3F) << 12) | ((@src.byte_at(i + 2) & 0x3F) << 6) | (@src.byte_at(i + 3) & 0x3F), 4]
    [b, 1]

  -> push_brace(v)
    if @sp < @stack.size
      @stack[@sp] = v
    else
      @stack.push(v)
    @sp += 1

  # ---- whitespace and comments ----

  -> skip_space
    @nl = false
    src = @src
    n = @n
    i = @pos
    while i < n
      b = src.byte_at(i)
      if b == 32 || b == 9 || b == 11 || b == 12
        i += 1
      elsif b == 10 || b == 13
        @nl = true
        i += 1
      elsif b == 47
        b2 = i + 1 < n ? src.byte_at(i + 1) : 0
        if b2 == 47
          i += 2
          while i < n && !lt_at?(i)
            i += 1
        elsif b2 == 42
          e = src.index("*/", i + 2)
          if e == nil
            @pos = i
            fail("Unterminated comment", i)
          j = i + 2
          while j < e
            if lt_at?(j)
              @nl = true
              break
            j += 1
          i = e + 2
        else
          break
      elsif b >= 0x80
        k = uspace_len(i)
        break if k == 0
        @nl = true if k == 3 && src.byte_at(i) == 0xE2 && src.byte_at(i + 1) == 0x80 && src.byte_at(i + 2) >= 0xA8 && src.byte_at(i + 2) <= 0xA9
        i += k
      elsif b == 60 && !@module && i + 3 < n && src.byte_at(i + 1) == 33 && src.byte_at(i + 2) == 45 && src.byte_at(i + 3) == 45
        # Annex B: <!-- starts a single-line comment in scripts
        i += 4
        while i < n && !lt_at?(i)
          i += 1
      elsif b == 45 && !@module && (@nl || @tt == -1) && i + 2 < n && src.byte_at(i + 1) == 45 && src.byte_at(i + 2) == 62
        # Annex B: --> at the start of a line is a single-line comment
        i += 3
        while i < n && !lt_at?(i)
          i += 1
      else
        break
    @pos = i

  # ---- the scanner ----

  # Could a regular expression start here, judging by the previous token?
  -> regex_allowed?(prev)
    return true if prev < 0
    return false if prev == T_NAME || prev == T_NUM || prev == T_BIGINT || prev == T_STRING || prev == T_REGEX || prev == T_PRIVATE
    return @tail == false if prev == T_TEMPLATE
    return false if prev == T_THIS || prev == T_SUPER || prev == T_NULL || prev == T_TRUE || prev == T_FALSE
    return false if prev == T_RPAREN || prev == T_RBRACK || prev == T_INC || prev == T_DEC
    true

  -> next_token
    if @simd_toks != nil && @simd_pos == @pos && @simd_ti < @simd_nt
      tok = jt_payload(@simd_toks, @simd_ti)
      @simd_ti += 1
      @prev_end = @tend
      tt = tok >> 38
      off = (tok >> 2) & 0xFFFFFF
      len = (tok >> 26) & 0xFFF
      @nl = (tok & 1) != 0
      f1 = (tok & 2) != 0
      @tstart = off
      @escaped = false
      @legacy_octal = false
      if tt == 0
        @tt = T_EOF
        @tend = off
        @pos = off
        release_simd_lex()
        return T_EOF
      if tt >= 10
        # Keyword (10..45) or Punctuator/Operator (60..125): zero scanning, zero allocation!
        if tt <= T_KW_LAST
          @value = JS_KW_STR[tt]
        elsif tt == T_LBRACE
          push_brace(0)
        elsif tt == T_RBRACE && @sp > 0
          if @stack[@sp - 1] == 1
            @pos = off
            @simd_pos = -1
            return next_token_pull(true, @nl)
          @sp -= 1
        @tt = tt
        @tend = off + len
        @pos = @tend
        @simd_pos = @pos
        return tt
      if tt == T_NAME && !f1 && len > 0 && len < 4095
        @tt = T_NAME
        @tend = off + len
        @pos = @tend
        @simd_pos = @pos
        @value = @src.slice(off, len)
        return T_NAME
      if tt == T_STRING && !f1 && len >= 2 && len < 4095
        @tt = T_STRING
        @tend = off + len
        @pos = @tend
        @simd_pos = @pos
        @value = @src.slice(off + 1, len - 2)
        return T_STRING
      if tt == T_NUM && len > 0 && len < 20
        b0 = @src.byte_at(off)
        # Fast path for plain decimal integers & floats (no leading 0x/0b/0o/legacy octal, no '_')
        if (b0 >= 49 && b0 <= 57) || (b0 == 48 && (len == 1 || @src.byte_at(off + 1) == 46))
          txt = @src.slice(off, len)
          if txt.index("_") == nil && txt.index("e") == nil && txt.index("E") == nil && !(off + len < @n && (js_ident_part_ascii?(@src.byte_at(off + len)) || @src.byte_at(off + len) == 92 || @src.byte_at(off + len) >= 0x80))
            @tt = T_NUM
            @tend = off + len
            @pos = @tend
            @simd_pos = @pos
            @num = txt.to_f
            return T_NUM
      # Complex literal (escaped string/ident, template, regex, BigInt, hex/sep/octal number, >=4KB token):
      # delegate this single token to the spec-exact pull scanner, then re-sync SIMD stream if next token aligns!
      @pos = off
      @simd_pos = -1
      saved_nl = @nl
      res = next_token_pull(true, saved_nl)
      if len < 4095 && @pos == off + len
        @simd_pos = @pos
      elsif len >= 4095 && @simd_ti < @simd_nt
        ntok = jt_payload(@simd_toks, @simd_ti)
        noff = (ntok >> 2) & 0xFFFFFF
        @simd_pos = @pos if noff == @pos
      return res
    next_token_pull(false, false)

  -> next_token_pull(has_nl, saved_nl)
    @prev_end = @tend if !has_nl
    prev = @tt
    if has_nl
      @nl = saved_nl
    else
      skip_space()
    i = @pos
    @tstart = i
    @escaped = false
    @legacy_octal = false
    if i >= @n
      @tt = T_EOF
      @tend = i
      return T_EOF
    src = @src
    b = src.byte_at(i)
    if (b >= 97 && b <= 122) || (b >= 65 && b <= 90) || b == 36 || b == 95
      # identifier fast path
      j = i + 1
      n = @n
      c = 0
      while j < n
        c = src.byte_at(j)
        break if !((c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57) || c == 36 || c == 95)
        j += 1
      if j < n && (c == 92 || c >= 0x80)
        scan_ident_slow(i)
        return @tt
      @pos = j
      @tend = j
      @value = src.slice(i, j - i)
      @tt = T_NAME
      if b >= 97 && j - i >= 2 && j - i <= 10
        k = JS_KEYWORDS[@value]
        @tt = k if k != nil
      return @tt
    if b >= 48 && b <= 57
      scan_number(i)
      return @tt
    case b
    when 40
      return punct(T_LPAREN, 1)
    when 41
      return punct(T_RPAREN, 1)
    when 59
      return punct(T_SEMI, 1)
    when 44
      return punct(T_COMMA, 1)
    when 46
      b1 = peek_byte(i + 1)
      return scan_number(i) if b1 >= 48 && b1 <= 57
      return punct(T_ELLIPSIS, 3) if b1 == 46 && peek_byte(i + 2) == 46
      return punct(T_DOT, 1)
    when 123
      push_brace(0)
      return punct(T_LBRACE, 1)
    when 125
      if @sp > 0
        @sp -= 1
        if @stack[@sp] == 1
          scan_template(i + 1)
          return @tt
      return punct(T_RBRACE, 1)
    when 91
      return punct(T_LBRACK, 1)
    when 93
      return punct(T_RBRACK, 1)
    when 58
      return punct(T_COLON, 1)
    when 34, 39
      scan_string(i, b)
      return @tt
    when 96
      scan_template(i + 1)
      return @tt
    when 61
      b1 = peek_byte(i + 1)
      if b1 == 61
        return punct(T_SEQ, 3) if peek_byte(i + 2) == 61
        return punct(T_EQ, 2)
      return punct(T_ARROW, 2) if b1 == 62
      return punct(T_ASSIGN, 1)
    when 33
      if peek_byte(i + 1) == 61
        return punct(T_SNE, 3) if peek_byte(i + 2) == 61
        return punct(T_NE, 2)
      return punct(T_BANG, 1)
    when 43
      b1 = peek_byte(i + 1)
      return punct(T_INC, 2) if b1 == 43
      return punct(T_PLUS_ASSIGN, 2) if b1 == 61
      return punct(T_PLUS, 1)
    when 45
      b1 = peek_byte(i + 1)
      return punct(T_DEC, 2) if b1 == 45
      return punct(T_MINUS_ASSIGN, 2) if b1 == 61
      return punct(T_MINUS, 1)
    when 42
      b1 = peek_byte(i + 1)
      if b1 == 42
        return punct(T_STARSTAR_ASSIGN, 3) if peek_byte(i + 2) == 61
        return punct(T_STARSTAR, 2)
      return punct(T_STAR_ASSIGN, 2) if b1 == 61
      return punct(T_STAR, 1)
    when 47
      if regex_allowed?(prev)
        return @tt if try_regex(i)
      return punct(T_SLASH_ASSIGN, 2) if peek_byte(i + 1) == 61
      return punct(T_SLASH, 1)
    when 37
      return punct(T_PERCENT_ASSIGN, 2) if peek_byte(i + 1) == 61
      return punct(T_PERCENT, 1)
    when 60
      b1 = peek_byte(i + 1)
      if b1 == 60
        return punct(T_SHL_ASSIGN, 3) if peek_byte(i + 2) == 61
        return punct(T_SHL, 2)
      return punct(T_LE, 2) if b1 == 61
      return punct(T_LT, 1)
    when 62
      b1 = peek_byte(i + 1)
      if b1 == 62
        b2 = peek_byte(i + 2)
        if b2 == 62
          return punct(T_USHR_ASSIGN, 4) if peek_byte(i + 3) == 61
          return punct(T_USHR, 3)
        return punct(T_SHR_ASSIGN, 3) if b2 == 61
        return punct(T_SHR, 2)
      return punct(T_GE, 2) if b1 == 61
      return punct(T_GT, 1)
    when 38
      b1 = peek_byte(i + 1)
      if b1 == 38
        return punct(T_ANDAND_ASSIGN, 3) if peek_byte(i + 2) == 61
        return punct(T_ANDAND, 2)
      return punct(T_BITAND_ASSIGN, 2) if b1 == 61
      return punct(T_BITAND, 1)
    when 124
      b1 = peek_byte(i + 1)
      if b1 == 124
        return punct(T_OROR_ASSIGN, 3) if peek_byte(i + 2) == 61
        return punct(T_OROR, 2)
      return punct(T_BITOR_ASSIGN, 2) if b1 == 61
      return punct(T_BITOR, 1)
    when 94
      return punct(T_BITXOR_ASSIGN, 2) if peek_byte(i + 1) == 61
      return punct(T_BITXOR, 1)
    when 126
      return punct(T_TILDE, 1)
    when 63
      b1 = peek_byte(i + 1)
      if b1 == 63
        return punct(T_NULLISH_ASSIGN, 3) if peek_byte(i + 2) == 61
        return punct(T_NULLISH, 2)
      if b1 == 46
        b2 = peek_byte(i + 2)
        return punct(T_QDOT, 2) if !(b2 >= 48 && b2 <= 57)
      return punct(T_QUESTION, 1)
    when 35
      j = i + 1
      if j < @n && (js_ident_start_ascii?(src.byte_at(j)) || src.byte_at(j) == 92 || src.byte_at(j) >= 0x80)
        scan_ident_slow(j)
        @tt = T_PRIVATE
        @tstart = i
        return @tt
      fail("Invalid or unexpected token", i)
    when 64
      return punct(T_AT, 1)
    when 92
      scan_ident_slow(i)
      return @tt
    if b >= 0x80
      scan_ident_slow(i)
      return @tt
    fail("Invalid or unexpected token", i)

  # ---- lazy parsing: skip a function body ----
  #
  # From the '{' at i, find its matching '}' without making tokens or nodes (V8's
  # preparser idea, reduced to bracket matching). Strings, templates, comments and regex
  # literals are skipped whole; a '/' is a regex where an operand may start, judged from
  # the previous token, with `)` closing `if (` / `while (` / `for (` / `with (` counting
  # as operand position. Returns the offset just past the '}', or -1 when the scan runs
  # off the end or the brackets do not match (the parser then parses the body fully).
  # Sets @skip_args when the identifier `arguments` occurs (an arrow body uses the
  # enclosing function's arguments object).
  -> skip_body(i)
    if @skip_buf == nil
      @skip_buf = ccall("w_string_bytes_view", @src)
      @skip_stack = i64[4098]
    e = js_skip_scan(@skip_buf, i, @n, @module ? 1 : 0, @skip_stack)
    @skip_args = @skip_stack[4097] != 0
    e

  -> peek_byte(i)
    i < @n ? @src.byte_at(i) : 0

  -> punct(t, len)
    @tt = t
    @pos = @tstart + len
    @tend = @pos
    t

  # Identifier with escapes or non-ASCII characters, starting at i.
  -> scan_ident_slow(i)
    sb = StringBuffer()
    src = @src
    n = @n
    first = true
    while i < n
      b = src.byte_at(i)
      if js_ident_part_ascii?(b)
        break if first && b >= 48 && b <= 57
        sb.append(b.chr)
        i += 1
      elsif b == 92
        if i + 1 >= n || src.byte_at(i + 1) != 117
          fail("Invalid Unicode escape sequence", i)
        @pos = i + 2
        cp = read_unicode_escape()
        if cp < 128
          ok_c = first ? js_ident_start_ascii?(cp) : js_ident_part_ascii?(cp)
          fail("Invalid Unicode escape sequence", i) if !ok_c
        else
          ok_u = first ? js_rx_is_id_start?(cp) : (js_rx_is_id_continue?(cp) || cp == 0x200C || cp == 0x200D)
          fail("Invalid Unicode escape sequence", i) if !ok_u
        i = @pos
        @escaped = true
        sb.append(cp.chr)
      elsif b >= 0x80
        break if uspace_len(i) > 0
        d = utf8_at(i)
        cp = d[0]
        if first
          fail("Invalid identifier start character", i) if !js_rx_is_id_start?(cp)
        else
          break if !(js_rx_is_id_continue?(cp) || cp == 0x200C || cp == 0x200D)
        sb.append(src.slice(i, d[1]))
        i += d[1]
      else
        break
      first = false
    fail("Invalid or unexpected token", i) if first
    @pos = i
    @tend = i
    @value = sb.to_s
    ccall("w_value_free_w", sb)
    @tt = T_NAME
    if !@escaped
      k = JS_KEYWORDS[@value]
      @tt = k if k != nil
    @tt

  # After "\u": reads XXXX or {X...}; leaves @pos after it; returns the code point.
  -> read_unicode_escape
    src = @src
    if @pos < @n && src.byte_at(@pos) == 123
      @pos += 1
      v = 0
      digits = 0
      while @pos < @n && src.byte_at(@pos) != 125
        h = js_hex_val(src.byte_at(@pos))
        fail("Invalid Unicode escape sequence", @pos) if h < 0
        v = v * 16 + h
        fail("Undefined Unicode code-point", @pos) if v > 0x10FFFF
        digits += 1
        @pos += 1
      fail("Invalid Unicode escape sequence", @pos) if @pos >= @n || digits == 0
      @pos += 1
      return v
    v = 0
    k = 0
    while k < 4
      h = @pos < @n ? js_hex_val(src.byte_at(@pos)) : -1
      fail("Invalid Unicode escape sequence", @pos) if h < 0
      v = v * 16 + h
      @pos += 1
      k += 1
    v

  # ---- numbers ----

  -> scan_number(i)
    src = @src
    n = @n
    start = i
    b = src.byte_at(i)
    has_sep = false
    if b == 48 && i + 1 < n
      b1 = src.byte_at(i + 1) | 32
      radix = 0
      radix = 16 if b1 == 120
      radix = 8 if b1 == 111
      radix = 2 if b1 == 98
      if radix > 0
        j = i + 2
        v = ~0.0
        digits = 0
        prev_sep = false
        while j < n
          c = src.byte_at(j)
          if c == 95
            fail("Invalid numeric separator", j) if digits == 0 || prev_sep
            prev_sep = true
            has_sep = true
            j += 1
            next
          h = js_hex_val(c)
          break if h < 0 || h >= radix
          prev_sep = false
          v = v * radix.to_f + h.to_f
          digits += 1
          j += 1
        fail("Invalid or unexpected token", j) if digits == 0 || prev_sep
        if j < n && src.byte_at(j) == 110
          @tt = T_BIGINT
          @value = src.slice(start, j - start)
          @value = @value.gsub("_", "") if has_sep
          j += 1
        else
          @tt = T_NUM
          @num = v
        return finish_number(j)
      c1 = src.byte_at(i + 1)
      if c1 == 95
        fail("Numeric separator can not be used after leading 0", i + 1)
      if c1 >= 48 && c1 <= 57
        # legacy octal (017) or a decimal with a leading zero (089)
        @legacy_octal = true
        j = i + 1
        octal = true
        while j < n && src.byte_at(j) >= 48 && src.byte_at(j) <= 57
          octal = false if src.byte_at(j) >= 56
          j += 1
        fail("Invalid numeric separator", j) if j < n && src.byte_at(j) == 95
        fail("Invalid BigInt literal", j) if j < n && src.byte_at(j) == 110
        if octal
          v = ~0.0
          k = i + 1
          while k < j
            v = v * ~8.0 + (src.byte_at(k) - 48).to_f
            k += 1
          @tt = T_NUM
          @num = v
          return finish_number(j)
        i = j
        # a non-octal leading-zero literal may still have a fraction/exponent
        return scan_decimal_rest(start, i)
    j = i
    prev_sep = false
    digits = 0
    while j < n
      c = src.byte_at(j)
      if c >= 48 && c <= 57
        prev_sep = false
        digits += 1
        j += 1
      elsif c == 95
        fail("Invalid numeric separator", j) if digits == 0 || prev_sep
        prev_sep = true
        has_sep = true
        j += 1
      else
        break
    fail("Invalid numeric separator", j) if prev_sep
    if j < n && src.byte_at(j) == 110 && src.byte_at(start) != 46
      @tt = T_BIGINT
      @value = src.slice(start, j - start)
      @value = @value.gsub("_", "") if has_sep
      return finish_number(j + 1)
    scan_decimal_rest(start, j)

  # Fraction and exponent of a decimal literal whose integer part ends at j.
  -> scan_decimal_rest(start, j)
    src = @src
    n = @n
    if j < n && src.byte_at(j) == 46
      j += 1
      fdigits = 0
      fprev_sep = false
      while j < n
        c = src.byte_at(j)
        if c >= 48 && c <= 57
          fprev_sep = false
          fdigits += 1
          j += 1
        elsif c == 95
          fail("Invalid numeric separator", j) if fdigits == 0 || fprev_sep
          fprev_sep = true
          j += 1
        else
          break
      fail("Invalid numeric separator", j) if fprev_sep
    if j < n && (src.byte_at(j) | 32) == 101
      k = j + 1
      k += 1 if k < n && (src.byte_at(k) == 43 || src.byte_at(k) == 45)
      if k < n && src.byte_at(k) >= 48 && src.byte_at(k) <= 57
        j = k
        edigits = 0
        eprev_sep = false
        while j < n
          c = src.byte_at(j)
          if c >= 48 && c <= 57
            eprev_sep = false
            edigits += 1
            j += 1
          elsif c == 95
            fail("Invalid numeric separator", j) if edigits == 0 || eprev_sep
            eprev_sep = true
            j += 1
          else
            break
        fail("Invalid numeric separator", j) if eprev_sep
      else
        fail("Invalid or unexpected token", k)
    text = src.slice(start, j - start)
    text = text.gsub("_", "") if text.index("_") != nil
    text = "0" + text if text.byte_at(0) == 46
    @tt = T_NUM
    @num = text.to_f
    finish_number(j)

  -> finish_number(j)
    if j < @n
      c = @src.byte_at(j)
      if js_ident_part_ascii?(c) || c == 92
        fail("Invalid or unexpected token", j)
    @pos = j
    @tend = j
    @tt

  # ---- strings ----

  -> scan_string(i, q)
    src = @src
    n = @n
    j = i + 1
    while j < n
      c = src.byte_at(j)
      break if c == q || c == 92 || c == 10 || c == 13
      j += 1
    if j < n && src.byte_at(j) == q
      @value = src.slice(i + 1, j - i - 1)
      @pos = j + 1
      @tend = @pos
      @tt = T_STRING
      return @tt
    # slow path: escapes
    sb = StringBuffer()
    sb.append(src.slice(i + 1, j - i - 1))
    @pos = j
    while true
      fail("Unterminated string constant", i) if @pos >= n
      c = src.byte_at(@pos)
      if c == q
        @pos += 1
        break
      if c == 92
        @pos += 1
        read_escape(sb, false)
      elsif c == 10 || c == 13
        fail("Unterminated string constant", i)
      else
        st = @pos
        while @pos < n
          c = src.byte_at(@pos)
          break if c == q || c == 92 || c == 10 || c == 13
          @pos += 1
        sb.append(src.slice(st, @pos - st))
    @value = sb.to_s
    ccall("w_value_free_w", sb)
    @tend = @pos
    @tt = T_STRING
    @tt

  # After a backslash (at @pos): appends the escape's value to sb and moves
  # @pos past it. In templates, returns false for escapes that only tagged
  # templates allow (octal, bad \x / \u); in strings those are errors (or
  # legacy octal escapes).
  -> read_escape(sb, templ)
    src = @src
    n = @n
    fail("Unterminated string constant", @pos) if @pos >= n
    c = src.byte_at(@pos)
    @pos += 1
    case c
    when 110
      sb.append(10.chr)
    when 116
      sb.append(9.chr)
    when 114
      sb.append(13.chr)
    when 98
      sb.append(8.chr)
    when 102
      sb.append(12.chr)
    when 118
      sb.append(11.chr)
    when 10
      return true
    when 13
      @pos += 1 if @pos < n && src.byte_at(@pos) == 10
      return true
    when 120
      h1 = @pos < n ? js_hex_val(src.byte_at(@pos)) : -1
      h2 = @pos + 1 < n ? js_hex_val(src.byte_at(@pos + 1)) : -1
      if h1 < 0 || h2 < 0
        return false if templ
        fail("Invalid hexadecimal escape sequence", @pos)
      @pos += 2
      sb.append(js_chr(h1 * 16 + h2))
    when 117
      if templ && !unicode_escape_ok?()
        return false
      cp = read_unicode_escape()
      if cp >= 0xD800 && cp <= 0xDBFF && @pos + 1 < n && src.byte_at(@pos) == 92 && src.byte_at(@pos + 1) == 117
        save = @pos
        @pos += 2
        if unicode_escape_ok?()
          lo = read_unicode_escape()
          if lo >= 0xDC00 && lo <= 0xDFFF
            cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00)
          else
            @pos = save
        else
          @pos = save
      sb.append(js_chr(cp))
    when 48
      nb = @pos < n ? src.byte_at(@pos) : 0
      if nb >= 48 && nb <= 57
        return false if templ
        @legacy_octal = true
        @pos -= 1
        read_legacy_octal(sb)
      else
        sb.append(js_chr(0))
    else
      if c >= 49 && c <= 57
        return false if templ
        @legacy_octal = true
        if c >= 56
          sb.append(c.chr)
        else
          @pos -= 1
          read_legacy_octal(sb)
      elsif c >= 0x80
        # LS / PS line continuation, or any other character escaping itself
        @pos -= 1
        if c == 0xE2 && lt_at?(@pos)
          @pos += 3
          return true
        d = utf8_at(@pos)
        sb.append(src.slice(@pos, d[1]))
        @pos += d[1]
      else
        sb.append(c.chr)
    true

  -> unicode_escape_ok?
    src = @src
    p = @pos
    if p < @n && src.byte_at(p) == 123
      p += 1
      v = 0
      d = 0
      while p < @n && src.byte_at(p) != 125
        h = js_hex_val(src.byte_at(p))
        return false if h < 0
        v = v * 16 + h
        return false if v > 0x10FFFF
        d += 1
        p += 1
      return p < @n && d > 0
    k = 0
    while k < 4
      return false if p + k >= @n || js_hex_val(src.byte_at(p + k)) < 0
      k += 1
    true

  -> read_legacy_octal(sb)
    src = @src
    v = 0
    k = 0
    first = src.byte_at(@pos)
    maxd = first <= 51 ? 3 : 2
    while k < maxd && @pos < @n && src.byte_at(@pos) >= 48 && src.byte_at(@pos) <= 55
      v = v * 8 + (src.byte_at(@pos) - 48)
      @pos += 1
      k += 1
    sb.append(js_chr(v))

  # ---- templates ----

  # Scans a template piece starting just after ` or }. Ends at ` (tail) or ${.
  -> scan_template(i)
    src = @src
    n = @n
    j = i
    simple = true
    while j < n
      c = src.byte_at(j)
      break if c == 96
      break if c == 36 && j + 1 < n && src.byte_at(j + 1) == 123
      if c == 92 || c == 13
        simple = false
        break
      j += 1
    if simple
      fail("Unterminated template", @tstart) if j >= n
      @value = src.slice(i, j - i)
      @raw = @value
    else
      sb = StringBuffer()
      ok = true
      @pos = i
      while true
        fail("Unterminated template", @tstart) if @pos >= n
        c = src.byte_at(@pos)
        break if c == 96
        break if c == 36 && @pos + 1 < n && src.byte_at(@pos + 1) == 123
        if c == 92
          @pos += 1
          ok = false if !read_escape(sb, true)
        elsif c == 13
          sb.append(10.chr)
          @pos += 1
          @pos += 1 if @pos < n && src.byte_at(@pos) == 10
        else
          st = @pos
          while @pos < n
            c = src.byte_at(@pos)
            break if c == 96 || c == 92 || c == 13 || (c == 36 && @pos + 1 < n && src.byte_at(@pos + 1) == 123)
            @pos += 1
          sb.append(src.slice(st, @pos - st))
      j = @pos
      @value = ok ? sb.to_s : nil
      ccall("w_value_free_w", sb)
      r = src.slice(i, j - i)
      if r.index(13.chr) != nil
        r = r.gsub(13.chr + 10.chr, 10.chr).gsub(13.chr, 10.chr)
      @raw = r
    if src.byte_at(j) == 96
      @tail = true
      @pos = j + 1
    else
      @tail = false
      @pos = j + 2
      push_brace(1)
    @tend = @pos
    @tt = T_TEMPLATE
    @tt

  # ---- regular expressions ----

  # Tries to scan a regex literal at i ('/'). Leaves state untouched on failure.
  -> try_regex(i)
    src = @src
    n = @n
    j = i + 1
    in_class = false
    while true
      return false if j >= n
      c = src.byte_at(j)
      if c == 92
        j += 1
        return false if j >= n || lt_at?(j)
        j += 1
        next
      if c == 10 || c == 13
        return false
      if c == 0xE2 && lt_at?(j)
        return false
      if in_class
        in_class = false if c == 93
      elsif c == 91
        in_class = true
      elsif c == 47
        break
      j += 1
    return false if j == i + 1
    body_end = j
    j += 1
    fs = j
    while j < n && (js_ident_part_ascii?(src.byte_at(j)))
      j += 1
    @value = src.slice(i + 1, body_end - i - 1)
    @raw = src.slice(fs, j - fs)
    @pos = j
    @tend = j
    @tt = T_REGEX
    true

  # The parser wants an operand: re-read the current '/' or '/=' as a regex.
  -> rescan_regex
    @pos = @tstart
    fail("Invalid regular expression: missing /", @tstart) if !try_regex(@tstart)
    resync_simd()
    @tt

  # The parser wants an operator: re-read the current regex token as '/' or '/='.
  -> rescan_div
    i = @tstart
    r = peek_byte(i + 1) == 61 ? punct(T_SLASH_ASSIGN, 2) : punct(T_SLASH, 1)
    resync_simd()
    r

  # ---- lookahead ----

  # Type of the token after the current one; @peek_value / @peek_nl describe it.
  -> peek
    s_pos = @pos
    s_tt = @tt
    s_tstart = @tstart
    s_tend = @tend
    s_value = @value
    s_raw = @raw
    s_num = @num
    s_tail = @tail
    s_nl = @nl
    s_esc = @escaped
    s_prev = @prev_end
    s_sp = @sp
    s_simd_toks = @simd_toks
    s_simd_ti = @simd_ti
    s_simd_pos = @simd_pos
    t = next_token()
    @peek_value = @value
    @peek_nl = @nl
    @peek_start = @tstart
    @pos = s_pos
    @tt = s_tt
    @tstart = s_tstart
    @tend = s_tend
    @value = s_value
    @raw = s_raw
    @num = s_num
    @tail = s_tail
    @nl = s_nl
    @escaped = s_esc
    @prev_end = s_prev
    @sp = s_sp
    if @simd_toks == nil && s_simd_toks != nil
      # Re-acquire if peeking hit T_EOF and released our scratch lease
      if s_simd_toks == JS_SIMD_TOKS_SCRATCH[0]
        JS_SIMD_TOKS_LEASED[0] = true
      @simd_toks = s_simd_toks
    @simd_ti = s_simd_ti
    @simd_pos = s_simd_pos
    t

  -> peek_value
    @peek_value

  -> peek_nl
    @peek_nl


# ---- the body skipper (typed, so it runs as a native loop) ----
#
# From the '{' at i, find its matching '}' without making tokens or nodes (V8's
# preparser idea, reduced to bracket matching). Strings, templates, comments and regex
# literals are skipped whole; a '/' is a regex where an operand may start, judged from
# the previous token, with `)` closing `if (` / `while (` / `for (` / `with (` counting
# as operand position. Returns the offset just past the '}', or -1 when the scan runs
# off the end or the brackets do not match (the parser then parses the body fully).
# stack[4097] = 1 when the identifier `arguments` occurs (an arrow body uses the enclosing
# function's arguments object).
# Bracket stack entries: 0 {, 1 ${, 2 (, 3 ( after if/for/while/with, 4 [.
-> js_skip_scan(buf, i, n, mod, stack) (u8[] i64 i64 i64 i64[]) i64
  sp = 1 ## i64
  stack[0] = 0
  i += 1
  re = 1 ## i64
  kwp = 0 ## i64
  dot = 0 ## i64
  stack[4097] = 0
  res = 0 - 1 ## i64
  while i < n
    b = buf[i] ## i64
    if b == 32 || b == 10 || b == 9 || b == 13 || b == 11 || b == 12
      i += 1
    elsif (b >= 97 && b <= 122) || (b >= 65 && b <= 90) || b == 36 || b == 95 || b == 92 || b >= 128 || b == 35
      j = i + 1
      while j < n && js_skip_idpart(buf[j] ## i64) == 1
        j += 1
      len = j - i
      nre = 0 ## i64
      nkw = 0 ## i64
      if dot == 0 && len >= 2 && len <= 10 && b >= 97 && b <= 121
        w = js_skip_word(buf, i, len)
        nre = w & 1
        nkw = (w >> 1) & 1
        nkw = 1 if kwp == 1 && (w & 8) != 0
        stack[4097] = 1 if (w & 4) != 0
      re = nre
      kwp = nkw
      dot = 0
      i = j
    elsif b >= 48 && b <= 57
      j = i + 1
      while j < n && (js_skip_idpart(buf[j] ## i64) == 1 || buf[j] == 46)
        j += 1
      re = 0
      kwp = 0
      dot = 0
      i = j
    elsif b == 34 || b == 39
      j = i + 1
      bad = 0 ## i64
      while j < n && (buf[j] ## i64) != b && bad == 0
        c = buf[j] ## i64
        if c == 10 || c == 13
          bad = 1
        elsif c == 92
          j += 2
        else
          j += 1
      if bad == 1 || j >= n
        return res
      i = j + 1
      re = 0
      kwp = 0
      dot = 0
    elsif b == 96 || (b == 125 && sp > 0 && stack[sp - 1] == 1)
      if b == 125
        sp -= 1
      # template characters: to the closing backtick, or into a ${ substitution
      j = i + 1
      fin = 0 ## i64
      while j < n && fin == 0
        c = buf[j] ## i64
        if c == 92
          j += 2
        elsif c == 96
          fin = 1
          j += 1
        elsif c == 36 && j + 1 < n && buf[j + 1] == 123
          fin = 2
          j += 2
        else
          j += 1
      if fin == 0
        return res
      if fin == 2
        if sp >= 4096
          return res
        stack[sp] = 1
        sp += 1
        re = 1
      else
        re = 0
      i = j
      kwp = 0
      dot = 0
    elsif b == 123 || b == 40 || b == 91
      if sp >= 4096
        return res
      t = 0 ## i64
      t = (kwp == 1 ? 3 : 2) if b == 40
      t = 4 if b == 91
      stack[sp] = t
      sp += 1
      i += 1
      re = 1
      kwp = 0
      dot = 0
    elsif b == 125 || b == 41 || b == 93
      if sp == 0
        return res
      sp -= 1
      t = stack[sp]
      if b == 125
        if t != 0
          return res
        if sp == 0
          return i + 1
        re = 1
      elsif b == 41
        if t != 2 && t != 3
          return res
        re = t == 3 ? 1 : 0
      else
        if t != 4
          return res
        re = 0
      i += 1
      kwp = 0
      dot = 0
    elsif b == 47
      b2 = 0 ## i64
      b2 = buf[i + 1] ## i64 if i + 1 < n
      if b2 == 47
        i += 2
        while i < n && buf[i] != 10 && buf[i] != 13
          i += 1
      elsif b2 == 42
        i += 2
        while i + 1 < n && !(buf[i] == 42 && buf[i + 1] == 47)
          i += 1
        if i + 1 >= n
          return res
        i += 2
      elsif re == 1
        j = i + 1
        cls = 0 ## i64
        fin = 0 ## i64
        while j < n && fin == 0
          c = buf[j] ## i64
          if c == 10 || c == 13
            return res
          if c == 92
            j += 2
          else
            if c == 91
              cls = 1
            elsif c == 93
              cls = 0
            elsif c == 47 && cls == 0
              fin = 1
            j += 1
        if fin == 0
          return res
        while j < n && ((buf[j] >= 97 && buf[j] <= 122) || (buf[j] >= 65 && buf[j] <= 90))
          j += 1
        i = j
        re = 0
        kwp = 0
        dot = 0
      else
        i += 1
        re = 1
        kwp = 0
        dot = 0
    elsif b == 46
      b2 = 0 ## i64
      b2 = buf[i + 1] ## i64 if i + 1 < n
      if b2 >= 48 && b2 <= 57
        j = i + 1
        while j < n && js_skip_idpart(buf[j] ## i64) == 1
          j += 1
        i = j
        re = 0
        dot = 0
      elsif b2 == 46
        i += 3
        re = 1
        dot = 0
      else
        i += 1
        re = 1
        dot = 1
      kwp = 0
    elsif (b == 43 || b == 45) && i + 1 < n && buf[i + 1] == b
      i += 2
      kwp = 0
      dot = 0
    elsif b == 60 && mod == 0 && i + 3 < n && buf[i + 1] == 33 && buf[i + 2] == 45 && buf[i + 3] == 45
      i += 4
      while i < n && buf[i] != 10 && buf[i] != 13
        i += 1
    else
      i += 1
      re = 1
      kwp = 0
      dot = 0
  res

-> js_skip_idpart(c) (i64) i64
  if (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57) || c == 36 || c == 95 || c == 92 || c >= 128
    return 1
  0

# Keyword classes of the word at i: 1 a regex may follow (return, typeof, in, ...),
# 2 a parenthesized head then a statement (if, for, while, with), 4 `arguments`, 8 `await`.
-> js_skip_word(buf, i, len) (u8[] i64 i64) i64
  c0 = buf[i] ## i64
  c1 = buf[i + 1] ## i64
  if len == 2
    if c0 == 105 && c1 == 110
      return 1
    if c0 == 111 && c1 == 102
      return 1
    if c0 == 100 && c1 == 111
      return 1
    if c0 == 105 && c1 == 102
      return 2
    return 0
  c2 = buf[i + 2] ## i64
  if len == 3
    if c0 == 110 && c1 == 101 && c2 == 119
      return 1
    if c0 == 102 && c1 == 111 && c2 == 114
      return 2
    return 0
  c3 = buf[i + 3] ## i64
  if len == 4
    if c0 == 99 && c1 == 97 && c2 == 115 && c3 == 101
      return 1
    if c0 == 101 && c1 == 108 && c2 == 115 && c3 == 101
      return 1
    if c0 == 118 && c1 == 111 && c2 == 105 && c3 == 100
      return 1
    if c0 == 119 && c1 == 105 && c2 == 116 && c3 == 104
      return 2
    return 0
  c4 = buf[i + 4] ## i64
  if len == 5
    if c0 == 116 && c1 == 104 && c2 == 114 && c3 == 111 && c4 == 119
      return 1
    if c0 == 121 && c1 == 105 && c2 == 101 && c3 == 108 && c4 == 100
      return 1
    if c0 == 97 && c1 == 119 && c2 == 97 && c3 == 105 && c4 == 116
      return 9
    if c0 == 119 && c1 == 104 && c2 == 105 && c3 == 108 && c4 == 101
      return 2
    return 0
  c5 = buf[i + 5] ## i64
  if len == 6
    if c0 == 114 && c1 == 101 && c2 == 116 && c3 == 117 && c4 == 114 && c5 == 110
      return 1
    if c0 == 116 && c1 == 121 && c2 == 112 && c3 == 101 && c4 == 111 && c5 == 102
      return 1
    if c0 == 100 && c1 == 101 && c2 == 108 && c3 == 101 && c4 == 116 && c5 == 101
      return 1
    return 0
  if len == 9
    if c0 == 97 && c1 == 114 && c2 == 103 && c3 == 117 && c4 == 109 && c5 == 101 && buf[i + 6] == 110 && buf[i + 7] == 116 && buf[i + 8] == 115
      return 4
    return 0
  if len == 10
    if c0 == 105 && c1 == 110 && c2 == 115 && c3 == 116 && c4 == 97 && c5 == 110 && buf[i + 6] == 99 && buf[i + 7] == 101 && buf[i + 8] == 111 && buf[i + 9] == 102
      return 1
  0
