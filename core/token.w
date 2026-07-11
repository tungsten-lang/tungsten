# Token — lexical token, a W_TAG_CHAR value with subtype 00.
#
# A Token is a single 64-bit packed value emitted by the lexer:
#
#   bits 45..38  type    (8 bits, 256 token classes)
#   bits 37..26  length  (12 bits, max 4095 bytes per token)
#   bits 25..2   offset  (24 bits, max 16MB source files)
#   bit  1       reserved
#   bit  0       f_line_start (first non-whitespace token on its line)
#
# `self` IS the bare packed i64 — there is no separate object wrapper.
# Method calls on any W_LEXICAL_TOKEN value route here via the runtime's
# w_dispatch_key (W_TAG_CHAR subtype 00 → 0xD0). Field-extraction
# methods are direct shift+mask on `self`; the optimizer can fold them
# to a single instruction once the lowering recognizer learns the
# Token.X → inline-bitop rewrite (TODO).
#
# Methods that need the raw bytes (.value, .equal?) take the source
# buffer as an argument — Token itself carries only (offset, length).
# The enclosing File node holds the buffer.

# --- Token type constants ---
#
# These integer ids populate the 8-bit type field of W_LEXICAL_TOKEN.
# Bracket 1..25 mirrors the SIMD lexer's broad categories (compiler/
# lib/lexer.w `t_id`..`t_sp`); the materialize step re-packs with a
# refined id (T_KEYWORD, T_LPAREN, T_PLUS, …) for the parser to dispatch
# on. The parser checks `tok.type == T_X` instead of `tok[:type] == :X`,
# eliminating both the symbol comparison and the wrapping hash.

# Sentinel
T_UNKNOWN         = 0

# 1..25 — SIMD broad categories (must match compiler/lib/lexer.w t_*)
T_ID              = 1
T_NAME            = 2
T_INT             = 3
T_DECIMAL         = 4
T_STRING          = 5
T_SYMBOL          = 6
T_TYPE_HINT       = 7
T_NEWLINE         = 8
T_INDENT          = 9
T_DEDENT          = 10
T_OP              = 11
T_IVAR            = 12
T_CVAR            = 13
T_PARG            = 14
T_BYTE_ARRAY      = 15
T_KEY             = 16
T_COLOR           = 17
T_CHAR            = 18
T_CODEPOINT       = 19
T_WORD_ARRAY      = 20
T_SYMBOL_ARRAY    = 21
T_MAGIC           = 22
T_EOF             = 23
T_PATH            = 24
T_SP              = 25

# 26..29 — refinements of T_ID (`materialize_id` discriminates)
T_KEYWORD         = 26
T_TYPE            = 27
T_GLOBAL          = 28
T_AND             = 29  # `and` keyword
T_OR              = 30  # `or` keyword

# 31..49 — refinements of T_INT / T_DECIMAL / T_STRING (numeric + string-like
# forms discriminated by `materialize_number` / `materialize_string_like`)
T_FLOAT           = 31
T_RATIONAL        = 32
T_WVALUE          = 33
T_DATE            = 34
T_DATETIME        = 35
T_TIME            = 36
T_MONTH           = 37
T_DURATION        = 38
T_IP              = 39
T_CIDR            = 40
T_UUID            = 41
T_BASE            = 42
T_CURRENCY        = 43
T_QUANTITY        = 44
T_LAMBDA_ARITY    = 45
T_REGEX_CAPTURE   = 46
T_STRING_INTERP   = 47
T_REGEX           = 48
T_BYTE_ARRAY_INTERP = 49

# 50..79 — bracketing / punctuation / control operators (refinements of T_OP)
T_LPAREN          = 50
T_RPAREN          = 51
T_LBRACE          = 52
T_RBRACE          = 53
T_LBRACKET        = 54
T_RBRACKET        = 55
T_COMMA           = 56
T_COLON           = 57
T_SEMICOLON       = 58
T_DOT             = 59
T_DOTDOT          = 60
T_DOTDOTDOT       = 61
T_ARROW           = 62
T_FAT_ARROW       = 63
T_SAFE_NAV        = 64
T_BANG            = 65
T_QUESTION        = 66
T_PIPE_FWD        = 67
T_MAP             = 68
T_BLOCK_CALL      = 69
T_CLASS_DEF       = 70
T_PUTS_OP         = 71
T_PRINT_OP        = 72
T_RAISE_OP        = 73

# 80..89 — arithmetic
T_PLUS            = 80
T_MINUS           = 81
T_STAR            = 82
T_SLASH           = 83
T_PERCENT         = 84
T_POW             = 85

# 90..99 — assignment / compound-assign
T_ASSIGN          = 90
T_PLUS_EQ         = 91
T_MINUS_EQ        = 92
T_STAR_EQ         = 93
T_SLASH_EQ        = 94
T_PERCENT_EQ      = 95
T_OR_ASSIGN       = 96

