# qwen3.6 MoE forward test on layer 0.
#
# Validates the dual-MoE pipeline (256 routed experts top-8 + always-on
# shared expert with sigmoid gate) against MLX. Input: raw sin curve
# directly into post_attention_layernorm + MoE (skipping Mamba to isolate).
#
# Pipeline:
#   1.  rms_norm(x, post_attention_layernorm.weight)        →  xn
#   2.  router_logits = int8_affine_matvec(mlp.gate, xn)    →  [256]
#   3.  CPU softmax + argpartition top-8 → indices + scores
#   4.  CPU normalize: scores /= sum(scores)
#   5.  For each of 8 expert ids:
#         gate  = nvfp4(switch_mlp.gate_proj[id], xn)        →  [512]
#         up    = nvfp4(switch_mlp.up_proj[id],   xn)        →  [512]
#         hidden = silu(gate) * up                           →  [512]
#         down  = nvfp4(switch_mlp.down_proj[id], hidden)    →  [HIDDEN]
#         y    += scores[i] * down                           →  weighted_add
#   6.  Shared expert path:
#         sg    = sigmoid(int8_affine_matvec(shared_expert_gate, xn))  →  scalar
#         sgate = nvfp4(shared.gate_proj, xn)                →  [512]
#         sup   = nvfp4(shared.up_proj,   xn)                →  [512]
#         shidden = silu(sgate) * sup                         →  [512]
#         shared = nvfp4(shared.down_proj, shidden)          →  [HIDDEN]
#         y    += sg * shared
#
# Per-expert nvfp4 slicing: each [256, *, *] tensor is laid out row-major,
# so for expert e the byte offset is e * (per-expert byte size).

use core/metal
use tungsten-llama/sharded_safetensors

QWEN36_PATH = "/Users/erik/.cache/huggingface/hub/models--mlx-community--Qwen3.6-35B-A3B-nvfp4/snapshots/9c1a3a223ddd8a3425212cc421056614f149cf0f/model.safetensors.index.json"
SHARED_DIR  = "bits/tungsten-llama/lib/kernels/shared/"
NVFP4_DIR   = "bits/tungsten-llama/lib/kernels/nvfp4/"
INT8AFF_DIR = "bits/tungsten-llama/lib/kernels/int8_affine/"

HIDDEN       = 2048
EXPERT_FFN   = 512        # moe_intermediate_size
SHARED_FFN   = 512        # shared_expert_intermediate_size
N_EXPERTS    = 256
TOP_K        = 8
EPS          = ~0.000001

# Per-expert nvfp4 byte sizes (shared across gate/up/down — see comments above)
PER_EXPERT_W_BYTES = EXPERT_FFN * (HIDDEN / 8) * 4    # 512 × 256 × 4 = 524288
PER_EXPERT_S_BYTES = EXPERT_FFN * (HIDDEN / 16)        # 512 × 128       = 65536

device = metal_device()
queue  = metal_queue(device)

st = ShardedSafetensors.new(QWEN36_PATH)

# ---- Pipelines ----
rms_pipe       = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "rms_norm.metal")), "rms_norm")
nvfp4_mlx_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR  + "nvfp4_matvec_mlx.metal")), "nvfp4_matvec_mlx")
int8aff_pipe   = metal_pipeline(metal_compile_source(device, read_file(INT8AFF_DIR + "int8_affine_matvec.metal")), "int8_affine_matvec")
silu_pipe      = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "silu_mul.metal")), "silu_mul")
wadd_pipe      = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "weighted_add.metal")), "weighted_add")

prefix = "language_model.model.layers.0."

# ---- Input: raw sin curve ----
x_buf = metal_buffer(device, HIDDEN * 4)
i = 0
while i < HIDDEN
  metal_buffer_write_f32(x_buf, i, Math.sin(i * ~0.013))
  i = i + 1

# ---- Stage 1: post_attention_layernorm ----
norm_w_buf = metal_buffer(device, HIDDEN * 4)
nd = st.tensor(prefix + "post_attention_layernorm.weight")
nm = st.mmap_for(prefix + "post_attention_layernorm.weight")
i = 0
while i < HIDDEN
  off = nd[:byte_offset] + i * 2
  bits = nm.byte_at(off + 0) | (nm.byte_at(off + 1) << 8)
  metal_buffer_write_i32(norm_w_buf, i, bits << 16)
  i = i + 1

xn_buf = metal_buffer(device, HIDDEN * 4)
metal_batch_begin(queue)
metal_dispatch_groups(queue, rms_pipe, [x_buf, norm_w_buf, xn_buf, HIDDEN, ~1.0 / HIDDEN, EPS], 1, 256)
metal_batch_commit(queue)

