# Lightning-1.7B-mlx-nvfp4 generation bench in pure Tungsten.
# Same forward pass as verify_lightning.w but loops 50 generated tokens
# after prefill so we can measure steady-state decode tok/s.
# MLX baseline on this model: 261.9 tok/s.

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
GROUP_SIZE = 2
KV_ROW = 1024
INTERMEDIATE = 6144
N_VOCAB = 151936
N_LAYERS = 28
EPS = ~0.000001
BASE = ~1000000.0
MAX_POS = 128
N_GENERATE = 50
N_PROMPT = 8
K_DECODE = 8

# Hoisted compound constants — used as inline literals in dispatch arg lists,
# auto-boxed to 1-elt Metal buffers by the runtime (cached per (kind, value)).
INV_HIDDEN            = ~1.0 / HIDDEN
INV_HEAD_DIM          = ~1.0 / HEAD_DIM
ATTN_SCALE            = ~1.0 / Math.sqrt(~0.0 + HEAD_DIM)
N_PROMPT_HIDDEN       = N_PROMPT * HIDDEN
N_PROMPT_INTERMEDIATE = N_PROMPT * INTERMEDIATE
K_DECODE_HIDDEN       = K_DECODE * HIDDEN
K_DECODE_INTERMEDIATE = K_DECODE * INTERMEDIATE
LAST_TOKEN_OFFSET     = (N_PROMPT - 1) * HIDDEN
KDIM_O                = N_Q_HEADS * HEAD_DIM

device = metal_device()
queue = metal_queue(device)

<< "loading Lightning-1.7B safetensors..."
st = Safetensors.new(LIGHTNING_PATH)

nvfp4_matvec_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec.metal")), "nvfp4_matvec")
nvfp4_matvec_v4_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_v4.metal")), "nvfp4_matvec_v4")
nvfp4_matvec_r_pipe  = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_residual.metal")), "nvfp4_matvec_residual")
nvfp4_matvec_silu_r_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_silu_residual.metal")), "nvfp4_matvec_silu_residual")
nvfp4_embed_pipe  = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_embedding_lookup.metal")), "nvfp4_embedding_lookup")
f16_to_f32_pipe   = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "f16_to_f32.metal")), "f16_to_f32")
rms_pipe       = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "shared/rms_norm.metal")), "rms_norm")
phn_rope_pipe  = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "shared/per_head_norm_rope.metal")), "per_head_norm_rope")
phn_rope_kc_pipe = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "shared/per_head_norm_rope_to_cache_bf16.metal")), "per_head_norm_rope_to_cache_bf16")
kv_pipe        = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "shared/kv_write_bf16.metal")), "kv_write_bf16")
scores_pipe    = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "shared/attn_scores.metal")), "attn_scores")
softmax_pipe   = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "shared/attn_softmax.metal")), "attn_softmax")
weighted_pipe  = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "shared/attn_weighted_sum.metal")), "attn_weighted_sum")
silu_pipe      = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "shared/silu_mul.metal")), "silu_mul")
argmax_pipe    = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "shared/argmax.metal")), "argmax")

# ---- Batched prefill pipelines (FC=K_DIM,N_ROWS,BATCH baked in) ----
nvfp4_mvb_lib    = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_batch_fc.metal"))
nvfp4_mvb_r_lib  = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_batch_residual_fc.metal"))
nvfp4_mvb_kv_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_batch_to_cache_fc.metal"))
nvfp4_mvb_v4_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_batch_v4_fc.metal"))
nvfp4_mvb_v4_r_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_batch_v4_residual_fc.metal"))
nvfp4_mm_simd_lib  = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matmul_simd_fc.metal"))
nvfp4_mm_simd_r_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matmul_simd_residual_fc.metal"))
nvfp4_mm_simd_v2_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matmul_simd_v2_fc.metal"))
nvfp4_mm_simd_v2_r_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matmul_simd_v2_residual_fc.metal"))
f16_mm_v2_lib   = metal_compile_source(device, read_file(NVFP4_DIR + "f16_matmul_simd_v2_fc.metal"))
f16_mm_v2_r_lib = metal_compile_source(device, read_file(NVFP4_DIR + "f16_matmul_simd_v2_residual_fc.metal"))
f16_mm_v3_lib   = metal_compile_source(device, read_file(NVFP4_DIR + "f16_matmul_simd_v3_fc.metal"))
f16_mm_v4_lib   = metal_compile_source(device, read_file(NVFP4_DIR + "f16_matmul_simd_v4_fc.metal"))
f16_mv_pipe   = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "f16_matvec.metal")), "f16_matvec")
f16_mv_r_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "f16_matvec_residual.metal")), "f16_matvec_residual")
nvfp4_mlx_pipe   = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx.metal")), "nvfp4_matvec_mlx")
nvfp4_mlx_qkv_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_qkv.metal")), "nvfp4_matvec_mlx_qkv")
nvfp4_mlx_gu_pipe  = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_gu.metal")), "nvfp4_matvec_mlx_gu")
# bf16 activation experiments removed — at decode (M=1) the activation
# stays in L1/L2 cache across matvecs, so compressing it doesn't reduce
# DRAM BW. Only weight reads (4-bit nvfp4) actually hit DRAM; KV cache
# attention BW is the only other meaningful win-target (already done via
# sdpa_vector_bf16). See PERFORMANCE.md for the writeup.
nvfp4_mlx_r_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_residual.metal")), "nvfp4_matvec_mlx_residual")
sdpa_pipe = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "shared/sdpa_vector_bf16.metal")), "sdpa_vector_bf16")

# ---- Speculative decode kernels (BATCH=K_DECODE) ----
phn_rope_kc_db_lib = metal_compile_source(device, read_file(KERNEL_DIR + "shared/per_head_norm_rope_to_cache_decode_batch_fc.metal"))
phn_rope_kc_db_pipe = metal_pipeline_with_int_constants(phn_rope_kc_db_lib, "per_head_norm_rope_to_cache_decode_batch_fc", [HEAD_DIM, HEAD_DIM_HALF, N_KV_HEADS, K_DECODE])

v_write_db_lib = metal_compile_source(device, read_file(KERNEL_DIR + "shared/v_write_decode_batch_fc.metal"))
v_write_db_pipe = metal_pipeline_with_int_constants(v_write_db_lib, "v_write_decode_batch_fc", [K_DECODE, KV_ROW])

scores_db_lib = metal_compile_source(device, read_file(KERNEL_DIR + "shared/attn_scores_decode_batch_fc.metal"))
scores_db_pipe = metal_pipeline_with_int_constants(scores_db_lib, "attn_scores_decode_batch_fc", [HEAD_DIM, N_Q_HEADS, N_KV_HEADS, GROUP_SIZE, K_DECODE, MAX_POS])

