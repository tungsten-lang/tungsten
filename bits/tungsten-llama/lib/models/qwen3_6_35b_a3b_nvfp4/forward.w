# qwen3.6/35b-a3b-nvfp4 forward pass — SKELETON.
#
# Loads the sharded MLX safetensors snapshot, dispatches each of 40 layers
# by type (linear_attention / full_attention), runs the dual-MoE FFN, and
# argmaxes the lm_head logits.
#
# Status: scaffold. Each layer-type forward function is documented but
# returns the input unchanged (passthrough). To bring inference up:
#   1. Wire the int8_affine_matvec kernel into route() for the router.
#   2. Wire gated_delta_step.metal into forward_linear_attn() — per-head
#      Mamba step using the in-register state.
#   3. Wire Lightning's nvfp4_matvec_mlx into forward_full_attn() with
#      the new attn_output_gate handling (q_proj is 2× wide).
#   4. Wire dual MoE: shared_expert path (always-on) + switch_mlp top-8
#      routed experts, combined per token.
#
# All quantization formats already understood + tested:
#   - nvfp4 (bulk weights): kernels in lib/kernels/nvfp4/
#   - int8 affine (router/gates): kernels in lib/kernels/int8_affine/
# Mamba/SSM step kernel proven bit-exact vs MLX:
#   lib/kernels/qwen3_6/gated_delta_step.metal

in Tungsten:Llama

use core/metal
use tungsten-llama/sharded_safetensors

# Constants from this dir's config.w (kept inline here to avoid `use` chains
# while the model dir's `use`-resolution is being figured out).
HIDDEN              = 2048
HEAD_DIM            = 256
N_ATTN_HEADS        = 16
N_KV_HEADS          = 2
GQA_GROUP_SIZE      = 8
ATTN_OUTPUT_GATE    = 1
FULL_ATTN_INTERVAL  = 4
N_HIDDEN_LAYERS     = 40
N_VOCAB             = 248320
RMS_NORM_EPS        = ~0.000001
ROPE_THETA          = 10000000

# Mamba (linear_attention)
LINEAR_KEY_DIM      = 128
LINEAR_NUM_K_HEADS  = 16
LINEAR_VALUE_DIM    = 128
LINEAR_NUM_V_HEADS  = 32
LINEAR_CONV_KERNEL  = 4

# MoE
N_EXPERTS           = 256
NUM_EXPERTS_PER_TOK = 8
MOE_FFN_DIM         = 512
SHARED_FFN_DIM      = 512

QWEN36_PATH = "/Users/erik/.cache/huggingface/hub/models--mlx-community--Qwen3.6-35B-A3B-nvfp4/snapshots/9c1a3a223ddd8a3425212cc421056614f149cf0f/model.safetensors.index.json"

