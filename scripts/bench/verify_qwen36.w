# End-to-end forward pass for qwen3.6/35b-a3b, ollama-fetched MLX weights.
#
# Goal: prefill prompt "The capital of France is" (token ids
# [760, 6511, 314, 9338, 369]) through all 40 layers, take argmax of
# the last position's logits, expect token id 11751 (" Paris").
#
# Architecture: 40 layers = 30 linear_attention (Mamba/GatedDeltaNet)
# + 10 full_attention (every 4th: 3, 7, 11, …, 39). Dual MoE per layer
# (256 routed experts top-8 + always-on shared expert with sigmoid gate).
#
# Quantization of `ollama pull qwen3.6:35b-mlx` (differs from the original
# mlx-community nvfp4 export this harness first targeted):
#   - nvfp4 (U32 packed + U8 .weight.scale, group_size 16): MoE experts,
#     shared-expert swiglu, attention q/k/v/o_proj, Mamba qkv/z/out_proj.
#   - BF16: embed_tokens, lm_head, MoE router (mlp.gate), shared_expert_gate,
#     Mamba in_proj_a / in_proj_b, plus all the norms.
# The bf16 paths use shared/bf16_embedding_lookup.metal + shared/bf16_matvec.metal;
# `.scales` names resolve to `.weight.scale` via ShardedSafetensors#resolve_name.
#
# Stage 0 prints an embedding smoke sample; Stage 3 runs the full 40-layer
# prefill + a short greedy generation.

use core/metal
use tungsten-llama/sharded_safetensors

QWEN36_PATH = "/Users/erik/.cache/tungsten/qwen36-mlx/model.safetensors.index.json"
NVFP4_DIR   = "bits/tungsten-llama/lib/kernels/nvfp4/"
SHARED_DIR  = "bits/tungsten-llama/lib/kernels/shared/"
Q36_DIR     = "bits/tungsten-llama/lib/kernels/qwen3_6/"

HIDDEN   = 2048
N_VOCAB  = 248320

# Mamba dims
HK      = 16
HV      = 32
DK      = 128
DV      = 128
Q_DIM   = HK * DK     # 2048
K_DIM   = HK * DK     # 2048
V_DIM   = HV * DV     # 4096
QKV_DIM = Q_DIM + K_DIM + V_DIM    # 8192 = conv_dim
EPS     = ~0.000001

# MoE dims
EXPERT_FFN          = 512
SHARED_FFN          = 512
N_EXPERTS           = 256
TOP_K               = 8
PER_EXPERT_W_BYTES  = EXPERT_FFN * (HIDDEN / 8) * 4    # 524288
PER_EXPERT_S_BYTES  = EXPERT_FFN * (HIDDEN / 16)       # 65536
PER_EXPERT_DW_BYTES = HIDDEN * (EXPERT_FFN / 8) * 4    # 524288
PER_EXPERT_DS_BYTES = HIDDEN * (EXPERT_FFN / 16)       # 65536

device = metal_device()
queue  = metal_queue(device)

<< "loading qwen3.6/35b-a3b-nvfp4 sharded safetensors..."
# ShardedSafetensors is defined `in Tungsten:Llama`; the evolved compiler only
# resolves a bare namespaced class name from inside a method of a class in that
# same namespace, not from a top-level script statement. Use the fully-qualified
# name so the class resolves here (see milestone-1 diagnosis).
st = Tungsten:Llama:ShardedSafetensors.new(QWEN36_PATH)
<< "  total tensors: " + st.count().to_s

# ---- Pipelines ----
# ollama's MLX qwen3.6 export keeps embed_tokens / lm_head / the MoE router /
# the shared-expert gate in BF16 (not nvfp4 + scales), so those paths use the
# bf16 kernels below. The MoE experts + attention projections stay nvfp4.
bf16_embed_pipe  = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "bf16_embedding_lookup.metal")), "bf16_embedding_lookup")
bf16_matvec_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "bf16_matvec.metal")), "bf16_matvec")

# ---- Embedding tensor (zero-copy mmap → MTLBuffer). BF16 [N_VOCAB, HIDDEN]. ----
ew_d = st.tensor("language_model.model.embed_tokens.weight")
ew_v = st.mmap_for("language_model.model.embed_tokens.weight").view_at(ew_d[:byte_offset], :u8, ew_d[:byte_length])
embed_w_buf = metal_buffer_for(device, ew_v)
<< "  embed table: " + (ew_d[:byte_length] / 1024 / 1024).to_s + " MB bf16"

x_buf = metal_buffer(device, HIDDEN * 4)

# ---- Helper: gather one bf16 embedding row into x_buf ----
-> embed_token(token_id)
  metal_batch_begin(queue)
  metal_dispatch_n(queue, bf16_embed_pipe, [embed_w_buf, x_buf, token_id, HIDDEN], HIDDEN)
  metal_batch_commit(queue)

-> show_embed(label, token_id)
  embed_token(token_id)
  s = ""
  i = 0
  while i < 8
    s = s + metal_buffer_read_f32(x_buf, i).to_s + " "
    i = i + 1
  << "  " + label + "[0..8] = " + s

# ---- Stage 0: bf16 embedding lookup smoke ----
<< ""
<< "=== Stage 0: bf16 embedding lookup ==="
show_embed("emb[369]", 369)
show_embed("emb[760]", 760)

# =============================================================
# Shared setup for the forward pass: kernel pipelines, RoPE-free
# per-head-norm scale buffers, and the bf16 / nvfp4 weight loaders.
# =============================================================

