# Tungsten language server

The stdio server supports symbols, hover, definitions, references, completion,
signature help, diagnostics, parameter rename, and duplicate-import quick fixes.

## Refactoring

`textDocument/prepareRename` and `textDocument/rename` support explicit
positional parameters within one function or method. The server matches lexer
tokens to AST binding occurrences, uses UTF-16 source ranges, preserves
same-named parameters in other functions, and returns versioned
`documentChanges`. The editor applies the returned edits; the server never
writes the source file.

This first refactoring surface rejects nested captures, keyword/ivar/splat
parameters, defaults, interpolation, hash shorthand, name-bound type hints,
and name collisions. Cross-file functions, methods, classes, and fields are
not advertised as safe rename targets. Existing text-based reference search
is not used to authorize edits. These limits are deliberate until the compiler
provides occurrence-level locations and a complete workspace binding index.

`textDocument/codeAction` returns `quickfix` edits for duplicate unconditional
top-level imports in the requested range. Commented imports are preserved.

The transport follows the [Language Server Protocol](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/).

## Focused local verification

From the repository root:

```sh
mkdir -p build/reports
TUNGSTEN_C_INCLUDES=bits/tungsten-json/runtime/json_simd.c \
  bin/tungsten-compiler compile bits/tungsten-lsp/lib/lsp.w \
  --out build/reports/lsp-refactor --no-lto
python3 scripts/test-lsp-refactor.py
```

The explicit C include mirrors this bit's `Bitfile`. The test exchanges real
JSON-RPC frames with the compiled server, checks accepted and refused renames,
astral Unicode ranges, versioned edits, quick-fix filtering, and before/after
native execution. Invalid identifiers also exercise the error helpers needed
to keep the server alive after a rejected request.
