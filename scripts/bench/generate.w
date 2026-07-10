# Greedy generation demo. Loads qwen3:30b-a3b-q8_0, tokenizes a prompt,
# prefills the KV cache, then samples N_GENERATE tokens by argmax of
# the lm_head logits. Same forward kernels as verify_paris but with a
# generation loop instead of a single-token verification check.
#
# Memory: 48 transformer blocks × ~660 MB = ~31.7 GB of Metal buffers
# plus ~660 MB of top-level weights. Comfortable on a 64+ GB unified-
# memory M3.

use core/metal
use tungsten-llama/gguf
use tungsten-llama/tensor
use tungsten-llama/tokenizer
use tungsten-llama/sampler
use tungsten-llama/model_gate

MODEL_ID = QWEN3_30B_A3B_Q8_0
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
MAX_POS = 64
N_GENERATE = 50
PREFILL_LEN = 5
BENCH_WARMUP_RUNS = 1
BENCH_RUNS = 5
PROMPT = "The capital of France is"
TEMPERATURE = ~0.0    # 0.0 = greedy argmax. Try 0.7–1.0 for sampled output.
TOP_K_SAMPLE = 40     # 0 = full vocab, K > 0 restricts to the K highest
                      # logits before softmax (avoids repetition loops).

device = metal_device()
queue = metal_queue(device)
KERNEL_DIR = "bits/tungsten-llama/lib/kernels/shared/"

<< "loading " + MODEL_ID + " GGUF + tokenizer..."
g = GGUF.new(GGUF_PATH)
require_qwen3_30b_a3b_q8_0(g)
tok = Tokenizer.new(g)

