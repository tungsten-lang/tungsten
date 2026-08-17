# Decode-only Qwen3.8 27B MLX/NVFP4 inference on Metal.
#
# Prepare the Ollama weights without copying them:
#   ruby scripts/bench/prepare_ollama_mlx.rb qwen3.8:27b-mlx
#
# Run modes:
#   bin/tungsten run scripts/bench/qwen38_mlx.w baseline 8
#   bin/tungsten run scripts/bench/qwen38_mlx.w optimized 8
#   bin/tungsten run scripts/bench/qwen38_mlx.w concurrent 8
#   bin/tungsten run scripts/bench/qwen38_mlx.w mtp 24
#   bin/tungsten run scripts/bench/qwen38_mlx.w mtp2 24
#   bin/tungsten run scripts/bench/qwen38_mlx.w mtp-auto 48
#   bin/tungsten run scripts/bench/qwen38_mlx.w concurrent 8 auto mmap
#
# All modes execute the same f32 compute graph. Optimized mode fuses dense
# gate/up and projection+residual operations and submits one command buffer
# per token; concurrent mode additionally overlaps independent projections.
# MTP mode uses the checkpoint's one-layer MTP head to draft one token and a
# two-token target pass that shares each packed weight load across both rows.
# MTP-auto probes the one- and two-draft arms on complete decode rounds and
# retains the one with the higher observed emitted-token rate.
# Draft selection projects only the common-token prefix plus Qwen control
# tokens; verification still scores the full vocabulary and remains exact.

use core/metal
use tungsten-llama/sharded_safetensors
use tungsten-llama/tokenizer

MODEL_INDEX = "/Users/erik/.cache/tungsten/qwen3.8-27b-mlx/model.safetensors.index.json"
TOKENIZER_BIN = "/Users/erik/.cache/tungsten/qwen3.8-27b-mlx/tokenizer.json.bin"
NVFP4_DIR = "bits/tungsten-llama/lib/kernels/nvfp4/"
SHARED_DIR = "bits/tungsten-llama/lib/kernels/shared/"
QWEN_DIR = "bits/tungsten-llama/lib/kernels/qwen3_6/"

HIDDEN = 5120
N_LAYERS = 64
N_VOCAB = 248320
FFN = 17408
EPS = ~0.000001

# Linear attention / GatedDeltaNet.
HK = 16
HV = 48
DK = 128
DV = 128
Q_DIM = HK * DK
K_DIM = HK * DK
V_DIM = HV * DV
QKV_DIM = Q_DIM + K_DIM + V_DIM

# Full attention.
N_HEADS = 24
N_KV_HEADS = 4
HEAD_DIM = 256
GQA = N_HEADS / N_KV_HEADS
KV_DIM = N_KV_HEADS * HEAD_DIM
ATTN_DIM = N_HEADS * HEAD_DIM
QFULL_DIM = ATTN_DIM * 2
ATTN_SCALE = ~1.0 / Math.sqrt(~0.0 + HEAD_DIM)
ROT_DIM = 64
ROT_HALF = ROT_DIM / 2
ROPE_BASE = ~10000000.0
MAX_POS = 128
MTP_DRAFT_PREFIX = 98304
MTP_DRAFT_CONTROL_START = 248044
MTP_DRAFT_CONTROL_COUNT = 26
MTP_DRAFT_CONTROL_ROWS = 32
ARGMAX_CHUNKS = (N_VOCAB + 1023) / 1024

mode = ARGV.size() > 0 ? ARGV[0] : "concurrent"
n_generate = ARGV.size() > 1 ? ARGV[1].to_i() : 8
row_schedule = ARGV.size() > 2 ? ARGV[2] : (mode == "concurrent" ? "16r" : "r2")
weight_binding = ARGV.size() > 3 ? ARGV[3] : "mmap"
force_reject = ARGV.size() > 4 && ARGV[4] == "force-reject"
legacy_mtp = ARGV.size() > 4 && ARGV[4] == "legacy-mtp"
full_history_mtp = ARGV.size() > 4 && ARGV[4] == "full-history"
full_draft_vocab = legacy_mtp || (ARGV.size() > 4 && ARGV[4] == "full-draft-vocab")
profile_components = ARGV.size() > 4 && ARGV[4] == "profile"
profile_prompt_tokens = ARGV.size() > 5 ? ARGV[5].to_i() : 5
legacy_reductions = ARGV.size() > 6 && ARGV[6] == "legacy-reductions"
if profile_prompt_tokens < 1 then raise "profile prompt length must be positive"
setup_t0 = ccall("__w_clock_ms")
# Mutable profiling state (closure-local assignment would shadow scalars):
# phase, decode target ms/count, prefill target ms/count, verify ms/count,
# draft ms/count, history ms/count, hidden-copy ms/count, rollback ms/count,
# first-prefill ms, remaining-prefill ms.
profile_stats = [0, ~0.0, 0, ~0.0, 0, ~0.0, 0, ~0.0, 0,
  ~0.0, 0, ~0.0, 0, ~0.0, 0, ~0.0, ~0.0]
optimized = mode == "optimized" || mode == "concurrent"
concurrent = mode == "concurrent"
mtp_enabled = mode == "mtp" || mode == "mtp2" || mode == "mtp-auto"
mtp_adaptive = mode == "mtp-auto"
mtp_depth2 = mode == "mtp2" || mtp_adaptive
if mtp_enabled
  optimized = true
  concurrent = true
if !optimized && mode != "baseline"
  raise "usage: qwen38_mlx.w [baseline|optimized|concurrent|mtp|mtp2|mtp-auto] [tokens] [4r|8r|16r|r2|auto] [mmap|copy]"
if row_schedule != "4r" && row_schedule != "8r" && row_schedule != "16r" && row_schedule != "r2" && row_schedule != "auto"
  raise "row schedule must be 4r, 8r, 16r, r2, or auto"
if weight_binding != "copy" && weight_binding != "mmap"
  raise "weight binding must be copy or mmap"

device = metal_device()
queue = metal_queue(device)
st = Tungsten:Llama:ShardedSafetensors.new(MODEL_INDEX)

<< "qwen3.8/27b-mlx: " + mode + ", " + row_schedule + ", " + weight_binding + ", " + st.count().to_s + " tensors"

# Compile reusable pipelines.
bf16_embed_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "bf16_embedding_lookup.metal")), "bf16_embedding_lookup")
bf16_matvec_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "bf16_matvec.metal")), "bf16_matvec")
rms_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "rms_norm.metal")), "rms_norm")
rms_batch_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "rms_norm_batch.metal")), "rms_norm_batch")
phn_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "per_head_norm.metal")), "per_head_norm")
copy_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "copy_f32_slice.metal")), "copy_f32_slice")
kv_write_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "kv_write.metal")), "kv_write")
add_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "residual_add.metal")), "residual_add")
silu_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "silu_mul.metal")), "silu_mul")
argmax_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "argmax.metal")), "argmax")
argmax_parallel_lib = metal_compile_source(device, read_file(SHARED_DIR + "argmax_two_stage.metal"))
argmax_stage1_pipe = metal_pipeline(argmax_parallel_lib, "argmax_stage1")
argmax_stage2_pipe = metal_pipeline(argmax_parallel_lib, "argmax_stage2")

scaled_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled.metal")), "nvfp4_matvec_mlx_scaled")
r2_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_r_2.metal")), "nvfp4_matvec_mlx_scaled_r_2")
scaled_rows_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_rows.metal"))
scaled_4_pipe = metal_pipeline(scaled_rows_lib, "nvfp4_matvec_mlx_scaled_4r")
scaled_16_pipe = metal_pipeline(scaled_rows_lib, "nvfp4_matvec_mlx_scaled_16r")
scaled_res_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_residual.metal")), "nvfp4_matvec_mlx_scaled_residual")
scaled_gu_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_gu.metal")), "nvfp4_matvec_mlx_scaled_gu")
scaled_pair_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_pair.metal"))
scaled_pair_pipe = metal_pipeline(scaled_pair_lib, "nvfp4_matvec_mlx_scaled_pair")
scaled_pair_res_pipe = metal_pipeline(scaled_pair_lib, "nvfp4_matvec_mlx_scaled_pair_residual")
scaled_triplet_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_triplet.metal"))
scaled_triplet_pipe = metal_pipeline(scaled_triplet_lib, "nvfp4_matvec_mlx_scaled_triplet")
scaled_triplet_res_pipe = metal_pipeline(scaled_triplet_lib, "nvfp4_matvec_mlx_scaled_triplet_residual")
scaled_triplet_r1_pipe = metal_pipeline(scaled_triplet_lib, "nvfp4_matvec_mlx_scaled_triplet_r1")
scaled_triplet_res_r1_pipe = metal_pipeline(scaled_triplet_lib, "nvfp4_matvec_mlx_scaled_triplet_residual_r1")

conv_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "conv1d_depthwise_step.metal")), "conv1d_depthwise_step")
g_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "compute_g.metal")), "compute_g")
delta_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "gated_delta_step.metal")), "gated_delta_step")
rng_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "rms_norm_gated.metal")), "rms_norm_gated")
sigmoid_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "sigmoid_inplace.metal")), "sigmoid_f32")
split_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "split_q_gate.metal")), "split_q_gate")
rope_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "partial_rope_neox.metal")), "partial_rope_neox")
sdpa_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "sdpa_decode_hd256.metal")), "sdpa_decode_hd256")
gate_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "attn_output_gate.metal")), "attn_output_gate")

pair_lib = metal_compile_source(device, read_file(QWEN_DIR + "decode_pair.metal"))
pair_embed_pipe = metal_pipeline(pair_lib, "bf16_embedding_lookup_pair")
pair_bf16_pipe = metal_pipeline(pair_lib, "bf16_matvec_pair")
concat_pipe = metal_pipeline(pair_lib, "concat_f32")
copy_pair_row_pipe = metal_pipeline(pair_lib, "copy_pair_row")
copy_pair_slice_pipe = metal_pipeline(pair_lib, "copy_f32_slice_pair")
split_pair_pipe = metal_pipeline(pair_lib, "split_q_gate_pair")
phn_rope_pair_pipe = metal_pipeline(pair_lib, "per_head_norm_partial_rope_pair")
kv_write_pair_pipe = metal_pipeline(pair_lib, "kv_write_pair")
sdpa_pair_pipe = metal_pipeline(pair_lib, "sdpa_decode_pair_hd256")
conv_pair_pipe = metal_pipeline(pair_lib, "conv1d_depthwise_pair")
delta_pair_pipe = metal_pipeline(pair_lib, "gated_delta_pair")

