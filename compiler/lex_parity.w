# Semantic parity harness for the self-hosted RegexLexer and the packed
# production Lexer. Production-only :SP transport tokens are filtered before
# comparing refined token types and values.
#
# Usage:
#   bin/tungsten compile compiler/lex_parity.w --out /tmp/tungsten-lex-parity
#   /tmp/tungsten-lex-parity compiler/tungsten.w compiler/lib/lexer.w ...

use lib/lexer
use ../languages/tungsten/lexers/regex
use ../languages/tungsten/lexers/lex32
use ../languages/tungsten/lexers/wtoken32

# Link-time marker for the gated LexChar tables. Calls to String#lchs lower
# through an inline-cache slot whose IR does not retain the method name, so the
# ordinary IR text probe cannot discover the dependency by itself.
-> lexchars_link_marker
  nil

-> packed_type_id(tok)
  (tok >> 38) & 0xFF

-> packed_offset(tok)
  (tok >> 2) & 0xFFFFFF

-> packed_length(tok)
  (tok >> 26) & 0xFFF

-> packed_line_start?(tok)
  (tok & 0x1) != 0

-> token32_type_id(tok)
  (tok >> 2) & 0x3F

-> token32_offset(tok)
  tok >> 8

-> token32_sp_before?(tok)
  (tok & 0x1) != 0

-> token32_sp_after?(tok)
  (tok & 0x2) != 0

-> packed_type_name(id)
  if id == 1
    return "ID"
  if id == 2
    return "NAME"
  if id == 3
    return "INT"
  if id == 4
    return "DECIMAL"
  if id == 5
    return "STRING"
  if id == 6
    return "SYMBOL"
  if id == 7
    return "TYPE_HINT"
  if id == 8
    return "NEWLINE"
  if id == 9
    return "INDENT"
  if id == 10
    return "DEDENT"
  if id == 11
    return "OP"
  if id == 12
    return "IVAR"
  if id == 13
    return "CVAR"
  if id == 14
    return "PARG"
  if id == 15
    return "BYTE_ARRAY"
  if id == 16
    return "KEY"
  if id == 17
    return "COLOR"
  if id == 18
    return "CHAR"
  if id == 19
    return "CODEPOINT"
  if id == 20
    return "WORD_ARRAY"
  if id == 21
    return "SYMBOL_ARRAY"
  if id == 22
    return "MAGIC"
  if id == 23
    return "EOF"
  if id == 24
    return "PATH"
  "UNKNOWN"

-> op_like_type?(type)
  type in (:LAMBDA_ARITY :ARROW :LSHIFT :PUTS_OP :PRINT_OP :RAISE_OP :FAT_ARROW :EQ :MATCH :NEQ :LTE :RSHIFT :GTE :SAFE_NAV :AND :OR_ASSIGN :OR :PIPE_FWD :PLUS_PLUS :PLUS_EQ :MINUS_MINUS :MINUS_EQ :POW :STAR_EQ :SLASH_EQ :PERCENT_EQ :PLUS :PLUS_MINUS :CLASS_DEF :MINUS :STAR :MAP :SLASH :PERCENT :LT :GT :ASSIGN :BANG :DOTDOTDOT :DOTDOT :DOT :COMMA :BLOCK_CALL :AMPERSAND :PIPE :CARET :LPAREN :RPAREN :LBRACE :RBRACE :LBRACKET :RBRACKET :QUESTION :COLON :SEMICOLON)

