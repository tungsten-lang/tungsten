# CUDA dialect for `@gpu fn`

Tungsten's GPU path is multi-dialect. Metal (MSL) is the primary Apple path.
**CUDA C** is a second dialect that reuses the same kernel AST and statement
emitters; only signatures and the thread-index prologue differ.

## Emit

When a program contains one or more `@gpu fn` definitions, compile writes:

| Artifact | When |
|----------|------|
| `source.metal` | Always (Metal) |
| `source.cu` | By default (CUDA). Disable with `TUNGSTEN_GPU_DIALECTS=none` |
| `source.wgsl` | Only if `TUNGSTEN_GPU_DIALECTS` includes `wgsl` |

```bash
bin/tungsten compile kernels.w --out /tmp/kernels
# → kernels.metal, kernels.cu next to kernels.w

TUNGSTEN_GPU_DIALECTS=cuda,wgsl bin/tungsten compile kernels.w --out /tmp/kernels
TUNGSTEN_GPU_DIALECTS=none     bin/tungsten compile kernels.w --out /tmp/kernels
```

## Surface (v0+)

Supported in both Metal and CUDA:

- Parameters: `## f32[]`, `## i32`, `## f32`, half/bfloat variants where mapped
- Locals with `##` type hints
- Assignments, `if` / `elsif` / `else`, `while`, `return`
- Indexing `a[i]`, arithmetic, comparisons
- `gpu.thread_position_in_grid` (and related grid/thread ids)
- `gpu.shared_f32(N)` / `gpu.shared_i32(N)` → `__shared__` / `threadgroup`
- Device helpers: `@gpu fn name(...)` with `## TYPE: ret`

CUDA-only (no MSL mapping):

- `gpu.wmma_*` tensor-core fragments (`wmma::fragment` / MMA)

Metal-only features (simdgroup matrices, some TG helpers) are skipped or error
on the CUDA path with a clear `@gpu kernel:` message.

## Host launch

Emitted kernels are `extern "C" __global__ void name(...)`. Launch from host C++:

```cpp
kernel<<<grid, block, shared_bytes, stream>>>(args...);
cudaDeviceSynchronize();
```

See `benchmarks/cuda_add/` for a minimal `nvcc` smoke test and
`spec/compiler/gpu_cuda_emit_spec.w` for emit-marker checks (no GPU required).

## Implementation

- Shared emitters: `compiler/lib/metal_emitter.w` (`emit_stmt` / `emit_expr`, dialect key)
- CUDA entry: `emit_gpu_kernels_cuda` / `emit_kernel_cuda` / `emit_device_fn_cuda`
- Wire-in: `compiler/tungsten.w` after LLVM emit, next to the source path