rms_pipe       = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "rms_norm.metal")), "rms_norm")
phn_pipe       = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "per_head_norm.metal")), "per_head_norm")
rope_pipe      = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "rope.metal")), "rope_neox")
kv_pipe        = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "kv_write.metal")), "kv_write")
scores_pipe    = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "attn_scores.metal")), "attn_scores")
softmax_pipe   = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "attn_softmax.metal")), "attn_softmax")
weighted_pipe  = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "attn_weighted_sum.metal")), "attn_weighted_sum")
flash_pipe     = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "flash_attn.metal")), "flash_attn")
q8_pipe        = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "q8_matvec_coop_v2.metal")), "q8_matvec_coop_v2")
q8_v4_pipe     = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "q8_matvec_coop_v4.metal")), "q8_matvec_coop_v4")
q8_v4_lib_fc   = metal_compile_source(device, read_file(KERNEL_DIR + "q8_matvec_coop_v4_fc.metal"))
q8_v4_lm_pipe  = metal_pipeline_with_int_constants(q8_v4_lib_fc, "q8_matvec_coop_v4_fc", [HIDDEN, N_VOCAB])
q8r_pipe       = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "q8_matvec_coop_residual.metal")), "q8_matvec_coop_residual")
q8r_v4_pipe    = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "q8_matvec_coop_residual_v4.metal")), "q8_matvec_coop_residual_v4")
f16_pipe       = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "f16_matvec.metal")), "f16_matvec")
f32_pipe       = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "f32_matvec.metal")), "f32_matvec")
expert_pipe    = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "q8_matvec_expert_v3.metal")), "q8_matvec_expert_v3")
silu_down_pipe = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "q8_matvec_silu_down_expert.metal")), "q8_matvec_silu_down_expert")
silu_pipe      = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "silu_mul.metal")), "silu_mul")
silu8_pipe     = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "silu_mul_8.metal")), "silu_mul_8")
add_pipe       = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "residual_add.metal")), "residual_add")
wadd_pipe      = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "weighted_add.metal")), "weighted_add")
argmax_pipe    = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "argmax.metal")), "argmax")
gate_up_pipe   = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "q8_matvec_gate_up_expert_v3.metal")), "q8_matvec_gate_up_expert_v3")
combine8_pipe  = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "moe_combine_8.metal")), "moe_combine_8")
combine8r_pipe = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "moe_combine_8_residual.metal")), "moe_combine_8_residual")
phnr_pipe      = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "per_head_norm_rope.metal")), "per_head_norm_rope")
phnrc_pipe     = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "per_head_norm_rope_to_cache.metal")), "per_head_norm_rope_to_cache")
f16c_pipe      = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "f16_matvec_to_cache.metal")), "f16_matvec_to_cache")
topk_pipe      = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "router_topk_8.metal")), "router_topk_8")
router_topk_pipe = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "router_matvec_topk_8.metal")), "router_matvec_topk_8")
topk_packed_lib_fc = metal_compile_source(device, read_file(KERNEL_DIR + "router_topk_8_packed_fc.metal"))
topk_packed_pipe = metal_pipeline_with_int_constants(topk_packed_lib_fc, "router_topk_8_packed_fc", [N_EXPERTS])
moe_gate_up_8_lib_fc = metal_compile_source(device, read_file(KERNEL_DIR + "q8_moe_gate_up_8_1d_fc.metal"))
moe_gate_up_8_pipe = metal_pipeline_with_int_constants(moe_gate_up_8_lib_fc, "q8_moe_gate_up_8_1d_fc", [HIDDEN, EXPERT_FFN])
moe_silu_down_8_lib_fc = metal_compile_source(device, read_file(KERNEL_DIR + "q8_moe_silu_down_8_1d_fc.metal"))
moe_silu_down_8_pipe = metal_pipeline_with_int_constants(moe_silu_down_8_lib_fc, "q8_moe_silu_down_8_1d_fc", [EXPERT_FFN, HIDDEN])
moe_silu_packed_lib_fc = metal_compile_source(device, read_file(KERNEL_DIR + "silu_mul_packed_inplace_fc.metal"))
moe_silu_packed_pipe = metal_pipeline_with_int_constants(moe_silu_packed_lib_fc, "silu_mul_packed_inplace_fc", [EXPERT_FFN])
moe_down_8_lib_fc = metal_compile_source(device, read_file(KERNEL_DIR + "q8_moe_down_8_1d_fc.metal"))
moe_down_8_pipe = metal_pipeline_with_int_constants(moe_down_8_lib_fc, "q8_moe_down_8_1d_fc", [EXPERT_FFN, HIDDEN])
combine8pr_lib_fc = metal_compile_source(device, read_file(KERNEL_DIR + "moe_combine_8_packed_residual_fc.metal"))
combine8pr_pipe = metal_pipeline_with_int_constants(combine8pr_lib_fc, "moe_combine_8_packed_residual_fc", [HIDDEN])
copy_slice_pipe = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "copy_f32_slice.metal")), "copy_f32_slice")

