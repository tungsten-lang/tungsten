# qwen3.6/35b-a3b-nvfp4

Status: **kernel-tuned, no inference path yet.**

## Model

- HuggingFace: `mlx-community/Qwen3.6-35B-A3B-nvfp4`
- Architecture: `Qwen3_5MoeForConditionalGeneration` (`qwen3_5_moe`)
- Cache (already pulled, ~20 GB):
  - `~/.cache/huggingface/hub/models--mlx-community--Qwen3.6-35B-A3B-nvfp4/snapshots/<sha>/`
  - 4 safetensors shards + config.json + tokenizer
- Also available via ollama as `qwen3.6:35b-a3b-nvfp4` (~20 GB blobs)

See [config.w](config.w) for the full architecture spec extracted from the
on-disk config.json.

## Why no inference path

Per the architecture audit (2026-04-28):
- **Mamba/SSM (linear_attention) layers**: 30 of 40 layers. The
  selective_scan kernel has no analog in tungsten-llama; it's a
  sequential scan recurrence (`h[t] = A·h[t-1] + B·x[t]; y[t] = C·h[t]`)
  that's hard to parallelize across time but parallel across heads/state-dims.
- **Dual MoE**: shared expert + 256 routed experts, top-8 per token. The
  existing tungsten-llama MoE kernels (`q8_moe_gate_up_8`, `q8_moe_silu_down_8`,
  `moe_combine_8_*`) are designed for qwen3's single-MoE-128-experts shape;
  256 experts + a parallel shared expert means new kernels and a new
  router (`router_topk_8` would need to be `router_topk_8_of_256`).
- **Per-head attention output gate**: NEW vs Lightning/qwen3 — there's a
  per-head gate applied to the attention output before o_proj. Confirmed
  via tensor-shape inspection: `q_proj.weight` is `[8192, 2048]` (8192 =
  16 heads × 256 head_dim × 2 — Q vector + gate signal stacked).
- **head_dim=256**: 2× Lightning's 128. Affects per_head_norm, attn
  kernel register pressure.

## Quantization formats — TWO schemes coexist

Confirmed end-to-end against MLX's `mx.dequantize` (2026-04-29):

| Format | Tensors | Spec |
|---|---|---|
| **nvfp4** (existing) | 432 tensors (all bulk weights — experts, shared expert FFN, attention projections, embed/lm_head) | 4-bit E2M1, group_size=16, fp8 (E4M3) scales, NO biases. `dequant = scale_e4m3 * fp4_table[nibble]` |
| **int8 affine** (NEW) | 80 tensors (`mlp.gate` + `mlp.shared_expert_gate` per layer × 40) | 8-bit unsigned, group_size=64, BF16 scales + BF16 biases. `dequant = scale * uint8(byte) + bias` |

Layout of an int8-affine tensor (`mlp.gate.weight` shape `[N=256, K_u32=512]`,
where `K = K_u32 × 4 = 2048` weights/row):

```
weight: U32[N, K/4]   — 4 little-endian uint8 packed per u32
                         byte 0 = (u32 >> 0) & 0xFF
                         byte 1 = (u32 >> 8) & 0xFF
                         ...
scales: BF16[N, K/64] — one per 64-element group along K
biases: BF16[N, K/64] — one per 64-element group along K
```

Per-element: `w_dequant[n, k] = scales[n, k/64] * uint8(weight_byte[n, k]) + biases[n, k/64]`.

Verified manually: weight u32 `0x99744f60` at `[0,0]` decodes to bytes
`(96, 79, 116, 153)`. With `scale=0.00051116943359375, bias=-0.0654296875`:
- `0.00051... * 96 + (-0.06543...) = -0.01636` ✓ matches MLX
- `0.00051... * 153 + (-0.06543...) = 0.01278` ✓ matches MLX

The bias absorbs the offset — typically a per-group "zero point" but
stored as the full `−scale × zero_point` precomputed.

**Why MLX uses 8-bit affine here**: router (`mlp.gate`) and
`shared_expert_gate` are low-rank, sensitivity-critical projections.
Router output picks 8 of 256 experts via top-K; small precision loss
can change which experts get activated, cascading into much bigger
output errors. 8-bit affine preserves fidelity at marginal memory cost
(router is 256×2048 = ~0.5M params per layer, vs the 256-expert MoE at
~393M params per layer).