triplet_lib = metal_compile_source(device, read_file(QWEN_DIR + "decode_triplet.metal"))
triplet_embed_pipe = metal_pipeline(triplet_lib, "bf16_embedding_lookup_triplet")
triplet_bf16_pipe = metal_pipeline(triplet_lib, "bf16_matvec_triplet")
copy_triplet_slice_pipe = metal_pipeline(triplet_lib, "copy_f32_slice_triplet")
split_triplet_pipe = metal_pipeline(triplet_lib, "split_q_gate_triplet")
phn_rope_triplet_pipe = metal_pipeline(triplet_lib, "per_head_norm_partial_rope_triplet")
kv_write_triplet_pipe = metal_pipeline(triplet_lib, "kv_write_triplet")
sdpa_triplet_pipe = metal_pipeline(triplet_lib, "sdpa_decode_triplet_hd256")
conv_triplet_pipe = metal_pipeline(triplet_lib, "conv1d_depthwise_triplet")
delta_triplet_pipe = metal_pipeline(triplet_lib, "gated_delta_triplet")

mtp_select_lib = metal_compile_source(device, read_file(QWEN_DIR + "mtp_draft_select.metal"))
mtp_select_pipe = metal_pipeline(mtp_select_lib, "mtp_compact_draft_select")

rms_pair_lib = metal_compile_source(device, read_file(SHARED_DIR + "rms_norm_batch_fc.metal"))
rms_pair_pipe = metal_pipeline_with_int_constants(rms_pair_lib, "rms_norm_batch_fc", [HIDDEN, 2])
argmax_pair_lib = metal_compile_source(device, read_file(SHARED_DIR + "argmax_batch_fc.metal"))
argmax_pair_pipe = metal_pipeline_with_int_constants(argmax_pair_lib, "argmax_batch_fc", [N_VOCAB, 2])
rms_triplet_pipe = metal_pipeline_with_int_constants(rms_pair_lib, "rms_norm_batch_fc", [HIDDEN, 3])
argmax_triplet_pipe = metal_pipeline_with_int_constants(argmax_pair_lib, "argmax_batch_fc", [N_VOCAB, 3])

# Small weight-loading helpers. Quantized handles are [packed, group scale,
# global scale]. Each tensor binds a byte-offset view of its shard's mmap, so
# the GPU reads the file-backed pages directly without expanding or copying.
-> raw_tensor(name)
  d = st.tensor(name)
  if weight_binding == "mmap"
    metal_buffer_for_mmap(device, st.mmap_for(name), d[:byte_offset], d[:byte_length])
  else
    metal_buffer_for(device, st.mmap_for(name).view_at(d[:byte_offset], :u8, d[:byte_length]))

-> raw_tensor_rows(spec)
  name = spec[0]
  row_start = spec[1]
  row_count = spec[2]
  d = st.tensor(name)
  total_rows = d[:shape][0]
  row_bytes = d[:byte_length] / total_rows
  byte_offset = d[:byte_offset] + row_start * row_bytes
  byte_length = row_count * row_bytes
  if weight_binding == "mmap"
    metal_buffer_for_mmap(device, st.mmap_for(name), byte_offset, byte_length)
  else
    metal_buffer_for(device, st.mmap_for(name).view_at(byte_offset, :u8, byte_length))

-> quant_tensor(name)
  [raw_tensor(name), raw_tensor(name + ".scale"), raw_tensor(name + ".global_scale")]

-> quant_tensor_rows(spec)
  name = spec[0]
  row_start = spec[1]
  row_count = spec[2]
  [raw_tensor_rows([name, row_start, row_count]),
   raw_tensor_rows([name + ".scale", row_start, row_count]),
   raw_tensor(name + ".global_scale")]

-> load_bf16(spec)
  name = spec[0]
  n = spec[1]
  dst = spec[2]
  d = st.tensor(name)
  m = st.mmap_for(name)
  i = 0
  while i < n
    off = d[:byte_offset] + i * 2
    bits = m.byte_at(off) | (m.byte_at(off + 1) << 8)
    metal_buffer_write_i32(dst, i, bits << 16)
    i = i + 1

# Qwen3.5 checkpoints carrying MTP weights store the outer RMSNorm, q_norm,
# and k_norm parameters as deltas from one. This mirrors mlx-lm's sanitize().
-> load_shifted_norm(spec)
  name = spec[0]
  n = spec[1]
  dst = spec[2]
  d = st.tensor(name)
  m = st.mmap_for(name)
  i = 0
  while i < n
    off = d[:byte_offset] + i * 2
    bits = m.byte_at(off) | (m.byte_at(off + 1) << 8)
    value = ccall("w_float_from_u32_bits", bits << 16) + 1.0
    metal_buffer_write_i32(dst, i, ccall("w_float_to_u32_bits", value))
    i = i + 1

# Embedding and fixed final weights.
embed_w = raw_tensor("model.language_model.embed_tokens.weight")
final_norm = metal_buffer(device, HIDDEN * 4)
load_shifted_norm(["model.language_model.norm.weight", HIDDEN, final_norm])
lm_head = quant_tensor("lm_head.weight")
mtp_draft_prefix_head = quant_tensor_rows(
  ["lm_head.weight", 0, MTP_DRAFT_PREFIX])
mtp_draft_control_head = quant_tensor_rows(
  ["lm_head.weight", MTP_DRAFT_CONTROL_START, MTP_DRAFT_CONTROL_ROWS])

# Per-head constants used by GatedDeltaNet's q/k normalization.
q_norm_scale = metal_buffer(device, DK * 4)
k_norm_scale = metal_buffer(device, DK * 4)
inv_sqrt_dk = ~1.0 / Math.sqrt(~0.0 + DK)
i = 0
while i < DK
  metal_buffer_write_f32(q_norm_scale, i, inv_sqrt_dk * inv_sqrt_dk)
  metal_buffer_write_f32(k_norm_scale, i, inv_sqrt_dk)
  i = i + 1

# Preload all handles and persistent recurrent/cache state.
layers = []
li = 0
while li < N_LAYERS
  prefix = "model.language_model.layers." + li.to_s + "."
  if (li % 8) == 0 then << "  loading layer " + li.to_s
  in_norm = metal_buffer(device, HIDDEN * 4)
  post_norm = metal_buffer(device, HIDDEN * 4)
  load_shifted_norm([prefix + "input_layernorm.weight", HIDDEN, in_norm])
  load_shifted_norm([prefix + "post_attention_layernorm.weight", HIDDEN, post_norm])
  base = {
    in_norm: in_norm,
    post_norm: post_norm,
    gate: quant_tensor(prefix + "mlp.gate_proj.weight"),
    up: quant_tensor(prefix + "mlp.up_proj.weight"),
    down: quant_tensor(prefix + "mlp.down_proj.weight")
  }
  if st.has?(prefix + "linear_attn.A_log")
    conv_w = metal_buffer(device, QKV_DIM * 4 * 4)
    alog = metal_buffer(device, HV * 4)
    dtb = metal_buffer(device, HV * 4)
    ln_w = metal_buffer(device, DV * 4)
    load_bf16([prefix + "linear_attn.conv1d.weight", QKV_DIM * 4, conv_w])
    load_bf16([prefix + "linear_attn.A_log", HV, alog])
    load_bf16([prefix + "linear_attn.dt_bias", HV, dtb])
    load_bf16([prefix + "linear_attn.norm.weight", DV, ln_w])
    base[:kind] = "mamba"
    base[:qkv] = quant_tensor(prefix + "linear_attn.in_proj_qkv.weight")
    base[:z] = quant_tensor(prefix + "linear_attn.in_proj_z.weight")
    base[:a] = raw_tensor(prefix + "linear_attn.in_proj_a.weight")
    base[:b] = raw_tensor(prefix + "linear_attn.in_proj_b.weight")
    base[:conv] = conv_w
    base[:alog] = alog
    base[:dtb] = dtb
    base[:linear_norm] = ln_w
    base[:out] = quant_tensor(prefix + "linear_attn.out_proj.weight")
    base[:cs_a] = metal_buffer(device, 3 * QKV_DIM * 4)
    base[:cs_b] = metal_buffer(device, 3 * QKV_DIM * 4)
    base[:ss_a] = metal_buffer(device, HV * DV * DK * 4)
    base[:ss_b] = metal_buffer(device, HV * DV * DK * 4)
    if mtp_enabled
      base[:cs_mid] = metal_buffer(device, 3 * QKV_DIM * 4)
      base[:ss_mid] = metal_buffer(device, HV * DV * DK * 4)
      if mtp_depth2
        base[:cs_mid2] = metal_buffer(device, 3 * QKV_DIM * 4)
        base[:ss_mid2] = metal_buffer(device, HV * DV * DK * 4)
    base[:ping] = 0
  else
    qn = metal_buffer(device, HEAD_DIM * 4)
    kn = metal_buffer(device, HEAD_DIM * 4)
    load_shifted_norm([prefix + "self_attn.q_norm.weight", HEAD_DIM, qn])
    load_shifted_norm([prefix + "self_attn.k_norm.weight", HEAD_DIM, kn])
    base[:kind] = "full"
    base[:q] = quant_tensor(prefix + "self_attn.q_proj.weight")
    base[:k] = quant_tensor(prefix + "self_attn.k_proj.weight")
    base[:v] = quant_tensor(prefix + "self_attn.v_proj.weight")
    base[:out] = quant_tensor(prefix + "self_attn.o_proj.weight")
    base[:qn] = qn
    base[:kn] = kn
    base[:k_cache] = metal_buffer(device, MAX_POS * KV_DIM * 4)
    base[:v_cache] = metal_buffer(device, MAX_POS * KV_DIM * 4)
  layers.push(base)
  li = li + 1