rms_batch_lib_fc = metal_compile_source(device, read_file(KERNEL_DIR + "rms_norm_batch_fc.metal"))
rms_batch_pipe = metal_pipeline_with_int_constants(rms_batch_lib_fc, "rms_norm_batch_fc", [HIDDEN, PREFILL_LEN])
q8_batch_lib_fc = metal_compile_source(device, read_file(KERNEL_DIR + "q8_matvec_batch_v4_fc.metal"))
q8_batch_q_pipe = metal_pipeline_with_int_constants(q8_batch_lib_fc, "q8_matvec_batch_v4_fc", [HIDDEN, 4096, PREFILL_LEN])
q8_batch_k_pipe = metal_pipeline_with_int_constants(q8_batch_lib_fc, "q8_matvec_batch_v4_fc", [HIDDEN, KV_ROW, PREFILL_LEN])
f16c_batch_lib_fc = metal_compile_source(device, read_file(KERNEL_DIR + "f16_matvec_to_cache_batch_fc.metal"))
f16c_batch_pipe = metal_pipeline_with_int_constants(f16c_batch_lib_fc, "f16_matvec_to_cache_batch_fc", [HIDDEN, KV_ROW, PREFILL_LEN])
phnr_batch_lib_fc = metal_compile_source(device, read_file(KERNEL_DIR + "per_head_norm_rope_batch_fc.metal"))
phnr_batch_pipe = metal_pipeline_with_int_constants(phnr_batch_lib_fc, "per_head_norm_rope_batch_fc", [HEAD_DIM, HEAD_DIM_HALF, N_Q_HEADS, PREFILL_LEN])
phnrc_batch_lib_fc = metal_compile_source(device, read_file(KERNEL_DIR + "per_head_norm_rope_to_cache_batch_fc.metal"))
phnrc_batch_pipe = metal_pipeline_with_int_constants(phnrc_batch_lib_fc, "per_head_norm_rope_to_cache_batch_fc", [HEAD_DIM, HEAD_DIM_HALF, N_KV_HEADS, PREFILL_LEN])
attn_scores_prefill_lib_fc = metal_compile_source(device, read_file(KERNEL_DIR + "attn_scores_prefill_batch_fc.metal"))
attn_scores_prefill_pipe = metal_pipeline_with_int_constants(attn_scores_prefill_lib_fc, "attn_scores_prefill_batch_fc", [HEAD_DIM, N_Q_HEADS, N_KV_HEADS, GROUP_SIZE, PREFILL_LEN])
attn_softmax_prefill_lib_fc = metal_compile_source(device, read_file(KERNEL_DIR + "attn_softmax_prefill_batch_fc.metal"))
attn_softmax_prefill_pipe = metal_pipeline_with_int_constants(attn_softmax_prefill_lib_fc, "attn_softmax_prefill_batch_fc", [N_Q_HEADS, PREFILL_LEN])
attn_weighted_prefill_lib_fc = metal_compile_source(device, read_file(KERNEL_DIR + "attn_weighted_sum_prefill_batch_fc.metal"))
attn_weighted_prefill_pipe = metal_pipeline_with_int_constants(attn_weighted_prefill_lib_fc, "attn_weighted_sum_prefill_batch_fc", [HEAD_DIM, N_Q_HEADS, N_KV_HEADS, GROUP_SIZE, PREFILL_LEN])
q8_batch_residual_lib_fc = metal_compile_source(device, read_file(KERNEL_DIR + "q8_matvec_batch_residual_fc.metal"))
q8_batch_o_pipe = metal_pipeline_with_int_constants(q8_batch_residual_lib_fc, "q8_matvec_batch_residual_fc", [4096, HIDDEN, PREFILL_LEN])
f32_batch_lib_fc = metal_compile_source(device, read_file(KERNEL_DIR + "f32_matvec_batch_fc.metal"))
f32_batch_router_pipe = metal_pipeline_with_int_constants(f32_batch_lib_fc, "f32_matvec_batch_fc", [HIDDEN, N_EXPERTS, PREFILL_LEN])
topk_batch_lib_fc = metal_compile_source(device, read_file(KERNEL_DIR + "router_topk_8_packed_batch_fc.metal"))
topk_batch_pipe = metal_pipeline_with_int_constants(topk_batch_lib_fc, "router_topk_8_packed_batch_fc", [N_EXPERTS, PREFILL_LEN])
moe_gate_up_batch_lib_fc = metal_compile_source(device, read_file(KERNEL_DIR + "q8_moe_gate_up_8_1d_batch_fc.metal"))
moe_gate_up_batch_pipe = metal_pipeline_with_int_constants(moe_gate_up_batch_lib_fc, "q8_moe_gate_up_8_1d_batch_fc", [HIDDEN, EXPERT_FFN, PREFILL_LEN])
moe_silu_batch_lib_fc = metal_compile_source(device, read_file(KERNEL_DIR + "silu_mul_packed_inplace_batch_fc.metal"))
moe_silu_batch_pipe = metal_pipeline_with_int_constants(moe_silu_batch_lib_fc, "silu_mul_packed_inplace_batch_fc", [EXPERT_FFN, PREFILL_LEN])
moe_down_batch_lib_fc = metal_compile_source(device, read_file(KERNEL_DIR + "q8_moe_down_8_1d_batch_fc.metal"))
moe_down_batch_pipe = metal_pipeline_with_int_constants(moe_down_batch_lib_fc, "q8_moe_down_8_1d_batch_fc", [EXPERT_FFN, HIDDEN, PREFILL_LEN])
combine8pr_batch_lib_fc = metal_compile_source(device, read_file(KERNEL_DIR + "moe_combine_8_packed_residual_batch_fc.metal"))
combine8pr_batch_pipe = metal_pipeline_with_int_constants(combine8pr_batch_lib_fc, "moe_combine_8_packed_residual_batch_fc", [HIDDEN, PREFILL_LEN])

