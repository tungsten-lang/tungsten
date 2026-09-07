# Compiler images

The normal Tungsten compiler is a closed compile/check/WIRE-run image. It does
not lower the legacy tree-walking interpreter, REPL, or multi-dialect GPU
emitter on every invocation.

`compiler/tungsten_driver.w` contains the shared command implementation.
Three deliberately thin entry files select the source image and then close
its Core and method universes. `LOCK_THE_DOORS!` already closes the type
universe, so the launchers do not redundantly declare `STOP_THE_PRESS!`:

- `compiler/tungsten.w` is the default launcher.
- `compiler/repl.w` uses the interpreter, REPL, and GPU adapter.
- `compiler/tungsten_metal.w` uses the full GPU adapter.

The default image parses its normal command line. REPL and legacy interpreter
modes delegate immediately to the REPL image. For a compile or check, a small
AST visitor detects `@gpu` definitions; only those programs delegate to the
Metal image. This preserves the existing command surface and generated GPU
sidecars without putting feature selection throughout the frontend or
mid-end. The optional binaries use the existing incremental source-manifest
cache, so a warm invocation validates rather than rebuilds them.

The default and Metal launchers also emit a no-op compiler-image marker. When
the linker is compiling `runtime.c` from source, it converts that marker into a
single C profile define. The profile removes product-only IC/static-dispatch
roots for Socket/TLS/HTTP, Channel, Mmap, Quantity, and packed network values;
FullLTO then drops their unreachable implementation regions. The REPL image
keeps the universal runtime, and ordinary programs compiled by any image do
too. The compiler's required `w_date_today` primitive remains available for
the one-day target-probe cache.

## Performance gate

On 2026-09-06, a fixed compiler compiled the original monolithic entry and the
new default entry seven times each, alternating order. Both used
`--release --native --fast --no-debug --emit-ll`; final-artifact caching was
disabled and both shared the same warmed frontend/Core cache.

| Image | Median | Mean | Emitted LLVM |
| --- | ---: | ---: | ---: |
| Monolithic | 3.698 s | 3.694 s | 27,562,726 bytes |
| Default | 3.149 s | 3.143 s | 22,907,184 bytes |

The default image reduced wall time by 14.83% and emitted IR size by 16.89%
(17.41% higher compile throughput). The first optional-image invocation pays a
native build; a warm legacy-interpreter invocation measured 0.62 s versus
0.24 s in the monolith. That cold/rare-path trade is intentional.

The final trust-chain-installed compiler is 6,997,648 bytes versus 10,094,400
for the matched monolith (30.68% smaller). Its dynamic dependencies are only
zstd and libSystem; the monolith also linked Metal, the UI/graphics frameworks,
Accelerate, MLX, and Objective-C because linker probes mistook probe strings in
the compiler's own static slab for live LLVM calls.

The runtime profile was measured separately against the exact same emitted
compiler LLVM, using seven alternating `--release --native --fast --no-debug`
link-only runs with the final-artifact cache disabled:

| Runtime | Median link | Mean link | Compiler bytes |
| --- | ---: | ---: | ---: |
| Universal | 28.195 s | 28.243 s | 7,052,576 |
| Compiler profile | 27.759 s | 27.986 s | 7,020,312 |

This is a deliberately modest win: 1.55% lower median link time (0.91% lower
mean), 32,264 fewer bytes, and 57 fewer runtime symbols. The small profile
boundary is retained because it removes whole product subsystems without
duplicating their implementations or changing ordinary-program semantics.

Correctness gates require stage-1/stage-2 identity for the default image,
legacy interpreter output identity, normal REPL behavior, and byte-identical
Metal/CUDA sidecars between the monolithic and delegated GPU paths.
