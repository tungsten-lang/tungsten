use ../lib/interpreter

-> as_i64(value) (f64) i64
  value ## i64

-> as_u64(value) (f64) u64
  value ## u64

-> as_i128(value) (f32) i128
  value ## i128

-> as_u128(value) (f32) u128
  value ## u128

-> parse_ascription_source(source)
  lexer = Lexer.new(source)
  token_count = lexer.tokenize()
  Parser.new(token_count, lexer.packed_tokens, source, lexer.values, lexer.line_at, lexer.col_at, lexer.file).set_chars(lexer.chars).parse()

program = parse_ascription_source("identity(value ## f64)")
ascription = program.expressions[0].args[0]
raise "expression ascription did not produce a wrapper" if ast_kind(ascription) != :type_ascription
raise "ascription lost its expression" if ast_kind(ascription.expression) != :var
raise "ascription lost its variable name" if ascription.expression.name != "value"
raise "ascription lost its type" if ascription.type_hint != "f64"

plain_value = parse_ascription_source("value").expressions[0]
raise "type hint contaminated another interned variable occurrence" if plain_value.type_hint != nil

interp = Interpreter.new([])
env = Environment.new()
unsigned = Tungsten:AST:TypeAscription.new(Tungsten:AST:Int.new(-1, nil, "-1"), "u64")
raise "interpreter did not apply u64 expression ascription" if interp.evaluate(unsigned, env).to_s() != "18446744073709551615"

as_float = Tungsten:AST:TypeAscription.new(Tungsten:AST:Int.new(81, nil, "81"), "f64")
float_value = interp.evaluate(as_float, env)
raise "interpreter did not apply f64 expression ascription" if type(float_value) != "Float" || float_value != 81.0

raise "compiled f64 to i64 ascription failed" if as_i64((-81.9) ## f64) != -81
raise "compiled f64 to u64 ascription failed" if as_u64(81.9 ## f64) != 81
raise "compiled f32 to i128 ascription failed" if as_i128((-81.9) ## f32) != -81
raise "compiled f32 to u128 ascription failed" if as_u128(81.9 ## f32) != 81