embd_t      = g.tensor("token_embd.weight")
embd_off    = g.tensor_file_offset(embd_t)
out_norm_buf = Tensor.new(g, g.tensor("output_norm.weight")).upload_f32(device)
lm_parts     = Tensor.new(g, g.tensor("output.weight")).upload_q8(device)

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
hg_packed   = metal_buffer(device, TOP_K * EXPERT_FFN * 4)
hu_packed   = metal_buffer(device, TOP_K * EXPERT_FFN * 4)
eo_packed   = metal_buffer(device, TOP_K * HIDDEN * 4)
exp_ids_packed = metal_buffer(device, TOP_K * 4)

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

exp_idx_bufs = []
w_scalar_bufs = []
i = 0
while i < TOP_K
  exp_idx_bufs.push(metal_buffer(device, 4))
  w_scalar_bufs.push(metal_buffer(device, 4))
  i = i + 1
weights_packed = metal_buffer(device, TOP_K * 4)
last_hidden_src_off_buf = metal_buffer(device, 4) ; metal_buffer_write_i32(last_hidden_src_off_buf, 0, (PREFILL_LEN - 1) * HIDDEN)

x_prefill       = metal_buffer(device, PREFILL_LEN * HIDDEN * 4)
xn_prefill      = metal_buffer(device, PREFILL_LEN * HIDDEN * 4)
q_prefill       = metal_buffer(device, PREFILL_LEN * N_Q_HEADS * HEAD_DIM * 4)
k_prefill       = metal_buffer(device, PREFILL_LEN * KV_ROW * 4)
scores_prefill  = metal_buffer(device, PREFILL_LEN * N_Q_HEADS * PREFILL_LEN * 4)
attn_out_prefill = metal_buffer(device, PREFILL_LEN * N_Q_HEADS * HEAD_DIM * 4)
router_scores_prefill = metal_buffer(device, PREFILL_LEN * N_EXPERTS * 4)
hg_prefill      = metal_buffer(device, PREFILL_LEN * TOP_K * EXPERT_FFN * 4)
hu_prefill      = metal_buffer(device, PREFILL_LEN * TOP_K * EXPERT_FFN * 4)
eo_prefill      = metal_buffer(device, PREFILL_LEN * TOP_K * HIDDEN * 4)
exp_ids_prefill = metal_buffer(device, PREFILL_LEN * TOP_K * 4)
weights_prefill = metal_buffer(device, PREFILL_LEN * TOP_K * 4)
cos_prefill     = metal_buffer(device, PREFILL_LEN * HEAD_DIM_HALF * 4)
sin_prefill     = metal_buffer(device, PREFILL_LEN * HEAD_DIM_HALF * 4)

log_base = Math.log(BASE)
inv_hd = ~2.0 / HEAD_DIM
nb_h = HIDDEN / 32

sampler = Sampler.new(TEMPERATURE, TOP_K_SAMPLE, ccall("__w_clock_ms"))

-> build_rope_tables(pos)
  i = 0
  while i < HEAD_DIM_HALF
    theta = Math.exp(log_base * (~0.0 - i * inv_hd))
    angle = pos * theta
    metal_buffer_write_f32(cos_buf, i, Math.cos(angle))
    metal_buffer_write_f32(sin_buf, i, Math.sin(angle))
    i = i + 1

-> build_prefill_rope_tables(n)
  p = 0
  while p < n
    i = 0
    while i < HEAD_DIM_HALF
      theta = Math.exp(log_base * (~0.0 - i * inv_hd))
      angle = p * theta
      off = p * HEAD_DIM_HALF + i
      metal_buffer_write_f32(cos_prefill, off, Math.cos(angle))
      metal_buffer_write_f32(sin_prefill, off, Math.sin(angle))
      i = i + 1
    p = p + 1

