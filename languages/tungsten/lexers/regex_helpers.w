# Reference lexer for Tungsten — character-at-a-time scanning with NaN-boxed LexChar
#
# Source is converted to LexChar values (0xFFFC tag, subtype 01):
#   bits 38-18: codepoint (21 bits)
# The default LexChar layout carries digit_value in bits 10-7. Language-
# specific `lchs("tungsten")` replaces the low byte with Tungsten flags, so
# digit recognition uses the codepoint and works with both layouts.
#
# LexChar flag bits (at LSB):
#   bit 6: IS_ID_START    (a-z, _)
#   bit 5: IS_ID_CONTINUE (a-z, 0-9, _)
#   bit 4: IS_WHITESPACE  (space, tab)
#   bit 3: IS_HEX         (0-9, a-f, A-F)

# Extract codepoint from LexChar value
-> lc_cp(lc)
  bits = wvalue_bits(lc) ## i64
  (bits >> 18) & 2097151

# LexChar predicates — test packed flag bits
-> is_digit?(lc)
  cp = lc_cp(lc)
  cp >= 48 && cp <= 57

-> is_lower?(lc)
  lc_cp(lc) >= 97 && lc_cp(lc) <= 122

-> is_upper?(lc)
  lc_cp(lc) >= 65 && lc_cp(lc) <= 90

-> is_alpha?(lc)
  is_lower?(lc) || is_upper?(lc)

-> is_ident_start?(lc)
  (wvalue_bits(lc) & 64) != 0

-> is_ident_char?(lc)
  (wvalue_bits(lc) & 32) != 0

-> is_name_char?(lc)
  (wvalue_bits(lc) & 32) != 0 || is_upper?(lc)

-> is_keyword?(word)
  n = word.size()
  if n < 2 || n > 8 || n == 7
    return false
  case n
  when 2
    word == "if" || word == "in" || word == "fn" || word == "is" || word == "on" || word == "go"
  when 3
    word == "nil" || word == "use"
  when 4
    word == "else" || word == "true" || word == "self" || word == "when" || word == "case" || word == "next" || word == "with" || word == "then" || word == "loop" || word == "exit"
  when 5
    word == "while" || word == "false" || word == "elsif" || word == "break" || word == "raise" || word == "begin" || word == "super" || word == "trait" || word == "until" || word == "yield"
  when 6
    word == "return" || word == "rescue" || word == "unless" || word == "ensure" || word == "module" || word == "extern" || word == "recase"
  when 8
    word == "parallel"
  else
    false

-> is_type_name?(word)
  n = word.size()
  if n < 2 || n > 13
    return false
  case n
  when 2
    word == "i8" || word == "u8" || word == "i1" || word == "i4" || word == "u1" || word == "u4"
  when 3
    word == "i64" || word == "i32" || word == "f64" || word == "f32" || word == "u64" || word == "u32" || word == "w64" || word == "int" || word == "i16" || word == "u16" || word == "f16" || word == "f80" || word == "c32" || word == "c64" || word == "fp8" || word == "fp4" || word == "nf4"
  when 4
    word == "bool" || word == "i128" || word == "u128" || word == "f128" || word == "f256" || word == "d128" || word == "c128" || word == "bf16" || word == "tf32"
  when 5
    word == "mxfp8" || word == "mxfp6" || word == "mxfp4"
  when 6
    word == "string" || word == "bigint" || word == "mxint8" || word == "posit8"
  when 7
    word == "integer" || word == "posit16" || word == "posit32" || word == "posit64"
  when 10
    word == "bigdecimal"
  when 13
    word == "string_buffer"
  else
    false

-> is_currency_prefix?(ch)
  ch == "$" || ch == "€" || ch == "£" || ch == "¥" || ch == "₹" || ch == "₩" || ch == "₿" || ch == "₽" || ch == "฿"

-> is_currency_suffix?(ch)
  ch == "¢" || ch == "円" || ch == "元"

-> is_greek_math?(ch)
  ch == "π" || ch == "τ" || ch == "ϕ" || ch == "φ" || ch == "ℯ" || ch == "ℇ" || ch == "∞" || ch == "ℎ" || ch == "ℏ" || ch == "σ" || ch == "ε" || ch == "μ"