softmax_db_lib = metal_compile_source(device, read_file(KERNEL_DIR + "shared/attn_softmax_decode_batch_fc.metal"))
softmax_db_pipe = metal_pipeline_with_int_constants(softmax_db_lib, "attn_softmax_decode_batch_fc", [N_Q_HEADS, K_DECODE, MAX_POS])

wsum_db_lib = metal_compile_source(device, read_file(KERNEL_DIR + "shared/attn_weighted_sum_decode_batch_fc.metal"))
wsum_db_pipe = metal_pipeline_with_int_constants(wsum_db_lib, "attn_weighted_sum_decode_batch_fc", [HEAD_DIM, N_Q_HEADS, N_KV_HEADS, GROUP_SIZE, K_DECODE, MAX_POS])

# argmax_batch_fc deferred — using per-token argmax_pipe in forward_decode_batch loop instead

# Specialized matmul pipelines for K=K_DECODE (separate from prefill's BATCH=N_PROMPT)
mvb_q_d   = metal_pipeline_with_int_constants(f16_mm_v4_lib, "f16_matmul_simd_v4_fc", [HIDDEN, N_Q_HEADS * HEAD_DIM, K_DECODE])
mvb_k_d   = metal_pipeline_with_int_constants(f16_mm_v4_lib, "f16_matmul_simd_v4_fc", [HIDDEN, KV_ROW, K_DECODE])
mvb_v_d   = metal_pipeline_with_int_constants(f16_mm_v4_lib, "f16_matmul_simd_v4_fc", [HIDDEN, KV_ROW, K_DECODE])
mvb_o_r_d = metal_pipeline_with_int_constants(f16_mm_v2_r_lib, "f16_matmul_simd_v2_residual_fc", [N_Q_HEADS * HEAD_DIM, HIDDEN, K_DECODE])
mvb_g_d   = metal_pipeline_with_int_constants(f16_mm_v4_lib, "f16_matmul_simd_v4_fc", [HIDDEN, INTERMEDIATE, K_DECODE])
mvb_u_d   = metal_pipeline_with_int_constants(f16_mm_v4_lib, "f16_matmul_simd_v4_fc", [HIDDEN, INTERMEDIATE, K_DECODE])
mvb_d_r_d = metal_pipeline_with_int_constants(f16_mm_v2_r_lib, "f16_matmul_simd_v2_residual_fc", [INTERMEDIATE, HIDDEN, K_DECODE])

# rms_b_pipe_d / phn_rope_b_pipe_d defined later (after rms_b_lib / phn_rope_b_lib are compiled)
dequant_full_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_dequant_full.metal")), "nvfp4_dequant_full")
f32_to_f16_pipe    = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "f32_to_f16.metal")), "f32_to_f16")
nvfp4_emb_b_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_embedding_batch.metal")), "nvfp4_embedding_batch")
copy_slice_pipe  = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "copy_slice_f32.metal")), "copy_slice_f32")

# Per-shape specializations for batch=N_PROMPT
mvb_q   = metal_pipeline_with_int_constants(f16_mm_v4_lib, "f16_matmul_simd_v4_fc",               [HIDDEN, N_Q_HEADS * HEAD_DIM, N_PROMPT])
mvb_k_kv = metal_pipeline_with_int_constants(nvfp4_mvb_kv_lib, "nvfp4_matvec_batch_to_cache_fc",   [HIDDEN, KV_ROW, N_PROMPT])
mvb_v_kv = metal_pipeline_with_int_constants(nvfp4_mvb_kv_lib, "nvfp4_matvec_batch_to_cache_fc",   [HIDDEN, KV_ROW, N_PROMPT])
mvb_k_simd = metal_pipeline_with_int_constants(f16_mm_v4_lib, "f16_matmul_simd_v4_fc",            [HIDDEN, KV_ROW, N_PROMPT])
mvb_v_simd = metal_pipeline_with_int_constants(f16_mm_v4_lib, "f16_matmul_simd_v4_fc",            [HIDDEN, KV_ROW, N_PROMPT])
mvb_o_r = metal_pipeline_with_int_constants(f16_mm_v2_r_lib, "f16_matmul_simd_v2_residual_fc",    [N_Q_HEADS * HEAD_DIM, HIDDEN, N_PROMPT])
mvb_g   = metal_pipeline_with_int_constants(f16_mm_v4_lib, "f16_matmul_simd_v4_fc",               [HIDDEN, INTERMEDIATE, N_PROMPT])
mvb_u   = metal_pipeline_with_int_constants(f16_mm_v4_lib, "f16_matmul_simd_v4_fc",               [HIDDEN, INTERMEDIATE, N_PROMPT])
mvb_d_r = metal_pipeline_with_int_constants(f16_mm_v2_r_lib, "f16_matmul_simd_v2_residual_fc",    [INTERMEDIATE, HIDDEN, N_PROMPT])
# We use the K-side with rope+norm fused via per_head_norm_rope_to_cache_batch_fc, so for K
# we keep a non-cache batched matvec (writes to k_batch_buf), and a separate fused phn-rope-cache.
# But to keep things simple, alternate: matvec K → k_batch, then phn_rope_to_cache_batch reads k_batch and writes cache+rope.
mvb_k = metal_pipeline_with_int_constants(nvfp4_mvb_lib, "nvfp4_matvec_batch_fc", [HIDDEN, KV_ROW, N_PROMPT])

rms_b_lib  = metal_compile_source(device, read_file(KERNEL_DIR + "shared/rms_norm_batch_fc.metal"))
rms_b_pipe = metal_pipeline_with_int_constants(rms_b_lib, "rms_norm_batch_fc", [HIDDEN, N_PROMPT])
rms_b_pipe_d = metal_pipeline_with_int_constants(rms_b_lib, "rms_norm_batch_fc", [HIDDEN, K_DECODE])

phn_rope_b_lib = metal_compile_source(device, read_file(KERNEL_DIR + "shared/per_head_norm_rope_batch_fc.metal"))
phn_rope_b_pipe = metal_pipeline_with_int_constants(phn_rope_b_lib, "per_head_norm_rope_batch_fc", [HEAD_DIM, HEAD_DIM_HALF, N_Q_HEADS, N_PROMPT])
phn_rope_b_pipe_d = metal_pipeline_with_int_constants(phn_rope_b_lib, "per_head_norm_rope_batch_fc", [HEAD_DIM, HEAD_DIM_HALF, N_Q_HEADS, K_DECODE])

