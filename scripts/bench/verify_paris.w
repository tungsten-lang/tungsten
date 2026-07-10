# Verification gate (P5.9): full 48-layer qwen3 forward pass on real
# weights, prompt "The capital of France is", verify the next token
# decodes to " Paris" (with the GPT-2 leading-space marker).
#
# Memory: each block is ~660 MB on disk (mostly the three Q8_0 expert
# tensors at 213 MB each). 48 blocks ≈ 32 GB of Metal buffer
# allocations + ~660 MB top-level (token_embd, lm_head, output_norm).
# Comfortable on a 64+ GB unified-memory M3.

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
GROUP_SIZE = 8
KV_ROW = 512
EXPERT_FFN = 768
N_EXPERTS = 128
TOP_K = 8
EPS = ~0.000001
BASE = ~1000000.0
N_VOCAB = 151936
N_LAYERS = 48
MAX_POS = 32

device = metal_device()
queue = metal_queue(device)

<< "loading qwen3 GGUF + tokenizer..."
g = GGUF.new(GGUF_PATH)
tok = Tokenizer.new(g)

rms_pipe       = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/rms_norm.metal")), "rms_norm")
phn_pipe       = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/per_head_norm.metal")), "per_head_norm")
rope_pipe      = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/rope.metal")), "rope_neox")
kv_pipe        = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/kv_write.metal")), "kv_write")
scores_pipe    = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/attn_scores.metal")), "attn_scores")
softmax_pipe   = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/attn_softmax.metal")), "attn_softmax")
weighted_pipe  = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/attn_weighted_sum.metal")), "attn_weighted_sum")
flash_pipe     = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/flash_attn.metal")), "flash_attn")
q8_pipe        = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/q8_matvec_coop_v2.metal")), "q8_matvec_coop_v2")
q8r_pipe       = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/q8_matvec_coop_residual.metal")), "q8_matvec_coop_residual")
f16_pipe       = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/f16_matvec.metal")), "f16_matvec")
f32_pipe       = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/f32_matvec.metal")), "f32_matvec")
expert_pipe    = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/q8_matvec_expert_v2.metal")), "q8_matvec_expert_v2")
silu_down_pipe = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/q8_matvec_silu_down_expert.metal")), "q8_matvec_silu_down_expert")
silu_pipe      = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/silu_mul.metal")), "silu_mul")
silu8_pipe     = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/silu_mul_8.metal")), "silu_mul_8")
add_pipe       = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/residual_add.metal")), "residual_add")
wadd_pipe      = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/weighted_add.metal")), "weighted_add")
argmax_pipe    = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/argmax.metal")), "argmax")
gate_up_pipe   = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/q8_matvec_gate_up_expert_v2.metal")), "q8_matvec_gate_up_expert_v2")
combine8_pipe  = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/moe_combine_8.metal")), "moe_combine_8")
combine8r_pipe = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/moe_combine_8_residual.metal")), "moe_combine_8_residual")
phnr_pipe      = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/per_head_norm_rope.metal")), "per_head_norm_rope")
phnrc_pipe     = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/per_head_norm_rope_to_cache.metal")), "per_head_norm_rope_to_cache")
f16c_pipe      = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/f16_matvec_to_cache.metal")), "f16_matvec_to_cache")
topk_pipe      = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/router_topk_8.metal")), "router_topk_8")
router_topk_pipe = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/router_matvec_topk_8.metal")), "router_matvec_topk_8")

embd_t      = g.tensor("token_embd.weight")
embd_off    = g.tensor_file_offset(embd_t)
out_norm_buf = Tensor.new(g, g.tensor("output_norm.weight")).upload_f32(device)
lm_parts     = Tensor.new(g, g.tensor("output.weight")).upload_q8(device)

