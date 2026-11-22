# JavaScript runtime (Tungsten)

The engine that runs JavaScript in Tungsten: first for Blade, the browser, and then as a
first-class language (`bin/tungsten file.js`). The front end (lexer, parser, AST codec and
cache) lives beside it in `languages/javascript/` (branch js-frontend).

Blade develops this code in `apps/blade/lib/blade/js/` (Blade takes no shared code) and
`tools/sync_runtime.sh` mirrors it here.

| File | What |
|---|---|
| `value.w` | the value model, objects (ordinary, arrays, functions, property descriptors, private elements) and the abstract operations (ECMA-262 §6–7) |
| `realm.w` | the runtime contract: realm and intrinsics, builtin-definition helpers, iteration protocol, job queue, host hooks |
| `ops.w` | operators (§13), with number/string fast paths and BigInt |
| `interp.w` | tier 0: the closure compiler (scopes, slots, statements, expressions, patterns, functions, classes, eval) and its run-time helpers |
| `runtime.w` | frames, property access on any value, [[Call]]/[[Construct]] of compiled functions, generators/async on goroutines, the error bridge |
| `module.w` | ES modules: live bindings through cells, `export *`, dynamic `import()`, `import.meta` |
| `regexp.w` | a backtracking regex engine with ES semantics (flags dgimsuvy, named groups, lookbehind, `\p{}`), and RegExp |
| `b_*.w` | builtins: Object/Function/Boolean/Symbol/Error, Array, iterators and generator prototypes, String, Number/Math/BigInt, JSON, Promise, Map/Set/Weak*, console, Date (system zone from TZif), Proxy/Reflect, typed arrays/ArrayBuffer/DataView |
| `engine.w` | load order; `js_new_realm(host)`, `js_run_script(src)` |
| `tools/test262.w`, `tools/test262.py` | the test262 runner (one realm per test) and a driver that survives crashes and hangs |

Design (agreed with the user):
- Tier 0 is a closure-compiling interpreter: the AST becomes Tungsten lambdas once, so pages start immediately.
  Identifiers resolve at compile time to (frame hops, slot); a block gets its own frame only when a closure
  inside it could capture its bindings, and `for (let …)` copies its frame per iteration only then. No
  per-op hashing for locals. Statements return nil or a JsCompletion (break/continue/return); throw is a
  Tungsten raise of JsThrow.
- Tier 1 compiles JS to WIRE, with hot functions compiled lazily from tier-0 type feedback. Results are content-hashed and cached in the build store, so a library seen on one site is compiled once for every site, and loaded with the in-memory JIT loader. (Not built yet; each JsCode keeps its source span so it can be added per function.)
- Function bodies are deduplicated by canonical AST hash (positions excluded), as Tungsten does for its own functions.
- The parsed-AST cache is keyed by sha256 of the source.
- Generators and async run on goroutines (Tungsten's cooperative coroutines): the body runs on its own
  stack and `yield`/`await` are unbuffered channel handoffs. Goroutine stacks are 4 MB (address space).
- The DOM is Blade's Node.

Tungsten core gaps found while writing this (minimal reproductions in `repros/`; each is worked around
in place with a TODO(tungsten) note):
- `super_default3.w`: `super(...)` inside an override whose parameter list has a default value does
  nothing in compiled code (the interpreter calls the parent).
- `if_lambda.w`: assigning a lambda literal to an existing local inside an `if`/`while` body is lost in
  compiled code (the local keeps its old value).
- `numeric_infer.w`: a function that returns its untyped argument on one path and a Float on another
  is typed as returning Float; returning an object then dies with "expected numeric type".
- `field_reopen.w`: reopening a parent class to add a field after a subclass declared fields makes the
  two fields share storage.
- `0.chr` is "" in toolchains before 6423288b (chr-nul).
- No local time-zone offset primitive (Date reads /etc/localtime itself), and no stdout flush or stderr
  write except `ccall("w_flush")` / `ccall("w_eputs", …)`.
- `ccall("w_goroutine_stack_size_hint", n)` ignores an untyped literal `n` (it needs `## int`), which
  also affects the self-hosted interpreter's own call.