# Inline MTP-1 head. Its decoder layer is full attention and shares the main
# embedding and LM head. The MTP KV cache advances on committed
# (look-ahead-token, target-hidden) pairs only, so a rejected target draft
# never needs to be removed from this cache.
mtp_layer = nil
mtp_enorm = nil
mtp_hnorm = nil
mtp_norm = nil
mtp_fc = nil
if mtp_enabled
  mtp_enorm = metal_buffer(device, HIDDEN * 4)
  mtp_hnorm = metal_buffer(device, HIDDEN * 4)
  mtp_norm = metal_buffer(device, HIDDEN * 4)
  mtp_in_norm = metal_buffer(device, HIDDEN * 4)
  mtp_post_norm = metal_buffer(device, HIDDEN * 4)
  mtp_qn = metal_buffer(device, HEAD_DIM * 4)
  mtp_kn = metal_buffer(device, HEAD_DIM * 4)
  load_shifted_norm(["mtp.pre_fc_norm_embedding.weight", HIDDEN, mtp_enorm])
  load_shifted_norm(["mtp.pre_fc_norm_hidden.weight", HIDDEN, mtp_hnorm])
  load_shifted_norm(["mtp.norm.weight", HIDDEN, mtp_norm])
  load_shifted_norm(["mtp.layers.0.input_layernorm.weight", HIDDEN, mtp_in_norm])
  load_shifted_norm(["mtp.layers.0.post_attention_layernorm.weight", HIDDEN, mtp_post_norm])
  load_shifted_norm(["mtp.layers.0.self_attn.q_norm.weight", HEAD_DIM, mtp_qn])
  load_shifted_norm(["mtp.layers.0.self_attn.k_norm.weight", HEAD_DIM, mtp_kn])
  mtp_fc = quant_tensor("mtp.fc.weight")
  mtp_layer = {
    kind: "full",
    in_norm: mtp_in_norm,
    post_norm: mtp_post_norm,
    q: quant_tensor("mtp.layers.0.self_attn.q_proj.weight"),
    k: quant_tensor("mtp.layers.0.self_attn.k_proj.weight"),
    v: quant_tensor("mtp.layers.0.self_attn.v_proj.weight"),
    out: quant_tensor("mtp.layers.0.self_attn.o_proj.weight"),
    qn: mtp_qn,
    kn: mtp_kn,
    gate: quant_tensor("mtp.layers.0.mlp.gate_proj.weight"),
    up: quant_tensor("mtp.layers.0.mlp.up_proj.weight"),
    down: quant_tensor("mtp.layers.0.mlp.down_proj.weight"),
    k_cache: metal_buffer(device, MAX_POS * KV_DIM * 4),
    v_cache: metal_buffer(device, MAX_POS * KV_DIM * 4)
  }

# Shared decode scratch.
x = metal_buffer(device, HIDDEN * 4)
xn = metal_buffer(device, HIDDEN * 4)
backbone_hidden = metal_buffer(device, HIDDEN * 4)
projection = metal_buffer(device, HIDDEN * 4)
ffn_out = metal_buffer(device, HIDDEN * 4)
gate_tmp = metal_buffer(device, FFN * 4)
up_tmp = metal_buffer(device, FFN * 4)
hidden_tmp = metal_buffer(device, FFN * 4)

qkv_tmp = metal_buffer(device, QKV_DIM * 4)
z_tmp = metal_buffer(device, V_DIM * 4)
a_tmp = metal_buffer(device, HV * 4)
b_tmp = metal_buffer(device, HV * 4)
conv_tmp = metal_buffer(device, QKV_DIM * 4)
mq_tmp = metal_buffer(device, Q_DIM * 4)
mk_tmp = metal_buffer(device, K_DIM * 4)
mv_tmp = metal_buffer(device, V_DIM * 4)
g_tmp = metal_buffer(device, HV * 4)
beta_tmp = metal_buffer(device, HV * 4)
delta_tmp = metal_buffer(device, V_DIM * 4)
mamba_norm_tmp = metal_buffer(device, V_DIM * 4)

qfull_tmp = metal_buffer(device, QFULL_DIM * 4)
queries_tmp = metal_buffer(device, ATTN_DIM * 4)
attn_gate_tmp = metal_buffer(device, ATTN_DIM * 4)
k_tmp = metal_buffer(device, KV_DIM * 4)
v_tmp = metal_buffer(device, KV_DIM * 4)
attn_tmp = metal_buffer(device, ATTN_DIM * 4)
cos_tmp = metal_buffer(device, ROT_HALF * 4)
sin_tmp = metal_buffer(device, ROT_HALF * 4)

# MTP fusion scratch.
mtp_embed_tmp = metal_buffer(device, HIDDEN * 4)
mtp_embed_norm_tmp = metal_buffer(device, HIDDEN * 4)
mtp_hidden_norm_tmp = metal_buffer(device, HIDDEN * 4)
mtp_fc_input_tmp = metal_buffer(device, HIDDEN * 2 * 4)
mtp_prefix_logits = metal_buffer(device, MTP_DRAFT_PREFIX * 4)
mtp_control_logits = metal_buffer(device, MTP_DRAFT_CONTROL_ROWS * 4)

# Two-token target-verification scratch. Pair projections use f32 throughout;
# packed weights remain mmap-backed and are decoded only in the pair qmv.
x_pair = metal_buffer(device, 2 * HIDDEN * 4)
xn_pair = metal_buffer(device, 2 * HIDDEN * 4)
gate_pair_tmp = metal_buffer(device, 2 * FFN * 4)
up_pair_tmp = metal_buffer(device, 2 * FFN * 4)
hidden_pair_tmp = metal_buffer(device, 2 * FFN * 4)

qkv_pair_tmp = metal_buffer(device, 2 * QKV_DIM * 4)
z_pair_tmp = metal_buffer(device, 2 * V_DIM * 4)
a_pair_tmp = metal_buffer(device, 2 * HV * 4)
b_pair_tmp = metal_buffer(device, 2 * HV * 4)
conv_pair_tmp = metal_buffer(device, 2 * QKV_DIM * 4)
mq_pair_tmp = metal_buffer(device, 2 * Q_DIM * 4)
mk_pair_tmp = metal_buffer(device, 2 * K_DIM * 4)
mv_pair_tmp = metal_buffer(device, 2 * V_DIM * 4)
g_pair_tmp = metal_buffer(device, 2 * HV * 4)
beta_pair_tmp = metal_buffer(device, 2 * HV * 4)
delta_pair_tmp = metal_buffer(device, 2 * V_DIM * 4)
mamba_norm_pair_tmp = metal_buffer(device, 2 * V_DIM * 4)

qfull_pair_tmp = metal_buffer(device, 2 * QFULL_DIM * 4)
queries_pair_tmp = metal_buffer(device, 2 * ATTN_DIM * 4)
attn_gate_pair_tmp = metal_buffer(device, 2 * ATTN_DIM * 4)
k_pair_tmp = metal_buffer(device, 2 * KV_DIM * 4)
v_pair_tmp = metal_buffer(device, 2 * KV_DIM * 4)
attn_pair_tmp = metal_buffer(device, 2 * ATTN_DIM * 4)
cos_pair_tmp = metal_buffer(device, 2 * ROT_HALF * 4)
sin_pair_tmp = metal_buffer(device, 2 * ROT_HALF * 4)

logits_pair = metal_buffer(device, 2 * N_VOCAB * 4)
argmax_pair_out = metal_buffer(device, 2 * 4)
token_pair_buf = metal_buffer(device, 2 * 4)

# Three-token target-verification scratch for the MTP-2 autotune arm.
x_triplet = metal_buffer(device, 3 * HIDDEN * 4)
xn_triplet = metal_buffer(device, 3 * HIDDEN * 4)
gate_triplet_tmp = metal_buffer(device, 3 * FFN * 4)
up_triplet_tmp = metal_buffer(device, 3 * FFN * 4)
hidden_triplet_tmp = metal_buffer(device, 3 * FFN * 4)
qkv_triplet_tmp = metal_buffer(device, 3 * QKV_DIM * 4)
z_triplet_tmp = metal_buffer(device, 3 * V_DIM * 4)
a_triplet_tmp = metal_buffer(device, 3 * HV * 4)
b_triplet_tmp = metal_buffer(device, 3 * HV * 4)
conv_triplet_tmp = metal_buffer(device, 3 * QKV_DIM * 4)
mq_triplet_tmp = metal_buffer(device, 3 * Q_DIM * 4)
mk_triplet_tmp = metal_buffer(device, 3 * K_DIM * 4)
mv_triplet_tmp = metal_buffer(device, 3 * V_DIM * 4)
g_triplet_tmp = metal_buffer(device, 3 * HV * 4)
beta_triplet_tmp = metal_buffer(device, 3 * HV * 4)
delta_triplet_tmp = metal_buffer(device, 3 * V_DIM * 4)
mamba_norm_triplet_tmp = metal_buffer(device, 3 * V_DIM * 4)
qfull_triplet_tmp = metal_buffer(device, 3 * QFULL_DIM * 4)
queries_triplet_tmp = metal_buffer(device, 3 * ATTN_DIM * 4)
attn_gate_triplet_tmp = metal_buffer(device, 3 * ATTN_DIM * 4)
k_triplet_tmp = metal_buffer(device, 3 * KV_DIM * 4)
v_triplet_tmp = metal_buffer(device, 3 * KV_DIM * 4)
attn_triplet_tmp = metal_buffer(device, 3 * ATTN_DIM * 4)
cos_triplet_tmp = metal_buffer(device, 3 * ROT_HALF * 4)
sin_triplet_tmp = metal_buffer(device, 3 * ROT_HALF * 4)
logits_triplet = metal_buffer(device, 3 * N_VOCAB * 4)
argmax_triplet_out = metal_buffer(device, 3 * 4)
token_triplet_buf = metal_buffer(device, 3 * 4)