rms_pipe       = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "rms_norm.metal")), "rms_norm")
nvfp4_mlx_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR  + "nvfp4_matvec_mlx.metal")), "nvfp4_matvec_mlx")
copy_pipe      = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "copy_f32_slice.metal")), "copy_f32_slice")
phn_pipe       = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "per_head_norm.metal")), "per_head_norm")
add_pipe       = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "residual_add.metal")), "residual_add")
conv_pipe      = metal_pipeline(metal_compile_source(device, read_file(Q36_DIR    + "conv1d_depthwise_step.metal")), "conv1d_depthwise_step")
g_pipe         = metal_pipeline(metal_compile_source(device, read_file(Q36_DIR    + "compute_g.metal")), "compute_g")
step_pipe      = metal_pipeline(metal_compile_source(device, read_file(Q36_DIR    + "gated_delta_step.metal")), "gated_delta_step")
rng_pipe       = metal_pipeline(metal_compile_source(device, read_file(Q36_DIR    + "rms_norm_gated.metal")), "rms_norm_gated")

inv_scale_k = ~1.0 / Math.sqrt(~0.0 + DK)
q_scale = inv_scale_k * inv_scale_k
k_scale = inv_scale_k
q_w_buf = metal_buffer(device, DK * 4)
k_w_buf = metal_buffer(device, DK * 4)
i = 0
while i < DK
  metal_buffer_write_f32(q_w_buf, i, q_scale)
  metal_buffer_write_f32(k_w_buf, i, k_scale)
  i = i + 1

-> load_bf16(name, n_elements, dst_buf)
  d = st.tensor(name)
  m = st.mmap_for(name)
  i = 0
  while i < n_elements
    off = d[:byte_offset] + i * 2
    bits = m.byte_at(off + 0) | (m.byte_at(off + 1) << 8)
    metal_buffer_write_i32(dst_buf, i, bits << 16)
    i = i + 1

-> load_nvfp4_part(name)
  d = st.tensor(name)
  v = st.mmap_for(name).view_at(d[:byte_offset], :u8, d[:byte_length])
  metal_buffer_for(device, v)

# =============================================================
# Stage 3: end-to-end forward — prefill 5 tokens, argmax = 11751
# =============================================================
# Architecture:
#   40 layers, layer_type = "mamba" if (li % 4 != 3) else "full_attn"
#   (full_attn at indices 3, 7, 11, …, 39 — every 4th)
#   Each layer: x = x + attn_or_mamba(input_layernorm(x))
#               x = x + moe(post_attention_layernorm(x))
#   Final:      x = final_norm(x); logits = lm_head(x); pred = argmax
#
# State persistence (per token, recurrent):
#   Mamba layers: conv_state (3 × QKV_DIM f32) + ssm_state (HV*DV*DK f32),
#                 ping-ponged across token steps.
#   Full_attn:    KV cache (MAX_POS × KV_DIM f32 each for K and V).
#
# RoPE: qwen3.6 uses partial NeoX rotation (rotary_dim=64 of head_dim=256).
# At pos=0 RoPE is identity, so no need for full_attn at first token.

# ---- Constants for full_attn ----
N_HEADS_ATTN = 16
HEAD_DIM     = 256
N_KV_HEADS   = 2
GQA_GROUP    = N_HEADS_ATTN / N_KV_HEADS  # 8
KV_DIM       = N_KV_HEADS * HEAD_DIM       # 512
QFULL_DIM    = N_HEADS_ATTN * HEAD_DIM * 2 # 8192 (q + gate stacked)
ATTN_OUT_DIM = N_HEADS_ATTN * HEAD_DIM     # 4096
ATTN_SCALE   = ~1.0 / Math.sqrt(~0.0 + HEAD_DIM)
ROT_DIM      = 64
ROT_DIM_HALF = ROT_DIM / 2                 # 32
ROPE_BASE    = ~10000000.0                 # qwen3.6 rope_theta = 1e7
MAX_POS      = 64
N_LAYERS     = 40

# ---- Additional pipelines for full_attn + final ----
split_pipe   = metal_pipeline(metal_compile_source(device, read_file(Q36_DIR + "split_q_gate.metal")), "split_q_gate")
sdpa_pipe    = metal_pipeline(metal_compile_source(device, read_file(Q36_DIR + "sdpa_vector_hd256.metal")), "sdpa_vector_hd256")
aog_pipe     = metal_pipeline(metal_compile_source(device, read_file(Q36_DIR + "attn_output_gate.metal")), "attn_output_gate")
prope_pipe   = metal_pipeline(metal_compile_source(device, read_file(Q36_DIR + "partial_rope_neox.metal")), "partial_rope_neox")
sigmoid_pipe = metal_pipeline(metal_compile_source(device, read_file(Q36_DIR + "sigmoid_inplace.metal")), "sigmoid_f32")
gu_pipe      = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_gu.metal")), "nvfp4_matvec_mlx_gu")
silu_sd_pipe = metal_pipeline(metal_compile_source(device, read_file(Q36_DIR + "nvfp4_matvec_silu_score_residual.metal")), "nvfp4_matvec_silu_score_residual")
topk_pipe    = metal_pipeline(metal_compile_source(device, read_file(Q36_DIR + "router_softmax_topk8.metal")), "router_softmax_topk8")
silu_bs_pipe = metal_pipeline(metal_compile_source(device, read_file(Q36_DIR + "nvfp4_matvec_silu_bufscore_residual.metal")), "nvfp4_matvec_silu_bufscore_residual")
silu_sr_pipe = metal_pipeline(metal_compile_source(device, read_file(Q36_DIR + "nvfp4_matvec_silu_score_replace.metal")), "nvfp4_matvec_silu_score_replace")
sum8_pipe    = metal_pipeline(metal_compile_source(device, read_file(Q36_DIR + "sum8_into.metal")), "sum8_into")
argmax_pipe  = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "argmax.metal")), "argmax")

