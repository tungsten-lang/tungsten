# Print LLVM IR for a Tungsten source file (without compiling)
# Usage: tungsten print_ir.w <file.w>

use lib/compiler
use lib/loader

args = argv()
if args.size() == 0
  << "Usage: tungsten print_ir.w <file.w>"
  exit 1

src_path = args[0]
loader = Loader.new()
ast = loader.load_program_ast(src_path)

ir = compile(ast, src_path)

<< ir
