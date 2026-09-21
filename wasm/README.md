# Tungsten on WebAssembly (wasm32-wasi)

The self-hosted tree-walking interpreter (`compiler/lib/interpreter/`, i.e.
`tungsten run --interpret`) compiled to a WASI "command" module, plus a
dependency-free WASI host that runs it in Cloudflare Workers, browsers, Node
and Bun. One request = one fresh `WebAssembly.Instance` = one program.

| file | what |
| --- | --- |
| `tungsten.wasm` | the interpreter. Imports only `wasi_snapshot_preview1`; exports `_start`, `memory` |
| `tungsten.fs` | one binary bundle of every file it reads at run time |
| `wasi_shim.js` | ES module: `run(module, options)` + `loadBundle(buffer)` |
| `pack_fs.py` | builds `tungsten.fs` |
| `repl_entry.w` | the wasm program's entry (a thin `run --interpret`) |
| `wasi_stubs.c`, `compat/` | everything WASI lacks, as inert stubs / shim headers |
| `build.sh`, `scripts/` | reproducible build |
| `test.mjs` | suite + timings + native comparison |

## Host contract (what a Worker has to do)

```js
import wasm from "./tungsten.wasm";            // Workers: a WebAssembly.Module
import fsBytes from "./tungsten.fs";            // Workers: an ArrayBuffer (Data rule)
import { run, loadBundle } from "./wasi_shim.js";

const bundle = loadBundle(fsBytes);             // module scope: once per isolate

const { stdout, stderr, exitCode, truncated } = run(wasm, {
  args: ["tungsten", "/work/main.w"],           // argv[1] = program path; "-" = stdin
  files: [new Map([["/work/main.w", source]]), bundle],   // earlier layers win
  maxOutputBytes: 64 * 1024,                    // stdout+stderr cap (default 1 MiB)
});
```

* **argv**: `tungsten [path|-] [script args…]`. `path` defaults to
  `/work/main.w`. `-` reads the program from stdin (the shim exposes `stdin`
  as the file `/dev/stdin`, which is what the entry opens). Script args become
  the program's `argv()`.
* **cwd / files**: the guest's root is the repo layout: it opens
  `/core/**/*.w`, `/languages/tungsten/tungsten.lex64` and
  `/data/unit_names.txt` (all in `tungsten.fs`), plus the program itself.
  Relative paths resolve against `/`.
* **env**: none needed. The entry sets `TUNGSTEN_TARGET=wasm32-wasip1` itself.
* **exit codes**: `0` ok · `1` Tungsten runtime/compile error (readable message
  on stderr) · `2` program file unreadable · `124` aborted by the shim
  (`maxOutputBytes` / `timeoutMs`; `truncated` is set) · `134` wasm trap
  (stack overflow, `unreachable`), message appended to stderr.
* `run` is synchronous and never throws for guest failures.
* Wrangler: add rules `{ type: "CompiledWasm", globs: ["**/*.wasm"] }` and
  `{ type: "Data", globs: ["**/*.fs"] }`.

## How it is built

```
repl_entry.w ──host compiler, --target=wasm32-wasip1──▶ repl_entry.ll ─clang─▶ .o ┐
runtime/*.c + wasi_stubs.c ──clang --target=wasm32-wasip1 (wasi-sdk sysroot)──▶ .o ┼▶ wasm-ld (LTO) ▶ wasm-opt ▶ strip
```

`wasm/build.sh` does all of it (≈3–15 min, dominated by one native `-O3`
build of the compiler). Toolchain: Homebrew LLVM 23 `clang`, `wasm-ld`
(brew `lld`), the **wasi-sdk 34 sysroot + compiler-rt** (downloaded into
`wasm/toolchain/`; zig's bundled clang is older than the IR the compiler
emits and zig ships no `libsetjmp`), optional `wasm-opt`
(`npm --prefix wasm/toolchain install binaryen`).

This is the *clean* route, not an IR sed-rewrite: the compiler's existing
`--target=<triple>` cross path is used, with the five small fixes below.

## Porting decisions

### Compiler / core changes (native codegen verified byte-identical where noted)