# ---- Discover layer types ----
layer_types = []
li = 0
while li < N_LAYERS
  k = "language_model.model.layers." + li.to_s + ".linear_attn.A_log"
  if st.has?(k) then layer_types.push("mamba") else layer_types.push("full_attn")
  li = li + 1
n_mamba = 0
n_full = 0
li = 0
while li < N_LAYERS
  if layer_types[li] == "mamba" then n_mamba = n_mamba + 1 else n_full = n_full + 1
  li = li + 1
<< ""
<< "=== Stage 3: layer-type map: " + n_mamba.to_s + " mamba + " + n_full.to_s + " full_attn ==="

# ---- Pre-load weight handles for all 40 layers ----
# Each entry is a dict containing the per-layer weight buffer handles.
# nvfp4 weights are zero-copy mmap views; bf16 norms get an upload to f32.
<< "preloading 40 layers (this opens mmap views; first touch lazy-pages weights)..."
layers = []
li = 0
while li < N_LAYERS
  prefix = "language_model.model.layers." + li.to_s + "."
  if (li % 8) == 0 then << "  layer " + li.to_s + " (" + layer_types[li] + ")"

  # Common: input_layernorm.weight (BF16 [HIDDEN])
  in_norm_buf = metal_buffer(device, HIDDEN * 4)
  load_bf16(prefix + "input_layernorm.weight", HIDDEN, in_norm_buf)
  # Common: post_attention_layernorm.weight (BF16 [HIDDEN])
  post_norm_buf = metal_buffer(device, HIDDEN * 4)
  load_bf16(prefix + "post_attention_layernorm.weight", HIDDEN, post_norm_buf)

  if layer_types[li] == "mamba"
    # Mamba weights
    qkv_w = load_nvfp4_part(prefix + "linear_attn.in_proj_qkv.weight")
    qkv_s = load_nvfp4_part(prefix + "linear_attn.in_proj_qkv.scales")
    z_w   = load_nvfp4_part(prefix + "linear_attn.in_proj_z.weight")
    z_s   = load_nvfp4_part(prefix + "linear_attn.in_proj_z.scales")
    # in_proj_a / in_proj_b are BF16 [HV, HIDDEN] in the ollama MLX export
    # (not nvfp4) — zero-copy mmap, matvec via bf16_matvec_pipe.
    a_w   = load_nvfp4_part(prefix + "linear_attn.in_proj_a.weight")
    b_w   = load_nvfp4_part(prefix + "linear_attn.in_proj_b.weight")
    conv_w_buf = metal_buffer(device, QKV_DIM * 4 * 4)
    load_bf16(prefix + "linear_attn.conv1d.weight", QKV_DIM * 4, conv_w_buf)
    a_log_buf   = metal_buffer(device, HV * 4)
    dt_bias_buf = metal_buffer(device, HV * 4)
    load_bf16(prefix + "linear_attn.A_log",   HV, a_log_buf)
    load_bf16(prefix + "linear_attn.dt_bias", HV, dt_bias_buf)
    ln_w_buf = metal_buffer(device, DV * 4)
    load_bf16(prefix + "linear_attn.norm.weight", DV, ln_w_buf)
    op_w = load_nvfp4_part(prefix + "linear_attn.out_proj.weight")
    op_s = load_nvfp4_part(prefix + "linear_attn.out_proj.scales")
    # Persistent state (zeroed)
    cs_a = metal_buffer(device, 3 * QKV_DIM * 4)
    cs_b = metal_buffer(device, 3 * QKV_DIM * 4)
    ss_a = metal_buffer(device, HV * DV * DK * 4)
    ss_b = metal_buffer(device, HV * DV * DK * 4)
    i = 0
    while i < 3 * QKV_DIM
      metal_buffer_write_f32(cs_a, i, ~0.0)
      i = i + 1
    i = 0
    while i < HV * DV * DK
      metal_buffer_write_f32(ss_a, i, ~0.0)
      i = i + 1
    layers.push({
      kind: "mamba", in_norm: in_norm_buf, post_norm: post_norm_buf,
      qkv_w: qkv_w, qkv_s: qkv_s, z_w: z_w, z_s: z_s,
      a_w: a_w, b_w: b_w,
      conv_w: conv_w_buf, alog: a_log_buf, dtb: dt_bias_buf,
      ln_w: ln_w_buf, op_w: op_w, op_s: op_s,
      cs_a: cs_a, cs_b: cs_b, ss_a: ss_a, ss_b: ss_b, ping: 0
    })
  else
    # Full attention weights
    qp_w = load_nvfp4_part(prefix + "self_attn.q_proj.weight")
    qp_s = load_nvfp4_part(prefix + "self_attn.q_proj.scales")
    kp_w = load_nvfp4_part(prefix + "self_attn.k_proj.weight")
    kp_s = load_nvfp4_part(prefix + "self_attn.k_proj.scales")
    vp_w = load_nvfp4_part(prefix + "self_attn.v_proj.weight")
    vp_s = load_nvfp4_part(prefix + "self_attn.v_proj.scales")
    op_w = load_nvfp4_part(prefix + "self_attn.o_proj.weight")
    op_s = load_nvfp4_part(prefix + "self_attn.o_proj.scales")
    qn_buf = metal_buffer(device, HEAD_DIM * 4)
    kn_buf = metal_buffer(device, HEAD_DIM * 4)
    load_bf16(prefix + "self_attn.q_norm.weight", HEAD_DIM, qn_buf)
    load_bf16(prefix + "self_attn.k_norm.weight", HEAD_DIM, kn_buf)
    k_cache = metal_buffer(device, MAX_POS * KV_DIM * 4)
    v_cache = metal_buffer(device, MAX_POS * KV_DIM * 4)
    layers.push({
      kind: "full_attn", in_norm: in_norm_buf, post_norm: post_norm_buf,
      qp_w: qp_w, qp_s: qp_s, kp_w: kp_w, kp_s: kp_s,
      vp_w: vp_w, vp_s: vp_s, op_w: op_w, op_s: op_s,
      qn: qn_buf, kn: kn_buf, k_cache: k_cache, v_cache: v_cache
    })
  li = li + 1

