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
- **Perf**: bf16 build 30.9 tok/s short / 27 prose; **FN_QUANT=1** (self-
  quantized NVFP4 stack via `quantize_flash_next.py`, layers 0/1/46/47 kept
  bf16) reaches **40.3 tok/s short / 37 prose** (median 25-27 ms rounds) at
  preserved quality (fixture " Paris" ✓, coherent prose). bf16 matvecs route
  through `bf16_matvec_w2` (1.35-1.8x naive per `autotune_qwen38fn.w`).
  Negative results, measured: scoped resource barriers (FN_FULLBAR A/B),
  the gdn_fused/moe_output dispatch fusions, the 2-stage fused HC mix
  (FN_HCFUSED, 2ms slower), expert pinning, and prebuilt dispatch programs
  are all ~neutral on the round.

  **Profiled decode round ledger (FN_TIME=1 + Metal System Trace, prose)**:
  GPU execution 21.4 ms/token; host = rope+ple 0.1-0.5 ms, ENCODE 17.9 ms,
  commit+wait tail 9.2 ms; the 3-way commit split overlaps most of the GPU
  behind encode, so the round floor IS the encode: ~2900 bridge calls x
  ~6 µs each (prebuilt args changed nothing — the cost is per-call bridge
  overhead, not .w-side boxing). The forward now runs a prebuilt per-layer
  step-program (ids-identical to the per-call path), which is the staging
  ground for the two structural fixes:
  1. C-side program executor (record the step list once in the runtime,
     one ccall per layer/token) — encode 18 -> ~2 ms, est. 45-55 tok/s;
  2. MTP width-n verify — the same ~2900 calls serve n tokens/round,
     dividing BOTH encode and GPU serial latency by acceptance (est. 70-90
     tok/s combined).
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

## 10-idea perf campaign scoreboard (9/1)

1. **ICB whole-token replay** — DONE, negative: encode 17.9 -> 0.85 ms
   (thesis proven) but 1191 executeCommandsInBuffer segments cost ~10 us
   each GPU-side (21 -> 34 ms). Gated FN_ICB=1. Landmine found: the
   compiler CSEs ccall wrappers with constant args (see memory).
