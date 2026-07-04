use assert
use ../lib/ast
use ../lib/lexer
use ../lib/parser

-> parse(source)
  lexer = Lexer.new(source)
  token_count = lexer.tokenize()
  Parser.new(token_count, lexer.packed_tokens, source, lexer.values, lexer.line_at, lexer.col_at, lexer.file).set_chars(lexer.chars).parse()

-> first_expr(source)
  ast = parse(source)
  ast[:expressions][0]

test "parses integers"
expr = first_expr("42")
assert_eq expr[:node], :int
assert_eq expr[:value], 42

test "parses hex integers"
expr = first_expr("0xFF")
assert_eq expr[:node], :int
assert_eq expr[:value], 255

test "parses raw WValue literals"
expr = first_expr("u0xFFF9073656C6966B")
assert_eq expr[:node], :wvalue
assert_eq expr[:raw], "u0xFFF9073656C6966B"

test "parses strings"
expr = first_expr("\"hello\"")
assert_eq expr[:node], :string
assert_eq expr[:value], "hello"

test "parses symbols"
expr = first_expr(":foo")
assert_eq expr[:node], :symbol
assert_eq expr[:value], "foo"

test "parses booleans"
expr = first_expr("true")
assert_eq expr[:node], :bool
assert_eq expr[:value], true

test "parses nil"
expr = first_expr("nil")
assert_eq expr[:node], :nil_lit

test "parses variables"
expr = first_expr("x")
assert_eq expr[:node], :var
assert_eq expr[:name], "x"

test "parses assignment"
expr = first_expr("x = 42")
assert_eq expr[:node], :assign
assert_eq expr[:target][:name], "x"
assert_eq expr[:value][:value], 42

test "parses binary operations"
expr = first_expr("2 + 3")
assert_eq expr[:node], :binary_op
assert_eq expr[:op], :PLUS
assert_eq expr[:left][:value], 2
assert_eq expr[:right][:value], 3

test "parses operator precedence"
expr = first_expr("2 + 3 * 4")
assert_eq expr[:node], :binary_op
assert_eq expr[:op], :PLUS
assert_eq expr[:right][:op], :STAR

test "parses exponentiation"
expr = first_expr("2 ** 3 ** 2")
assert_eq expr[:node], :binary_op
assert_eq expr[:op], :POW
assert_eq expr[:right][:op], :POW

test "parses variable multiplication as infix star"
expr = first_expr("i * 8")
assert_eq expr[:node], :binary_op
assert_eq expr[:op], :STAR
assert_eq expr[:left][:name], "i"
assert_eq expr[:right][:value], 8

test "parses comparison"
expr = first_expr("x == 5")
assert_eq expr[:node], :binary_op
assert_eq expr[:op], :EQ

test "parses logical operators"
expr = first_expr("a && b")
assert_eq expr[:node], :and
expr = first_expr("a || b")
assert_eq expr[:node], :or

test "parses not"
expr = first_expr("!x")
assert_eq expr[:node], :not

test "parses unary minus"
expr = first_expr("-5")
assert_eq expr[:node], :unary_op
assert_eq expr[:op], :MINUS

test "parses method calls with parens"
expr = first_expr("foo(1, 2)")
assert_eq expr[:node], :call
assert_eq expr[:name], "foo"
assert_eq expr[:args].size(), 2

test "parses fat-arrow hash args"
expr = first_expr("exists?(field => value)")
assert_eq expr[:node], :call
assert_eq expr[:args][0][:node], :hash_literal
assert_eq expr[:args][0][:entries][0][0][:name], "field"

test "parses dot calls"
expr = first_expr("x.size()")
assert_eq expr[:node], :call
assert_eq expr[:name], "length"

test "parses array literal"
expr = first_expr("\[1, 2, 3]")
assert_eq expr[:node], :array
assert_eq expr[:elements].size(), 3

test "parses hash literal"
expr = first_expr("{a: 1, b: 2}")
assert_eq expr[:node], :hash_literal
assert_eq expr[:entries].size(), 2

test "parses if/else"
expr = first_expr("if true\n  42\nelse\n  0")
assert_eq expr[:node], :if
assert_eq expr[:then_body][0][:value], 42

test "parses while"
expr = first_expr("while true\n  42")
assert_eq expr[:node], :while

test "parses method def"
expr = first_expr("-> foo(a, b)\n  a + b")
assert_eq expr[:node], :method_def
assert_eq expr[:name], "foo"
assert_eq expr[:params].size(), 2

test "parses equals inline method body"
expr = first_expr("-> foo(a) = a")
assert_eq expr[:node], :method_def
assert_eq expr[:body][0][:node], :var
assert_eq expr[:body][0][:name], "a"

test "parses type words as method names"
expr = first_expr("-> string(name) = name")
assert_eq expr[:node], :method_def
assert_eq expr[:name], "string"

test "parses leading pipeline continuation lines"
expr = first_expr("-> f\n  value\n  |> .to_s")
assert_eq expr[:node], :method_def
assert_eq expr[:body].size(), 1
assert_eq expr[:body][0][:node], :call
assert_eq expr[:body][0][:name], "to_s"

test "parses indented dot continuation chains"
expr = first_expr("items\n  .drop(1)\n  .take(2)")
assert_eq expr[:node], :call
assert_eq expr[:name], "take"
assert_eq expr[:receiver][:name], "drop"

test "parses indented self continuation chains"
expr = first_expr("items\n  self.drop(1)")
assert_eq expr[:node], :call
assert_eq expr[:receiver][:name], "items"
assert_eq expr[:name], "drop"

