# tungsten-cinder

**Cinder** is a pure-Tungsten native code-generation backend, in-process JIT, and direct binary object emitter (`Mach-O 64` and `ELF64`) designed as a zero-Clang alternative for both interactive JIT workloads and ahead-of-time Tungsten compilation.

## Capabilities

1. **In-Process WIRE JIT (`arm64` & `x86_64`)**
   - Compiles `WireFunc` / WIRE text directly into executable memory (`MAP_JIT` on macOS Apple Silicon, `mmap` RWX / W^X on Linux `x86_64` & `aarch64`) in ~10–25 µs per function.
   - Includes local `mem2reg` slot promotion into callee-saved registers, all 12 TypedArray width inline accessors (including ARMv8.2 FP16 and x86_64 F16C / IEEE-754 binary16), and 128-bit NEON / SSE2 / AVX2 loop vectorization.
2. **Direct AOT `.ll` -> Native `.o` & Executable Compiler (Zero `clang` / `llvm` / `as`)**
   - Streams Tungsten's emitted `.ll` IR directly into native **Mach-O 64-bit** (`CPU_TYPE_ARM64`) or **ELF64** (`EM_X86_64` & `EM_AARCH64`) relocatable object files, complete with thread-local storage (`__thread_vars`/`__thread_bss` on macOS, `.tbss` `TPOFF32` on Linux), GOT/PLT/page relocations, `i128` & `<2 x i64>` lowering, and ARM64 inline/module assembly encoding.
   - Links directly against Tungsten's prebuilt runtime archive via the OS linker (`ld` on macOS, `ld.lld` / `ld` on Linux) — capable of self-hosting the full 575,000-line `compiler/tungsten.w` compiler on both macOS ARM64 and Linux `x86_64`.

## CLI Usage

```bash
# Compile a .ll module to a native relocatable .o object (host or explicit target)
bin/cinder compile input.ll -c -o output.o
bin/cinder compile input.ll --target x86_64-unknown-linux-gnu -c -o output_x64.o

# Compile a .w or .ll file all the way to a native executable via Cinder + OS linker
bin/cinder compile app.w -o app
bin/tungsten --cinder -o app app.w
```

## Library Usage

```tungsten
use cinder

mod = wire_parse_text(wire_src)
res = wire_compile_func(mod.functions[0])
fp = res[0]
```
