# Linear-algebra benchmark suite

Cross-language single-precision (f32) matrix-multiply benchmark for
comparing Tungsten's CPU codegen against the leading native and managed
linear-algebra runtimes. Same operation across all implementations:

  Compute `C = A · B` where A, B, C are N×N row-major f32 matrices,
  K times, report median wall-clock time in ms and effective GFLOPS.

Sizes: **N = 4** (quaternion-scale, exercises register reuse + ILP),
**N = 256** (cache-resident, exercises SIMD throughput),
**N = 2048** (memory-bandwidth bound, exercises blocking + threading).

## Implementations

| Language / runtime          | Strategy                                           | Notes |
|------------------------------|---------------------------------------------------|---|
| C (`c/matmul.c`)             | Hand-rolled triple loop, then with `-O3 -march=native -ffast-math` | Baseline. clang auto-vectorizes to NEON / AVX. |
| C + Accelerate (`c/matmul_accel.c`) | `cblas_sgemm`                              | Apple Accelerate framework, the high-water mark on Apple Silicon. |
| Rust (`rust/`)               | `nalgebra` static-size + `ndarray` dynamic-size | Idiomatic Rust matrix libraries. |
| Python (`python/matmul.py`)  | `numpy.matmul` / `@` operator                     | OpenBLAS or vecLib on macOS. |
| Julia (`julia/matmul.jl`)    | `*` operator (built-in)                           | OpenBLAS by default. |
| Go (`go/matmul.go`)          | `gonum/mat`                                       | Pure-Go BLAS via gonum. |
| Swift + MLX (`swift/matmul.swift`) | `MLX.matmul` on Apple Silicon GPU            | Metal Performance Shaders under the hood. |
| Swift + Accelerate           | `vDSP_mmul`                                       | Native Apple linalg, no GPU. |
| **Tungsten (`tungsten/`)**   | Hand-rolled with native `## f32` arithmetic       | Today: scalar f32 (compiler/lib/lowering's f32 path, see commit 74eed92b). Future: `<4 x float>` SIMD lowering + `@llvm.matrix.multiply.*` / Accelerate dispatch. |

Each language directory has its own `README.md` with build/run
instructions and any version pinning. The top-level `run.sh` invokes
all available implementations and writes a `results.csv`.

## Running

```bash
# Run everything available on this machine, write CSV.
./benchmarks/linalg/run.sh

# Single implementation.
./benchmarks/linalg/run.sh --only tungsten

# Custom size / iterations.
./benchmarks/linalg/run.sh --sizes 4,256,2048 --iters 1000,100,10
```

## Expected order on Apple Silicon (M1 Pro / M2 / M3 / M4)

For N = 2048 single-precision matmul, ballpark wall-clock:

- **Swift + MLX (Metal GPU)** — fastest by a wide margin (~0.1× the CPU
  numbers, often hundreds of GFLOPS).
- **Accelerate (CPU)** — ~2-5 GFLOPS/core × cores, uses AMX
  co-processor on M-series.
- **numpy + vecLib** — basically Accelerate under the hood, expect parity.
- **C with `-O3 -march=native -ffast-math`** — clang auto-vectorizes
  reasonably, ~30-50% of Accelerate.
- **Tungsten (scalar f32 native)** — today, much slower than the
  above because we emit scalar `fmul float` / `fadd float` instructions.
  Even though they're native, there's no SIMD packing.

For N = 4 (quaternion-scale), the picture flips: register pressure and
function-call overhead dominate. Tungsten's tight `Mat4 * Mat4` loop is
expected to be competitive once `<4 x float>` lowering lands.

## Updating Tungsten's number

After running, paste the result block into `results.md` with a
date and machine identifier. The repo's `make bench-linalg` target
(once added) will re-run, compute deltas vs the last entry, and flag
regressions.

## What's blocking Tungsten parity with Accelerate

In rough order of impact:

1. **`<4 x float>` LLVM types for Vec4 / Mat4 receivers** — enables
   one-instruction SIMD multiply across 4 lanes; ~4× speedup on
   matrix-vector products and cross products.
2. **`shufflevector` for swizzles** — today `.wzyx`, `.yzx`, etc.
   construct fresh component arrays; should be one shuffle instruction.
3. **`@llvm.matrix.multiply.f32.v16f32.v16f32` intrinsic emission** for
   `Mat4 * Mat4` — clang lowers this to AMX on Apple Silicon (via
   Accelerate's hot path) and to AVX-512 dot-product instructions on x86.
4. **Accelerate dispatch** for large `Mat<T, M, N> * Mat<T, N, P>` —
   ccall through to `cblas_sgemm` when M, N, P > some threshold.
5. **MLX backend** for `@gpu fn` kernels containing matrix arithmetic
   — already partially wired through `metal_emitter`, would let
   GPU-friendly code reach MLX's optimized kernels.

See PERFORMANCE.md (forthcoming) for measurement methodology and
the change-log of optimization landings.
