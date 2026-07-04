# C Lexer Unit Tests — verify all codepaths in c_tokenize_fast
#
# Tests all codepaths using combined source strings. The compiled runtime
# has a pre-existing allocation limit (~200 chars total across distinct
# lchs() calls), so tests are grouped into 5 combined source strings.

use ./lexer

# ── Token type IDs ────────────────────────────────────────────────────
ID_IDENT   = 1
ID_INT     = 3
ID_FLOAT   = 4
ID_STRING  = 5
ID_CHAR    = 6
ID_OP      = 7
ID_PREPROC = 8
ID_COMMENT = 9
ID_WS      = 10
ID_NL      = 11
ID_HEADER  = 12
ID_ERROR   = 13
ID_PPNUM   = 14
FLAG_BOL   = 1
FLAG_SPACE = 2
FLAG_ERROR = 4

# ── Test infrastructure ───────────────────────────────────────────────
pass_count = 0
fail_count = 0

-> ok(cond, msg)
  if !cond
    << "  FAIL: [msg]"
    exit(1)

## i64: tval, r
## i64[]: tokens
fn ttype(tokens, i)
  tval = tokens[i]
  r = (tval >> 38) & 15
  r

## i64: tval, r
## i64[]: tokens
fn tlen(tokens, i)
  tval = tokens[i]
  r = (tval >> 24) & 0x3FFF
  r

## i64: tval, r
## i64[]: tokens
fn tflags(tokens, i)
  tval = tokens[i]
  r = (tval >> 42) & 0x3F
  r

fn tok(source)
  lc = source.lchs("c")
  n = lc.size()
  tokens = i64[n]
  tc = c_tokenize_fast(lc, n, tokens)
  [tokens, tc]

# ══════════════════════════════════════════════════════════════════════

<< "C Lexer Unit Tests"
<< "══════════════════════════════════════"

# ── 1. Basics: ident + ws + nl + int + ops (30 chars) ────────────────
# Source: "int _X=42;\n  \t b"
# Tokens(10): ID(3) WS ID(2) OP(1) INT(2) OP(1) NL WS(4) ID(1)
#              wait, _X is one ident with underscore + uppercase
# int _X=42;\n  \t b  (that's 16 chars after escape)
# Actually: 'int' ' ' '_X' '=' '42' ';' '\n' '  \t ' 'b'
# int(3) WS(1) _X(2) OP(1) INT(2) OP(1) NL(1) WS(4) ID(1) = hmm
# Wait: 'int' starts at 0, WS at 3, '_X' at 4, '=' at 6, '42' at 7, ';' at 9, NL at 10, '  \t ' at 11-14, 'b' at 15
# Tokens: IDENT(3) WS(1) IDENT(2) OP(1) INT(2) OP(1) NL(1) WS(4) IDENT(1)
# That's 9 tokens
<< "  1. Basics"
result = tok("int _X=42;\n  \t b")
tokens = result[0]
tc = result[1]
ok(tc == 9, "basics: 9 tokens")
ok(ttype(tokens, 0) == ID_IDENT, "'int' → IDENT")
ok(tlen(tokens, 0) == 3, "'int' len=3")
ok(ttype(tokens, 1) == ID_WS, "' ' → WS")
ok(ttype(tokens, 2) == ID_IDENT, "'_X' → IDENT (underscore+upper)")
ok(tlen(tokens, 2) == 2, "'_X' len=2")
ok(ttype(tokens, 3) == ID_OP, "'=' → OP")
ok(ttype(tokens, 4) == ID_INT, "'42' → INT")
ok(tlen(tokens, 4) == 2, "'42' len=2")
ok(ttype(tokens, 5) == ID_OP, "';' → OP")
ok(ttype(tokens, 6) == ID_NL, "NL")
ok(ttype(tokens, 7) == ID_WS, "spaces+tab → WS")
ok(tlen(tokens, 7) == 4, "ws run len=4")
ok(ttype(tokens, 8) == ID_IDENT, "'b' → IDENT")