# 100..109 — comparison
T_EQ              = 100
T_NEQ             = 101
T_LT              = 102
T_GT              = 103
T_LTE             = 104
T_GTE             = 105
T_SPACESHIP       = 106
T_MATCH           = 107

# 110..119 — bitwise
T_LSHIFT          = 110
T_RSHIFT          = 111
T_AMPERSAND       = 112
T_PIPE            = 113
T_CARET           = 114

# 120..129 — vector products + increment/decrement
T_DOT_PRODUCT     = 120
T_CROSS_PRODUCT   = 121
T_PLUS_PLUS       = 122
T_MINUS_MINUS     = 123
T_HADAMARD        = 124
T_KRONECKER       = 125

# 130..139 — dot-prefix elementwise (Julia convention)
T_DOT_PLUS        = 130
T_DOT_MINUS       = 131
T_DOT_STAR        = 132
T_DOT_SLASH       = 133
T_DOT_PIPE        = 134
T_DOT_AMP         = 135
T_DOT_CARET       = 136
T_DOT_LSHIFT      = 137
T_DOT_RSHIFT      = 138

# 140..149 — magic constants
T_MAGIC_FILE      = 140
T_MAGIC_LINE      = 141
T_MAGIC_DIR       = 142

# 143..152 — other lexer-emitted refinements not yet categorized
T_SUPERSCRIPT     = 143
T_FIELD           = 144
T_BASE32          = 145
T_BASE58          = 146
T_BASE64          = 147
T_IP4             = 148
T_CIDR4           = 149
T_NMATCH          = 150
T_TRIPLE_EQ       = 151
# ALL_CAPS identifier — distinguishes assignable constants (SC_2,
# KIND_VAR, BUILTIN_TYPES) from class references (Integer, Hash —
# T_NAME). The chunker classifies both as type_id 2; the materialize
# step splits them based on whether the raw bytes contain any
# lowercase letter.
T_CONSTANT        = 152

# A Unicode superscript run after a value — `x⁷`, `(a+b)¹²`. The lexer
# decodes the digits and stores them as the token value; the parser turns
# `value EXPONENT(n)` into `value ** n`. A distinct token (vs POW + INT)
# keeps the superscript origin visible at the token level.
T_EXPONENT        = 153

# `√` prefix square root — `√(Δx² + Δy² + Δz²)` ⇒ `(…).sqrt`.
T_SQRT            = 154

# `<>` swap operator — `a <> b` swaps two variables (desugars to a
# MultiAssign destructuring `[b, a]`).
T_SWAP            = 155

# IPv6 address / CIDR literals (RFC 5952) — `::1`, `2001:db8::1`,
# `2001:db8::/32`. Scoped to lowercase forms containing `::` (zero-
# compression) so `:` stays unambiguous vs symbols/ternary/namespaces/
# hash-keys, and uppercase stays available for class references.
T_IP6             = 156
T_CIDR6           = 157

# `%h<dim>-<type>[c0 c1 …]` hypercomplex literal, e.g. `%h4-f32[1 2 3 4]`.
T_HYPER_ARRAY     = 158

# Measurement constructor operator: `value ± standard_uncertainty`.
T_PLUS_MINUS      = 159

+ Token
  # Force-load helper — referencing this from a caller triggers the
  # autoload pass to load core/token.w, which in turn registers Token
  # with the runtime dispatch table for W_TAG_CHAR subtype 00 (0xD0).
  # Returns nil so callers can use it as a side-effecting no-op.
  -> .ensure_loaded
    nil

  # Construct a Token (W_LEXICAL_TOKEN packed i64) from (type_id, off,
  # length). Routes through the C runtime so the W_TAG_CHAR bits 48..63
  # survive the boundary — a pure-Tungsten `tag | (type<<38) | …`
  # helper would mask the type-tag arg to Integer's 48-bit range and
  # `(w64 w64 w64)` type hints don't propagate to the `|` operator.
  -> .make(type_id, off, length)
    ccall_nobox("w_make_token_extern", type_id, length, off)

  # Token type id (the lexer's classification index 0..63). `$value`
  # lowers self to its raw 64-bit content (untagged i64), making the
  # `>>` and `&` here resolve to raw integer ops rather than dispatch
  # through Char's operators.
  -> type
    ($value >> 38) & 0xFF

  # First-byte source offset of this token.
  -> offset
    ($value >> 2) & 0xFFFFFF

  # Length in source bytes (raw, before escape decoding).
  -> length
    ($value >> 26) & 0xFFF

  # f_line_start flag (bit 0).
  -> line_start?
    ($value & 0x1) != 0

  # Raw source bytes for this token. Caller supplies the source
  # buffer (typically the enclosing File node's :source slot).
  -> value(source)
    source.slice(offset, length)

  # Equality against a literal string — avoids materializing the
  # slice when the lengths differ. Caller supplies source.
  -> equal?(source, literal)
    if length != literal.size()
      return false
    value(source) == literal

  -> to_s
    "Token(type=" + type.to_s() + ", off=" + offset.to_s() + ", len=" + length.to_s() + ")"
