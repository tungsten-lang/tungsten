# Bootstrap Target

Goal: make `implementations/c/build/tungsten-c` run the self-hosted compiler
well enough to build a native Tungsten compiler.

Non-goals for this phase:

- REPL parity
- arbitrary user application compatibility
- every literal/domain type unless compiler execution reaches it
- general inheritance/trait semantics beyond compiler source needs

Primary source set:

- `compiler/tungsten.w`
- `compiler/lib/*.w`
- `languages/tungsten/tungsten.lex64`
- runtime C support needed by generated binaries

Milestones:

1. Lexer parity for compiler sources.
   The C lexer should emit the same broad packed token classes as
   `compiler/lib/lexer.w`, using the lex64 table and zero-copy source slices.
2. Parser for the compiler subset.
   Produce AST-shaped runtime values compatible with the existing
   self-hosted interpreter model: arrays, hashes, strings, symbols, ints,
   booleans, nil, blocks, functions, simple classes, method defs, and control
   flow.
3. Runtime values.
   Use `WValue` as the public slot representation, with C heap objects for
   strings, arrays, hashes, blocks, classes, and objects. Pull from
   `runtime/runtime.c` where it reduces work without making the shared runtime
   the dumping ground.
4. Bytecode interpreter for compiler execution.
   Compile AST/evaluation operations to bytecode for the compiler path:
   environment lookup/set, calls, receiver calls, blocks, loops, conditionals,
   case, begin/rescue/ensure, and builtin dispatch.
5. Host builtins.
   Implement only what `compiler/tungsten.w` and `compiler/lib/*.w` require:
   `argv`, `read_file`, `file?`, `capture`, `system`, `env`, `clock`, output,
   cache helpers, and the string/array/hash enumerable methods hit by the
   compiler.
6. Bootstrap proof.
   Run the C interpreter on `compiler/tungsten.w compile ...` and produce a
   working compiler binary.

Useful checkpoints:

```sh
make -C implementations/c
implementations/c/build/tungsten-c --check-lex compiler/tungsten.w
make -C implementations/c bootstrap-lex
make -C implementations/c bootstrap-tokens
make -C implementations/c bootstrap-parse
make -C implementations/c bootstrap-ast
TUNGSTEN_LEX64_TABLE=../../languages/tungsten/tungsten.lex64 make -C implementations/c test
```
