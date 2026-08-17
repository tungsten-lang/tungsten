# Qwen3.8/27B non-QMV component profiler.
#
# Measures the exact Tungsten Metal kernels and production dimensions used by
# qwen38_mlx.w. QMV/dequant is covered separately by autotune_qwen38.w; this
# isolates normalization, recurrent state, KV/cache attention, activations,
# embeddings, and vocabulary selection for target widths 1..3.

use core/metal

SHARED_DIR = "bits/tungsten-llama/lib/kernels/shared/"
QWEN_DIR = "bits/tungsten-llama/lib/kernels/qwen3_6/"

HIDDEN = 5120
N_VOCAB = 248320
FFN = 17408
HK = 16
HV = 48
DK = 128
DV = 128
Q_DIM = HK * DK
V_DIM = HV * DV
QKV_DIM = Q_DIM + Q_DIM + V_DIM
N_HEADS = 24
N_KV_HEADS = 4
HEAD_DIM = 256
GQA = N_HEADS / N_KV_HEADS
KV_DIM = N_KV_HEADS * HEAD_DIM
ATTN_DIM = N_HEADS * HEAD_DIM
MAX_POS = 128
EPS = ~0.000001
ATTN_SCALE = ~1.0 / Math.sqrt(~0.0 + HEAD_DIM)
WARMUP_ITERS = 20
MEASURE_ITERS = 50

device = metal_device()
queue = metal_queue(device)

rms_lib = metal_compile_source(device, read_file(SHARED_DIR + "rms_norm.metal"))
rms_pipe = metal_pipeline(rms_lib, "rms_norm")
rms_batch_lib = metal_compile_source(device, read_file(SHARED_DIR + "rms_norm_batch_fc.metal"))
rms_pair_pipe = metal_pipeline_with_int_constants(rms_batch_lib, "rms_norm_batch_fc", [HIDDEN, 2])
rms_triplet_pipe = metal_pipeline_with_int_constants(rms_batch_lib, "rms_norm_batch_fc", [HIDDEN, 3])
rms_generic_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "rms_norm_batch.metal")), "rms_norm_batch")
phn_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "per_head_norm.metal")), "per_head_norm")
kv_write_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "kv_write.metal")), "kv_write")
silu_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "silu_mul.metal")), "silu_mul")
argmax_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "argmax.metal")), "argmax")
argmax_batch_lib = metal_compile_source(device, read_file(SHARED_DIR + "argmax_batch_fc.metal"))
argmax_pair_pipe = metal_pipeline_with_int_constants(argmax_batch_lib, "argmax_batch_fc", [N_VOCAB, 2])
argmax_triplet_pipe = metal_pipeline_with_int_constants(argmax_batch_lib, "argmax_batch_fc", [N_VOCAB, 3])
argmax_parallel_lib = metal_compile_source(device, read_file(SHARED_DIR + "argmax_two_stage.metal"))
argmax_stage1_pipe = metal_pipeline(argmax_parallel_lib, "argmax_stage1")
argmax_stage2_pipe = metal_pipeline(argmax_parallel_lib, "argmax_stage2")
embed_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "bf16_embedding_lookup.metal")), "bf16_embedding_lookup")
bf16_matvec_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "bf16_matvec.metal")), "bf16_matvec")

conv_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "conv1d_depthwise_step.metal")), "conv1d_depthwise_step")
delta_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "gated_delta_step.metal")), "gated_delta_step")
rng_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "rms_norm_gated.metal")), "rms_norm_gated")
g_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "compute_g.metal")), "compute_g")
sigmoid_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "sigmoid_inplace.metal")), "sigmoid_f32")
gate_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "attn_output_gate.metal")), "attn_output_gate")
sdpa_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "sdpa_decode_hd256.metal")), "sdpa_decode_hd256")

pair_lib = metal_compile_source(device, read_file(QWEN_DIR + "decode_pair.metal"))
embed_pair_pipe = metal_pipeline(pair_lib, "bf16_embedding_lookup_pair")
bf16_pair_pipe = metal_pipeline(pair_lib, "bf16_matvec_pair")
kv_pair_pipe = metal_pipeline(pair_lib, "kv_write_pair")
sdpa_pair_pipe = metal_pipeline(pair_lib, "sdpa_decode_pair_hd256")
conv_pair_pipe = metal_pipeline(pair_lib, "conv1d_depthwise_pair")
delta_pair_pipe = metal_pipeline(pair_lib, "gated_delta_pair")