+ Qwen36Forward
  rw :device
  rw :queue
  rw :st                # ShardedSafetensors
  rw :layers            # Array of layer dicts (per index, by layer type)

  -> new(device, queue)
    @device = device
    @queue = queue
    @st = ShardedSafetensors.new(QWEN36_PATH)
    @layers = []
    # TODO: walk 0..39, classify each layer (linear_attn vs full_attn),
    # upload weights into Metal buffers, build per-layer dispatch records.

  # Dispatch by layer index. qwen3.6 pattern: every 4th layer is full_attention,
  # others are linear_attention. Verified by load smoke test (scripts/bench/
  # qwen36_smoke.w) — exact 30/10 split.
  -> layer_type(layer_idx)
    if (layer_idx + 1) % FULL_ATTN_INTERVAL == 0
      :full_attention
    else
      :linear_attention

  # ---- Layer-type forwards (stubs) ----

  # Mamba/GatedDeltaNet step (decode T=1):
  #   x_normed = rms_norm(x, input_layernorm)
  #   qkv      = x_normed @ in_proj_qkv.T          # [4096+2048+2048] = [Q+K+V]
  #   z        = x_normed @ in_proj_z.T            # [4096] gate
  #   a        = x_normed @ in_proj_a.T            # [32]  data-dep A scale
  #   b        = x_normed @ in_proj_b.T            # [32]  data-dep beta input
  #   conv_in  = concat(conv_state, qkv) along seq # [conv_kernel-1 + T, 8192]
  #   conv_out = silu(conv1d(conv_in))             # 1D depthwise conv along seq
  #   q, k, v  = split(conv_out, [Q_dim, K_dim])   # [16,128] [16,128] [32,128]
  #   q        = (1/sqrt(Dk))^2 * rms_norm(q)
  #   k        = (1/sqrt(Dk))   * rms_norm(k)
  #   beta     = sigmoid(b)                        # per-head [32]
  #   g        = exp(-exp(A_log) * softplus(a + dt_bias))   # per-head [32]
  #   out, state = gated_delta_step(q, k, v, g, beta, state_in)  # KERNEL
  #   out      = rms_norm_gated(out, z)            # per-head V norm with z gate
  #   x_new    = x + out_proj(out)                 # residual
  -> forward_linear_attn(layer_idx, x_buf)
    # TODO: dispatch the kernels above against this layer's weights.
    x_buf

  # Full attention (qwen3-style with attn_output_gate):
  #   x_normed = rms_norm(x, input_layernorm)
  #   q_full   = x_normed @ q_proj.T               # [16 * 256 * 2 = 8192]
  #                                                  (output gate: q_full split
  #                                                   into [Q | gate], each 4096)
  #   k        = x_normed @ k_proj.T               # [2 * 256 = 512]  GQA group=8
  #   v        = x_normed @ v_proj.T               # [2 * 256 = 512]
  #   q, q_gate = split(q_full, 4096)
  #   q        = per_head_norm_rope(q, q_norm, cos, sin)
  #   k        = per_head_norm_rope(k, k_norm, cos, sin)  → write to k_cache
  #   v        → write to v_cache
  #   attn_out = sdpa(q, k_cache, v_cache, attn_scale)    # [4096]
  #   attn_out = attn_out * sigmoid(q_gate)               # NEW: per-head output gate
  #   x_new    = x + o_proj(attn_out)              # residual
  -> forward_full_attn(layer_idx, x_buf)
    # TODO
    x_buf

  # Dual MoE FFN (shared expert + 256 routed top-8):
  #   x_normed = rms_norm(x, post_attention_layernorm)
  #   # Shared expert (always-on, runs every token)
  #   shared_h    = silu(x_normed @ shared_expert.gate_proj.T) * (x_normed @ shared_expert.up_proj.T)
  #   shared_out  = shared_h @ shared_expert.down_proj.T
  #   shared_gate = sigmoid(x_normed @ shared_expert_gate.T)   # int8-affine kernel
  #   shared_out *= shared_gate
  #   # Routed experts (top-8 of 256)
  #   logits   = x_normed @ mlp.gate.T              # [256] — int8-affine kernel
  #   topk_v, topk_i = topk(softmax(logits), 8)     # top-8 selection
  #   routed_out = sum_k(topk_v[k] * expert(topk_i[k], x_normed))   # 8 experts run
  #   x_new    = x + shared_out + routed_out        # residual + both expert outs
  -> forward_moe(layer_idx, x_buf)
    # TODO
    x_buf

  # Single decode step. Returns argmax token id.
  -> forward_step(token_id, position)
    # TODO:
    # 1. Embed token_id → x_buf [HIDDEN]
    # 2. For each layer 0..39:
    #    if linear_attention: x_buf = forward_linear_attn(li, x_buf)
    #    else:                x_buf = forward_full_attn(li, x_buf)
    #    x_buf = forward_moe(li, x_buf)
    # 3. final rms_norm(x_buf, model.norm)
    # 4. logits = lm_head(x_buf)        — nvfp4_matvec_v4 (matches Lightning)
    # 5. return argmax(logits)          — argmax kernel @ TG=1024 (autotune-best)
    -1   # placeholder

  -> close
    @st.close
