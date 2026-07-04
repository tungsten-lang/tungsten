# Single-token, single-block forward pass on real qwen3 weights.
#
# Pipeline: token → embed → attn_norm → q/k/v proj → q/k norm + RoPE →
# write KV → attention → o proj → residual → ffn_norm → MoE FFN →
# residual → output_norm → lm_head → argmax.
#
# Single-token means the KV cache has exactly one entry (the current
# token), so attention degenerates to "current token attends to itself"
# — out = V[0]. Not meaningful as language modeling, but exercises every
# kernel the full forward needs. Multi-block / multi-token comes in P5.9
# (the verification gate).

use core/metal
use tungsten-llama/gguf
use tungsten-llama/tensor
use tungsten-llama/tokenizer

GGUF_PATH = "/Users/erik/.ollama/models/blobs/sha256-ae354763fe478c790125fb993e59bb1266655b3fa721eebe4a931660c3ed2ce9"
HIDDEN = 2048
HEAD_DIM = 128
HEAD_DIM_HALF = 64
N_Q_HEADS = 32
N_KV_HEADS = 4
GROUP_SIZE = 8           # 32 / 4
KV_ROW = 512             # n_kv_heads * head_dim
EXPERT_FFN = 768
N_EXPERTS = 128
TOP_K = 8
EPS = ~0.000001
BASE = ~1000000.0
N_VOCAB = 151936
TOKEN_ID = 3838          # "What"
POS = 0
MAX_POS = 1              # single-token KV cache

device = metal_device()
queue = metal_queue(device)

<< "loading qwen3 GGUF + tokenizer..."
g = GGUF.new(GGUF_PATH)
tok = Tokenizer.new(g)

# ── Compile every kernel we need ──
rms_pipe       = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/rms_norm.metal")), "rms_norm")
phn_pipe       = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/per_head_norm.metal")), "per_head_norm")
rope_pipe      = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/rope.metal")), "rope_neox")
kv_pipe        = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/kv_write.metal")), "kv_write")
scores_pipe    = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/attn_scores.metal")), "attn_scores")
softmax_pipe   = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/attn_softmax.metal")), "attn_softmax")
weighted_pipe  = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/attn_weighted_sum.metal")), "attn_weighted_sum")
q8_pipe        = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/q8_matvec_coop.metal")), "q8_matvec_coop")
f16_pipe       = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/f16_matvec.metal")), "f16_matvec")
f32_pipe       = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/f32_matvec.metal")), "f32_matvec")
expert_pipe    = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/q8_matvec_expert.metal")), "q8_matvec_expert")
silu_pipe      = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/silu_mul.metal")), "silu_mul")
add_pipe       = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/residual_add.metal")), "residual_add")

# ── Tensor handles ──
embd       = Tensor.new(g, g.tensor("token_embd.weight"))            # Q8_0 [2048, 151936]
out_norm_t = Tensor.new(g, g.tensor("output_norm.weight"))           # F32 [2048]
lm_head_t  = Tensor.new(g, g.tensor("output.weight"))                # Q8_0 [2048, 151936]

# Block 0
attn_norm_t = Tensor.new(g, g.tensor("blk.0.attn_norm.weight"))      # F32 [2048]
q_proj_t    = Tensor.new(g, g.tensor("blk.0.attn_q.weight"))         # Q8_0 [2048, 4096]
k_proj_t    = Tensor.new(g, g.tensor("blk.0.attn_k.weight"))         # Q8_0 [2048, 512]
v_proj_t    = Tensor.new(g, g.tensor("blk.0.attn_v.weight"))         # F16  [2048, 512]
o_proj_t    = Tensor.new(g, g.tensor("blk.0.attn_output.weight"))    # Q8_0 [4096, 2048]
q_norm_t    = Tensor.new(g, g.tensor("blk.0.attn_q_norm.weight"))    # F32 [128]
k_norm_t    = Tensor.new(g, g.tensor("blk.0.attn_k_norm.weight"))    # F32 [128]
ffn_norm_t  = Tensor.new(g, g.tensor("blk.0.ffn_norm.weight"))       # F32 [2048]
router_t    = Tensor.new(g, g.tensor("blk.0.ffn_gate_inp.weight"))   # F32 [2048, 128]
gate_t      = Tensor.new(g, g.tensor("blk.0.ffn_gate_exps.weight"))  # Q8_0 [2048, 768, 128]
up_t        = Tensor.new(g, g.tensor("blk.0.ffn_up_exps.weight"))    # Q8_0 [2048, 768, 128]
down_t      = Tensor.new(g, g.tensor("blk.0.ffn_down_exps.weight"))  # Q8_0 [768, 2048, 128]