logits = metal_buffer(device, N_VOCAB * 4)
argmax_out = metal_buffer(device, 4)
n_vocab_buf = metal_buffer(device, 4)
metal_buffer_write_i32(n_vocab_buf, 0, N_VOCAB)
argmax_partial_values = metal_buffer(device, 3 * ARGMAX_CHUNKS * 4)
argmax_partial_indices = metal_buffer(device, 3 * ARGMAX_CHUNKS * 4)

log_rope = Math.log(ROPE_BASE)
rope_power = ~2.0 / ROT_DIM
-> build_rope(pos)
  i = 0
  while i < ROT_HALF
    theta = Math.exp(log_rope * (~0.0 - i * rope_power))
    angle = pos * theta
    metal_buffer_write_f32(cos_tmp, i, Math.cos(angle))
    metal_buffer_write_f32(sin_tmp, i, Math.sin(angle))
    i = i + 1

-> build_rope_pair(pos_start)
  token = 0
  while token < 2
    i = 0
    while i < ROT_HALF
      theta = Math.exp(log_rope * (~0.0 - i * rope_power))
      angle = (pos_start + token) * theta
      metal_buffer_write_f32(cos_pair_tmp, token * ROT_HALF + i, Math.cos(angle))
      metal_buffer_write_f32(sin_pair_tmp, token * ROT_HALF + i, Math.sin(angle))
      i = i + 1
    token = token + 1

-> build_rope_triplet(pos_start)
  token = 0
  while token < 3
    i = 0
    while i < ROT_HALF
      theta = Math.exp(log_rope * (~0.0 - i * rope_power))
      angle = (pos_start + token) * theta
      metal_buffer_write_f32(cos_triplet_tmp, token * ROT_HALF + i, Math.cos(angle))
      metal_buffer_write_f32(sin_triplet_tmp, token * ROT_HALF + i, Math.sin(angle))
      i = i + 1
    token = token + 1

-> enqueue_scaled(spec)
  w = spec[0]
  input = spec[1]
  output = spec[2]
  kdim = spec[3]
  rows = spec[4]
  args = [w[0], w[1], input, output, kdim, w[2]]
  schedule = row_schedule
  if schedule == "auto"
    schedule = "8r"
    if kdim == FFN && rows == HIDDEN
      schedule = "16r"
    if rows == QKV_DIM || rows == V_DIM || rows == QFULL_DIM || (kdim == HIDDEN * 2 && rows == HIDDEN)
      schedule = "r2"
    if rows == KV_DIM || rows == N_VOCAB
      schedule = "4r"
  if schedule == "4r"
    metal_dispatch_groups(queue, scaled_4_pipe, args, rows / 4, 32)
  else
    if schedule == "16r"
      metal_dispatch_groups(queue, scaled_16_pipe, args, rows / 16, 128)
    else
      if schedule == "r2"
        metal_dispatch_groups(queue, r2_pipe, args, rows / 8, 64)
      else
        metal_dispatch_groups(queue, scaled_pipe, args, rows / 8, 64)

-> enqueue_scaled_pair(spec)
  w = spec[0]
  input = spec[1]
  output = spec[2]
  kdim = spec[3]
  rows = spec[4]
  metal_dispatch_groups(queue, scaled_pair_pipe,
    [w[0], w[1], input, output, kdim, rows, w[2]], (rows + 3) / 4, 64)

-> enqueue_residual_pair(spec)
  w = spec[0]
  input = spec[1]
  residual = spec[2]
  kdim = spec[3]
  rows = spec[4]
  metal_dispatch_groups(queue, scaled_pair_res_pipe,
    [w[0], w[1], input, residual, kdim, rows, w[2]], (rows + 3) / 4, 64)

-> enqueue_scaled_triplet(spec)
  w = spec[0]
  input = spec[1]
  output = spec[2]
  kdim = spec[3]
  rows = spec[4]
  if kdim == FFN || rows == N_VOCAB
    metal_dispatch_groups(queue, scaled_triplet_pipe,
      [w[0], w[1], input, output, kdim, rows, w[2]], (rows + 3) / 4, 64)
  else
    metal_dispatch_groups(queue, scaled_triplet_r1_pipe,
      [w[0], w[1], input, output, kdim, rows, w[2]], (rows + 1) / 2, 64)

-> enqueue_residual_triplet(spec)
  w = spec[0]
  input = spec[1]
  residual = spec[2]
  kdim = spec[3]
  rows = spec[4]
  if kdim == FFN
    metal_dispatch_groups(queue, scaled_triplet_res_pipe,
      [w[0], w[1], input, residual, kdim, rows, w[2]], (rows + 3) / 4, 64)
  else
    metal_dispatch_groups(queue, scaled_triplet_res_r1_pipe,
      [w[0], w[1], input, residual, kdim, rows, w[2]], (rows + 1) / 2, 64)

-> enqueue_residual(spec)
  w = spec[0]
  input = spec[1]
  residual = spec[2]
  kdim = spec[3]
  rows = spec[4]
  if optimized
    metal_dispatch_groups(queue, scaled_res_pipe, [w[0], w[1], input, residual, kdim, w[2]], rows / 8, 64)
  else
    enqueue_scaled([w, input, projection, kdim, rows])
    metal_dispatch_n(queue, add_pipe, [residual, projection, rows], rows)

-> dependency_barrier
  if concurrent then metal_batch_barrier(queue)

-> enqueue_rms(spec)
  if legacy_reductions
    if spec[3] == 1
      metal_dispatch_groups(queue, rms_pipe,
        [spec[0], spec[1], spec[2], HIDDEN, ~1.0 / HIDDEN, EPS], 1, 256)
    elsif spec[3] == 2
      metal_dispatch_groups(queue, rms_pair_pipe,
        [spec[0], spec[1], spec[2], ~1.0 / HIDDEN, EPS], 2, 32)
    else
      metal_dispatch_groups(queue, rms_triplet_pipe,
        [spec[0], spec[1], spec[2], ~1.0 / HIDDEN, EPS], 3, 32)
  else
    metal_dispatch_groups(queue, rms_batch_pipe,
      [spec[0], spec[1], spec[2], HIDDEN, spec[3], ~1.0 / HIDDEN, EPS],
      spec[3], 512)

# Two-stage exact vocabulary reduction. The previous one-simdgroup argmax
# scanned all 248K logits twice and cost ~1.7 ms; this uses 1024-logit tiles
# and a small final reduction for all target widths.
-> enqueue_argmax(spec)
  input_logits = spec[0]
  output_index = spec[1]
  batch = spec[2]
  if legacy_reductions
    if batch == 1
      metal_dispatch_groups(queue, argmax_pipe,
        [input_logits, output_index, n_vocab_buf], 1, 32)
    elsif batch == 2
      metal_dispatch_groups(queue, argmax_pair_pipe,
        [input_logits, output_index], 2, 32)
    else
      metal_dispatch_groups(queue, argmax_triplet_pipe,
        [input_logits, output_index], 3, 32)
  else
    metal_dispatch_groups(queue, argmax_stage1_pipe,
      [input_logits, argmax_partial_values, argmax_partial_indices,
       N_VOCAB, ARGMAX_CHUNKS, batch], batch * ARGMAX_CHUNKS, 256)
    dependency_barrier()
    metal_dispatch_groups(queue, argmax_stage2_pipe,
      [argmax_partial_values, argmax_partial_indices, output_index,
       ARGMAX_CHUNKS, batch], batch, 256)

-> enqueue_mamba(lyr)
  cs_in = lyr[:cs_a]
  cs_out = lyr[:cs_b]
  ss_in = lyr[:ss_a]
  ss_out = lyr[:ss_b]
  if lyr[:ping] == 1
    cs_in = lyr[:cs_b]
    cs_out = lyr[:cs_a]
    ss_in = lyr[:ss_b]
    ss_out = lyr[:ss_a]
  enqueue_rms([x, lyr[:in_norm], xn, 1])
  dependency_barrier()
  enqueue_scaled([lyr[:qkv], xn, qkv_tmp, HIDDEN, QKV_DIM])
  enqueue_scaled([lyr[:z], xn, z_tmp, HIDDEN, V_DIM])
  metal_dispatch_groups(queue, bf16_matvec_pipe, [lyr[:a], xn, a_tmp, HIDDEN], HV, 32)
  metal_dispatch_groups(queue, bf16_matvec_pipe, [lyr[:b], xn, b_tmp, HIDDEN], HV, 32)
  dependency_barrier()
  metal_dispatch_n(queue, conv_pipe, [lyr[:conv], cs_in, qkv_tmp, conv_tmp, cs_out, QKV_DIM, QKV_DIM], QKV_DIM)
  dependency_barrier()
  metal_dispatch_n(queue, copy_pipe, [conv_tmp, mq_tmp, 0, Q_DIM], Q_DIM)
  metal_dispatch_n(queue, copy_pipe, [conv_tmp, mk_tmp, Q_DIM, K_DIM], K_DIM)
  metal_dispatch_n(queue, copy_pipe, [conv_tmp, mv_tmp, Q_DIM + K_DIM, V_DIM], V_DIM)
  dependency_barrier()
  metal_dispatch_groups(queue, phn_pipe, [mq_tmp, q_norm_scale, DK, ~1.0 / DK, EPS], HK, 32)
  metal_dispatch_groups(queue, phn_pipe, [mk_tmp, k_norm_scale, DK, ~1.0 / DK, EPS], HK, 32)
  metal_dispatch_n(queue, g_pipe, [a_tmp, lyr[:alog], lyr[:dtb], g_tmp, HV, HV], HV)
  metal_dispatch_n(queue, sigmoid_pipe, [b_tmp, beta_tmp, HV], HV)
  dependency_barrier()
  metal_dispatch_3d(queue, delta_pipe, [mq_tmp, mk_tmp, mv_tmp, g_tmp, beta_tmp, ss_in, delta_tmp, ss_out, HK, HV, DK, DV], 1, DV / 4, HV, 32, 4, 1)
  dependency_barrier()
  metal_dispatch_groups(queue, rng_pipe, [delta_tmp, z_tmp, lyr[:linear_norm], mamba_norm_tmp, DV, EPS], HV, 32)
  dependency_barrier()
  enqueue_residual([lyr[:out], mamba_norm_tmp, x, V_DIM, HIDDEN])
  dependency_barrier()
  lyr[:ping] = 1 - lyr[:ping]