phn_rope_kc_b_lib = metal_compile_source(device, read_file(KERNEL_DIR + "shared/per_head_norm_rope_to_cache_batch_fc.metal"))
phn_rope_kc_b_pipe = metal_pipeline_with_int_constants(phn_rope_kc_b_lib, "per_head_norm_rope_to_cache_batch_fc", [HEAD_DIM, HEAD_DIM_HALF, N_KV_HEADS, N_PROMPT])

scores_b_lib  = metal_compile_source(device, read_file(KERNEL_DIR + "shared/attn_scores_prefill_batch_fc.metal"))
scores_b_pipe = metal_pipeline_with_int_constants(scores_b_lib, "attn_scores_prefill_batch_fc", [HEAD_DIM, N_Q_HEADS, N_KV_HEADS, GROUP_SIZE, N_PROMPT])

softmax_b_lib  = metal_compile_source(device, read_file(KERNEL_DIR + "shared/attn_softmax_prefill_batch_fc.metal"))
softmax_b_pipe = metal_pipeline_with_int_constants(softmax_b_lib, "attn_softmax_prefill_batch_fc", [N_Q_HEADS, N_PROMPT])

wsum_b_lib  = metal_compile_source(device, read_file(KERNEL_DIR + "shared/attn_weighted_sum_prefill_batch_fc.metal"))
wsum_b_pipe = metal_pipeline_with_int_constants(wsum_b_lib, "attn_weighted_sum_prefill_batch_fc", [HEAD_DIM, N_Q_HEADS, N_KV_HEADS, GROUP_SIZE, N_PROMPT])

-> upload_f16_as_f32(name)
  desc = st.tensor(name)
  n_floats = desc[:byte_length] / 2
  src_buf = metal_buffer(device, desc[:byte_length])
  dst_buf = metal_buffer(device, n_floats * 4)
  st.upload_bytes(name, src_buf)
  n_buf = metal_buffer(device, 4)
  metal_buffer_write_i32(n_buf, 0, n_floats)
  metal_batch_begin(queue)
  metal_dispatch_n(queue, f16_to_f32_pipe, [src_buf, dst_buf, n_buf], n_floats)
  metal_batch_commit(queue)
  dst_buf

-> upload_nvfp4(name)
  w_desc = st.tensor(name + ".weight")
  s_desc = st.tensor(name + ".scales")
  # Zero-copy: mmap.view_at returns a BigArray over the safetensors file
  # pages; metal_buffer_for wraps the same physical bytes as an MTLBuffer
  # (Apple Silicon unified memory). No upload, no copy when the slice base
  # is page-aligned; falls back to a one-shot newBufferWithBytes: copy when
  # the safetensors offset isn't on a page boundary.
  w_view = st.mmap.view_at(w_desc[:byte_offset], :u8, w_desc[:byte_length])
  s_view = st.mmap.view_at(s_desc[:byte_offset], :u8, s_desc[:byte_length])
  { quants: metal_buffer_for(device, w_view), scales: metal_buffer_for(device, s_view) }

# Pre-dequant an nvfp4 matrix into a f16 buffer at load time.
-> upload_nvfp4_f16(name, k_dim, n_rows)
  pair = upload_nvfp4(name)
  total_floats = n_rows * k_dim
  f16_buf = metal_buffer(device, total_floats * 2)
  kdim_buf2 = metal_buffer(device, 4) ; metal_buffer_write_i32(kdim_buf2, 0, k_dim)
  nrows_buf = metal_buffer(device, 4) ; metal_buffer_write_i32(nrows_buf, 0, n_rows)
  metal_batch_begin(queue)
  metal_dispatch_n(queue, dequant_full_pipe, [pair[:quants], pair[:scales], f16_buf, kdim_buf2, nrows_buf], n_rows * (k_dim / 16))
  metal_batch_commit(queue)
  { quants: pair[:quants], scales: pair[:scales], weights: f16_buf }

<< "uploading model..."
t_load_start = ccall("__w_clock")
embed = upload_nvfp4("model.embed_tokens")
layers = []
li = 0
while li < N_LAYERS
  prefix = "model.layers." + li.to_s + "."
  layers.push({
    attn_norm: upload_f16_as_f32(prefix + "input_layernorm.weight"),
    q_proj:    upload_nvfp4_f16(prefix + "self_attn.q_proj", HIDDEN, N_Q_HEADS * HEAD_DIM),
    k_proj:    upload_nvfp4_f16(prefix + "self_attn.k_proj", HIDDEN, KV_ROW),
    v_proj:    upload_nvfp4_f16(prefix + "self_attn.v_proj", HIDDEN, KV_ROW),
    o_proj:    upload_nvfp4_f16(prefix + "self_attn.o_proj", N_Q_HEADS * HEAD_DIM, HIDDEN),
    q_norm:    upload_f16_as_f32(prefix + "self_attn.q_norm.weight"),
    k_norm:    upload_f16_as_f32(prefix + "self_attn.k_norm.weight"),
    ffn_norm:  upload_f16_as_f32(prefix + "post_attention_layernorm.weight"),
    gate_proj: upload_nvfp4_f16(prefix + "mlp.gate_proj", HIDDEN, INTERMEDIATE),
    up_proj:   upload_nvfp4_f16(prefix + "mlp.up_proj",   HIDDEN, INTERMEDIATE),
    down_proj: upload_nvfp4_f16(prefix + "mlp.down_proj", INTERMEDIATE, HIDDEN),
    k_cache:   metal_buffer(device, MAX_POS * KV_ROW * 2),
    v_cache:   metal_buffer(device, MAX_POS * KV_ROW * 2)
  })
  li = li + 1
out_norm = upload_f16_as_f32("model.norm.weight")
t_load = (ccall("__w_clock") - t_load_start) * ~1000.0
<< "  done in " + t_load.to_s + " ms"