-> run_block(lyr, n_pos_active)
  metal_dispatch_groups(queue, rms_pipe, [x_buf, lyr[:attn_norm], xn_buf, hidden_buf, inv_h_buf, eps_buf], 1, 512)
  metal_batch_barrier_resources(queue, [xn_buf])
  metal_set_threadgroup_memory(queue, HIDDEN * 4, 0)
  metal_dispatch_groups(queue, q8_v4_pipe, [lyr[:q_proj][:quants], lyr[:q_proj][:scales], xn_buf, q_buf, kdim_q_buf], 4096 / 32, 1024)
  metal_set_threadgroup_memory(queue, HIDDEN * 4, 0)
  metal_dispatch_groups(queue, q8_v4_pipe, [lyr[:k_proj][:quants], lyr[:k_proj][:scales], xn_buf, k_buf, kdim_kv_buf], KV_ROW / 32, 1024)
  metal_dispatch_groups(queue, f16c_pipe, [lyr[:v_proj], xn_buf, lyr[:v_cache], kdim_kv_buf, pos_buf, kv_row_buf], KV_ROW, 32)
  metal_batch_barrier_resources(queue, [q_buf, k_buf, lyr[:v_cache]])
  metal_dispatch_groups(queue, phnr_pipe, [q_buf, lyr[:q_norm], cos_buf, sin_buf, hd_buf, hdh_buf, inv_d_buf, eps_buf], N_Q_HEADS, 32)
  metal_dispatch_groups(queue, phnrc_pipe, [k_buf, lyr[:k_norm], cos_buf, sin_buf, lyr[:k_cache], hd_buf, hdh_buf, pos_buf, kv_row_buf, inv_d_buf, eps_buf], N_KV_HEADS, 32)
  metal_batch_barrier_resources(queue, [q_buf, lyr[:k_cache]])
  # Cooperative attn kernels (post-@gpu-language-extension): 1 TG per
  # output cell, TG_SIZE threads cooperate via tg_sum on the inner reduce.
  # TG=32 keeps single-simdgroup behavior for head_dim=128 / short n_pos.
  metal_dispatch_groups(queue, scores_pipe, [q_buf, lyr[:k_cache], scores_buf, hd_buf, n_kv_buf, gs_buf, n_pos_buf, scale_buf], N_Q_HEADS * n_pos_active, 32)
  metal_batch_barrier_resources(queue, [scores_buf])
  metal_dispatch_groups(queue, softmax_pipe, [scores_buf, n_pos_buf], N_Q_HEADS, 32)
  metal_batch_barrier_resources(queue, [scores_buf])
  metal_dispatch_groups(queue, weighted_pipe, [scores_buf, lyr[:v_cache], attn_out, hd_buf, n_kv_buf, gs_buf, n_pos_buf], N_Q_HEADS * HEAD_DIM, 32)
  metal_batch_barrier_resources(queue, [attn_out])
  metal_set_threadgroup_memory(queue, 4096 * 4, 0)
  metal_dispatch_groups(queue, q8r_v4_pipe, [lyr[:o_proj][:quants], lyr[:o_proj][:scales], attn_out, x_buf, kdim_o_buf], HIDDEN / 32, 1024)
  metal_batch_barrier_resources(queue, [x_buf])
  metal_dispatch_groups(queue, rms_pipe, [x_buf, lyr[:ffn_norm], xn_buf, hidden_buf, inv_h_buf, eps_buf], 1, 512)
  metal_batch_barrier_resources(queue, [xn_buf])
  metal_dispatch_groups(queue, f32_pipe, [lyr[:router], xn_buf, router_scores, hidden_buf], N_EXPERTS, 32)
  metal_batch_barrier_resources(queue, [router_scores])
  metal_dispatch_groups(queue, topk_packed_pipe, [router_scores, exp_ids_packed, weights_packed], 1, 32)
  metal_batch_barrier_resources(queue, [exp_ids_packed, weights_packed])

  metal_dispatch_groups(queue, moe_gate_up_8_pipe, [lyr[:gate][:quants], lyr[:gate][:scales], lyr[:up][:quants], lyr[:up][:scales], xn_buf, hg_packed, hu_packed, exp_ids_packed], TOP_K * (EXPERT_FFN / 4), 128)
  metal_batch_barrier_resources(queue, [hg_packed, hu_packed])
  metal_dispatch_n(queue, moe_silu_packed_pipe, [hg_packed, hu_packed], TOP_K * EXPERT_FFN)
  metal_batch_barrier_resources(queue, [hg_packed])
  metal_dispatch_groups(queue, moe_down_8_pipe, [lyr[:down][:quants], lyr[:down][:scales], hg_packed, eo_packed, exp_ids_packed], TOP_K * (HIDDEN / 32), 1024)
  metal_batch_barrier_resources(queue, [eo_packed])
  metal_dispatch_n(queue, combine8pr_pipe, [x_buf, eo_packed, weights_packed], HIDDEN)
  metal_batch_barrier_resources(queue, [x_buf])