-> enqueue_full(lyr, pos)
  enqueue_rms([x, lyr[:in_norm], xn, 1])
  dependency_barrier()
  enqueue_scaled([lyr[:q], xn, qfull_tmp, HIDDEN, QFULL_DIM])
  enqueue_scaled([lyr[:k], xn, k_tmp, HIDDEN, KV_DIM])
  enqueue_scaled([lyr[:v], xn, v_tmp, HIDDEN, KV_DIM])
  dependency_barrier()
  metal_dispatch_n(queue, split_pipe, [qfull_tmp, queries_tmp, attn_gate_tmp, N_HEADS, HEAD_DIM], ATTN_DIM)
  dependency_barrier()
  metal_dispatch_groups(queue, phn_pipe, [queries_tmp, lyr[:qn], HEAD_DIM, ~1.0 / HEAD_DIM, EPS], N_HEADS, 32)
  metal_dispatch_groups(queue, phn_pipe, [k_tmp, lyr[:kn], HEAD_DIM, ~1.0 / HEAD_DIM, EPS], N_KV_HEADS, 32)
  dependency_barrier()
  if pos > 0
    metal_dispatch_n(queue, rope_pipe, [queries_tmp, cos_tmp, sin_tmp, HEAD_DIM, ROT_HALF, N_HEADS], N_HEADS * ROT_HALF)
    metal_dispatch_n(queue, rope_pipe, [k_tmp, cos_tmp, sin_tmp, HEAD_DIM, ROT_HALF, N_KV_HEADS], N_KV_HEADS * ROT_HALF)
  dependency_barrier()
  metal_dispatch_n(queue, kv_write_pipe, [k_tmp, lyr[:k_cache], pos, KV_DIM], KV_DIM)
  metal_dispatch_n(queue, kv_write_pipe, [v_tmp, lyr[:v_cache], pos, KV_DIM], KV_DIM)
  dependency_barrier()
  metal_dispatch_groups(queue, sdpa_pipe, [queries_tmp, lyr[:k_cache], lyr[:v_cache], attn_tmp, GQA, pos + 1, HEAD_DIM, KV_DIM, ATTN_SCALE], N_HEADS, 256)
  dependency_barrier()
  metal_dispatch_n(queue, gate_pipe, [attn_tmp, attn_gate_tmp, ATTN_DIM], ATTN_DIM)
  dependency_barrier()
  enqueue_residual([lyr[:out], attn_tmp, x, ATTN_DIM, HIDDEN])
  dependency_barrier()

-> enqueue_ffn(lyr)
  enqueue_rms([x, lyr[:post_norm], xn, 1])
  dependency_barrier()
  if optimized
    metal_dispatch_groups(queue, scaled_gu_pipe, [lyr[:gate][0], lyr[:gate][1], lyr[:up][0], lyr[:up][1], xn, gate_tmp, up_tmp, HIDDEN, FFN / 8, lyr[:gate][2], lyr[:up][2]], (FFN / 8) * 2, 64)
  else
    enqueue_scaled([lyr[:gate], xn, gate_tmp, HIDDEN, FFN])
    enqueue_scaled([lyr[:up], xn, up_tmp, HIDDEN, FFN])
  dependency_barrier()
  metal_dispatch_n(queue, silu_pipe, [gate_tmp, up_tmp, hidden_tmp, FFN], FFN)
  dependency_barrier()
  if optimized
    metal_dispatch_groups(queue, scaled_res_pipe, [lyr[:down][0], lyr[:down][1], hidden_tmp, x, FFN, lyr[:down][2]], HIDDEN / 8, 64)
  else
    enqueue_scaled([lyr[:down], hidden_tmp, ffn_out, FFN, HIDDEN])
    metal_dispatch_n(queue, add_pipe, [x, ffn_out, HIDDEN], HIDDEN)
  dependency_barrier()

-> enqueue_mamba_pair(lyr)
  cs_in = lyr[:cs_a]
  cs_out = lyr[:cs_b]
  ss_in = lyr[:ss_a]
  ss_out = lyr[:ss_b]
  if lyr[:ping] == 1
    cs_in = lyr[:cs_b]
    cs_out = lyr[:cs_a]
    ss_in = lyr[:ss_b]
    ss_out = lyr[:ss_a]
  enqueue_rms([x_pair, lyr[:in_norm], xn_pair, 2])
  dependency_barrier()
  enqueue_scaled_pair([lyr[:qkv], xn_pair, qkv_pair_tmp, HIDDEN, QKV_DIM])
  enqueue_scaled_pair([lyr[:z], xn_pair, z_pair_tmp, HIDDEN, V_DIM])
  metal_dispatch_groups(queue, pair_bf16_pipe,
    [lyr[:a], xn_pair, a_pair_tmp, HIDDEN, HV], HV, 32)
  metal_dispatch_groups(queue, pair_bf16_pipe,
    [lyr[:b], xn_pair, b_pair_tmp, HIDDEN, HV], HV, 32)
  dependency_barrier()
  metal_dispatch_n(queue, conv_pair_pipe,
    [lyr[:conv], cs_in, qkv_pair_tmp, conv_pair_tmp, lyr[:cs_mid], cs_out, QKV_DIM], QKV_DIM)
  dependency_barrier()
  metal_dispatch_n(queue, copy_pair_slice_pipe,
    [conv_pair_tmp, mq_pair_tmp, QKV_DIM, Q_DIM, 0, Q_DIM], 2 * Q_DIM)
  metal_dispatch_n(queue, copy_pair_slice_pipe,
    [conv_pair_tmp, mk_pair_tmp, QKV_DIM, K_DIM, Q_DIM, K_DIM], 2 * K_DIM)
  metal_dispatch_n(queue, copy_pair_slice_pipe,
    [conv_pair_tmp, mv_pair_tmp, QKV_DIM, V_DIM, Q_DIM + K_DIM, V_DIM], 2 * V_DIM)
  dependency_barrier()
  metal_dispatch_groups(queue, phn_pipe,
    [mq_pair_tmp, q_norm_scale, DK, ~1.0 / DK, EPS], 2 * HK, 32)
  metal_dispatch_groups(queue, phn_pipe,
    [mk_pair_tmp, k_norm_scale, DK, ~1.0 / DK, EPS], 2 * HK, 32)
  metal_dispatch_n(queue, g_pipe,
    [a_pair_tmp, lyr[:alog], lyr[:dtb], g_pair_tmp, HV, 2 * HV], 2 * HV)
  metal_dispatch_n(queue, sigmoid_pipe, [b_pair_tmp, beta_pair_tmp, 2 * HV], 2 * HV)
  dependency_barrier()
  metal_dispatch_3d(queue, delta_pair_pipe,
    [mq_pair_tmp, mk_pair_tmp, mv_pair_tmp, g_pair_tmp, beta_pair_tmp,
     ss_in, delta_pair_tmp, lyr[:ss_mid], ss_out, HK, HV, DK, DV],
    1, DV / 4, HV, 32, 4, 1)
  dependency_barrier()
  metal_dispatch_groups(queue, rng_pipe,
    [delta_pair_tmp, z_pair_tmp, lyr[:linear_norm], mamba_norm_pair_tmp, DV, EPS],
    2 * HV, 32)
  dependency_barrier()
  enqueue_residual_pair([lyr[:out], mamba_norm_pair_tmp, x_pair, V_DIM, HIDDEN])
  dependency_barrier()
  lyr[:ping] = 1 - lyr[:ping]

-> enqueue_full_pair(spec)
  lyr = spec[0]
  pos_start = spec[1]
  enqueue_rms([x_pair, lyr[:in_norm], xn_pair, 2])
  dependency_barrier()
  enqueue_scaled_pair([lyr[:q], xn_pair, qfull_pair_tmp, HIDDEN, QFULL_DIM])
  enqueue_scaled_pair([lyr[:k], xn_pair, k_pair_tmp, HIDDEN, KV_DIM])
  enqueue_scaled_pair([lyr[:v], xn_pair, v_pair_tmp, HIDDEN, KV_DIM])
  dependency_barrier()
  metal_dispatch_n(queue, split_pair_pipe,
    [qfull_pair_tmp, queries_pair_tmp, attn_gate_pair_tmp, N_HEADS, HEAD_DIM],
    2 * ATTN_DIM)
  dependency_barrier()
  metal_dispatch_groups(queue, phn_rope_pair_pipe,
    [queries_pair_tmp, lyr[:qn], cos_pair_tmp, sin_pair_tmp,
     HEAD_DIM, ROT_HALF, N_HEADS, ~1.0 / HEAD_DIM, EPS], 2 * N_HEADS, 32)
  metal_dispatch_groups(queue, phn_rope_pair_pipe,
    [k_pair_tmp, lyr[:kn], cos_pair_tmp, sin_pair_tmp,
     HEAD_DIM, ROT_HALF, N_KV_HEADS, ~1.0 / HEAD_DIM, EPS], 2 * N_KV_HEADS, 32)
  dependency_barrier()
  metal_dispatch_n(queue, kv_write_pair_pipe,
    [k_pair_tmp, v_pair_tmp, lyr[:k_cache], lyr[:v_cache], pos_start, KV_DIM],
    2 * KV_DIM)
  dependency_barrier()
  metal_dispatch_groups(queue, sdpa_pair_pipe,
    [queries_pair_tmp, lyr[:k_cache], lyr[:v_cache], attn_pair_tmp,
     GQA, pos_start, N_HEADS, KV_DIM, ATTN_SCALE], 2 * N_HEADS, 256)
  dependency_barrier()
  metal_dispatch_n(queue, gate_pipe,
    [attn_pair_tmp, attn_gate_pair_tmp, 2 * ATTN_DIM], 2 * ATTN_DIM)
  dependency_barrier()
  enqueue_residual_pair([lyr[:out], attn_pair_tmp, x_pair, ATTN_DIM, HIDDEN])
  dependency_barrier()