REF_XN = [~0.0, ~0.016905, ~0.032226, ~0.043153, ~0.066730, ~0.078359, ~0.121599, ~0.102086]
max_d = ~0.0
i = 0
while i < 8
  got = metal_buffer_read_f32(xn_buf, i)
  d = got - REF_XN[i]
  if d < ~0.0 then d = ~0.0 - d
  if d > max_d then max_d = d
  i = i + 1
<< "Stage 1 (post_attention_layernorm) max diff: " + max_d.to_s
if max_d < ~0.001 then << "  PASS" else << "  FAIL"

# ---- Stage 2: router logits via int8_affine_matvec ----
rw_d = st.tensor(prefix + "mlp.gate.weight")
rs_d = st.tensor(prefix + "mlp.gate.scales")
rb_d = st.tensor(prefix + "mlp.gate.biases")
rw_v = st.mmap_for(prefix + "mlp.gate.weight").view_at(rw_d[:byte_offset], :u8, rw_d[:byte_length])
rs_v = st.mmap_for(prefix + "mlp.gate.scales").view_at(rs_d[:byte_offset], :u8, rs_d[:byte_length])
rb_v = st.mmap_for(prefix + "mlp.gate.biases").view_at(rb_d[:byte_offset], :u8, rb_d[:byte_length])
rw_buf = metal_buffer_for(device, rw_v)
rs_buf = metal_buffer_for(device, rs_v)
rb_buf = metal_buffer_for(device, rb_v)

router_buf = metal_buffer(device, N_EXPERTS * 4)
metal_batch_begin(queue)
metal_dispatch_groups(queue, int8aff_pipe, [rw_buf, rs_buf, rb_buf, xn_buf, router_buf, HIDDEN, N_EXPERTS], (N_EXPERTS + 7) / 8, 64)
metal_batch_commit(queue)

# ---- Stage 3-4: CPU softmax + topk-8 + normalize ----
# Read all 256 logits, find top-8 indices via partial sort
logits = []
i = 0
while i < N_EXPERTS
  logits.push(metal_buffer_read_f32(router_buf, i))
  i = i + 1

# Softmax (subtract max for numerical stability)
max_l = logits[0]
i = 1
while i < N_EXPERTS
  if logits[i] > max_l then max_l = logits[i]
  i = i + 1
sum_e = ~0.0
i = 0
while i < N_EXPERTS
  logits[i] = Math.exp(logits[i] - max_l)
  sum_e = sum_e + logits[i]
  i = i + 1
i = 0
while i < N_EXPERTS
  logits[i] = logits[i] / sum_e
  i = i + 1

# Top-8 via simple selection (k small, n=256)
top_indices = []
top_scores = []
sel_count = 0
while sel_count < TOP_K
  best_i = -1
  best_v = ~-1.0
  i = 0
  while i < N_EXPERTS
    # Skip if already selected
    is_taken = false
    j = 0
    while j < top_indices.size()
      if top_indices[j] == i then is_taken = true
      j = j + 1
    if (!is_taken) && logits[i] > best_v
      best_v = logits[i]
      best_i = i
    i = i + 1
  top_indices.push(best_i)
  top_scores.push(best_v)
  sel_count = sel_count + 1

# Normalize scores: scores /= sum(scores)
score_sum = ~0.0
i = 0
while i < TOP_K
  score_sum = score_sum + top_scores[i]
  i = i + 1
i = 0
while i < TOP_K
  top_scores[i] = top_scores[i] / score_sum
  i = i + 1

<< "Stage 3-4: top-8 indices = " + top_indices.to_s
<< "           top-8 scores  (sorted high→low) = " + top_scores.to_s

REF_INDS = [42, 118, 9, 123, 124, 94, 70, 39]
# Match against expected top-8 indices (any order — we sort high→low; MLX may
# present low→high). Just check set membership.
indices_match = true
i = 0
while i < TOP_K
  found = false
  j = 0
  while j < TOP_K
    if top_indices[i] == REF_INDS[j] then found = true
    j = j + 1
  if !found then indices_match = false
  i = i + 1
if indices_match then << "  Top-8 indices PASS (set match)" else << "  Top-8 indices FAIL"

# ---- Stage 5: 8 routed experts ----
# Per-expert: gate_proj (HIDDEN → EXPERT_FFN), up_proj (same), silu_mul,
# down_proj (EXPERT_FFN → HIDDEN), weighted_add into y_buf.

gw_d = st.tensor(prefix + "mlp.switch_mlp.gate_proj.weight")
gs_d = st.tensor(prefix + "mlp.switch_mlp.gate_proj.scales")
uw_d = st.tensor(prefix + "mlp.switch_mlp.up_proj.weight")
us_d = st.tensor(prefix + "mlp.switch_mlp.up_proj.scales")
dw_d = st.tensor(prefix + "mlp.switch_mlp.down_proj.weight")
ds_d = st.tensor(prefix + "mlp.switch_mlp.down_proj.scales")