# ---- Pre-resolve all MoE per-layer FIXED handles (router, shared, descriptors) ----
# This eliminates ~14 st.tensor() / st.mmap_for() / metal_buffer_for() calls
# from every moe_step (per token: 14 × 40 layers = 560 calls). Per-expert
# handles are still resolved lazily and cached per-layer.
<< "preloading per-layer MoE handles..."
li = 0
while li < N_LAYERS
  prefix = "language_model.model.layers." + li.to_s + "."
  lyr = layers[li]

  # Router gate is BF16 [N_EXPERTS, HIDDEN] in the ollama MLX export (no
  # int8-affine scales/biases) — zero-copy mmap, matvec via bf16_matvec_pipe.
  rw_d = st.tensor(prefix + "mlp.gate.weight")
  lyr[:rw] = metal_buffer_for(device, st.mmap_for(prefix + "mlp.gate.weight").view_at(rw_d[:byte_offset], :u8, rw_d[:byte_length]))

  # Shared expert gate is BF16 [1, HIDDEN] (output dim 1).
  sgw_d = st.tensor(prefix + "mlp.shared_expert_gate.weight")
  lyr[:sgw] = metal_buffer_for(device, st.mmap_for(prefix + "mlp.shared_expert_gate.weight").view_at(sgw_d[:byte_offset], :u8, sgw_d[:byte_length]))

  # Shared expert (nvfp4 swiglu)
  swg_d = st.tensor(prefix + "mlp.shared_expert.gate_proj.weight")
  sws_d = st.tensor(prefix + "mlp.shared_expert.gate_proj.scales")
  suw_d = st.tensor(prefix + "mlp.shared_expert.up_proj.weight")
  sus_d = st.tensor(prefix + "mlp.shared_expert.up_proj.scales")
  sdw_d = st.tensor(prefix + "mlp.shared_expert.down_proj.weight")
  sds_d = st.tensor(prefix + "mlp.shared_expert.down_proj.scales")
  lyr[:swg] = metal_buffer_for(device, st.mmap_for(prefix + "mlp.shared_expert.gate_proj.weight").view_at(swg_d[:byte_offset], :u8, swg_d[:byte_length]))
  lyr[:sws] = metal_buffer_for(device, st.mmap_for(prefix + "mlp.shared_expert.gate_proj.scales").view_at(sws_d[:byte_offset], :u8, sws_d[:byte_length]))
  lyr[:suw] = metal_buffer_for(device, st.mmap_for(prefix + "mlp.shared_expert.up_proj.weight").view_at(suw_d[:byte_offset], :u8, suw_d[:byte_length]))
  lyr[:sus] = metal_buffer_for(device, st.mmap_for(prefix + "mlp.shared_expert.up_proj.scales").view_at(sus_d[:byte_offset], :u8, sus_d[:byte_length]))
  lyr[:sdw] = metal_buffer_for(device, st.mmap_for(prefix + "mlp.shared_expert.down_proj.weight").view_at(sdw_d[:byte_offset], :u8, sdw_d[:byte_length]))
  lyr[:sds] = metal_buffer_for(device, st.mmap_for(prefix + "mlp.shared_expert.down_proj.scales").view_at(sds_d[:byte_offset], :u8, sds_d[:byte_length]))

  # Per-expert weight tables (descriptors + mmaps cached, per-expert handles lazy)
  lyr[:gw_d] = st.tensor(prefix + "mlp.switch_mlp.gate_proj.weight")
  lyr[:gs_d] = st.tensor(prefix + "mlp.switch_mlp.gate_proj.scales")
  lyr[:uw_d] = st.tensor(prefix + "mlp.switch_mlp.up_proj.weight")
  lyr[:us_d] = st.tensor(prefix + "mlp.switch_mlp.up_proj.scales")
  lyr[:dw_d] = st.tensor(prefix + "mlp.switch_mlp.down_proj.weight")
  lyr[:ds_d] = st.tensor(prefix + "mlp.switch_mlp.down_proj.scales")
  lyr[:gw_mm] = st.mmap_for(prefix + "mlp.switch_mlp.gate_proj.weight")
  lyr[:gs_mm] = st.mmap_for(prefix + "mlp.switch_mlp.gate_proj.scales")
  lyr[:uw_mm] = st.mmap_for(prefix + "mlp.switch_mlp.up_proj.weight")
  lyr[:us_mm] = st.mmap_for(prefix + "mlp.switch_mlp.up_proj.scales")
  lyr[:dw_mm] = st.mmap_for(prefix + "mlp.switch_mlp.down_proj.weight")
  lyr[:ds_mm] = st.mmap_for(prefix + "mlp.switch_mlp.down_proj.scales")
  # Per-expert handle cache (lazy: id → [gw,gs,uw,us,dw,ds]).
  # Eager pre-resolution of all 256 experts × 40 layers OOM-killed the
  # process by forcing all 17 GB of MoE weights into resident memory.
  lyr[:exp_cache] = {}
  li = li + 1