x_buf      = metal_buffer(device, HIDDEN * 4)
xn_buf     = metal_buffer(device, HIDDEN * 4)
q_buf      = metal_buffer(device, N_Q_HEADS * HEAD_DIM * 4)
k_buf      = metal_buffer(device, KV_ROW * 4)
v_buf      = metal_buffer(device, KV_ROW * 4)
# Batched buffers (sized for N_PROMPT)
xb_buf      = metal_buffer(device, N_PROMPT * HIDDEN * 4)
xnb_buf     = metal_buffer(device, N_PROMPT * HIDDEN * 4)
qb_buf      = metal_buffer(device, N_PROMPT * N_Q_HEADS * HEAD_DIM * 4)
kb_buf      = metal_buffer(device, N_PROMPT * KV_ROW * 4)
attn_out_b  = metal_buffer(device, N_PROMPT * N_Q_HEADS * HEAD_DIM * 4)
gate_b      = metal_buffer(device, N_PROMPT * INTERMEDIATE * 4)
up_b        = metal_buffer(device, N_PROMPT * INTERMEDIATE * 4)
h_b         = metal_buffer(device, N_PROMPT * INTERMEDIATE * 4)
scores_b    = metal_buffer(device, N_PROMPT * N_Q_HEADS * N_PROMPT * 4)
cos_b_buf   = metal_buffer(device, N_PROMPT * HEAD_DIM_HALF * 4)
sin_b_buf   = metal_buffer(device, N_PROMPT * HEAD_DIM_HALF * 4)
token_ids_buf = metal_buffer(device, N_PROMPT * 4)
# Speculative-decode buffers (reuse prefill xb_buf/xnb_buf since K_DECODE <= N_PROMPT typically)
scores_db_buf  = metal_buffer(device, K_DECODE * N_Q_HEADS * MAX_POS * 4)
cos_db_buf     = metal_buffer(device, K_DECODE * HEAD_DIM_HALF * 4)
sin_db_buf     = metal_buffer(device, K_DECODE * HEAD_DIM_HALF * 4)
token_ids_d_buf = metal_buffer(device, K_DECODE * 4)
pos_start_buf  = metal_buffer(device, 4)
argmax_d_buf   = metal_buffer(device, K_DECODE * 4)
# Per-token slice offsets for decoding K logits
slice_off_buf  = metal_buffer(device, 4)
xnb_h_buf       = metal_buffer(device, N_PROMPT * HIDDEN * 2)        # half activation for simd matmul (q/k/v/gate/up input)
attn_out_h_buf  = metal_buffer(device, N_PROMPT * HIDDEN * 2)        # half attn output (o_proj input)
h_h_buf         = metal_buffer(device, N_PROMPT * INTERMEDIATE * 2)  # half FFN inner (down input)
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

pos_buf     = metal_buffer(device, 4)
n_pos_buf   = metal_buffer(device, 4)
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

# Build per-position rope tables for a batch of positions [pos_start..pos_start+N_PROMPT-1].
# Layout: cos_b_buf[token * HEAD_DIM_HALF + p], same for sin.
-> build_rope_tables_batch(pos_start)
  t = 0
  while t < N_PROMPT
    pos = pos_start + t
    base = t * HEAD_DIM_HALF
    i = 0
    while i < HEAD_DIM_HALF
      theta = Math.exp(log_base * (~0.0 - i * inv_hd))
      angle = pos * theta
      metal_buffer_write_f32(cos_b_buf, base + i, Math.cos(angle))
      metal_buffer_write_f32(sin_b_buf, base + i, Math.sin(angle))
      i = i + 1
    t = t + 1

# Build cos/sin for K_DECODE positions starting at pos_start.
-> build_rope_tables_decode_batch(pos_start)
  t = 0
  while t < K_DECODE
    pos = pos_start + t
    base = t * HEAD_DIM_HALF
    i = 0
    while i < HEAD_DIM_HALF
      theta = Math.exp(log_base * (~0.0 - i * inv_hd))
      angle = pos * theta
      metal_buffer_write_f32(cos_db_buf, base + i, Math.cos(angle))
      metal_buffer_write_f32(sin_db_buf, base + i, Math.sin(angle))
      i = i + 1
    t = t + 1

-> run_block(lyr, n_pos_active)
  # Scalar literal autobox: HIDDEN/inv_h/EPS pass directly, runtime caches the
  # 1-element constant buffers per (kind, value) — no scalar-buffer ceremony.
  metal_dispatch_groups(queue, rms_pipe, [x_buf, lyr[:attn_norm], xn_buf, HIDDEN, ~1.0 / HIDDEN, EPS], 1, 512)
  metal_batch_barrier(queue)
  # Fused Q/K/V — one dispatch produces all three projections from xn_buf.
  metal_dispatch_groups(queue, nvfp4_mlx_qkv_pipe, [
    lyr[:q_proj][:quants], lyr[:q_proj][:scales],
    lyr[:k_proj][:quants], lyr[:k_proj][:scales],
    lyr[:v_proj][:quants], lyr[:v_proj][:scales],
    xn_buf, q_buf, k_buf, v_buf,
    HIDDEN, (N_Q_HEADS * HEAD_DIM) / 8, KV_ROW / 8
  ], ((N_Q_HEADS * HEAD_DIM) / 8) + (KV_ROW / 8) + (KV_ROW / 8), 64)
  metal_batch_barrier(queue)
  # Fused: per-head norm + rope (Q side, in-place) || per-head norm + rope + kv-cache write (K side) || raw kv-cache write (V side)
  metal_dispatch_groups(queue, phn_rope_pipe, [q_buf, lyr[:q_norm], cos_buf, sin_buf, HEAD_DIM, HEAD_DIM_HALF, INV_HEAD_DIM, EPS], N_Q_HEADS, 32)
  metal_dispatch_groups(queue, phn_rope_kc_pipe, [k_buf, lyr[:k_norm], cos_buf, sin_buf, lyr[:k_cache], HEAD_DIM, HEAD_DIM_HALF, pos_buf, KV_ROW, INV_HEAD_DIM, EPS], N_KV_HEADS, 32)
  metal_dispatch_n(queue, kv_pipe, [v_buf, lyr[:v_cache], pos_buf, KV_ROW], KV_ROW)
  metal_batch_barrier(queue)
  # Fused SDPA: scores+softmax+wsum in one kernel (online softmax, no scratch).
  # 1 TG per Q head, 1024 threads (32 simdgroups × 32 lanes).
  # Reused scalar buffers: GROUP_SIZE=gqa_factor (2), HEAD_DIM=HEAD_DIM (128), KV_ROW=N_KV_HEADS*HEAD_DIM (1024).
  metal_dispatch_groups(queue, sdpa_pipe, [q_buf, lyr[:k_cache], lyr[:v_cache], attn_out, GROUP_SIZE, n_pos_buf, HEAD_DIM, KV_ROW, ATTN_SCALE], N_Q_HEADS, 1024)
  metal_batch_barrier(queue)
  # o_proj fused with residual: writes (matvec(o_proj, attn_out) + x_buf) into x_buf
  metal_dispatch_groups(queue, nvfp4_mlx_r_pipe, [lyr[:o_proj][:quants], lyr[:o_proj][:scales], attn_out, x_buf, KDIM_O], HIDDEN / 8, 64)
  metal_batch_barrier(queue)
  metal_dispatch_groups(queue, rms_pipe, [x_buf, lyr[:ffn_norm], xn_buf, HIDDEN, INV_HIDDEN, EPS], 1, 512)
  metal_batch_barrier(queue)
  # Fused gate/up — one dispatch produces both FFN-input projections from xn_buf.
  metal_dispatch_groups(queue, nvfp4_mlx_gu_pipe, [
    lyr[:gate_proj][:quants], lyr[:gate_proj][:scales],
    lyr[:up_proj][:quants],   lyr[:up_proj][:scales],
    xn_buf, gate_buf, up_buf,
    HIDDEN, INTERMEDIATE / 8
  ], (INTERMEDIATE / 8) * 2, 64)
  metal_batch_barrier(queue)
  metal_dispatch_n(queue, silu_pipe, [gate_buf, up_buf, h_buf, INTERMEDIATE], INTERMEDIATE)
  metal_batch_barrier(queue)
  # down_proj fused with residual: writes (matvec(down, h) + x_buf) into x_buf
  metal_dispatch_groups(queue, nvfp4_mlx_r_pipe, [lyr[:down_proj][:quants], lyr[:down_proj][:scales], h_buf, x_buf, INTERMEDIATE], HIDDEN / 8, 64)
  metal_batch_barrier(queue)

