# gen_js_lextable.w — Generate ECMAScript 2024 LexChar flag tables for Tungsten's
# String#lchs("js", bits: 16 | 32 | 64) runtime loader.
#
# Output files (loaded automatically by runtime_unicode.c w_load_lang_flags):
#   languages/js/js.lex16   (256 bytes: ASCII flags)
#   languages/js/js.lex32   (0x110000 bytes: full Unicode flags)
#   languages/js/js.lex64   (0x110000 bytes: full Unicode flags)
#
# Bit layout (identical to C's LexChar flags for NEON w_lex16_* compatibility,
# with JavaScript-specific extensions for '$', '`', '@', U+2028/2029, Unicode IDs):
#   bit 7 (0x80): IS_NEWLINE      \n \r U+2028 U+2029
#   bit 6 (0x40): IS_ID_START     a-z A-Z _ $ + Unicode ID_Start
#   bit 5 (0x20): IS_ID_CONTINUE  a-z A-Z 0-9 _ $ + Unicode ID_Continue + ZWNJ/ZWJ
#   bit 4 (0x10): IS_WHITESPACE   space \t \v \f U+00A0 U+FEFF Zs
#   bit 3 (0x08): IS_HEX          0-9 a-f A-F
#   bit 2 (0x04): IS_OPERATOR     + - * / % ^ & | < > = ! ~ ? . : ; , ( ) [ ] { } # @
#   bit 1 (0x02): IS_QUOTE        " ' `
#   bit 0 (0x01): IS_DIGIT        0-9

F_DIGIT       = 0x01
F_QUOTE       = 0x02
F_OPERATOR    = 0x04
F_HEX         = 0x08
F_WHITESPACE  = 0x10
F_ID_CONTINUE = 0x20
F_ID_START    = 0x40
F_NEWLINE     = 0x80

-> build_js_ascii_flags
  tbl = ByteArray.new(256)
  i = 0
  while i < 256
    tbl[i] = 0
    i += 1

  # Newlines: LF (10), CR (13)
  tbl[10] = F_NEWLINE
  tbl[13] = F_NEWLINE

  # Whitespace: TAB (9), VT (11), FF (12), SPACE (32)
  tbl[9]  = F_WHITESPACE
  tbl[11] = F_WHITESPACE
  tbl[12] = F_WHITESPACE
  tbl[32] = F_WHITESPACE

  # Digits: 0-9 (48..57) -> DIGIT | HEX | ID_CONTINUE
  c = 48
  while c <= 57
    tbl[c] = F_DIGIT | F_HEX | F_ID_CONTINUE
    c += 1

  # Uppercase A-Z (65..90)
  c = 65
  while c <= 90
    fl = F_ID_START | F_ID_CONTINUE
    fl = fl | F_HEX if c <= 70
    tbl[c] = fl
    c += 1

  # Lowercase a-z (97..122)
  c = 97
  while c <= 122
    fl = F_ID_START | F_ID_CONTINUE
    fl = fl | F_HEX if c <= 102
    tbl[c] = fl
    c += 1

  # '_' (95) and '$' (36) -> JS identifier start + continue
  tbl[95] = F_ID_START | F_ID_CONTINUE
  tbl[36] = F_ID_START | F_ID_CONTINUE

  # Quotes: '"' (34), "'" (39), '`' (96)
  tbl[34] = F_QUOTE
  tbl[39] = F_QUOTE
  tbl[96] = F_QUOTE

  # Operators & punctuators: + - * / % ^ & | < > = ! ~ ? . : ; , ( ) [ ] { } # @
  ops = [43, 45, 42, 47, 37, 94, 38, 124, 60, 62, 61, 33, 126, 63, 46, 58, 59, 44, 40, 41, 91, 93, 123, 125, 35, 64]
  i = 0
  while i < ops.size
    tbl[ops[i]] = F_OPERATOR
    i += 1

  tbl

-> build_js_unicode_flags(ascii)
  n = 0x110000
  tbl = ByteArray.new(n)
  # Copy ASCII 0..127
  i = 0
  while i < 128
    tbl[i] = ascii[i]
    i += 1
  # Non-ASCII: default to ID_START | ID_CONTINUE (superset matching jsn/lexer.w),
  # then override Unicode whitespace & line terminators precisely.
  # (Control chars 0x80..0x9F stay 0.)
  i = 0xA0
  while i < n
    tbl[i] = F_ID_START | F_ID_CONTINUE
    i += 1

  # Unicode whitespace (ECMA-262 WhiteSpace)
  ws = [0x00A0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200A, 0x202F, 0x205F, 0x3000, 0xFEFF]
  i = 0
  while i < ws.size
    tbl[ws[i]] = F_WHITESPACE
    i += 1

  # Unicode line terminators (ECMA-262 LineTerminator): LS (U+2028), PS (U+2029)
  tbl[0x2028] = F_NEWLINE
  tbl[0x2029] = F_NEWLINE

  # ZWNJ / ZWJ are ID_CONTINUE only, not ID_START
  tbl[0x200C] = F_ID_CONTINUE
  tbl[0x200D] = F_ID_CONTINUE

  tbl

-> write_bytes_file(path, ba)
  s = ccall("w_string_from_byte_array", ba)
  File.write(path, s)

File.mkdir_p("languages/js") if !Dir.exist?("languages/js")
ascii = build_js_ascii_flags()
uni = build_js_unicode_flags(ascii)
write_bytes_file("languages/js/js.lex16", ascii)
write_bytes_file("languages/js/js.lex32", uni)
write_bytes_file("languages/js/js.lex64", uni)
<< "Generated languages/js/js.lex16 (256B), js.lex32 (1.1MB), js.lex64 (1.1MB)"