-> run_block_prefill(lyr)
  metal_dispatch_groups(queue, rms_batch_pipe, [x_prefill, lyr[:attn_norm], xn_prefill, inv_h_buf, eps_buf], PREFILL_LEN, 32)
  metal_batch_barrier_resources(queue, [xn_prefill])
  metal_set_threadgroup_memory(queue, HIDDEN * 4, 0)
  metal_dispatch_groups(queue, q8_batch_q_pipe, [lyr[:q_proj][:quants], lyr[:q_proj][:scales], xn_prefill, q_prefill], PREFILL_LEN * (4096 / 32), 1024)
  metal_set_threadgroup_memory(queue, HIDDEN * 4, 0)
  metal_dispatch_groups(queue, q8_batch_k_pipe, [lyr[:k_proj][:quants], lyr[:k_proj][:scales], xn_prefill, k_prefill], PREFILL_LEN * (KV_ROW / 32), 1024)
  metal_dispatch_groups(queue, f16c_batch_pipe, [lyr[:v_proj], xn_prefill, lyr[:v_cache], kv_row_buf], PREFILL_LEN * KV_ROW, 32)
  metal_batch_barrier_resources(queue, [q_prefill, k_prefill, lyr[:v_cache]])
  metal_dispatch_groups(queue, phnr_batch_pipe, [q_prefill, lyr[:q_norm], cos_prefill, sin_prefill, inv_d_buf, eps_buf], PREFILL_LEN * N_Q_HEADS, 32)
  metal_dispatch_groups(queue, phnrc_batch_pipe, [k_prefill, lyr[:k_norm], cos_prefill, sin_prefill, lyr[:k_cache], kv_row_buf, inv_d_buf, eps_buf], PREFILL_LEN * N_KV_HEADS, 32)
  metal_batch_barrier_resources(queue, [q_prefill, lyr[:k_cache]])
  metal_dispatch_n(queue, attn_scores_prefill_pipe, [q_prefill, lyr[:k_cache], scores_prefill, scale_buf], PREFILL_LEN * N_Q_HEADS * PREFILL_LEN)
  metal_batch_barrier_resources(queue, [scores_prefill])
  metal_dispatch_groups(queue, attn_softmax_prefill_pipe, [scores_prefill], PREFILL_LEN * N_Q_HEADS, 32)
  metal_batch_barrier_resources(queue, [scores_prefill])
  metal_dispatch_n(queue, attn_weighted_prefill_pipe, [scores_prefill, lyr[:v_cache], attn_out_prefill], PREFILL_LEN * N_Q_HEADS * HEAD_DIM)
  metal_batch_barrier_resources(queue, [attn_out_prefill])
  metal_dispatch_groups(queue, q8_batch_o_pipe, [lyr[:o_proj][:quants], lyr[:o_proj][:scales], attn_out_prefill, x_prefill], PREFILL_LEN * HIDDEN, 32)
  metal_batch_barrier_resources(queue, [x_prefill])
  metal_dispatch_groups(queue, rms_batch_pipe, [x_prefill, lyr[:ffn_norm], xn_prefill, inv_h_buf, eps_buf], PREFILL_LEN, 32)
  metal_batch_barrier_resources(queue, [xn_prefill])
  metal_dispatch_groups(queue, f32_batch_router_pipe, [lyr[:router], xn_prefill, router_scores_prefill], PREFILL_LEN * N_EXPERTS, 32)
  metal_batch_barrier_resources(queue, [router_scores_prefill])
  metal_dispatch_groups(queue, topk_batch_pipe, [router_scores_prefill, exp_ids_prefill, weights_prefill], PREFILL_LEN, 32)
  metal_batch_barrier_resources(queue, [exp_ids_prefill, weights_prefill])
  metal_dispatch_groups(queue, moe_gate_up_batch_pipe, [lyr[:gate][:quants], lyr[:gate][:scales], lyr[:up][:quants], lyr[:up][:scales], xn_prefill, hg_prefill, hu_prefill, exp_ids_prefill], PREFILL_LEN * TOP_K * (EXPERT_FFN / 4), 128)
  metal_batch_barrier_resources(queue, [hg_prefill, hu_prefill])
  metal_dispatch_n(queue, moe_silu_batch_pipe, [hg_prefill, hu_prefill], PREFILL_LEN * TOP_K * EXPERT_FFN)
  metal_batch_barrier_resources(queue, [hg_prefill])
  metal_dispatch_groups(queue, moe_down_batch_pipe, [lyr[:down][:quants], lyr[:down][:scales], hg_prefill, eo_prefill, exp_ids_prefill], PREFILL_LEN * TOP_K * (HIDDEN / 32), 1024)
  metal_batch_barrier_resources(queue, [eo_prefill])
  metal_dispatch_n(queue, combine8pr_batch_pipe, [x_prefill, eo_prefill, weights_prefill], PREFILL_LEN * HIDDEN)
  metal_batch_barrier_resources(queue, [x_prefill])