# Batched layer block. Operates on N_PROMPT-batched buffers in-place on xb_buf.
# Writes the K/V cache rows for positions [0..N_PROMPT-1] of this layer.
-> run_block_batch(lyr)
  metal_dispatch_groups(queue, rms_b_pipe, [xb_buf, lyr[:attn_norm], xnb_buf, INV_HIDDEN, EPS], N_PROMPT, 32)
  metal_batch_barrier(queue)
  # f32→f16 of xnb for simd matmul (q uses simd; k/v stay on f32 path)
  metal_dispatch_n(queue, f32_to_f16_pipe, [xnb_buf, xnb_h_buf, N_PROMPT_HIDDEN], N_PROMPT * HIDDEN)
  metal_batch_barrier(queue)
  # q via simd matmul, k/v via batched matvec (k → kb_buf for phn_rope; v → directly into v_cache)
  m_tiles_p = N_PROMPT / 8
  n_tiles_q = (N_Q_HEADS * HEAD_DIM) / 32
  n_q_tiles = m_tiles_p * n_tiles_q
  metal_set_threadgroup_memory(queue, 8 * 16 * 2, 0)
  metal_set_threadgroup_memory(queue, 8 * 8 * 2, 1)
  # q via f16 v2 (pre-dequanted weights — no inner-loop dequant)
  metal_set_threadgroup_memory(queue, 256 * 2, 0)
  metal_dispatch_groups(queue, mvb_q, [lyr[:q_proj][:weights], xnb_h_buf, qb_buf], n_q_tiles, 128)
  # k via f16 v2 (writes f32 to kb_buf for phn_rope_to_cache)
  n_tiles_kv = KV_ROW / 32
  n_kv_tiles = m_tiles_p * n_tiles_kv
  metal_set_threadgroup_memory(queue, 256 * 2, 0)
  metal_dispatch_groups(queue, mvb_k_simd, [lyr[:k_proj][:weights], xnb_h_buf, kb_buf], n_kv_tiles, 128)
  # v via f16 v2 directly into v_cache
  metal_set_threadgroup_memory(queue, 256 * 2, 0)
  metal_dispatch_groups(queue, mvb_v_simd, [lyr[:v_proj][:weights], xnb_h_buf, lyr[:v_cache]], n_kv_tiles, 128)
  metal_batch_barrier(queue)
  # phn+rope on Q (in-place); phn+rope+cache-write on K (kb_buf → k_cache rows 0..N-1)
  metal_dispatch_groups(queue, phn_rope_b_pipe, [qb_buf, lyr[:q_norm], cos_b_buf, sin_b_buf, INV_HEAD_DIM, EPS], N_PROMPT * N_Q_HEADS, 32)
  metal_dispatch_groups(queue, phn_rope_kc_b_pipe, [kb_buf, lyr[:k_norm], cos_b_buf, sin_b_buf, lyr[:k_cache], KV_ROW, INV_HEAD_DIM, EPS], N_PROMPT * N_KV_HEADS, 32)
  metal_batch_barrier(queue)
  # Attention: scores (causal mask in kernel), softmax, weighted sum.
  metal_dispatch_n(queue, scores_b_pipe, [qb_buf, lyr[:k_cache], scores_b, ATTN_SCALE], N_PROMPT * N_Q_HEADS * N_PROMPT)
  metal_batch_barrier(queue)
  metal_dispatch_groups(queue, softmax_b_pipe, [scores_b], N_PROMPT * N_Q_HEADS, 32)
  metal_batch_barrier(queue)
  metal_dispatch_n(queue, wsum_b_pipe, [scores_b, lyr[:v_cache], attn_out_b], N_PROMPT * N_Q_HEADS * HEAD_DIM)
  metal_batch_barrier(queue)
  # f32→f16 of attn_out for simd o_proj
  metal_dispatch_n(queue, f32_to_f16_pipe, [attn_out_b, attn_out_h_buf, N_PROMPT_HIDDEN], N_PROMPT * HIDDEN)
  metal_batch_barrier(queue)
  # o_proj via f16 v2 + residual
  n_tiles_o = HIDDEN / 32
  n_o_tiles = m_tiles_p * n_tiles_o
  metal_set_threadgroup_memory(queue, 256 * 2, 0)
  metal_dispatch_groups(queue, mvb_o_r, [lyr[:o_proj][:weights], attn_out_h_buf, xb_buf], n_o_tiles, 128)
  metal_batch_barrier(queue)
  # FFN
  metal_dispatch_groups(queue, rms_b_pipe, [xb_buf, lyr[:ffn_norm], xnb_buf, INV_HIDDEN, EPS], N_PROMPT, 32)
  metal_batch_barrier(queue)
  # f32→f16 of xnb for gate/up
  metal_dispatch_n(queue, f32_to_f16_pipe, [xnb_buf, xnb_h_buf, N_PROMPT_HIDDEN], N_PROMPT * HIDDEN)
  metal_batch_barrier(queue)
  # gate, up via f16 v2 matmul
  n_tiles_g = INTERMEDIATE / 32
  n_g_tiles = m_tiles_p * n_tiles_g
  metal_set_threadgroup_memory(queue, 256 * 2, 0)
  metal_dispatch_groups(queue, mvb_g, [lyr[:gate_proj][:weights], xnb_h_buf, gate_b], n_g_tiles, 128)
  metal_set_threadgroup_memory(queue, 256 * 2, 0)
  metal_dispatch_groups(queue, mvb_u, [lyr[:up_proj][:weights], xnb_h_buf, up_b], n_g_tiles, 128)
  metal_batch_barrier(queue)
  # silu_mul is element-wise; same kernel works on the batched buffers as one big array.
  metal_dispatch_n(queue, silu_pipe, [gate_b, up_b, h_b, N_PROMPT_INTERMEDIATE], N_PROMPT * INTERMEDIATE)
  metal_batch_barrier(queue)
  # f32→f16 of h for down_proj simd
  metal_dispatch_n(queue, f32_to_f16_pipe, [h_b, h_h_buf, N_PROMPT_INTERMEDIATE], N_PROMPT * INTERMEDIATE)
  metal_batch_barrier(queue)
  # down via f16 v2 + residual
  n_tiles_d = HIDDEN / 32
  n_d_tiles = m_tiles_p * n_tiles_d
  metal_set_threadgroup_memory(queue, 256 * 2, 0)
  metal_dispatch_groups(queue, mvb_d_r, [lyr[:down_proj][:weights], h_h_buf, xb_buf], n_d_tiles, 128)
  metal_batch_barrier(queue)

