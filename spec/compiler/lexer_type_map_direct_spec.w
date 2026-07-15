# Exact semantic coverage for the Lexer token-symbol-to-id mapping. The
# isolated direct-helper trial leaves these public methods available while
# routing Lexer#emit and Lexer#emit_at through top-level helpers.
#
# This deliberately does not exercise subclass overrides from inherited emit
# methods: devirtualizing those two internal calls changes that unsupported
# extension point, which the trial audit and benchmark note call out.

use ../../compiler/lib/lexer

-> check(name, got, want)
  if got != want
    << "FAIL lexer type map " + name + " got=" + got.to_s() + " want=" + want.to_s()
    exit(1)

-> packed_type_for_probe(tok)
  (tok >> 38) & 0xFF

+ LexerTypeMapProbe < Lexer
  # Avoid the production constructor's source-table setup. Mapping wrappers
  # need no fields; emit/push_token need only this deliberately small state.
  -> new
    @packed_tokens = []
    @values = []
    @token_count = 0
    @last_token_type = nil
    @last_token_value = nil
    @regex_capture_scope = false
    @current_packed_tok = 0
    @col = 1

+ LexerTypeMapOverrideProbe < LexerTypeMapProbe
  -> type_sym_to_id(sym)
    199

syms = [
  :ID, :NAME, :INT, :DECIMAL, :STRING, :SYMBOL, :TYPE_HINT, :NEWLINE,
  :INDENT, :DEDENT, :IVAR, :CVAR, :PARG, :BYTE_ARRAY, :KEY, :COLOR,
  :CHAR, :CODEPOINT, :WORD_ARRAY, :SYMBOL_ARRAY, :MAGIC, :EOF, :PATH,
  :SP, :KEYWORD, :TYPE, :GLOBAL, :AND, :OR,
  :FLOAT, :RATIONAL, :WVALUE, :DATE, :DATETIME, :TIME, :MONTH,
  :DURATION, :IP, :CIDR, :UUID, :BASE, :CURRENCY, :QUANTITY,
  :LAMBDA_ARITY, :REGEX_CAPTURE, :STRING_INTERP, :REGEX,
  :BYTE_ARRAY_INTERP,
  :LPAREN, :RPAREN, :LBRACE, :RBRACE, :LBRACKET, :RBRACKET, :COMMA,
  :COLON, :SEMICOLON, :DOT, :DOTDOT, :DOTDOTDOT, :ARROW, :FAT_ARROW,
  :SAFE_NAV, :BANG, :QUESTION, :PIPE_FWD, :MAP, :BLOCK_CALL, :CLASS_DEF,
  :PUTS_OP, :PRINT_OP, :RAISE_OP,
  :PLUS, :MINUS, :STAR, :SLASH, :PERCENT, :POW,
  :ASSIGN, :PLUS_EQ, :MINUS_EQ, :STAR_EQ, :SLASH_EQ, :PERCENT_EQ,
  :OR_ASSIGN,
  :EQ, :NEQ, :LT, :GT, :LTE, :GTE, :SPACESHIP, :MATCH,
  :LSHIFT, :RSHIFT, :AMPERSAND, :PIPE, :CARET,
  :DOT_PRODUCT, :CROSS_PRODUCT, :PLUS_PLUS, :MINUS_MINUS, :HADAMARD,
  :KRONECKER,
  :DOT_PLUS, :DOT_MINUS, :DOT_STAR, :DOT_SLASH, :DOT_PIPE, :DOT_AMP,
  :DOT_CARET, :DOT_LSHIFT, :DOT_RSHIFT,
  :MAGIC_FILE, :MAGIC_LINE, :MAGIC_DIR, :SUPERSCRIPT, :FIELD, :BASE32,
  :BASE58, :BASE64, :IP4, :CIDR4, :NMATCH, :TRIPLE_EQ, :CONSTANT,
  :EXPONENT, :SQRT, :SWAP, :IP6, :CIDR6, :HYPER_ARRAY, :PLUS_MINUS
]
ids = [
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 13, 14, 15, 16, 17, 18, 19,
  20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30,
  31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47,
  48, 49,
  50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65,
  66, 67, 68, 69, 70, 71, 72, 73,
  80, 81, 82, 83, 84, 85,
  90, 91, 92, 93, 94, 95, 96,
  100, 101, 102, 103, 104, 105, 106, 107,
  110, 111, 112, 113, 114,
  120, 121, 122, 123, 124, 125,
  130, 131, 132, 133, 134, 135, 136, 137, 138,
  140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152,
  153, 154, 155, 156, 157, 158, 159
]

check("mapping table sizes", syms.size(), ids.size())
lexer = LexerTypeMapProbe.new()
i = 0
while i < syms.size()
  sym = syms[i]
  id = ids[i]
  check("aggregate " + sym.to_s(), lexer.type_sym_to_id(sym), id)

  want_a = 0
  want_b = 0
  want_c = 0
  if id <= 30
    want_a = id
  elsif id <= 49
    want_b = id
  else
    want_c = id
  check("segment a " + sym.to_s(), lexer.type_sym_to_id_a(sym), want_a)
  check("segment b " + sym.to_s(), lexer.type_sym_to_id_b(sym), want_b)
  check("segment c " + sym.to_s(), lexer.type_sym_to_id_c(sym), want_c)
  i += 1

# T_UNKNOWN=0 and the broad SIMD-only T_OP=11 intentionally have no refined
# symbol mapping. Any unrecognized symbol follows the same zero path.
check("unknown sentinel", lexer.type_sym_to_id(:UNKNOWN), 0)
check("broad op", lexer.type_sym_to_id(:OP), 0)
check("unrecognized", lexer.type_sym_to_id(:NOT_A_TOKEN), 0)
check("nil", lexer.type_sym_to_id(nil), 0)

# One representative from every segment goes through each internal
# materializer. Candidate builds reach the top-level aggregate directly;
# baseline builds exercise the original virtual chain.
emitter = LexerTypeMapProbe.new()
emitter.emit(:OR, nil)
emitter.emit(:FLOAT, nil)
emitter.emit_at(:PLUS_MINUS, nil, 0)
packed = emitter.packed_tokens()
check("emit token count", packed.size(), 3)
check("emit segment a", packed_type_for_probe(packed[0]), 30)
check("emit segment b", packed_type_for_probe(packed[1]), 31)
check("emit_at segment c", packed_type_for_probe(packed[2]), 159)

unknown_emitter = LexerTypeMapProbe.new()
unknown_emitter.emit(:OP, nil)
check("emit unknown remains zero", unknown_emitter.packed_tokens()[0], 0)

# The public aggregate remains an ordinary virtual entry point. Inherited
# emit/emit_at intentionally no longer consult such an override in the
# candidate; repository-wide audits must establish that Lexer has no subclass.
override = LexerTypeMapOverrideProbe.new()
check("public aggregate override", override.type_sym_to_id(:PLUS), 199)

<< "PASS lexer type-symbol mapping semantics"
