# Real-weights MoE FFN smoke. Loads block 0 of qwen3 from disk, runs:
#   x → ffn_norm → router → top-8 selection → 8× SwiGLU → weighted sum
# all on GPU. Verifies the result is plausible (non-zero, finite,
# magnitude in the same range as a good FFN's output).
#
# Memory: one MoE block's expert weights are ~640 MB on disk. That fits
# easily on M3 Max unified memory; whole-model weight residency is a
# later phase.

use core/metal
use tungsten-llama/gguf
use tungsten-llama/tensor

GGUF_PATH = "/Users/erik/.ollama/models/blobs/sha256-ae354763fe478c790125fb993e59bb1266655b3fa721eebe4a931660c3ed2ce9"
HIDDEN = 2048
EXPERT_FFN = 768
N_EXPERTS = 128
TOP_K = 8
EPS = ~0.000001

device = metal_device()
queue = metal_queue(device)

rms_pipe   = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/rms_norm.metal")), "rms_norm")
f32mv_pipe = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/f32_matvec.metal")), "f32_matvec")
expert_pipe = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/q8_matvec_expert.metal")), "q8_matvec_expert")
silu_pipe  = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/silu_mul.metal")), "silu_mul")

<< "loading qwen3 block 0 MoE tensors..."
g = GGUF.new(GGUF_PATH)
norm_t = Tensor.new(g, g.tensor("blk.0.ffn_norm.weight"))       # F32 [2048]
router_t = Tensor.new(g, g.tensor("blk.0.ffn_gate_inp.weight")) # F32 [2048, 128]
gate_t = Tensor.new(g, g.tensor("blk.0.ffn_gate_exps.weight"))  # Q8_0 [2048, 768, 128]
up_t = Tensor.new(g, g.tensor("blk.0.ffn_up_exps.weight"))      # Q8_0 [2048, 768, 128]
down_t = Tensor.new(g, g.tensor("blk.0.ffn_down_exps.weight"))  # Q8_0 [768, 2048, 128]

<< "uploading expert weights to GPU (~640 MB)..."
norm_buf = norm_t.upload_f32(device)
router_buf = router_t.upload_f32(device)
gate_parts = gate_t.upload_q8(device)
up_parts = up_t.upload_q8(device)
down_parts = down_t.upload_q8(device)
<< "  done."

# Per-iteration buffers
x_buf      = metal_buffer(device, HIDDEN * 4)
xn_buf     = metal_buffer(device, HIDDEN * 4)
scores_buf = metal_buffer(device, N_EXPERTS * 4)
hg_buf     = metal_buffer(device, EXPERT_FFN * 4)
hu_buf     = metal_buffer(device, EXPERT_FFN * 4)
h_buf      = metal_buffer(device, EXPERT_FFN * 4)
out_part   = metal_buffer(device, HIDDEN * 4)
out_buf    = metal_buffer(device, HIDDEN * 4)

# Constants
hidden_buf = metal_buffer(device, 4)
inv_h_buf  = metal_buffer(device, 4)
eps_buf    = metal_buffer(device, 4)
exp_idx_buf = metal_buffer(device, 4)
nrows_gu_buf = metal_buffer(device, 4)
nrows_d_buf = metal_buffer(device, 4)
kdim_h_buf = metal_buffer(device, 4)
kdim_e_buf = metal_buffer(device, 4)
n_silu_buf = metal_buffer(device, 4)

metal_buffer_write_i32(hidden_buf, 0, HIDDEN)
metal_buffer_write_f32(inv_h_buf, 0, ~1.0 / HIDDEN)
metal_buffer_write_f32(eps_buf, 0, EPS)
metal_buffer_write_i32(nrows_gu_buf, 0, EXPERT_FFN)  # gate/up: 768 output rows
metal_buffer_write_i32(nrows_d_buf, 0, HIDDEN)       # down: 2048 output rows
metal_buffer_write_i32(kdim_h_buf, 0, HIDDEN)        # gate/up: K=2048
metal_buffer_write_i32(kdim_e_buf, 0, EXPERT_FFN)    # down: K=768
metal_buffer_write_i32(n_silu_buf, 0, EXPERT_FFN)

