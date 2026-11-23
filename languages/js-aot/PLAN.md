# JS-AOT: JavaScript compiled through the Tungsten compiler

Status: M0 and M1 implemented (branch `js-aot`); see "Implementation status" just below and
Appendix B for what was built, the numbers, and where the implementation departs from this plan.
Audience: the agent that implements it. Every stage has an exit criterion with a command and a number.

### Implementation status (kept current)

| Milestone | State |
|---|---|
| M0 | done: `frontend/`, `tier0/` (Blade 99b7307 + the aot body-scope fix), `tools/jsrun.w`, `tools/memstat.sh`, `bench/`, `BASELINE.md` |
| M1 | exit met: see Appendix B.1 (speed, blocks, spike, scale). Tests: T1 on tier 1 6 pass / 17 fail (missing builtins: M2) / 24 unsupported constructs (M3); the test262 sample needs M2's builtins (its harness uses Object, Array, String, Error) and moves there |
| M2 | tier 0 = new tree walker (`tier0/walk.w`, deviation 7): the whole language but `with`, direct eval included (deviation 9); generators/async on goroutines (`runtime/coro.w`); all builtins ported (`runtime/b_*.w`, `regexp.w`). T1 on tier 0: 44/47 (2 `with`, 1 a sloppy eval declaring a function in its caller, deviation 9). test262 built-ins 15,664/18,062 before the fixes the port's report listed (now made); language directories not re-run yet. T3 tier 0: arith 995 ms, closure 885, property 1,170 (M0: 1,621 / 992 / 1,452) |
| M3 | translator: everything but mapped `arguments`, generators, async, eval and `with` (those functions stay in tier 0). T1 on tier 1: 37 pass / 0 fail / 10 tier-0-only; youtube-main 47,143 of 47,143 functions translate. Bench (tier 1 static): arith 46 ms, closure 29, property 63 |
| M5 | units load into a running host (deviation 8): `translate/unit.w`, `unit/prelude.w`, `runtime/units.w`, `runtime/unit_rt.w`, `tools/jsu.sh`, `tools/jsrun3.w`. Bench with units (script body and functions compiled, loaded at run time): arith 105 ms, closure 75, property 108. Blade side: `blade/jsn/unitcache.w` (background builds per 2,000-function window, cache by script SHA-256 and engine id, load at task boundaries) |
| M6 | Blade runs on the new engine (private copy wired to `jsn/engine`): bindings use an engine-neutral API (`blade/js/neutral.w` ↔ `blade/jsn/compat.w`), YouTube's watch page plays in tier 0 |

Next, in order: finish M2 (builtins, eval/with in tier 0, T1 47/47, test262 parity), then M6's
Blade switch on tier 0 of the new runtime (compat layer: `JsObject < JS:Special` with the old
constructor, `is_a?(JsObject)` → `js_object?`, `js_call(f, t, args)` → `js_call_arr`, `.elems` →
the array itself; 15,460 binding lines, ~1,000 call sites to touch), then M5 units (translated
functions + a fast-path prelude, runtime entries through a table handed to `jsu_init`, extracted
from a normal compile) so Blade runs compiled code (`BLADE_JS_ENGINE=aot`). Generators and async
stay in tier 0 until M4. `BLADE_JS_ENGINE=tier0` means the new runtime with units off: the old
closure interpreter and the new runtime cannot be linked into one binary (their global function
names collide), so the old engine is retired when Blade switches.


Deviations from the plan as written, each with its reason:

1. **Value layout (user directive, 2026-11-22).** No new WValue tags. `JS:Object` is a plain
   instance; the inline-cache test is `subtag == 4 && ivars[0] == cached_shape` (the shape load is
   needed anyway, so a dedicated subtag would save nothing). A JS kind byte lives in the spare
   32-bit word of the instance header (`WObject._reserved`, zeroed on every allocation and
   recycle path): 1 ordinary, 2 function, 3 native, 4 bound, 5 exotic, +128 "is a prototype",
   +64/+32 function virtual-property flags. typeof/IsCallable are one header load.
2. **JS arrays are WArrays (user directive).** See 2.3 as amended: the marker is the spare header
   byte `WArray._pad[0]`, not a new ebits code (ebits stays 65 so every core fast path applies).
3. **The prototype lives in the shape** (as V8 maps, JSC structures and SpiderMonkey shapes do),
   so `JS:Object` has six inline slots instead of five, and a cached shape check also fixes the
   prototype chain's first link. Prototype hits are guarded by one global epoch (V8 uses
   per-prototype validity cells; the epoch is the simple form, bumped when any object that is a
   prototype changes layout).
4. **Function entry convention.** Every compiled function is `jsd_N(fe, this, argc, a0..a3, more)`
   where `fe` is its environment (a `JS:Env`, the single captured value, or nil). Functions that
   have an object also get `jsf_N(f, …)` = `jsd_N(f.@env, …)`, reached through the generated
   `js_dispatch(index, …)` switch. Call-only functions and IIFEs are called through `jsd_N`
   directly. (The plan's separate "direct form with exact parameters" is folded into this: the
   generic form already passes four arguments in registers.)
5. **How jsc reaches the compiler.** A driver hook (`program_ast_hook`, compiler/lib/driver/ir.w)
   lets a front end transform the loaded program AST before compilation; `tools/jsc.w` is the
   compiler binary plus the JS front end and sets the hook. The JS runtime is ordinary Tungsten
   source (`runtime/main.w`) loaded as the program; the translated script is appended as
   `Tungsten:AST` nodes. Stage identity verified after the change.
7. **Tier 0 is a new tree walker** (the M9 option, taken in M2 instead of porting `interp.w`):
   it shares `analyze.w`'s layout with tier 1 for free (one owner, so closures cross tiers),
   allocates nothing per node (activations are pooled), and was already faster than the closure
   interpreter on the T3 core before any tuning. Per-node inline caches live in the JsNode's
   annotation slot.
