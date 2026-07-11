# Tensor vs WTensor

## Short answer

| Name | Layer | Role |
|------|--------|------|
| **`Tensor`** | language (`core/tensor.w`) | Multi-D dense type: shape, strides, dtype, unit, CPU/GPU ops |
| **`WTensor`** | runtime C (`runtime/runtime.h`) | **Struct header** for multi-D storage — same idea as `WArray` for 1-D |

`WTensor` is **not** a second user product type. It is the boxed layout the
runtime uses for CPU multi-D buffers (and what `Tensor.w_*` factories expose
as an opaque handle). Language code should say `Tensor`.

```
Tensor  ──CPU face──►  WArray pages / buffer bytes
        ──header───►  WTensor { ebits, rank, offset, shape, strides, storage }
        ──GPU face──►  MTLBuffer + optional MTLTensor
```

## Why the name `W`?

Runtime boxes use a `W` prefix (`WArray`, `WHash`, `WTensor`) — Tungsten’s
native heap objects. The language class is plain `Tensor`, matching how
`Array` sits above `WArray`.

## Fields (`struct WTensor`)

```c
typedef struct WTensor {
  uint8_t type;           /* W_TYPE_WTENSOR */
  uint8_t flags;
  int8_t  ebits;          /* same codes as WArray (e.g. −32 = f32) */
  uint8_t rank;
  uint8_t borrow;         /* 1 = do not free storage */
  int32_t offset;         /* element index into storage */
  int32_t shape_inline[4];
  int32_t strides_inline[4];
  int32_t *shape_heap;    /* if rank > 4 */
  int32_t *strides_heap;
  void    *storage;
  int64_t  storage_elems;
} WTensor;
```

### ebits

Match **WArray** (65 = polymorphic w64, −32 = f32, −64 = f64, …).

### shape / strides / offset

- **shape[k]** — extent on axis k (outer → inner, C order by default)
- **strides[k]** — step in **elements** (not bytes)
- **offset** — element index of the first logical element in `storage`
  (views/slices without copy)

```
logical[i0,i1,…]  →  storage[offset + Σ i_k * strides[k]]
```

## Language API over WTensor

```
t = Tensor.w_zeros([4, 3])           # allocate WTensor
<< Tensor.w_rank(t)
<< Tensor.w_shape(t)
Tensor.w_set(t, [1, 2], ~3.5)
v = Tensor.w_slice0(t, 1, 3)         # borrow storage, shift offset
w = Tensor.w_view(t, 3, [3, 3])
```

Full arithmetic, unit tagging, Metal, and matmul live on **`Tensor` objects**
(`Tensor.zeros`, `Tensor.zeros_unit`, …), which may hold a WArray or Metal
buffer rather than always boxing a `WTensor` today. Unifying every CPU
`Tensor` to always own a `WTensor` header is the long-term clean story;
`w_*` is the header surface already.

## Relation to Metal

`WMetalTensor` is the ObjC `id<MTLTensor>` handle — a third face, not a
rename of `WTensor`. A Metal-backed language `Tensor` can hold buffer +
MTLTensor over unified memory while a CPU-only path uses WArray / WTensor.
