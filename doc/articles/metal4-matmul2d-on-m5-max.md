# Metal 4 matmul2d on M5 Max

Apple's M5 Max ships Metal 4 and `MTLGPUFamilyMetal4`. The headline new
primitive is `mpp::tensor_ops::matmul2d` — a cooperative-tensor matrix
multiply distributed across SIMD-groups inside a threadgroup. We wired
it into Tungsten's Metal runtime and benched against the existing
`simdgroup_matrix` kernel.

## Result

F16 matmul, K=N=2048, varying M. Best-of-5 ms/iter, on macOS 26.4.1
(Tahoe), Apple M5 Max, 40-core GPU.

```
shape (M)  | matmul2d   simdgroup_v4   speedup
-----------+------------+--------------+--------
  M=64     |   2.7 TF   |  10.3 TF     | 0.26×
  M=128    |   5.2 TF   |  11.1 TF     | 0.46×
  M=256    |   8.7 TF   |  11.8 TF     | 0.74×
  M=512    |  13.9 TF   |  12.0 TF     | 1.16×
  M=1024   |  18.9 TF   |  11.8 TF     | 1.61×
```

Crossover at **M ≈ 400**. matmul2d wins for prefill batches at long
prompts; the existing simdgroup-matrix kernel still wins for small
batches and decode (M=1).

The win at M=1024 is **19 TFLOPS measured** — close to Apple's published
17 TFLOPS-ish FP16 peak for M5 Max's GPU, and ~60% over the
simdgroup-matrix path.

Existing kernel: `bits/tungsten-llama/lib/kernels/nvfp4/f16_matmul_simd_v4_fc.metal`
(Metal 3, 8×8 simdgroup_matrix tiles, K loop unrolled 8×).

New kernel: `bits/tungsten-llama/lib/kernels/f16_matmul_m4.metal`.

## Two load-bearing bugs in the integration

Apple's published example for `matmul2d` is wrong on two points. Both
caused multi-tile dispatches to silently mis-write or only partially
write output. Single-tile dispatches at (0,0) appeared correct, which
made the bug subtle.

### Cooperative-tensor pipelines need MTL4Compiler

Pipelines built via the legacy `[device newComputePipelineStateWithFunction:]`
path silently mis-dispatch when the kernel uses cooperative tensors.
The fix:

```objc
MTL4LibraryFunctionDescriptor *fn = [[MTL4LibraryFunctionDescriptor alloc] init];
fn.library = lib;
fn.name    = fn_name;

MTL4ComputePipelineDescriptor *pd = [[MTL4ComputePipelineDescriptor alloc] init];
pd.computeFunctionDescriptor    = fn;
pd.requiredThreadsPerThreadgroup = MTLSizeMake(128, 1, 1);  // mandatory

id<MTL4Compiler> compiler = [device newCompilerWithDescriptor:cdesc error:&err];
id<MTLComputePipelineState> ps =
    [compiler newComputePipelineStateWithDescriptor:pd
                                  compilerTaskOptions:nil
                                                error:&err];
```

`requiredThreadsPerThreadgroup` is **only settable on
`MTL4ComputePipelineDescriptor`** — there's no equivalent on the legacy
`MTLComputePipelineDescriptor`. Apple's docs note in passing that
cooperative tensors require this property, but the example code in
`MPPTensorOpsMatMul2d.h` builds pipelines via the legacy path.

In Tungsten this lives at:
- `runtime/metal.m` → `w_metal4_compiler_new`, `w_metal4_pipeline_for`
- `core/metal.w` → `metal4_compiler`, `metal4_pipeline`

### Apple tensor extents are `(innermost, outermost)`

For row-major M×K data, the natural reading is "extents = (M rows, K cols)".
But Metal's `dextents` orders **innermost first** — for a row-major M×K
buffer where K varies fastest in memory, extents are `(K, M)` and strides
are `(1, K)`.

```metal
// WRONG (matches NumPy convention; produces silent multi-tile bug):
auto extA = dextents<int32_t, 2>(M, K);
auto mA = A.slice<64, dynamic_length_v<int32_t>>(tgid.x * 64, 0);

// RIGHT (Apple convention; multi-tile output writes correctly):
auto extA = dextents<int32_t, 2>(K, M);
auto mA = A.slice<dynamic_length_v<int32_t>, 64>(0, tgid.x * 64);
```

The slice dim ordering follows extents: `slice<innermost_extent, outermost_extent>(innermost_off, outermost_off)`.

With both fixes in place, multi-tile output is correct and the bench
above matches its scalar reference (`err_max = 0`) across all shapes.

## MTL4 host bindings — what was needed