# Load every block 0..N_LAYERS into an array of layer hashes.
-> load_layer(li)
  prefix = "blk." + li.to_s + "."
  v_proj_t = Tensor.new(g, g.tensor(prefix + "attn_v.weight"))
  v_buf = metal_buffer(device, v_proj_t.byte_length)
  metal_buffer_write_from_mmap(v_buf, 0, g.mmap, v_proj_t.file_offset, v_proj_t.byte_length)
  {
    attn_norm: Tensor.new(g, g.tensor(prefix + "attn_norm.weight")).upload_f32(device),
    q_proj:    Tensor.new(g, g.tensor(prefix + "attn_q.weight")).upload_q8(device),
    k_proj:    Tensor.new(g, g.tensor(prefix + "attn_k.weight")).upload_q8(device),
    v_proj:    v_buf,
    o_proj:    Tensor.new(g, g.tensor(prefix + "attn_output.weight")).upload_q8(device),
    q_norm:    Tensor.new(g, g.tensor(prefix + "attn_q_norm.weight")).upload_f32(device),
    k_norm:    Tensor.new(g, g.tensor(prefix + "attn_k_norm.weight")).upload_f32(device),
    ffn_norm:  Tensor.new(g, g.tensor(prefix + "ffn_norm.weight")).upload_f32(device),
    router:    Tensor.new(g, g.tensor(prefix + "ffn_gate_inp.weight")).upload_f32(device),
    gate:      Tensor.new(g, g.tensor(prefix + "ffn_gate_exps.weight")).upload_q8(device),
    up:        Tensor.new(g, g.tensor(prefix + "ffn_up_exps.weight")).upload_q8(device),
    down:      Tensor.new(g, g.tensor(prefix + "ffn_down_exps.weight")).upload_q8(device),
    k_cache:   metal_buffer(device, MAX_POS * KV_ROW * 4),
    v_cache:   metal_buffer(device, MAX_POS * KV_ROW * 4)
  }

<< "uploading " + N_LAYERS.to_s + " blocks (~" + (N_LAYERS * 660).to_s + " MB)..."
layers = []
li = 0
while li < N_LAYERS
  if li % 8 == 0
    << "  layer " + li.to_s + "/" + N_LAYERS.to_s + "..."
  layers.push(load_layer(li))
  li = li + 1
<< "  done."

# Per-step buffers (shared across layers — mutated in-place each block)
x_buf       = metal_buffer(device, HIDDEN * 4)
xn_buf      = metal_buffer(device, HIDDEN * 4)
q_buf       = metal_buffer(device, N_Q_HEADS * HEAD_DIM * 4)
k_buf       = metal_buffer(device, KV_ROW * 4)
v_buf       = metal_buffer(device, KV_ROW * 4)
cos_buf     = metal_buffer(device, HEAD_DIM_HALF * 4)
sin_buf     = metal_buffer(device, HEAD_DIM_HALF * 4)
scores_buf  = metal_buffer(device, N_Q_HEADS * MAX_POS * 4)
attn_out    = metal_buffer(device, N_Q_HEADS * HEAD_DIM * 4)
attn_proj   = metal_buffer(device, HIDDEN * 4)
# Per-slot intermediates so the 8 expert chains can be reordered into
# 4 phases (all gate+ups, then all silus, then all downs, then all
# wadds) — minimizes pipeline-state switches inside the batch.
hg_slots = []
hu_slots = []
h_slots  = []
eo_slots = []
i = 0
while i < TOP_K
  hg_slots.push(metal_buffer(device, EXPERT_FFN * 4))
  hu_slots.push(metal_buffer(device, EXPERT_FFN * 4))
  h_slots.push(metal_buffer(device, EXPERT_FFN * 4))
  eo_slots.push(metal_buffer(device, HIDDEN * 4))
  i = i + 1
ffn_out     = metal_buffer(device, HIDDEN * 4)
router_scores = metal_buffer(device, N_EXPERTS * 4)
logits_buf  = metal_buffer(device, N_VOCAB * 4)
argmax_buf  = metal_buffer(device, 4)
n_vocab_buf = metal_buffer(device, 4)

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
kdim_q_buf  = metal_buffer(device, 4) ; metal_buffer_write_i32(kdim_q_buf, 0, HIDDEN)
kdim_kv_buf = metal_buffer(device, 4) ; metal_buffer_write_i32(kdim_kv_buf, 0, HIDDEN)
kdim_o_buf  = metal_buffer(device, 4) ; metal_buffer_write_i32(kdim_o_buf, 0, 4096)
kdim_lm_buf = metal_buffer(device, 4) ; metal_buffer_write_i32(kdim_lm_buf, 0, HIDDEN)
n_silu_buf  = metal_buffer(device, 4) ; metal_buffer_write_i32(n_silu_buf, 0, EXPERT_FFN)
nrows_gate_buf = metal_buffer(device, 4) ; metal_buffer_write_i32(nrows_gate_buf, 0, EXPERT_FFN)
nrows_down_buf = metal_buffer(device, 4) ; metal_buffer_write_i32(nrows_down_buf, 0, HIDDEN)
kdim_down_buf  = metal_buffer(device, 4) ; metal_buffer_write_i32(kdim_down_buf, 0, EXPERT_FFN)
n_experts_buf  = metal_buffer(device, 4) ; metal_buffer_write_i32(n_experts_buf, 0, N_EXPERTS)
metal_buffer_write_i32(n_vocab_buf, 0, N_VOCAB)

