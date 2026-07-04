## Lightning-1.7B nvfp4 long-prefill bench using Metal 4 matmul2d.
##
## Demonstrates the matmul2d (cooperative tensor) speedup at long prompts
## by routing the four big matmul shapes (q/o/gate/up/down + k/v) through
## the M4 path while using existing simdgroup kernels for everything else.
##
## Usage:
##   N_PROMPT=512 ./scripts/bench/bench_lightning_long_prefill.wc
##   N_PROMPT=1024 USE_M4=1 ./scripts/bench/bench_lightning_long_prefill.wc
##   USE_M4=0 ./scripts/bench/bench_lightning_long_prefill.wc   # baseline (simdgroup)
##
## N_PROMPT must be a multiple of 64 (matmul2d M-tile = 64). USE_M4 defaults to 1.

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

# CLI overrides via env.
N_PROMPT = 512
n_prompt_env = ccall("__w_env", "N_PROMPT")
if n_prompt_env != nil
  N_PROMPT = n_prompt_env.to_i
USE_M4 = true
use_m4_env = ccall("__w_env", "USE_M4")
if use_m4_env != nil
  if use_m4_env == "0"
    USE_M4 = false

# matmul2d M-tile is 64 rows; round-up of N_PROMPT must be a multiple of 64.
if (N_PROMPT % 64) != 0
  << "warning: N_PROMPT=" + N_PROMPT.to_s + " is not a multiple of 64; rounding up"
  N_PROMPT = ((N_PROMPT + 63) / 64) * 64
MAX_POS = N_PROMPT
INV_HIDDEN   = ~1.0 / HIDDEN
INV_HEAD_DIM = ~1.0 / HEAD_DIM
ATTN_SCALE   = ~1.0 / Math.sqrt(~0.0 + HEAD_DIM)
N_PROMPT_HIDDEN       = N_PROMPT * HIDDEN
N_PROMPT_INTERMEDIATE = N_PROMPT * INTERMEDIATE

device   = metal_device()
queue    = metal_queue(device)
m4_comp  = metal4_compiler(device)
m4_queue = metal4_queue(device)
m4_alloc = metal4_allocator(device)

<< "Lightning long-prefill bench  N_PROMPT=" + N_PROMPT.to_s + "  USE_M4=" + USE_M4.to_s
<< "loading Lightning-1.7B safetensors..."
st = Safetensors.new(LIGHTNING_PATH)

# ---- Pipelines (host-side) ----
f16_to_f32_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "f16_to_f32.metal")), "f16_to_f32")
f32_to_f16_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "f32_to_f16.metal")), "f32_to_f16")
nvfp4_emb_b_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_embedding_batch.metal")), "nvfp4_embedding_batch")
dequant_full_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_dequant_full.metal")), "nvfp4_dequant_full")
nvfp4_matvec_v4_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_v4.metal")), "nvfp4_matvec_v4")
copy_slice_pipe  = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "copy_slice_f32.metal")), "copy_slice_f32")
argmax_pipe = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "shared/argmax.metal")), "argmax")
silu_pipe   = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "shared/silu_mul.metal")), "silu_mul")
add_pipe    = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "shared/residual_add.metal")), "residual_add")

# Batched FC pipelines (BATCH_FC = N_PROMPT).
rms_b_lib  = metal_compile_source(device, read_file(KERNEL_DIR + "shared/rms_norm_batch_fc.metal"))
rms_b_pipe = metal_pipeline_with_int_constants(rms_b_lib, "rms_norm_batch_fc", [HIDDEN, N_PROMPT])

phn_rope_b_lib  = metal_compile_source(device, read_file(KERNEL_DIR + "shared/per_head_norm_rope_batch_fc.metal"))
phn_rope_b_pipe = metal_pipeline_with_int_constants(phn_rope_b_lib, "per_head_norm_rope_batch_fc", [HEAD_DIM, HEAD_DIM_HALF, N_Q_HEADS, N_PROMPT])

phn_rope_kc_b_lib  = metal_compile_source(device, read_file(KERNEL_DIR + "shared/per_head_norm_rope_to_cache_batch_bf16_fc.metal"))
phn_rope_kc_b_pipe = metal_pipeline_with_int_constants(phn_rope_kc_b_lib, "per_head_norm_rope_to_cache_batch_bf16_fc", [HEAD_DIM, HEAD_DIM_HALF, N_KV_HEADS, N_PROMPT])

