use assert
use ../lib/lexer

-> lex(source)
  Lexer.new(source).tokenize()

test "tokenizes integers"
tokens = lex("42")
assert_eq tokens[0][:type], :INT
assert_eq tokens[0][:value], "42"

test "tokenizes hex integers"
tokens = lex("0xFF")
assert_eq tokens[0][:type], :INT
assert_eq tokens[0][:value], "0xFF"

test "tokenizes raw WValue literals"
tokens = lex("u0xFFF9073656C6966B")
assert_eq tokens[0][:type], :WVALUE
assert_eq tokens[0][:value], "u0xFFF9073656C6966B"

test "tokenizes strings"
tokens = lex("\"hello\"")
assert_eq tokens[0][:type], :STRING
assert_eq tokens[0][:value], "hello"

test "tokenizes symbols"
tokens = lex(":foo")
assert_eq tokens[0][:type], :SYMBOL
assert_eq tokens[0][:value], "foo"

test "tokenizes identifiers"
tokens = lex("foo")
assert_eq tokens[0][:type], :ID
assert_eq tokens[0][:value], "foo"

test "tokenizes identifiers with ? and !"
tokens = lex("empty?")
assert_eq tokens[0][:type], :ID
assert_eq tokens[0][:value], "empty?"

test "tokenizes keywords"
tokens = lex("if")
assert_eq tokens[0][:type], :KEYWORD
assert_eq tokens[0][:value], "if"

test "tokenizes class names"
tokens = lex("Foo")
assert_eq tokens[0][:type], :NAME
assert_eq tokens[0][:value], "Foo"

test "tokenizes instance variables"
tokens = lex("@name")
assert_eq tokens[0][:type], :IVAR
assert_eq tokens[0][:value], "@name"

test "tokenizes arrow"
tokens = lex("->")
assert_eq tokens[0][:type], :ARROW

test "tokenizes comparison operators"
tokens = lex("==")
assert_eq tokens[0][:type], :EQ
tokens = lex("!=")
assert_eq tokens[0][:type], :NEQ
tokens = lex("<=")
assert_eq tokens[0][:type], :LTE
tokens = lex(">=")
assert_eq tokens[0][:type], :GTE

test "tokenizes logical operators"
tokens = lex("&&")
assert_eq tokens[0][:type], :AND
tokens = lex("||")
assert_eq tokens[0][:type], :OR

test "tokenizes compound assignment"
tokens = lex("+=")
assert_eq tokens[0][:type], :PLUS_EQ
tokens = lex("-=")
assert_eq tokens[0][:type], :MINUS_EQ

test "tokenizes puts and print operators"
tokens = lex("<<")
assert_eq tokens[0][:type], :PUTS_OP
tokens = lex("<-")
assert_eq tokens[0][:type], :PRINT_OP

test "tokenizes + at column 1 as CLASS_DEF"
tokens = lex("+Foo")
assert_eq tokens[0][:type], :CLASS_DEF

test "tokenizes single char operators"
tokens = lex("1 + 1 - 1 * 1 / 1 % 1")
assert_eq tokens[1][:type], :PLUS
assert_eq tokens[3][:type], :MINUS
assert_eq tokens[5][:type], :STAR
assert_eq tokens[7][:type], :SLASH
assert_eq tokens[9][:type], :PERCENT

test "tokenizes delimiters"
tokens = lex("( ) \[ ] { }")
assert_eq tokens[0][:type], :LPAREN
assert_eq tokens[1][:type], :RPAREN
assert_eq tokens[2][:type], :LBRACKET
assert_eq tokens[3][:type], :RBRACKET
assert_eq tokens[4][:type], :LBRACE
assert_eq tokens[5][:type], :RBRACE

test "skips comments"
tokens = lex("42 # comment\n")
assert_eq tokens[0][:type], :INT
assert_eq tokens[0][:value], "42"
assert_eq tokens[1][:type], :NEWLINE

test "emits INDENT and DEDENT"
tokens = lex("if true\n  42")
# if, true, NEWLINE, INDENT, 42, DEDENT, EOF
i = 0
while i < tokens.size()
  if tokens[i][:type] == :INDENT
    break
  i += 1
assert_eq tokens[i][:type], :INDENT

test "tokenizes string interpolation"
tokens = lex("\"hello \[name]\"")
assert_eq tokens[0][:type], :STRING_INTERP

test "handles newlines"
tokens = lex("a\nb")
assert_eq tokens[0][:type], :ID
assert_eq tokens[1][:type], :NEWLINE
assert_eq tokens[2][:type], :ID

# ── Literal ecosystem token tests ──

# Date/DateTime/Time/Month
test "tokenizes date literal"
tokens = lex("2026-04-10")
assert_eq tokens[0][:type], :DATE
assert_eq tokens[0][:value], "2026-04-10"

test "tokenizes datetime literal"
tokens = lex("2026-04-10T14:30:00Z")
assert_eq tokens[0][:type], :DATETIME
assert_eq tokens[0][:value], "2026-04-10T14:30:00Z"

test "tokenizes time literal"
tokens = lex("14:30:00")
assert_eq tokens[0][:type], :TIME
assert_eq tokens[0][:value], "14:30:00"

test "tokenizes month literal"
tokens = lex("2026-04")
assert_eq tokens[0][:type], :MONTH
assert_eq tokens[0][:value], "2026-04"

# Date disambiguation
test "date vs subtraction: 2026 - 4 is INT MINUS INT"
tokens = lex("2026 - 4")
assert_eq tokens[0][:type], :INT

test "4-digit number without dash is INT"
tokens = lex("2026")
assert_eq tokens[0][:type], :INT

