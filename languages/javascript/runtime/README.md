# JavaScript runtime (Tungsten)

The engine that runs JavaScript in Tungsten: first for Blade, the browser, and then as a
first-class language (`bin/tungsten file.js`). The front end (lexer, parser, AST codec and
cache) lives beside it in `languages/javascript/` (branch js-frontend).

| File | What |
|---|---|
| `value.w` | the value model and abstract operations (ECMA-262 §6–7) |
| `realm.w` | the runtime contract: realm and intrinsics, builtin-definition helpers, iteration protocol, job queue, host hooks |

Design (agreed with the user):
- Tier 0 is a closure-compiling interpreter: the AST becomes Tungsten lambdas once, so pages start immediately.
- Tier 1 compiles JS to WIRE, with hot functions compiled lazily from tier-0 type feedback. Results are content-hashed and cached in the build store, so a library seen on one site is compiled once for every site, and loaded with the in-memory JIT loader.
- Function bodies are deduplicated by canonical AST hash (positions excluded), as Tungsten does for its own functions.
- The parsed-AST cache is keyed by sha256 of the source.
- Generators and async run on Tungsten fibers, and the event loop is Tungsten's.
- The DOM is Blade's Node.