v_write_b_lib  = metal_compile_source(device, read_file(KERNEL_DIR + "shared/v_write_batch_bf16_fc.metal"))
v_write_b_pipe = metal_pipeline_with_int_constants(v_write_b_lib, "v_write_batch_bf16_fc", [N_PROMPT, KV_ROW])

scores_b_lib  = metal_compile_source(device, read_file(KERNEL_DIR + "shared/attn_scores_prefill_batch_bf16_fc.metal"))
scores_b_pipe = metal_pipeline_with_int_constants(scores_b_lib, "attn_scores_prefill_batch_bf16_fc", [HEAD_DIM, N_Q_HEADS, N_KV_HEADS, GROUP_SIZE, N_PROMPT])

softmax_b_lib  = metal_compile_source(device, read_file(KERNEL_DIR + "shared/attn_softmax_prefill_batch_fc.metal"))
softmax_b_pipe = metal_pipeline_with_int_constants(softmax_b_lib, "attn_softmax_prefill_batch_fc", [N_Q_HEADS, N_PROMPT])

wsum_b_lib  = metal_compile_source(device, read_file(KERNEL_DIR + "shared/attn_weighted_sum_prefill_batch_bf16_fc.metal"))
wsum_b_pipe = metal_pipeline_with_int_constants(wsum_b_lib, "attn_weighted_sum_prefill_batch_bf16_fc", [HEAD_DIM, N_Q_HEADS, N_KV_HEADS, GROUP_SIZE, N_PROMPT])

# Simdgroup matmul (baseline) — same shapes as bench_lightning.w.
f16_mm_v4_lib   = metal_compile_source(device, read_file(NVFP4_DIR + "f16_matmul_simd_v4_fc.metal"))
f16_mm_v2_r_lib = metal_compile_source(device, read_file(NVFP4_DIR + "f16_matmul_simd_v2_residual_fc.metal"))
mvb_q_simd  = metal_pipeline_with_int_constants(f16_mm_v4_lib, "f16_matmul_simd_v4_fc", [HIDDEN, N_Q_HEADS * HEAD_DIM, N_PROMPT])
mvb_k_simd  = metal_pipeline_with_int_constants(f16_mm_v4_lib, "f16_matmul_simd_v4_fc", [HIDDEN, KV_ROW, N_PROMPT])
mvb_v_simd  = metal_pipeline_with_int_constants(f16_mm_v4_lib, "f16_matmul_simd_v4_fc", [HIDDEN, KV_ROW, N_PROMPT])
mvb_o_r_simd = metal_pipeline_with_int_constants(f16_mm_v2_r_lib, "f16_matmul_simd_v2_residual_fc", [N_Q_HEADS * HEAD_DIM, HIDDEN, N_PROMPT])
mvb_g_simd  = metal_pipeline_with_int_constants(f16_mm_v4_lib, "f16_matmul_simd_v4_fc", [HIDDEN, INTERMEDIATE, N_PROMPT])
mvb_u_simd  = metal_pipeline_with_int_constants(f16_mm_v4_lib, "f16_matmul_simd_v4_fc", [HIDDEN, INTERMEDIATE, N_PROMPT])
mvb_d_r_simd = metal_pipeline_with_int_constants(f16_mm_v2_r_lib, "f16_matmul_simd_v2_residual_fc", [INTERMEDIATE, HIDDEN, N_PROMPT])

# Metal 4 matmul2d pipelines (cooperative tensors).
f16_mm_m4_lib    = metal_compile_source(device, read_file(KERNEL_DIR + "f16_matmul_m4.metal"))
f16_mm_m4_pipe   = metal4_pipeline(m4_comp, f16_mm_m4_lib, "f16_matmul_m4", 128, 1, 1)
f16_mm_m4_r_lib  = metal_compile_source(device, read_file(KERNEL_DIR + "f16_matmul_m4_residual.metal"))
f16_mm_m4_r_pipe = metal4_pipeline(m4_comp, f16_mm_m4_r_lib, "f16_matmul_m4_residual", 128, 1, 1)

