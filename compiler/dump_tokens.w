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
  val = values[i]
  if type_id == 25 && val == nil
    val = lexer.slice_chars((p >> 2) & 0xFFFFFF, (p >> 26) & 0xFFF)
  << type_id.to_s() + " " + val.to_s()
  i += 1