-> forward_step(token_id, pos, need_logits)
  src_off = embd_off + token_id * nb_h * 34
  metal_q8_dequant_row(x_buf, 0, g.mmap, src_off, nb_h)
  build_rope_tables(pos)
  metal_buffer_write_i32(pos_buf, 0, pos)
  n_pos_active = pos + 1
  metal_buffer_write_i32(n_pos_buf, 0, n_pos_active)
  # One concurrent batch for the entire token. Greedy: GPU argmax keeps
  # the readback to a single i32. Sampled: CPU sampler reads N_VOCAB
  # logits via metal_buffer_read_f32.
  metal_batch_begin_concurrent(queue)
  li = 0
  while li < N_LAYERS
    run_block(layers[li], n_pos_active)
    li = li + 1
  if !need_logits
    metal_batch_commit(queue)
    return -1
  metal_dispatch_groups(queue, rms_pipe, [x_buf, out_norm_buf, xn_buf, hidden_buf, inv_h_buf, eps_buf], 1, 512)
  metal_batch_barrier(queue)
  metal_set_threadgroup_memory(queue, HIDDEN * 4, 0)
  metal_dispatch_groups(queue, q8_v4_lm_pipe, [lm_parts[:quants], lm_parts[:scales], xn_buf, logits_buf], N_VOCAB / 32, 1024)
  if TEMPERATURE == ~0.0
    metal_batch_barrier(queue)
    metal_dispatch_groups(queue, argmax_pipe, [logits_buf, argmax_buf, n_vocab_buf], 1, 1024)
    metal_batch_commit(queue)
    metal_buffer_read_i32(argmax_buf, 0)
  else
    metal_batch_commit(queue)
    sampler.sample(logits_buf, N_VOCAB)

