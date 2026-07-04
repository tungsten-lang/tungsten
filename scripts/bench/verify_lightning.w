# End-to-end forward pass for Lightning-1.7B-mlx-nvfp4 in pure Tungsten.
# Loads the safetensors model, runs prefill on a tiny prompt, prints the
# argmax over the lm_head logits.
#
# Architecture (qwen3, dense FFN, all full_attention):
#   28 layers, hidden=2048, head_dim=128, q_heads=16, kv_heads=8 (GQA=2),
#   intermediate (FFN dim) = 6144, vocab = 151936, RoPE base 1e6.
#   Tied embeddings (lm_head reuses model.embed_tokens).
#
# All weight matrices (q/k/v/o projections, gate/up/down, embeddings)
# are nvfp4-quantized: 4 bits per weight, group_size=16, E4M3 fp8 scale
# per group. Norm weights are f16 (converted to f32 at load time).

use core/metal
use core/json
use tungsten-llama/safetensors

LIGHTNING_PATH = "/Users/erik/.cache/huggingface/hub/models--bradyclarke--Lightning-1.7B-mlx-nvfp4/snapshots/93b9599f5380f67efa1faa0dc6591251f040882a/model.safetensors"
KERNEL_DIR = "bits/tungsten-llama/lib/kernels/"
NVFP4_DIR  = "bits/tungsten-llama/lib/kernels/nvfp4/"

HIDDEN = 2048
HEAD_DIM = 128
HEAD_DIM_HALF = 64
N_Q_HEADS = 16
N_KV_HEADS = 8
GROUP_SIZE = 2          # N_Q_HEADS / N_KV_HEADS
KV_ROW = 1024           # N_KV_HEADS * HEAD_DIM
INTERMEDIATE = 6144
N_VOCAB = 151936
N_LAYERS = 28
EPS = ~0.000001
BASE = ~1000000.0
MAX_POS = 64

device = metal_device()
queue = metal_queue(device)

<< "loading Lightning-1.7B safetensors..."
st = Safetensors.new(LIGHTNING_PATH)
<< "  " + st.count.to_s + " tensors"

# ── Pipelines ──────────────────────────────────────────────────────────
nvfp4_matvec_pipe   = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec.metal")), "nvfp4_matvec")
nvfp4_embed_pipe    = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_embedding_lookup.metal")), "nvfp4_embedding_lookup")
f16_to_f32_pipe     = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "f16_to_f32.metal")), "f16_to_f32")

rms_pipe       = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "shared/rms_norm.metal")), "rms_norm")
phn_pipe       = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "shared/per_head_norm.metal")), "per_head_norm")
rope_pipe      = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "shared/rope.metal")), "rope_neox")
kv_pipe        = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "shared/kv_write.metal")), "kv_write")
scores_pipe    = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "shared/attn_scores.metal")), "attn_scores")
softmax_pipe   = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "shared/attn_softmax.metal")), "attn_softmax")
weighted_pipe  = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "shared/attn_weighted_sum.metal")), "attn_weighted_sum")
silu_pipe      = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "shared/silu_mul.metal")), "silu_mul")
add_pipe       = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "shared/residual_add.metal")), "residual_add")
argmax_pipe    = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "shared/argmax.metal")), "argmax")

# ── Helper: convert an F16 weight tensor into a fresh F32 Metal buffer.
-> upload_f16_as_f32(name)
  desc = st.tensor(name)
  n_floats = desc[:byte_length] / 2   # F16 = 2 bytes/elem
  src_buf = metal_buffer(device, desc[:byte_length])
  dst_buf = metal_buffer(device, n_floats * 4)
  st.upload_bytes(name, src_buf)
  n_buf = metal_buffer(device, 4)
  metal_buffer_write_i32(n_buf, 0, n_floats)
  metal_batch_begin(queue)
  metal_dispatch_n(queue, f16_to_f32_pipe, [src_buf, dst_buf, n_buf], n_floats)
  metal_batch_commit(queue)
  dst_buf

# ── Helper: upload an nvfp4 tensor pair (weight + scales) into Metal buffers
-> upload_nvfp4(name)
  w_desc = st.tensor(name + ".weight")
  s_desc = st.tensor(name + ".scales")
  w_buf = metal_buffer(device, w_desc[:byte_length])
  s_buf = metal_buffer(device, s_desc[:byte_length])
  st.upload_bytes(name + ".weight", w_buf)
  st.upload_bytes(name + ".scales", s_buf)
  { quants: w_buf, scales: s_buf }