test "does not treat array newline arrow as implicit each"
ast = parse("items = []\n-> empty?\n  items.empty?()")
assert_eq ast[:expressions].size(), 2
assert_eq ast[:expressions][0][:node], :assign
assert_eq ast[:expressions][1][:node], :method_def
assert_eq ast[:expressions][1][:name], "empty?"

test "parses same-line array arrow as implicit each"
expr = first_expr("\[1, 2] -> (item)\n  item")
assert_eq expr[:node], :call
assert_eq expr[:name], "each"
assert_eq expr[:block][:params][0], "item"

test "infers implicit range param names"
expr = first_expr("0...3 ->\n  i")
assert_eq expr[:node], :call
assert_eq expr[:block][:params][0], "i"

expr = first_expr("j...3 ->\n  j")
assert_eq expr[:node], :call
assert_eq expr[:block][:params][0], "j"

test "parses dotted zero-arg call with arrow block"
expr = first_expr("items.each -> (item)\n  item")
assert_eq expr[:node], :call
assert_eq expr[:name], "each"
assert_eq expr[:receiver][:node], :var
assert_eq expr[:receiver][:name], "items"
assert_eq expr[:args].size(), 0
assert_eq expr[:block][:params][0], "item"

test "parses suffix condition in inline lambda body"
expr = first_expr("each -> return false unless item")
assert_eq expr[:node], :call
assert_eq expr[:name], "each"
assert_eq expr[:block][:body][0][:node], :if
assert_eq expr[:block][:body][0][:condition][:node], :not
assert_eq expr[:block][:body][0][:then_body][0][:node], :return

test "parses passthrough fallthrough after each lambda"
expr = first_expr("each -> out.push(item) : out")
assert_eq expr[:node], :passthrough
assert_eq expr[:expression][:node], :call
assert_eq expr[:expression][:name], "each"
assert_eq expr[:value][:node], :var
assert_eq expr[:value][:name], "out"

test "parses named accumulator method header"
expr = first_expr("-> reduce(init, &) acc=init\n  each -> acc = &(acc, item)")
assert_eq expr[:node], :method_def
assert_eq expr[:body][0][:node], :assign
assert_eq expr[:body][0][:target][:name], "acc"
assert_eq expr[:body][0][:value][:name], "init"
assert_eq expr[:body].last()[:node], :var
assert_eq expr[:body].last()[:name], "acc"

test "parses block splat params and call splats"
expr = first_expr("define_singleton_method(name) -> (*args)\n  query_fn.call(*args)")
assert_eq expr[:node], :call
assert_eq expr[:block][:params][0], "args"
assert_eq expr[:block][:body][0][:args][0][:name], "args"

test "parses class def"
expr = first_expr("+Dog\n  -> bark\n    42")
assert_eq expr[:node], :class_def
assert_eq expr[:name], "Dog"

test "parses trait def"
expr = first_expr("trait Talker\n  -> talk\n    \"hi\"")
assert_eq expr[:node], :trait_def
assert_eq expr[:name], "Talker"
assert_eq expr[:body][0][:name], "talk"

test "parses trait include"
expr = first_expr("is Talker")
assert_eq expr[:node], :trait_include
assert_eq expr[:name], "Talker"

test "parses data declaration after trait include"
expr = first_expr("+ Array\n  is Enumerable\n\n  - data\n      u8 flags\n      u8[3] _pad\n    * w64[] items")
assert_eq expr[:node], :class_def
assert_eq expr[:body][0][:node], :trait_include
assert_eq expr[:body][1][:node], :view_decl
assert_eq expr[:body][1][:name], "data"
assert_eq expr[:body][1][:kind], "struct"
assert_eq expr[:body][1][:count][:fields][0][:name], "flags"
assert_eq expr[:body][1][:count][:fields][1][:type], "u8[3]"
assert_eq expr[:body][1][:count][:fields][2][:type], "*w64[]"

test "parses data declaration backing struct name"
expr = first_expr("+ Array\n  - data (WArray)\n      u8 flags\n    * w64[] slots")
assert_eq expr[:node], :class_def
assert_eq expr[:body][0][:node], :view_decl
assert_eq expr[:body][0][:count][:struct_name], "WArray"
assert_eq expr[:body][0][:count][:fields][0][:name], "flags"
assert_eq expr[:body][0][:count][:fields][1][:type], "*w64[]"

test "parses return"
expr = first_expr("return 42")
assert_eq expr[:node], :return
assert_eq expr[:value][:value], 42

test "parses break and next"
expr = first_expr("break")
assert_eq expr[:node], :break
expr = first_expr("next")
assert_eq expr[:node], :next

test "parses use"
expr = first_expr("use \"foo\"")
assert_eq expr[:node], :use
assert_eq expr[:path], "foo"

test "parses begin/rescue"
expr = first_expr("begin\n  42\nrescue err\n  0")
assert_eq expr[:node], :begin
assert_eq expr[:rescue_var], "err"

test "parses yield"
expr = first_expr("yield 1, 2")
assert_eq expr[:node], :yield
assert_eq expr[:args].size(), 2

test "parses indexed access"
expr = first_expr("a\[0]")
assert_eq expr[:node], :call
assert_eq expr[:name], "\[]"

test "parses puts operator"
expr = first_expr("<< 42")
assert_eq expr[:node], :puts

test "parses case/when"
expr = first_expr("case\nwhen x == 1\n  42")
assert_eq expr[:node], :case
assert_eq expr[:whens].size(), 1

test "parses semicolon sequences in arrow case bodies"
expr = first_expr("case x\n  1 => touch(); \"done\"")
assert_eq expr[:node], :case_value
assert_eq expr[:arms][0][:body].size(), 2

test "parses comma-separated arrow case patterns"
expr = first_expr("case kind\n  :a, :b => \"hit\"")
assert_eq expr[:node], :case_value
assert_eq expr[:arms].size(), 2

report()