-> prefill_batch_fixed(prompt_ids)
  i = 0
  while i < PREFILL_LEN
    src_off = embd_off + prompt_ids[i] * nb_h * 34
    metal_q8_dequant_row(x_prefill, i * HIDDEN, g.mmap, src_off, nb_h)
    i = i + 1
  build_prefill_rope_tables(PREFILL_LEN)
  metal_batch_begin_concurrent(queue)
  li = 0
  while li < N_LAYERS
    run_block_prefill(layers[li])
    li = li + 1
  metal_dispatch_n(queue, copy_slice_pipe, [x_prefill, x_buf, last_hidden_src_off_buf, hidden_buf], HIDDEN)
  metal_batch_barrier_resources(queue, [x_buf])
  metal_dispatch_groups(queue, rms_pipe, [x_buf, out_norm_buf, xn_buf, hidden_buf, inv_h_buf, eps_buf], 1, 512)
  metal_batch_barrier(queue)
  metal_set_threadgroup_memory(queue, HIDDEN * 4, 0)
  metal_dispatch_groups(queue, q8_v4_lm_pipe, [lm_parts[:quants], lm_parts[:scales], xn_buf, logits_buf], N_VOCAB / 32, 1024)
  metal_batch_barrier(queue)
  metal_dispatch_groups(queue, argmax_pipe, [logits_buf, argmax_buf, n_vocab_buf], 1, 1024)
  metal_batch_commit(queue)
  metal_buffer_read_i32(argmax_buf, 0)

-> stat_min(values)
  m = values[0]
  i = 1
  while i < values.size()
    if values[i] < m
      m = values[i]
    i = i + 1
  m

-> stat_mean(values)
  sum = 0
  i = 0
  while i < values.size()
    sum = sum + values[i]
    i = i + 1
  sum / values.size()

-> stat_median(values)
  sorted = values.sort
  sorted[sorted.size() / 2]

-> run_trial(prompt_ids)
  all_ids = []
  pos = 0
  i = 0
  last_pred = -1
  t_prefill_start = ccall("__w_clock_ms")
  if prompt_ids.size() == PREFILL_LEN
    while i < prompt_ids.size()
      all_ids.push(prompt_ids[i])
      i = i + 1
    last_pred = prefill_batch_fixed(prompt_ids)
    pos = PREFILL_LEN
  else
    while i < prompt_ids.size()
      all_ids.push(prompt_ids[i])
      last_pred = forward_step(prompt_ids[i], pos, i == prompt_ids.size() - 1)
      pos = pos + 1
      i = i + 1
  t_prefill = ccall("__w_clock_ms") - t_prefill_start

  t_decode_start = ccall("__w_clock_ms")
  i = 0
  while i < N_GENERATE
    all_ids.push(last_pred)
    next_tok = forward_step(last_pred, pos, true)
    pos = pos + 1
    last_pred = next_tok
    i = i + 1
  t_decode = ccall("__w_clock_ms") - t_decode_start

  {prefill: t_prefill, decode: t_decode, output: tok.decode(all_ids)}

prompt_ids = tok.encode(PROMPT)
<< ""
<< "prompt: '" + PROMPT + "'"
<< "  ids: " + prompt_ids.to_s + " (" + prompt_ids.size().to_s + " tokens)"
<< "benchmark: " + BENCH_WARMUP_RUNS.to_s + " warmup, " + BENCH_RUNS.to_s + " measured runs"

i = 0
while i < BENCH_WARMUP_RUNS
  r = run_trial(prompt_ids)
  << "warmup " + (i + 1).to_s + "/" + BENCH_WARMUP_RUNS.to_s + ": prefill " + r[:prefill].to_s + " ms, decode " + r[:decode].to_s + " ms"
  i = i + 1

prefill_times = []
decode_times = []
output_text = ""
i = 0
while i < BENCH_RUNS
  r = run_trial(prompt_ids)
  prefill_times.push(r[:prefill])
  decode_times.push(r[:decode])
  output_text = r[:output]
  << "run " + (i + 1).to_s + "/" + BENCH_RUNS.to_s + ": prefill " + r[:prefill].to_s + " ms (" + (r[:prefill] / prompt_ids.size()).to_s + " ms/token), decode " + r[:decode].to_s + " ms (" + (r[:decode] / N_GENERATE).to_s + " ms/token)"
  i = i + 1

<< ""
<< "summary:"
<< "  prefill ms min/median/mean: " + stat_min(prefill_times).to_s + " / " + stat_median(prefill_times).to_s + " / " + stat_mean(prefill_times).to_s
<< "  decode  ms min/median/mean: " + stat_min(decode_times).to_s + " / " + stat_median(decode_times).to_s + " / " + stat_mean(decode_times).to_s
<< ""
<< "full output:"
<< "  '" + output_text + "'"

g.close