# ---- Weight loaders ----
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
  w_view = st.mmap.view_at(w_desc[:byte_offset], :u8, w_desc[:byte_length])
  s_view = st.mmap.view_at(s_desc[:byte_offset], :u8, s_desc[:byte_length])
  { quants: metal_buffer_for(device, w_view), scales: metal_buffer_for(device, s_view) }

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

# ---- Per-pass buffers (sized for N_PROMPT) ----
xb_buf      = metal_buffer(device, N_PROMPT * HIDDEN * 4)
xnb_buf     = metal_buffer(device, N_PROMPT * HIDDEN * 4)
xnb_h_buf   = metal_buffer(device, N_PROMPT * HIDDEN * 2)
qb_buf      = metal_buffer(device, N_PROMPT * N_Q_HEADS * HEAD_DIM * 4)
kb_buf      = metal_buffer(device, N_PROMPT * KV_ROW * 4)
vb_buf      = metal_buffer(device, N_PROMPT * KV_ROW * 4)
attn_out_b  = metal_buffer(device, N_PROMPT * N_Q_HEADS * HEAD_DIM * 4)
attn_out_h_buf = metal_buffer(device, N_PROMPT * HIDDEN * 2)
gate_b      = metal_buffer(device, N_PROMPT * INTERMEDIATE * 4)
up_b        = metal_buffer(device, N_PROMPT * INTERMEDIATE * 4)
h_b         = metal_buffer(device, N_PROMPT * INTERMEDIATE * 4)
h_h_buf     = metal_buffer(device, N_PROMPT * INTERMEDIATE * 2)
scores_b    = metal_buffer(device, N_PROMPT * N_Q_HEADS * N_PROMPT * 4)
cos_b_buf   = metal_buffer(device, N_PROMPT * HEAD_DIM_HALF * 4)
sin_b_buf   = metal_buffer(device, N_PROMPT * HEAD_DIM_HALF * 4)
token_ids_buf = metal_buffer(device, N_PROMPT * 4)

xn_buf      = metal_buffer(device, HIDDEN * 4)
logits_buf  = metal_buffer(device, N_VOCAB * 4)
argmax_buf  = metal_buffer(device, 4)
slice_off_buf = metal_buffer(device, 4)

log_base = Math.log(BASE)
inv_hd   = ~2.0 / HEAD_DIM

-> build_rope_tables_batch
  t = 0
  while t < N_PROMPT
    base = t * HEAD_DIM_HALF
    i = 0
    while i < HEAD_DIM_HALF
      theta = Math.exp(log_base * (~0.0 - i * inv_hd))
      angle = t * theta
      metal_buffer_write_f32(cos_b_buf, base + i, Math.cos(angle))
      metal_buffer_write_f32(sin_b_buf, base + i, Math.sin(angle))
      i = i + 1
    t = t + 1

# Per-layer activation tensors (rebuilt per call — N_PROMPT = M is fixed across run).
xnb_h_tensor   = metal_tensor_2d(xnb_h_buf, METAL_DTYPE_FLOAT16, N_PROMPT, HIDDEN, 0, 0)
qb_tensor      = metal_tensor_2d(qb_buf,    METAL_DTYPE_FLOAT32, N_PROMPT, N_Q_HEADS * HEAD_DIM, 0, 0)
kb_tensor      = metal_tensor_2d(kb_buf,    METAL_DTYPE_FLOAT32, N_PROMPT, KV_ROW, 0, 0)
vb_tensor      = metal_tensor_2d(vb_buf,    METAL_DTYPE_FLOAT32, N_PROMPT, KV_ROW, 0, 0)
attn_out_h_tensor = metal_tensor_2d(attn_out_h_buf, METAL_DTYPE_FLOAT16, N_PROMPT, HIDDEN, 0, 0)
xb_tensor      = metal_tensor_2d(xb_buf,    METAL_DTYPE_FLOAT32, N_PROMPT, HIDDEN, 0, 0)
gate_tensor    = metal_tensor_2d(gate_b,    METAL_DTYPE_FLOAT32, N_PROMPT, INTERMEDIATE, 0, 0)
up_tensor      = metal_tensor_2d(up_b,      METAL_DTYPE_FLOAT32, N_PROMPT, INTERMEDIATE, 0, 0)
h_h_tensor     = metal_tensor_2d(h_h_buf,   METAL_DTYPE_FLOAT16, N_PROMPT, INTERMEDIATE, 0, 0)

