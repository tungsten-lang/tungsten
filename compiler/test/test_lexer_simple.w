use ../lib/lexer
use ../lib/ast
use ../lib/parser
use ../lib/environment
use ../lib/builtins
use ../lib/interpreter
<< "loaded all modules"

# Meta-interpreter smoke test
# Tests: implementations/ruby (Ruby) interprets tungsten.w, which interprets user code

interp = Interpreter.new()

interp.run("<< 42")
interp.run("x = 5\n<< x")
interp.run("<< 1 + 2 * 3")
interp.run("if true\n  << \"yes\"")
interp.run("-> add(a, b)\n  a + b\n\n<< add(3, 4)")
interp.run("-> abs(n)\n  if n < 0\n    return 0 - n\n  n\n\n<< abs(5)\n<< abs(-3)")
