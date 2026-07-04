# Ruby Language Overrides — flag definitions for Ruby LexChar
#
# The generated table lives at languages/ruby/ruby.lex64 and is built by:
#   python3 scripts/gen_unicode_codepoints.py --lang ruby [--bits 16|32|64]
#
# Ruby LexChar flag bits:
#   bit 7(128): IS_NEWLINE       \n \r
#   bit 6 (64): IS_ID_START      a-z A-Z _ and Unicode letters
#   bit 5 (32): IS_ID_CONTINUE   IS_ID_START plus 0-9
#   bit 4 (16): IS_WHITESPACE    space tab
#   bit 3  (8): IS_HEX           0-9 a-f A-F
#   bit 2  (4): IS_OPERATOR      + - * / % ^ & | < > = ! ~ ? . : ; , ( ) [ ] { } # @ $
#   bit 1  (2): IS_QUOTE         " ' `
#   bit 0  (1): IS_DIGIT         0-9

F_IS_NEWLINE     = 128 # bit 7
F_IS_ID_START    = 64  # bit 6
F_IS_ID_CONTINUE = 32  # bit 5
F_IS_WHITESPACE  = 16  # bit 4
F_IS_HEX         = 8   # bit 3
F_IS_OPERATOR    = 4   # bit 2
F_IS_QUOTE       = 2   # bit 1
F_IS_DIGIT       = 1   # bit 0

