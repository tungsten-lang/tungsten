# A line ending in a binary operator continues on the next line: the lexers
# (compiler/lib/lexer/fast64.w, languages/tungsten/lexers/regex.w, lex32.w,
# wtoken32.w, and the Ruby Lexer/CodepointLexer) treat its newline as
# whitespace and the next line's indentation as not block structure.
# Continuing operators: + - * / % ** == != < > <= >= && || & ^.
# An unspaced `>` closes a type-argument list (`+ Poly<K>`) and does not
# continue: before that rule, every generic class header ending in `>`
# swallowed its body (core/algebra/polynomial.w's `+ Poly<K>` stopped
# parsing, and with it every algebra class).

-> check(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)

-> sum3(a, b, c)
  total = a +
    b +
    c
  total

a = 1 +
  2
check("plus", a, 3)

b = 10 -
      3 *
      2
check("minus and times, deeper indent", b, 4)

c = 2 **

  3
check("power across a blank line", c, 8)

d = 5 +   # a comment after the operator
  6
check("comment after the operator", d, 11)

ok = a == 3 &&
  b == 4
check("logical and", ok, true)

s = "ab" +
  "cd"
check("string concatenation", s, "abcd")

big = 0
if a >
   2
  big = 1
check("condition continued before its body", big, 1)

check("inside a method body", sum3(1, 2, 3), 6)

e = 7 -
  2
f = e - 1
check("the statement after a continuation", f, 4)

+ Crate<T>
  with T in (i64 f64)

  -> new(@item)

  ro :item

check("generic class header ending in > keeps its body", Crate<i64>.new(4).item, 4)

+ Pair<K, V>
  -> new(@key, @value)
  -> describe
    "[@key]=[@value]"

check("multi-parameter generic header", Pair<i64, i64>.new(1, 2).describe, "1=2")

<< "PASS line continuation"