triplet_lib = metal_compile_source(device, read_file(QWEN_DIR + "decode_triplet.metal"))
embed_triplet_pipe = metal_pipeline(triplet_lib, "bf16_embedding_lookup_triplet")
bf16_triplet_pipe = metal_pipeline(triplet_lib, "bf16_matvec_triplet")
kv_triplet_pipe = metal_pipeline(triplet_lib, "kv_write_triplet")
sdpa_triplet_pipe = metal_pipeline(triplet_lib, "sdpa_decode_triplet_hd256")
conv_triplet_pipe = metal_pipeline(triplet_lib, "conv1d_depthwise_triplet")
delta_triplet_pipe = metal_pipeline(triplet_lib, "gated_delta_triplet")

# Shared synthetic storage; numeric values are deliberately bounded so every
# kernel executes normally without NaNs. Timing does not depend on real weights.
x = metal_buffer(device, 3 * FFN * 4)
w_hidden = metal_buffer(device, HIDDEN * 4)
rms_out = metal_buffer(device, 3 * HIDDEN * 4)
i = 0
while i < 3 * FFN
  metal_buffer_write_f32(x, i, Math.sin(i * ~0.0013) * ~0.1)
  i = i + 1
i = 0
while i < HIDDEN
  metal_buffer_write_f32(w_hidden, i, ~1.0)
  i = i + 1

conv_w = metal_buffer(device, 4 * QKV_DIM * 4)
conv_state = metal_buffer(device, 3 * QKV_DIM * 4)
conv_mid = metal_buffer(device, 3 * QKV_DIM * 4)
conv_mid2 = metal_buffer(device, 3 * QKV_DIM * 4)
conv_out_state = metal_buffer(device, 3 * QKV_DIM * 4)
conv_out = metal_buffer(device, 3 * QKV_DIM * 4)

q = metal_buffer(device, 3 * Q_DIM * 4)
k = metal_buffer(device, 3 * Q_DIM * 4)
v = metal_buffer(device, 3 * V_DIM * 4)
g = metal_buffer(device, 3 * HV * 4)
beta = metal_buffer(device, 3 * HV * 4)
delta_state = metal_buffer(device, HV * DV * DK * 4)
delta_mid = metal_buffer(device, HV * DV * DK * 4)
delta_mid2 = metal_buffer(device, HV * DV * DK * 4)
delta_out_state = metal_buffer(device, HV * DV * DK * 4)
delta_out = metal_buffer(device, 3 * V_DIM * 4)
rng_w = metal_buffer(device, DV * 4)
rng_out = metal_buffer(device, 3 * V_DIM * 4)

queries = metal_buffer(device, 3 * ATTN_DIM * 4)
k_now = metal_buffer(device, 3 * KV_DIM * 4)
v_now = metal_buffer(device, 3 * KV_DIM * 4)
k_cache = metal_buffer(device, MAX_POS * KV_DIM * 4)
v_cache = metal_buffer(device, MAX_POS * KV_DIM * 4)
attn_out = metal_buffer(device, 3 * ATTN_DIM * 4)

logits = metal_buffer(device, 3 * N_VOCAB * 4)
argmax_out = metal_buffer(device, 3 * 4)
n_vocab_buf = metal_buffer(device, 4)
metal_buffer_write_i32(n_vocab_buf, 0, N_VOCAB)
argmax_chunks = (N_VOCAB + 1023) / 1024
argmax_partial_values = metal_buffer(device, 3 * argmax_chunks * 4)
argmax_partial_indices = metal_buffer(device, 3 * argmax_chunks * 4)

# Three tiny embedding rows are sufficient because token_ids are 0..2.
embed_w = metal_buffer(device, 3 * HIDDEN * 2)
bf16_w = metal_buffer(device, HV * HIDDEN * 2)
bf16_out = metal_buffer(device, 3 * HV * 4)
token_ids = metal_buffer(device, 3 * 4)
metal_buffer_write_i32(token_ids, 0, 0)
metal_buffer_write_i32(token_ids, 1, 1)
metal_buffer_write_i32(token_ids, 2, 2)

-> one_sample(enqueue)
  metal_batch_begin(queue)
  i = 0
  while i < WARMUP_ITERS
    enqueue.call()
    i = i + 1
  metal_batch_commit(queue)
  metal_batch_begin(queue)
  i = 0
  while i < MEASURE_ITERS
    enqueue.call()
    i = i + 1
  ms = metal_batch_commit_ms(queue, 0)
  (ms / MEASURE_ITERS) * ~1000.0

-> median3(a, b, c)
  lo = a
  if b < lo then lo = b
  if c < lo then lo = c
  hi = a
  if b > hi then hi = b
  if c > hi then hi = c
  a + b + c - lo - hi

-> bench(label, enqueue)
  us = median3(one_sample(enqueue), one_sample(enqueue), one_sample(enqueue))
  << label + "=" + us.to_s + " us"

<< "Qwen3.8/27B non-QMV Metal components (median 3x" + MEASURE_ITERS.to_s + ")"

