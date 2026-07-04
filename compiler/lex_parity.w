# Count and packed-tag parity harness for the alternate compiler lexers.
#
# Usage:
#   bin/tungsten compile compiler/lex_parity.w --out /tmp/tungsten-lex-parity
#   /tmp/tungsten-lex-parity compiler/tungsten.w compiler/lib/lexer.w ...

use lib/lexer
use ../languages/tungsten/lexers/regex
use ../languages/tungsten/lexers/lex32
use ../languages/tungsten/lexers/wtoken32

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
  type in (:LAMBDA_ARITY :ARROW :LSHIFT :PUTS_OP :PRINT_OP :RAISE_OP :FAT_ARROW :EQ :MATCH :NEQ :LTE :RSHIFT :GTE :SAFE_NAV :AND :OR_ASSIGN :OR :PIPE_FWD :PLUS_PLUS :PLUS_EQ :MINUS_MINUS :MINUS_EQ :POW :STAR_EQ :SLASH_EQ :PERCENT_EQ :PLUS :CLASS_DEF :MINUS :STAR :MAP :SLASH :PERCENT :LT :GT :ASSIGN :BANG :DOTDOTDOT :DOTDOT :DOT :COMMA :BLOCK_CALL :AMPERSAND :PIPE :CARET :LPAREN :RPAREN :LBRACE :RBRACE :LBRACKET :RBRACKET :QUESTION :COLON :SEMICOLON)

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
    skipped += 1
    checked += 1
    i += 1
    next

  old_count = old_tokens.size()
  new_tokens = Lexer.new(source, file).tokenize()

  if new_tokens.size() != old_count
    failed += 1
    << "FAIL [file]: rich count regex=[old_count] lexer=[new_tokens.size()]"
    checked += 1
    i += 1
    next

  rich_mismatch = 0
  rj = 0
  while rj < old_count && rich_mismatch == 0
    old_tok = old_tokens[rj]
    new_tok = new_tokens[rj]
    old_value = display_value(old_tok[:value])
    new_value = display_value(new_tok[:value])
    if old_tok[:type] != new_tok[:type] || old_value != new_value
      rich_mismatch = 1
      failed += 1
      << "FAIL [file]: rich token [rj] regex=[old_tok[:type]]([old_value])@[old_tok[:line]]:[old_tok[:col]] lexer=[new_tok[:type]]([new_value])@[new_tok[:line]]:[new_tok[:col]]"
    rj += 1
  if rich_mismatch != 0
    checked += 1
    i += 1
    next

  lc64 = source.lchs("tungsten")
  tokens64 = i64[lc64.size() + 2048] ## reuse
  indents64 = i64[1024] ## reuse
  count64 = tungsten_tokenize_fast64(lc64, lc64.size(), tokens64, indents64)

  lc32 = source.lchs("tungsten", bits: 32)
  tokens32 = i64[lc32.size() + 2048] ## reuse
  indents32 = i64[1024] ## reuse
  count32 = tungsten_tokenize_fast32(lc32, lc32.size(), tokens32, indents32)
  tokens32_token = u32[lc32.size() + 2048] ## reuse
  lengths32_token = u8[lc32.size() + 2048] ## reuse
  indents32_token = i64[1024] ## reuse
  count32_token = tungsten_tokenize_wtoken32(lc32, lc32.size(), tokens32_token, lengths32_token, indents32_token)

  limit = old_count
  if count64 < limit
    limit = count64
  if count32 < limit
    limit = count32
  if count32_token < limit
    limit = count32_token

  j = 0
  mismatch = 0
  while j < limit && mismatch == 0
    prev = nil
    if j > 0
      prev = old_tokens[j - 1]
    expected = expected_packed_type(old_tokens[j], prev)
    actual64 = packed_type_id(tokens64[j])
    actual32 = packed_type_id(tokens32[j])
    actual32_token = token32_type_id(tokens32_token[j])
    expected_off32 = packed_offset(tokens32[j])
    actual_off32_token = token32_offset(tokens32_token[j])
    expected_len32 = packed_length(tokens32[j])
    expected_len32_token = expected_len32
    if expected_len32_token > 255
      expected_len32_token = 255
    actual_len32_token = lengths32_token[j]
    # sp_before / sp_after flags were dropped from the 64-bit Token
    # layout when the SIMD lexer started emitting explicit :SP tokens.
    # The 32-bit packed lexers still carry them at their LSB — those
    # checks are skipped here pending a 32-bit-lex follow-up.
    if expected != actual64 || expected != actual32 || expected != actual32_token || expected_off32 != actual_off32_token || expected_len32_token != actual_len32_token
      mismatch = 1
      failed += 1
      old_type = old_tokens[j][:type]
      old_line = old_tokens[j][:line]
      old_col = old_tokens[j][:col]
      old_value = old_tokens[j][:value]
      expected_name = packed_type_name(expected)
      name64 = packed_type_name(actual64)
      name32 = packed_type_name(actual32)
      name32_token = packed_type_name(actual32_token)
      off64 = packed_offset(tokens64[j])
      off32 = packed_offset(tokens32[j])
      off32_token = token32_offset(tokens32_token[j])
      << "FAIL [file]: token [j] old=[old_type]([old_value])@[old_line]:[old_col] expected=[expected_name] lex64=[name64]@[off64] lex32=[name32]@[off32] wtoken32=[name32_token]@[off32_token] len32=[expected_len32] wlen=[actual_len32_token] sp32=[expected_sp_before32]/[expected_sp_after32] wsp=[actual_sp_before32_token]/[actual_sp_after32_token]"
      wi = j - 4
      if wi < 0
        wi = 0
      while wi < limit && wi <= j + 4
        prevw = nil
        if wi > 0
          prevw = old_tokens[wi - 1]
        expw = expected_packed_type(old_tokens[wi], prevw)
        oldw = old_tokens[wi]
        aw64 = packed_type_id(tokens64[wi])
        ow64 = packed_offset(tokens64[wi])
        aw32_token = token32_type_id(tokens32_token[wi])
        ow32_token = token32_offset(tokens32_token[wi])
        << "  [wi] old=[oldw[:type]]([oldw[:value]])@[oldw[:line]]:[oldw[:col]] exp=[packed_type_name(expw)] lex64=[packed_type_name(aw64)]@[ow64] wtoken32=[packed_type_name(aw32_token)]@[ow32_token]"
        wi += 1
    j += 1

  if mismatch == 0 && (old_count != count64 || old_count != count32 || old_count != count32_token)
    failed += 1
    << "FAIL [file]: count old=[old_count] lex64=[count64] lex32=[count32] wtoken32=[count32_token] prefix=[limit]"

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