<< "uploading top-level + block 0 weights..."
out_norm_buf = out_norm_t.upload_f32(device)
lm_parts     = lm_head_t.upload_q8(device)

attn_norm_buf = attn_norm_t.upload_f32(device)
q_proj_parts  = q_proj_t.upload_q8(device)
k_proj_parts  = k_proj_t.upload_q8(device)
# v_proj is F16; bytes go straight into a metal buffer that the kernel reads as half[]
v_proj_buf    = metal_buffer(device, v_proj_t.byte_length)
metal_buffer_write_from_mmap(v_proj_buf, 0, g.mmap, v_proj_t.file_offset, v_proj_t.byte_length)
o_proj_parts  = o_proj_t.upload_q8(device)
q_norm_buf    = q_norm_t.upload_f32(device)
k_norm_buf    = k_norm_t.upload_f32(device)
ffn_norm_buf  = ffn_norm_t.upload_f32(device)
router_buf    = router_t.upload_f32(device)
gate_parts    = gate_t.upload_q8(device)
up_parts      = up_t.upload_q8(device)
down_parts    = down_t.upload_q8(device)
<< "  done."

# ── Per-step buffers ──
x_buf       = metal_buffer(device, HIDDEN * 4)
xn_buf      = metal_buffer(device, HIDDEN * 4)
q_buf       = metal_buffer(device, N_Q_HEADS * HEAD_DIM * 4)   # 4096
k_buf       = metal_buffer(device, KV_ROW * 4)                  # 512
v_buf       = metal_buffer(device, KV_ROW * 4)                  # 512
k_cache     = metal_buffer(device, MAX_POS * KV_ROW * 4)
v_cache     = metal_buffer(device, MAX_POS * KV_ROW * 4)
cos_buf     = metal_buffer(device, HEAD_DIM_HALF * 4)
sin_buf     = metal_buffer(device, HEAD_DIM_HALF * 4)
scores_buf  = metal_buffer(device, N_Q_HEADS * MAX_POS * 4)
attn_out    = metal_buffer(device, N_Q_HEADS * HEAD_DIM * 4)   # 4096
attn_proj   = metal_buffer(device, HIDDEN * 4)
hg_buf      = metal_buffer(device, EXPERT_FFN * 4)
hu_buf      = metal_buffer(device, EXPERT_FFN * 4)
h_buf       = metal_buffer(device, EXPERT_FFN * 4)
out_part    = metal_buffer(device, HIDDEN * 4)
ffn_out     = metal_buffer(device, HIDDEN * 4)
router_scores = metal_buffer(device, N_EXPERTS * 4)
logits_buf  = metal_buffer(device, N_VOCAB * 4)

