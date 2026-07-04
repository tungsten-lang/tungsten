# SME / SME2 on Apple Silicon

ARM's Scalable Matrix Extension (SME) — and SME2 — is the new CPU-side
matrix-multiply hardware. Apple shipped it with M4 and refined it on M5
(`FEAT_SME2p1`, plus FP16-acc and BF16-acc outer-product variants).

We explored SME for LLM inference on M5 Max: smoke-tested the toolchain,
built an FP16 matvec kernel, and probed the SME2 LUTI4 path for NVFP4
dequant. The conclusion is that **SME is not viable as a primary
inference path** on this workload — the CPU-side bandwidth ceiling
caps it at ~4-16× slower than GPU. But the toolchain knowledge is
captured for future use.

## What M5 Max has

```
$ sysctl hw.optional.arm | grep -iE "sme|sve"
hw.optional.arm.FEAT_SME:    1     ← base SME
hw.optional.arm.FEAT_SME2:   1
hw.optional.arm.FEAT_SME2p1: 1     ← newer than M4
hw.optional.arm.SME_F32F32:  1
hw.optional.arm.SME_F16F32:  1     ← FP16 mul → FP32 acc
hw.optional.arm.FEAT_SME_F16F16: 1 ← FP16 mul → FP16 acc (NEW vs M4)
hw.optional.arm.FEAT_SME_B16B16: 1 ← BF16 mul → BF16 acc (NEW vs M4)
hw.optional.arm.SME_I8I32:   1     ← INT8 mul → INT32 acc
hw.optional.arm.sme_max_svl_b: 64  ← SVL = 64 bytes = 16 FP32 / 32 FP16 lanes
```

Notably **`hw.optional.arm.FEAT_SVE` is 0**: Apple ships *streaming-only*
SVE. SVE instructions are legal inside `PSTATE.SM=1` but trap with
SIGILL outside. This has consequences for how SME code can be written.

ZA tile (FP32 case): 16×16 elements. Each `fmopa za, p, p, z, z`
performs a full outer product = 256 FMAs = 512 FLOPS.

## The toolchain trap

Apple's clang accepts the ACLE SME function attributes:
- `__arm_streaming` (type qualifier, after declarator) — caller must enter
  streaming mode before calling.
- `__arm_locally_streaming` (declarator) — function enters/exits
  streaming on entry/exit.
- `__arm_inout("za")` (type qualifier) — function reads/writes ZA state.
- `__arm_new("za")` (attribute, before declarator) — function takes
  fresh ZA storage.

**All of them break on Apple silicon.**

Clang's lowering for SME-attributed functions emits `cntd` / `rdvl`
(non-streaming SVE) in the prologue/epilogue for stack management of
SVE-aware spill space. On Apple silicon those instructions trap with
SIGILL because non-streaming SVE isn't supported. The trap is in code
the compiler emits *before* the `smstart sm` instruction.

Even functions that *call* SME-attributed functions inherit this — the
compiler emits `rdvl` in *their* prologues for ABI compliance with
SVE-aware stack alignment. With `-march=armv9-a` (which mandates SVE2),
this is true for *every* function in the TU.

### Fix: pure inline asm + split TUs

The only workable pattern we found:

1. **SME kernels are pure inline asm.** No clang SME function attributes,
   no SME intrinsics (which use the attributes internally).
2. **SME kernels live in their own TU** compiled with
   `-march=armv9.2-a+sme2`.
3. **Driver code (`main`, harnesses) lives in a separate TU** compiled
   with `-march=armv8.6-a` (no SVE codegen at all).
4. **Inline asm clobber list must include `d0`–`d31`.** `smstart sm` /
   `smstop sm` zero the entire FP/SVE register file, including
   callee-saved `d8`–`d15`. Without these clobbers, host-side code that
   uses any FP value across the asm reads garbage. (Our first FP16 matvec
   bench showed `clock_gettime` returning `t1 = inf` until we added
   `d8`–`d15` to the clobber list.)

Minimal pattern:

```c
// kernel.c — compiled with -march=armv9.2-a+sme2
void sme_matvec_f16(const __fp16 *W, const __fp16 *x, float *y,
                    uint64_t K, uint64_t N) {
    __asm__ volatile(
        "smstart sm                                 \n"
        "ptrue p0.h                                 \n"
        // ... matvec inner loops ...
        "faddv h4, p0, z0.h                         \n"
        "fcvt s4, h4                                \n"
        "str s4, [%[y]]                             \n"
        "smstop sm                                  \n"
        :
        : [W]"r"(W), [x]"r"(x), [y]"r"(y), [K]"r"(K), [N]"r"(N)
        : "x4","x5","x6","p0","z0","z1","z2",
          "d0","d1","d2","d3","d4","d5","d6","d7",
          "d8","d9","d10","d11","d12","d13","d14","d15",
          "d16","d17","d18","d19","d20","d21","d22","d23",
          "d24","d25","d26","d27","d28","d29","d30","d31",
          "memory"
    );
}
```