# Per-layer weight tensors built lazily (they reuse the same f16 buffer).
-> tensor_for_weights(buf, n_rows, k_dim)
  metal_tensor_2d(buf, METAL_DTYPE_FLOAT16, n_rows, k_dim, 0, 0)

# Single argtable, rebound per dispatch. Apple's MTL4ArgumentTable is
# designed for reuse; pre-building many argtables at once exposes a
# runtime bug (slot bindings on a later argtable seem to invalidate the
# same slot on earlier ones). Rebinding per dispatch is fast enough —
# setAddress / setResource are just CPU-side stores into the table.
m4_at = metal4_argtable(device, 3)

# Pre-build per-layer M4 weight tensors. Tensors share underlying buffers.
m4_layer = []
li = 0
while li < N_LAYERS
  ly = layers[li]
  q_t = tensor_for_weights(ly[:q_proj][:weights],   N_Q_HEADS * HEAD_DIM, HIDDEN)
  k_t = tensor_for_weights(ly[:k_proj][:weights],   KV_ROW,               HIDDEN)
  v_t = tensor_for_weights(ly[:v_proj][:weights],   KV_ROW,               HIDDEN)
  o_t = tensor_for_weights(ly[:o_proj][:weights],   HIDDEN,               N_Q_HEADS * HEAD_DIM)
  g_t = tensor_for_weights(ly[:gate_proj][:weights], INTERMEDIATE,        HIDDEN)
  u_t = tensor_for_weights(ly[:up_proj][:weights],   INTERMEDIATE,        HIDDEN)
  d_t = tensor_for_weights(ly[:down_proj][:weights], HIDDEN,              INTERMEDIATE)
  m4_layer.push({
    q_t: q_t, k_t: k_t, v_t: v_t, o_t: o_t, g_t: g_t, u_t: u_t, d_t: d_t,
    res_q: [ly[:q_proj][:weights], xnb_h_buf, qb_buf],
    res_k: [ly[:k_proj][:weights], xnb_h_buf, kb_buf],
    res_v: [ly[:v_proj][:weights], xnb_h_buf, vb_buf],
    res_o: [ly[:o_proj][:weights], attn_out_h_buf, xb_buf],
    res_g: [ly[:gate_proj][:weights], xnb_h_buf, gate_b],
    res_u: [ly[:up_proj][:weights], xnb_h_buf, up_b],
    res_d: [ly[:down_proj][:weights], h_h_buf, xb_buf]
  })
  li = li + 1

# M-tile dispatch grids for matmul2d.
TG_M       = N_PROMPT / 64
TG_N_QHEAD = (N_Q_HEADS * HEAD_DIM) / 32
TG_N_KV    = KV_ROW / 32
TG_N_HID   = HIDDEN / 32
TG_N_INT   = INTERMEDIATE / 32

# m_tile for the simd matmul path (M=N_PROMPT, M-tile=8).
M_TILES_SIMD = N_PROMPT / 8

-> bind_at(a_t, b_t, c_t)
  metal4_argtable_set_tensor(m4_at, 0, a_t)
  metal4_argtable_set_tensor(m4_at, 1, b_t)
  metal4_argtable_set_tensor(m4_at, 2, c_t)

-> matmul_q_m4(lyr_m4)
  bind_at(xnb_h_tensor, lyr_m4[:q_t], qb_tensor)
  metal4_dispatch_groups_3d(m4_queue, m4_alloc, f16_mm_m4_pipe, m4_at, lyr_m4[:res_q], 0, TG_M, TG_N_QHEAD, 1, 128, 1, 1)
-> matmul_k_m4(lyr_m4)
  bind_at(xnb_h_tensor, lyr_m4[:k_t], kb_tensor)
  metal4_dispatch_groups_3d(m4_queue, m4_alloc, f16_mm_m4_pipe, m4_at, lyr_m4[:res_k], 0, TG_M, TG_N_KV, 1, 128, 1, 1)
-> matmul_v_m4(lyr_m4)
  bind_at(xnb_h_tensor, lyr_m4[:v_t], vb_tensor)
  metal4_dispatch_groups_3d(m4_queue, m4_alloc, f16_mm_m4_pipe, m4_at, lyr_m4[:res_v], 0, TG_M, TG_N_KV, 1, 128, 1, 1)