# ── Constants ──
hidden_buf  = metal_buffer(device, 4) ; metal_buffer_write_i32(hidden_buf, 0, HIDDEN)
inv_h_buf   = metal_buffer(device, 4) ; metal_buffer_write_f32(inv_h_buf, 0, ~1.0 / HIDDEN)
eps_buf     = metal_buffer(device, 4) ; metal_buffer_write_f32(eps_buf, 0, EPS)
hd_buf      = metal_buffer(device, 4) ; metal_buffer_write_i32(hd_buf, 0, HEAD_DIM)
inv_d_buf   = metal_buffer(device, 4) ; metal_buffer_write_f32(inv_d_buf, 0, ~1.0 / HEAD_DIM)
hdh_buf     = metal_buffer(device, 4) ; metal_buffer_write_i32(hdh_buf, 0, HEAD_DIM_HALF)
n_q_buf     = metal_buffer(device, 4) ; metal_buffer_write_i32(n_q_buf, 0, N_Q_HEADS)
n_kv_buf    = metal_buffer(device, 4) ; metal_buffer_write_i32(n_kv_buf, 0, N_KV_HEADS)
gs_buf      = metal_buffer(device, 4) ; metal_buffer_write_i32(gs_buf, 0, GROUP_SIZE)
n_pos_buf   = metal_buffer(device, 4) ; metal_buffer_write_i32(n_pos_buf, 0, 1)
scale_buf   = metal_buffer(device, 4) ; metal_buffer_write_f32(scale_buf, 0, ~1.0 / Math.sqrt(~0.0 + HEAD_DIM))
kv_row_buf  = metal_buffer(device, 4) ; metal_buffer_write_i32(kv_row_buf, 0, KV_ROW)
pos_buf     = metal_buffer(device, 4) ; metal_buffer_write_i32(pos_buf, 0, POS)
kdim_q_buf  = metal_buffer(device, 4) ; metal_buffer_write_i32(kdim_q_buf, 0, HIDDEN)        # q_proj K=2048
nrows_q_buf = metal_buffer(device, 4) ; metal_buffer_write_i32(nrows_q_buf, 0, 4096)         # q_proj N=4096
kdim_kv_buf = metal_buffer(device, 4) ; metal_buffer_write_i32(kdim_kv_buf, 0, HIDDEN)        # k/v_proj K=2048
nrows_kv_buf = metal_buffer(device, 4) ; metal_buffer_write_i32(nrows_kv_buf, 0, KV_ROW)      # 512
kdim_o_buf  = metal_buffer(device, 4) ; metal_buffer_write_i32(kdim_o_buf, 0, 4096)          # o_proj K=4096
nrows_o_buf = metal_buffer(device, 4) ; metal_buffer_write_i32(nrows_o_buf, 0, HIDDEN)
kdim_lm_buf = metal_buffer(device, 4) ; metal_buffer_write_i32(kdim_lm_buf, 0, HIDDEN)
n_silu_buf  = metal_buffer(device, 4) ; metal_buffer_write_i32(n_silu_buf, 0, EXPERT_FFN)
exp_idx_buf = metal_buffer(device, 4)
ffn_n_buf = metal_buffer(device, 4) ; metal_buffer_write_i32(ffn_n_buf, 0, EXPERT_FFN)
nrows_gate_buf = metal_buffer(device, 4) ; metal_buffer_write_i32(nrows_gate_buf, 0, EXPERT_FFN)
nrows_down_buf = metal_buffer(device, 4) ; metal_buffer_write_i32(nrows_down_buf, 0, HIDDEN)
kdim_down_buf = metal_buffer(device, 4) ; metal_buffer_write_i32(kdim_down_buf, 0, EXPERT_FFN)

# CPU-side cos/sin tables for RoPE at position POS.
inv_hd = ~2.0 / HEAD_DIM
log_base = Math.log(BASE)
i = 0
while i < HEAD_DIM_HALF
  theta = Math.exp(log_base * (~0.0 - i * inv_hd))
  angle = POS * theta
  metal_buffer_write_f32(cos_buf, i, Math.cos(angle))
  metal_buffer_write_f32(sin_buf, i, Math.sin(angle))
  i = i + 1

# ── Step 1: dequant token embedding into x ──
nb_h = HIDDEN / 32
src_off = embd.file_offset + TOKEN_ID * nb_h * 34
metal_q8_dequant_row(x_buf, 0, g.mmap, src_off, nb_h)
<< "embedded token " + TOKEN_ID.to_s + " (\"" + tok.tokens[TOKEN_ID] + "\")"

# Save copy of x for residual.
i = 0
while i < HIDDEN
  metal_buffer_write_f32(out_part, i, metal_buffer_read_f32(x_buf, i))
  i = i + 1