# Decode-batch layer block. K_DECODE tokens at positions pos_start..pos_start+K_DECODE-1.
# K/V cache rows pos_start..pos_start+K_DECODE-1 get filled. Each token attends to all [0, pos_start+t].
-> run_block_decode_batch(lyr)
  metal_dispatch_groups(queue, rms_b_pipe_d, [xb_buf, lyr[:attn_norm], xnb_buf, INV_HIDDEN, EPS], K_DECODE, 32)
  metal_batch_barrier(queue)
  metal_dispatch_n(queue, f32_to_f16_pipe, [xnb_buf, xnb_h_buf, K_DECODE_HIDDEN], K_DECODE * HIDDEN)
  metal_batch_barrier(queue)
  # q,k,v matmuls (f16, K=K_DECODE batched)
  m_tiles_d = K_DECODE / 8
  metal_set_threadgroup_memory(queue, 256 * 2, 0)
  metal_dispatch_groups(queue, mvb_q_d, [lyr[:q_proj][:weights], xnb_h_buf, qb_buf], m_tiles_d * (N_Q_HEADS * HEAD_DIM / 32), 128)
  metal_set_threadgroup_memory(queue, 256 * 2, 0)
  metal_dispatch_groups(queue, mvb_k_d, [lyr[:k_proj][:weights], xnb_h_buf, kb_buf], m_tiles_d * (KV_ROW / 32), 128)
  # V into a temporary (use up_b as scratch, sized for K_DECODE × KV_ROW). Then v_write_db copies to v_cache.
  metal_set_threadgroup_memory(queue, 256 * 2, 0)
  metal_dispatch_groups(queue, mvb_v_d, [lyr[:v_proj][:weights], xnb_h_buf, up_b], m_tiles_d * (KV_ROW / 32), 128)
  metal_batch_barrier(queue)
  # phn+rope on Q (in-place); phn+rope+cache write on K (kb_buf → k_cache rows pos_start..pos_start+K-1)
  metal_dispatch_groups(queue, phn_rope_b_pipe_d, [qb_buf, lyr[:q_norm], cos_db_buf, sin_db_buf, INV_HEAD_DIM, EPS], K_DECODE * N_Q_HEADS, 32)
  metal_dispatch_groups(queue, phn_rope_kc_db_pipe, [kb_buf, lyr[:k_norm], cos_db_buf, sin_db_buf, lyr[:k_cache], KV_ROW, pos_start_buf, INV_HEAD_DIM, EPS], K_DECODE * N_KV_HEADS, 32)
  # V cache write
  metal_dispatch_n(queue, v_write_db_pipe, [up_b, lyr[:v_cache], pos_start_buf], K_DECODE * KV_ROW)
  metal_batch_barrier(queue)
  # Attention (each token attends to [0, pos_start+t])
  metal_dispatch_n(queue, scores_db_pipe, [qb_buf, lyr[:k_cache], scores_db_buf, pos_start_buf, ATTN_SCALE], K_DECODE * N_Q_HEADS * MAX_POS)
  metal_batch_barrier(queue)
  metal_dispatch_groups(queue, softmax_db_pipe, [scores_db_buf, pos_start_buf], K_DECODE * N_Q_HEADS, 32)
  metal_batch_barrier(queue)
  metal_dispatch_n(queue, wsum_db_pipe, [scores_db_buf, lyr[:v_cache], attn_out_b, pos_start_buf], K_DECODE * N_Q_HEADS * HEAD_DIM)
  metal_batch_barrier(queue)
  # f32→f16 attn_out for o_proj simd
  metal_dispatch_n(queue, f32_to_f16_pipe, [attn_out_b, attn_out_h_buf, K_DECODE_HIDDEN], K_DECODE * HIDDEN)
  metal_batch_barrier(queue)
  metal_set_threadgroup_memory(queue, 256 * 2, 0)
  metal_dispatch_groups(queue, mvb_o_r_d, [lyr[:o_proj][:weights], attn_out_h_buf, xb_buf], m_tiles_d * (HIDDEN / 32), 128)
  metal_batch_barrier(queue)
  # FFN
  metal_dispatch_groups(queue, rms_b_pipe_d, [xb_buf, lyr[:ffn_norm], xnb_buf, INV_HIDDEN, EPS], K_DECODE, 32)
  metal_batch_barrier(queue)
  metal_dispatch_n(queue, f32_to_f16_pipe, [xnb_buf, xnb_h_buf, K_DECODE_HIDDEN], K_DECODE * HIDDEN)
  metal_batch_barrier(queue)
  metal_set_threadgroup_memory(queue, 256 * 2, 0)
  metal_dispatch_groups(queue, mvb_g_d, [lyr[:gate_proj][:weights], xnb_h_buf, gate_b], m_tiles_d * (INTERMEDIATE / 32), 128)
  metal_set_threadgroup_memory(queue, 256 * 2, 0)
  metal_dispatch_groups(queue, mvb_u_d, [lyr[:up_proj][:weights],   xnb_h_buf, up_b],   m_tiles_d * (INTERMEDIATE / 32), 128)
  metal_batch_barrier(queue)
  metal_dispatch_n(queue, silu_pipe, [gate_b, up_b, h_b, K_DECODE_INTERMEDIATE], K_DECODE * INTERMEDIATE)
  metal_batch_barrier(queue)
  metal_dispatch_n(queue, f32_to_f16_pipe, [h_b, h_h_buf, K_DECODE_INTERMEDIATE], K_DECODE * INTERMEDIATE)
  metal_batch_barrier(queue)
  metal_set_threadgroup_memory(queue, 256 * 2, 0)
  metal_dispatch_groups(queue, mvb_d_r_d, [lyr[:down_proj][:weights], h_h_buf, xb_buf], m_tiles_d * (HIDDEN / 32), 128)
  metal_batch_barrier(queue)

