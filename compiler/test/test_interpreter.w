use assert
use ../lib/interpreter

-> eval(source)
  interp = Interpreter.new()
  interp.run(source)

test "evaluates integers"
assert_eq eval("42"), 42

test "evaluates raw WValue literals as their exact bits"
assert_eq eval("u0xFFF9073656C6966B").to_s(), "18444781678838060651"

test "evaluates strings"
assert_eq eval("\"hello\""), "hello"

test "evaluates booleans"
assert_eq eval("true"), true
assert_eq eval("false"), false

test "evaluates nil"
assert_nil eval("nil")

test "evaluates symbols"
assert_eq eval(":foo"), :foo

test "evaluates arrays"
assert_eq eval("\[1, 2, 3]"), [1, 2, 3]

test "evaluates hashes"
result = eval("{a: 1, b: 2}")
assert_eq result[:a], 1
assert_eq result[:b], 2

test "evaluates addition"
assert_eq eval("2 + 3"), 5

test "evaluates subtraction"
assert_eq eval("10 - 4"), 6

test "evaluates multiplication"
assert_eq eval("3 * 7"), 21

test "evaluates division"
assert_eq eval("10 / 3"), 3

test "evaluates modulo"
assert_eq eval("10 % 3"), 1

test "evaluates bitwise operators"
assert_eq eval("6 & 3"), 2
assert_eq eval("6 | 3"), 7
assert_eq eval("6 ^ 3"), 5
assert_eq eval("3 << 4"), 48
assert_eq eval("48 >> 4"), 3

test "applies integer type hints during assignment"
assert_eq eval("x = 18446744073709551615 ## i64\nx"), -1
assert_eq eval("x = -1 ## u64\nx").to_s(), "18446744073709551615"
assert_eq eval("x = 340282366920938463463374607431768211456 ## u128\nx"), 0

test "evaluates unary minus"
assert_eq eval("-5"), -5

test "respects precedence"
assert_eq eval("2 + 3 * 4"), 14
assert_eq eval("(2 + 3) * 4"), 20

test "string concatenation"
assert_eq eval("\"foo\" + \"bar\""), "foobar"

test "comparison operators"
assert_true eval("5 == 5")
assert_true eval("5 != 3")
assert_true eval("3 < 5")
assert_true eval("5 > 3")
assert_true eval("5 <= 5")
assert_true eval("5 >= 5")

test "logical operators"
assert_false eval("true && false")
assert_true eval("true || false")
assert_false eval("!true")
assert_true eval("!false")

test "variables"
assert_eq eval("x = 42\nx"), 42

test "compound assignment"
assert_eq eval("x = 5\nx += 3\nx"), 8

test "if/else"
assert_eq eval("if true\n  42\nelse\n  0"), 42
assert_eq eval("if false\n  42\nelse\n  0"), 0

test "while loop"
assert_eq eval("x = 0\nwhile x < 5\n  x += 1\nx"), 5

test "method definition and call"
assert_eq eval("-> add(a, b)\n  a + b\nadd(3, 4)"), 7

test "method with default params"
assert_eq eval("-> add(a, b = 10)\n  a + b\nadd(5)"), 15

test "return from method"
assert_eq eval("-> foo\n  return 10\n  20\nfoo"), 10

test "classes"
code = "+Dog\n  -> new(@name)\n  -> bark\n    \"woof\"\nd = Dog.new(\"Rex\")\nd.bark()"
assert_eq eval(code), "woof"

test "instance variables"
code = "+Dog\n  -> new(@name)\n  -> get_name\n    @name\nd = Dog.new(\"Rex\")\nd.get_name()"
assert_eq eval(code), "Rex"

test "inheritance"
code = "+Animal\n  -> speak\n    \"...\"\n+Dog < Animal\n  -> speak\n    \"woof!\"\nd = Dog.new()\nd.speak()"
assert_eq eval(code), "woof!"

test "inherited methods"
code = "+Base\n  -> greet\n    \"hello\"\n+Child < Base\nc = Child.new()\nc.greet()"
assert_eq eval(code), "hello"

test "blocks with each"
code = "result = \[]\n\[1, 2, 3].each ->(x) { result.push(x) }\nresult"
assert_eq eval(code), [1, 2, 3]

test "map with block"
assert_eq eval("\[1, 2, 3].map ->(x) { x * 2 }"), [2, 4, 6]

test "select with block"
assert_eq eval("\[1, 2, 3, 4].select ->(x) { x % 2 == 0 }"), [2, 4]

test "reduce with block"
assert_eq eval("\[1, 2, 3, 4].reduce ->(acc, x) { acc + x }"), 10

test "break in while"
assert_eq eval("x = 0\nwhile true\n  x += 1\n  break if x == 3\nx"), 3

test "case/when"
code = "x = 2\ncase\nwhen x == 1\n  \"a\"\nwhen x == 2\n  \"b\"\nelse\n  \"c\""
assert_eq eval(code), "b"

test "string interpolation"
assert_eq eval("name = \"world\"\n\"hello \[name]\""), "hello world"

test "array indexing"
assert_eq eval("\[10, 20, 30]\[1]"), 20

test "array index assignment"
assert_eq eval("a = \[1, 2, 3]\na\[0] = 10\na\[0]"), 10

test "begin/rescue"
code = "result = begin\n  raise \"boom\"\nrescue err\n  \"caught: \[err]\"\nresult"
assert_eq eval(code), "caught: boom"

test "suffix if"
assert_eq eval("42 if true"), 42
assert_nil eval("42 if false")

test "hash access"
assert_eq eval("h = {a: 1}\nh\[:a]"), 1

report()
