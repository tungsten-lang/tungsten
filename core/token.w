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
# refined id (TOK_KEYWORD, TOK_LPAREN, TOK_PLUS, …) for the parser to dispatch
# on. The parser checks `tok.type == T_X` instead of `tok[:type] == :X`,
# eliminating both the symbol comparison and the wrapping hash.

# Sentinel
TOK_UNKNOWN         = 0

# 1..25 — SIMD broad categories (must match compiler/lib/lexer.w t_*)
TOK_ID              = 1
TOK_NAME            = 2
TOK_INT             = 3
TOK_DECIMAL         = 4
TOK_STRING          = 5
TOK_SYMBOL          = 6
TOK_TYPE_HINT       = 7
TOK_NEWLINE         = 8
TOK_INDENT          = 9
TOK_DEDENT          = 10
TOK_OP              = 11
TOK_IVAR            = 12
TOK_CVAR            = 13
TOK_PARG            = 14
TOK_BYTE_ARRAY      = 15
TOK_KEY             = 16
TOK_COLOR           = 17
TOK_CHAR            = 18
TOK_CODEPOINT       = 19
TOK_WORD_ARRAY      = 20
TOK_SYMBOL_ARRAY    = 21
TOK_MAGIC           = 22
TOK_EOF             = 23
TOK_PATH            = 24
TOK_SP              = 25

# 26..29 — refinements of TOK_ID (`materialize_id` discriminates)
TOK_KEYWORD         = 26
TOK_TYPE            = 27
TOK_GLOBAL          = 28
TOK_AND             = 29  # `and` keyword
TOK_OR              = 30  # `or` keyword

# 31..49 — refinements of TOK_INT / TOK_DECIMAL / TOK_STRING (numeric + string-like
# forms discriminated by `materialize_number` / `materialize_string_like`)
TOK_FLOAT           = 31
TOK_RATIONAL        = 32
TOK_WVALUE          = 33
TOK_DATE            = 34
TOK_DATETIME        = 35
TOK_TIME            = 36
TOK_MONTH           = 37
TOK_DURATION        = 38
TOK_IP              = 39
TOK_CIDR            = 40
TOK_UUID            = 41
TOK_BASE            = 42
TOK_CURRENCY        = 43
TOK_QUANTITY        = 44
TOK_LAMBDA_ARITY    = 45
TOK_REGEX_CAPTURE   = 46
TOK_STRING_INTERP   = 47
TOK_REGEX           = 48
TOK_BYTE_ARRAY_INTERP = 49

# 50..79 — bracketing / punctuation / control operators (refinements of TOK_OP)
TOK_LPAREN          = 50
TOK_RPAREN          = 51
TOK_LBRACE          = 52
TOK_RBRACE          = 53
TOK_LBRACKET        = 54
TOK_RBRACKET        = 55
TOK_COMMA           = 56
TOK_COLON           = 57
TOK_SEMICOLON       = 58
TOK_DOT             = 59
TOK_DOTDOT          = 60
TOK_DOTDOTDOT       = 61
TOK_ARROW           = 62
T_FAT_ARROW       = 63
TOK_SAFE_NAV        = 64
TOK_BANG            = 65
TOK_QUESTION        = 66
TOK_PIPE_FWD        = 67
TOK_MAP             = 68
TOK_BLOCK_CALL      = 69
TOK_CLASS_DEF       = 70
TOK_PUTS_OP         = 71
T_PRINT_OP        = 72
TOK_RAISE_OP        = 73

# 80..89 — arithmetic
TOK_PLUS            = 80
TOK_MINUS           = 81
TOK_STAR            = 82
TOK_SLASH           = 83
TOK_PERCENT         = 84
TOK_POW             = 85

# 90..99 — assignment / compound-assign
TOK_ASSIGN          = 90
TOK_PLUS_EQ         = 91
TOK_MINUS_EQ        = 92
TOK_STAR_EQ         = 93
TOK_SLASH_EQ        = 94
T_PERCENT_EQ      = 95
TOK_OR_ASSIGN       = 96

# 100..109 — comparison
TOK_EQ              = 100
TOK_NEQ             = 101
TOK_LT              = 102
TOK_GT              = 103
TOK_LTE             = 104
TOK_GTE             = 105
TOK_SPACESHIP       = 106
TOK_MATCH           = 107