1. **`compiler/lib/target.w` — `detect_target` follows `TUNGSTEN_TARGET`.**
   It used to report the *host* os/arch even under `--target`, so `on arm64`
   guards matched and AArch64 `asm` kernels were emitted into wasm IR. New
   `target_from_triple`. The wasm entry sets the same variable at startup so
   interpreted `on …` guards resolve without spawning `uname`.
2. **`core/numeric/big_int.w` — 49 `__bigint_*_raw` wrappers moved under the
   `on macos && arm64` guard of the kernels they call**, and the mis-indented,
   unguarded asm fn `__bigint_mod_42_exact` put back under its guard. Before
   this, *any* non-macOS-arm64 target failed to lower once `BigInt` was
   autoloaded (`unknown function '__bigint_div_42_exact'` — reproducible with
   `--target=x86_64-unknown-linux-gnu`). All call sites were already guarded.
   Native IR of the entry: byte-identical before/after
   (`scripts/emit_native_ir.sh`). Audit tools: `scripts/guard_audit.py`,
   `guard_callsites.py`, `guard_fix.py`.
3. **`compiler/lib/lowering.w` — the BigInt source-seam gate only demands the
   arm64-kernel-backed seams on macOS/arm64.** Other targets bind the
   runtime's exact-C weak defaults (the portable C bignum).
4. **`compiler/tungsten_driver.w` — `TUNGSTEN_TARGET_MARCH_ARGS`**: feature
   flags for a cross target (`-mexception-handling`), stamped on emitted
   functions exactly like the runtime's C objects.
