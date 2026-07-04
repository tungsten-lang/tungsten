# Print the AST for a Tungsten source file
# Usage: tungsten print_ast.w <file.w>

use lib/lexer
use lib/parser

args = argv()
if args.size() == 0
  << "Usage: tungsten print_ast.w <file.w>"
  exit 1

src_path = args[0]
source = read_file(src_path)

lexer = Lexer.new(source)
token_count = lexer.tokenize()
parser = Parser.new(token_count, lexer.packed_tokens, source, lexer.values, lexer.line_at, lexer.col_at, lexer.file).set_chars(lexer.chars)
ast = parser.parse()

<< ast