# Per-expert constant buffers: 8 exp_idx bufs + 8 w_scalar bufs. Having
# eight distinct buffers lets all eight experts' dispatches encode into
# one batched command buffer without each reading the same (last-written)
# constant at GPU execution time.
exp_idx_bufs = []
w_scalar_bufs = []
i = 0
while i < TOP_K
  exp_idx_bufs.push(metal_buffer(device, 4))
  w_scalar_bufs.push(metal_buffer(device, 4))
  i = i + 1
# Packed weights for moe_combine_8 — same 8 floats as w_scalar_bufs but
# in one contiguous buffer the kernel can index by slot.
weights_packed = metal_buffer(device, TOP_K * 4)

log_base = Math.log(BASE)
inv_hd = ~2.0 / HEAD_DIM
nb_h = HIDDEN / 32


-> build_rope_tables(pos)
  i = 0
  while i < HEAD_DIM_HALF
    theta = Math.exp(log_base * (~0.0 - i * inv_hd))
    angle = pos * theta
    metal_buffer_write_f32(cos_buf, i, Math.cos(angle))
    metal_buffer_write_f32(sin_buf, i, Math.sin(angle))
    i = i + 1

-> run_block(lyr, n_pos_active)
  # Caller is responsible for begin_concurrent / commit and for
  # writing pos_buf / n_pos_buf. This lets forward_step encode all
  # 48 layers + lm_head into a single command buffer (one commit
  # per token instead of 49).
  metal_dispatch_groups(queue, rms_pipe, [x_buf, lyr[:attn_norm], xn_buf, hidden_buf, inv_h_buf, eps_buf], 1, 512)
  metal_batch_barrier(queue)

  metal_dispatch_groups(queue, q8_pipe, [lyr[:q_proj][:quants], lyr[:q_proj][:scales], xn_buf, q_buf, kdim_q_buf], 4096, 32)
  metal_dispatch_groups(queue, q8_pipe, [lyr[:k_proj][:quants], lyr[:k_proj][:scales], xn_buf, k_buf, kdim_kv_buf], KV_ROW, 32)
  metal_dispatch_groups(queue, f16c_pipe, [lyr[:v_proj], xn_buf, lyr[:v_cache], kdim_kv_buf, pos_buf, kv_row_buf], KV_ROW, 32)
  metal_batch_barrier(queue)

  metal_dispatch_groups(queue, phnr_pipe, [q_buf, lyr[:q_norm], cos_buf, sin_buf, hd_buf, hdh_buf, inv_d_buf, eps_buf], N_Q_HEADS, 32)
  metal_dispatch_groups(queue, phnrc_pipe, [k_buf, lyr[:k_norm], cos_buf, sin_buf, lyr[:k_cache], hd_buf, hdh_buf, pos_buf, kv_row_buf, inv_d_buf, eps_buf], N_KV_HEADS, 32)
  metal_batch_barrier(queue)

  # Fused FlashAttention: scores + softmax + wsum in one dispatch.
  # Threadgroup memory holds the per-head scores between phases.
  metal_set_threadgroup_memory(queue, MAX_POS * 4, 0)
  metal_dispatch_groups(queue, flash_pipe, [q_buf, lyr[:k_cache], lyr[:v_cache], attn_out, hd_buf, n_kv_buf, gs_buf, n_pos_buf, scale_buf], N_Q_HEADS, 32)
  metal_batch_barrier(queue)

  metal_dispatch_groups(queue, q8r_pipe, [lyr[:o_proj][:quants], lyr[:o_proj][:scales], attn_out, x_buf, kdim_o_buf], HIDDEN, 32)
  metal_batch_barrier(queue)

  # FFN side: ffn_norm reads x_buf (now post-attn) and writes xn_buf;
  # the router + experts + ffn_out chain reads xn_buf and writes other
  # scratch buffers. x_buf survives untouched until the FFN residual.
  metal_dispatch_groups(queue, rms_pipe, [x_buf, lyr[:ffn_norm], xn_buf, hidden_buf, inv_h_buf, eps_buf], 1, 512)
  metal_batch_barrier(queue)
  metal_dispatch_groups(queue, f32_pipe, [lyr[:router], xn_buf, router_scores, hidden_buf], N_EXPERTS, 32)
  metal_batch_barrier(queue)
  metal_dispatch_groups(queue, topk_pipe, [router_scores, exp_idx_bufs[0], exp_idx_bufs[1], exp_idx_bufs[2], exp_idx_bufs[3], exp_idx_bufs[4], exp_idx_bufs[5], exp_idx_bufs[6], exp_idx_bufs[7], weights_packed, n_experts_buf], 1, 32)
  metal_batch_barrier(queue)

  # ── Expert phases — all in the same concurrent batch as the
  # pre-router work. 8 gate+ups → barrier → 8 silus → barrier →
  # 8 downs → barrier → moe_combine_8 → barrier → residual.
  j = 0
  while j < TOP_K
    metal_dispatch_groups(queue, gate_up_pipe, [lyr[:gate][:quants], lyr[:gate][:scales], lyr[:up][:quants], lyr[:up][:scales], xn_buf, hg_slots[j], hu_slots[j], hidden_buf, nrows_gate_buf, exp_idx_bufs[j]], EXPERT_FFN, 32)
    j = j + 1
  metal_batch_barrier(queue)
  # Fused (silu*mul) + down matvec, one dispatch per slot.
  # Silu staged in threadgroup memory, then matvec reads from there.
  j = 0
  while j < TOP_K
    metal_set_threadgroup_memory(queue, EXPERT_FFN * 4, 0)
    metal_dispatch_groups(queue, silu_down_pipe, [lyr[:down][:quants], lyr[:down][:scales], hg_slots[j], hu_slots[j], eo_slots[j], kdim_down_buf, nrows_down_buf, exp_idx_bufs[j]], HIDDEN / 32, 1024)
    j = j + 1
  metal_batch_barrier(queue)
  metal_dispatch_n(queue, combine8r_pipe, [x_buf, eo_slots[0], eo_slots[1], eo_slots[2], eo_slots[3], eo_slots[4], eo_slots[5], eo_slots[6], eo_slots[7], weights_packed, hidden_buf], HIDDEN)
  # Boundary into the next layer (or final norm) — x_buf was just
  # written by combine8_residual; whatever reads x_buf next must wait.
  metal_batch_barrier(queue)