# ── Load embeddings (tied with lm_head)
<< "uploading embeddings..."
embed = upload_nvfp4("model.embed_tokens")

# ── Load 28 layers
<< "uploading 28 layers..."
layers = []
li = 0
while li < N_LAYERS
  if li % 7 == 0
    << "  layer " + li.to_s + "/" + N_LAYERS.to_s + "..."
  prefix = "model.layers." + li.to_s + "."
  layers.push({
    attn_norm: upload_f16_as_f32(prefix + "input_layernorm.weight"),
    q_proj:    upload_nvfp4(prefix + "self_attn.q_proj"),
    k_proj:    upload_nvfp4(prefix + "self_attn.k_proj"),
    v_proj:    upload_nvfp4(prefix + "self_attn.v_proj"),
    o_proj:    upload_nvfp4(prefix + "self_attn.o_proj"),
    q_norm:    upload_f16_as_f32(prefix + "self_attn.q_norm.weight"),
    k_norm:    upload_f16_as_f32(prefix + "self_attn.k_norm.weight"),
    ffn_norm:  upload_f16_as_f32(prefix + "post_attention_layernorm.weight"),
    gate_proj: upload_nvfp4(prefix + "mlp.gate_proj"),
    up_proj:   upload_nvfp4(prefix + "mlp.up_proj"),
    down_proj: upload_nvfp4(prefix + "mlp.down_proj"),
    k_cache:   metal_buffer(device, MAX_POS * KV_ROW * 4),
    v_cache:   metal_buffer(device, MAX_POS * KV_ROW * 4)
  })
  li = li + 1

out_norm = upload_f16_as_f32("model.norm.weight")
<< "  done."

# ── Per-step buffers ──────────────────────────────────────────────────
x_buf      = metal_buffer(device, HIDDEN * 4)
xn_buf     = metal_buffer(device, HIDDEN * 4)
q_buf      = metal_buffer(device, N_Q_HEADS * HEAD_DIM * 4)
k_buf      = metal_buffer(device, KV_ROW * 4)
v_buf      = metal_buffer(device, KV_ROW * 4)
cos_buf    = metal_buffer(device, HEAD_DIM_HALF * 4)
sin_buf    = metal_buffer(device, HEAD_DIM_HALF * 4)
scores_buf = metal_buffer(device, N_Q_HEADS * MAX_POS * 4)
attn_out   = metal_buffer(device, N_Q_HEADS * HEAD_DIM * 4)
attn_proj  = metal_buffer(device, HIDDEN * 4)
gate_buf   = metal_buffer(device, INTERMEDIATE * 4)
up_buf     = metal_buffer(device, INTERMEDIATE * 4)
h_buf      = metal_buffer(device, INTERMEDIATE * 4)
ffn_out    = metal_buffer(device, HIDDEN * 4)
logits_buf = metal_buffer(device, N_VOCAB * 4)
argmax_buf = metal_buffer(device, 4)

# ── Constant buffers ──────────────────────────────────────────────────
hidden_buf  = metal_buffer(device, 4) ; metal_buffer_write_i32(hidden_buf, 0, HIDDEN)
inv_h_buf   = metal_buffer(device, 4) ; metal_buffer_write_f32(inv_h_buf, 0, ~1.0 / HIDDEN)
eps_buf     = metal_buffer(device, 4) ; metal_buffer_write_f32(eps_buf, 0, EPS)
hd_buf      = metal_buffer(device, 4) ; metal_buffer_write_i32(hd_buf, 0, HEAD_DIM)
inv_d_buf   = metal_buffer(device, 4) ; metal_buffer_write_f32(inv_d_buf, 0, ~1.0 / HEAD_DIM)
hdh_buf     = metal_buffer(device, 4) ; metal_buffer_write_i32(hdh_buf, 0, HEAD_DIM_HALF)
n_q_buf     = metal_buffer(device, 4) ; metal_buffer_write_i32(n_q_buf, 0, N_Q_HEADS)
n_kv_buf    = metal_buffer(device, 4) ; metal_buffer_write_i32(n_kv_buf, 0, N_KV_HEADS)
gs_buf      = metal_buffer(device, 4) ; metal_buffer_write_i32(gs_buf, 0, GROUP_SIZE)
scale_buf   = metal_buffer(device, 4) ; metal_buffer_write_f32(scale_buf, 0, ~1.0 / Math.sqrt(~0.0 + HEAD_DIM))
kv_row_buf  = metal_buffer(device, 4) ; metal_buffer_write_i32(kv_row_buf, 0, KV_ROW)
pos_buf     = metal_buffer(device, 4)
n_pos_buf   = metal_buffer(device, 4)
kdim_h_buf  = metal_buffer(device, 4) ; metal_buffer_write_i32(kdim_h_buf, 0, HIDDEN)
kdim_o_buf  = metal_buffer(device, 4) ; metal_buffer_write_i32(kdim_o_buf, 0, N_Q_HEADS * HEAD_DIM)
kdim_int_buf = metal_buffer(device, 4) ; metal_buffer_write_i32(kdim_int_buf, 0, INTERMEDIATE)
n_silu_buf  = metal_buffer(device, 4) ; metal_buffer_write_i32(n_silu_buf, 0, INTERMEDIATE)
n_vocab_buf = metal_buffer(device, 4) ; metal_buffer_write_i32(n_vocab_buf, 0, N_VOCAB)
token_id_buf = metal_buffer(device, 4)