# ---- Final norm + lm_head ----
final_norm_buf = metal_buffer(device, HIDDEN * 4)
load_bf16("language_model.model.norm.weight", HIDDEN, final_norm_buf)
# lm_head is BF16 [N_VOCAB, HIDDEN] in the ollama MLX export — zero-copy mmap.
lh_w = load_nvfp4_part("language_model.lm_head.weight")

# ---- Per-step buffers ----
xn_step       = metal_buffer(device, HIDDEN * 4)
qkv_step      = metal_buffer(device, QKV_DIM * 4)
z_step        = metal_buffer(device, V_DIM * 4)
a_step        = metal_buffer(device, HV * 4)
b_step        = metal_buffer(device, HV * 4)
conv_out_step = metal_buffer(device, QKV_DIM * 4)
mq_step       = metal_buffer(device, Q_DIM * 4)
mk_step       = metal_buffer(device, K_DIM * 4)
mv_step       = metal_buffer(device, V_DIM * 4)
g_step        = metal_buffer(device, HV * 4)
beta_step     = metal_buffer(device, HV * 4)
y_step        = metal_buffer(device, V_DIM * 4)
ng_step       = metal_buffer(device, V_DIM * 4)
mamba_out_step = metal_buffer(device, HIDDEN * 4)

qfull_step    = metal_buffer(device, QFULL_DIM * 4)
queries_step  = metal_buffer(device, ATTN_OUT_DIM * 4)
gate_step     = metal_buffer(device, ATTN_OUT_DIM * 4)
fk_step       = metal_buffer(device, KV_DIM * 4)
fv_step       = metal_buffer(device, KV_DIM * 4)
sdpa_out_step = metal_buffer(device, ATTN_OUT_DIM * 4)
attn_proj_step = metal_buffer(device, HIDDEN * 4)

cos_tab_buf   = metal_buffer(device, ROT_DIM_HALF * 4)
sin_tab_buf   = metal_buffer(device, ROT_DIM_HALF * 4)

x_step        = metal_buffer(device, HIDDEN * 4)
attn_or_mamba_out = metal_buffer(device, HIDDEN * 4)

router_step   = metal_buffer(device, N_EXPERTS * 4)
topk_idx_buf  = metal_buffer(device, TOP_K * 4)
topk_score_buf = metal_buffer(device, TOP_K * 4)
# Per-expert scratch buffers (8 sets) for parallel expert execution.
# Each expert writes into its own ge_e[i], ue_e[i], y_e[i] so the 8 expert
# command buffers don't conflict and can run concurrently on the GPU.
ge_e = []
ue_e = []
y_e  = []
i = 0
while i < TOP_K
  ge_e.push(metal_buffer(device, EXPERT_FFN * 4))
  ue_e.push(metal_buffer(device, EXPERT_FFN * 4))
  y_e.push(metal_buffer(device, HIDDEN * 4))
  i = i + 1
ge_step = metal_buffer(device, EXPERT_FFN * 4)
ue_step = metal_buffer(device, EXPERT_FFN * 4)
he_step = metal_buffer(device, EXPERT_FFN * 4)
de_step = metal_buffer(device, HIDDEN * 4)
moe_y_step = metal_buffer(device, HIDDEN * 4)
zero_hidden_buf = metal_buffer(device, HIDDEN * 4)
i = 0
while i < HIDDEN
  metal_buffer_write_f32(zero_hidden_buf, i, ~0.0)
  i = i + 1
sgl_step = metal_buffer(device, 4)
sg_score_step = metal_buffer(device, 4)
sg_buf_step = metal_buffer(device, SHARED_FFN * 4)
su_buf_step = metal_buffer(device, SHARED_FFN * 4)
sh_buf_step = metal_buffer(device, SHARED_FFN * 4)
sd_buf_step = metal_buffer(device, HIDDEN * 4)

logits_buf  = metal_buffer(device, N_VOCAB * 4)
argmax_buf  = metal_buffer(device, 4)
n_vocab_buf = metal_buffer(device, 4)
metal_buffer_write_i32(n_vocab_buf, 0, N_VOCAB)

# ---- Build partial-RoPE cos/sin tables for a given pos ----
log_base_q = Math.log(ROPE_BASE)
inv_rd     = ~2.0 / ROT_DIM
-> build_rope_tables(pos)
  i = 0
  while i < ROT_DIM_HALF
    theta = Math.exp(log_base_q * (~0.0 - i * inv_rd))
    angle = pos * theta
    metal_buffer_write_f32(cos_tab_buf, i, Math.cos(angle))
    metal_buffer_write_f32(sin_tab_buf, i, Math.sin(angle))
    i = i + 1

