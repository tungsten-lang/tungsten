use ../../compiler/lib/ast
use ../../compiler/lib/lexer
use ../../compiler/lib/parser

-> parse_math(source)
  lexer = Lexer.new(source)
  count = lexer.tokenize()
  parser = Parser.new(count, lexer.packed_tokens, source, lexer.values, lexer.line_at, lexer.col_at, lexer.file)
  parser.set_chars(lexer.chars).parse().expressions[0]

-> check_math(name, got, want)
  if got != want
    raise "FAIL [name]: got=[got] want=[want]"

composition = parse_math("f ∘ g")
check_math("tight composition", ast_kind(parse_math("f∘g")), :block)
check_math("composition closure", ast_kind(composition), :block)
check_math("outer callable", composition.body[0].name, "f")
check_math("inner callable", composition.body[0].args[0].name, "g")
check_math("method reference", parse_math("f ∘ obj.method").body[0].args[0].receiver.name, "obj")
check_math("closure operand", ast_kind(parse_math("(->(x) x + 1) ∘ g").body[0].receiver), :block)

chain = parse_math("a() <= b() < c() < d()")
check_math("chain", ast_kind(chain), :and)
check_math("nested continuation", ast_kind(chain.right), :and)
check_math("save once", ast_kind(chain.left.right), :assign)
check_math("middle expression", chain.left.right.value.name, "b")
check_math("reuse middle", chain.right.left.left.name, chain.left.right.target.name)
check_math("parentheses break chain", ast_kind(parse_math("(a < b) < c")), :binary_op)

tower = parse_math("2 ↑↑ 3 ↑↑ 2")
check_math("tight tetration", parse_math("2↑↑3").name, "tetrate")
check_math("tetration", tower.name, "tetrate")
check_math("right associativity", tower.args[0].name, "tetrate")
check_math("power precedence", parse_math("1 + 2 ↑↑ 3").right.name, "tetrate")

member = parse_math("item() ∈ collection()")
check_math("membership ordering", ast_kind(member), :begin)
check_math("element first", member.body[0].value.name, "item")
check_math("membership send", member.body[1].name, "include?")
check_math("nonmembership", ast_kind(parse_math("x ∉ a").body[1]), :not)
check_math("union", parse_math("a ∪ b").name, "union")
check_math("intersection precedence", parse_math("a ∪ b ∩ c").args[0].name, "intersect")
check_math("subset", parse_math("a ⊆ b").name, "subset?")

<< "PASS mathematical operator parser"