# IPv4/CIDR4
test "tokenizes IPv4"
tokens = lex("192.168.1.1")
assert_eq tokens[0][:type], :IP4
assert_eq tokens[0][:value], "192.168.1.1"

test "tokenizes CIDR4"
tokens = lex("10.0.0.0/8")
assert_eq tokens[0][:type], :CIDR4
assert_eq tokens[0][:value], "10.0.0.0/8"

test "IPv4 backtrack: 192.168 is DECIMAL"
tokens = lex("192.168")
assert_eq tokens[0][:type], :DECIMAL

test "IPv4 invalid octet: 256.1.1.1 is not IP4"
tokens = lex("256.1.1.1")
assert_eq tokens[0][:type], :DECIMAL

# Rational
test "tokenizes rational"
tokens = lex("3/4")
assert_eq tokens[0][:type], :RATIONAL
assert_eq tokens[0][:value], "3/4"

test "rational vs division: 3 / 4 is INT SLASH INT"
tokens = lex("3 / 4")
assert_eq tokens[0][:type], :INT

# Char
test "tokenizes char literal"
tokens = lex("U+0041")
assert_eq tokens[0][:type], :CHAR
assert_eq tokens[0][:value], 65

# Color
test "tokenizes color literal #RRGGBB"
tokens = lex("#FF6B35")
assert_eq tokens[0][:type], :COLOR

test "tokenizes color literal #RGB"
tokens = lex("#F60")
assert_eq tokens[0][:type], :COLOR

test "color vs comment: # text is comment"
tokens = lex("# comment")
assert_eq tokens[0][:type], :EOF

# Key literal
test "tokenizes key literal"
tokens = lex("#[Enter]")
assert_eq tokens[0][:type], :KEY
assert_eq tokens[0][:value], "Enter"

# PARG
test "tokenizes positional argument"
tokens = lex("@1")
assert_eq tokens[0][:type], :PARG
assert_eq tokens[0][:value], "1"

test "PARG vs IVAR: @name is IVAR"
tokens = lex("@name")
assert_eq tokens[0][:type], :IVAR

# MAP operator
test "tokenizes MAP at line start"
tokens = lex("/to_s")
assert_eq tokens[0][:type], :MAP

test "MAP vs SLASH after value"
tokens = lex("x / to_s")
assert_eq tokens[1][:type], :SLASH

# Lambda arity
test "tokenizes lambda arity"
tokens = lex("->/2")
assert_eq tokens[0][:type], :LAMBDA_ARITY
assert_eq tokens[0][:value], "->/2"

test "arrow without arity"
tokens = lex("->")
assert_eq tokens[0][:type], :ARROW

# Superscript
test "tokenizes superscript digits"
tokens = lex("²")
assert_eq tokens[0][:type], :SUPERSCRIPT

# Greek/math symbols
test "tokenizes greek letters as identifiers"
tokens = lex("π")
assert_eq tokens[0][:type], :ID
assert_eq tokens[0][:value], "π"

# Operator symbols
test "tokenizes operator symbol :+"
tokens = lex(":+")
assert_eq tokens[0][:type], :SYMBOL
assert_eq tokens[0][:value], "+"

test "tokenizes operator symbol :=="
tokens = lex(":==")
assert_eq tokens[0][:type], :SYMBOL
assert_eq tokens[0][:value], "=="

test "tokenizes operator symbol :<=>"
tokens = lex(":<=>")
assert_eq tokens[0][:type], :SYMBOL
assert_eq tokens[0][:value], "<=>"

# Word/symbol arrays
test "tokenizes word array"
tokens = lex("%w[foo bar]")
assert_eq tokens[0][:type], :WORD_ARRAY

test "tokenizes symbol array"
tokens = lex("%i[one two]")
assert_eq tokens[0][:type], :SYMBOL_ARRAY

# Base encoding
test "tokenizes base58"
tokens = lex("0b58-3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy")
assert_eq tokens[0][:type], :BASE58

test "base58 vs binary: 0b0101 is INT"
tokens = lex("0b0101")
assert_eq tokens[0][:type], :INT

# Heredoc
test "tokenizes heredoc"
tokens = lex("<<~EOF\n  hello\nEOF")
assert_eq tokens[0][:type], :STRING
assert_eq tokens[0][:value], "hello"

# [] in strings is literal, not interpolation
test "empty brackets in string are literal"
tokens = lex("\"[]\"")
assert_eq tokens[0][:type], :STRING
assert_eq tokens[0][:value], "[]"

# Standalone time disambiguation
test "time requires HH:MM:SS (not just HH:MM)"
tokens = lex("14:30")
assert_eq tokens[0][:type], :INT

# Regression: existing tokens still work
test "existing UUID still works"
tokens = lex("a1b2c3d4-e5f6-4789-abcd-ef0123456789")
assert_eq tokens[0][:type], :UUID

test "existing duration still works"
tokens = lex("2h30m")
assert_eq tokens[0][:type], :DURATION

test "existing currency still works"
tokens = lex("$5.25")
assert_eq tokens[0][:type], :CURRENCY

test "float 3.14 still works"
tokens = lex("3.14")
assert_eq tokens[0][:type], :DECIMAL

test "is_value_type context: + after INT is PLUS"
tokens = lex("42 + 1")
assert_eq tokens[1][:type], :PLUS

test "<< at line start is PUTS_OP"
tokens = lex("<< 1")
assert_eq tokens[0][:type], :PUTS_OP

test "<< after value is LSHIFT"
tokens = lex("x << 1")
assert_eq tokens[1][:type], :LSHIFT

report()