# Down per-expert byte size differs: HIDDEN outputs × (EXPERT_FFN/8) u32 × 4 bytes
PER_EXPERT_DW_BYTES = HIDDEN * (EXPERT_FFN / 8) * 4    # 2048 × 64 × 4 = 524288
PER_EXPERT_DS_BYTES = HIDDEN * (EXPERT_FFN / 16)        # 2048 × 32     = 65536

gw_mmap = st.mmap_for(prefix + "mlp.switch_mlp.gate_proj.weight")
gs_mmap = st.mmap_for(prefix + "mlp.switch_mlp.gate_proj.scales")
uw_mmap = st.mmap_for(prefix + "mlp.switch_mlp.up_proj.weight")
us_mmap = st.mmap_for(prefix + "mlp.switch_mlp.up_proj.scales")
dw_mmap = st.mmap_for(prefix + "mlp.switch_mlp.down_proj.weight")
ds_mmap = st.mmap_for(prefix + "mlp.switch_mlp.down_proj.scales")

y_buf = metal_buffer(device, HIDDEN * 4)
i = 0
while i < HIDDEN
  metal_buffer_write_f32(y_buf, i, ~0.0)
  i = i + 1

gate_out_buf = metal_buffer(device, EXPERT_FFN * 4)
up_out_buf   = metal_buffer(device, EXPERT_FFN * 4)
hidden_buf   = metal_buffer(device, EXPERT_FFN * 4)
down_out_buf = metal_buffer(device, HIDDEN * 4)

ei = 0
while ei < TOP_K
  expert_id = top_indices[ei]
  expert_score = top_scores[ei]

  # Per-expert weight slices
  gw_slice = gw_mmap.view_at(gw_d[:byte_offset] + expert_id * PER_EXPERT_W_BYTES, :u8, PER_EXPERT_W_BYTES)
  gs_slice = gs_mmap.view_at(gs_d[:byte_offset] + expert_id * PER_EXPERT_S_BYTES, :u8, PER_EXPERT_S_BYTES)
  uw_slice = uw_mmap.view_at(uw_d[:byte_offset] + expert_id * PER_EXPERT_W_BYTES, :u8, PER_EXPERT_W_BYTES)
  us_slice = us_mmap.view_at(us_d[:byte_offset] + expert_id * PER_EXPERT_S_BYTES, :u8, PER_EXPERT_S_BYTES)
  dw_slice = dw_mmap.view_at(dw_d[:byte_offset] + expert_id * PER_EXPERT_DW_BYTES, :u8, PER_EXPERT_DW_BYTES)
  ds_slice = ds_mmap.view_at(ds_d[:byte_offset] + expert_id * PER_EXPERT_DS_BYTES, :u8, PER_EXPERT_DS_BYTES)

  metal_batch_begin(queue)
  metal_dispatch_groups(queue, nvfp4_mlx_pipe, [metal_buffer_for(device, gw_slice), metal_buffer_for(device, gs_slice), xn_buf, gate_out_buf, HIDDEN], EXPERT_FFN / 8, 64)
  metal_dispatch_groups(queue, nvfp4_mlx_pipe, [metal_buffer_for(device, uw_slice), metal_buffer_for(device, us_slice), xn_buf, up_out_buf,   HIDDEN], EXPERT_FFN / 8, 64)
  metal_dispatch_n(queue, silu_pipe, [gate_out_buf, up_out_buf, hidden_buf, EXPERT_FFN], EXPERT_FFN)
  metal_dispatch_groups(queue, nvfp4_mlx_pipe, [metal_buffer_for(device, dw_slice), metal_buffer_for(device, ds_slice), hidden_buf, down_out_buf, EXPERT_FFN], HIDDEN / 8, 64)
  metal_dispatch_n(queue, wadd_pipe, [y_buf, down_out_buf, expert_score, HIDDEN], HIDDEN)
  metal_batch_commit(queue)
  ei = ei + 1

<< "Stage 5: 8 routed experts dispatched"

# ---- Stage 6: shared expert + shared_gate ----
# shared_expert_gate: int8_affine, [1 × HIDDEN] → scalar
sgw_d = st.tensor(prefix + "mlp.shared_expert_gate.weight")
sgs_d = st.tensor(prefix + "mlp.shared_expert_gate.scales")
sgb_d = st.tensor(prefix + "mlp.shared_expert_gate.biases")
sgw_v = st.mmap_for(prefix + "mlp.shared_expert_gate.weight").view_at(sgw_d[:byte_offset], :u8, sgw_d[:byte_length])
sgs_v = st.mmap_for(prefix + "mlp.shared_expert_gate.scales").view_at(sgs_d[:byte_offset], :u8, sgs_d[:byte_length])
sgb_v = st.mmap_for(prefix + "mlp.shared_expert_gate.biases").view_at(sgb_d[:byte_offset], :u8, sgb_d[:byte_length])

