use ../../compiler/lib/ast
use ../../compiler/lib/lexer
use ../../compiler/lib/parser

-> parse_product(source)
  lexer = Lexer.new(source)
  count = lexer.tokenize()
  parser = Parser.new(count, lexer.packed_tokens, source, lexer.values, lexer.line_at, lexer.col_at, lexer.file)
  parser.set_chars(lexer.chars).parse().expressions[0]

-> check_product(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)

factorial = parse_product("10!")
check_product("factorial call", ast_kind(factorial), :call)
check_product("factorial method", factorial.name, "factorial")
check_product("factorial receiver", ast_kind(factorial.receiver), :int)
primorial = parse_product("n#")
check_product("primorial method", primorial.name, "primorial")
check_product("primorial receiver", primorial.receiver.name, "n")
check_product("bang method", parse_product("list.first!").name, "first!")
check_product("spaced hash", ast_kind(parse_product("10 # comment")), :int)
check_product("tight variable bang", parse_product("n!").name, "n!")

grouped_sources = ["(a + b)!", "(a + b)#", "((a + b))!", "(\na + b\n)!", "(\na + b\n)#"]
i = 0
while i < grouped_sources.size
  grouped = parse_product(grouped_sources[i])
  check_product("grouped product", ast_kind(grouped), :call)
  check_product("grouped operand", ast_kind(grouped.receiver), :binary_op)
  check_product("grouped operator", grouped.name, grouped_sources[i].ends_with?("#") ? "primorial" : "factorial")
  i += 1
check_product("grouped variable", parse_product("(n)!").receiver.name, "n")
check_product("grouped factorial", parse_product("(n!)!").receiver.name, "n!")
check_product("grouped method", parse_product("(list.first)!").receiver.name, "first")
check_product("grouped function", parse_product("(f())#").receiver.name, "f")
check_product("grouped prefix not", ast_kind(parse_product("!(a + b)")), :not)
check_product("not of grouped factorial", parse_product("!(a + b)!").operand.name, "factorial")
check_product("grouped spaced hash", ast_kind(parse_product("(a + b) # comment")), :binary_op)

sources = ["10 !", "n !", "(n) !", "(a + b) !", "(a + b)\t!", "(\na + b\n) !", "f()!", "f()#", "list.first#", "list\[0]!", "3!#", "3#!", "n!#", "n!!", "(a + b)!#", "(a + b)#!", "(a + b)!!", "Int!", "Int#"]
i = 0
while i < sources.size
  rejected = false
  begin
    parse_product(sources[i])
  rescue
    rejected = true
  check_product(sources[i], rejected, true)
  i += 1
<< "PASS postfix product parser"