8. **Units are runtime-bound through host closures** (refines section 1.4 after the M1 spike):
   a unit calls the host's runtime only through a table of host closures (one per
   "name/arity", `runtime/unit_rt.w`, generated): the context holds each closure's code pointer
   and captures, and the unit calls the code directly (a closure's code takes its captures and
   raw WValues, so no boxing and no four-argument limit). This needs no symbol exports and no
   compiler unit mode: a unit is an ordinary Tungsten compile of `unit/prelude.w` plus the
   translated functions (unsharded, so `jsu_init` reaches each entry through its `w:` profiler
   alias), loaded with the runtime's in-memory Mach-O loader (`w_jit_load_object`, which now finds
   functions by alias and skips unwind sections). Host values (strings longer than five bytes,
   cells, codes, literal shapes, template objects, the cache table, the prototype epoch) are
   context slots. The prelude keeps fast lanes inline (numbers, booleans, inline caches, plain
   globals, and calls of compiled functions, which jump to the callee's entry without the host).
   The old engine's AOT tier (`blade/js/aot.w`) used closures for its upcalls too.
9. **Direct eval in tier 0** is analysed below the call site as an arrow-like function (its
   this, arguments and new.target are the caller's), with every binding of the calling functions
   kept in environments. A sloppy eval's `var` or function declaration assigns the caller's
   existing binding or a global; one that would add a new variable to a function stays the eval
   code's own (no dynamic variable objects). `with` is not implemented (no YouTube script uses it).
6. **Raw-value discipline.** Fast paths are `fn … (i64 …) i64` functions with `ll` bodies on raw
   WValue bits (`runtime/prims.w`). Measured traps, now rules: a heap value passed to an `ll` fn
   as bits is invisible to escape analysis and gets freed, so pointers are only *stored* through
   `ccall("w_ivar_set_idx", …)` or Tungsten assignment; typed fns must not reference untyped module
   constants (they get boxed wrappers); raw bits beyond 48 bits must not reach untyped code (they
   box as BigInt); typed arrays read on fast paths (`JS_IC`) are declared before the functions that
   read them, so the program declares `JS_IC` ahead of `use runtime/main`.


Words used below:

- **tier 0**: the fallback engine for code that has no native unit yet (today's closure interpreter, ported).
- **tier 1**: JS translated to the Tungsten AST and compiled by the Tungsten compiler.
- **unit**: the native code for a set of functions of one script, built out of process and loaded into the host.
- **host**: the process that runs JS (Blade, or the `jsrun` test runner).
- **static AOT**: a whole JS program plus the JS runtime compiled into one native binary (no loading step). Used for tests and benchmarks.

---

## 0. Decisions in one page

| Question | Decision |
|---|---|
| How does JS reach the compiler? | JS source → cached JsNode AST (`.jsast`) → scope analysis → **Tungsten AST built with the `Tungsten:AST:*` constructors** → `compile(ast, …)` → LLVM IR → clang. No Tungsten source text is generated (a debug printer only). |
| Where does the compiler run? | In a separate long-lived **compile service** (`tungsten-jsc`), never inside Blade. The compiler never frees its memory (270 MB peak for a program of 4,849 functions, 1,000 of them user code, measured), so linking it into the browser would defeat the memory goal. |
| How is the result cached and loaded? | One unit per (script SHA-256, function set), stored in the shared build store under `js-units/`, keyed by script hash + AST version + JS ABI version + compiler identity + target. Loaded with `w_jit_load_object` (about 3 ms), falling back to `w_dlopen`. Validation reads a manifest; nothing is regenerated. |
| Compile latency on several MB of JS | Tier 0 runs at once. The service builds a unit in the background for the functions that actually ran; later visits start native. Per-function fallback, so a unit never has to cover a whole script. |
| Does the closure interpreter stay? | As the execution engine: no. It is replaced by compiled code for everything in the cache. As tier 0: yes for now, ported onto the new runtime, because `eval`, `new Function`, inline handlers and first visits need something that starts in microseconds. `aot.w` is deleted. Milestone 9 decides with numbers whether tier 0 becomes a tree walker with no per-node allocation. |
| Value representation | Tungsten's own WValue, unchanged. It is already NaN-boxed with immediate doubles, and it is what the current engine uses. No second tagging scheme. |
| Object model | New `JS:Object` with shapes, inline slots and per-site inline caches. Core `Hash` and `Array` are used inside it, not subclassed. |
| Function objects | Static analysis of how each function *value* is used (section 3.9). A function that is only called gets no object. A callback handed to an engine builtin gets none either. One that escapes gets a lean object, made at the point of escape, with no property storage until something writes to it. |
| Async | New core pieces: `JobQueue`, non-blocking `Future#then`, a `Coroutine` class and a compiler pass that lowers resumable functions to state machines. Goroutines are no longer used for generators or async functions. |
| Collection | The registry collector (`gc.w`) evolves in two steps: precise at task boundaries (G1), then conservative stack roots for collection in the middle of a task (G2). No shadow stack, no stack maps. |
| Blade | Switches over in milestone 6 behind `BLADE_JS_ENGINE=aot`, with a compatibility layer so the 15,000 lines of bindings port mechanically. |

What I measured for this plan is in Appendix A. The numbers that drive the design:

- Hand-translated Tungsten in the shape tier 1 will emit ran **16×, 10× and 80× faster** than the closure interpreter on closure creation, property access and arithmetic, with 8.5×, 2× and 12× less peak memory before any collector.
- A separately compiled Tungsten unit loaded into a running host with `dlopen` **can already** send messages to host objects, call host closures, allocate arrays, hashes and strings, and raise and rescue. It needed three manual fixes, which become the compiler's "unit mode" (section 1.4).
- Lowering costs about 0.1 ms of CPU per small function and clang -O3 about 2 ms. `youtube-main.js` has 47,407 `function` keywords in 10.9 MB.

---

## 1. Architecture

### 1.1 Pipeline

```text
                         ┌──────────── host (Blade / jsrun) ─────────────┐
JS source ─ sha256 ─┬──▶ │ .jsast cache ─▶ JsNode AST ─▶ analyze ─▶ tier 0 │
                    │    │                               │  (JS:Code per fn)
                    │    │      unit ready? ─ load ──────┘  entries patched │
                    │    └───────────────▲───────────────────────────────┘
                    │                    │ <store>/js-units/…{.o,.dylib,.manifest}
                    │    ┌───────────────┴──── tungsten-jsc (service) ─────┐
                    └──▶ │ .jsast ─▶ analyze ─▶ translate ─▶ Tungsten AST   │
                         │   ─▶ compile() (WIRE, ownership, emit) ─▶ clang  │
                         └──────────────────────────────────────────────────┘
```

The same `analyze` pass runs in both places. It is the single source of truth for scope layout: which variables are native locals, which live in an environment record, and at which slot. Tier 0 and tier 1 therefore agree on every closure environment, and a function compiled natively can be nested inside, or contain, a function still running in tier 0. (`aot.w` does this today by reusing the interpreter's scopes. A layout mismatch between cache and interpreter is what broke YouTube with the `jsaot-1` cache, so the layout gets one owner and a version number.)

### 1.2 Why the Tungsten AST and not source text or WIRE

- **AST, in process inside the service.** `Tungsten:AST:Call.new(...)`, `FnDef.new(...)` and the rest are ordinary constructors the compiler already uses on itself (`compiler/lib/lowering/calls.w:1411`, `blocks.w:52`). `Tungsten:AST:Store.reset` is the per-compile reset "for REPL/JIT callers" (`compiler/lib/ast.w:31-42`). `compile(ast, source_path, …)` (`compiler/lib/compiler.w:313`) takes the AST and returns LLVM IR.
- **Not source text.** Tungsten identifiers are snake_case only, `[` interpolates in strings, `~` prefixes floats, and several words are reserved. Printing and re-parsing megabytes of generated text buys nothing. A printer (`tools/dump_w.w`, built on `ast_to_tree`) exists only so a human can read what was emitted and cut a compiler bug down to a `.w` reproduction.
- **Not WIRE.** Skipping lowering would skip type inference, monomorphization, no-raise analysis and ownership, which are the reasons to use the Tungsten compiler at all.

### 1.3 The compile service

`tungsten-jsc` is a Tungsten program in `languages/js-aot/service/` that `use`s `compiler/lib/driver_modules` the way `compiler/repl.w` does.

- Started by the host on first need, kept alive while requests arrive, exits after 60 s idle. One per machine user (a lock file in the store).
- Requests are one JSON line on stdin: script key, goal (script or module), the list of function indices to compile (pre-order indices from the `.jsast` function table) or `all`, and options. The `.jsast` is read from the store, so source text never crosses the pipe.
- The reply is one JSON line: unit path or an error with the unsupported-construct list.
- It pays the toolchain discovery once. Every compiler process start measured about 5 s of wall time inside `detect_target` / `host_c_compiler` / `target_homebrew_formula_prefix` (`compiler/lib/target.w`), all of it waiting on subprocesses, on a loaded machine.
- It shards a large unit across cores with the existing sharded codegen (`compiler/lib/emitter/sharded.w`, `driver/shard_codegen.w`).
- If no toolchain is installed the host simply stays in tier 0, as Blade does today without clang.

### 1.4 Units and how they bind to the host

A unit holds the compiled functions of one script. It defines **no classes**, and it reaches the host's JS runtime only through values handed to its init function and through runtime message sends. I call this *runtime-bound*. The probe in Appendix A.3 shows the mechanism works with today's compiler: a unit's dynamic sends to a host class instance resolve through the runtime's own inline caches (`w_method_call_cached`), and nothing in the unit depends on the host's class ids or ivar offsets.

Unit contract:

- `jsu_init(ctx)`: called once per (unit, realm). `ctx` is a Tungsten Array from the host holding the runtime helper table, the `JS:Code` descriptors for every function the unit mentions, and the unit's inline-cache table for that realm.
- One entry per function: `jsf_<n>(f, this, argc, a0, a1, a2, a3, more)`, all untyped WValues (the compiler passes them as `i64`; see the IR in A.3). Eight register arguments on arm64, so calls with up to four arguments allocate nothing. `more` is a Tungsten Array only when `argc > 4`.
- The host calls an entry through an `ll`-bodied trampoline, the same technique as `jsn_invoke` in `aot.w:536`. This sidesteps the four-argument limit of `Closure#call`.
- Inside a unit, a call to a function that analysis proves is bound once (a function declaration never reassigned, in a scope with no `eval` or `with`) is a direct Tungsten call with exact parameters, so clang can inline it.

Compiler work this needs, **"unit mode"** (core addition C1, section 4.5). The probe needed these by hand:

1. Exported entries. Today a top-level function is `define internal` and unreachable from outside.
2. No `main`, no scheduler run, no second copy of core. A 15-line unit currently drags in 804 functions, 106,000 lines of IR and 785 KB. Core functions become `declare`s that resolve against the host, which is linked with `-export_dynamic` (the REPL host already is).
3. A keep-list so the host does not dead-strip core symbols a unit may need (the probe's `dlopen` failed on two BigInt symbols until they were stubbed).

Later, and only if milestone 8 shows the need, units may become *layout-bound*: compiled against a host manifest of class ids and ivar offsets so `o.shape` is a load instead of a cached send. That is an optimization, not a requirement.

### 1.5 Cache

```text
<store>/js-ast/<2 hex>/<sha256>-v<JS_AST_VERSION>-<s|m>.jsast          (exists on js-frontend)
<store>/js-units/<2 hex>/<key>.o | .dylib | .manifest
key = sha256(source) "-" JS_AST_VERSION "-" JS_ABI "-" <compiler exe identity> "-" <target> "-" <opt> "-" <set id>
```

- `<store>` is the shared build store (`TUNGSTEN_BUILD_STORE`, else `~/.tungsten/build`). Add the new artifact kind to `scripts/test-build-store.sh` and to `bin/commands/cache_gc.sh`'s sweep, as AGENTS.md requires. Blade keeps its own directory (`~/Library/Caches/Blade/js-units`) through the same code with a different root.
- `JS_ABI` is one integer bumped whenever the scope layout, entry signature, helper table or `JS:` object layout changes. It replaces `JS_AOT_VERSION`.
- The compiler exe identity is the one `driver/ir.w:625-645` already computes for the Core cache.
- The manifest lists: every key component, the functions covered (pre-order index → symbol → canonical function hash from `ast_codec`), the constants each needs from the host, and the unsupported functions with the reason.
- Loading checks the manifest fields and nothing else. Today's AOT regenerates IR to validate each function (5% of YouTube CPU) and pays the dyld floor per dylib (another 5%). Both go away.
- Publishing is temp file plus rename, the manifest last.

### 1.6 Tiering and latency

| Situation | What runs |
|---|---|
| First sight of a script | Tier 0 immediately. Functions are still compiled lazily on first call. |
| Page goes idle, or 5 s of JS time accumulate | Host asks the service for a unit covering every function that has run, plus their statically bound callees. |
| Unit arrives during the session | `JS:Code` entries are patched at the next task boundary. New calls go native. Activations already running finish in tier 0 (no on-stack replacement). |
| Later visit, same script bytes | Unit is loaded before the script's first statement runs. Functions not in it run in tier 0 and are queued for a delta unit. |
| Function uses direct `eval`, `with`, or a mapped `arguments` object | Never compiled. Stays in tier 0 for good. |
| `eval(str)`, `new Function`, string timers, inline handlers | Tier 0. If the same source text gets hot (BotGuard's VM), it is keyed by its own SHA-256 like any script. |
| JS builtins shipped with the host (Blade's 75 KB `web.js`, compiled per realm today) | Compiled at host build time and linked statically. |

Measured in milestone 1 on `youtube-main.js` (Appendix B.1): lowering costs 0.22 ms and about
270 KB of compiler memory per translated function, clang about 2.7 ms of CPU, and the code is
844 bytes per function. The executed subset (assume 10,000 functions) is therefore about 2 s of
lowering and 27 s of clang CPU, a few seconds of wall time on eight cores. The whole file (44,535
functions the slice translates) needs more than 16 GB in one compile (it was stopped at the cap
after 40 s), so units are sharded at 2,000 functions per compile (about 1.1 GB each).

Rejected alternatives:

- **Compile everything before running.** Minutes of delay on a first visit.
- **Baseline-compile each function on first call.** The REPL measures 17 ms per snippet with the in-memory loader; thousands of first calls per page make that seconds of stalls.
- **Run the Tungsten AST on Tungsten's tree-walking interpreter as tier 0.** One translator and one semantics would be attractive, but interpreted instances are Hashes (`rt: :object`), not compiled objects, so the interpreter cannot share `JS:` objects with compiled code.

---

## 2. The `JS:` namespace layer

Namespace syntax is a file-level directive: `in JS`, after which `+ Object` defines `JS:Object` (`compiler/lib/parser/core.w:875-893`; precedent `in Tungsten:AST` with its own `Int`, `String`, `Array`). References from outside are written `JS:Object`.

Two rules for the whole layer:

1. **Never subclass or reopen a core class.** Subclassing core `Array` forces the compiler's "monolithic fallback" and disables Core cache reuse; reopening clears the container contracts (`compiler.w:401-402`). `JS:Array` is a subclass of `JS:Object` that *holds* a core `Array`.
2. **No escaping Tungsten lambda is created per operation.** Each one costs a 24-byte closure, a captures array and 16-byte capture cells that nothing ever frees (`runtime.c:51642`; `w_value_free` skips cells). Those cells are the 16.5 M 16-byte blocks seen on YouTube. Promise reactions, bound functions and natives carry data fields and a static function reference instead.

### 2.1 Values

| JS | Representation | Core class used as is? |
|---|---|---|
| undefined | `nil` | yes |
| null | `JS:NULL`, the one instance of `JS:Null` | no (a second "nothing") |
| boolean | `true` / `false` | yes |
| number | `Float`, always. An immediate in the NaN-box, never allocated | yes for storage, `+ - * / %`, comparison, `Math.*` |
| string | `String` (UTF-8, lone surrogates as WTF-8) | yes for storage, concatenation, equality, hashing |
| bigint | `JS:BigInt` wrapping a core `Integer` | arithmetic is core; the wrapper keeps it apart from numbers |
| symbol | `JS:Symbol` | no (core symbols are interned by name; JS symbols are identities) |
| object | `JS:Object` and subclasses | no |

Numbers are always `Float` at the value level. Machine integers exist only as unboxed locals inside a compiled function (section 3.2). There is no small-integer tag to check, because a double is already as cheap as one.

`JS:BigInt` stays a wrapper although a bare core `Int` would be distinguishable from a `Float`. Host code that leaks an `Int` where a number was meant (`arr.size` without `+ ~0.0`) would otherwise silently become a bigint. `JS.check(v)` asserts the invariant at the binding boundary in debug builds.

### 2.2 `JS:Object`

A Tungsten instance costs 8 bytes of header plus 8 bytes per ivar with a floor of eight ivars (72 bytes), and 8-slot objects have a recycle pool in the runtime (`runtime.c:51131-51180`). So the layout is exactly eight ivars:

```text
JS:Object   @shape  @proto  @ext  @s0 @s1 @s2 @s3 @s4          72 bytes, one block
```

- `@shape` is a `JS:Shape`: the key → slot index table (a core `Hash`, insertion-ordered), attribute bits per key, the transition table to child shapes (a core `Hash`), and flags (extensible, has-accessors, has-index-keys, dictionary). Shapes are shared by every object built the same way.
- Properties 0–4 live in `@s0..@s4`. Property 5 onwards lives in `@ext`, a core `Array`, allocated on demand. Milestone 1 measures the own-property count histogram on the YouTube corpus and fixes the split.
- **Property order** is integer keys ascending, then strings in insertion order, then symbols. Integer-like keys go to an element store, so the shape's own order is already the spec order for the rest.
- **Accessors and non-default attributes** are flags in the shape; the slot holds a `JS:Accessor` pair. Ordinary objects pay nothing.
- **Dictionary mode**: after a `delete`, or past 64 properties, an object gets a private shape whose table is its own `Hash`. Sites then miss their caches and take the generic path.
- **Exotic objects** (Proxy, arguments, typed arrays, and Blade's 30 host subclasses) override `get`, `set`, `has_property?`, `delete_own`, `own_keys`, `get_own_property`, `define_own_property`. They carry the shared `JS:EXOTIC` shape, which no inline cache ever matches.
- Private names (`#x`) are ordinary shape keys whose key object is a `JS:PrivateName`.

Inline cache at a site `o.x`, as emitted:

```text
s = js_shape_of(o)                       # nil unless o is a JS:Object
v = s == ics[k] ? js_slot(o, ics[k + 1]) : js_get_miss(o, "x", ics, k)
```

`ics` is the unit's cache table for the current realm, read once per function from `f.code.ics`. A miss fills the cache for own data properties and for prototype hits guarded by the prototype's shape.

Today an object literal costs a 96-byte instance plus a 168-byte Hash. This design costs one 72-byte block for up to five properties.

Shared key layouts, which are where the per-object Hash goes:

- **Literals.** An object literal with static keys has its final shape computed once per (site, realm) at unit init. Creating the object is one allocation with that shape and the values stored straight into slots; no transitions are walked and no keys are stored per object.
- **Constructors and classes.** A `new F` site caches the starting shape for `F.prototype`. Each `this.x = …` in the constructor is an add-property site that caches (old shape → new shape, slot), so every instance built by the same path ends with the same shape and the keys exist once. Class fields work the same way.
- **Pre-sizing.** When a constructor's final shape has more than five properties, the shape records the count after it has been seen eight times, and later instances allocate `@ext` at that exact capacity.
- **Shape count is bounded.** A shape with more than 32 child transitions, or an object that adds keys in a data-dependent order (used as a map), goes to dictionary mode instead of growing the tree.

### 2.3 `JS:Array`

**As built (user directive):** a JS array *is* a core `Array` (polymorphic, ebits 65), marked in its
spare header byte `WArray._pad[0]` (`runtime/array.w`): `JS_AF_ARRAY`, `JS_AF_HOLES` (may hold
`JS_HOLE`; when clear an in-bounds read needs no check), `JS_AF_EXT` (named properties, a non-default
prototype, sparse elements or a non-writable length, kept in a side `JS:Object` keyed by the
array's pointer). One allocation for the header, one for the slots, and core speed for indexing,
`push`, `pop`; a core `copy`/`dup` is an unflagged engine array. (V8 tracks the same facts as
elements kinds plus a properties store; JSC as indexing types plus the butterfly.) If the side
table shows up in profiles, an 8-byte `ext` word at WArray offset 24 costs no memory (macOS malloc
already rounds the 24-byte header to 32). The original design below is kept for reference.

`JS:Array < JS:Object` adds `@elems` (core `Array`) and `@len`.

- Dense storage is the core array. A hole is the `JS:HOLE` sentinel. A write far past the end (more than 65,536, the current `ARRAY_GAP`) moves the array to sparse mode, where indices live in a `Hash`.
- `length` is `@elems.size` when dense. Assigning `length` truncates or records a sparse length.
- A slice from core is a borrowed view that cannot grow, so the runtime uses `copy`, never `slice`, for anything that becomes an array's storage.
- `arr[i]` with `i` a non-negative integral double and `arr` dense is one bounds check and one load, inline.
- Empty arrays are truthy and equal only to themselves; both fall out of the generic rules (section 3.1).
- `push`, `pop`, `shift`, `splice`, `sort`, `indexOf` and the rest call the core array methods on `@elems` when the array is dense and has no holes, and the spec's generic algorithm otherwise.

### 2.4 `JS:String`

A JS string value is a core `String`. `JS:String` is a class of static methods (UTF-16 semantics) and also the wrapper object for `new String(s)`.

- Core strings index by code point and measure in bytes. JS needs UTF-16 code units.
- An ASCII string (`String#ascii?`) has units = bytes, so `length`, `charCodeAt`, `slice` and `indexOf` are direct. This is the common case and needs no side data.
- A non-ASCII string gets a unit index built on first indexed access and kept in a small cache keyed by string identity (today's `js_units` cache, four entries per thread, grown to 64).
- Strings up to 5 bytes are immediates and strings of 6–61 bytes are slab-interned (`wvalue.h:708,734`), so most property names and short results never touch `malloc`.
- `s += x` in a loop builds through a `StringBuffer` held in the local and materialized on first read (the existing `sbuild` analysis in `interp.w`). No rope type.

### 2.5 `JS:Number`

Static methods only, plus the `new Number(x)` wrapper.

- Core `Float` already has the IEEE behaviour JS needs: I measured `0/0` → NaN, `NaN == NaN` false, `-0 == 0` true, `1/-0` → -inf, and `%` truncating like `fmod` (`-5.5 % 2` = -1.5).
- JS-specific: number → string (core prints `9.9999999999999995e-08` where JS prints `1e-7`, and `1.2345678901234568e+20` where JS prints `123456789012345680000`), string → number, `**` (JS differs from C `pow` for `1 ** Infinity` and `NaN ** 0`), `ToInt32` / `ToUint32` (modular, where core `to_i` saturates), `toFixed` and friends. These port from `value.w` and `b_number.w`.

### 2.6 `JS:Function`

As built: `JS:Function < JS:Base` is `@shape @ext @code @env` plus four inline slots, eight ivars
(72 bytes, an 80-byte malloc block, recycle-pool size). The object layout is `JS:Base` (`@shape
@ext`) with subclasses adding their fields before their inline slots; the shape records where
inline slots start (`ibase`) and how many there are (`inline`).

```text
JS:Function < JS:Object     … @code  @env                    88 bytes, one block
JS:Code                     name, length, kind, flags, entry, body0, node, src span, url, ics, calls, unit
```

- `@code` is the shared static descriptor: one per function per loaded script. `entry` is the native entry address (an Int) or 0. `body0` is tier 0's compiled form, built on first call.
- `@env` is the captured environment record, or `nil`.
- `name`, `length` and `prototype` are **virtual**: read from the code until someone writes, deletes or redefines them, at which point they become real properties. `prototype` is created on first read (the existing `@lazy` scheme).
- Natives: `JS:NativeFunction` with a static Tungsten function reference and one data slot, so a native that needs state does not need a capturing lambda.
- Bound functions: `JS:BoundFunction` with target, this and arguments as fields.

Creating a closure today builds a 25-ivar `JsFunction` (208 bytes), two Hashes of 168 bytes each for `length`/`name` and their attributes (`JsFunction.new`, `value.w:776`, allocates `@props = {}` and `@attrs` for every function object whether or not a script ever touches them), and a registry push: about 544 bytes in five blocks. That is the `js_make_closure` 41% of allocation work. Here it is one 88-byte block with no property storage until the first write, and section 3.9 removes the object altogether where analysis allows.

### 2.7 Environments

`JS:Env` is an eight-ivar instance: `@up` and `@v0..@v6`. A scope with more than seven captured variables uses `JS:EnvN` (`@up`, `@vars` as a core Array). Only captured variables live in an environment. A function with no captured variables allocates none.

### 2.8 The rest

| Type | Design | Core reuse |
|---|---|---|
| `JS:Symbol` | description, registry key | registry is a `Hash` |
| `JS:Map`, `JS:Set` | entries in a core `Hash` (insertion-ordered; NaN keys already collapse; `1.0` and `1` are distinct keys, measured) | `Hash` as is. Keys normalize `-0` to `+0` first. Live iteration during mutation uses an entry array with tombstones, as `b_collections.w` does |
| `JS:WeakMap`, `JS:WeakSet`, `JS:WeakRef`, `JS:FinalizationRegistry` | identity `Hash` cleared by the collector in a post-mark pass | `Hash` |
| `JS:RegExp` | the existing ES engine (`regexp.w`: flags dgimsuvy, lookbehind, named groups) | no. Core `Regex` is a different dialect |
| `JS:ArrayBuffer`, typed arrays, `JS:DataView` | bytes in a core `ByteArray`; a typed array whose element type is known compiles to raw typed-array loads | `ByteArray`, `i32[]`, `f64[]` |
| `JS:Date` | time value as a Float; zone rules from TZif | core clock |
| `JS:Promise` | section 4.3 | `JobQueue` |
| `JS:Proxy`, `Reflect` | exotic subclass; `Reflect` calls the internal methods | none |
| `JS:Error` family | ordinary objects; `stack` built from the JS call stack | none |
| `JS:Generator`, `JS:AsyncGenerator` | wrap a core `Coroutine` | `Coroutine` |

### 2.9 Interned names and shared empties

Small items that each remove an allocation from every object:

- **Property names are interned.** Every key in a shape, an inline cache or a literal is one canonical `String` per process, held in `JS:Names`. Cache checks compare keys by identity, and a name is stored once however many shapes use it. The runtime already makes strings of up to 5 bytes immediates and slab-interns 6–61 bytes (`wvalue.h:708,734`), so the table only has work to do for longer names and for computed keys (`o[k]`), which go through a per-site last-key cache. A unit resolves its property names once, in `jsu_init`.
- **Array indices are never turned into strings** on the dense path. Today `get_idx` falls back to `i.to_s`.
- **No empty containers per object.** `nil` means empty everywhere: `@ext` for an object with no overflow properties, `@elems` for an empty array until its first write, the reaction list of a promise (one reaction is stored inline; an Array appears only for the second). Today every object, array and function allocates `@props = {}` (168 bytes) at birth, and functions a second Hash.
- **Shared constants.** One `JS:NO_ARGS` array for zero-argument calls into natives (it exists today), one root shape per prototype, one `JS:EXOTIC` shape, one empty-object shape per realm.

### 2.10 Where "use core without specialization" holds

**Holds:** booleans; number storage and `+ - * / %`, comparisons and `Math`; wrapping integer arithmetic for `|0`, `>>>0`, `Math.imul` and bitwise operators (untyped integer literals are wrapping i64 on the compiled path; I measured `2147483647 * 2147483647 * 4` wrapping); BigInt arithmetic; string storage, concatenation, equality and hashing; strict equality (core `==` is already identity for instances, value for strings, IEEE for floats); dense array storage; dictionary and Map/Set storage; byte buffers and typed arrays; boolean logic once truthiness is established; threads and channels for workers.

**Does not hold:** the object model (prototypes, attributes, order); array holes and `length`; UTF-16 string indexing; truthiness (Tungsten treats `0`, `""` and NaN as true); loose equality and the coercions; `typeof`; number formatting and parsing; symbols; exceptions that carry any value; promise ordering; regular expressions; dates.

So the split is close to what was hoped: the data lives in core classes, and the JS layer is the object model plus coercion rules.

---

## 3. Semantics mapping

The translator is a tree walk from JsNode to Tungsten AST. Rules that need a decision:

### 3.1 Operators and coercions

- Every operator has a runtime function (`js_add`, `js_lt`, …, ported from `ops.w`) and an inline fast path the translator emits when it cannot prove types: `a.is_a?(Float) && b.is_a?(Float) ? a + b : js_add(a, b)`.
- When analysis proves both operands are numbers (literals, results of arithmetic other than `+`, comparisons, `x|0`, typed-array reads), the guard is omitted.
- `===` is core `==` behind a guard for the BigInt wrapper. `==` is `js_loose_eq`. `Object.is` and SameValueZero are `js_same_value` / `js_same_value_zero`.
- Truthiness: `js_truthy(v)` with the fast path `v == true || (v != false && v != nil && js_truthy_slow(v))`. A comparison result is already a Bool and is used directly.
- `typeof`, `ToPrimitive`, `ToNumber`, `ToString`, `ToPropertyKey`, `ToObject` port unchanged from `value.w`.

### 3.2 Arithmetic lanes

| Lane | When | Emitted as |
|---|---|---|
| generic | types unknown | guard plus `js_*` call |
| double | both proven numbers | core `Float` operator, unboxed by the compiler |
| int32, wrapping | bitwise operators, `x\|0`, `x>>>0`, `Math.imul`, a loop counter compared against an int32 bound and only incremented | `## i64` locals, wrapped with `(x << 32) >> 32` (`## i32` does not wrap by itself, `doc/specification/03_grammar.md:489-497`) |
| int, non-wrapping | array indices and lengths | i64, converted to `Float` when it escapes |

A value leaves a lane as a `Float`. No machine integer is ever stored in a property, an environment or an argument.

### 3.3 Calls and `this`

- `this` is the second parameter of every entry. Sloppy functions box a primitive `this` on entry; strict ones do not. Arrows read the enclosing `this` as a captured variable.
- `f(a, b)`: if `f` is a `JS:Function` with a native entry, call it through the trampoline; if it has none, call tier 0; otherwise `js_call_slow` (proxies, callable host objects, the TypeError).
- `o.m(a)`: inline-cache the lookup of `m`, then call with `this = o`.
- `new F(a)`: allocate with the shape cached at the site for `F.prototype`, then call the entry with `new_target` in a per-thread register (constructors that never read `new.target` ignore it).
- Missing arguments arrive as `nil`. Default values and rest parameters read `argc`.
- `arguments`: only materialized when the parser flagged `F_USES_ARGS`. Strict or non-simple parameter lists get an unmapped copy. A sloppy function that needs the mapped form stays in tier 0.
- Stack depth: one counter increment and compare per entry gives `RangeError: Maximum call stack size exceeded` before the native stack runs out.

### 3.4 Variables and closures

For each binding `analyze` decides:

| Kind | Condition | Becomes |
|---|---|---|
| local | not referenced from any nested function, no `eval`/`with` in scope | a Tungsten local (a register) |
| captured | referenced from a nested function | a slot in the scope's `JS:Env` |
| per-iteration | `let` in a loop head, captured | a fresh `JS:Env` per iteration, copied forward |
| script lexical | top-level `let`/`const`/`class` | a `JS:Cell` shared by all scripts of the realm |
| global | unresolved, or top-level `var`/function | a property of the global object, cached per site as a `JS:GlobalCell` |
| dynamic | function contains direct `eval` or `with` | tier 0 only |

Temporal dead zone: a `JS:TDZ` sentinel and a check, omitted when the read is dominated by the initialization.

### 3.5 Control flow

The Tungsten AST has `If`, `While`, `Case`, `Break`, `Next`, `Return`, `Begin` (one rescue, one ensure) and `Raise`. It has no labelled break and no fallthrough. The translator lowers:

- `for (init; test; update)` → `init; first = true; while true { if first then first = false else update; break if !test; body }`, so `continue` is `Next` and still runs `update`.
- `do … while` the same way with the test skipped on the first pass.
- Labelled `break`/`continue` across loops → a flag local, `Break` in the inner loop, and a check after it in each enclosing loop up to the target. A labelled block is a one-pass `while`.
- `switch` → a `Case` when every clause ends in `break`/`return` and the tests are distinct literals (this keeps the LLVM `switch` for the big dispatch loops of VM-style code). Otherwise: compute the entry index with an `if` chain, then one guarded block per clause inside a one-pass `while`.
- No Tungsten blocks or lambdas are emitted for control flow, which avoids the `next`/`return`-inside-block traps.

### 3.6 Exceptions

- `throw v` → `raise JS:Throw.new(v)`. Errors raised by the runtime itself are converted at the catch, as `js_error_value` does.
- `try/catch` → `Begin` with `rescue`.
- `finally` is lowered by hand, not with `ensure`, because a JS `finally` can replace the completion: the body runs in a one-pass loop with a pending-completion record (normal, return value, break target, thrown value); the finally code runs after it; then the record is replayed.
- Exceptions are setjmp/longjmp (`control_flow.w:2411-2440`), about one push and one `setjmp` per `try` entry. Two consequences to measure in milestone 3: the ownership pass skips functions that contain a setjmp (`ownership.w:1993`), and a raise skips pending frees. If either shows up, the translator outlines `try` bodies into their own functions.

### 3.7 Getters, setters, Proxy, Reflect

Accessors are a shape flag: a site whose cache holds an accessor slot calls the getter with the receiver. Proxies and host exotics carry `JS:EXOTIC` and go through the overridden methods. `Reflect.*` calls those methods directly. Nothing in compiled code special-cases a proxy.

### 3.8 `eval`, `with`, strict and sloppy

- Indirect eval and `new Function` are just new scripts in the global scope: tier 0, then a unit if hot.
- A function containing direct `eval` or `with` is marked dynamic by the parser flags (`F_HAS_EVAL`, the `:with` node), and so is every function nested in it that the eval could reach. They run in tier 0 with all bindings in environment records. This costs nothing elsewhere, and both are rare in hot code.
- Strictness is a flag on `JS:Code` and a parameter of the translator: it changes `this` boxing, assignment to undeclared names, failed property writes (throw instead of ignore), `arguments` mapping and `delete` errors.

### 3.9 Function values without function objects

A script *can* attach properties to any function, compare it by identity or print its source. Most never do, and `analyze` can tell which is which by looking at how each function's **value** is used, not just how it is called. The object is needed only when the value becomes visible to code the analysis cannot see.

Every compiled function has two forms: the generic entry `(f, this, argc, a0..a3, more)`, which reads its environment from `f.env`, and a **direct form** `(ics, env, this, p0..pn)` with exact parameters. The direct form needs no function object. Because both exist, every optimization below has a fallback: make the object and use the generic entry.

**Classification.** For each function expression or declaration, `analyze` records every use of its value:

| Class | Condition | What tier 1 emits |
|---|---|---|
| (a) call-only | An IIFE; or bound to a binding that is never reassigned and whose every reference is the callee of a plain call | No object. Each call is a direct call passing the enclosing environment. |
| (b) builtin callback | Written inline as an argument to a call that a run-time guard proves is an engine builtin on the list below | No object. The builtin's loop is emitted inline and calls the direct form. |
| (c) no captures | References no binding of an enclosing function | No environment at all, whichever of the other classes applies. |
| (d) escaping | Anything else: stored in a property, returned, passed to a host API or an unknown callee, exported, a global | A lean object (section 2.6), created at the point of escape, with property storage allocated on first write. |

Details per class:

- **(a) Call-only.** `(function(){…})()` and `(() => …)()` compile to a direct call; if the body is small clang inlines it. For `function helper(){…}` or `var h = function(){…}` used only as `helper(x)`, the hoisted declaration creates nothing at scope entry. Recursion through the function's own name in callee position keeps it call-only.
- **(b) Builtin callbacks.** These builtins are ours, and they never compare the callback by identity, read or write its properties, or hand it to user code. Two groups:
  - *Non-retaining*: `forEach`, `map`, `filter`, `find`, `findIndex`, `findLast`, `findLastIndex`, `some`, `every`, `reduce`, `reduceRight`, `flatMap`, `sort`, `toSorted`, `Array.from` (map function), `String#replace` / `replaceAll` (replacer), `Map#forEach`, `Set#forEach`, the `JSON.parse` reviver and `JSON.stringify` replacer, and the typed-array equivalents. The callback is dead when the call returns.
  - *Retaining, internal*: `Promise#then` / `catch` / `finally` and `queueMicrotask`. The callback outlives the call but only inside a `JS:Reaction` or a job, which stores `(code, env)` directly.
  - At the site, emitted code looks up the method through the inline cache and compares it with the realm's intrinsic, and checks the receiver (a dense `JS:Array` with an untouched prototype chain and species; a native promise with the built-in `then`). If the guard holds, the loop runs inline with direct calls. If it fails (a user-defined `map`, an array-like, a Proxy, a subclass), the site creates the function object then and makes the ordinary call.
  - The inline loop follows the spec for dense arrays (length read once, holes skipped) and drops to the generic builtin if the callback makes the array sparse mid-iteration.
  - A callback that is not written inline is treated the same way when its binding's only uses are calls and arguments at such guarded sites (`arr.forEach(helper)`).
  - **One object per call site where a builtin still wants one.** Only the array iteration family gets an inline loop. The other non-retaining builtins (`sort`, `replace`, the JSON hooks, `Map`/`Set` `forEach`, typed arrays) stay in the runtime and take a function object. Since they never compare it or give it properties, and it is dead when they return, the site keeps a single object in its cache table and reuses it on every execution. When nothing the callback captures varies per iteration, the environment record is the same and the object is reused untouched. When it differs, the site re-points the object's `@env` before the call. A busy flag covers re-entry (the callback reaching the same site again while the outer call is running): a busy site allocates a fresh object.
  - If the guard fails, the callee is unknown code, and each evaluation makes a new object as the language requires.
  - **Frame release.** If every function that captures a scope's variables is class (a) or non-retaining (b), the scope's `JS:Env` cannot outlive the scope. It is not registered with the collector, and the translator emits its release at scope exit, as tier 0 does today for frames nothing can capture (`w_value_free_w` in `js_exec`). An exit by exception skips the release and leaks the 72 bytes, which is Tungsten's own rule for raises. Milestone 3 measures a throw-heavy loop; if it grows, these records are registered instead.
- **(c) No captures.** A function that reads only its own locals, parameters and globals gets no environment: the direct form drops the `env` parameter, and an escaping one has `@env = nil`. Two further cases avoid the environment record:
  - A scope allocates a `JS:Env` only if a captured variable exists. This is already the rule of section 3.4.
  - **A single captured variable that is never reassigned** (a parameter never assigned, or a `const`/`let`/`var` with an initializer that precedes every capturing function expression, with no hoisted function declaration capturing it) is stored in `@env` itself, by value. `mk(i)` returning `function(x){ return x + i }` then allocates one block, not two. Two or three such variables use one flat record created with the function, and the enclosing scope still needs none.
- **(d) Escaping.** The object is created where the value is first read as a value, and cached in the binding's slot so that every later read gives the same object. Identity is therefore exactly what the language specifies. A function declaration in a scope that takes the address of the function on one rare path (`if (debug) el.addEventListener("click", helper)`) pays for the object only on that path.
  - Getters and setters in object literals and classes are stored as `(code, env)` in the `JS:Accessor`. A function object is made only if a script reflects on the descriptor (`Object.getOwnPropertyDescriptor`, `__lookupGetter__`).
  - Host APIs are never on the builtin list. `addEventListener`/`removeEventListener` compare by identity, timers and observers keep the function, and the dev panel reads its name and source position. Those get objects.

**How conservative it is.** A function value is treated as escaping, with the object made eagerly as the language describes, whenever any of these holds:

| Condition | Why |
|---|---|
| Direct `eval` or `with` anywhere in the scope chain of the binding | The eval can name the binding and do anything with it. (These functions are tier 0 anyway.) |
| The binding is a script-level `var`, function declaration or anything on the global object | Other scripts, inline handlers and `window.name` can reach it. Only bindings inside a function or a module are analysed. |
| The binding is exported from a module | Another module holds it. |
| The binding is assigned more than once, or is a block-level function declaration under sloppy Annex B rules | Calls are no longer to one known function. |
| The function's own body refers to itself other than as a callee (a named function expression's name as a value, `arguments.callee`) or uses `new.target` | It can observe its own object. |
| Used with `new`, `.call`, `.apply`, `.bind`, `typeof`, `instanceof`, or any property read or write | These are value uses. (`new` needs `prototype`.) Later work can special-case `.call` and `typeof`. |
| A class, a class method, a generator or an async function | They are created with prototype objects or wrapped results; not worth it. |

What does **not** force an object:

- `Function.prototype.toString`. It can only be called on a value, and any value use already makes the object. The source span lives on `JS:Code`.
- `Error.stack`, the dev panel's stack lines and the watchdog. They are built from the `JS:Code` on the JS call stack, not from function objects.
- The legacy `caller` property. It reports `null` when the caller has no object, which the specification permits.

**Tiers.** Tier 0 does not use the classification: it makes a (lean) object for every function it evaluates. The shared layout always keeps the binding's slot, so a tier 1 function that must call a nested function still in tier 0 makes the object lazily into that slot and calls through it. The direct form is used only when caller and callee are in the same unit.

**Safety net.** `JS_FNOBJ=always` (an option in the unit key) turns the whole analysis off. The differential suite runs with it both ways, plus a set of adversarial tests: properties attached to a callback inside the callback, a user-defined `forEach`, `Array.prototype.map` replaced mid-loop, identity comparison of a function read twice, a callback that deletes array elements, `arguments.callee`, and `toString` on each class.

**What it buys.** Per call of `arr.forEach(function(x){…})` today: a function object (five blocks), an arguments array per element, and a frame per element. After: nothing. On YouTube the forms measured as hottest for `js_make_closure` are `x = function(){}` and `a.b = function(){}`. The first is class (a) whenever `x` is a local that is only called. The second is class (d): the object stays, at 88 bytes in one block where it was about 544 in five. Milestone 1 counts the functions of the js-corpus by class so the expected gain is a number before the work is done.

---

## 4. Async in Tungsten

### 4.1 What exists

- Core `Future` and `Promise` (`core/future.w`, `core/promise.w`) are thread-based and blocking: settlement is an atomic compare-and-swap, waiters block on a channel, `Future.async` and `map` each start an OS thread, `wait(ms)` polls every millisecond. There is no continuation that runs later on the caller's thread.
- No job queue, no `async`/`await`, no generators. `yield` means "call the block".
- The JS engine runs each generator and async function on a goroutine with two unbuffered channels. Blocked channel operations yield-spin rather than park. A suspended goroutine keeps at least one 16 KiB stack page resident. An uncaught raise in a goroutine exits the process, and an abandoned goroutine never runs its `ensure`.

Measured with the current engine (Appendix A.1): 650 ns per `yield`, about 30 KB resident per suspended generator, 3.7 KB allocated per `await`.

### 4.2 State machines versus goroutines

| | Goroutine per coroutine (today) | State machine (this plan) |
|---|---|---|
| Suspended cost | 256-byte struct plus stack pages, never returned | one `Coroutine` (72 bytes) plus a frame array |
| Resume/suspend | two channel handoffs through the scheduler | a call and a `case` |
| Limit | 9,000 live (engine cap), 10,000 (runtime) | memory only |
| Collector | stack is opaque, so everything it allocated is pinned until it finishes | the frame is an ordinary object the collector traces |
| Ownership analysis | cannot see across the switch | sees plain code; values that cross a suspension are stores into the frame, everything else is freed as usual |
| Abandoned coroutine | leaks its stack, `ensure` never runs | the frame is garbage like any object |
| Nested resume | deadlocks (TODO in `runtime.w:666`), worked around by routing through main | plain nested calls |

**How the pinning problem goes away:** after the transform no JS value lives on a native stack across a suspension. Every local of a resumable function is a slot in its frame, and the frame hangs off the generator or promise that will resume it. The collector reaches it like any other object, so there is nothing to pin and no per-coroutine root list.

### 4.3 Core additions

**C2. Resumable functions** — `compiler/lib/resumable.w`, `core/coroutine.w`

- A new AST node `Tungsten:AST:Suspend(value)` and a pass `resumable_lower(fn_def)` that rewrites a function containing `Suspend` nodes into a step function `(co, mode, sent)` plus a constructor that returns a `Coroutine`. It is an AST → AST transform producing only existing node kinds, so it runs before lowering and the compiler, the interpreter and every later pass see ordinary code.
- No surface syntax in this project. (`yield` is taken; a later proposal can add syntax and the Ruby implementation.) Until then the pass is called explicitly by front ends, so nothing changes for existing programs and the stage-identity check is unaffected.
- Shape of the output: all locals become frame slots; the body becomes `while true` around a `case co.state`; each `Suspend` stores the next state and returns; a `Begin` that contains a suspension is re-entered on resume through a handler table indexed by state; a `finally` uses the completion-record lowering of section 3.6.
- `Coroutine`: `state`, `frame`, `step`, `done?`, and `resume(v)`, `throw(e)`, `finish(v)`.
- Specs: `spec/compiler/resumable_spec.w` (loops, nested try/finally, suspension inside expressions, early finish, throw into a suspended try) and `spec/core/coroutine_spec.w`. Both run compiled and interpreted.

**C3. Job queue and continuations** — `core/job_queue.w`, edits to `core/future.w`

- `JobQueue`: a per-thread FIFO. `JobQueue.current`, `enqueue(job)` where a job is any object with `run`, `drain` (runs until empty, including jobs enqueued while draining; returns the count), `empty?`, and a thread-safe inbox so another thread can post.
- `Future#then(on_ok, on_err = nil)` returns a new `Future` and runs the callback as a job on the queue of the thread that called `then`, never inline and never on the settling thread. Also `Future#finally`, `Future.all`, `Future.race`, `Future.any` in non-blocking form. The blocking methods stay.
- This is the "something to handle the callbacks": a worker thread fulfils a promise, the reaction lands in the main thread's queue, and the main loop runs it at its next drain.
- Runtime hook: `w_scheduler_run` drains the current thread's queue before it blocks in `w_event_poll`, so a plain program needs no loop of its own. Blade calls `drain` from its own loop.
- Specs: `spec/core/job_queue_spec.w` (FIFO order, re-entrancy, cross-thread post), `spec/core/future_then_spec.w` (never inline, ordering, error propagation, chaining).

**`JS:Promise` is its own class**, not built on `FutureState`. A `FutureState` allocates three atomics, a mutex and an unbounded channel, far too heavy for something created on every `await`, and JS ordering rules (thenable jobs, the exact number of ticks, species, unhandled-rejection tracking) are stricter than a general future needs. It shares the `JobQueue`, and `JS:Promise.from_future(f)` / `#to_future` bridge the two.

- Reactions are `JS:Reaction` records with a kind field (JS handler, await-resume, async-generator-resume, all/any element, …) dispatched by `case`, with no lambdas.
- `async function` = a resumable function whose driver is `js_async_step(co, cap)`: `await v` is `Suspend`, and the driver attaches one await-resume reaction to `v`. With the fast path for native promises this is one promise, one reaction and no closures per `await`.
- Generators: `JS:Generator` wraps the `Coroutine`; `next`/`throw`/`return` map to `resume`/`throw`/`finish`. Async generators add the request queue from `runtime.w:843-926`.

### 4.4 Integration with Blade's loop

Blade already has the right structure: `JsPageRuntime#drain` runs `realm.run_jobs`, then mutation observers, then unhandled-rejection reports, after every task. `realm.jobs` becomes a `JobQueue`. Frame realms keep sharing their parent's queue. Each worker thread has its own. The timeline's microtask spans (`PT_MICRO`) wrap `drain` as now.

### 4.5 All core and compiler additions

| # | Addition | Files | Needed by |
|---|---|---|---|
| C1 | Unit mode: `compile_unit(ast, opts)`; exported entries; no `main`; core as external declarations; host keep-list | `compiler/lib/driver/unit.w`, small edits in `emitter/artifact.w`, `driver/link.w` | M5 |
| C2 | `Suspend` node, `resumable_lower`, `Coroutine` | `compiler/lib/resumable.w`, `compiler/lib/ast.w`, `ast_schema.w`, `core/coroutine.w` | M4 |
| C3 | `JobQueue`, `Future#then` family, scheduler drain hook | `core/job_queue.w`, `core/future.w`, `runtime/runtime.c` | M4 |
| C4 | `w_stack_words()`: the current thread's stack words and saved registers as an `i64[]`; `w_closure_captures(c)` | `runtime/stack_scan.c` (+ a line in `runtime/sources.txt`) | M7 |
| C5 | `w_jit_load_object` returning a handle with symbol lookup, so one object can export thousands of entries | `runtime/runtime.c` | M5 |
| C6 | Compiler bugs found on generated code (expected; see risk R3) | as found | all |

Every change to `compiler/` or `core/` follows AGENTS.md: note the stage-identity line before, and get the same line after.

---

## 5. Memory model

### 5.1 Where allocations disappear

| Source today | Cost today | After |
|---|---|---|
| Function object creation (`js_make_closure`, 41% of allocation work) | 5 blocks, about 544 bytes | 1 block, 88 bytes, when the value escapes; none for call-only functions and builtin callbacks (section 3.9) |
| Environment for a closure capturing one unchanging variable | a frame Array | none: the value sits in the function's `@env` |
| Compiling function bodies to closure trees (38%) | one 24-byte closure, a captures array and 16-byte cells per AST node, kept for the life of the page | native code in a mapped file; nothing on the heap |
| Tier 0 lazy compile | a fresh `JsCompiler` per function (`js_code_ready`, `interp.w:2003`); the body itself is compiled once per `JsCode`, not per closure | one compiler per script, reused |
| Keys of an object | a 168-byte Hash per object | one shape shared by every object built the same way (section 2.2) |
| Empty `@props` / `@attrs` on every object, array and function | 168 bytes each, allocated at birth | `nil` until needed (section 2.9) |
| Property-name strings | one per use beyond 61 bytes | interned once (section 2.9) |
| Call frame | an Array per call (freed only when nothing could capture it) | registers; a 72-byte `JS:Env` only for scopes with captured variables |
| Arguments | an Array per call | registers up to four arguments |
| Object literal, ≤ 5 properties | instance plus Hash, 264 bytes | 1 block, 72 bytes |
| `await` | 3.7 KB measured | a promise and a reaction, ≤ 300 bytes |
| Suspended generator | about 30 KB resident | ≤ 200 bytes |
| Capture cells from per-operation lambdas | 16 bytes each, never freed | none created (rule 2 of section 2) |

Together the first two rows are the 80% of allocation work measured on YouTube.

### 5.2 Collecting what escapes

Tungsten has no collector: allocation is `malloc`, and the only frees are the ones the compiler inserts for values it proves do not escape (`w_gc_mark_roots` is an empty stub). That stays true for Tungsten. The JS heap gets its own collector, `JS:Heap`, an evolution of `gc.w`.

**What it manages.** Everything allocated on behalf of running JS: objects, arrays and their element stores, functions, environments, coroutine frames, promise records, argument overflow arrays. Each is registered at creation. Registration stores the value in the heap's table, which the compiler's escape analysis sees as an escape, so the compiler will never also free a registered object. The two mechanisms cannot collide.

**Tracing.** Each `JS:` class has a hand-written `js_trace(visitor)` instead of today's reflective walk over ivars. Host classes either implement `js_trace` or register for the reflective walk as now. With C4's `w_closure_captures`, lambdas that host code stores become traceable, which removes the `js_keep` lists and the rule that an untrusted native pins its arguments forever.

**Roots, in two steps.**

- **G1, precise, at task boundaries** (milestone 3). Collection runs when no JS frame is on the stack: after a task's microtasks have drained. Roots are the realms, the job queues, host roots and nothing else, because suspended coroutines are heap objects. Top-level loop back-edges at call depth 0 are also safepoints: the translator passes that function's live reference locals explicitly. No stack scanning, no cooperation from compiled code beyond one flag check per back-edge.
- **G2, conservative stack roots** (milestone 7). For a long task that allocates without returning to the loop, the collector also scans the native stack and saved registers (C4) for words that are registered objects, and treats those as roots. This is the approach JavaScriptCore uses: conservative on the stack, precise in the heap. It requires a non-moving collector, which this is. Compiled code cooperates only by polling a flag at loop back-edges and function entries. Collection is still refused while a builtin or host native is on the stack, because natives may hold JS values in unregistered temporary arrays.

Why not the alternatives:

| Option | Why not |
|---|---|
| Shadow stack | Every reference local is stored to memory around every call. It defeats the register allocation that makes tier 1 fast, on every call, to help a collection that runs rarely. |
| LLVM stack maps / statepoints | Precise and free at run time, but a large change to the emitter (the compiler emits IR text and has no relocation model), and only needed for a moving collector. Revisit if a generational collector is ever wanted. |
| An allocator-level managed heap in the C runtime | Would also catch Tungsten-level temporaries, but the runtime has 293 direct `malloc`/`calloc`/`realloc` sites and no wrapper. Kept as an option (G3) if milestone 7 shows unregistered garbage still dominates. |

**How compiled code cooperates**, in full: it registers what it allocates; it polls one flag at back-edges and entries (the same flag serves the 10-second task watchdog); at depth-0 back-edges it lists its live locals. No write barrier.

**Determinism.** Nothing observable depends on when a collection runs until `WeakRef`/`FinalizationRegistry` exist; when they do, finalizers and cleared refs are delivered only at task boundaries. In `--deterministic` and replay mode collections are triggered by allocation count, never by time.

**Leaks found on the way that the collector must fix:** page runtimes are added to the root set and never removed (`jsdom.w:183`, no removal in `gc.w`), and `JS_MAIN_AGENTS` keeps every runtime. Milestone 6 adds root removal on page teardown.

### 5.3 Targets

Per operation, counted with the malloc histogram tool from milestone 0:

| Operation | Target |
|---|---|
| Closure creation, value escapes | 1 block, ≤ 96 bytes (plus one 72-byte environment per scope instance only if two or more variables, or a reassigned one, are captured) |
| IIFE, or a local function that is only called | 0 blocks |
| `arr.forEach` / `map` / `filter` / `reduce` with an inline callback on a dense array | 0 blocks for the callback and its calls (`map` and `filter` allocate their result) |
| `arr.sort(function…)`, `str.replace(re, function…)` | 0 blocks after the site's first execution |
| `p.then(function…)` on a native promise | the reaction only; no function object |
| Call, ≤ 4 arguments, no captured variables | 0 blocks |
| Object literal, ≤ 5 properties | 1 block, 72 bytes |
| Array literal | 2 blocks, ≤ 176 bytes |
| `await` of a native promise | ≤ 3 blocks, ≤ 300 bytes |
| `yield` | 0 blocks |
| Suspended generator | ≤ 200 bytes |

Steady state for the three loop benchmarks (1 M iterations each, Appendix A.1), with G1 on: peak RSS ≤ 48 MB each (today 713, 359 and 37 MB), and no growth between iteration 100,000 and the end.

YouTube watch page, replayed from a recording, warm unit cache, at 14 s:

| Measure | Today | Target |
|---|---|---|
| Live malloc blocks | about 30 M | ≤ 5 M |
| 16-byte blocks | 16.5 M | ≤ 1 M |
| Peak RSS | recorded in milestone 0 | ≤ 40% of that |
| CPU in JS execution | about 60% of page CPU | ≤ a quarter of today's absolute time |
| Cache load and validation | 10% of page CPU | ≤ 1% |

First visit (cold cache) target: live blocks ≤ 15 M, from the function-object and promise changes alone. Milestone 9 addresses the rest.

---

## 6. Integration with Blade

Facts about today's coupling (from a read of `apps/blade/lib`): about 1,350 native registration sites (`r.method` 603, `js_acc` 374, `js_iface` 162, `r.getter` 110, `r.native` 75); about 30 classes subclass `JsObject` and override its internal methods; bindings call `js_call` (71 sites), `.get` (228), `.put_own` (259), `.define` (199), and read raw slots (`.internal` 276, `.cls` 40, `.elems` 14). The js\*.w binding files total 15,458 lines.

### 6.1 Bindings

- Natives keep the signature `->(this, args, new_target)`. Compiled code calling a native builds the `args` Array (natives are the minority of calls). A second registration form, `r.method_n(obj, name, fn/2)`, takes fixed arguments with no array and is applied to the hottest DOM methods found by profile in milestone 8.
- A compatibility file, `blade/js/compat.w`, keeps the old names working during the port: `JsObject`, `JsArray`, `JsFunction`, `JS_NULL`, `js_call`, `js_arg`, `js_to_string`, `js_throw_type`, `js_new_capability` and the realm helpers, defined in terms of `JS:` classes. `JS:Object` keeps the method names the bindings use (`get`, `set`, `put_own`, `define`, `define_accessor`, `get_own`, `has_own?`, `own_keys`, `delete_own`, `get_own_property`, `define_own_property`, `call_obj`, `callable?`, `htmldda?`).
- `internal` and `cls` become real fields on a `JS:HostObject < JS:Object` subclass rather than on every object. The 276 `.internal` sites are on host objects already.
- Exotic host classes override the same methods as today and get the `JS:EXOTIC` shape automatically.
- DOM wrappers keep their identity map (`JsPageRuntime#wrap`). The map is a root while the page lives and is dropped at teardown.
- Blade's JS-source builtins (`web.js`) are compiled statically at Blade build time, removing a 75 KB compile per realm.

### 6.2 Script execution

- `js_run_script(src, name)` keeps its signature. Inside: hash → `.jsast` cache (Blade does not use one today) → analyze → look for a unit → run.
- Network waits are unaffected. `net_step` is not called from inside JS; it runs between tasks. What blocks inside JS is synchronous XHR and `src` script fetches, both outside this plan.
- Inline handlers, string timers and `javascript:` navigation go through the same entry and stay in tier 0 unless hot.

### 6.3 Workers, frames, realms

- Workers are OS threads with their own realm and per-thread engine state (`js/tls.w`). That stays. Native code is immutable and shared across threads; `JS:Code` descriptors, inline-cache tables and heaps are per realm. A worker loads the same unit file and gets its own tables. Today each worker re-parses; with the `.jsast` cache it does not.
- Units are requested from the main thread only; a worker posts its request through its existing channel.
- Frame realms: a second realm built with the same installers, sharing the parent's job queue. Inline caches are per (unit, realm), so two realms running one script do not thrash each other.
- The current realm stays a per-thread register. Entering a function whose realm differs switches it, which also fixes the present gap where it is only switched inside frame `eval`.

### 6.4 The AOT cache that is replaced

`aot.w` (1,890 lines), `~/Library/Caches/Blade/jsaot/` and the seven `BLADE_JS_AOT*` variables are removed in milestone 6. Replacements: `BLADE_JS_ENGINE=aot|tier0` (default `aot` after the exit criterion), `BLADE_JS_UNITS=0` (never load or request), `BLADE_JS_UNITS_SYNC=1` (wait for the unit; tests), `BLADE_JS_UNITS_DIR`, `BLADE_JS_UNITS_DEBUG=1`.

### 6.5 Dev panel and timeline

- `perftrace.w` reads `JsFunction.bound`, `.fname`, `.code.url`, `.code.src`, `.code.pos`, and calls `js_src_linecol`. These stay, on `JS:Function` and `JS:Code`.
- `timeline.w` calls `js_stack_lines()` and `js_top_location()` on every DOM mutation, and `Error.stack` needs the same data. Compiled code maintains the JS call stack as today's `js_exec` does: one store of the `JS:Code` per entry at the current depth. The position within the function costs one more store per call site, so it is emitted only in units built with `positions: true`. That flag is part of the unit key and is requested when the dev panel, recording or the timeline is on.
- New timeline events: unit requested, built (ms, functions), loaded, and collection (ms, freed, live).

### 6.6 Record and replay

Replay forces `--deterministic`, which seeds `Math.random`, pins the clock and the zone, and orders timers by due time and id.

- Tier 0 and tier 1 must be observably identical: property order, exception messages, stack contents at every recorded mutation. The differential suite (section 7, T4) enforces it.
- A unit arriving in the middle of a session is not deterministic in time, so in deterministic mode units are loaded only at script start, from cache, and no build is requested. The recording header stores the engine mode and `JS_ABI`.
- Collections follow allocation counts (section 5.2).

---

## 7. Milestones

Test assets used throughout:

- **T1** `tests/regress` (47 files with `// expect:` first lines) and `tests/gc` (stress under a 200 MB cap), run with `run.sh <runner>`.
- **T2** test262 at `~/src/test262`, through `tools/test262.py RUNNER ROOT OUT dirs…` (batches of 150, survives crashes).
- **T3** `bench/`: the six programs of Appendix A.1 plus string building, array methods, `for…of`, and a class-heavy one.
- **T4** differential: every T1/T2/T3 program run on tier 0 and tier 1 with outputs compared, and `apps/blade/test/js-corpus` (43 YouTube scripts, 12 MB) translated and compiled as a scale test.
- **T5** Blade pages: `test/frames`, `test/web`, `test/determinism`, and a recorded YouTube watch page replayed headless.

All probes and tests run with `TUNGSTEN_MEMORY_LIMIT=4.5G` and under `timeout`. No audible sound.

### M0. Baseline and harness (small)

- **Scope:** copy the front end into `languages/js-aot/frontend/` (lexer and parser from Blade's `lib/blade/js/`, which are newer than the js-frontend worktree's; `ast_codec.w` and `ast_cache.w` from `~/tungsten-worktrees/js-frontend`, updated for the lazy-body fields). Copy the current engine as `languages/js-aot/tier0/` unchanged and build `tools/jsrun.w`. Write `tools/memstat.sh` (peak RSS from `/usr/bin/time -l`, block-size histogram from `heap`). Record a YouTube watch-page session with `blade --record`.
- **Exit:** `BASELINE.md` holds T1 pass count, test262 pass rates per directory, T3 times and peak RSS, and the YouTube numbers of section 5.3, each reproducible within 5% on a second run.

### M1. Vertical slice (medium) — proves the benefit before the build-out

- **Scope:** `analyze.w` (bindings, capture, layout) for functions, closures, `var`/`let`/`const`. `translate/` for: functions and closures, calls, `new`, `this`, prototypes, object and array literals, property read/write with inline caches, numbers and strings, all operators, `if`/loops/`break`/`continue`, `try`/`catch`/`throw`, `typeof`. A minimal fresh `runtime/` in `in JS`: `Object`, `Shape`, `Array`, `Function`, `Code`, `Env`, the operators, `console.log`. `tools/jsc.w`: JS file → Tungsten AST → `compile()` → binary, as a static program.
- **Also, the loading spike:** repeat Appendix A.3 with a translated function instead of a hand-written one, and record the cost of a host → unit → host call round trip.
- **Function-value analysis, first part (section 3.9):** classes (a) and (c): IIFEs and call-only bindings as direct calls, no environment for capture-free functions, a single unchanging capture stored in `@env`. Class (d) objects are lean from the start (virtual `name`/`length`/`prototype`, no property storage).
- **Also, the scale check:** translate every function of `youtube-main.js` that the slice supports, lower it (no clang), and record functions per second, peak compiler RSS, and the histogram of unsupported constructs. Then clang 2,000 of them and record ms and bytes of code per function. Run `analyze` over the whole js-corpus and record how many functions fall in each class of section 3.9, how many scopes need no environment, and the own-property count histogram of object literals and constructors.
- **Tests:** T3 subset (closure, property, arithmetic), 30 hand-picked T1 files, a 500-test sample of test262 `language/expressions` and `language/statements` in static batches.
- **Exit, all required:**
  - closure benchmark ≥ 8× faster than tier 0, property ≥ 6×, arithmetic ≥ 30× (the hand translations reached 16×, 10×, 80×);
  - blocks per iteration meet section 5.3 for closure creation, calls, object literals, IIFEs and call-only functions; the closure benchmark allocates exactly one block per iteration (its one captured variable is never reassigned);
  - the spike calls a translated function inside a host and gets the right answer, with the three manual fixes listed as the C1 work items, confirmed or corrected;
  - the scale numbers are written into this file's Appendix A, and the section 1.6 estimates are replaced by them.
- **If an exit fails:** stop and report. The speed and block targets failing means the object model or call convention is wrong, and everything after depends on them.

### M2. Runtime port, tier 0 on the new runtime (large)

- **Scope:** port `value.w`, `realm.w`, `ops.w`, `b_*.w`, `regexp.w`, `module.w` into `runtime/` on the `JS:` object model, with no per-operation lambdas. Port `interp.w` and `runtime.w` into `tier0/` on top of it: `analyze.w` layouts (locals in the activation array, captured variables in `JS:Env`), `JS:Code` entries, the eight-argument convention at the boundary. Generators and async stay on goroutines here.
- **Tests:** T1 all; T2 full.
- **Memory items in this milestone** (sections 2.2 and 2.9): literal and constructor shapes, interned property names, `nil` for every empty container, one tier 0 compiler per script.
- **Exit:** T1 47/47. test262 pass rate per directory within 0.3 points of M0 (the runtime changed, the interpreter did not). Closure benchmark on tier 0 allocates ≤ 2 blocks per closure. An empty object, an empty array and a function each cost one block. One million objects built by the same constructor share one shape. T3 on tier 0 no slower than M0.

### M3. Translator coverage and collector G1 (large)

- **Scope:** the rest of the language in `translate/`: destructuring, spread, default and rest parameters, classes (fields, private names, `super`, derived constructors), template literals, tagged templates, optional chaining, `for…in`/`for…of` with iterator fast paths, labelled statements, `switch`, `finally`, getters and setters, `arguments` (unmapped), modules. The arithmetic lanes of section 3.2. `runtime/heap.w`: `JS:Heap` with per-class `js_trace`, task-boundary and depth-0 safepoints. Function-value analysis, second part (section 3.9): guarded builtin callbacks with inline loops, per-site callback objects, environment release at scope exit, lazy materialization at the point of escape, accessors without function objects, and the `JS_FNOBJ=always` switch.
- **Tests:** T2 in static batch mode (150 tests per binary, one realm per test); T4 differential on all of T1, T2, T3, each run with `JS_FNOBJ=always` and without; the adversarial function-identity tests of section 3.9; `tests/gc` with `BLADE_JS_GC_VERIFY`-style checking and with a collection every 50 allocations.
- **Exit:** tier 1 test262 pass rate within 0.5 points of tier 0 in every directory except generators/async, with zero differential mismatches that are not filed as known, and none between the two `JS_FNOBJ` modes. ≥ 97% of functions in the js-corpus translate (the rest are `eval`/`with`/mapped-arguments). `tests/gc` passes under 200 MB. The three loop benchmarks meet the steady-state memory target. The callback rows of section 5.3 are met. A loop that throws through a released scope 1 M times grows by less than 100 MB, or those records are registered instead.

### M4. Async (medium)

- **Scope:** C2 and C3 in core and the compiler, with their specs. `JS:Promise`, `JS:Reaction`, `JS:Generator`, `JS:AsyncGenerator` on them. Translator support for `function*`, `async`, `await`, `for await`, `yield*`. Tier 0 switches from goroutines to the same `Coroutine` by lowering through the same pass on its own activation records, or, if that proves awkward, keeps goroutines for tier 0 only (functions with `yield`/`await` are then always compiled first). Remove the pin lists from the collector.
- **Tests:** core specs on both engines; test262 `built-ins/Promise`, `language/statements/async-*`, `generators`, `for-await-of`; T1 `promise_combinators.js`.
- **Exit:** stage-identity line unchanged. Promise and generator directories within 0.5 points of M0. `yield` ≤ 50 ns and 0 blocks; `await` ≤ 300 bytes; 100,000 live suspended generators fit in 64 MB (today the engine refuses past 9,000).

### M5. Units, service, cache, tier mixing (large)

- **Scope:** C1 and C5. `service/` (`tungsten-jsc`). Host side in `runtime/units.w`: request, poll, load, patch entries, per-realm cache tables, manifest check. Mixed execution: tier 0 calling native entries and the reverse, closures created by one tier over environments created by the other. `jsrun --units` mode.
- **Tests:** T4 in three modes: all tier 0, all tier 1, and **alternating** (functions with even pre-order index compiled, odd interpreted, then swapped), which exercises every cross-tier boundary. Cache tests: hit, miss, stale `JS_ABI`, truncated file, concurrent writers. `scripts/test-build-store.sh` extended.
- **Exit:** alternating mode has zero mismatches on T1, T3 and the test262 sample. A unit for 2,000 functions loads in ≤ 20 ms with no IR work. Warm start of the js-corpus scripts in `jsrun` executes ≥ 95% of calls natively.

### M6. Blade (large)

- **Scope:** sync `languages/js-aot` into `apps/blade/lib/blade/js/` (Blade takes copies; update `tools/sync_runtime.sh`). `compat.w`. Port the bindings file by file, exotic classes first. `JobQueue` in `drain`. Timeline and perftrace hooks. Deterministic-mode rules. Root removal at page teardown. Static compile of `web.js`. Delete `aot.w` and the old cache.
- **Tests:** T5 with `BLADE_JS_ECHO=1`; the determinism test; replay of the recorded YouTube session with identical timeline output in `tier0` and `aot` modes; the acceptance pages (google.com renders, YouTube plays a video).
- **Exit:** every T5 page behaves the same under `BLADE_JS_ENGINE=tier0` and `aot`. YouTube plays with a warm cache. Replay is byte-identical across two runs. Then the default flips to `aot`.

### M7. Memory on real pages: collector G2 (medium)

- **Scope:** C4. Conservative stack roots, polling at back-edges and entries in units. Collection events in the dev panel. Measure what the remaining live blocks on YouTube are, by caller.
- **Tests:** `tests/gc` variants that allocate inside nested calls and never return to the loop; a 10-minute YouTube soak.
- **Exit:** the YouTube targets of section 5.3 for a warm cache. No growth in live blocks over the last 5 minutes of the soak beyond 5%. If unregistered blocks are more than 30% of what is live, write up G3 with the measured breakdown instead of building it.

### M8. Speed (medium, open-ended; stop when the target is met)

- **Scope, in order of expected gain, each kept only if it measures:** direct calls and inlining for statically bound callees; fixed-argument natives for the hottest DOM methods; layout-bound units (section 1.4); typed-array element access; `for…of` over arrays without iterator objects; outlined `try` bodies.
- **Exit:** JS execution time on the replayed YouTube load ≤ a quarter of M0's. Each T3 benchmark within 1.5× of its hand translation.

### M9. Tier 0's future (decision, then small or large)

- **Measure:** on a cold-cache YouTube load, the bytes held by tier 0's closure trees and the time spent building them.
- **Decide:** if they exceed 25% of live blocks, replace tier 0's closure compiler with a tree walker over JsNode that resolves bindings into node side slots and allocates nothing per node (about 3,000 lines, validated by T4 against tier 1). If not, keep the ported interpreter and close the project.

### Risks, and where each is retired

| # | Risk | Retired by |
|---|---|---|
| R1 | A unit cannot share the host's heap and runtime cleanly | Appendix A.3 already shows it can. M1 spike repeats it with real output; M5 makes it a compiler mode. |
| R2 | Compile time or compiler memory does not scale to 47,000 functions | M1 scale check, before any build-out. Mitigation built in: per-function fallback means a unit never needs the whole script; sharding at 2,000 functions. |
| R3 | The compiler mishandles machine-generated dynamic code. Known examples in `languages/javascript/runtime/repros/`: a function returning its untyped argument on one path and a Float on another is inferred as numeric; a lambda assigned inside `if` is lost; `super` with a default parameter | M1's 500-test sample runs generated code early. Each bug is fixed in the compiler with a spec, not worked around in the translator. `tools/dump_w.w` produces the reproduction. |
| R4 | Native code size (the probe's object file averaged about 1.1 KB per core function; inline caches add more, and 47,000 functions at 3 KB would be 140 MB) | M1 records bytes per function; target median ≤ 1.5 KB. Slow paths are calls, never inline. |
| R5 | Collector frees a live object | G1 is precise by construction. A verify mode that poisons instead of freeing runs in CI for M3 and M7. G2 is never enabled under a native frame. |
| R6 | The two tiers drift apart | One runtime, one analyzer, and the alternating differential mode from M5 on. |
| R7 | `setjmp` per `try`, and no automatic frees in functions that contain one | Measured in M3; outlining is the fix. |
| R8 | The resumable transform is wrong for some combination of loops, `try` and `finally` | Its own spec suite on both engines, then several thousand test262 generator and async tests in M4. |
| R9 | The binding port is larger than the shim hides (30 exotic classes) | M6 ports exotic classes first; M2 freezes the internal-method names before then. |
| R10 | Replay stops being deterministic | Section 6.6 rules; byte-identical replay is an M6 exit criterion. |
| R11 | The in-memory loader is refused in a signed, hardened Blade.app (it maps executable memory) | M5 tests inside the app bundle; `dlopen` of an ad-hoc signed dylib is the fallback, at about 120 ms per unit. |
| R12 | Other agents change the engine in Blade while this is built | M0 pins the copied revision; M6 starts by re-syncing and re-running T1/T2 on tier 0. |
| R13 | The function-value analysis is wrong somewhere, and a script observes a missing or duplicated function object | The rules of section 3.9 only ever skip an object when no value use exists. Every site keeps the generic fallback. `JS_FNOBJ=always` disables it, and the differential suite compares both modes from M3 on. |
| R14 | The analysis helps less than hoped on real pages, because most functions there are stored in properties | M1 counts the js-corpus by class before the second part is built. Class (d) is already 6× smaller and one block, so the floor is known. |

---

## 8. Work breakdown

In order. Sizes: S ≤ 300 lines, M ≤ 1,000, L ≤ 3,000, XL more. Work only in this worktree; never edit `~/tungsten`. Run focused specs only (AGENTS.md).

| # | Item | Where | Size | Milestone |
|---|---|---|---|---|
| 1 | Copy front end and current engine; `jsrun`; `memstat.sh`; `BASELINE.md` | `frontend/`, `tier0/`, `tools/` | S (new code) | M0 |
| 2 | `analyze.w`: bindings, capture analysis, env layout, dynamic-scope marking, statically bound functions, function-value uses and classes (a)/(c), single-capture detection; corpus statistics tool | `analyze.w`, `tools/fnstats.w` | M | M1 |
| 3 | AST builder helpers over `Tungsten:AST:*` (calls, guards, loops, locals, positions) and `tools/dump_w.w` | `translate/build.w` | S | M1 |
| 4 | Minimal runtime in `in JS`: Object, Shape, inline caches, Array, Function, Code, Env, operators, call trampolines (`ll`) | `runtime/` | M | M1 |
| 5 | Translator slice: expressions, statements, functions, closures, `try` | `translate/` | L | M1 |
| 6 | `tools/jsc.w` static pipeline; bench runner; loading spike; scale check | `tools/` | S | M1 |
| 6a | Shapes for literals and constructors, pre-sizing, dictionary fallback; `JS:Names` interning; `nil` empties | `runtime/shape.w`, `runtime/names.w` | M | M2 |
| 7 | Port the builtins onto `JS:` classes (object, array, string, number, json, collections, date, reflect/proxy, typed arrays, regexp, console) | `runtime/b_*.w` | XL (about 9,000 lines moved and adapted) | M2 |
| 8 | Port tier 0 to the shared layout, `JS:Code` entries and the new call convention | `tier0/` | L | M2 |
| 9 | test262 static batch driver for tier 1; differential runner | `tools/` | M | M3 |
| 10 | Translator: destructuring, spread, classes, templates, iteration, labels, `switch`, `finally`, accessors, modules | `translate/` | XL | M3 |
| 11 | Arithmetic lanes and type facts in `analyze.w` | `analyze.w`, `translate/` | M | M3 |
| 11a | Function values, second part: builtin-callback guards and inline loops, per-site callback objects, scope release, lazy materialization, accessor pairs, `JS_FNOBJ=always`, adversarial tests | `analyze.w`, `translate/func.w`, `runtime/array_iter.w`, `tests/fnobj/` | L | M3 |
| 12 | `JS:Heap` G1 with per-class tracing and verify mode | `runtime/heap.w` | M | M3 |
| 13 | C3: `JobQueue`, `Future#then` family, scheduler hook, specs | `core/`, `runtime/`, `spec/core/` | M | M4 |
| 14 | C2: `Suspend`, `resumable_lower`, `Coroutine`, specs | `compiler/lib/`, `core/`, `spec/` | L | M4 |
| 15 | `JS:Promise`, reactions, generators, async functions and generators; translator support; tier 0 off goroutines | `runtime/`, `translate/`, `tier0/` | L | M4 |
| 16 | C1 unit mode and C5 loader handle, with a spec and `scripts/test-unit-load.sh` | `compiler/lib/driver/unit.w`, `runtime/runtime.c` | L | M5 |
| 17 | `tungsten-jsc` service, store layout, manifest, store tests | `service/`, `scripts/` | M | M5 |
| 18 | Host unit manager: request, load, patch, per-realm tables; alternating mode | `runtime/units.w` | M | M5 |
| 19 | Sync into Blade; `compat.w`; port bindings (exotic classes first) | `apps/blade/lib/blade/` | XL (15,000 lines touched, mostly mechanical) | M6 |
| 20 | Blade loop, timeline, perftrace, determinism, teardown roots, static `web.js`; delete `aot.w` | `apps/blade/lib/blade/` | M | M6 |
| 21 | C4 and collector G2; soak test; block-source report | `runtime/stack_scan.c`, `runtime/heap.w` | M | M7 |
| 22 | Speed items of M8, one at a time with before/after numbers | various | M each | M8 |
| 23 | Tier 0 measurement and decision; tree walker if chosen | `tier0/` | S or L | M9 |

Layout when done:

```text
languages/js-aot/
  PLAN.md  BASELINE.md
  frontend/    lexer.w parser.w ast_codec.w ast_cache.w
  analyze.w
  translate/   build.w expr.w stmt.w func.w class.w pattern.w resumable_js.w
  runtime/     (in JS) object.w shape.w array.w string.w number.w function.w env.w ops.w
               promise.w heap.w units.w realm.w b_*.w regexp.w module.w
  tier0/       interp.w runtime.w
  service/     jsc.w
  tools/       jsrun.w jsc.w dump_w.w test262.w test262.py differential.sh memstat.sh
  bench/  tests/regress/  tests/gc/
```

---

## Appendix A. Measurements made for this plan

Machine: Apple Silicon, loaded (other builds running). Tungsten at fd1eaa9b, `--release` builds. Probe sources were throwaway and are not in the repository; the shapes are described so they can be rewritten.

### A.1 Closure interpreter baseline (`blade --js file.js`) against hand translation

| Program | What it does | Tier 0 CPU | Tier 0 peak RSS | Hand-translated CPU | Hand-translated peak RSS |
|---|---|---|---|---|---|
| closure | 1 M × `mk(i)` returning `function(x){return x+i}`, then a call | 1.00 s | 713 MB | 0.06 s | 84 MB |
| property | 1 M × `new P(i,1)` and a prototype method reading two fields | 1.54 s | 359 MB | 0.15 s | 180 MB |
| arithmetic | `fib(27)` plus 3 M iterations of `h = (h*31+i)\|0` | 1.64 s | 37 MB | 0.02 s | 3 MB |
| generator | 200,000 `yield`s consumed by `for…of` | 0.13 s | 111 MB | — | — |
| async | 100,000 `await`s of an async call | 0.18 s | 369 MB | — | — |
| many generators | 2,000 generators suspended at once | 0.15 s | 75 MB | — | — |

The hand translations had no collector, so their remaining memory is the escaping objects themselves: 80 bytes per iteration for the closure case, 180 for the property case (which used a separate slots array; inline slots halve it).

The hand-translated closure case, which is the shape tier 1 emits:

```tungsten
-> mk_inner(env, this, x)
  js_add(x, env[0])            # js_add: Float + Float inline, else the slow path
-> mk(this, i)
  env = [i]
  JsFn.new(mk_inner/3, env)    # one object: code reference + environment
```

The property case used shapes and per-site caches exactly as in section 2.2.

### A.2 Compiler throughput (synthetic: N functions of 13 lines each)

| | 1,000 functions | 5,000 functions |
|---|---|---|
| Parse + lower (`-c`), CPU | 0.26 s | 0.52 s |
| Peak compiler RSS (`-c`) | 270 MB | not recorded |
| Full build `-o` (clang -O3), CPU | 4.7 s | 10.4 s |
| LLVM IR lines | 207,000 | not recorded |

Wall times were 5–20 s longer than CPU in every run. A sample of the compiler showed the time in `popen` reads under `detect_target`, `host_c_compiler` and `target_homebrew_formula_prefix`. That fixed cost is per compiler process, which is one reason for a long-lived service.

### A.3 Loading a separately compiled unit into a host

- Unit: one function taking `(box, n, helper)` that reads and writes `box.v` (a host class's accessor), loops on floats, builds an Array and a Hash, concatenates strings, calls `helper` (a host closure), and raises and rescues.
- Built with `tungsten --ll unit.w`, then `clang -O2 -dynamiclib -undefined dynamic_lookup`.
- Host: defines the class, `w_dlopen`s the unit, finds the entry with `w_dlsym`, and calls it through an `ll` trampoline with `wvalue_bits` arguments.
- Result: correct output (`[20, boom, 200]`, and the host object's field updated).
- Manual fixes needed, which define C1:
  1. the entry was `define internal`; made external by editing the IR;
  2. `dlopen` failed on two core BigInt symbols the host had stripped; stubbed;
  3. the unit carried its own `main` and 804 functions of core (106,000 lines of IR, 785 KB).
- `w_jit_load_object` returned nil for this object; not investigated. C5 covers it.

### A.4 Core behaviour checked for the JS mapping

`0/0` is NaN; `NaN == NaN` is false; `-0 == 0` is true; `1/-0` is -inf; `-5.5 % 2` is -1.5 (truncating); `Float#to_s` gives `1e+21` and `9.9999999999999995e-08` (not JS formatting); `(~4294967301.7).to_i` is 4294967301 (no wrap); a Hash keeps one NaN key and treats `~1.0` and `1` as different keys, in insertion order; `"héllo".size` is 6 (bytes); `2147483647 * 2147483647 * 4` on untyped literals wraps in i64.

### A.5 Corpus

`apps/blade/test/js-corpus`: 43 files, 12 MB. `youtube-main.js` is 10.9 MB with 47,407 `function` keywords and 9 arrows.

## Appendix B. Implementation measurements

Machine as in Appendix A (Apple M5, other work running). Tier 0 is `tools/jsrun.w` (the closure
interpreter, BLADE_JS_AOT=0); tier 1 is `tools/jsc.sh --release`. Times are the script's own
(`JSRUN_TIME=1`), best of 3 (tier 0) or 5 (tier 1).

### B.1 Milestone 1 exit

| Benchmark | Tier 0 | Tier 1 | Ratio | Target | Live blocks per iteration (tier 1) |
|---|---|---|---|---|---|
| closure (1 M closures + calls) | 992 ms | 39 ms | 25× | ≥ 8× | 1 (80-byte block: the function object; its one captured variable is its @env) |
| property (1 M `new P` + method) | 1,452 ms | 94 ms | 15× | ≥ 6× | 1 (the object, 80 bytes) |
| arithmetic (fib(27) + 3 M `(h*31+i)\|0`) | 1,621 ms | 49 ms | 33× | ≥ 30× | 0 |

- For reference, fib(27) plus the loop takes V8 13.5 ms, JavaScriptCore 14.5–16.7 ms, the planner's
  hand translation about 20 ms. Split: fib(27) alone is 4 ms in tier 1 (a guarded direct call to the
  callee's entry; 227 ms in tier 0); the 3 M-iteration loop over globals is 45 ms (over function
  locals 39 ms). The loop's cost is the boxed double arithmetic and ToInt32 on every iteration:
  the int32 lane of section 3.2 (M3) is what brings it to V8's level.
- Blocks per operation (tests/blocks/, `memstat.sh --heap`, live malloc blocks after the run):
  IIFE and call-only local functions 0 per call; calls with ≤ 4 arguments 0; object literal
  `{a, b, c}` 1 block (80 bytes); closure creation 1 block. (A call to a native builtin still
  allocates its arguments Array, 2 blocks: fixed-argument natives are M8.)
- Peak RSS: closure 80 MB (tier 0: 482 MB), property 80 MB (314 MB), arithmetic 3 MB (7 MB), with
  no collector.

Loading spike (A.3 repeated with translated code): `function f(o, cb){ return cb(o.x + 1) * 2 }`
translated by jsc, its entry extracted into a 50 KB dylib, loaded into a host built from the same
runtime, called through an `ll` trampoline with a host object and a host native: correct result
(43). A host → unit → host round trip that does a property inline-cache read through the host
runtime, a call of a host native, an add and a multiply costs 33 ns. The three C1 items, confirmed
or corrected:

1. Exported entries: confirmed (the entry must be `define`, with a stable exported name).
2. No `main`, no second copy of core: confirmed — the unit contains only translated functions.
   Corrected: binding to the host by symbol name does not work, because Tungsten symbols are
   content hashes and whole-program inference specializes the host's own copies (parameter
   representations included). The unit is *runtime-bound through a table*: `jsu_init(table)` receives
   the addresses of the host runtime entries it calls (taken in the host with `ptrtoint` of the
   `w:<name>` aliases), and those host entries must keep the generic boxed ABI (they are external
   entry points: no parameter specialization).
3. Keep-list: confirmed — the host dead-strips runtime functions its own code does not reference;
   building the table references them. With sharded codegen the alias must be visible across
   shards (the spike used `TUNGSTEN_SHARD_CODEGEN=0`).
4. New: typed-array parameters arrive in `ll` bodies as raw element pointers; strings longer than
   five bytes are slab-interned per module, so a unit needs its own string table (or strings
   interned through the host at init).

Scale check on `youtube-main.js` (10.9 MB, 47,134 functions):

| | |
|---|---|
| Functions the slice translates | 44,535 (94.5%) |
| Not yet (first reason) | `arguments` 1,303, `finally` 848, regex literal 234, `for…in` 181, named function expression as a value 26, accessor in a literal 8 |
| Lowering, 2,000 functions | 0.44 s over an empty program (0.22 ms per function, ~4,500 per second) |
| Compiler memory | 1.0 GB at 2,000 functions, 1.8 GB at 5,000 (≈ 270 KB per function); all 44,535 in one compile exceeded 16 GB |
| clang, 2,000 functions | +2.7 s wall (sharded), ≈ 2.7 ms CPU per function |
| Code size | +1.69 MB text for 2,000 functions: 844 bytes per function (R4 target median ≤ 1.5 KB) |

Analysis over the whole js-corpus (43 files, 12 MB, 48,724 functions, `tools/fnstats.w`):

| Class (section 3.9) | Functions |
|---|---|
| call-only (local declarations only called) | 715 |
| IIFE | 233 |
| escaping (lean object) | 47,776 (98%) |
| no captured variables (no environment, class c) | 12,626 (26%) |
| exactly one captured, unchanging variable (stored in @env) | 7,944 (16%) |
| using direct eval or `with` | 0 |

Function scopes needing no environment record: 43,350 of 48,767 (89%). Object literal property
counts: 0: 3,600, 1: 14,476, 2: 9,772, 3: 3,894, 4: 1,154, 5: 558, 6: 366, 7–16: ~770, more: 227
(six inline slots cover 96%). Constructors' distinct `this.x =` names: 1: 2,406, 2: 740, 3: 334,
4: 199, 5: 94, 6: 86, more: ~207 (six cover 95%). As R14 expected, almost every function value
escapes (Closure Compiler output stores functions in properties); the lean one-block object is
the floor there. `var h = function(){}` locals that are only called are not yet classed call-only
(the analysis must first prove no call precedes the assignment): M3.