**Implementation needed**: `nvfp4_matvec` won't work for these — needs
a new `int8_affine_matvec.metal` kernel:
```
# Inner loop sketch (each lane handles K/TG_SIZE elements):
group_idx = k / 64
scale = scales[m, group_idx]
bias  = biases[m, group_idx]
byte  = (weight[m, k/4] >> (8 * (k % 4))) & 0xFF
w_dq  = scale * float(byte) + bias
acc  += w_dq * x[k]
```

`bits/tungsten-llama/lib/sharded_safetensors.w` already loads these
correctly (raw u32 / bf16 buffers); only the matvec kernel is missing.

Estimated effort: **~2 weeks of porting** (selective_scan kernel is the
biggest unknown; the rest is mostly adapt-existing-kernel work).

## Kernel tuning (already complete)

`scripts/bench/autotune_qwen36.w` runs synthetic-input sweeps at
qwen3.6's dimensions. Findings on M3 Max:

```
kernel              shape                            best TG    µs/call
──────────────      ──────────────────────           ───────    ───────
rms_norm            HIDDEN=2048                      1024       7.77
argmax              N_VOCAB=248320                   1024       66.8
attn_softmax        n_pos=4096 (long context)        1024       3.67
attn_scores         head_dim=256, decode             32         5.07
nvfp4 matvec        K=2048, N=2048 (q_proj-shape)    nvfp4_matvec_mlx (5.6 µs/call from Lightning autotune)
```

In-isolation findings — bench-level may differ due to concurrent-encoder
dynamics (see PERFORMANCE.md Round 11). The Lightning experience showed:
- rms_norm autotune-best (TG=1024 in isolation) is close to but slightly
  worse than bench-best in-context due to barrier-drain cost — picking
  TG=512 or 1024 likely both fine.
- argmax autotune-best transfers cleanly to the bench (terminal kernel,
  no concurrent overlap to compete with).
- attn_scores TG=32 confirms the cooperative kernel's single-simdgroup
  dispatch is right at this head_dim.

**Argmax at vocab=248K hits Apple's 1024-thread/TG ceiling at 67 µs/call**
— each lane scans 242 elements. To go faster, would need a 2-pass
kernel (multiple TGs compute partial maxes into a scratch buffer; one
final TG reduces). Worth ~30-50% per-call savings for vocab > ~200K.

## Path forward

When porting, consume in this order:

1. **Tokenizer + config loader** — read MLX safetensors snapshot
   (already supported via `bits/tungsten-llama/lib/safetensors.w`),
   parse this dir's `config.w` constants, set up dimensions.
2. **Layer-type dispatch** — read `text_config.layer_types` to route
   each layer to either `forward_full_attention` or `forward_linear_attention`.
3. **Full attention layer** (10 layers) — adapt Lightning's qwen3
   forward_step. Differences:
   - head_dim=256 (kernel TG sizes already validated above)
   - per-head output gate (new gate kernel needed)
   - Apply autotune-best dispatch shapes from the table above.
4. **Mamba/SSM layer** (30 layers) — write `selective_scan.metal`.
   Reference: `mamba_ssm` or MLX's `mlx-lm/models/mamba.py` for the
   recurrence math. Apple GPU advantage: 32 simdgroups can compute
   parallel per-state-dim chains within a sequence.
5. **Router for 256 experts + shared expert** — adapt `router_topk_8.w`
   for 256-expert vocab, add the shared-expert path.
6. **MoE forward** — fuse with existing `q8_moe_gate_up_8` / `_silu_down_8`
   variants if they generalize; otherwise write nvfp4 versions.
7. **Bench + verify scripts** at `scripts/bench/{bench,verify}_qwen36.w`,
   use this dir's `config.w`.

## Files

| Path | What |
|------|------|
| `config.w` | architecture constants extracted from config.json |
| `README.md` | this file (status, port plan) |
| `../../kernels/nvfp4/` | nvfp4 matvec kernels (already proven on Lightning) |
| `../../kernels/shared/` | shared @gpu-emitted kernels (rms, argmax, attn_*, etc.) |
| `scripts/bench/autotune_qwen36.w` | synthetic-input kernel sweep at qwen3.6 dimensions |