# ---- Per-step Mamba (uses pre-loaded weights + persistent state) ----
# NOTE: mamba_step/full_attn_step/moe_pre/moe_post are "open" — they only
# enqueue dispatches; the caller (forward_step) manages metal_batch_begin/commit
# so adjacent functions share command buffers (fewer commits per layer).
-> mamba_step(lyr, x_in_buf, x_out_buf)
  cs_in  = lyr[:cs_a]
  cs_out = lyr[:cs_b]
  ss_in  = lyr[:ss_a]
  ss_out = lyr[:ss_b]
  if lyr[:ping] == 1
    cs_in  = lyr[:cs_b]
    cs_out = lyr[:cs_a]
    ss_in  = lyr[:ss_b]
    ss_out = lyr[:ss_a]
  metal_dispatch_groups(queue, rms_pipe, [x_in_buf, lyr[:in_norm], xn_step, HIDDEN, ~1.0 / HIDDEN, EPS], 1, 256)
  metal_dispatch_groups(queue, nvfp4_mlx_pipe, [lyr[:qkv_w], lyr[:qkv_s], xn_step, qkv_step, HIDDEN], QKV_DIM / 8, 64)
  metal_dispatch_groups(queue, nvfp4_mlx_pipe, [lyr[:z_w],   lyr[:z_s],   xn_step, z_step,   HIDDEN], V_DIM / 8, 64)
  metal_dispatch_groups(queue, bf16_matvec_pipe, [lyr[:a_w], xn_step, a_step, HIDDEN], HV, 32)
  metal_dispatch_groups(queue, bf16_matvec_pipe, [lyr[:b_w], xn_step, b_step, HIDDEN], HV, 32)
  metal_dispatch_n(queue, conv_pipe, [lyr[:conv_w], cs_in, qkv_step, conv_out_step, cs_out, QKV_DIM, QKV_DIM], QKV_DIM)
  metal_dispatch_n(queue, copy_pipe, [conv_out_step, mq_step, 0,             Q_DIM], Q_DIM)
  metal_dispatch_n(queue, copy_pipe, [conv_out_step, mk_step, Q_DIM,         K_DIM], K_DIM)
  metal_dispatch_n(queue, copy_pipe, [conv_out_step, mv_step, Q_DIM + K_DIM, V_DIM], V_DIM)
  metal_dispatch_groups(queue, phn_pipe, [mq_step, q_w_buf, DK, ~1.0 / DK, EPS], HK, 32)
  metal_dispatch_groups(queue, phn_pipe, [mk_step, k_w_buf, DK, ~1.0 / DK, EPS], HK, 32)
  metal_dispatch_n(queue, g_pipe, [a_step, lyr[:alog], lyr[:dtb], g_step, HV, HV], HV)
  metal_dispatch_n(queue, sigmoid_pipe, [b_step, beta_step, HV], HV)
  metal_dispatch_3d(queue, step_pipe, [mq_step, mk_step, mv_step, g_step, beta_step, ss_in, y_step, ss_out, HK, HV, DK, DV], 1, DV / 4, HV, 32, 4, 1)
  metal_dispatch_groups(queue, rng_pipe, [y_step, z_step, lyr[:ln_w], ng_step, DV, EPS], HV, 32)
  metal_dispatch_groups(queue, nvfp4_mlx_pipe, [lyr[:op_w], lyr[:op_s], ng_step, mamba_out_step, V_DIM], HIDDEN / 8, 64)
  metal_dispatch_n(queue, copy_pipe, [mamba_out_step, x_out_buf, 0, HIDDEN], HIDDEN)
  metal_dispatch_n(queue, add_pipe, [x_out_buf, x_in_buf, HIDDEN], HIDDEN)
  lyr[:ping] = 1 - lyr[:ping]

# ---- Per-step full attention (KV-cached, partial-RoPE if pos > 0) ----
-> full_attn_step(lyr, x_in_buf, x_out_buf, pos)
  if pos > 0 then build_rope_tables(pos)
  metal_dispatch_groups(queue, rms_pipe, [x_in_buf, lyr[:in_norm], xn_step, HIDDEN, ~1.0 / HIDDEN, EPS], 1, 256)
  metal_dispatch_groups(queue, nvfp4_mlx_pipe, [lyr[:qp_w], lyr[:qp_s], xn_step, qfull_step, HIDDEN], QFULL_DIM / 8, 64)
  metal_dispatch_groups(queue, nvfp4_mlx_pipe, [lyr[:kp_w], lyr[:kp_s], xn_step, fk_step,    HIDDEN], (KV_DIM + 7) / 8, 64)
  metal_dispatch_groups(queue, nvfp4_mlx_pipe, [lyr[:vp_w], lyr[:vp_s], xn_step, fv_step,    HIDDEN], (KV_DIM + 7) / 8, 64)
  metal_dispatch_n(queue, split_pipe, [qfull_step, queries_step, gate_step, N_HEADS_ATTN, HEAD_DIM], ATTN_OUT_DIM)
  metal_dispatch_groups(queue, phn_pipe, [queries_step, lyr[:qn], HEAD_DIM, ~1.0 / HEAD_DIM, EPS], N_HEADS_ATTN, 32)
  metal_dispatch_groups(queue, phn_pipe, [fk_step,      lyr[:kn], HEAD_DIM, ~1.0 / HEAD_DIM, EPS], N_KV_HEADS,   32)
  if pos > 0
    metal_dispatch_n(queue, prope_pipe, [queries_step, cos_tab_buf, sin_tab_buf, HEAD_DIM, ROT_DIM_HALF, N_HEADS_ATTN], N_HEADS_ATTN * ROT_DIM_HALF)
    metal_dispatch_n(queue, prope_pipe, [fk_step,      cos_tab_buf, sin_tab_buf, HEAD_DIM, ROT_DIM_HALF, N_KV_HEADS],   N_KV_HEADS   * ROT_DIM_HALF)
  metal_dispatch_n(queue, copy_pipe, [fk_step, lyr[:k_cache], pos * KV_DIM, KV_DIM], KV_DIM)
  metal_dispatch_n(queue, copy_pipe, [fv_step, lyr[:v_cache], pos * KV_DIM, KV_DIM], KV_DIM)
  metal_dispatch_groups(queue, sdpa_pipe, [queries_step, lyr[:k_cache], lyr[:v_cache], sdpa_out_step, GQA_GROUP, pos + 1, HEAD_DIM, KV_DIM, ATTN_SCALE], N_HEADS_ATTN, 1024)
  metal_dispatch_n(queue, aog_pipe, [sdpa_out_step, gate_step, ATTN_OUT_DIM], ATTN_OUT_DIM)
  metal_dispatch_groups(queue, nvfp4_mlx_pipe, [lyr[:op_w], lyr[:op_s], sdpa_out_step, attn_proj_step, ATTN_OUT_DIM], HIDDEN / 8, 64)
  metal_dispatch_n(queue, copy_pipe, [attn_proj_step, x_out_buf, 0, HIDDEN], HIDDEN)
  metal_dispatch_n(queue, add_pipe, [x_out_buf, x_in_buf, HIDDEN], HIDDEN)