-> matmul_o_m4_residual(lyr_m4)
  bind_at(attn_out_h_tensor, lyr_m4[:o_t], xb_tensor)
  metal4_dispatch_groups_3d(m4_queue, m4_alloc, f16_mm_m4_r_pipe, m4_at, lyr_m4[:res_o], 0, TG_M, TG_N_HID, 1, 128, 1, 1)
-> matmul_g_m4(lyr_m4)
  bind_at(xnb_h_tensor, lyr_m4[:g_t], gate_tensor)
  metal4_dispatch_groups_3d(m4_queue, m4_alloc, f16_mm_m4_pipe, m4_at, lyr_m4[:res_g], 0, TG_M, TG_N_INT, 1, 128, 1, 1)
-> matmul_u_m4(lyr_m4)
  bind_at(xnb_h_tensor, lyr_m4[:u_t], up_tensor)
  metal4_dispatch_groups_3d(m4_queue, m4_alloc, f16_mm_m4_pipe, m4_at, lyr_m4[:res_u], 0, TG_M, TG_N_INT, 1, 128, 1, 1)
-> matmul_d_m4_residual(lyr_m4)
  bind_at(h_h_tensor, lyr_m4[:d_t], xb_tensor)
  metal4_dispatch_groups_3d(m4_queue, m4_alloc, f16_mm_m4_r_pipe, m4_at, lyr_m4[:res_d], 0, TG_M, TG_N_HID, 1, 128, 1, 1)

-> run_block_m4(lyr, lyr_m4)
  metal_batch_begin(queue)
  metal_dispatch_groups(queue, rms_b_pipe, [xb_buf, lyr[:attn_norm], xnb_buf, INV_HIDDEN, EPS], N_PROMPT, 32)
  metal_batch_barrier(queue)
  metal_dispatch_n(queue, f32_to_f16_pipe, [xnb_buf, xnb_h_buf, N_PROMPT_HIDDEN], N_PROMPT * HIDDEN)
  metal_batch_commit(queue)
  matmul_q_m4(lyr_m4)
  matmul_k_m4(lyr_m4)
  matmul_v_m4(lyr_m4)
  metal_batch_begin(queue)
  metal_dispatch_groups(queue, phn_rope_b_pipe, [qb_buf, lyr[:q_norm], cos_b_buf, sin_b_buf, INV_HEAD_DIM, EPS], N_PROMPT * N_Q_HEADS, 32)
  metal_dispatch_groups(queue, phn_rope_kc_b_pipe, [kb_buf, lyr[:k_norm], cos_b_buf, sin_b_buf, lyr[:k_cache], KV_ROW, INV_HEAD_DIM, EPS], N_PROMPT * N_KV_HEADS, 32)
  metal_dispatch_n(queue, v_write_b_pipe, [vb_buf, lyr[:v_cache]], N_PROMPT * KV_ROW)
  metal_batch_barrier(queue)
  metal_dispatch_n(queue, scores_b_pipe, [qb_buf, lyr[:k_cache], scores_b, ATTN_SCALE], N_PROMPT * N_Q_HEADS * N_PROMPT)
  metal_batch_barrier(queue)
  metal_dispatch_groups(queue, softmax_b_pipe, [scores_b], N_PROMPT * N_Q_HEADS, 32)
  metal_batch_barrier(queue)
  metal_dispatch_n(queue, wsum_b_pipe, [scores_b, lyr[:v_cache], attn_out_b], N_PROMPT * N_Q_HEADS * HEAD_DIM)
  metal_batch_barrier(queue)
  metal_dispatch_n(queue, f32_to_f16_pipe, [attn_out_b, attn_out_h_buf, N_PROMPT_HIDDEN], N_PROMPT * HIDDEN)
  metal_batch_commit(queue)
  matmul_o_m4_residual(lyr_m4)
  metal_batch_begin(queue)
  metal_dispatch_groups(queue, rms_b_pipe, [xb_buf, lyr[:ffn_norm], xnb_buf, INV_HIDDEN, EPS], N_PROMPT, 32)
  metal_batch_barrier(queue)
  metal_dispatch_n(queue, f32_to_f16_pipe, [xnb_buf, xnb_h_buf, N_PROMPT_HIDDEN], N_PROMPT * HIDDEN)
  metal_batch_commit(queue)
  matmul_g_m4(lyr_m4)
  matmul_u_m4(lyr_m4)
  metal_batch_begin(queue)
  metal_dispatch_n(queue, silu_pipe, [gate_b, up_b, h_b, N_PROMPT_INTERMEDIATE], N_PROMPT * INTERMEDIATE)
  metal_batch_barrier(queue)
  metal_dispatch_n(queue, f32_to_f16_pipe, [h_b, h_h_buf, N_PROMPT_INTERMEDIATE], N_PROMPT * INTERMEDIATE)
  metal_batch_commit(queue)
  matmul_d_m4_residual(lyr_m4)

