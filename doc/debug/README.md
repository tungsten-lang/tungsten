# Tungsten debugging

`bin/tungsten debug program.w` builds symbols, frame pointers, development
checks and the adjacent sidemap, then loads the Tungsten LLDB helpers.
The existing `--build-only`, `--run`, and GDB modes are preserved.

LLDB commands:

- `wbreak core/example.w:12`: break at an exact function declaration in the
  sidemap. `wbreak Example#method` matches class/method names.
- `wsource`: show every source origin for the selected frame's hashed symbol;
  shared implementations can have multiple origins.
- `wvalue 0xfffaffffffffffd6`: decode a raw WValue (this one is -42).
- `wvalue $x0` or `wvalue local`: inspect a register or available local without
  evaluating an expression or calling the target runtime.

WValue-typed C locals/globals receive automatic summaries. Strings are bounded
to 160 bytes; arrays show header/type/size information. Slab strings and other
packed domains currently show identifiers/raw bits. Unreadable memory produces
a diagnostic. No arbitrary object traversal or target calls occur.

This is declaration-level/source-map debugging. The compiler does not yet emit
local-variable DWARF records or complete statement line tables for generated
Tungsten functions, so full source stepping and named Tungsten locals remain a
separate compiler task. Inlining or dead-code elimination can yield a breakpoint
with zero locations; the command reports that explicitly.

For VS Code with CodeLLDB, merge the adjacent `launch.json` and `tasks.json`
examples into `.vscode/`. They build the active source and launch the same
binary/helpers. Existing editor configuration is not overwritten. CLI LLDB and
the native debug build were tested; interactive editor operation was not.

References: [LLDB summaries](https://lldb.llvm.org/use/variable.html),
[CodeLLDB configuration](https://github.com/vadimcn/codelldb/blob/master/MANUAL.md).
Focused check: `python3 scripts/test-lldb-values.py` runs real runtime-produced
values and breakpoint/sidemap commands in LLDB, including invalid memory.
