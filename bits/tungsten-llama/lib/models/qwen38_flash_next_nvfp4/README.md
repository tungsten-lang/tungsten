# Qwen3.8-Flash-Next (qwen4_exp) — NVFP4

Alibaba's 2026-08-26 release previewing the Qwen4 architecture. 125B total /
6B active + 51B fp8 n-gram embeddings. Checkpoint:
`RadixArk/Qwen3.8-Flash-Next-NVFP4` (ModelOpt NVFP4, group 16), prepared by

```sh
hf download RadixArk/Qwen3.8-Flash-Next-NVFP4
python3 scripts/bench/prepare_flash_next.py
python3 bits/tungsten-llama/scripts/tokenizer_pack.py \
  ~/.cache/tungsten/qwen38-flash-next-nvfp4/tokenizer.json \
  ~/.cache/tungsten/qwen38-flash-next-nvfp4/tokenizer.json.bin
```

Weights land in `~/.cache/tungsten/qwen38-flash-next-nvfp4/` as symlinks plus
three synthesized manifests (`index.slim.json`, `experts_manifest.json`,
`ple_manifest.json` — see the prep script header).

## Architecture vs Qwen3.8-27B (the working port this one clones)

Same bones: 3:1 GatedDeltaNet : full-attention interval, identical GDN head
geometry (16 K-heads / 48 V-heads / 128-dim, conv 4), head_dim 256 with
25% NeoX partial RoPE (theta 1e7), fused q_proj = Q + sigmoid output gate,
per-head q/k RMS norms. Differences, in decreasing order of implementation
weight:

| # | New thing | Shape facts |
|---|---|---|
| 1 | **4-branch hyper-connection residual** (`hc_count 4`): the residual stream is 4x2560 = 10240 f32. Every sublayer reads a dynamically mixed 2560 view and writes back through per-branch injection gates; low-rank (320) dynamic mixers. | per sublayer: `input_mix_weight_down [320,10240]`, `input_mix_weight_up [10240,320]`, `block_inject_weight [4,10240]`, `hc_norm [10240]`; global `hyper_connection_mixer.*` |
| 2 | **MoE 512 experts, top-10** + always-on shared expert with sigmoid gate. Routed experts are the ONLY NVFP4 tensors (gate/up `[640,2560]`, down `[2560,640]`, group 16, per-expert `weight_scale_2`). Router `mlp.gate [512,2560]` bf16. | experts sharded 4 files/layer x 128 experts, string-sorted slot order (see manifest) |
| 3 | **PLE n-gram embeddings** at layer 2 only: 16 hash heads (8 per n-gram order) x 160 dims; 51.2GB fp8 table (128 shards x [2500012,160]) — mmapped, gathered per token (2.5KB/token), never GPU-resident. | `ple.{key_proj [10240,2560], value_proj [2560,2560], conv1d [10240,1,4], norm_conv/key/query [10240]}`, hash constants in `ple_manifest.json` |
| 4 | **QSA sparse attention** (lightning indexer, budget 2048, 4x compression): `indexer.index_qk_proj [640,2560]` = 4 q-heads x 128 + 1 k x 128. At seq <= 2048 top-2048 selection is the whole context, so dense SDPA is exact and v1 skips the indexer entirely (MAX_POS guard enforces this). | |
| 5 | **2 KV heads** (GQA 12) instead of 4; hidden 2560 vs 5120; 48 layers vs 64. | k/v_proj `[512,2560]` |
| 6 | **mrope** (interleaved, sections [11,11,10]) — for text-only input all three position streams are equal and it reduces to standard partial RoPE. | |
| 7 | **MTP head**: one full-attention layer with its OWN bf16 512-expert MoE (`gate_up_proj [512,1280,2560]`, `down_proj [512,2560,640]`) + hyper-connections; `fc_embedding`/`fc_hidden [2560,2560]` instead of the 27B's single fc. Phase 2. | |
| 8 | Vision tower (27 blocks) — ignored, text-only port. | |

