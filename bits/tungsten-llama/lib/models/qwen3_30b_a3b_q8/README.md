# qwen3:30b-a3b-q8_0

Status: **inference path exists; @gpu tg_* learnings applied to dispatch shapes
(unverifiable without the model on this machine).**

## Model

- ollama: `qwen3:30b-a3b-q8_0` (~30 GB GGUF blob, not currently pulled on this dev machine)
- Architecture: Qwen3 MoE (full_attention + 128 experts, top-8)
- 48 layers, hidden=2048, head_dim=128, vocab=151936
- Q8_0 quantization (block of 32 i8 values + 1 f16 scale)
- Path when pulled:
  - `/Users/erik/.ollama/models/blobs/sha256-ae354763fe478c790125fb993e59bb1266655b3fa721eebe4a931660c3ed2ce9`

## Entry-point scripts

| Script | What |
|--------|------|
| `scripts/bench/generate.w` | end-to-end decode bench |
| `scripts/bench/verify_paris.w` | single-prompt argmax verification (expects token id 12095 = " Paris") |

## Latest dispatch-shape changes (committed 2026-04-28, unverified)

The same @gpu tg_* primitive learnings from Lightning were applied to
the qwen3-30b dispatch shapes in `scripts/bench/{generate,verify_paris}.w`:

- `rms_norm`: TG=32 → TG=512 (5 sites in generate.w, 3 in verify_paris.w)
- `argmax`: TG=32 → TG=1024 (2 sites in generate.w, 1 in verify_paris.w)
- `attn_scores` + `attn_weighted_sum` dispatch contract update
  (was 1 thread per cell via `metal_dispatch_n`; now 1 TG per cell
  via `metal_dispatch_groups(..., n_cells, 32)` matching the new
  cooperative-tg_sum kernel signature)

Pre-fix decode was ~43.5 tok/s. Expected post-fix: significant
improvement, mirroring Lightning's wins (Lightning had 28 layers ×
2 rms calls + 1 final = 57; qwen3-30b has 48 × 2 + 1 = 97, so the
rms_norm fix alone should save more ms/token in absolute terms).

To verify and bench:

```bash
ollama pull qwen3:30b-a3b-q8_0   # ~30 GB
bin/tungsten compile scripts/bench/verify_paris.w
codesign --force -s - scripts/bench/verify_paris.wc
scripts/bench/verify_paris.wc          # expects argmax = 12095 (" Paris")

bin/tungsten compile scripts/bench/generate.w
codesign --force -s - scripts/bench/generate.wc
scripts/bench/generate.wc              # was ~43.5 tok/s decode pre-fixes
```

## Untouched MoE matvec kernels

The MoE-specific q8 matvec kernels (`q8_matvec_coop_v2`, `_v4`,
`q8_matvec_expert_v3`, `q8_matvec_gate_up_expert_v3`,
`q8_moe_gate_up_8`, `q8_moe_silu_down_8`) are hand-rolled MSL, not
@gpu source. They weren't touched in the Lightning round. The
autotune harness (see `scripts/bench/autotune_lightning.w`)
generalizes — could be adapted to sweep these for TG_SIZE × variant
once the model is available.