-> expected_packed_type(tok, prev_tok)
  type = tok[:type]
  if type in (:ID :KEYWORD :TYPE :FIELD :SUPERSCRIPT)
    return 1
  if type == :NAME
    return 2
  if type in (:INT :DATE :MONTH :IP4 :CIDR4 :RATIONAL :BASE32 :BASE58 :BASE64 :UUID :WVALUE)
    return 3
  if type in (:DECIMAL :FLOAT :CURRENCY :QUANTITY :DURATION :TIME :DATETIME)
    return 4
  if type in (:STRING :STRING_INTERP :REGEX)
    if prev_tok != nil && prev_tok[:type] == :KEYWORD && prev_tok[:value] == "use"
      return 24
    return 5
  if type == :REGEX_CAPTURE
    return 4
  if type == :SYMBOL
    return 6
  if type == :TYPE_HINT
    return 7
  if type == :NEWLINE
    return 8
  if type == :INDENT
    return 9
  if type == :DEDENT
    return 10
  if op_like_type?(type)
    return 11
  if type == :IVAR
    return 12
  if type == :CVAR
    return 13
  if type == :PARG
    return 14
  if type in (:BYTE_ARRAY :BYTE_ARRAY_INTERP)
    return 15
  if type == :KEY
    return 16
  if type == :COLOR
    return 17
  if type == :CHAR
    return 18
  if type == :CODEPOINT
    return 19
  if type == :WORD_ARRAY
    return 20
  if type == :SYMBOL_ARRAY
    return 21
  if type in (:MAGIC_FILE :MAGIC_LINE :MAGIC_DIR)
    return 22
  if type == :EOF
    return 23
  0

-> display_value(value)
  if value == nil
    return ""
  value.to_s()

args = argv()
if args.size() == 0
  << "usage: lex_parity <file.w> \[file.w ...]"
  exit(1)

checked = 0
failed = 0
skipped = 0
i = 0
while i < args.size()
  file = args[i]
  source = read_file(file)
  if source == nil
    skipped += 1
    checked += 1
    i += 1
    next

  old_tokens = nil
  begin
    old_tokens = RegexLexer.new(source, file).tokenize()
  rescue err
    failed += 1
    << "FAIL [file]: RegexLexer raised [err]"
    checked += 1
    i += 1
    next

  old_count = old_tokens.size()
  new_lexer = Lexer.new(source, file)
  new_lexer.tokenize()
  packed = new_lexer.packed_tokens()
  values = new_lexer.values()
  line_at = new_lexer.line_at()
  col_at = new_lexer.col_at()

  # The production lexer preserves whitespace as explicit :SP tokens for the
  # parser. RegexLexer intentionally exposes the traditional semantic stream,
  # so compare after removing those transport-only entries.
  semantic_indices = []
  pj = 0
  while pj < packed.size()
    if packed_type_id(packed[pj]) != 25
      semantic_indices.push(pj)
    pj += 1

  if semantic_indices.size() != old_count
    failed += 1
    << "FAIL [file]: count regex=[old_count] production=[semantic_indices.size()]"
    checked += 1
    i += 1
    next

  mismatch = 0
  rj = 0
  while rj < old_count && mismatch == 0
    old_tok = old_tokens[rj]
    ni = semantic_indices[rj]
    new_tok = packed[ni]
    expected_type = new_lexer.type_sym_to_id(old_tok[:type])
    actual_type = packed_type_id(new_tok)
    old_value = display_value(old_tok[:value])
    new_value = display_value(values[ni])
    off = packed_offset(new_tok)
    new_line = line_at[off]
    new_col = col_at[off]
    # In an open unit type argument (`Tensor<f64, m/s>`) the production
    # lexer retains its context-free `/name` transport classification (:MAP),
    # while RegexLexer classifies `/` after a value as :SLASH. The parser's
    # type-argument collector intentionally accepts either spelling; normalize
    # that one lexically identical token for semantic parity.
    if old_tok[:type] == :SLASH && old_value == "/" && actual_type == 68 && new_value == "/"
      expected_type = actual_type
    if expected_type == 0 || expected_type != actual_type || old_value != new_value
      mismatch = 1
      failed += 1
      << "FAIL [file]: token [rj] regex=[old_tok[:type]]([old_value])@[old_tok[:line]]:[old_tok[:col]] production_type=[actual_type]([new_value])@[new_line]:[new_col]"
    rj += 1

  checked += 1
  i += 1

if failed == 0
  if skipped > 0
    << "OK [checked] files ([skipped] skipped)"
  else
    << "OK [checked] files"
else
  << "FAILED [failed] / [checked] files"
  exit(1)