-> enqueue_ffn_pair(lyr)
  enqueue_rms([x_pair, lyr[:post_norm], xn_pair, 2])
  dependency_barrier()
  enqueue_scaled_pair([lyr[:gate], xn_pair, gate_pair_tmp, HIDDEN, FFN])
  enqueue_scaled_pair([lyr[:up], xn_pair, up_pair_tmp, HIDDEN, FFN])
  dependency_barrier()
  metal_dispatch_n(queue, silu_pipe,
    [gate_pair_tmp, up_pair_tmp, hidden_pair_tmp, 2 * FFN], 2 * FFN)
  dependency_barrier()
  enqueue_residual_pair([lyr[:down], hidden_pair_tmp, x_pair, FFN, HIDDEN])
  dependency_barrier()

-> enqueue_mamba_triplet(lyr)
  cs_in = lyr[:cs_a]
  cs_out = lyr[:cs_b]
  ss_in = lyr[:ss_a]
  ss_out = lyr[:ss_b]
  if lyr[:ping] == 1
    cs_in = lyr[:cs_b]
    cs_out = lyr[:cs_a]
    ss_in = lyr[:ss_b]
    ss_out = lyr[:ss_a]
  enqueue_rms([x_triplet, lyr[:in_norm], xn_triplet, 3])
  dependency_barrier()
  enqueue_scaled_triplet([lyr[:qkv], xn_triplet, qkv_triplet_tmp, HIDDEN, QKV_DIM])
  enqueue_scaled_triplet([lyr[:z], xn_triplet, z_triplet_tmp, HIDDEN, V_DIM])
  metal_dispatch_groups(queue, triplet_bf16_pipe,
    [lyr[:a], xn_triplet, a_triplet_tmp, HIDDEN, HV], HV, 32)
  metal_dispatch_groups(queue, triplet_bf16_pipe,
    [lyr[:b], xn_triplet, b_triplet_tmp, HIDDEN, HV], HV, 32)
  dependency_barrier()
  metal_dispatch_n(queue, conv_triplet_pipe,
    [lyr[:conv], cs_in, qkv_triplet_tmp, conv_triplet_tmp,
     lyr[:cs_mid], lyr[:cs_mid2], cs_out, QKV_DIM], QKV_DIM)
  dependency_barrier()
  metal_dispatch_n(queue, copy_triplet_slice_pipe,
    [conv_triplet_tmp, mq_triplet_tmp, QKV_DIM, Q_DIM, 0, Q_DIM], 3 * Q_DIM)
  metal_dispatch_n(queue, copy_triplet_slice_pipe,
    [conv_triplet_tmp, mk_triplet_tmp, QKV_DIM, K_DIM, Q_DIM, K_DIM], 3 * K_DIM)
  metal_dispatch_n(queue, copy_triplet_slice_pipe,
    [conv_triplet_tmp, mv_triplet_tmp, QKV_DIM, V_DIM, Q_DIM + K_DIM, V_DIM], 3 * V_DIM)
  dependency_barrier()
  metal_dispatch_groups(queue, phn_pipe,
    [mq_triplet_tmp, q_norm_scale, DK, ~1.0 / DK, EPS], 3 * HK, 32)
  metal_dispatch_groups(queue, phn_pipe,
    [mk_triplet_tmp, k_norm_scale, DK, ~1.0 / DK, EPS], 3 * HK, 32)
  metal_dispatch_n(queue, g_pipe,
    [a_triplet_tmp, lyr[:alog], lyr[:dtb], g_triplet_tmp, HV, 3 * HV], 3 * HV)
  metal_dispatch_n(queue, sigmoid_pipe,
    [b_triplet_tmp, beta_triplet_tmp, 3 * HV], 3 * HV)
  dependency_barrier()
  metal_dispatch_3d(queue, delta_triplet_pipe,
    [mq_triplet_tmp, mk_triplet_tmp, mv_triplet_tmp, g_triplet_tmp,
     beta_triplet_tmp, ss_in, delta_triplet_tmp, lyr[:ss_mid],
     lyr[:ss_mid2], ss_out, HK, HV, DK, DV],
    1, DV / 4, HV, 32, 4, 1)
  dependency_barrier()
  metal_dispatch_groups(queue, rng_pipe,
    [delta_triplet_tmp, z_triplet_tmp, lyr[:linear_norm],
     mamba_norm_triplet_tmp, DV, EPS], 3 * HV, 32)
  dependency_barrier()
  enqueue_residual_triplet(
    [lyr[:out], mamba_norm_triplet_tmp, x_triplet, V_DIM, HIDDEN])
  dependency_barrier()
  lyr[:ping] = 1 - lyr[:ping]

-> enqueue_full_triplet(spec)
  lyr = spec[0]
  pos_start = spec[1]
  enqueue_rms([x_triplet, lyr[:in_norm], xn_triplet, 3])
  dependency_barrier()
  enqueue_scaled_triplet([lyr[:q], xn_triplet, qfull_triplet_tmp, HIDDEN, QFULL_DIM])
  enqueue_scaled_triplet([lyr[:k], xn_triplet, k_triplet_tmp, HIDDEN, KV_DIM])
  enqueue_scaled_triplet([lyr[:v], xn_triplet, v_triplet_tmp, HIDDEN, KV_DIM])
  dependency_barrier()
  metal_dispatch_n(queue, split_triplet_pipe,
    [qfull_triplet_tmp, queries_triplet_tmp, attn_gate_triplet_tmp,
     N_HEADS, HEAD_DIM], 3 * ATTN_DIM)
  dependency_barrier()
  metal_dispatch_groups(queue, phn_rope_triplet_pipe,
    [queries_triplet_tmp, lyr[:qn], cos_triplet_tmp, sin_triplet_tmp,
     HEAD_DIM, ROT_HALF, N_HEADS, ~1.0 / HEAD_DIM, EPS], 3 * N_HEADS, 32)
  metal_dispatch_groups(queue, phn_rope_triplet_pipe,
    [k_triplet_tmp, lyr[:kn], cos_triplet_tmp, sin_triplet_tmp,
     HEAD_DIM, ROT_HALF, N_KV_HEADS, ~1.0 / HEAD_DIM, EPS], 3 * N_KV_HEADS, 32)
  dependency_barrier()
  metal_dispatch_n(queue, kv_write_triplet_pipe,
    [k_triplet_tmp, v_triplet_tmp, lyr[:k_cache], lyr[:v_cache],
     pos_start, KV_DIM], 3 * KV_DIM)
  dependency_barrier()
  metal_dispatch_groups(queue, sdpa_triplet_pipe,
    [queries_triplet_tmp, lyr[:k_cache], lyr[:v_cache], attn_triplet_tmp,
     GQA, pos_start, N_HEADS, KV_DIM, ATTN_SCALE], 3 * N_HEADS, 256)
  dependency_barrier()
  metal_dispatch_n(queue, gate_pipe,
    [attn_triplet_tmp, attn_gate_triplet_tmp, 3 * ATTN_DIM], 3 * ATTN_DIM)
  dependency_barrier()
  enqueue_residual_triplet(
    [lyr[:out], attn_triplet_tmp, x_triplet, ATTN_DIM, HIDDEN])
  dependency_barrier()

-> enqueue_ffn_triplet(lyr)
  enqueue_rms([x_triplet, lyr[:post_norm], xn_triplet, 3])
  dependency_barrier()
  enqueue_scaled_triplet([lyr[:gate], xn_triplet, gate_triplet_tmp, HIDDEN, FFN])
  enqueue_scaled_triplet([lyr[:up], xn_triplet, up_triplet_tmp, HIDDEN, FFN])
  dependency_barrier()
  metal_dispatch_n(queue, silu_pipe,
    [gate_triplet_tmp, up_triplet_tmp, hidden_triplet_tmp, 3 * FFN], 3 * FFN)
  dependency_barrier()
  enqueue_residual_triplet(
    [lyr[:down], hidden_triplet_tmp, x_triplet, FFN, HIDDEN])
  dependency_barrier()

# A committed MTP-history row only needs to append the attention K/V derived
# from the fused embedding/target-hidden input. Q, attention output, the MLP,
# final norm, and vocabulary projection are dead for this row.
-> enqueue_mtp_history(lyr, pos)
  enqueue_rms([x, lyr[:in_norm], xn, 1])
  dependency_barrier()
  enqueue_scaled([lyr[:k], xn, k_tmp, HIDDEN, KV_DIM])
  enqueue_scaled([lyr[:v], xn, v_tmp, HIDDEN, KV_DIM])
  dependency_barrier()
  metal_dispatch_groups(queue, phn_pipe,
    [k_tmp, lyr[:kn], HEAD_DIM, ~1.0 / HEAD_DIM, EPS], N_KV_HEADS, 32)
  dependency_barrier()
  if pos > 0
    metal_dispatch_n(queue, rope_pipe,
      [k_tmp, cos_tmp, sin_tmp, HEAD_DIM, ROT_HALF, N_KV_HEADS],
      N_KV_HEADS * ROT_HALF)
  dependency_barrier()
  metal_dispatch_n(queue, kv_write_pipe,
    [k_tmp, lyr[:k_cache], pos, KV_DIM], KV_DIM)
  metal_dispatch_n(queue, kv_write_pipe,
    [v_tmp, lyr[:v_cache], pos, KV_DIM], KV_DIM)
  dependency_barrier()