# ── Step 2: attn_norm ──
metal_dispatch_groups(queue, rms_pipe, [x_buf, attn_norm_buf, xn_buf, hidden_buf, inv_h_buf, eps_buf], 1, 32)

# ── Step 3: Q, K, V projections ──
metal_dispatch_groups(queue, q8_pipe, [q_proj_parts[:quants], q_proj_parts[:scales], xn_buf, q_buf, kdim_q_buf], 4096, 32)
metal_dispatch_groups(queue, q8_pipe, [k_proj_parts[:quants], k_proj_parts[:scales], xn_buf, k_buf, kdim_kv_buf], KV_ROW, 32)
metal_dispatch_groups(queue, f16_pipe, [v_proj_buf, xn_buf, v_buf, kdim_kv_buf], KV_ROW, 32)

# ── Step 4: per-head norm on Q and K ──
metal_dispatch_groups(queue, phn_pipe, [q_buf, q_norm_buf, hd_buf, inv_d_buf, eps_buf], N_Q_HEADS, 32)
metal_dispatch_groups(queue, phn_pipe, [k_buf, k_norm_buf, hd_buf, inv_d_buf, eps_buf], N_KV_HEADS, 32)

# ── Step 5: RoPE on Q and K ──
metal_dispatch_n(queue, rope_pipe, [q_buf, cos_buf, sin_buf, hd_buf, hdh_buf, n_q_buf], N_Q_HEADS * HEAD_DIM_HALF)
metal_dispatch_n(queue, rope_pipe, [k_buf, cos_buf, sin_buf, hd_buf, hdh_buf, n_kv_buf], N_KV_HEADS * HEAD_DIM_HALF)

# ── Step 6: write K and V into the cache at this position ──
metal_dispatch_n(queue, kv_pipe, [k_buf, k_cache, pos_buf, kv_row_buf], KV_ROW)
metal_dispatch_n(queue, kv_pipe, [v_buf, v_cache, pos_buf, kv_row_buf], KV_ROW)

# ── Step 7: attention scores → softmax → weighted sum ──
metal_dispatch_n(queue, scores_pipe, [q_buf, k_cache, scores_buf, hd_buf, n_kv_buf, gs_buf, n_pos_buf, scale_buf], N_Q_HEADS * 1)
metal_dispatch_groups(queue, softmax_pipe, [scores_buf, n_pos_buf], N_Q_HEADS, 32)
metal_dispatch_n(queue, weighted_pipe, [scores_buf, v_cache, attn_out, hd_buf, n_kv_buf, gs_buf, n_pos_buf], N_Q_HEADS * HEAD_DIM)

# ── Step 8: output projection (4096 → 2048) ──
metal_dispatch_groups(queue, q8_pipe, [o_proj_parts[:quants], o_proj_parts[:scales], attn_out, attn_proj, kdim_o_buf], HIDDEN, 32)

# ── Step 9: residual add (x = x + attn_proj) ──
# Restore x from out_part (pre-norm copy), then add attn_proj.
i = 0
while i < HIDDEN
  metal_buffer_write_f32(x_buf, i, metal_buffer_read_f32(out_part, i))
  i = i + 1
metal_dispatch_n(queue, add_pipe, [x_buf, attn_proj, hidden_buf], HIDDEN)

# Save current x for the FFN residual.
i = 0
while i < HIDDEN
  metal_buffer_write_f32(out_part, i, metal_buffer_read_f32(x_buf, i))
  i = i + 1

# ── Step 10: ffn_norm ──
metal_dispatch_groups(queue, rms_pipe, [x_buf, ffn_norm_buf, xn_buf, hidden_buf, inv_h_buf, eps_buf], 1, 32)

# ── Step 11: MoE FFN ──
metal_dispatch_groups(queue, f32_pipe, [router_buf, xn_buf, router_scores, hidden_buf], N_EXPERTS, 32)