# Build a deterministic input: x[i] = sin(i * 0.013) * 0.1.
i = 0
while i < HIDDEN
  metal_buffer_write_f32(x_buf, i, Math.sin(i * ~0.013) * ~0.1)
  i = i + 1

# 1. xn = rms_norm(x, w_norm)
rms_bufs = [x_buf, norm_buf, xn_buf, hidden_buf, inv_h_buf, eps_buf]
metal_dispatch_groups(queue, rms_pipe, rms_bufs, 1, 32)

# 2. router scores = router_w @ xn, shape [128]
router_bufs = [router_buf, xn_buf, scores_buf, hidden_buf]
metal_dispatch_groups(queue, f32mv_pipe, router_bufs, N_EXPERTS, 32)

# 3. CPU-side: read scores, softmax, top-k.
all_scores = []
i = 0
while i < N_EXPERTS
  all_scores.push(metal_buffer_read_f32(scores_buf, i))
  i = i + 1

# Top-K selection by repeated argmax with masking.
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

# Softmax over the top-k logits → routing weights summing to 1.0.
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

<< "router selected experts: " + selected_ids.to_s
<< "router weights: " + weights.to_s

# Zero out the accumulator buffer.
i = 0
while i < HIDDEN
  metal_buffer_write_f32(out_buf, i, ~0.0)
  i = i + 1

# 4. For each selected expert, run gate / up / silu_mul / down,
#    then weighted-accumulate into out_buf.
i = 0
while i < TOP_K
  e_id = selected_ids[i]
  w_i = weights[i]
  metal_buffer_write_i32(exp_idx_buf, 0, e_id)

  # h_gate = W_gate[e_id] @ xn
  gate_bufs = [gate_parts[:quants], gate_parts[:scales], xn_buf, hg_buf, kdim_h_buf, nrows_gu_buf, exp_idx_buf]
  metal_dispatch_groups(queue, expert_pipe, gate_bufs, EXPERT_FFN, 32)

  # h_up = W_up[e_id] @ xn
  up_bufs = [up_parts[:quants], up_parts[:scales], xn_buf, hu_buf, kdim_h_buf, nrows_gu_buf, exp_idx_buf]
  metal_dispatch_groups(queue, expert_pipe, up_bufs, EXPERT_FFN, 32)

  # h = silu(h_gate) * h_up
  silu_bufs = [hg_buf, hu_buf, h_buf, n_silu_buf]
  metal_dispatch_n(queue, silu_pipe, silu_bufs, EXPERT_FFN)

  # out_part = W_down[e_id] @ h
  down_bufs = [down_parts[:quants], down_parts[:scales], h_buf, out_part, kdim_e_buf, nrows_d_buf, exp_idx_buf]
  metal_dispatch_groups(queue, expert_pipe, down_bufs, HIDDEN, 32)

  # CPU read+accumulate (a fused weighted-add kernel comes in a perf pass).
  j = 0
  while j < HIDDEN
    cur = metal_buffer_read_f32(out_buf, j)
    add = metal_buffer_read_f32(out_part, j)
    metal_buffer_write_f32(out_buf, j, cur + w_i * add)
    j = j + 1

  i = i + 1

# Sanity check the output.
non_zero = 0
sum_sq = ~0.0
abs_max = ~0.0
i = 0
while i < HIDDEN
  v = metal_buffer_read_f32(out_buf, i)
  if v != ~0.0
    non_zero = non_zero + 1
  sum_sq = sum_sq + v * v
  av = v
  if av < ~0.0
    av = ~0.0 - av
  if av > abs_max
    abs_max = av
  i = i + 1

<< "MoE output: non_zero=" + non_zero.to_s + "/" + HIDDEN.to_s + ", L2² = " + sum_sq.to_s + ", |max| = " + abs_max.to_s
if non_zero < HIDDEN / 2
  << "FAIL: too many zeros"
  exit 1
if abs_max > ~100.0
  << "FAIL: blew up"
  exit 1
<< "OK — MoE FFN layer 0 ran end-to-end on real qwen3 weights"

g.close
