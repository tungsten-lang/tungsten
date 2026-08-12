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

## Results

### Fixed small — current `Mat3`/`Mat4` vs ideal

Apple M5 Max, Homebrew clang 22.1.8, 2026-08-12; median of three warmed
Tungsten runs.

| kernel | Tungsten `*` | Tungsten `mul_into` | raw Tungsten kernel | C schoolbook | `*` gap |
|---|---:|---:|---:|---:|---:|
| Mat3 (27 mul) | 71.9 ns/op | 23.7 ns/op | 17.4 ns/op | 2.10 ns/op | **34.3×** |
| Mat4 (64 mul) | 75.7 ns/op | 26.6 ns/op | 20.5 ns/op | 2.62 ns/op | **28.9×** |

The compiler now preserves both matrix operands as typed float storage, lowers
the arithmetic to native fmul/fadd/FMA, and constructs `[...] ## f64[N]`
directly in one typed buffer rather than boxing into a temporary Array and
copy-converting it. That cuts the value-semantic operators from the old
2837/3267 ns baseline to 72/76 ns (**39×/43× faster**). Tiny typed
literals also keep their WArray header and element payload in one allocation,
removing the second malloc while retaining normal grow/free behavior.

`mul_into(other, out)` separates allocation from arithmetic for hot loops.
The raw-kernel row additionally removes the three matrix method sends and is
the compiler/codegen floor. C still has stack-resident fixed arrays and no
WArray header loads, so 2–3 ns is not yet a like-for-like API target. The
remaining Tungsten gap is fixed-storage escape/stack promotion, object
dispatch/allocation, and WArray access—not the schoolbook arithmetic.

### NxN sweep — GFLOP/s

Current same-flags C, Apple M5 Max, Homebrew clang 22.1.8, 2026-08-12:

| N | schoolbook | Strassen | dgemm (AMX) |
|---|---|---|---|
| 8 | 11.4 | 11.1 | 15.8 |
| 16 | 11.3 | 11.8 | 37.4 |
| 32 | 15.0 | 11.9 | 164 |
| 64 | 20.2 | 18.5 | 351 |
| 128 | 21.6 | 19.0 | 431 |
| 256 | 17.2 | 20.7 | 411 |
| 512 | 17.3 | **22.8** | 443 |

The current Tungsten hand-written `f64[]` schoolbook loop reaches only
**~0.99 GFLOP/s** at N=512, while warmed `dgemm` reaches **~443 GFLOP/s**.
The old near-C result below has regressed; it is retained as useful compiler
history, not presented as current performance.

Historical progress: 0.10 → 0.27 → 4.0 → 17 GFLOP/s across four compiler fixes:
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