# Read scores, top-K, softmax (CPU)
all_scores = []
i = 0
while i < N_EXPERTS
  all_scores.push(metal_buffer_read_f32(router_scores, i))
  i = i + 1
selected_ids = []
selected_logits = []
i = 0
while i < TOP_K
  best_v = ~-1000000000.0
  best_i = -1
  j = 0
  while j < N_EXPERTS
    if all_scores[j] > best_v
      best_v = all_scores[j]
      best_i = j
    j = j + 1
  selected_ids.push(best_i)
  selected_logits.push(best_v)
  all_scores[best_i] = ~-1000000000.0
  i = i + 1

max_l = selected_logits[0]
i = 1
while i < TOP_K
  if selected_logits[i] > max_l
    max_l = selected_logits[i]
  i = i + 1
sum_e = ~0.0
exps = []
i = 0
while i < TOP_K
  e = Math.exp(selected_logits[i] - max_l)
  exps.push(e)
  sum_e = sum_e + e
  i = i + 1
weights = []
i = 0
while i < TOP_K
  weights.push(exps[i] / sum_e)
  i = i + 1

# Zero ffn_out, accumulate per expert.
i = 0
while i < HIDDEN
  metal_buffer_write_f32(ffn_out, i, ~0.0)
  i = i + 1

i = 0
while i < TOP_K
  e_id = selected_ids[i]
  w_i = weights[i]
  metal_buffer_write_i32(exp_idx_buf, 0, e_id)
  metal_dispatch_groups(queue, expert_pipe, [gate_parts[:quants], gate_parts[:scales], xn_buf, hg_buf, hidden_buf, nrows_gate_buf, exp_idx_buf], EXPERT_FFN, 32)
  metal_dispatch_groups(queue, expert_pipe, [up_parts[:quants], up_parts[:scales], xn_buf, hu_buf, hidden_buf, nrows_gate_buf, exp_idx_buf], EXPERT_FFN, 32)
  metal_dispatch_n(queue, silu_pipe, [hg_buf, hu_buf, h_buf, n_silu_buf], EXPERT_FFN)
  metal_dispatch_groups(queue, expert_pipe, [down_parts[:quants], down_parts[:scales], h_buf, x_buf, kdim_down_buf, nrows_down_buf, exp_idx_buf], HIDDEN, 32)
  # CPU-side weighted accumulate (perf later).
  j = 0
  while j < HIDDEN
    cur = metal_buffer_read_f32(ffn_out, j)
    add = metal_buffer_read_f32(x_buf, j)
    metal_buffer_write_f32(ffn_out, j, cur + w_i * add)
    j = j + 1
  i = i + 1

<< "router selected experts: " + selected_ids.to_s

# ── Step 12: FFN residual (x = saved_x + ffn_out) ──
i = 0
while i < HIDDEN
  metal_buffer_write_f32(x_buf, i, metal_buffer_read_f32(out_part, i))
  i = i + 1
metal_dispatch_n(queue, add_pipe, [x_buf, ffn_out, hidden_buf], HIDDEN)

# ── Step 13: output norm ──
metal_dispatch_groups(queue, rms_pipe, [x_buf, out_norm_buf, xn_buf, hidden_buf, inv_h_buf, eps_buf], 1, 32)

# ── Step 14: lm_head matvec → logits ──
metal_dispatch_groups(queue, q8_pipe, [lm_parts[:quants], lm_parts[:scales], xn_buf, logits_buf, kdim_lm_buf], N_VOCAB, 32)

# ── Step 15: argmax over logits ──
best_id = 0
best_val = metal_buffer_read_f32(logits_buf, 0)
i = 1
while i < N_VOCAB
  v = metal_buffer_read_f32(logits_buf, i)
  if v > best_val
    best_val = v
    best_id = i
  i = i + 1

<< ""
<< "single-block forward complete"
<< "  predicted next token id = " + best_id.to_s
<< "  decoded = '" + tok.decode([best_id]) + "'"
<< "  (only block 0 ran; no transformer stack — this isn't real LM output,"
<< "   but every kernel in the forward pipeline executed end-to-end)"

g.close
