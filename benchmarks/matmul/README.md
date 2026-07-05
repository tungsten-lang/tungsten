# Matrix-multiply benchmarks

Does Tungsten's matmul approach (fully-unrolled schoolbook) hold up against the
fast algorithms — Strassen, Laderman, AlphaTensor — and where does vendor BLAS
sit? Sweeps fixed 3×3/4×4 up to 512×512.

```
benchmarks/matmul/run.sh        # build + run everything at --release flags
```

All C is built at **Tungsten's exact `--release` flags** (`-O3 -DNDEBUG
-march=native -mtune=native -flto`). Tungsten lowers to LLVM IR → clang with
these flags, so same-flags C is a faithful stand-in for Tungsten's backend
codegen for a general matmul (minus the array-access tax measured separately).

- `sweep.c` — NxN schoolbook (ikj) vs Strassen (recursive, base 64) vs
  Accelerate `cblas_dgemm`. Strassen verified against schoolbook each run.
- `fixed_small.c` — 3×3 / 4×4 unrolled schoolbook (the "ideal small" floor).
- `tungsten_matmul.w` — the actual `Mat3`/`Mat4` `*` operator, a hand-written
  NxN loop on `f64_array`, and warmed `dgemm` via `core/blas`.

## Results (Apple M5 Max, clang 21, 2026-06)

### Fixed small — current `Mat3`/`Mat4` vs ideal

| kernel | Tungsten `*` (measured) | C schoolbook (ideal) | gap |
|---|---|---|---|
| Mat3 (27 mul) | 2837 ns/op | 2.0 ns/op (499 M/s) | **~1400×** |
| Mat4 (64 mul) | 3267 ns/op | 2.5 ns/op (406 M/s) | **~1325×** |

The arithmetic is ~2 ns; the rest is operator-overload dispatch (runtime
`is_a?` walks) + per-call `class.new` heap allocation. **Dispatch/alloc bound,
not FLOP bound.**

### NxN sweep — GFLOP/s

| N | schoolbook | Strassen | dgemm (AMX) |
|---|---|---|---|
| 8 | 12.2 | 12.1 | 17 |
| 16 | 12.3 | 12.8 | 36 |
| 32 | 16.2 | 13.1 | 163 |
| 64 | 21.8 | 20.1 | 375 |
| 128 | 23.3 | 20.4 | 452 |
| 256 | 18.6 | 22.3 | 429 |
| 512 | 18.7 | **24.6** | 453 |

Tungsten-native: hand-written schoolbook loop ≈ **~17 GFLOP/s** at N=512
(~6% slower than same-loop C at ~17.9 GF — within measurement noise); warmed
`dgemm` ≈ **452 GFLOP/s** (full vendor speed, identical to C Accelerate).

Progress: 0.10 → 0.27 → 4.0 → 17 GFLOP/s across four compiler fixes:
1. `f64[n]` typed array + `:f64` float-path in `lower_assign_expr` / `lower_binary_op`
   (eliminated `store double <i64>` LLVM error; enabled inline `fmul`/`fadd`)
2. `:i64` machine-int loop vars now populate `ctx[:unboxed_vars]` in `lower_while`
   (eliminated `w_lt`/`w_mul` in index arithmetic; uses `icmp slt` / `mul i64` / `add i64`)
3. `!invariant.load !{}` on typed array header loads (`data_ptr` at header+16,
   `base_index` at header+4) in `emitter.w` — unblocked clang LICM to hoist the
   6 loop-invariant header loads out of the jj inner loop, which in turn enabled
   auto-vectorization to NEON `fmul.2d` (8 doubles/iter)
4. Default math mode (`--precise`, no flag required) emits `fmul contract double`
   / `fadd contract double` — enables LLVM FMA formation pass to fuse the SIMD
   `fmul.2d + fadd.2d` to `fmla.2d`, matching C's default `-ffp-contract=on`

Three math modes (compiler flag):
- (default): `contract` flag — FMA contraction, same as C `-ffp-contract=on`
- `--strict-math`: bare `fmul`/`fadd`, strict IEEE 754 two-rounding semantics
- `--fast-math`: `fast` flag — all transforms: reassoc + nnan + ninf + arcp + afn

Remaining ~6% gap: the `n` matrix-dimension parameter is a boxed WValue — each
`ii*n` and `kk*n` in the outer loops still nanunboxes `n` (two shifts). Unboxing
function parameters before use would close this final gap.

## Verdict

- **Strassen** crosses over schoolbook only at **N ≈ 256**, and only ~1.3× at
  512. Below that it *loses* — the multiply saving is eaten by block additions,
  recursion, and memory traffic. Not worth it for a general-purpose stdlib.
- **Laderman** (3×3, 23 vs 27 mul): trades 4 multiplies for ~40 extra
  additions and an irregular dataflow that defeats SIMD/FMA. With multiplies
  already free on FMA hardware, it's a net loss. (Not benchmarked — the
  multiply/add accounting is decisive, and its factor table isn't reproduced
  here.)
- **AlphaTensor** (4×4, 47 mul): the headline 47 is over **GF(2)** (mod-2),
  not float — it doesn't apply to these matrices. For real 4×4 it matched
  Strassen² (49), which loses to schoolbook + NEON at this size.
- **Vendor BLAS dominates**: Accelerate (AMX) is ~20× faster than *any* scalar
  approach at N≥128. The hardware datapath matters ~20×; the best algorithmic
  trick matters ~1.3×. For large matmul, call `dgemm` (already in `core/blas`).

**Takeaway:** schoolbook is the correct choice; the only gap to the C optimum
is Tungsten's dispatch/alloc/boxing overhead, not the multiplication algorithm.
The exotic algorithms are a dead end here.