-> run_block_simd(lyr)
  metal_batch_begin(queue)
  metal_dispatch_groups(queue, rms_b_pipe, [xb_buf, lyr[:attn_norm], xnb_buf, INV_HIDDEN, EPS], N_PROMPT, 32)
  metal_batch_barrier(queue)
  metal_dispatch_n(queue, f32_to_f16_pipe, [xnb_buf, xnb_h_buf, N_PROMPT_HIDDEN], N_PROMPT * HIDDEN)
  metal_batch_barrier(queue)
  metal_set_threadgroup_memory(queue, 256 * 2, 0)
  metal_dispatch_groups(queue, mvb_q_simd, [lyr[:q_proj][:weights], xnb_h_buf, qb_buf], M_TILES_SIMD * TG_N_QHEAD, 128)
  metal_set_threadgroup_memory(queue, 256 * 2, 0)
  metal_dispatch_groups(queue, mvb_k_simd, [lyr[:k_proj][:weights], xnb_h_buf, kb_buf], M_TILES_SIMD * TG_N_KV, 128)
  metal_set_threadgroup_memory(queue, 256 * 2, 0)
  metal_dispatch_groups(queue, mvb_v_simd, [lyr[:v_proj][:weights], xnb_h_buf, vb_buf], M_TILES_SIMD * TG_N_KV, 128)
  metal_batch_barrier(queue)
  metal_dispatch_groups(queue, phn_rope_b_pipe, [qb_buf, lyr[:q_norm], cos_b_buf, sin_b_buf, INV_HEAD_DIM, EPS], N_PROMPT * N_Q_HEADS, 32)
  metal_dispatch_groups(queue, phn_rope_kc_b_pipe, [kb_buf, lyr[:k_norm], cos_b_buf, sin_b_buf, lyr[:k_cache], KV_ROW, INV_HEAD_DIM, EPS], N_PROMPT * N_KV_HEADS, 32)
  metal_dispatch_n(queue, v_write_b_pipe, [vb_buf, lyr[:v_cache]], N_PROMPT * KV_ROW)
  metal_batch_barrier(queue)
  metal_dispatch_n(queue, scores_b_pipe, [qb_buf, lyr[:k_cache], scores_b, ATTN_SCALE], N_PROMPT * N_Q_HEADS * N_PROMPT)
  metal_batch_barrier(queue)
  metal_dispatch_groups(queue, softmax_b_pipe, [scores_b], N_PROMPT * N_Q_HEADS, 32)
  metal_batch_barrier(queue)
  metal_dispatch_n(queue, wsum_b_pipe, [scores_b, lyr[:v_cache], attn_out_b], N_PROMPT * N_Q_HEADS * HEAD_DIM)
  metal_batch_barrier(queue)
  metal_dispatch_n(queue, f32_to_f16_pipe, [attn_out_b, attn_out_h_buf, N_PROMPT_HIDDEN], N_PROMPT * HIDDEN)
  metal_batch_barrier(queue)
  metal_set_threadgroup_memory(queue, 256 * 2, 0)
  metal_dispatch_groups(queue, mvb_o_r_simd, [lyr[:o_proj][:weights], attn_out_h_buf, xb_buf], M_TILES_SIMD * TG_N_HID, 128)
  metal_batch_barrier(queue)
  metal_dispatch_groups(queue, rms_b_pipe, [xb_buf, lyr[:ffn_norm], xnb_buf, INV_HIDDEN, EPS], N_PROMPT, 32)
  metal_batch_barrier(queue)
  metal_dispatch_n(queue, f32_to_f16_pipe, [xnb_buf, xnb_h_buf, N_PROMPT_HIDDEN], N_PROMPT * HIDDEN)
  metal_batch_barrier(queue)
  metal_set_threadgroup_memory(queue, 256 * 2, 0)
  metal_dispatch_groups(queue, mvb_g_simd, [lyr[:gate_proj][:weights], xnb_h_buf, gate_b], M_TILES_SIMD * TG_N_INT, 128)
  metal_set_threadgroup_memory(queue, 256 * 2, 0)
  metal_dispatch_groups(queue, mvb_u_simd, [lyr[:up_proj][:weights], xnb_h_buf, up_b], M_TILES_SIMD * TG_N_INT, 128)
  metal_batch_barrier(queue)
  metal_dispatch_n(queue, silu_pipe, [gate_b, up_b, h_b, N_PROMPT_INTERMEDIATE], N_PROMPT * INTERMEDIATE)
  metal_batch_barrier(queue)
  metal_dispatch_n(queue, f32_to_f16_pipe, [h_b, h_h_buf, N_PROMPT_INTERMEDIATE], N_PROMPT * INTERMEDIATE)
  metal_batch_barrier(queue)
  metal_set_threadgroup_memory(queue, 256 * 2, 0)
  metal_dispatch_groups(queue, mvb_d_r_simd, [lyr[:down_proj][:weights], h_h_buf, xb_buf], M_TILES_SIMD * TG_N_HID, 128)
  metal_batch_commit(queue)