log_base = Math.log(BASE)
inv_hd = ~2.0 / HEAD_DIM

-> build_rope_tables(pos)
  i = 0
  while i < HEAD_DIM_HALF
    theta = Math.exp(log_base * (~0.0 - i * inv_hd))
    angle = pos * theta
    metal_buffer_write_f32(cos_buf, i, Math.cos(angle))
    metal_buffer_write_f32(sin_buf, i, Math.sin(angle))
    i = i + 1

-> run_block(lyr, n_pos_active)
  # attn_norm
  metal_dispatch_groups(queue, rms_pipe, [x_buf, lyr[:attn_norm], xn_buf, hidden_buf, inv_h_buf, eps_buf], 1, 32)
  metal_batch_barrier(queue)
  # q/k/v projections
  metal_dispatch_groups(queue, nvfp4_matvec_pipe, [lyr[:q_proj][:quants], lyr[:q_proj][:scales], xn_buf, q_buf, kdim_h_buf], N_Q_HEADS * HEAD_DIM, 32)
  metal_dispatch_groups(queue, nvfp4_matvec_pipe, [lyr[:k_proj][:quants], lyr[:k_proj][:scales], xn_buf, k_buf, kdim_h_buf], KV_ROW, 32)
  metal_dispatch_groups(queue, nvfp4_matvec_pipe, [lyr[:v_proj][:quants], lyr[:v_proj][:scales], xn_buf, v_buf, kdim_h_buf], KV_ROW, 32)
  metal_batch_barrier(queue)
  # per-head norm
  metal_dispatch_groups(queue, phn_pipe, [q_buf, lyr[:q_norm], hd_buf, inv_d_buf, eps_buf], N_Q_HEADS, 32)
  metal_dispatch_groups(queue, phn_pipe, [k_buf, lyr[:k_norm], hd_buf, inv_d_buf, eps_buf], N_KV_HEADS, 32)
  metal_batch_barrier(queue)
  # rope
  metal_dispatch_n(queue, rope_pipe, [q_buf, cos_buf, sin_buf, hd_buf, hdh_buf, n_q_buf], N_Q_HEADS * HEAD_DIM_HALF)
  metal_dispatch_n(queue, rope_pipe, [k_buf, cos_buf, sin_buf, hd_buf, hdh_buf, n_kv_buf], N_KV_HEADS * HEAD_DIM_HALF)
  metal_batch_barrier(queue)
  # kv write
  metal_dispatch_n(queue, kv_pipe, [k_buf, lyr[:k_cache], pos_buf, kv_row_buf], KV_ROW)
  metal_dispatch_n(queue, kv_pipe, [v_buf, lyr[:v_cache], pos_buf, kv_row_buf], KV_ROW)
  metal_batch_barrier(queue)
  # attention
  metal_dispatch_n(queue, scores_pipe, [q_buf, lyr[:k_cache], scores_buf, hd_buf, n_kv_buf, gs_buf, n_pos_buf, scale_buf], N_Q_HEADS * n_pos_active)
  metal_batch_barrier(queue)
  metal_dispatch_groups(queue, softmax_pipe, [scores_buf, n_pos_buf], N_Q_HEADS, 32)
  metal_batch_barrier(queue)
  metal_dispatch_n(queue, weighted_pipe, [scores_buf, lyr[:v_cache], attn_out, hd_buf, n_kv_buf, gs_buf, n_pos_buf], N_Q_HEADS * HEAD_DIM)
  metal_batch_barrier(queue)
  # o_proj + residual
  metal_dispatch_groups(queue, nvfp4_matvec_pipe, [lyr[:o_proj][:quants], lyr[:o_proj][:scales], attn_out, attn_proj, kdim_o_buf], HIDDEN, 32)
  metal_batch_barrier(queue)
  metal_dispatch_n(queue, add_pipe, [x_buf, attn_proj, hidden_buf], HIDDEN)
  metal_batch_barrier(queue)
  # ffn_norm
  metal_dispatch_groups(queue, rms_pipe, [x_buf, lyr[:ffn_norm], xn_buf, hidden_buf, inv_h_buf, eps_buf], 1, 32)
  metal_batch_barrier(queue)
  # gate / up
  metal_dispatch_groups(queue, nvfp4_matvec_pipe, [lyr[:gate_proj][:quants], lyr[:gate_proj][:scales], xn_buf, gate_buf, kdim_h_buf], INTERMEDIATE, 32)
  metal_dispatch_groups(queue, nvfp4_matvec_pipe, [lyr[:up_proj][:quants], lyr[:up_proj][:scales], xn_buf, up_buf, kdim_h_buf], INTERMEDIATE, 32)
  metal_batch_barrier(queue)
  # silu_mul
  metal_dispatch_n(queue, silu_pipe, [gate_buf, up_buf, h_buf, n_silu_buf], INTERMEDIATE)
  metal_batch_barrier(queue)
  # down
  metal_dispatch_groups(queue, nvfp4_matvec_pipe, [lyr[:down_proj][:quants], lyr[:down_proj][:scales], h_buf, ffn_out, kdim_int_buf], HIDDEN, 32)
  metal_batch_barrier(queue)
  # residual
  metal_dispatch_n(queue, add_pipe, [x_buf, ffn_out, hidden_buf], HIDDEN)
  metal_batch_barrier(queue)

