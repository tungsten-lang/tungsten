use lib/lexer
args = argv()
source = read_file(args[0])
lexer = Lexer.new(source)
count = lexer.tokenize()
packed = lexer.packed_tokens
values = lexer.values
i = 0
while i < count
  p = packed[i]
  type_id = (p >> 38) & 0xFF
  << type_id.to_s() + " " + values[i].to_s()
  i += 1