# ---- Per-step MoE (uses pre-loaded weight handles) ----
# Lazy-cache per-expert handles. First call populates, subsequent calls reuse.
-> get_expert_handles(lyr, eid)
  cache = lyr[:exp_cache]
  if cache.has_key?(eid)
    cache[eid]
  else
    h = [
      metal_buffer_for(device, lyr[:gw_mm].view_at(lyr[:gw_d][:byte_offset] + eid * PER_EXPERT_W_BYTES,  :u8, PER_EXPERT_W_BYTES)),
      metal_buffer_for(device, lyr[:gs_mm].view_at(lyr[:gs_d][:byte_offset] + eid * PER_EXPERT_S_BYTES,  :u8, PER_EXPERT_S_BYTES)),
      metal_buffer_for(device, lyr[:uw_mm].view_at(lyr[:uw_d][:byte_offset] + eid * PER_EXPERT_W_BYTES,  :u8, PER_EXPERT_W_BYTES)),
      metal_buffer_for(device, lyr[:us_mm].view_at(lyr[:us_d][:byte_offset] + eid * PER_EXPERT_S_BYTES,  :u8, PER_EXPERT_S_BYTES)),
      metal_buffer_for(device, lyr[:dw_mm].view_at(lyr[:dw_d][:byte_offset] + eid * PER_EXPERT_DW_BYTES, :u8, PER_EXPERT_DW_BYTES)),
      metal_buffer_for(device, lyr[:ds_mm].view_at(lyr[:ds_d][:byte_offset] + eid * PER_EXPERT_DS_BYTES, :u8, PER_EXPERT_DS_BYTES))
    ]
    cache[eid] = h
    h

# MoE pre-stage: rms_norm + router + GPU topk. Open — caller manages batch.
-> moe_pre(lyr, x_in_buf)
  metal_dispatch_groups(queue, rms_pipe, [x_in_buf, lyr[:post_norm], xn_step, HIDDEN, ~1.0 / HIDDEN, EPS], 1, 256)
  metal_dispatch_groups(queue, bf16_matvec_pipe, [lyr[:rw], xn_step, router_step, HIDDEN], N_EXPERTS, 32)
  metal_dispatch_groups(queue, topk_pipe, [router_step, topk_idx_buf, topk_score_buf], 1, N_EXPERTS)

# MoE post-stage: 8 routed experts running in parallel as separate async
# command buffers, shared expert sequential. Each expert writes into its own
# ge_e[i]/ue_e[i]/y_e[i] so the GPU can pipeline them across cores.
# Caller wraps this in metal_batch_begin (for the surrounding setup +
# shared expert + final reduce); the per-expert work uses its own buffers.
-> moe_post(lyr, x_in_buf, x_out_buf, top_indices, top_scores)
  # Caller has just committed the attn+moe_pre batch and read top-k back.
  # Launch 8 expert command buffers asynchronously — GPU may execute them
  # concurrently. Each writes its own y_e[i] (no buffer conflicts).
  cb_handles = []
  ei = 0
  while ei < TOP_K
    eh = get_expert_handles(lyr, top_indices[ei])
    es = top_scores[ei]
    metal_batch_begin(queue)
    metal_dispatch_groups(queue, nvfp4_mlx_pipe, [eh[0], eh[1], xn_step, ge_e[ei], HIDDEN], EXPERT_FFN / 8, 64)
    metal_dispatch_groups(queue, nvfp4_mlx_pipe, [eh[2], eh[3], xn_step, ue_e[ei], HIDDEN], EXPERT_FFN / 8, 64)
    metal_dispatch_groups(queue, silu_sr_pipe, [eh[4], eh[5], ge_e[ei], ue_e[ei], y_e[ei], EXPERT_FFN, es], HIDDEN, 32)
    cb_handles.push(metal_batch_commit_async(queue))
    ei = ei + 1

  # Wait for all 8 expert buffers to complete
  i = 0
  while i < TOP_K
    metal_command_buffer_wait(cb_handles[i])
    i = i + 1

  # Final batch: copy x_in, sum 8 experts into it, do shared expert, copy out
  metal_batch_begin(queue)
  metal_dispatch_n(queue, copy_pipe, [x_in_buf, moe_y_step, 0, HIDDEN], HIDDEN)
  metal_dispatch_n(queue, sum8_pipe, [moe_y_step, y_e[0], y_e[1], y_e[2], y_e[3], y_e[4], y_e[5], y_e[6], y_e[7], HIDDEN], HIDDEN)
  metal_dispatch_groups(queue, bf16_matvec_pipe, [lyr[:sgw], xn_step, sgl_step, HIDDEN], 1, 32)
  metal_dispatch_n(queue, sigmoid_pipe, [sgl_step, sg_score_step, 1], 1)
  metal_dispatch_groups(queue, nvfp4_mlx_pipe, [lyr[:swg], lyr[:sws], xn_step, sg_buf_step, HIDDEN], SHARED_FFN / 8, 64)
  metal_dispatch_groups(queue, nvfp4_mlx_pipe, [lyr[:suw], lyr[:sus], xn_step, su_buf_step, HIDDEN], SHARED_FFN / 8, 64)
  metal_dispatch_groups(queue, silu_bs_pipe, [lyr[:sdw], lyr[:sds], sg_buf_step, su_buf_step, moe_y_step, SHARED_FFN, sg_score_step], HIDDEN, 32)
  metal_dispatch_n(queue, copy_pipe, [moe_y_step, x_out_buf, 0, HIDDEN], HIDDEN)
  # Caller (forward_step) commits this batch.