# Run K_DECODE candidate tokens at positions pos_start..pos_start+K_DECODE-1.
# Returns array of K_DECODE argmax token IDs (the model's prediction for
# each input position's NEXT token).
-> forward_decode_batch(token_ids, pos_start)
  metal_buffer_write_i32(pos_start_buf, 0, pos_start)
  i = 0
  while i < K_DECODE
    metal_buffer_write_i32(token_ids_d_buf, i, token_ids[i])
    i = i + 1
  build_rope_tables_decode_batch(pos_start)
  metal_batch_begin_concurrent(queue)
  metal_dispatch_n(queue, nvfp4_emb_b_pipe, [embed[:quants], embed[:scales], xb_buf, token_ids_d_buf, HIDDEN, K_DECODE], K_DECODE * HIDDEN / 16)
  metal_batch_barrier(queue)
  li = 0
  while li < N_LAYERS
    run_block_decode_batch(layers[li])
    li = li + 1
  metal_dispatch_groups(queue, rms_b_pipe_d, [xb_buf, out_norm, xnb_buf, INV_HIDDEN, EPS], K_DECODE, 32)
  metal_batch_commit(queue)
  # Now run K lm_heads in separate command buffers and collect.
  results = []
  i = 0
  while i < K_DECODE
    metal_buffer_write_i32(slice_off_buf, 0, i * HIDDEN)
    metal_batch_begin(queue)
    metal_dispatch_n(queue, copy_slice_pipe, [xnb_buf, xn_buf, slice_off_buf, HIDDEN], HIDDEN)
    metal_batch_barrier(queue)
    metal_set_threadgroup_memory(queue, HIDDEN * 4, 0)
    metal_dispatch_groups(queue, nvfp4_matvec_v4_pipe, [embed[:quants], embed[:scales], xn_buf, logits_buf, HIDDEN], N_VOCAB / 32, 1024)
    metal_batch_barrier(queue)
    metal_dispatch_groups(queue, argmax_pipe, [logits_buf, argmax_buf, N_VOCAB], 1, 1024)
    metal_batch_commit(queue)
    results.push(metal_buffer_read_i32(argmax_buf, 0))
    i = i + 1
  results

# Run a batched prefill on N_PROMPT tokens starting at position 0. After this
# returns, the K/V caches are populated for positions [0..N_PROMPT-1] and the
# argmax of the LAST token's logits is returned.
-> forward_prefill(token_ids)
  i = 0
  while i < N_PROMPT
    metal_buffer_write_i32(token_ids_buf, i, token_ids[i])
    i = i + 1
  build_rope_tables_batch(0)
  metal_batch_begin_concurrent(queue)
  # Embed N_PROMPT tokens: dispatch (N_PROMPT * HIDDEN/16) threads.
  metal_dispatch_n(queue, nvfp4_emb_b_pipe, [embed[:quants], embed[:scales], xb_buf, token_ids_buf, HIDDEN, N_PROMPT], N_PROMPT * HIDDEN / 16)
  metal_batch_barrier(queue)
  li = 0
  while li < N_LAYERS
    run_block_batch(layers[li])
    li = li + 1
  # Final norm on LAST token only, then lm_head + argmax single-token style.
  # Slice: last token's hidden state lives at xb_buf[(N_PROMPT-1) * HIDDEN ..].
  # We can run rms_pipe (single-token) but it expects starting at offset 0,
  # so copy LAST token's slice into xn_buf via rms_b_pipe + last-row read.
  # Simpler: run rms_b_pipe on whole batch into xnb_buf (cheap), then do
  # lm_head v4 reading from xnb_buf at the LAST token's offset.
  metal_dispatch_groups(queue, rms_b_pipe, [xb_buf, out_norm, xnb_buf, INV_HIDDEN, EPS], N_PROMPT, 32)
  metal_batch_barrier(queue)
  metal_set_threadgroup_memory(queue, HIDDEN * 4, 0)
  # lm_head v4 reads x from a flat float* — passing the whole xnb_buf is wrong (would read first token).
  # Instead, copy last token slice to xn_buf via a separate dispatch. For now, encode logits over
  # a "view" by using f32_matvec offsets... simpler: do a small dispatch to memcpy slice.
  metal_dispatch_n(queue, copy_slice_pipe, [xnb_buf, xn_buf, LAST_TOKEN_OFFSET, HIDDEN], HIDDEN)
  metal_batch_barrier(queue)
  metal_dispatch_groups(queue, nvfp4_matvec_v4_pipe, [embed[:quants], embed[:scales], xn_buf, logits_buf, HIDDEN], N_VOCAB / 32, 1024)
  metal_batch_barrier(queue)
  metal_dispatch_groups(queue, argmax_pipe, [logits_buf, argmax_buf, N_VOCAB], 1, 1024)
  metal_batch_commit(queue)
  metal_buffer_read_i32(argmax_buf, 0)

# Prompt-Lookup Decoding: search history for [last 2 tokens] occurrence,
# return up to k tokens following the match.
-> pld_propose(history, k)
  result = []
  n = history.size()
  if n < 3
    return result
  needle_a = history[n - 2]
  needle_b = history[n - 1]
  i = 0
  while (i + 1) < (n - 2)
    if history[i] == needle_a
      if history[i + 1] == needle_b
        j = i + 2
        while j < n
          if result.size() >= k
            return result
          result.push(history[j])
          j = j + 1
        return result
    i = i + 1
  result

# Speculative decode loop using PLD. Returns generated history (incl. seed).
# Conditional: if PLD finds no n-gram match, fall back to single-token decode
# instead of running batched-decode with garbage drafts (which guarantees no
# acceptance and wastes the entire K-token round).
-> generate_speculative(seed, n_target)
  generated = []
  i = 0
  while i < seed.size()
    generated.push(seed[i])
    i = i + 1
  total_target = seed.size() + n_target
  rounds_spec = 0
  rounds_fallback = 0
  total_accepted = 0
  while generated.size() < total_target
    drafts = pld_propose(generated, K_DECODE - 1)
    if drafts.size() == 0
      # No n-gram match — single-token decode (cheaper than wasted K-batch)
      last_tok = generated[generated.size() - 1]
      pos = generated.size() - 1
      next_tok = forward_step(last_tok, pos)
      generated.push(next_tok)
      rounds_fallback = rounds_fallback + 1
    else
      # Pad drafts to K-1 in case PLD found fewer than K-1
      while drafts.size() < (K_DECODE - 1)
        drafts.push(0)
      last_tok = generated[generated.size() - 1]
      inputs = [last_tok]
      i = 0
      while i < (K_DECODE - 1)
        inputs.push(drafts[i])
        i = i + 1
      pos_start = generated.size() - 1
      preds = forward_decode_batch(inputs, pos_start)
      generated.push(preds[0])
      if generated.size() < total_target
        i = 0
        keep_going = true
        while keep_going
          if i >= (K_DECODE - 1)
            keep_going = false
          else
            if drafts[i] != preds[i]
              keep_going = false
            else
              generated.push(preds[i + 1])
              total_accepted = total_accepted + 1
              i = i + 1
              if generated.size() >= total_target
                keep_going = false
      rounds_spec = rounds_spec + 1
  { tokens: generated, rounds: rounds_spec, accepted: total_accepted, fallback: rounds_fallback }