-> forward_step(token_id, pos)
  metal_buffer_write_i32(pos_buf, 0, pos)
  n_pos_active = pos + 1
  metal_buffer_write_i32(n_pos_buf, 0, n_pos_active)
  metal_buffer_write_i32(token_id_buf, 0, token_id)

  build_rope_tables(pos)

  metal_batch_begin_concurrent(queue)
  # Embedding lookup: dequant 1 row of embed_tokens into x_buf
  metal_dispatch_n(queue, nvfp4_embed_pipe, [embed[:quants], embed[:scales], x_buf, token_id_buf, kdim_h_buf], HIDDEN / 16)
  metal_batch_barrier(queue)
  li = 0
  while li < N_LAYERS
    run_block(layers[li], n_pos_active)
    li = li + 1
  # final norm + lm_head (tied weights = embed_tokens)
  metal_dispatch_groups(queue, rms_pipe, [x_buf, out_norm, xn_buf, hidden_buf, inv_h_buf, eps_buf], 1, 32)
  metal_batch_barrier(queue)
  metal_dispatch_groups(queue, nvfp4_matvec_pipe, [embed[:quants], embed[:scales], xn_buf, logits_buf, kdim_h_buf], N_VOCAB, 32)
  metal_batch_barrier(queue)
  metal_dispatch_groups(queue, argmax_pipe, [logits_buf, argmax_buf, n_vocab_buf], 1, 32)
  metal_batch_commit(queue)
  metal_buffer_read_i32(argmax_buf, 0)

# ── Hardcoded prompt: "The capital of France is" ──
# token IDs from Qwen tokenizer (same vocab as our existing tungsten-llama):
PROMPT_IDS = [785, 6722, 315, 9625, 374]

<< ""
<< "running prefill on " + PROMPT_IDS.size().to_s + " tokens..."

t_start = ccall("__w_clock_ms")
pos = 0
i = 0
last_pred = -1
while i < PROMPT_IDS.size()
  last_pred = forward_step(PROMPT_IDS[i], pos)
  pos = pos + 1
  i = i + 1
t_elapsed = ccall("__w_clock_ms") - t_start
<< "prefill: " + PROMPT_IDS.size().to_s + " tokens in " + t_elapsed.to_s + " ms"
<< ""
<< "next token argmax id = " + last_pred.to_s
<< "(check via Python: tokenizer.decode([" + last_pred.to_s + "]))"

st.close