## Memory / perf model (M5 Max 128GB)

GPU-resident: ~67GB NVFP4 experts (mmap) + ~9GB bf16 backbone/embed/lm_head.
Host-only: 51GB PLE table (mmap, sparse row gather). MTP +5.6GB when enabled.

Decode reads/token (v1, bf16 non-expert weights): GDN 36x115MB + attn 12x100MB
+ HC 96x13MB + shared experts 0.5GB + 10 routed experts 48x28MB + router
+ lm_head 1.27GB ~= **9.7GB/token** → ~20 tok/s bandwidth bound. The follow-up
that matters: weight-only NVFP4 of GDN/attention/lm_head/HC mixers
(~3.5GB/token, 55-70 tok/s). RadixArk left those bf16 for accuracy, so any
self-quantization must re-run the parity + smoke gates.

## Status (2026-08-31): WORKING, parity-exact

- **Parity**: engine matches `flash_next_ref.py` (numpy, itself validated by
  predicting 11751 " Paris" on the fixture) at **~4e-7 rel across all 48
  layers and logits** (`check_fn_parity.py`). Greedy 240-token prose
  continuation is fluent.
- **Perf**: 30.9 tok/s decode short-context / 28.4 at pos ~450 (concurrent,
  median 32-35 ms rounds). bf16 matvecs route through `bf16_matvec_w2`
  (2 rows/simdgroup, ushort4), measured 1.35-1.8x the naive kernel per
  shape by `autotune_qwen38fn.w`.
- **Expert routing skew** (628-token prose, `expert-hist` mode): per-layer
  top-20% of experts = **85.5%** of activations (top-10% 64.4%, Gini 0.81;
  layer 0 flattest at 69.9%). `pin:<N>` wires the per-layer top-N into a
  private overlay (bit-exact); **measured NEUTRAL on this 128GB box** (35-36
  ms both arms) because the whole expert set is page-cache resident — keep it
  for smaller-RAM targets or cache-pressure regimes, don't re-test here.

### Checkpoint gotchas found (will bite any other engine too)

1. **Unpadded safetensors headers** in `model-bf16-00001/00010` and
   `model-plefp8-00009`: data sections start at odd offsets → GPU `ushort`
   loads undefined (NaNs from layer 0). `prepare_flash_next.py` materializes
   header-padded copies.
2. Expert regions inside each shard are laid out in **string-sorted**
   global-id order (`0,1,10,100,...`), so quarter-0 files need a slot
   permutation (in `experts_manifest.json`).
3. Quarter files have different header sizes; bind buffers at each file's
   own `data_start` and keep kernel offsets data-relative.
4. `ple_layer_ids: [2]` is one-indexed → PLE lives at 0-based layer 1.
5. GDN l2norm eps sits INSIDE the sum: the mean-domain eps must be
   `EPS/128`, or the recurrent state drifts ~1e-3 by mid-stack and flips
   router top-k choices.

## Next (ranked by research + measurement)

1. **MTP speculative decode** — community-measured 1.4-1.7x on Apple
   silicon. Rules that matter: run the HC combiner per-stream on the 10240
   state before the MTP layer (mean-pooling first collapses acceptance),
   p-min gate ~0.7 depth 2-3, quantize the MTP head's bf16 MoE.
2. **Self-quantize the bf16 stack to NVFP4** (GDN/attention/lm_head/HC:
   ~8.4 GB/token -> ~2.4) — needs a quantizer + re-run of the parity and
   fixture gates; community evals say experts-only-4bit is quality-parity,
   attention/GDN 8-bit is safe, 4-bit needs care on layers 0/1/46/47.
3. Fuse the hyper-connection mix chain (96x/token, SGLang measured ~2x
   kernel-level, +7.6% e2e) and the gate+up gather pair.
4. QSA indexer + `MAX_POS` beyond 2051 (needs sdpa threadgroup-scores
   rework too); dense is exact below that.