-> is_subscript?(ch)
  ch == "₀" || ch == "₁" || ch == "₂" || ch == "₃" || ch == "₄" || ch == "₅" || ch == "₆" || ch == "₇" || ch == "₈" || ch == "₉" || ch == "ₐ" || ch == "ₑ" || ch == "ₕ" || ch == "ᵢ" || ch == "ⱼ" || ch == "ₖ" || ch == "ₗ" || ch == "ₘ" || ch == "ₙ" || ch == "ₒ" || ch == "ₚ" || ch == "ᵣ" || ch == "ₛ" || ch == "ₜ" || ch == "ᵤ" || ch == "ᵥ" || ch == "ₓ" || ch == "ₔ"

-> is_superscript_digit?(ch)
  ch == "⁰" || ch == "¹" || ch == "²" || ch == "³" || ch == "⁴" || ch == "⁵" || ch == "⁶" || ch == "⁷" || ch == "⁸" || ch == "⁹"

-> is_superscript_sign?(ch)
  ch == "⁻" || ch == "⁺"

-> is_superscript_char?(ch)
  is_superscript_digit?(ch) || is_superscript_sign?(ch)

-> is_base32_char?(lc)
  cp = lc_cp(lc)
  (cp >= 50 && cp <= 55) || is_upper?(lc)

-> is_base58_char?(lc)
  cp = lc_cp(lc)
  (cp >= 49 && cp <= 57) || (cp >= 65 && cp <= 72) || (cp >= 74 && cp <= 78) || (cp >= 80 && cp <= 90) || (cp >= 97 && cp <= 107) || (cp >= 109 && cp <= 122)

-> is_base64_char?(lc)
  cp = lc_cp(lc)
  is_alpha?(lc) || is_digit?(lc) || cp == 43 || cp == 47 || cp == 61

-> is_value_type?(type)
  if type == nil || type == :NEWLINE || type == :INDENT || type == :DEDENT || type == :LPAREN || type == :COMMA || type == :ASSIGN || type == :COLON || type == :LBRACKET || type == :ARROW || type == :KEYWORD || type == :PUTS_OP || type == :EQ || type == :NEQ || type == :AND || type == :OR || type == :PLUS || type == :MINUS || type == :STAR || type == :SLASH || type == :LT || type == :GT || type == :LTE || type == :GTE || type == :LBRACE
    return false
  type == :ID || type == :RPAREN || type == :INT || type == :STRING || type == :IVAR || type == :SYMBOL || type == :NAME || type == :CONSTANT || type == :RBRACKET || type == :FLOAT || type == :DECIMAL || type == :TYPE || type == :RBRACE || type == :STRING_INTERP || type == :GLOBAL || type == :CVAR || type == :REGEX || type == :REGEX_CAPTURE || type == :MAGIC_FILE || type == :MAGIC_LINE || type == :MAGIC_DIR || type == :UUID || type == :CURRENCY || type == :QUANTITY || type == :DURATION || type == :WVALUE || type == :BYTE_ARRAY || type == :BYTE_ARRAY_INTERP || type == :DATE || type == :DATETIME || type == :TIME || type == :MONTH || type == :IP4 || type == :CIDR4 || type == :IP6 || type == :CIDR6 || type == :RATIONAL || type == :CHAR || type == :CODEPOINT || type == :KEY || type == :WORD_ARRAY || type == :SYMBOL_ARRAY || type == :BASE32 || type == :BASE58 || type == :BASE64 || type == :PARG || type == :SUPERSCRIPT || type == :EXPONENT || type == :COLOR || type == :SELF_REF

-> strip_bash_shebang(source)
  # Polyglot scripts begin with `#!/usr/bin/env bash` then an `exec` line
  # that re-execs the file under tungsten. The `#!` line is already a comment
  # to Tungsten; the `exec` line would parse as code. Comment it out so the
  # file parses identically through every entry point. Line numbers stay
  # stable because we only mutate the existing line in-place.
  if !source.starts_with?("#!")
    return source
  nl1 = source.index("\n")
  if nl1 == nil
    return source
  shebang = source.slice(0, nl1)
  if shebang.index("bash") == nil
    return source
  rest = source.slice(nl1 + 1, source.size() - nl1 - 1)
  if !rest.starts_with?("exec ")
    return source
  source.slice(0, nl1 + 1) + "#" + rest
