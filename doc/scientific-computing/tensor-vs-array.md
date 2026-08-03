# Array · Tensor · (no more NdArray) · Grid?

## Short answer

**You do not need a third multi-D type.**  
`NdArray` is gone. **`Tensor` is the multi-D dense numeric type.**  
**`Array` is the 1-D growable sequence.**  
**`WTensor` is the C runtime header** for multi-D storage (like `WArray` for
1-D) — not a second user-facing type. See `wtensor.md`.

`Grid` was a temporary portable CPU multi-D while Tensor was Metal-only.
It should **merge into Tensor** (CPU storage face + Metal face), not stay
forever. Reserve the word **grid** for *discretized fields / meshes / ML
search grids* if we need that domain type later — not for “ndarray.”

## Why Tensor is enough

| Concern | Answer |
|---------|--------|
| CPU vs GPU | Storage backend, not type name. Tensor holds shape/strides/dtype/(unit); buffer may be WArray pages or MTLBuffer/MTLTensor. |
| Rectangular? | Yes — any shape `[d0,…,dk]`, not necessarily square. |
| Only floats? | No — dtype/ebits (f32, f64, i32, bool, bf16, …). |
| vs Array | Array = 1-D list with cap/push. Tensor = fixed product(shape), multi-index. |

## Dense tables and layout are views, not Tensor subtypes

For shape `[rows, cols]`, Core's explicit element strides express both common
packed layouts over the same `f32[]`/`f64[]` storage:

```
Tensor.packed_strides([rows, cols])       # [cols, 1]  row-major / C order
Tensor.column_major_strides([rows, cols]) # [1, rows]  column-major / Fortran order
```

`Tensor.wrap_cpu(buffer, dtype, shape, strides, offset)` keeps that storage
zero-copy. `transpose` and `permute` are also zero-copy views: they reorder
shape and strides, so a write through either view aliases its parent. A BLAS
call may materialize a non-contiguous view because the current small bridge
offers row-major NN only; that compute limitation does not change the storage
or indexing contract.

`Tensor.from_rows(rows, Tensor.f64)` and `to_rows` are intentional copy
boundaries for numeric nested tables. Koala's `Matrix#to_tensor` /
`Matrix.from_tensor` use them, while its ragged-row nil-padding facade remains
separate: `nil` padding is not a numeric Tensor value.

### Fixed rank aliases

| Spelling | Meaning |
|----------|---------|
| `Mat2` / `Mat3` / `Mat4` | Already exist — small fixed **matrices** (graphics/LA). |
| `Vec2` / `Vec3` / `Vec4` | Fixed small **vectors**. |
| `Tensor3` | **Avoid** — ambiguous (rank-3? 3×3?). |
| `Tensor<3,3,3>` | Shape-in-type only helps **tiny fixed** tensors; fights dynamic sci sizes. Prefer runtime shape. |

### Recommended type spelling

```
# Element type + optional unit in the class params; shape at construction:
Tensor<f32>.zeros([3, 4])
Tensor<f64, m/s>.zeros([nt, nx, ny])

# Not:
Tensor<3, 4>              # shape as type params — wrong for dynamic N
Tensor<f32, m/s>(3, 4)    # ok-ish for rank-2 only; doesn't scale to rank-k
```

**Yes — with `Class<T, Q>` you still pass dimensions** as a shape value
(or fixed Mat/Vec when rank is 2/1 and tiny). Units and dtype are the
type parameters; **rank/extents are usually values**.

### “Just Array with multi-D storage?”

Elegant long-term story:

- `Array` remains the surface people know  
- When constructed with a multi-D shape, storage becomes shaped (WArray +
  shape/strides header, or Tensor under the hood)

That’s a language-kernel change. Until then, **explicit Tensor** is clearer
than overloading Array push/size semantics.

## What about `core/sci/grid.w` today?

Still there as a **pure-Tungsten multi-D** that works without Metal (smoke
tests, portable LA). Treat as **implementation scaffold** for Tensor’s CPU
path — migrate call sites to Tensor once `.zeros(shape)` works without a
Metal device.

## Safetensors

**Safetensors** is Hugging Face’s simple binary format for ML tensors:
length-prefixed JSON header + raw contiguous arrays, **no pickle** (so no
arbitrary code execution). Good for model weights. Tungsten already loads
it via **MLX** (`mlx_load_safetensors` in `runtime/mlx_bridge.c` /
llama bit). It’s not a general scientific archive (no groups/attrs like
HDF5).

## MLX — what else to expose

Already: sgemm/dgemm/hgemm/bgemm, batch sgemm, safetensors load, nvfp4
quant matmul.

Worth adding next:

| MLX op | Sci / ML use |
|--------|----------------|
| `mlx_add` / `mul` / `exp` / … | fused GPU elementwise on arrays |
| `mlx_softmax` / `mlx_matmul` graph | training-style graphs |
| reductions `sum`/`max` | over axes |
| `mlx_fft` if present | GPU FFT |
| random generators | Monte Carlo on GPU |
| compile / eval control | keep graphs off the CPU |

Keep MLX **opt-in** (dylib size) — same as today.

## Accelerate (in progress)

Expanded BLAS1/2 + vDSP: saxpy, sgemv, vadd/vmul/vsmul/vfill, vlog/vsqrt,
plus existing gemm / FFT / pure-C dgesv.
