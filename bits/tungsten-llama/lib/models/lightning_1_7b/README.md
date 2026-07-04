# Lightning-1.7B-mlx-nvfp4

Status: **working at 1.16× MLX decode (240 tok/s vs MLX 207).**

## Model

- HuggingFace: `bradyclarke/Lightning-1.7B-mlx-nvfp4`
- Architecture: standard Qwen3 (full_attention, no MoE)
- 28 layers, hidden=2048, head_dim=128, vocab=151936
- nvfp4 weights (E2M1, group_size=16, E4M3 fp8 scales)
- Cache: `~/.cache/huggingface/hub/models--bradyclarke--Lightning-1.7B-mlx-nvfp4/`

## Entry-point scripts

| Script | What |
|--------|------|
| `scripts/bench/bench_lightning.w` | end-to-end decode bench (8 prefill + 50 generated tokens) |
| `scripts/bench/verify_lightning.w` | single-prompt argmax verification |
| `scripts/bench/autotune_lightning.w` | TG_SIZE × kernel-variant sweep (synthetic inputs, no model load) |

Entry-points stay at `scripts/bench/` because Tungsten's `use core/X`
module resolution is script-relative — moving entry points deeper
breaks them. This dir is for reusable per-model lib code (config
constants when extracted, `forward.w` if/when extracted from the
bench, port-plan docs).

## Performance ladder (one session, 2026-04-28)

```
                                       decode tok/s    GPU µs/token   MLX ratio
                                       ────────────    ────────────   ─────────
Session start                          146.4           6527           0.71×
+ Q/K/V + gate/up matvec fusion        146.6           6452           0.71×
+ argmax fixed (TG=32 → TG=1024)       183.3           5199           0.89×
+ rms_norm fixed (TG=32 → TG=512)      231.1           3938           1.12×
+ @gpu language extension              238.5           3772           1.15×
+ autotune-confirmed final settings    239.5 (mean)    3733           1.16×
```

Full writeup: [`doc/articles/lightning-1-7b-passing-mlx.md`](../../../../../doc/articles/lightning-1-7b-passing-mlx.md).
Reference numbers in [`PERFORMANCE.md` Round 11](../../../../../PERFORMANCE.md).

## Optimal config (in bench_lightning.w)

| Component | Setting |
|---|---|
| rms_norm | TG=512 (16 simdgroups), `tg_sum` reduction |
| argmax | TG=1024 (32 simdgroups), `tg_max`+`tg_min` reduction |
| nvfp4 matvec | `nvfp4_matvec_mlx` variant (8 rows/TG, 64 threads) |
| Q/K/V projection | fused single dispatch |
| gate/up projection | fused single dispatch |
| KV cache | bf16 (halves attention BW) |
| SDPA | `sdpa_vector_bf16` fused (1024 thr/TG, online softmax) |
| Argmax/lm_head | GPU-side, only 1 i32 reads back per token |
| Weight load | zero-copy `mmap.view_at` → `metal_buffer_for` |
