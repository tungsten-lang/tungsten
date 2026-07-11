# Grid — RETIRED

**Grid is removed.** Multi-D dense → **Tensor** (`core/tensor.w` + `WTensor`
in `runtime/runtime.h`). See `tensor-vs-array.md` and `wtensor.md`.

Historical note: Grid briefly stood in as a pure-Tungsten multi-D before
Tensor gained a proper CPU header. We do not keep both.

## Quick use

```
use core/sci/grid

g = Grid.zeros([3, 4])        # default allocation — zero-filled
e = Grid.eye(4)
m = Grid.from_nested([[~1.0, ~2.0], [~3.0, ~4.0]])
```

## Array vs Grid — *mechanically*

| | **Array** | **Grid** |
|--|-----------|----------|
| Runtime header | `WArray`: flags, **ebits**, start, **size**, **cap**, slots | shape[], strides[], offset, data |
| Rank | always 1 | N (product of extents) |
| Growth | push/pop/shift; `cap` | fixed product(shape); reshape/view |
| Index | single integer `a[i]` | coordinates → offset + Σ iₖ·strideₖ |
| Element types | ebits (u8…f64, w64 polymorphic) | v0: Float list; ebits planned |
| Role | sequences, stacks, generic code | dense multi-D numeric work |

A Grid is **not** "an Array with shape metadata bolted on" today: it does
not share the WArray header. Longer term, a Grid may *reference* a typed
WArray as `data` (zero-copy with BLAS/Metal).

## Is a Grid a Tensor?

Conceptually **yes** — a dense multi-dimensional rectangular array.

- **Rectangular**, not necessarily square: any `[d0,d1,…,dk]`.
- **Not floats-only** by design: v0 is Float for simplicity; ints, bools,
  decimals, bf16 should use ebits like Array.
- **`core/tensor.w` today** is Metal-first (MTLBuffer / MTLTensor). That
  is a *storage backend*, not a different math object. The end state is
  one multi-D type (Grid or a unified Tensor) with CPU/Metal/CUDA faces —
  not two competing NDArray-style APIs.

## Zeros by default

New grids assume **zero-filled memory** (kernel zero pages for raw
buffers). `Grid(shape)` / `Grid.zeros` is the default path; `ones` /
`full` are explicit non-zero fills. Avoid APIs that allocate then
eagerly write zeros when the page is already zero.

## Units

Purpose: an array of **untagged** numbers that, *outside the local
numeric kernel*, behave as one quantity (e.g. all samples are m/s).

Already works: `Array` of `Quantity` (w64) — per-element units, heavy.

Wanted: **aggregate unit** on a homogeneous buffer.

### Preferred

1. **Type parameters** — `Grid<f64, m/s>` or `Grid<T, Q>`  
   Fits Tungsten's monomorphized generics; unit is part of the type.
2. **Named arg at construction** — `Grid.zeros([n], unit: m/s)`  
   Natural for dynamic units; a bit Python-y but readable.

### Acceptable later

3. Method `.with_unit(m/s)` — Ruby-ish; fine as a transformer.

### Rejected

- String units (`"m/s"`) — never in Tungsten  
- Two-field record `{data:, unit:}` — not a type  
- Hadamard-with-unit tricks — obscure  
- `Quantity(grid)` as "quantity of array" — confuses scalar Quantity  
  with a buffer; if anything, the grid *has* a unit, it is not itself a
  Quantity value in the CODATA sense  

No spare operator feels intuitive for unit annotation; don't force one.

## Naming note

`NdArray` was retired for being clunky and NumPy-shaped. `Grid` is short
and multi-D by connotation. If we later unify with Metal `Tensor`, the
portable name may become `Tensor` with backends — until then, Grid is the
sci-stack surface.