sg_logit_buf = metal_buffer(device, 4)
metal_batch_begin(queue)
metal_dispatch_groups(queue, int8aff_pipe, [metal_buffer_for(device, sgw_v), metal_buffer_for(device, sgs_v), metal_buffer_for(device, sgb_v), xn_buf, sg_logit_buf, HIDDEN, 1], 1, 64)
metal_batch_commit(queue)

sg_logit = metal_buffer_read_f32(sg_logit_buf, 0)
sg = ~1.0 / (~1.0 + Math.exp(~0.0 - sg_logit))
<< "Stage 6 (shared_expert_gate): logit=" + sg_logit.to_s + ", sigmoid=" + sg.to_s + " (ref ~0.521953)"

# Shared expert MLP
sg_w_d = st.tensor(prefix + "mlp.shared_expert.gate_proj.weight")
sg_s_d = st.tensor(prefix + "mlp.shared_expert.gate_proj.scales")
su_w_d = st.tensor(prefix + "mlp.shared_expert.up_proj.weight")
su_s_d = st.tensor(prefix + "mlp.shared_expert.up_proj.scales")
sd_w_d = st.tensor(prefix + "mlp.shared_expert.down_proj.weight")
sd_s_d = st.tensor(prefix + "mlp.shared_expert.down_proj.scales")

shared_gate_buf = metal_buffer(device, SHARED_FFN * 4)
shared_up_buf   = metal_buffer(device, SHARED_FFN * 4)
shared_hid_buf  = metal_buffer(device, SHARED_FFN * 4)
shared_out_buf  = metal_buffer(device, HIDDEN * 4)

metal_batch_begin(queue)
metal_dispatch_groups(queue, nvfp4_mlx_pipe,
  [metal_buffer_for(device, st.mmap_for(prefix + "mlp.shared_expert.gate_proj.weight").view_at(sg_w_d[:byte_offset], :u8, sg_w_d[:byte_length])),
   metal_buffer_for(device, st.mmap_for(prefix + "mlp.shared_expert.gate_proj.scales").view_at(sg_s_d[:byte_offset], :u8, sg_s_d[:byte_length])),
   xn_buf, shared_gate_buf, HIDDEN], SHARED_FFN / 8, 64)
metal_dispatch_groups(queue, nvfp4_mlx_pipe,
  [metal_buffer_for(device, st.mmap_for(prefix + "mlp.shared_expert.up_proj.weight").view_at(su_w_d[:byte_offset], :u8, su_w_d[:byte_length])),
   metal_buffer_for(device, st.mmap_for(prefix + "mlp.shared_expert.up_proj.scales").view_at(su_s_d[:byte_offset], :u8, su_s_d[:byte_length])),
   xn_buf, shared_up_buf, HIDDEN], SHARED_FFN / 8, 64)
metal_dispatch_n(queue, silu_pipe, [shared_gate_buf, shared_up_buf, shared_hid_buf, SHARED_FFN], SHARED_FFN)
metal_dispatch_groups(queue, nvfp4_mlx_pipe,
  [metal_buffer_for(device, st.mmap_for(prefix + "mlp.shared_expert.down_proj.weight").view_at(sd_w_d[:byte_offset], :u8, sd_w_d[:byte_length])),
   metal_buffer_for(device, st.mmap_for(prefix + "mlp.shared_expert.down_proj.scales").view_at(sd_s_d[:byte_offset], :u8, sd_s_d[:byte_length])),
   shared_hid_buf, shared_out_buf, SHARED_FFN], HIDDEN / 8, 64)
metal_dispatch_n(queue, wadd_pipe, [y_buf, shared_out_buf, sg, HIDDEN], HIDDEN)
metal_batch_commit(queue)

# ---- Verify final mlp_out ----
REF_MLP = [~0.040335, ~0.007051, ~0.008194, ~0.005456, ~0.017765, ~-0.016682, ~0.012655, ~0.001758]
<< ""
<< "MoE final output (kernel vs MLX):"
max_d_final = ~0.0
i = 0
while i < 8
  got = metal_buffer_read_f32(y_buf, i)
  d = got - REF_MLP[i]
  if d < ~0.0 then d = ~0.0 - d
  if d > max_d_final then max_d_final = d
  << "  mlp_out[" + i.to_s + "]: kernel=" + got.to_s + "  ref=" + REF_MLP[i].to_s + "  diff=" + (got - REF_MLP[i]).to_s
  i = i + 1
<< "  max diff: " + max_d_final.to_s
if max_d_final < ~0.001 then << "  MoE PASS" else << "  MoE FAIL"

st.close