-> mtp_step(spec)
  profile_t0 = profile_components ? ccall("__w_clock_ms") : ~0.0
  token_id = spec[0]
  hidden_in = spec[1]
  pos = spec[2]
  want_draft = legacy_mtp || full_history_mtp || spec.size() < 4 || spec[3]
  if pos > 0 then build_rope(pos)
  metal_batch_begin_concurrent(queue)
  metal_dispatch_n(queue, bf16_embed_pipe,
    [embed_w, mtp_embed_tmp, token_id, HIDDEN], HIDDEN)
  dependency_barrier()
  enqueue_rms([mtp_embed_tmp, mtp_enorm, mtp_embed_norm_tmp, 1])
  enqueue_rms([hidden_in, mtp_hnorm, mtp_hidden_norm_tmp, 1])
  dependency_barrier()
  metal_dispatch_n(queue, concat_pipe,
    [mtp_embed_norm_tmp, mtp_hidden_norm_tmp, mtp_fc_input_tmp, HIDDEN], HIDDEN)
  dependency_barrier()
  enqueue_scaled([mtp_fc, mtp_fc_input_tmp, x, HIDDEN * 2, HIDDEN])
  dependency_barrier()
  if want_draft
    enqueue_full(mtp_layer, pos)
    enqueue_ffn(mtp_layer)
    enqueue_rms([x, mtp_norm, xn, 1])
    dependency_barrier()
    if full_draft_vocab
      enqueue_scaled([lm_head, xn, logits, HIDDEN, N_VOCAB])
      dependency_barrier()
      enqueue_argmax([logits, argmax_out, 1])
    else
      enqueue_scaled([mtp_draft_prefix_head, xn, mtp_prefix_logits,
        HIDDEN, MTP_DRAFT_PREFIX])
      enqueue_scaled([mtp_draft_control_head, xn, mtp_control_logits,
        HIDDEN, MTP_DRAFT_CONTROL_ROWS])
      dependency_barrier()
      metal_dispatch_groups(queue, mtp_select_pipe,
        [mtp_prefix_logits, mtp_control_logits, argmax_out,
         MTP_DRAFT_PREFIX, MTP_DRAFT_CONTROL_COUNT, MTP_DRAFT_CONTROL_START],
        1, 32)
  else
    enqueue_mtp_history(mtp_layer, pos)
  metal_batch_commit(queue)
  result = want_draft ? metal_buffer_read_i32(argmax_out, 0) : -1
  if profile_components
    profile_dt = ccall("__w_clock_ms") - profile_t0
    if want_draft
      profile_stats[7] = profile_stats[7] + profile_dt
      profile_stats[8] = profile_stats[8] + 1
    else
      profile_stats[9] = profile_stats[9] + profile_dt
      profile_stats[10] = profile_stats[10] + 1
  result

-> forward_pair(spec)
  profile_t0 = profile_components ? ccall("__w_clock_ms") : ~0.0
  token0 = spec[0]
  token1 = spec[1]
  pos_start = spec[2]
  build_rope_pair(pos_start)
  metal_buffer_write_i32(token_pair_buf, 0, token0)
  metal_buffer_write_i32(token_pair_buf, 1, token1)
  metal_batch_begin_concurrent(queue)
  metal_dispatch_n(queue, pair_embed_pipe,
    [embed_w, x_pair, token_pair_buf, HIDDEN], 2 * HIDDEN)
  dependency_barrier()
  li = 0
  while li < N_LAYERS
    lyr = layers[li]
    if lyr[:kind] == "mamba"
      enqueue_mamba_pair(lyr)
    else
      enqueue_full_pair([lyr, pos_start])
    enqueue_ffn_pair(lyr)
    li = li + 1
  enqueue_rms([x_pair, final_norm, xn_pair, 2])
  dependency_barrier()
  enqueue_scaled_pair([lm_head, xn_pair, logits_pair, HIDDEN, N_VOCAB])
  dependency_barrier()
  enqueue_argmax([logits_pair, argmax_pair_out, 2])
  metal_batch_commit(queue)
  result = [metal_buffer_read_i32(argmax_pair_out, 0), metal_buffer_read_i32(argmax_pair_out, 1)]
  if profile_components
    profile_stats[5] = profile_stats[5] + ccall("__w_clock_ms") - profile_t0
    profile_stats[6] = profile_stats[6] + 1
  result

-> forward_triplet(spec)
  profile_t0 = profile_components ? ccall("__w_clock_ms") : ~0.0
  token0 = spec[0]
  token1 = spec[1]
  token2 = spec[2]
  pos_start = spec[3]
  build_rope_triplet(pos_start)
  metal_buffer_write_i32(token_triplet_buf, 0, token0)
  metal_buffer_write_i32(token_triplet_buf, 1, token1)
  metal_buffer_write_i32(token_triplet_buf, 2, token2)
  metal_batch_begin_concurrent(queue)
  metal_dispatch_n(queue, triplet_embed_pipe,
    [embed_w, x_triplet, token_triplet_buf, HIDDEN], 3 * HIDDEN)
  dependency_barrier()
  li = 0
  while li < N_LAYERS
    lyr = layers[li]
    if lyr[:kind] == "mamba"
      enqueue_mamba_triplet(lyr)
    else
      enqueue_full_triplet([lyr, pos_start])
    enqueue_ffn_triplet(lyr)
    li = li + 1
  enqueue_rms([x_triplet, final_norm, xn_triplet, 3])
  dependency_barrier()
  enqueue_scaled_triplet([lm_head, xn_triplet, logits_triplet, HIDDEN, N_VOCAB])
  dependency_barrier()
  enqueue_argmax([logits_triplet, argmax_triplet_out, 3])
  metal_batch_commit(queue)
  result = [metal_buffer_read_i32(argmax_triplet_out, 0),
    metal_buffer_read_i32(argmax_triplet_out, 1),
    metal_buffer_read_i32(argmax_triplet_out, 2)]
  if profile_components
    profile_stats[5] = profile_stats[5] + ccall("__w_clock_ms") - profile_t0
    profile_stats[6] = profile_stats[6] + 1
  result

-> copy_hidden_pair_row(row)
  profile_t0 = profile_components ? ccall("__w_clock_ms") : ~0.0
  metal_batch_begin(queue)
  metal_dispatch_n(queue, copy_pair_row_pipe,
    [xn_pair, backbone_hidden, row, HIDDEN], HIDDEN)
  metal_batch_commit(queue)
  if profile_components
    profile_stats[11] = profile_stats[11] + ccall("__w_clock_ms") - profile_t0
    profile_stats[12] = profile_stats[12] + 1

-> copy_hidden_triplet_row(row)
  profile_t0 = profile_components ? ccall("__w_clock_ms") : ~0.0
  metal_batch_begin(queue)
  metal_dispatch_n(queue, copy_pair_row_pipe,
    [xn_triplet, backbone_hidden, row, HIDDEN], HIDDEN)
  metal_batch_commit(queue)
  if profile_components
    profile_stats[11] = profile_stats[11] + ccall("__w_clock_ms") - profile_t0
    profile_stats[12] = profile_stats[12] + 1

-> rollback_pair_states
  profile_t0 = profile_components ? ccall("__w_clock_ms") : ~0.0
  li = 0
  while li < N_LAYERS
    lyr = layers[li]
    if lyr[:kind] == "mamba"
      if lyr[:ping] == 1
        tmp = lyr[:cs_b]
        lyr[:cs_b] = lyr[:cs_mid]
        lyr[:cs_mid] = tmp
        tmp = lyr[:ss_b]
        lyr[:ss_b] = lyr[:ss_mid]
        lyr[:ss_mid] = tmp
      else
        tmp = lyr[:cs_a]
        lyr[:cs_a] = lyr[:cs_mid]
        lyr[:cs_mid] = tmp
        tmp = lyr[:ss_a]
        lyr[:ss_a] = lyr[:ss_mid]
        lyr[:ss_mid] = tmp
    li = li + 1
  if profile_components
    profile_stats[13] = profile_stats[13] + ccall("__w_clock_ms") - profile_t0
    profile_stats[14] = profile_stats[14] + 1

-> rollback_triplet_states(accepted_count)
  profile_t0 = profile_components ? ccall("__w_clock_ms") : ~0.0
  li = 0
  while li < N_LAYERS
    lyr = layers[li]
    if lyr[:kind] == "mamba"
      if accepted_count == 0
        chosen_cs = lyr[:cs_mid]
        chosen_ss = lyr[:ss_mid]
      else
        chosen_cs = lyr[:cs_mid2]
        chosen_ss = lyr[:ss_mid2]
      if lyr[:ping] == 1
        old_cs = lyr[:cs_b]
        old_ss = lyr[:ss_b]
        lyr[:cs_b] = chosen_cs
        lyr[:ss_b] = chosen_ss
      else
        old_cs = lyr[:cs_a]
        old_ss = lyr[:ss_a]
        lyr[:cs_a] = chosen_cs
        lyr[:ss_a] = chosen_ss
      if accepted_count == 0
        lyr[:cs_mid] = old_cs
        lyr[:ss_mid] = old_ss
      else
        lyr[:cs_mid2] = old_cs
        lyr[:ss_mid2] = old_ss
    li = li + 1
  if profile_components
    profile_stats[13] = profile_stats[13] + ccall("__w_clock_ms") - profile_t0
    profile_stats[14] = profile_stats[14] + 1

-> forward(token_id, pos, want_logits)
  profile_t0 = profile_components ? ccall("__w_clock_ms") : ~0.0
  if pos > 0 then build_rope(pos)
  if concurrent then metal_batch_begin_concurrent(queue) else metal_batch_begin(queue)
  metal_dispatch_n(queue, bf16_embed_pipe, [embed_w, x, token_id, HIDDEN], HIDDEN)
  dependency_barrier()
  if !optimized then metal_batch_commit(queue)

  li = 0
  while li < N_LAYERS
    if !optimized then metal_batch_begin(queue)
    lyr = layers[li]
    if lyr[:kind] == "mamba" then enqueue_mamba(lyr) else enqueue_full(lyr, pos)
    enqueue_ffn(lyr)
    if !optimized then metal_batch_commit(queue)
    li = li + 1

  if !optimized then metal_batch_begin(queue)
  if want_logits || mtp_enabled
    enqueue_rms([x, final_norm, xn, 1])
    dependency_barrier()
    if mtp_enabled
      metal_dispatch_n(queue, copy_pipe, [xn, backbone_hidden, 0, HIDDEN], HIDDEN)
      dependency_barrier()
  if want_logits
    enqueue_scaled([lm_head, xn, logits, HIDDEN, N_VOCAB])
    dependency_barrier()
    enqueue_argmax([logits, argmax_out, 1])
  metal_batch_commit(queue)
  result = want_logits ? metal_buffer_read_i32(argmax_out, 0) : -1
  if profile_components
    profile_dt = ccall("__w_clock_ms") - profile_t0
    if profile_stats[0] == 1
      profile_stats[3] = profile_stats[3] + profile_dt
      if profile_stats[4] == 0
        profile_stats[15] = profile_dt
      else
        profile_stats[16] = profile_stats[16] + profile_dt
      profile_stats[4] = profile_stats[4] + 1
    else
      profile_stats[1] = profile_stats[1] + profile_dt
      profile_stats[2] = profile_stats[2] + 1
  result