`matmul2d` consumes `tensor<...>` kernel parameters, not buffer pointers.
Binding tensors requires the full MTL4 command stack — the legacy
`MTLComputeCommandEncoder` has no `setTensor` API.

Five new resource types in the Tungsten runtime:

```
W_TYPE_METAL_TENSOR        // id<MTLTensor>
W_TYPE_METAL4_QUEUE        // id<MTL4CommandQueue>
W_TYPE_METAL4_ALLOCATOR    // id<MTL4CommandAllocator>
W_TYPE_METAL4_ARGTABLE     // id<MTL4ArgumentTable>
W_TYPE_METAL4_COMPILER     // id<MTL4Compiler>
```

Per-dispatch flow:

```
metal4_compiler   ─→ metal4_pipeline (with requiredThreadsPerThreadgroup)
                                              │
metal4_argtable.setTensor(slot, tensor)       ↓
                  ─────────────────→ metal4_dispatch_groups_3d
metal4_alloc                            (begin cmdbuf, set argtable,
                  ─────────────────→     dispatchThreadgroups, end,
metal4_queue                             commit, signal+wait)
```

The load-bearing detail that's easy to miss: **MTL4 requires explicit
`MTLResidencySet`**. The legacy `setBuffer` implicitly tracked residency;
MTL4 doesn't. Without an `addResidencySet:` call before commit,
dispatches silently no-op:

```objc
MTLResidencySetDescriptor *rs = [MTLResidencySetDescriptor new];
id<MTLResidencySet> set = [device newResidencySetWithDescriptor:rs error:&err];
for (id<MTLBuffer> buf in resources) [set addAllocation:buf];
[set commit];
[queue addResidencySet:set];
// ... dispatch ...
[queue removeResidencySet:set];
```

`MTL4CommandQueue` also has no `waitUntilCompleted`. The canonical
pattern is signal an `MTLSharedEvent` after commit and wait host-side:

```objc
id<MTLSharedEvent> ev = [device newSharedEvent];
id<MTL4CommandBuffer> bufs[1] = { cmdbuf };
[queue commit:bufs count:1];
[queue signalEvent:ev value:1];
[ev waitUntilSignaledValue:1 timeoutMS:30000];
```

## What's worth using from Metal 4

- **F16/Q8 prefill matmul** at M ≥ ~400 — direct payoff via `matmul2d`.
- **NVFP4 matmul via dequant-into-half-tile + matmul2d** — works, holds
  ~72% of native F16 throughput (13.6 TF NVFP4 vs 18.9 TF F16 at M=1024)
  while using 4× less weight bandwidth. The kernel cooperatively
  dequantizes a 32×64 tile into TG memory per K-chunk and accumulates
  via `multiply_accumulate` mode into a long-lived `cooperative_tensor`.
  See `bits/tungsten-llama/lib/kernels/nvfp4_matmul_m4.metal`.
- **`MTL4ArgumentTable`** + **residency sets** — lower binding overhead
  than `setBuffer` per-dispatch.
- **Explicit `MTL4Compiler`** — separates pipeline build cost from
  dispatch cost; useful for warm restarts.

### Threadgroup memory must be set explicitly

When a kernel has a `[[threadgroup(N)]]` parameter (needed for the
dequant-tile path), MTL4 doesn't auto-allocate the TG memory. The host
must call `setThreadgroupMemoryLength:atIndex:` on the encoder before
dispatch. Without it, the kernel sees a null pointer and silently
writes nothing. Tungsten's `metal4_dispatch_groups_3d` takes
`tg_mem_bytes` as an explicit argument for exactly this — pass `0`
when the kernel has no TG-memory parameter, the actual byte count
(e.g. `4096` for a 32×64 half tile) when it does.

## What's not in Metal 4 (despite folklore)

- No native NVFP4 type in `MTLTensorDataType` or MSL scalars.
- No `MTLGPUFamily.apple10` in published headers — `MTLGPUFamily.metal4`
  is the documented capability flag for M5's tensor pipeline.
- No FP8 (E4M3/E5M2) datatypes in MSL.
- The `simdgroup_matrix` API from Metal 2.3+ still works and is
  competitive for shapes M < 400 — Metal 4's `matmul2d` is not a
  drop-in replacement.

## References

- `MetalPerformancePrimitives.framework/Headers/MPPTensorOpsMatMul2d.h`
- WWDC25 session 205 "Discover Metal 4"
- WWDC25 session 262 "Combine Metal 4 ML and graphics"
- llama.cpp PR #16634 (Metal4 Tensor API integration)
- liuliu/example_matmul_metal4 (GitHub) — third-party reference for
  the cooperative-tensor pattern; matches what we landed.