# 110..119 — bitwise
TOK_LSHIFT          = 110
TOK_RSHIFT          = 111
TOK_AMPERSAND       = 112
TOK_PIPE            = 113
TOK_CARET           = 114

# 120..129 — vector products + increment/decrement
T_DOT_PRODUCT     = 120
TOK_CROSS_PRODUCT   = 121
TOK_PLUS_PLUS       = 122
TOK_MINUS_MINUS     = 123
TOK_HADAMARD        = 124
TOK_KRONECKER       = 125

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
TOK_MAGIC_FILE      = 140
TOK_MAGIC_LINE      = 141
TOK_MAGIC_DIR       = 142

# 143..152 — other lexer-emitted refinements not yet categorized
TOK_SUPERSCRIPT     = 143
TOK_FIELD           = 144
TOK_BASE32          = 145
TOK_BASE58          = 146
TOK_BASE64          = 147
TOK_IP4             = 148
TOK_CIDR4           = 149
TOK_NMATCH          = 150
TOK_TRIPLE_EQ       = 151
# ALL_CAPS identifier — distinguishes assignable constants (SC_2,
# KIND_VAR, BUILTIN_TYPES) from class references (Integer, Hash —
# TOK_NAME). The chunker classifies both as type_id 2; the materialize
# step splits them based on whether the raw bytes contain any
# lowercase letter.
TOK_CONSTANT        = 152

# A Unicode superscript run after a value — `x⁷`, `(a+b)¹²`. The lexer
# decodes the digits and stores them as the token value; the parser turns
# `value EXPONENT(n)` into `value ** n`. A distinct token (vs POW + INT)
# keeps the superscript origin visible at the token level.
TOK_EXPONENT        = 153

# `√` prefix square root — `√(Δx² + Δy² + Δz²)` ⇒ `(…).sqrt`.
TOK_SQRT            = 154

# `<>` swap operator — `a <> b` swaps two variables (desugars to a
# MultiAssign destructuring `[b, a]`).
TOK_SWAP            = 155

# IPv6 address / CIDR literals (RFC 5952) — `::1`, `2001:db8::1`,
# `2001:db8::/32`. Scoped to lowercase forms containing `::` (zero-
# compression) so `:` stays unambiguous vs symbols/ternary/namespaces/
# hash-keys, and uppercase stays available for class references.
TOK_IP6             = 156
TOK_CIDR6           = 157

# `%h<dim>-<type>[c0 c1 …]` hypercomplex literal, e.g. `%h4-f32[1 2 3 4]`.
TOK_HYPER_ARRAY     = 158

# Measurement constructor operator: `value ± standard_uncertainty`.
TOK_PLUS_MINUS      = 159

# Consuming compound assignment. These remain distinct tokens so the
# lowering pass can select a destination-reusing BigInt entry only after its
# liveness proof succeeds; ordinary binary operators stay immutable.
TOK_POW_EQ          = 160
TOK_AMP_EQ          = 161
TOK_PIPE_EQ         = 162
T_CARET_EQ        = 163
T_LSHIFT_EQ       = 164
T_RSHIFT_EQ       = 165

# `%d[1.0 2.5 …]` decimal array literal — desugars in the parser to a
# plain Array of Decimal literals (no dedicated AST kind).
TOK_DECIMAL_ARRAY   = 166

# `%f32[…]` / `%f64[…]` typed float array literals — desugar in the
# parser to a Float-literal Array converted via Array#to_f32/to_f64
# into a real typed buffer (ebits -32/-64).
T_FLOAT_ARRAY     = 167

# `a ≈ b` — approximate equality (equality precedence; w_approx_eq).
TOK_APPROX          = 168

# Tight postfix primorial: product of primes at most the receiver.
TOK_PRIMORIAL       = 169

# Mathematical composition, tetration, and set notation.
TOK_COMPOSE         = 170
TOK_TETRATE         = 171
TOK_MEMBER          = 172
T_NOT_MEMBER      = 173
TOK_UNION           = 174
TOK_INTERSECTION    = 175
TOK_SUBSET          = 176

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