-> forward_step(token_id, pos)
  src_off = embd_off + token_id * nb_h * 34
  metal_q8_dequant_row(x_buf, 0, g.mmap, src_off, nb_h)
  build_rope_tables(pos)
  metal_buffer_write_i32(pos_buf, 0, pos)
  n_pos_active = pos + 1
  metal_buffer_write_i32(n_pos_buf, 0, n_pos_active)
  # One concurrent batch for the entire token: 48 layers + final norm
  # + lm_head + argmax. Single commit, single GPU sync.
  metal_batch_begin_concurrent(queue)
  li = 0
  while li < N_LAYERS
    run_block(layers[li], n_pos_active)
    li = li + 1
  metal_dispatch_groups(queue, rms_pipe, [x_buf, out_norm_buf, xn_buf, hidden_buf, inv_h_buf, eps_buf], 1, 512)
  metal_batch_barrier(queue)
  metal_dispatch_groups(queue, q8_pipe, [lm_parts[:quants], lm_parts[:scales], xn_buf, logits_buf, kdim_lm_buf], N_VOCAB, 32)
  metal_batch_barrier(queue)
  metal_dispatch_groups(queue, argmax_pipe, [logits_buf, argmax_buf, n_vocab_buf], 1, 1024)
  metal_batch_commit(queue)
  metal_buffer_read_i32(argmax_buf, 0)

prompt = "The capital of France is"
prompt_ids = tok.encode(prompt)
<< "prompt: '" + prompt + "'"
<< "prompt ids: " + prompt_ids.to_s

# Pre-fill: feed each prompt token through the network in order.
pos = 0
i = 0
last_pred = -1
t_prefill_start = ccall("__w_clock_ms")
while i < prompt_ids.size()
  last_pred = forward_step(prompt_ids[i], pos)
  pos = pos + 1
  i = i + 1
t_prefill = ccall("__w_clock_ms") - t_prefill_start
<< ""
<< "prefill: " + prompt_ids.size().to_s + " tokens in " + t_prefill.to_s + " ms (" + (t_prefill / prompt_ids.size()).to_s + " ms/token)"

<< ""
<< "next-token argmax = " + last_pred.to_s + " ('" + tok.decode([last_pred]) + "')"
<< "expected: ' Paris' (token 12095)"
expected = " Paris"
got = tok.decode([last_pred])
if got == expected
  << ""
  << "✓ PASS — Tungsten qwen3 inference matches expected behavior."
else
  << ""
  << "✗ MISMATCH — got '" + got + "' instead of '" + expected + "'."
  exit 1

g.close