# The raw Ollama prompt tokenization is stable for this tokenizer.
prompt_seed = [760, 6511, 314, 9338, 369]
prompt = []
i = 0
while i < profile_prompt_tokens
  prompt.push(prompt_seed[i % prompt_seed.size()])
  i = i + 1
setup_elapsed = ccall("__w_clock_ms") - setup_t0
<< "prefill " + prompt.size().to_s + " tokens"
prefill_t0 = ccall("__w_clock_ms")
profile_stats[0] = 1
i = 0
pred = -1
while i < prompt.size()
  pred = forward(prompt[i], i, i == prompt.size() - 1)
  if mtp_enabled && i + 1 < prompt.size()
    mtp_step([prompt[i + 1], backbone_hidden, i, false])
  i = i + 1
profile_stats[0] = 0
prefill_elapsed = ccall("__w_clock_ms") - prefill_t0
if prompt.size() == 5 && pred != 11751
  raise "Qwen3.8 parity failure: expected first token 11751, got " + pred.to_s
if prompt.size() == 5 then << "parity PASS: first token 11751 ( Paris)"

ids = []
ids.push(pred)
pos = prompt.size()
t0 = ccall("__w_clock_ms")
accepted = 0
drafted = 0
deep_drafted = 0
deep_accepted = 0
# Adaptive arm state: completed rounds, emitted tokens, and elapsed ms for
# depth 1 and depth 2. Arrays keep updates visible across the decode loop.
mtp_auto_rounds = [0, 0]
mtp_auto_tokens = [0, 0]
mtp_auto_ms = [~0.0, ~0.0]
if mtp_enabled
  current = pred
  draft = mtp_step([current, backbone_hidden, pos - 1])
  generated = 0
  while generated < n_generate
    remaining = n_generate - generated
    if remaining == 1
      current = forward(current, pos, true)
      ids.push(current)
      pos = pos + 1
      generated = generated + 1
    else
      use_depth2 = mtp_depth2 && remaining >= 3
      if mtp_adaptive && remaining >= 3
        if mtp_auto_rounds[0] == 0
          use_depth2 = false
        else
          if mtp_auto_rounds[1] == 0
            use_depth2 = true
          else
            depth1_score = (~0.0 + mtp_auto_tokens[0]) / mtp_auto_ms[0]
            depth2_score = (~0.0 + mtp_auto_tokens[1]) / mtp_auto_ms[1]
            use_depth2 = depth2_score > depth1_score
      arm = use_depth2 ? 1 : 0
      round_generated_before = generated
      round_t0 = mtp_adaptive ? ccall("__w_clock_ms") : ~0.0
      if use_depth2
        verify_draft0 = draft
        verify_draft1 = mtp_step([verify_draft0, xn, pos])
        if force_reject && drafted == 0
          verify_draft0 = (verify_draft0 + 1) % N_VOCAB
        triplet_preds = forward_triplet(
          [current, verify_draft0, verify_draft1, pos])
        accepted_now = 0
        if triplet_preds[0] == verify_draft0
          accepted_now = 1
          if triplet_preds[1] == verify_draft1
            accepted_now = 2
        accepted = accepted + accepted_now
        drafted = drafted + 2
        deep_drafted = deep_drafted + 1
        if accepted_now == 2 then deep_accepted = deep_accepted + 1
        if accepted_now == 2
          ids.push(verify_draft0)
          ids.push(verify_draft1)
          bonus = triplet_preds[2]
          ids.push(bonus)
          generated = generated + 3
          if generated < n_generate
            copy_hidden_triplet_row(0)
            mtp_step([verify_draft0, backbone_hidden, pos, false])
            copy_hidden_triplet_row(1)
            mtp_step([verify_draft1, backbone_hidden, pos + 1, false])
            copy_hidden_triplet_row(2)
            draft = mtp_step([bonus, backbone_hidden, pos + 2])
          current = bonus
          pos = pos + 3
        else
          rollback_triplet_states(accepted_now)
          if accepted_now == 1
            ids.push(verify_draft0)
            correction = triplet_preds[1]
            ids.push(correction)
            generated = generated + 2
            if generated < n_generate
              copy_hidden_triplet_row(0)
              mtp_step([verify_draft0, backbone_hidden, pos, false])
              copy_hidden_triplet_row(1)
              draft = mtp_step([correction, backbone_hidden, pos + 1])
            current = correction
            pos = pos + 2
          else
            correction = triplet_preds[0]
            ids.push(correction)
            generated = generated + 1
            if generated < n_generate
              copy_hidden_triplet_row(0)
              draft = mtp_step([correction, backbone_hidden, pos])
            current = correction
            pos = pos + 1
      else
        verify_draft = draft
        if force_reject && drafted == 0
          verify_draft = (draft + 1) % N_VOCAB
        pair_preds = forward_pair([current, verify_draft, pos])
        drafted = drafted + 1
        if pair_preds[0] == verify_draft
          accepted = accepted + 1
          ids.push(verify_draft)
          bonus = pair_preds[1]
          ids.push(bonus)
          generated = generated + 2
          if generated < n_generate
            copy_hidden_pair_row(0)
            mtp_step([verify_draft, backbone_hidden, pos, false])
            copy_hidden_pair_row(1)
            draft = mtp_step([bonus, backbone_hidden, pos + 1])
          current = bonus
          pos = pos + 2
        else
          rollback_pair_states()
          current = pair_preds[0]
          ids.push(current)
          generated = generated + 1
          if generated < n_generate
            copy_hidden_pair_row(0)
            draft = mtp_step([current, backbone_hidden, pos])
          pos = pos + 1
      if mtp_adaptive
        mtp_auto_rounds[arm] = mtp_auto_rounds[arm] + 1
        mtp_auto_tokens[arm] = mtp_auto_tokens[arm] + generated - round_generated_before
        mtp_auto_ms[arm] = mtp_auto_ms[arm] + ccall("__w_clock_ms") - round_t0
else
  i = 0
  while i < n_generate
    next_id = forward(ids[ids.size() - 1], pos, true)
    ids.push(next_id)
    pos = pos + 1
    i = i + 1
elapsed = ccall("__w_clock_ms") - t0
tokens_per_second = (~0.0 + n_generate) * 1000.0 / elapsed

tokenizer = Tungsten:Llama:Tokenizer.from_packed_tokenizer(TOKENIZER_BIN)
text_out = tokenizer.decode(ids)
<< "generated ids: " + ids.to_s
<< "generated: " + text_out
if mtp_enabled
  rate = drafted == 0 ? ~0.0 : (~0.0 + accepted) / drafted
  << "mtp: " + accepted.to_s + "/" + drafted.to_s + " drafts accepted (" + rate.to_s + ")"
  if mtp_depth2
    deep_rate = deep_drafted == 0 ? ~0.0 : (~0.0 + deep_accepted) / deep_drafted
    << "mtp depth-2: " + deep_accepted.to_s + "/" + deep_drafted.to_s + " accepted (" + deep_rate.to_s + ")"
  if mtp_adaptive
    score1 = ~0.0
    score2 = ~0.0
    if mtp_auto_ms[0] != ~0.0
      score1 = (~0.0 + mtp_auto_tokens[0]) * 1000.0 / mtp_auto_ms[0]
    if mtp_auto_ms[1] != ~0.0
      score2 = (~0.0 + mtp_auto_tokens[1]) * 1000.0 / mtp_auto_ms[1]
    selected_depth = score2 > score1 ? 2 : 1
    auto_msg = "mtp auto: depth1=" + mtp_auto_rounds[0].to_s
    auto_msg = auto_msg + " rounds/" + score1.to_s + " tok/s, depth2="
    auto_msg = auto_msg + mtp_auto_rounds[1].to_s + " rounds/"
    auto_msg = auto_msg + score2.to_s + " tok/s -> depth " + selected_depth.to_s
    << auto_msg
<< "decode: " + n_generate.to_s + " tokens in " + elapsed.to_s + " ms, " + tokens_per_second.to_s + " tok/s"
if profile_components
  << "components: setup=" + setup_elapsed.to_s + " ms"
  << "components: prefill=" + prefill_elapsed.to_s + " ms, " + ((~0.0 + prompt.size()) * ~1000.0 / prefill_elapsed).to_s + " tok/s"
  << "components: prefill-target=" + profile_stats[3].to_s + " ms/" + profile_stats[4].to_s
  << "components: first-weight-touch=" + profile_stats[15].to_s + " ms, warm-prefill=" + profile_stats[16].to_s + " ms/" + (profile_stats[4] - 1).to_s
  << "components: decode-target=" + profile_stats[1].to_s + " ms/" + profile_stats[2].to_s
  << "components: verify=" + profile_stats[5].to_s + " ms/" + profile_stats[6].to_s
  << "components: draft=" + profile_stats[7].to_s + " ms/" + profile_stats[8].to_s
  << "components: history=" + profile_stats[9].to_s + " ms/" + profile_stats[10].to_s
  << "components: hidden-copy=" + profile_stats[11].to_s + " ms/" + profile_stats[12].to_s
  << "components: rollback=" + profile_stats[13].to_s + " ms/" + profile_stats[14].to_s