bench("rms width1", -> () metal_dispatch_groups(queue, rms_pipe, [x, w_hidden, rms_out, HIDDEN, ~1.0 / HIDDEN, EPS], 1, 256))
bench("rms width2", -> () metal_dispatch_groups(queue, rms_pair_pipe, [x, w_hidden, rms_out, ~1.0 / HIDDEN, EPS], 2, 32))
bench("rms width3", -> () metal_dispatch_groups(queue, rms_triplet_pipe, [x, w_hidden, rms_out, ~1.0 / HIDDEN, EPS], 3, 32))
rms_tgs = [32, 64, 128, 256, 512]
rms_batch = 1
while rms_batch <= 3
  rt = 0
  while rt < rms_tgs.size()
    rms_tg = rms_tgs[rt]
    bench("rms generic width" + rms_batch.to_s + " tg" + rms_tg.to_s,
      -> () metal_dispatch_groups(queue, rms_generic_pipe,
        [x, w_hidden, rms_out, HIDDEN, rms_batch, ~1.0 / HIDDEN, EPS],
        rms_batch, rms_tg))
    rt = rt + 1
  rms_batch = rms_batch + 1

bench("mamba conv width1", -> () metal_dispatch_n(queue, conv_pipe, [conv_w, conv_state, x, conv_out, conv_out_state, QKV_DIM, QKV_DIM], QKV_DIM))
bench("mamba conv width2", -> () metal_dispatch_n(queue, conv_pair_pipe, [conv_w, conv_state, x, conv_out, conv_mid, conv_out_state, QKV_DIM], QKV_DIM))
bench("mamba conv width3", -> () metal_dispatch_n(queue, conv_triplet_pipe, [conv_w, conv_state, x, conv_out, conv_mid, conv_mid2, conv_out_state, QKV_DIM], QKV_DIM))

bench("gated-delta width1", -> () metal_dispatch_3d(queue, delta_pipe, [q, k, v, g, beta, delta_state, delta_out, delta_out_state, HK, HV, DK, DV], 1, DV / 4, HV, 32, 4, 1))
bench("gated-delta width2", -> () metal_dispatch_3d(queue, delta_pair_pipe, [q, k, v, g, beta, delta_state, delta_out, delta_mid, delta_out_state, HK, HV, DK, DV], 1, DV / 4, HV, 32, 4, 1))
bench("gated-delta width3", -> () metal_dispatch_3d(queue, delta_triplet_pipe, [q, k, v, g, beta, delta_state, delta_out, delta_mid, delta_mid2, delta_out_state, HK, HV, DK, DV], 1, DV / 4, HV, 32, 4, 1))

bench("mamba norm+gate width1", -> () metal_dispatch_groups(queue, rng_pipe, [delta_out, x, rng_w, rng_out, DV, EPS], HV, 32))
bench("mamba norm+gate width2", -> () metal_dispatch_groups(queue, rng_pipe, [delta_out, x, rng_w, rng_out, DV, EPS], 2 * HV, 32))
bench("mamba norm+gate width3", -> () metal_dispatch_groups(queue, rng_pipe, [delta_out, x, rng_w, rng_out, DV, EPS], 3 * HV, 32))
g_beta_enqueue = -> ()
  metal_dispatch_n(queue, g_pipe, [g, g, beta, g, HV, HV], HV)
  metal_dispatch_n(queue, sigmoid_pipe, [beta, beta, HV], HV)
bench("mamba g+beta elementwise width1", g_beta_enqueue)

kv_single_enqueue = -> ()
  metal_dispatch_n(queue, kv_write_pipe, [k_now, k_cache, 64, KV_DIM], KV_DIM)
  metal_dispatch_n(queue, kv_write_pipe, [v_now, v_cache, 64, KV_DIM], KV_DIM)
bench("KV write width1", kv_single_enqueue)
bench("KV write width2", -> () metal_dispatch_n(queue, kv_pair_pipe, [k_now, v_now, k_cache, v_cache, 64, KV_DIM], 2 * KV_DIM))
bench("KV write width3", -> () metal_dispatch_n(queue, kv_triplet_pipe, [k_now, v_now, k_cache, v_cache, 64, KV_DIM], 3 * KV_DIM))

contexts = [5, 64, 126]
ci = 0
while ci < contexts.size()
  pos = contexts[ci]
  bench("SDPA ctx" + pos.to_s + " width1", -> () metal_dispatch_groups(queue, sdpa_pipe, [queries, k_cache, v_cache, attn_out, GQA, pos, HEAD_DIM, KV_DIM, ATTN_SCALE], N_HEADS, 256))
  bench("SDPA ctx" + pos.to_s + " width2", -> () metal_dispatch_groups(queue, sdpa_pair_pipe, [queries, k_cache, v_cache, attn_out, GQA, pos, N_HEADS, KV_DIM, ATTN_SCALE], 2 * N_HEADS, 256))
  bench("SDPA ctx" + pos.to_s + " width3", -> () metal_dispatch_groups(queue, sdpa_triplet_pipe, [queries, k_cache, v_cache, attn_out, GQA, pos, N_HEADS, KV_DIM, ATTN_SCALE], 3 * N_HEADS, 256))
  ci = ci + 1

