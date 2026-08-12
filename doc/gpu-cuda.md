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

Accepted entries are `metal`, `cuda`, `wgsl`, `spirv`, and `none`. Names are
case-sensitive and may not be repeated; `none` must be used alone. Invalid
lists fail before any GPU sidecar is written. Metal is always emitted, so an
explicit `metal` entry documents intent but does not change the artifact set.

The default spec gate validates compiler-emitted WGSL with a pinned Naga CLI
on Linux CI. For the same semantic validation locally, install `naga-cli`
30.0.0 and either put `naga` on `PATH` or set `NAGA_BIN` before running
`scripts/test-specs.sh --job-wgsl spec/compiler/gpu_wgsl_emit_spec.w`.

## Check-time diagnostics

`bin/tungsten --check kernels.w` runs the selected-dialect emitters without
writing sidecars. Every `@gpu fn` is checked independently, so unrelated
invalid kernels are reported together under `E_GPU_KERNEL_UNSUPPORTED` with
the function name, dialect, and source line for each failure. The primary
caret remains anchored on the first failure. A function that is invalid in
more than one dialect reports the first selected-dialect failure, avoiding
duplicate follow-on messages for the same body.

## Surface (v0+)

Supported in both Metal and CUDA:

- Parameters: `## f32[]`, `## i32`, `## f32`, half/bfloat variants where mapped
- Locals with `##` type hints
- Assignments, `if` / `elsif` / `else`, `while`, `return`
- Indexing `a[i]`, arithmetic, comparisons
- `gpu.thread_position_in_grid` (and related grid/thread ids)
- `gpu.shared_f32(N)` / `gpu.shared_i32(N)` → `__shared__` / `threadgroup`
- Device helpers: `@gpu fn name(...)` with `## TYPE: ret`

Array parameters default to `device` memory. Device helpers can state the
required address space in the existing type-hint line, for example
`## f32[] threadgroup: tile` or `## u32[] constant: table`; accepted spaces are
`device`, `constant`, `threadgroup`, and `thread`. Entry kernels accept
`device` and `constant` buffers—the host ABI does not yet expose dynamic
threadgroup arguments, so shared storage must be allocated with
`gpu.shared_*` inside the kernel. Check-time preflight verifies helper calls
against these contracts.

Workgroup allocations are checked in aggregate, including implicit reduction
scratch: 32 KiB for Metal, 48 KiB for CUDA, and 16 KiB for the portable WGSL
baseline. A kernel exceeding the selected dialect's limit fails at
`bin/tungsten --check`, before an external shader compiler runs.

Buffer parameters may replace `[]` with a positive fixed extent, such as
`## f32[256]: values`. The emitted ABI remains a pointer/binding, while
preflight uses the extent to reject literal and constant-computed out-of-bounds
indices. Dynamic index range proofs remain conservative: an index whose range
cannot yet be proven is left to an explicit source guard.

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