# ---- forward_step: token → logits → argmax pred ----
# compute_logits = false on prefill non-final tokens — saves the giant
# lm_head matvec (N_VOCAB=248320 × HIDDEN=2048 = the model's largest dispatch).
-> forward_step(token_id, pos, compute_logits)
  # Embed
  metal_batch_begin(queue)
  metal_dispatch_n(queue, bf16_embed_pipe, [embed_w_buf, x_step, token_id, HIDDEN], HIDDEN)
  metal_batch_commit(queue)

  # 40 layers — 2 commits per layer (was 3):
  #   batch1: attn_or_mamba(x → attn_out) + moe_pre(attn_out → router_step+topk)
  #   readback 16 elements (top_indices, top_scores)
  #   batch2: moe_post(attn_out → x)
  li = 0
  while li < N_LAYERS
    lyr = layers[li]

    metal_batch_begin(queue)
    if lyr[:kind] == "mamba"
      mamba_step(lyr, x_step, attn_or_mamba_out)
    else
      full_attn_step(lyr, x_step, attn_or_mamba_out, pos)
    moe_pre(lyr, attn_or_mamba_out)
    metal_batch_commit(queue)

    top_indices = []
    top_scores  = []
    i = 0
    while i < TOP_K
      top_indices.push(metal_buffer_read_i32(topk_idx_buf, i))
      top_scores.push(metal_buffer_read_f32(topk_score_buf, i))
      i = i + 1

    # moe_post manages its own batches internally (8 async expert batches +
    # one trailing batch for shared expert + final reduction).
    moe_post(lyr, attn_or_mamba_out, x_step, top_indices, top_scores)
    metal_batch_commit(queue)

    li = li + 1

  if compute_logits
    metal_batch_begin(queue)
    metal_dispatch_groups(queue, rms_pipe, [x_step, final_norm_buf, xn_step, HIDDEN, ~1.0 / HIDDEN, EPS], 1, 256)
    metal_dispatch_groups(queue, bf16_matvec_pipe, [lh_w, xn_step, logits_buf, HIDDEN], N_VOCAB, 32)
    metal_dispatch_groups(queue, argmax_pipe, [logits_buf, argmax_buf, n_vocab_buf], 1, 32)
    metal_batch_commit(queue)
    metal_buffer_read_i32(argmax_buf, 0)
  else
    -1

# ---- Run prefill ----
PROMPT_IDS = [760, 6511, 314, 9338, 369]
<< ""
<< "running prefill on " + PROMPT_IDS.size().to_s + " tokens..."
t0 = ccall("__w_clock_ms")
last_pred = -1
i = 0
while i < PROMPT_IDS.size()
  is_last = i == (PROMPT_IDS.size() - 1)
  t_tok = ccall("__w_clock_ms")
  pred = forward_step(PROMPT_IDS[i], i, is_last)
  dt_tok = ccall("__w_clock_ms") - t_tok
  if is_last then last_pred = pred
  << "  pos " + i.to_s + " (tok " + PROMPT_IDS[i].to_s + ") → next_argmax = " + pred.to_s + "  \[" + dt_tok.to_s + " ms\]"
  i = i + 1
elapsed = ccall("__w_clock_ms") - t0
<< "prefill: " + PROMPT_IDS.size().to_s + " tokens in " + elapsed.to_s + " ms"
<< ""
<< "FINAL: argmax after prefill = " + last_pred.to_s + " (target 11751 = ' Paris')"
if last_pred == 11751
  << "Stage 3 PASS — first inference token bit-exact vs MLX!"
else
  << "Stage 3 FAIL — argmax mismatch"

# ---- Stage 4: greedy generation (next 8 tokens) ----
<< ""
<< "=== Stage 4: greedy generation, 8 tokens ==="
GEN_TOKENS = 8
generated = [last_pred]
gen_pos = PROMPT_IDS.size()
gi = 0
while gi < GEN_TOKENS
  t_g = ccall("__w_clock_ms")
  next_tok = forward_step(generated[gi], gen_pos, true)
  dt_g = ccall("__w_clock_ms") - t_g
  generated.push(next_tok)
  << "  gen " + gi.to_s + " (pos " + gen_pos.to_s + "): tok " + next_tok.to_s + "  \[" + dt_g.to_s + " ms\]"
  gen_pos = gen_pos + 1
  gi = gi + 1

<< ""
<< "generated token ids: " + generated.to_s

st.close
<< ""
<< "stages 0-3 complete."
