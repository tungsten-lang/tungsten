# Entry module for a program that embeds the Tungsten interpreter: the lexer,
# parser and tree-walker, plus the helpers their error paths need. A host
# reaches it through its toolchain's core root:
#
#   use core/../compiler/lib/embed
#
#   interp = Interpreter.new([])
#   interp.sandbox!
#   interp.run(source, "script.w")
#
# The embedding and sandbox API is documented in interpreter/sandbox.w and
# doc/SANDBOX.md ("Embedded interpreter").
use hashing
use error_formatter
use interpreter
