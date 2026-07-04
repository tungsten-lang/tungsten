# Tungsten C Interpreter

This is a parallel prototype for a C bytecode interpreter. It intentionally
lives outside the Ruby gem and self-hosted compiler paths.

The target is bootstrap practicality, not a full Tungsten implementation: run
just enough of the self-hosted compiler to build the compiler. Unsupported
general-language features should stay explicit until the compiler needs them.

Current shape:

- `src/lexer.c` builds 64-bit LexChar values from the generated
  `languages/tungsten/tungsten.lex64` table and emits packed `W_TAG_CHAR`
  token values using the same offset/length/type layout as `compiler/lib/lexer.w`.
- `src/parser.c` compiles a small expression subset directly to bytecode.
- `src/vm.c` runs the bytecode with `WValue` integer tagging from
  `runtime/wvalue.h`.

The first runnable subset supports:

- integer literals, string literals for `puts`, local variables, assignment
- `+`, `-`, `*`, `/`, comparisons, equality
- `puts expr`

Build:

```sh
make -C implementations/c
```

Run:

```sh
implementations/c/build/tungsten-c implementations/c/tests/smoke.w
implementations/c/build/tungsten-c -e 'a = 40 + 2
puts a'
implementations/c/build/tungsten-c --check-lex compiler/tungsten.w
```

This is a foundation, not yet a replacement for the Ruby interpreter. The next
big steps are full indentation tokens, a real AST or direct bytecode compiler
for Tungsten statements/classes/methods, and optional linking against
`runtime/runtime.c` for arrays, strings, hashes, and objects.