2. MTP width-n verify + speculative decode — **LANDED, WORKING END TO END**:
   - `multi:N` gate: `forward_multi` re-decodes the serial oracle in
     width-N blocks, ids EXACT (0 mismatches at widths 1-8, 119 tokens),
     still green after every optimization below. Bit-identity rules:
     every multi kernel is an EXPRESSION-level clone of its serial twin
     (fn_phn_rope_multi re-clones per_head_norm — the 27B multi kernel's
     rsqrt / x*(rrms*w) differ in ULPs from our 1/sqrt / (x*rrms)*w;
     gdn_conv_split_multi keeps z*sigmoid(z)); the gate forces naive bf16
     matvecs + host rope on BOTH arms so summation orders agree.
   - MTP head (`FN_MTP=1` harness): native qwen4_exp head — pre-mixer
     10240 stream + emb(next), single 10240-wide RMS + per-branch
     fc_hidden + broadcast fc_embedding, one attn+MoE layer (own HCs,
     kv slot = pos-1, bf16 FUSED gate|up experts), own mixer, shared
     lm_head. **79.3% greedy draft acceptance** on fixture prose.
   - `mtp:D` speculative loop: draft D (chained: variant-1 fuses from the
     MTP layer's own h_m), verify width-(D+1), accept longest matching
     prefix + bonus token, tape-replay rollback of GDN conv/delta + PLE
     conv states from per-layer stashed inputs (~22 MB; kv self-heals),
     PLE host ctx snapshot/re-advance. Deterministic histograms.
   - Perf treatment: verify + drafts run as RECORDED programs through
     w_metal_program_run (one ccall) on a CONCURRENT encoder with scoped
     barriers mirroring the serial progs; pos scalars live in mpos_buf so
     recordings replay at any position; per-(width,ping-parity) cache.
     NVFP4 wide-rung table from the `wide` sweep: r1 at rows<=640 or n=1,
     r2 otherwise (r1 collapses at n>=3 on big rows — register pressure).
   - **QUIET-BOX RANKING (9/1, load ~4, 2 reps)**: fixture prose — plain
     41.9/43.8, FN_RUNG=1 43.5/43.4 (tie; rungs stay opt-in), mtp:2
     48.1/44.7, mtp:3 45.3/46.9, mtp:4 40.9/46.5. **Compiler-source
     prompt (500-tok prefill, the realistic case): plain 35.6 -> mtp:3
     49.4 tok/s (+39%)** — 23/35 rounds full-accept; code drafts accept
     far better than prose. Depth 3 is the default recommendation.
     Width-1 verify 30 ms vs 24 serial; marginal in-block token ~8.5 ms
     (inherent GDN serial recurrence + per-token expert stream).
   - Costs remaining: draft ~2.3 ms each (GPU+sync latency), verify fixed
     ~30 ms. Next levers: w2-multi bf16 kernel (closes the width-1 gap),
     3-way async commit split for the verify program.
   - **Acceptance is TRAJECTORY-dependent** (9/1 pm, 4-cell test on the
     compiler prompt): quant+serial-prefill fell into repetitive usage-text
     (89-94% draft-1 accept, the 49.4 tok/s run); bf16-prefill and/or
     bf16-decode trajectories generate novel content at ~60-70% accept and
     proportionally less spec gain. Both texts fully coherent — do NOT
     read an acceptance drop as a bug before diffing the generated text
     (chunked-vs-serial prefill changes the trajectory: bf16 GEMM states).
   - `mtp:adaptive` (depth self-tunes: climb after 2 full-accept rounds,
     cap 4, drop to what stuck): measured NEGATIVE so far (22.7 vs fixed-3
     41.9 same-conditions; per-width program recordings + deep-verify cost
     outrun the ~3.2-token/round ceiling of 0.79^k chain acceptance).
     Kept as a mode; revisit with cheap recordings + mixed content.
3. Device-chained decode — OPEN (GPU rope landed as its enabler).
4. **GPU rope + PLE gather** — HALF: rope on GPU (neutral, ids-identical,
   enabler for #3); table gather on GPU REVERTED — binding the 51 GB table
   makes it command-buffer-resident and thrashes the page cache into
   multi-second tokens. Host sparse gather is the correct design.
5. GEMM prefill — OPEN.
6. Small-M wide kernels — OPEN (27B kernel family identified for reuse).
7. **Quant coverage boundary** — DONE, negative: outer layers 0/1/46/47
   AND the PLE projections each flip the fixture when quantized. The
   shipped conservative set is the optimum.
8. Expert-gather tuning — OPEN. Adjacent DONE: NVFP4 matvec rung sweep
   (`autotune_qwen38fn.w nv`, 7 rungs x 9 shapes on sidecar tensors):
   the default 8-row kernel starves low-row shapes — b1r1 (2 rows/TG)
   +52% on shared gate/up 640x2560, +46% on hc down 320x10240; 16r +19%
   on 2560x6144 out-projections; everything else ties. Wired behind
   FN_RUNG=1 (also `b1`/`16r` alone), golden taps + logits BIT-IDENTICAL
   to the 8r path. Default OFF: e2e A/B was contaminated by a concurrent
   CPU-pinned workload (encode floor is host-side); re-bench on a quiet
   box before flipping the default.
9. Cross-token encode overlap — OPEN (needs #3).
10. QSA indexer + long context — **DECODE PATH LANDED (C1)**:
    qwen4_fn/qsa.metal ports Qwen4ExpTextQSAIndexer verbatim: raw index
    keys cached un-normed; complete 4-blocks mean-pooled -> k_layernorm ->
    roped at the BLOCK-START position (static once complete, incremental
    build); q layernorm+rope at the query position (first 64 dims, pairs
    (i,i+32)); relu-sum scores over 4 heads / sqrt(128); top-512 blocks
    (histogram threshold select, cut-bin ties by block order) + the
    incomplete tail; SDPA over the selected list (identical arithmetic to
    dense when the budget covers everything). Fixed grids + buffer-driven
    bounds keep every step inside the recorded programs. FN_CTX=<n> sizes
    kv/index caches (cap 262144); FN_QSA=1 forces the indexer from pos 0.
    GATES: QSA==dense ids BIT-EXACT (fixture + 500-token compiler prompt);
    FN_CTX=4096 decode from pos 500 to ~2300 crosses the boundary with
    fully coherent code (1799 tokens, 24.6 tok/s avg). C2 LANDED same
    day: indexer steps in the chunked-prefill/multi path (the qsa.metal
    kernels were written width-ready: per-token nb/vis arrays, per-query
    select TGs; the per-chunk block build covers the whole chunk while
    nb[t] preserves causality). Gates: chunked QSA == chunked dense ids
    EXACT at 500 tokens. 32k DEMO: 32,000-token compiler-source prompt
    prefilled in 7.3 min (72.9 tok/s pp), decode at pos 32k = 16.1 tok/s,
    fully coherent code continuation. 100k DEMO: 100,000-token prompt
    prefilled in 19.2 min (86.9 tok/s pp, 11.5 ms/tok), decode at pos
    100k = 12.2 tok/s (75 ms rounds, encode still 2.2 ms) — the
    continuation mimics deep-compiler idiom from 100k tokens back. Known trims: the select kernel's
    single-threaded min/max + emit passes (~2 x nb serial per layer per
    token dominate long-ctx rounds); spec decode beyond 2051 still open
    (reuse the anchor's selection across draft steps).

Standing: plain 43 short / 35.6 code-context; **mtp:3 46-49 short / 49.4 code-context (+39%)**. All gates green.

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