PROFILE = true
# Hash to bypass closure-capture scoping (functions create local copies of int/float globals).
PROF = { setup: ~0.0, encode: ~0.0, commit: ~0.0, read: ~0.0, gpu_ms: ~0.0 }

-> forward_step(token_id, pos)
  t0 = ccall("__w_clock")
  metal_buffer_write_i32(pos_buf, 0, pos)
  n_pos_active = pos + 1
  metal_buffer_write_i32(n_pos_buf, 0, n_pos_active)
  metal_buffer_write_i32(token_id_buf, 0, token_id)
  build_rope_tables(pos)
  t1 = ccall("__w_clock")
  metal_batch_begin_concurrent(queue)
  metal_dispatch_n(queue, nvfp4_embed_pipe, [embed[:quants], embed[:scales], x_buf, token_id_buf, HIDDEN], HIDDEN / 16)
  metal_batch_barrier(queue)
  li = 0
  while li < N_LAYERS
    run_block(layers[li], n_pos_active)
    li = li + 1
  metal_dispatch_groups(queue, rms_pipe, [x_buf, out_norm, xn_buf, HIDDEN, INV_HIDDEN, EPS], 1, 512)
  metal_batch_barrier(queue)
  metal_set_threadgroup_memory(queue, HIDDEN * 4, 0)
  metal_dispatch_groups(queue, nvfp4_matvec_v4_pipe, [embed[:quants], embed[:scales], xn_buf, logits_buf, HIDDEN], N_VOCAB / 32, 1024)
  metal_batch_barrier(queue)
  metal_dispatch_groups(queue, argmax_pipe, [logits_buf, argmax_buf, N_VOCAB], 1, 1024)
  t2 = ccall("__w_clock")
  if PROFILE
    gpu_ms = metal_batch_commit_ms(queue, pos)
    PROF[:gpu_ms] = PROF[:gpu_ms] + gpu_ms
  else
    metal_batch_commit(queue)
  t3 = ccall("__w_clock")
  r = metal_buffer_read_i32(argmax_buf, 0)
  t4 = ccall("__w_clock")
  if PROFILE
    PROF[:setup]  = PROF[:setup]  + (t1 - t0)
    PROF[:encode] = PROF[:encode] + (t2 - t1)
    PROF[:commit] = PROF[:commit] + (t3 - t2)
    PROF[:read]   = PROF[:read]   + (t4 - t3)
  r

SEED_IDS = [785, 6722, 315, 9625, 374]
PROMPT_IDS = []
i = 0
while i < N_PROMPT
  PROMPT_IDS.push(SEED_IDS[i % SEED_IDS.size()])
  i = i + 1

<< ""
# f16 KV cache test: use single-token forward_step for prefill (same kernels
# as decode → cache writes match decode reads). Skips the batched-prefill
# code path which hasn't been converted to f16 cache writes yet.
<< "single-token prefill, " + PROMPT_IDS.size().to_s + " prompt tokens..."
t_pre_start = ccall("__w_clock")
last = -1
pos = 0
i = 0
while i < PROMPT_IDS.size()
  last = forward_step(PROMPT_IDS[i], pos)
  pos = pos + 1
  i = i + 1
t_pre = (ccall("__w_clock") - t_pre_start) * ~1000.0
<< "prefill: " + PROMPT_IDS.size().to_s + " in " + t_pre.to_s + " ms (" + (t_pre / PROMPT_IDS.size()).to_s + " ms/token, " + ((PROMPT_IDS.size() * ~1000.0) / t_pre).to_s + " tok/s)"

<< ""
<< "generating " + N_GENERATE.to_s + " tokens..."
# Optional Metal Frame Capture: set CAPTURE_TRACE=true to record one decode
# token to a .gputrace file. Open the file in Xcode → Frame Debugger → GPU
# Counters for per-kernel ALU / memory-stall / occupancy stats.
# Requires METAL_CAPTURE_ENABLED=1 in env when launched outside Xcode.
CAPTURE_TRACE = ccall("__w_env", "CAPTURE_TRACE") != nil
if CAPTURE_TRACE
  metal_capture_begin(device, "/tmp/bench_lightning.gputrace")
  forward_step(last, pos)
  metal_capture_end
  << "wrote /tmp/bench_lightning.gputrace — open in Xcode for per-kernel counters"
t_gen_start = ccall("__w_clock")
generated_ids = []
generated_ids.push(last)
i = 1
while i < N_GENERATE
  last = forward_step(last, pos)
  generated_ids.push(last)
  pos = pos + 1
  i = i + 1
t_gen = (ccall("__w_clock") - t_gen_start) * ~1000.0
<< "decode: " + N_GENERATE.to_s + " tokens in " + t_gen.to_s + " ms (" + (t_gen / N_GENERATE).to_s + " ms/token, " + ((N_GENERATE * ~1000.0) / t_gen).to_s + " tok/s)"
if PROFILE
  total_steps = PROMPT_IDS.size() + N_GENERATE
  factor = ~1000000.0 / total_steps
  << "profile (per token avg, us): setup=" + (PROF[:setup] * factor).to_s + " encode=" + (PROF[:encode] * factor).to_s + " commit=" + (PROF[:commit] * factor).to_s + " read=" + (PROF[:read] * factor).to_s
  gpu_us = (PROF[:gpu_ms] * ~1000.0) / total_steps
  << "profile gpu time (per token avg, us): " + gpu_us.to_s
<< ""
<< "first 8 generated ids: " + generated_ids[0..7].to_s

# Speculative decode bench DISABLED in f16 KV-cache test mode — the PLD
# decode-batch kernels still write f32 cache, would corrupt the f16 cache.
# Re-enable after porting decode_batch attn + cache writers to half.

st.close