-> forward_prefill_m4(token_ids)
  i = 0
  while i < N_PROMPT
    metal_buffer_write_i32(token_ids_buf, i, token_ids[i])
    i = i + 1
  build_rope_tables_batch
  metal_batch_begin(queue)
  metal_dispatch_n(queue, nvfp4_emb_b_pipe, [embed[:quants], embed[:scales], xb_buf, token_ids_buf, HIDDEN, N_PROMPT], N_PROMPT * HIDDEN / 16)
  metal_batch_commit(queue)
  li = 0
  while li < N_LAYERS
    if USE_M4
      run_block_m4(layers[li], m4_layer[li])
    else
      run_block_simd(layers[li])
    li = li + 1
  metal_batch_begin(queue)
  metal_dispatch_groups(queue, rms_b_pipe, [xb_buf, out_norm, xnb_buf, INV_HIDDEN, EPS], N_PROMPT, 32)
  metal_batch_barrier(queue)
  metal_dispatch_n(queue, copy_slice_pipe, [xnb_buf, xn_buf, (N_PROMPT - 1) * HIDDEN, HIDDEN], HIDDEN)
  metal_batch_barrier(queue)
  metal_set_threadgroup_memory(queue, HIDDEN * 4, 0)
  metal_dispatch_groups(queue, nvfp4_matvec_v4_pipe, [embed[:quants], embed[:scales], xn_buf, logits_buf, HIDDEN], N_VOCAB / 32, 1024)
  metal_batch_barrier(queue)
  metal_dispatch_groups(queue, argmax_pipe, [logits_buf, argmax_buf, N_VOCAB], 1, 1024)
  metal_batch_commit(queue)
  metal_buffer_read_i32(argmax_buf, 0)

# ---- Build seed prompt ----
SEED_IDS = [785, 6722, 315, 9625, 374]
PROMPT_IDS = []
i = 0
while i < N_PROMPT
  PROMPT_IDS.push(SEED_IDS[i % SEED_IDS.size()])
  i = i + 1

<< ""
<< "warming up..."
warm = forward_prefill_m4(PROMPT_IDS)
<< "  warmup argmax token id = " + warm.to_s

<< ""
<< "running prefill bench (5 trials)..."
best_ms = ~1.0e18
trial = 0
while trial < 5
  t0 = ccall("__w_clock")
  pred = forward_prefill_m4(PROMPT_IDS)
  elapsed = (ccall("__w_clock") - t0) * ~1000.0
  if elapsed < best_ms
    best_ms = elapsed
  trial = trial + 1
toks_per_s = (N_PROMPT.to_f * ~1000.0) / best_ms
ms_per_tok = best_ms / N_PROMPT.to_f
<< "prefill: N=" + N_PROMPT.to_s + "  best=" + best_ms.to_s + " ms  (" + ms_per_tok.to_s + " ms/tok, " + toks_per_s.to_s + " tok/s)"
<< "  argmax token id = " + pred.to_s

st.close
