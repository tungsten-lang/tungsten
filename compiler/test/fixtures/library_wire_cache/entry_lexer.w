use ../../../lib/lexer

Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!

lexer = Lexer.new("answer = 41 + 1\n", "(library-cache-bench)")
<< lexer.tokenize()
