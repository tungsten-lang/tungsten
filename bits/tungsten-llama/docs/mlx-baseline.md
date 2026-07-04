# MLX baseline — Qwen3.6-35B-A3B-nvfp4

**Date:** 2026-04-24.
**Hardware:** Apple M3 Max, 64 GB unified memory.
**Models tested:**
- `mlx-community/Qwen3.6-35B-A3B-nvfp4` (MLX 0.31.2, mlx-lm 0.31.3)
- `qwen3.6:35b-a3b-nvfp4` (ollama, llama.cpp backend)

## Headline numbers

| Runtime | Decode (5p/50g) | Decode (512p/128g) | Prefill (512p) | Peak mem |
| ------- | --------------- | ------------------ | -------------- | -------- |
| MLX     | **96.8 tok/s**  | 90.8 tok/s         | **1259 tok/s** | 20.2 GB  |
| ollama  | 85.7 tok/s      | 82 tok/s           | 164 tok/s      | ~21 GB   |

For reference, our current tungsten-llama on the older `qwen3:30b-a3b-q8_0`
hits **43.5 tok/s** decode (different model, different quant).

## Effective memory bandwidth

- MLX nvfp4:    ~145 GB/s  (96.8 tok/s × 1.5 GB/token of weights)
- ollama nvfp4: ~130 GB/s
- tungsten Q8:  ~130 GB/s

M3 Max LPDDR5 peak is ~400 GB/s. All three runtimes are at 30-40% of
peak. MLX has the most headroom utilization on the same data.

## Where MLX dominates

**Prefill: 7.7× faster than ollama** (1259 vs 164 tok/s). Apple's
`simdgroup_matrix` intrinsics + their batched matmul kernels are
vastly more efficient at multi-token prompt processing than any
hand-rolled per-token approach. This is the area where Tungsten is
~660× behind MLX on prefill (1.9 vs 1259 tok/s).

## nvfp4 quantization layout

Decoded from the safetensors:

- 4 bits per weight, group_size = 16 (16 weights share one scale)
- Packed: 8 weights per uint32, 32 uint32s = 256 weights per row chunk
- Scale: 1 uint8 per group (fp8 E4M3 microscaling)
- Total: 9 bytes per 16 weights = 0.5625 bytes/weight
  (vs Q8_0 at 1.0625 bytes/weight — about 1.9× less bandwidth)

### Tensor shapes (qwen3.6-35b-a3b)

```
self_attn.q_proj.weight: (8192, 256)  uint32   = 8192 × 2048 nvfp4 weights
self_attn.q_proj.scales: (8192, 128)  uint8    = 8192 × 128 fp8 scales

switch_mlp.down_proj.weight: (256, 2048, 64) uint32  = 256 experts × 2048 × 512 nvfp4 weights
switch_mlp.down_proj.scales: (256, 2048, 32) uint8   = 256 experts × 2048 × 32 fp8 scales
```

## Architecture deltas vs Qwen3-30B-A3B

The Qwen3.5/3.6 family is a substantial change from Qwen3:

1. **Hybrid attention** — some layers use standard `self_attn`,
   others use `linear_attn` (Mamba/SSM-style with `A_log`, `conv1d`,
   `dt_bias`, selective_scan op). New op family.
2. **Dual MoE** — `switch_mlp` (sparse routed, like Qwen3's
   ffn_*_exps) PLUS an always-on `shared_expert` with its own gate.
3. **More experts** — 256 vs 128 in Qwen3-30B-A3B.
4. **Multimodal** — `vision_tower` for image/video. Can skip for
   text-only inference.

## Implications for next direction

If we want Tungsten to be competitive on this model:

- **nvfp4 dequant kernel** — straightforward, ~3 days. Adds bit-unpack
  + fp8 scale. Same matvec shape as our Q8 kernels.
- **Linear attention kernel** — selective_scan SSM op, completely new.
  ~1 week.
- **Shared expert + dual routing** — extends the existing 8-expert
  pattern. ~2 days.
- **Batched prefill kernel + matrix intrinsics** — the biggest gap to
  MLX. ~1 week.

Total: ~3-4 weeks to get a feature-complete port of Qwen3.6 in
Tungsten. Decode tok/s would likely land in the 80-95 range (close to
or matching MLX). Prefill would need the full matmul stack.
