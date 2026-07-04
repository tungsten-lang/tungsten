# P5.3 second cut: real token embedding lookup.
# Dequantize token_embd[token_id] into x, then run lm_head matvec.
# The argmax isn't yet meaningful (no transformer layers in between)
# but proves token embedding lookup works on real qwen3 weights.

use core/metal
use tungsten-llama/gguf
use tungsten-llama/tensor

GGUF_PATH = "/Users/erik/.ollama/models/blobs/sha256-ae354763fe478c790125fb993e59bb1266655b3fa721eebe4a931660c3ed2ce9"

g = GGUF.new(GGUF_PATH)

# Load token_embd (Q8_0 [2048, 151936]) — 151936 vectors of 2048 f32s,
# stored as Q8_0 (64 blocks per vector, 34 bytes per block, 2176 bytes
# per token).
embd_desc = g.tensor("token_embd.weight")
embd = Tensor.new(g, embd_desc)

n_rows = 151936    # vocab
k_cols = 2048      # hidden
nb = k_cols / 32   # 64 blocks per embedding row

device = metal_device()

# Allocate x_buf for one embedding (2048 f32 = 8 KB).
x_buf = metal_buffer(device, k_cols * 4)

# Pick a token id arbitrarily — token 1234 is just one of the 151936
# vocab entries. Verify dequant produces non-zero plausible f32s.
TOKEN_ID = 1234

# Byte offset in token_embd's data region: TOKEN_ID * 64 blocks * 34 bytes/block.
src_off_in_data = TOKEN_ID * nb * 34
src_off_abs = embd.file_offset + src_off_in_data

<< "dequanting token_embd\[" + TOKEN_ID.to_s + "\] into x_buf..."
metal_q8_dequant_row(x_buf, 0, g.mmap, src_off_abs, nb)

# Spot-check the first 8 values — should be small floats, not all zero.
i = 0
non_zero = 0
sum_sq = ~0.0
while i < k_cols
  v = metal_buffer_read_f32(x_buf, i)
  if v != ~0.0
    non_zero = non_zero + 1
  sum_sq = sum_sq + v * v
  i = i + 1

<< "  non-zero values: " + non_zero.to_s + " / " + k_cols.to_s
<< "  L2 norm² = " + sum_sq.to_s
i = 0
preview = StringBuffer(128)
preview << "  first 8: "
while i < 8
  if i > 0
    preview << " "
  preview << metal_buffer_read_f32(x_buf, i).to_s
  i = i + 1
<< preview.to_s

if non_zero < (k_cols / 2)
  << "FAIL: too many zeros, dequant probably broken"
  exit 1

<< "embedding decoded; running lm_head matvec on it..."

# lm_head matvec: y[151936] = output.weight[2048, 151936] @ x[2048].
lm_desc = g.tensor("output.weight")
lm = Tensor.new(g, lm_desc)
lm_parts = lm.upload_q8(device)
w_q = lm_parts[:quants]
w_s = lm_parts[:scales]

y_buf = metal_buffer(device, n_rows * 4)
k_buf = metal_buffer(device, 4)
metal_buffer_write_i32(k_buf, 0, k_cols)

# Build the cooperative MSL kernel inline.
msl = StringBuffer(2048)
msl << "#include <metal_stdlib>\nusing namespace metal;\n"
msl << "kernel void k(\n"
msl << "  device int *w_q \[\[buffer(0)\]\],\n"
msl << "  device half *w_s \[\[buffer(1)\]\],\n"
msl << "  device float *x \[\[buffer(2)\]\],\n"
msl << "  device float *y \[\[buffer(3)\]\],\n"
msl << "  constant int &k_dim \[\[buffer(4)\]\],\n"
msl << "  uint __tg_id \[\[threadgroup_position_in_grid\]\],\n"
msl << "  uint __simd_lane \[\[thread_index_in_simdgroup\]\]\n"
msl << ") {\n"
msl << "  int m = int(__tg_id); int lane = int(__simd_lane);\n"
msl << "  int nb = k_dim/32, ipr = k_dim/4;\n"
msl << "  float partial = 0.0f;\n"
msl << "  for (int b = lane; b < nb; b += 32) {\n"
msl << "    half s = w_s\[m*nb+b\];\n"
msl << "    float ba = 0.0f;\n"
msl << "    int row_off = m*ipr + b*8, x_off = b*32;\n"
msl << "    for (int i = 0; i < 8; i++) {\n"
msl << "      int p = w_q\[row_off+i\];\n"
msl << "      ba += ((p<<24)>>24)*x\[x_off+i*4\] + ((p<<16)>>24)*x\[x_off+i*4+1\] + ((p<<8)>>24)*x\[x_off+i*4+2\] + (p>>24)*x\[x_off+i*4+3\];\n"
msl << "    }\n"
msl << "    partial += s * ba;\n"
msl << "  }\n"
msl << "  partial = simd_sum(partial);\n"
msl << "  if (lane == 0) y\[m\] = partial;\n"
msl << "}\n"

library = metal_compile_source(device, msl.to_s())
pipeline = metal_pipeline(library, "k")
queue = metal_queue(device)
bufs = [w_q, w_s, x_buf, y_buf, k_buf]

# Warmup + dispatch
i = 0
while i < 3
  metal_dispatch_groups(queue, pipeline, bufs, n_rows, 32)
  i = i + 1
metal_dispatch_groups(queue, pipeline, bufs, n_rows, 32)

# Argmax over 151936 logits.
best_id = 0
best_val = metal_buffer_read_f32(y_buf, 0)
i = 1
while i < n_rows
  v = metal_buffer_read_f32(y_buf, i)
  if v > best_val
    best_val = v
    best_id = i
  i = i + 1
<< "lm_head argmax for token_embd\[" + TOKEN_ID.to_s + "\]: token " + best_id.to_s + " (logit " + best_val.to_s + ")"
<< "(no transformer layers, so this isn't 'next token prediction' — but proves embed→lm_head)"

g.close