5. **`compiler/lib/emitter/artifact.w` — `__main_argc_argv` wrapper on wasm**
   (clang mangles a 2-arg C `main` to that name; wasi-libc's crt1 calls it).
6. **Typed `ccall`s to narrow constructors** (`emitter/primitives.w`
   `narrow_runtime_param_types`, `runtime_instructions.w`, `instructions.w`):
   `w_duration_months_ms`, `w_ipv4`, `w_date`, `w_color`, … are *declared*
   `(i32, …)` but the interpreter reaches them through plain `ccall`, which
   passes i64 words. Natively the wider register is silently truncated; on
   wasm LLVM links a `…_bitcast_invalid` stub that **traps**. The emitter now
   truncates explicitly, from one table that also renders the declarations.
7. **`runtime/runtime.c/.h`** — `w_duration_months_ms`, `w_ipv4`, `w_color`
   take `int32_t` words (they were `int16_t`/`uint8_t`, a different *IR* type
   from the declaration → the same trap under LTO); `W_SLAB_MAX_SLOTS` is
   overridable; the `sizeof(WArray)` assert is pointer-width aware
   (`16 + sizeof(void*)`). Every *offset* assert in the static-assert wall
   already holds on ILP32, so IR-baked layouts are unchanged.

wasm32 (not wasm64) works because WValues are NaN-boxed 64-bit words holding
48-bit pointers and the IR/runtime boundary passes `i64`/`ptr`, never a
pointer-sized integer.

### Exceptions
raise/rescue is `setjmp`/`longjmp`. Built with `-mexception-handling
-mllvm -wasm-enable-sjlj` (also `-Wl,-mllvm,-wasm-enable-sjlj` for LTO
codegen) and wasi-libc's `libsetjmp`. This uses the **legacy** wasm EH
opcodes (`try`/`catch`): Chrome 95+, Firefox 100+, Safari 15.2+, Node 17+,
Workers. The rescue in `repl_entry.w` lives in a function because a `setjmp`
in `main` made the SjLj pass rewrite all ~5k registration calls (a 21 MB
function, above V8's 7.6 MB limit).

### Memory / GC
The runtime has no collector (`malloc`/`free` + compile-time frees), and the
instance is discarded after each run, so nothing else is needed. Linear
memory: 32 MiB initial, 1 GiB max, 8 MiB stack placed first (overflow traps
instead of corrupting data). `mmap` is reimplemented in `wasi_stubs.c`:
anonymous maps are fresh `memory.grow` pages (zero, lazily committed — the
string slab's `PROT_NONE` reservation costs nothing until touched; wasi-libc's
emulation rejects `PROT_NONE`), file maps are `malloc`+`pread`. The slab
reservation is cut from 512 MiB to 8 MiB (`-DW_SLAB_MAX_SLOTS=262144`; a full
slab falls back to heap strings).

### Runtime sources
Compiled: `runtime.c tensor_bridge.c ssmr_witness.c lexchar_tables.c
unicode_tables.c aks.c tls_stub.c slab_zstd_stub.c` — **unmodified** apart from
item 7; `compat/wasi_compat.h` is force-included and `compat/*.h` supply the
headers wasi-libc lacks (`ucontext.h execinfo.h spawn.h sys/wait.h netdb.h`).
Left out: event loops, `terminal_input.c`, Metal/BLAS/HID/MLX bridges,
`tls.c`, `http2/3.c`, `slab_zstd.c`. Regex is POSIX `regex.h` (musl), not
Oniguruma. C bignum kernels are the portable `__int128` paths.

### Stubs (`wasi_stubs.c`) — all inert, all fail politely
| area | behaviour |
| --- | --- |
| processes: `fork exec* system popen pipe dup* posix_spawn* waitpid kill` | `-1`/`ENOSYS` (`system(...)` → `false`) |
| signals: `sigaction sigprocmask …` | no-ops |
| DNS: `getaddrinfo getnameinfo getifaddrs` | `EAI_FAIL` / `-1` (sockets: wasi-libc's own `ENOSYS`) |
| `dladdr`, `backtrace*` | not found / empty |
| `ucontext` (goroutines) | `ENOSYS` — no stack switching on wasm |
| threads | wasi-libc single-thread stubs: `Thread.new` fails |
| event loop (`w_event_*`), `w_isatty_stdout` | no loop; `isatty(1)` (shim says no → no ANSI) |
| `mkstemp` | `EROFS` |
| `pause()` (`sleep` with no duration) | prints an error, exits 1 |
| `__builtin_return_address` | `NULL` (only a debug hint in two fatal messages) |
| `ccall_nobox` ABI adapters | `w_body_arena_get`, `w_location_file_offset`, `w_big_array_view` re-exported with all-`i64` params |

Shim side: filesystem is read-only (`EROFS` on create/truncate/write-open,
`write_file` returns failure), `sleep` advances a virtual clock instead of
blocking, `random_get` uses `crypto.getRandomValues`, output is capped.

### Build gates
`scripts/link.sh` fails the build on a wasm-ld "function signature mismatch"
and on any `*_bitcast_invalid` symbol — both are calls that would trap at run
time. `scripts/build_host.sh` gives the seed compiler and the freshly built
host compiler **separate cache directories**: the compiler's on-disk caches
are not keyed by compiler identity/target, and sharing `build/cache` produced
a host compiler whose `main` mis-parsed its own argv.

## Known gaps
* **CPU**: the interpreter re-lexes/re-parses autoloaded core files on every
  request (`[1,2,3].map` parses `core/tungsten.w` + `array.w` +
  `traits/enumerable.w` ≈ 20 ms). It is a slow tree-walker: ≈4–5 µs per method
  call, so tight loops of ~20k iterations reach the 50 ms budget. Cheap wins
  not done here: a parsed-AST cache for core files in the bundle, or a
  post-init memory snapshot (wizer-style) with the common classes preloaded.
* No threads, goroutines, channels-with-blocking, sockets/HTTP/TLS, processes,
  terminal input, GPU/Metal/MLX/BLAS, `dlopen`, zstd slabs, file writes.
* `gets`/stdin works only via the pre-supplied `stdin` bytes.
* Pure compute loops cannot be interrupted by the shim (`timeoutMs` is checked
  on WASI calls only) — rely on the platform CPU limit.
* Bugs that reproduce identically in the native twin (not port issues):
  `<< 500ns` prints `-1688849.860s` (the interpreter passes a boxed int to
  `w_duration_ns(int64_t)`); `5m30s + 30s` fails with "cannot add duration +
  numeric".
