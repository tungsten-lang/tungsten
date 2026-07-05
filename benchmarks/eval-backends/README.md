# REPL eval backends: interpreter vs JIT vs hot-swap

Tungsten's `wit` REPL can evaluate a line three ways. This benchmark measures the
performance tradeoffs of each.

| Flag     | Backend                | How a line runs                                                    |
|----------|------------------------|-------------------------------------------------------------------|
| `--wit`  | **Interpreter**        | tree-walk the AST every time (`Interpreter#run`)                   |
| `--jit`  | **JIT**                | compile the line to a native object, load it **in-memory** + call |
| `--hot`  | **Hot-reload**         | accumulate definitions; compile the whole live program + call it  |

All three share the same front end (lexer/parser) and the same self-hosted
compiler. The JIT and hot paths reuse the in-process `emit_ir`, then `clang -c`
to a relocatable object, then **`w_jit_load_object`** — a small Mach-O loader
that maps the object into executable memory, applies its relocations, and resolves
the snippet's `jit_line` against `__w_fn_meta` (`compiler/lib/repl.w#compile_and_call`,
`runtime/runtime.c#w_jit_load_object`). No `dlopen`. On any unsupported relocation
or non-macOS platform it transparently falls back to the old `clang -dynamiclib`
+ `dlopen`/`w_dlfind_fn`/`w_dlcall` path, so the fast path is purely an
optimization.

## Measured numbers (M5 Max, macOS)

Kernel: sum `1..5_000_000` in a `while` loop (`kernel.w`), result `12500002500000`.

| Path                          | Time      | vs interpreter |
|-------------------------------|-----------|----------------|
| Interpreter (tree-walk)       | 16,063 ms | 1×             |
| Native, total (incl. startup) | 449 ms    | 36× faster     |
| Native, compute only          | ~172 ms   | **~93× faster**|

## Per-command latency in the REPL (and where it goes)

Evaluating one line under `--jit`/`--hot` used to have a ~170 ms lag that `--wit`
doesn't. The **in-memory Mach-O loader** (`w_jit_load_object`) removed the
dominant chunk of it. Measured per command (M5 Max, instrumented):

| Step                 | Old (`dlopen`) | Now (in-memory) | Notes                                       |
|----------------------|----------------|-----------------|---------------------------------------------|
| `emit_ir`            | ~45 ms         | ~45 ms          | in-process compile (no process spawn)       |
| `clang`              | ~33 ms (`-dynamiclib`) | ~14 ms (`-c`) | shell-out; `-c` skips the link             |
| load + call          | **~120 ms** (`dlopen`) | **~3 ms** (`w_jit_load_object`) | the eliminated dyld floor    |
| **total eval lag**   | **~170 ms**    | **~59 ms**      | **~2.9× faster**; vs ~0 ms for `--wit`      |

The cost we removed was **`dlopen`, and it was a macOS dyld floor**, not our
design: a trivial C dylib (`long f(){return 1;}`, zero undefined symbols) takes
~120 ms to `dlopen`, and *distinct* such dylibs each take ~120 ms. It's the dyld
closure build — an *unsigned* dylib still spends ~115 ms before dyld rejects it,
so the cost precedes and is independent of code-signature validation.

### The in-memory Mach-O loader (`w_jit_load_object`)
Instead of `clang -dynamiclib` + `dlopen`, we `clang -c` the snippet to a
relocatable Mach-O object and load it ourselves, bypassing dyld entirely:

1. **Two `mmap` regions, not one** — Apple Silicon enforces W^X, and real
   snippets have *writable* data: a method call's inline cache (`_.ic`) lives in
   `__DATA,__bss` and `w_method_call_cached` **writes** it on a miss. So
   executable sections (`__text`) go in a region we'll make R-X; everything else
   (`__const`, `__cstring`, `__bss`, `__w_fn_meta`) goes in an R-W region. A
   per-section base map lets relocations resolve across the split.
2. **Apply relocations** — every arm64 kind a snippet emits:
   - `BRANCH26` — `BL` calls to runtime fns, routed through a 16-byte far-call
     stub (`ldr x16,[pc,#8]; br x16; .quad target`) since the host runtime is
     usually >128 MB past `BL`'s reach;
   - `UNSIGNED` — 64-bit absolute pointers (`__w_fn_meta`, vtables);
   - `PAGE21` / `PAGEOFF12` — the `ADRP`+`ADD`/`LDR` pair that materializes the
     address of a constant or an inline cache (the `LDR`/`STR` low-12 offset is
     size-scaled);
   - `ADDEND` — a pair entry supplying a `symbol+offset` addend for its neighbor.

   Undefined symbols (`w_int`, …) resolve via `dlsym(RTLD_DEFAULT, …)` against the
   `-export_dynamic` host.