# ── 2. Operators: single + compound + triple + ellipsis (52 chars) ───
# Source: "(){}; a->b ==c ++d <<=e f(...)"
# ()  → OP(1) OP(1)
# {}  → OP(1) OP(1)
# ;   → OP(1)
# ' ' → WS(1)
# a   → ID(1)
# ->  → OP(2)
# b   → ID(1)
# ' ' → WS(1)
# ==  → OP(2)
# c   → ID(1)
# ' ' → WS(1)
# ++  → OP(2)
# d   → ID(1)
# ' ' → WS(1)
# <<= → OP(3)
# e   → ID(1)
# ' ' → WS(1)
# f   → ID(1)
# (   → OP(1)
# ... → OP(3)
# )   → OP(1)
# = 21 tokens
<< "  2. Operators"
result = tok("(){}; a->b ==c ++d <<=e f(...)")
tokens = result[0]
tc = result[1]
ok(tc == 23, "ops: 23 tokens")
ok(ttype(tokens, 0) == ID_OP, "'(' → OP")
ok(tlen(tokens, 0) == 1, "'(' len=1")
ok(ttype(tokens, 2) == ID_OP, "'{' → OP")
ok(ttype(tokens, 4) == ID_OP, "';' → OP")
ok(tlen(tokens, 7) == 2, "'->' len=2")
ok(tlen(tokens, 10) == 2, "'==' len=2")
ok(tlen(tokens, 13) == 2, "'++' len=2")
ok(tlen(tokens, 16) == 3, "'<<=' len=3")
ok(tlen(tokens, 21) == 3, "'...' len=3")

# ── 3. Preproc + comments (31 chars) ────────────────────────────────
# Source: "#include <x>\n// hi\na /* b */ c"
# #        → OP(1)
# include  → IDENT(7)
# ' '      → WS(1)
# <x>      → HEADER(3)
# \n       → NL(1)
# // hi    → COMMENT(5)
# \n       → NL(1)
# a        → ID(1)
# ' '      → WS(1)
# /* b */  → COMMENT(7)
# ' '      → WS(1)
# c        → ID(1)
# = 12 tokens
<< "  3. Preproc + comments"
result = tok("#include <x>\n// hi\na /* b */ c")
tokens = result[0]
tc = result[1]
ok(tc == 12, "preproc+comment: 12 tokens")
ok(ttype(tokens, 0) == ID_OP, "'#' → OP")
ok(tlen(tokens, 0) == 1, "'#' len=1")
ok((tflags(tokens, 0) & FLAG_BOL) != 0, "'#' has BOL flag")
ok(ttype(tokens, 1) == ID_IDENT, "'include' → IDENT")
ok(tlen(tokens, 1) == 7, "'include' len=7")
ok(ttype(tokens, 3) == ID_HEADER, "'<x>' → HEADER")
ok(tlen(tokens, 3) == 3, "header len=3")
ok((tflags(tokens, 3) & FLAG_SPACE) != 0, "header has leading-space flag")
ok(ttype(tokens, 4) == ID_NL, "NL after directive")
ok(ttype(tokens, 5) == ID_COMMENT, "'// hi' → COMMENT")
ok(tlen(tokens, 5) == 5, "line comment: len=5")
ok(ttype(tokens, 6) == ID_NL, "NL after line comment")
ok(ttype(tokens, 9) == ID_COMMENT, "'/* b */' → COMMENT")
ok(tlen(tokens, 9) == 7, "block comment: len=7")
ok(ttype(tokens, 11) == ID_IDENT, "'c' after block comment")

# ── 4. Strings + chars (22 chars) ───────────────────────────────────
# Source: "hi" "a\nb" 'x' '\n'
# (Tungsten: "\"hi\" \"a\\nb\" 'x' '\\n'")
# "hi"      → STRING(4)
# ' '       → WS(1)
# "a\nb"    → STRING(6) — 6 chars: " a \ n b "
# ' '       → WS(1)
# 'x'       → CHAR(3)
# ' '       → WS(1)
# '\n'      → CHAR(4) — 4 chars: ' \ n '
# = 7 tokens
<< "  4. Strings + chars"
result = tok("\"hi\" \"a\\nb\" 'x' '\\n'")
tokens = result[0]
ok(result[1] == 7, "str+char: 7 tokens")
ok(ttype(tokens, 0) == ID_STRING, "'\"hi\"' → STRING")
ok(tlen(tokens, 0) == 4, "string: len=4")
ok(ttype(tokens, 2) == ID_STRING, "string with escape → STRING")
ok(tlen(tokens, 2) == 6, "str-esc: len=6")
ok(ttype(tokens, 4) == ID_CHAR, "'x' → CHAR")
ok(tlen(tokens, 4) == 3, "char: len=3")
ok(ttype(tokens, 6) == ID_CHAR, "char escape → CHAR")
ok(tlen(tokens, 6) == 4, "char-esc: len=4")