```c
// main.c — compiled with -march=armv8.6-a
extern void sme_matvec_f16(const __fp16 *, const __fp16 *, float *,
                           uint64_t, uint64_t);
int main(void) { /* ... */ sme_matvec_f16(...); /* ... */ }
```

## Numbers

### FP32 outer-product (single ZA tile, latency-bound)

```
1 billion fmopa: 0.94 s → 0.55 TFLOPS FP32 (sustained)
```

Single-accumulator latency-bound at 4 cycles per fmopa. Round-robin
across 4 ZA tiles would scale toward ~2 TFLOPS (M4's published peak;
M5 likely similar). Two SME units chip-wide → ~4 TFLOPS theoretical
chip-wide ceiling.

### FP16 matvec K=N=2048

```
SME FP16 matvec, K=2048 N=2048:
  best-of-7: 0.260 ms/call
  32.2 GFLOPS,  32.3 GB/s
  verified correct vs scalar reference
```

For comparison, GPU on Lightning's path: ~16 µs/matvec. **GPU is
~16× faster**, even at single-batch decode where SME was supposed
to win.

The bottleneck is bandwidth: 32 GB/s ≈ 16-32% of CPU-side LPDDR5
ceiling (~150-200 GB/s sustained). The CPU-side ceiling itself is
fundamentally below the GPU's 546 GB/s on Apple silicon; CPU and GPU
share the memory but the GPU has wider channels.

### NVFP4 SME via LUTI4 — explored, has Apple-specific lane quirks

SME2's `LUTI4` instruction uses the ZT0 register (a 64-byte lookup
table, separate from ZA) for 4-bit dequant. In principle a perfect
fit for NVFP4 weights:

- Load 64-byte LUT into ZT0 once: `ldr zt0, [x_lut]`
- Per group: load packed nibbles, run `luti4 zd.h, zt0, zn[idx]`,
  multiply by E4M3 scale, accumulate into row sum.

LUTI4 raw throughput is ~136 G dequants/sec (effective ~273 GB/s of
FP16 produced) — far above any bandwidth concern.

**But** Apple's `LUTI4 zd.h, zt0, zn[0]` on M5 Max has unexpected lane
semantics that diverge from the textbook ARMv9.4 SME2 spec:

- Reads only the **low nibble** of input bytes.
- Reads only from **bytes 0-7 and 16-23** of `zn` (skips 8-15 and 24-31).
- Writes to **lanes 0-7 and 16-23** of `zd` (zeros 8-15 and 24-31).
- Effective: 16 valid fp16 outputs per LUTI4, from 16 specific input
  nibbles — not the 32 contiguous nibbles a naive reading suggests.

We tried single-vector (1V), 2V, and 4V (`{z0.h-z3.h}`) variants;
all show the same lane pattern. Either Apple's M5 implements a
non-standard LUTI4, or the textbook reading of the ARM ARM is wrong
for this microarchitecture. Reverse-engineering the full instruction
matrix to use it correctly was more effort than the bandwidth-bound
end result justified.

## Why SME isn't the right tool here

The bandwidth math is the wall, not compute:

| Path | Ceiling | Reality |
|---|---|---|
| GPU FP16 matvec | 546 GB/s mem | ~12 TFLOPS measured; ~16 µs at K=N=2048 |
| SME FP16 matvec | ~150 GB/s CPU mem | 0.26 ms = 32 GB/s effective |
| SME NVFP4 matvec | ~150 GB/s mem (4× less weight bytes) | ~65 µs best case (predicted) |

Even with a perfect NVFP4 LUTI4 path, SME at best closes the gap to
4× slower than GPU. Multi-core SME (parallelizing matvec rows across
P-cores) could bring it closer, but the chip-wide SME unit count is
capped at 2 — Apple shares SME hardware between core clusters.

For a CPU-only inference target (no GPU available), SME would be the
right tool. For Apple silicon with the GPU sitting right there sharing
the same memory, GPU wins.

## What's worth keeping

- The toolchain knowledge — how to compile SME code on macOS without
  hitting the streaming-SVE / SVE-attribute traps.
- Smoke files in `/tmp/sme_*.c` (not committed) document the working
  pure-asm pattern and the LUTI4 quirks.
- Confidence that Phase 3 was explored, characterized, and ruled out
  with real numbers — not predicted on theory.

## References

- `<arm_sme.h>` — ACLE SME intrinsics header (the *intrinsic* surface
  is unusable on Apple silicon for the reasons above; the assembly
  mnemonics it would emit are still useful).
- ARM Architecture Reference Manual — SME / SME2 sections (LUTI4,
  fmopa, smstart/smstop encodings).
- xnu-arm-sme.md — Apple's docs on macOS streaming-mode handling.
- Hello-SME microbenchmarks (Friedrich-Schiller-Univ. Jena) on M4
  P-cores: 2.0 TFLOPS FP32, 4.0 TOPS INT8 per SME unit.
- Apple Developer: "Determining Instruction Set Characteristics" —
  documents `sysctl hw.optional.arm.*` for runtime feature detection.