3. **`mprotect`** the *code* region R-X and flush the i-cache; the data region
   stays R-W so inline caches can update.
4. **Scan `__w_fn_meta`** for `jit_line` and return its address; the caller invokes
   it via `w_dlcall`.

The load is ~3 ms. It produces byte-identical results to the `dlopen` path across
the full expression set (verified by diffing both loaders), and anything it can't
handle (a GOT/TLV reloc, a non-macOS platform) returns nil and falls back to
`dlopen` — correctness is never at risk. The `-export_dynamic` link (below) is what
lets the loaded snippet resolve `w_int`/etc. from the already-running host.

> **Known limitation (pre-existing, both loaders):** a snippet that *interns a
> string* (a string literal, most string methods) bakes **slab offsets** into its
> constants and registers its own static slab via `w_slab_init_static` — but the
> host's slab is already initialized, so that call no-ops and the snippet's offsets
> resolve against the *host's* slab, yielding the wrong string. This is independent
> of the loader (the `dlopen` path mis-resolves identically) and is the next thing
> to fix for a fully-correct REPL JIT; numeric/array/method-dispatch snippets are
> correct today.

### The `-export_dynamic` link optimization
The compiler binary is linked `-export_dynamic`, keeping its runtime symbols
(`w_int`, `w_add`, …) in the dynamic symbol table. Snippet dylibs therefore link
**nothing** (no `runtime.a`) — `clang … -dynamiclib -undefined dynamic_lookup` —
and resolve those symbols from the already-loaded host at `dlopen`. That cut the
per-line link ~15× (relinking the 1.4 MB `runtime.a` was ~1,457 ms). Bonus: snippets
call the *host's* runtime, so results allocate in the *host's* heap and
string/object results work too (not just numbers).

### Eliminating the ~120 ms dyld floor — done
- **In-memory Mach-O loader (shipped)** — `w_jit_load_object` loads the snippet
  object without dyld, cutting the ~120 ms `dlopen` floor to ~3 ms and `clang`
  from ~33 ms (`-dynamiclib`) to ~14 ms (`-c`). Net: ~170 → ~59 ms/line. It needs
  **no new dependency** (a few hundred lines of arm64 relocation handling in the
  runtime), unlike the LLVM-ORC alternative. See above for how it works.
- **What's left at ~59 ms is `emit_ir` (~45 ms) + `clang -c` (~14 ms).** The next
  lever is the compile, not the load:
  - **In-process codegen (LLVM ORC / MCJIT)** would also drop `clang -c`, leaving
    ~45 ms — but at the cost of linking LLVM into the binary (large). With the
    dyld floor already gone, the marginal win (~14 ms) no longer justifies it.
  - **A warm/cached front end** could shave the ~45 ms `emit_ir` for repeated
    shapes.
- **Linux is even faster still** — its `dlopen` had no closure/codesign overhead
  to begin with, and the in-memory loader (ELF variant) would apply there too.

## The tradeoff

- **Interpreter** — zero compile cost, ~93× slower execution. **Wins for
  run-once trivial lines** (`6 * 7` is instant; paying ~1.5 s to compile it would
  be absurd) and for fast dev iteration.
- **JIT** — pays ~59 ms latency *per line* (the in-memory loader removed the
  ~120 ms dyld floor; see above), then runs native. **Wins for any computation the
  interpreter would spend more than ~59 ms on**: the 16 s interpreter loop
  becomes ~0.06 s latency + ~0.17 s run ≈ 0.23 s, **~70× faster** than the
  interpreter *including* the compile. The crossover dropped with the floor — the
  remaining ~59 ms is the compile (`emit_ir` + `clang -c`), not the load.
- **Hot-reload** — same native execution as JIT, plus **persistent definitions
  and hot code reload**: define a function once, keep calling it; redefine it and
  the next call swaps to the new version. Best for **building up a program** in
  the REPL and for **repeated calls** to the same definitions, where the
  definition cost amortizes.

In short: the interpreter trades execution speed for zero latency; the compiled
backends trade a fixed compile latency for ~90× faster execution. JIT is the
stateless "compile this line" mode; hot-reload adds the accumulating, swappable
program state that makes the compile cost worth paying repeatedly.

## Reproduce

```bash
bin/tungsten build              # ensures /tmp/tungsten-runtime.a exists
bash benchmarks/eval-backends/measure.sh
```