# ── 5. Numbers + edge cases (46 chars) ──────────────────────────────
# Source: "42 0xF 0b10 3.14 1e2 3e-1 42u 1.0f 077 @"
# 42    → INT(2)
# ' '   → WS(1)
# 0xF   → INT(3)
# ' '   → WS(1)
# 0b10  → INT(4)
# ' '   → WS(1)
# 3.14  → FLOAT(4)
# ' '   → WS(1)
# 1e2   → FLOAT(3)
# ' '   → WS(1)
# 3e-1  → FLOAT(4)
# ' '   → WS(1)
# 42u   → INT(3)
# ' '   → WS(1)
# 1.0f  → FLOAT(4)
# ' '   → WS(1)
# 077   → INT(3)
# ' '   → WS(1)
# @     → OP(1) (unknown char)
# = 19 tokens
<< "  5. Numbers + edge cases"
result = tok("42 0xF 0b10 3.14 1e2 3e-1 42u 1.0f 077 @")
tokens = result[0]
tc = result[1]
ok(tc == 19, "numbers: 19 tokens")
ok(ttype(tokens, 0) == ID_INT, "'42' → INT")
ok(tlen(tokens, 0) == 2, "'42' len=2")
ok(ttype(tokens, 2) == ID_INT, "'0xF' → INT (hex)")
ok(tlen(tokens, 2) == 3, "'0xF' len=3")
ok(ttype(tokens, 4) == ID_INT, "'0b10' → INT (binary)")
ok(tlen(tokens, 4) == 4, "'0b10' len=4")
ok(ttype(tokens, 6) == ID_FLOAT, "'3.14' → FLOAT")
ok(tlen(tokens, 6) == 4, "'3.14' len=4")
ok(ttype(tokens, 8) == ID_FLOAT, "'1e2' → FLOAT (exponent)")
ok(tlen(tokens, 8) == 3, "'1e2' len=3")
ok(ttype(tokens, 10) == ID_FLOAT, "'3e-1' → FLOAT (exp+sign)")
ok(tlen(tokens, 10) == 4, "'3e-1' len=4")
ok(ttype(tokens, 12) == ID_INT, "'42u' → INT (suffix)")
ok(tlen(tokens, 12) == 3, "'42u' len=3")
ok(ttype(tokens, 14) == ID_FLOAT, "'1.0f' → FLOAT (suffix)")
ok(tlen(tokens, 14) == 4, "'1.0f' len=4")
ok(ttype(tokens, 16) == ID_INT, "'077' → INT (octal)")
ok(tlen(tokens, 16) == 3, "'077' len=3")
ok(ttype(tokens, 18) == ID_ERROR, "'@' → ERROR (unknown)")
ok(tlen(tokens, 18) == 1, "'@' len=1")
ok((tflags(tokens, 18) & FLAG_ERROR) != 0, "'@' has error flag")

# ── 6. New C edge cases ─────────────────────────────────────────────
<< "  6. C edge cases"
result = tok(".5 1. 0x1.fp3 1e+ u8\"z\" \\u0041 <% %> a#b")
tokens = result[0]
tc = result[1]
ok(tc == 19, "edges: 19 tokens")
ok(ttype(tokens, 0) == ID_FLOAT, "'.5' → FLOAT")
ok(tlen(tokens, 0) == 2, "'.5' len=2")
ok(ttype(tokens, 2) == ID_FLOAT, "'1.' → FLOAT")
ok(tlen(tokens, 2) == 2, "'1.' len=2")
ok(ttype(tokens, 4) == ID_FLOAT, "'0x1.fp3' → FLOAT")
ok(tlen(tokens, 4) == 7, "'0x1.fp3' len=7")
ok(ttype(tokens, 6) == ID_PPNUM, "'1e+' → PPNUM")
ok(tlen(tokens, 6) == 3, "'1e+' len=3")
ok(ttype(tokens, 8) == ID_STRING, "'u8\"z\"' → STRING")
ok(tlen(tokens, 8) == 5, "'u8\"z\"' len=5")
ok(ttype(tokens, 10) == ID_IDENT, "'\\u0041' → IDENT")
ok(tlen(tokens, 10) == 6, "'\\u0041' len=6")
ok(ttype(tokens, 12) == ID_OP, "'<%' digraph → OP")
ok(tlen(tokens, 12) == 2, "'<%' len=2")
ok(ttype(tokens, 14) == ID_OP, "'%>' digraph → OP")
ok(tlen(tokens, 14) == 2, "'%>' len=2")
ok(ttype(tokens, 17) == ID_OP, "mid-line '#' → OP")
ok(tlen(tokens, 17) == 1, "mid-line '#' len=1")

# ══════════════════════════════════════════════════════════════════════
<< ""
<< "══════════════════════════════════════"
<< "ALL TESTS PASSED"
