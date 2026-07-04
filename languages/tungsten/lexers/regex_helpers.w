# Reference lexer for Tungsten — character-at-a-time scanning with NaN-boxed LexChar
#
# Source is converted to LexChar values (0xFFFC tag, subtype 01):
#   bits 38-18: codepoint (21 bits)
#   bits 10-7:  digit_value (4 bits, 0xF = not a digit)
#   bits 6-0:   lex_flags (7 bits at LSB for single-instruction test)
#
# LexChar flag bits (at LSB):
#   bit 6: IS_ID_START    (a-z, _)
#   bit 5: IS_ID_CONTINUE (a-z, 0-9, _)
#   bit 4: IS_WHITESPACE  (space, tab)
#   bit 3: IS_HEX         (0-9, a-f, A-F)

# Extract codepoint from LexChar value
-> lc_cp(lc)
  (lc >> 18) & 2097151

# LexChar predicates — test packed flag bits
-> is_digit?(lc)
  ((lc >> 7) & 15) != 15

-> is_lower?(lc)
  lc_cp(lc) >= 97 && lc_cp(lc) <= 122

-> is_upper?(lc)
  lc_cp(lc) >= 65 && lc_cp(lc) <= 90

-> is_alpha?(lc)
  is_lower?(lc) || is_upper?(lc)

-> is_ident_start?(lc)
  (lc & 64) != 0

-> is_ident_char?(lc)
  (lc & 32) != 0

-> is_name_char?(lc)
  (lc & 32) != 0 || is_upper?(lc)

-> is_keyword?(word)
  word == "begin" || word == "break" || word == "case" || word == "else" || word == "elsif" || word == "ensure" || word == "exit" || word == "extern" || word == "false" || word == "fn" || word == "go" || word == "if" || word == "in" || word == "is" || word == "loop" || word == "module" || word == "nil" || word == "next" || word == "on" || word == "parallel" || word == "raise" || word == "recase" || word == "rescue" || word == "return" || word == "self" || word == "super" || word == "then" || word == "trait" || word == "true" || word == "unless" || word == "until" || word == "use" || word == "when" || word == "while" || word == "with" || word == "yield"

-> is_type_name?(word)
  word == "bool" || word == "int" || word == "integer" || word == "string" || word == "string_buffer" || word == "i1" || word == "i4" || word == "i8" || word == "i16" || word == "i32" || word == "i64" || word == "i128" || word == "u1" || word == "u4" || word == "u8" || word == "u16" || word == "u32" || word == "u64" || word == "u128" || word == "w64" || word == "f16" || word == "f32" || word == "f64" || word == "f80" || word == "f128" || word == "f256" || word == "d128" || word == "c32" || word == "c64" || word == "c128" || word == "bigint" || word == "bigdecimal" || word == "bf16" || word == "tf32" || word == "fp8" || word == "fp4" || word == "nf4" || word == "mxfp8" || word == "mxfp6" || word == "mxfp4" || word == "mxint8" || word == "posit8" || word == "posit16" || word == "posit32" || word == "posit64"

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
  type == :INT || type == :FLOAT || type == :DECIMAL || type == :STRING || type == :STRING_INTERP || type == :REGEX || type == :REGEX_CAPTURE || type == :SYMBOL || type == :NAME || type == :ID || type == :IVAR || type == :CVAR || type == :GLOBAL || type == :RPAREN || type == :RBRACKET || type == :RBRACE || type == :MAGIC_FILE || type == :MAGIC_LINE || type == :MAGIC_DIR || type == :UUID || type == :CURRENCY || type == :QUANTITY || type == :DURATION || type == :WVALUE || type == :BYTE_ARRAY || type == :BYTE_ARRAY_INTERP || type == :DATE || type == :DATETIME || type == :TIME || type == :MONTH || type == :IP4 || type == :CIDR4 || type == :IP6 || type == :CIDR6 || type == :RATIONAL || type == :CHAR || type == :CODEPOINT || type == :KEY || type == :WORD_ARRAY || type == :SYMBOL_ARRAY || type == :BASE32 || type == :BASE58 || type == :BASE64 || type == :PARG || type == :SUPERSCRIPT || type == :EXPONENT || type == :COLOR || type == :SELF_REF || type == :CONSTANT || type == :TYPE

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
