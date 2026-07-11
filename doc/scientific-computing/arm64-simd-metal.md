# ARM64 / NEON / Metal4 coverage vs Tungsten

## What we already lower or emit

| Area | Status |
|------|--------|
| Scalar LLVM IR → clang | Full path for ordinary arithmetic |
| `llvm.fma.f64` | Explicit `fma` in emitter |
| Inline asm NEON POCs | `asm_neon_*` in emitter (umull, REDC, madd, NTT, Goldilocks) |
| Mat4 / vec4 f32 | Hand NEON in `runtime.c` (`w_mat4_mul_f32`, …) |
| Accelerate AMX via BLAS/vDSP | cblas + vDSP + SparseBLAS bridges |
| Metal `@gpu fn` → MSL | metal_emitter |
| Metal4 MTLTensor / matmul2d | Tensor path + MPP cooperative tensors |
| CUDA dialect emit | signatures + wmma subset |

## Gaps worth a Tungsten surface

### NEON / ARM64 SIMD (CPU)

| Instruction class | Tungsten correlary (proposed) |
|-------------------|-------------------------------|
| `fadd`/`fmul`/`fmla` 4×f32 / 2×f64 | `Simd.f32x4` / ops, or auto-vectorize Grid/Tensor loops |
| `ld1`/`st1` structured loads | typed WArray/WTensor vector load/store |
| Integer `add`/`mul`/`mla` | crypto/NTT already POC; expose as `Simd.i32x4` |
| `fcvt` f16↔f32 | bf16/f16 Tensor convert (partial via MLX) |
| SVE/SME (M4) | longer-term; Apple SME via Accelerate today |
| `tbl`/`tbx` permutes | sparse gather, codec tables |
| Crypto AES/SHA | already separate crypto path |

**WIRE gap:** no first-class vector types in IR yet — only scalar + external ccall/asm. Next step: WIRE `vN<T>` ops that lower to LLVM `<N x T>` or stay as Accelerate/NEON calls for hot kernels.

### Metal4 / GPU

| Feature | Sci correlary |
|---------|----------------|
| MTLTensor ranks | WTensor + GPU face |
| `matmul2d` / cooperative_tensor | dense LA / ML |
| `reduce_rows` / Shader ML | softmax, norms |
| Argument tables | bind multi buffers without re-encode |
| Concurrent ML + render | viz + sim |

### Recommendation

1. Keep **hot paths** on Accelerate/SparseBLAS/Metal (mature, AMX-aware).  
2. Add **WTensor** + dtype-aware loops that LLVM can auto-vectorize.  
3. Promote battle-tested `asm_neon_*` patterns only where LLVM fails (NTT, modular arith).  
4. Do **not** mirror every NEON mnemonic in the language — expose **ops** (add, fma, matmul, fft), not instructions.