bench("SiLU-mul width1", -> () metal_dispatch_n(queue, silu_pipe, [x, x, x, FFN], FFN))
bench("SiLU-mul width2", -> () metal_dispatch_n(queue, silu_pipe, [x, x, x, 2 * FFN], 2 * FFN))
bench("SiLU-mul width3", -> () metal_dispatch_n(queue, silu_pipe, [x, x, x, 3 * FFN], 3 * FFN))
bench("attention output gate width1", -> () metal_dispatch_n(queue, gate_pipe, [attn_out, queries, ATTN_DIM], ATTN_DIM))

bench("embedding width1", -> () metal_dispatch_n(queue, embed_pipe, [embed_w, rms_out, 0, HIDDEN], HIDDEN))
bench("embedding width2", -> () metal_dispatch_n(queue, embed_pair_pipe, [embed_w, rms_out, token_ids, HIDDEN], 2 * HIDDEN))
bench("embedding width3", -> () metal_dispatch_n(queue, embed_triplet_pipe, [embed_w, rms_out, token_ids, HIDDEN], 3 * HIDDEN))
bench("bf16 matvec 5120x48 width1", -> () metal_dispatch_groups(queue, bf16_matvec_pipe, [bf16_w, x, bf16_out, HIDDEN], HV, 32))
bench("bf16 matvec 5120x48 width2", -> () metal_dispatch_groups(queue, bf16_pair_pipe, [bf16_w, x, bf16_out, HIDDEN, HV], HV, 32))
bench("bf16 matvec 5120x48 width3", -> () metal_dispatch_groups(queue, bf16_triplet_pipe, [bf16_w, x, bf16_out, HIDDEN, HV], HV, 32))

bench("argmax width1", -> () metal_dispatch_groups(queue, argmax_pipe, [logits, argmax_out, n_vocab_buf], 1, 32))
bench("argmax width2", -> () metal_dispatch_groups(queue, argmax_pair_pipe, [logits, argmax_out], 2, 32))
bench("argmax width3", -> () metal_dispatch_groups(queue, argmax_triplet_pipe, [logits, argmax_out], 3, 32))
parallel_argmax1 = -> ()
  metal_dispatch_groups(queue, argmax_stage1_pipe,
    [logits, argmax_partial_values, argmax_partial_indices,
     N_VOCAB, argmax_chunks, 1], argmax_chunks, 256)
  metal_dispatch_groups(queue, argmax_stage2_pipe,
    [argmax_partial_values, argmax_partial_indices, argmax_out,
     argmax_chunks, 1], 1, 256)
parallel_argmax2 = -> ()
  metal_dispatch_groups(queue, argmax_stage1_pipe,
    [logits, argmax_partial_values, argmax_partial_indices,
     N_VOCAB, argmax_chunks, 2], 2 * argmax_chunks, 256)
  metal_dispatch_groups(queue, argmax_stage2_pipe,
    [argmax_partial_values, argmax_partial_indices, argmax_out,
     argmax_chunks, 2], 2, 256)
parallel_argmax3 = -> ()
  metal_dispatch_groups(queue, argmax_stage1_pipe,
    [logits, argmax_partial_values, argmax_partial_indices,
     N_VOCAB, argmax_chunks, 3], 3 * argmax_chunks, 256)
  metal_dispatch_groups(queue, argmax_stage2_pipe,
    [argmax_partial_values, argmax_partial_indices, argmax_out,
     argmax_chunks, 3], 3, 256)

# Exactness checks: negative values, a tied maximum (lowest index wins), and
# independent maxima in all three rows.
metal_buffer_write_f32(logits, 10, ~3.0)
metal_buffer_write_f32(logits, N_VOCAB - 1, ~3.0)
metal_buffer_write_f32(logits, N_VOCAB + 12345, ~4.0)
metal_buffer_write_f32(logits, 2 * N_VOCAB + 777, ~5.0)
metal_batch_begin(queue)
parallel_argmax3.call()
metal_batch_commit(queue)
if metal_buffer_read_i32(argmax_out, 0) != 10
  raise "parallel argmax validation failed for row 0"
if metal_buffer_read_i32(argmax_out, 1) != 12345
  raise "parallel argmax validation failed for row 1"
if metal_buffer_read_i32(argmax_out, 2) != 777
  raise "parallel argmax validation failed for row 2"
bench("argmax parallel width1", parallel_argmax1)
bench("argmax parallel width2", parallel_argmax2)
bench("argmax parallel width3", parallel_argmax3)

<< "component profile done"
