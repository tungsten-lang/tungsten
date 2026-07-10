# P5.3 first cut: load qwen3 lm_head (output.weight, Q8_0 [2048, 151936]),
# upload to GPU, dispatch the cooperative Q8 matvec on a hardcoded x
# vector, print top-5 logits.
#
# Doesn't yet implement proper token embedding (that needs a Q8 dequant
# kernel for one row). Hand-picks x = all 1.0 — proves the GPU pipeline
# from GGUF mmap → Metal buffers → kernel dispatch → readback works
# end-to-end on real model weights.

use core/metal
use tungsten-llama/gguf
use tungsten-llama/tensor
use tungsten-llama/q8_matvec_coop

GGUF_PATH = "/Users/erik/.ollama/models/blobs/sha256-ae354763fe478c790125fb993e59bb1266655b3fa721eebe4a931660c3ed2ce9"

g = GGUF.new(GGUF_PATH)

# lm_head: Q8_0 [2048, 151936] — 311M Q8 quants in 9.7M blocks, ~330 MB on disk.
lm_desc = g.tensor("output.weight")
lm = Tensor.new(g, lm_desc)

n_rows = 151936    # vocab size
k_cols = 2048      # hidden size
nb = k_cols / 32   # blocks per row

<< "uploading lm_head to GPU..."
device = metal_device()
t0 = clock
parts = lm.upload_q8(device)
upload_ms = (clock - t0) * ~1000.0
<< "  upload took " + upload_ms.to_s + "ms"

<< "parts keys: " + parts.keys().to_s
w_q = parts[:quants]   # i8 quants buffer, n_rows * k_cols bytes
w_s = parts[:scales]   # f16 scales buffer, n_rows * nb * 2 bytes
<< "w_q nil? " + (w_q == nil).to_s
<< "w_s nil? " + (w_s == nil).to_s
<< "k_cols=" + k_cols.to_s + " k_cols*4=" + (k_cols*4).to_s
# Hardcoded input vector x = all 1.0.
x_buf = metal_buffer(device, k_cols * 4)
<< "x_buf allocated"
i = 0
while i < k_cols
  metal_buffer_write_f32(x_buf, i, ~1.0)
  i = i + 1
<< "x filled"

y_buf = metal_buffer(device, n_rows * 4)
<< "y allocated, n_rows=" + n_rows.to_s
k_buf = metal_buffer(device, 4)
<< "k allocated"
metal_buffer_write_i32(k_buf, 0, k_cols)
<< "k written"

<< "building MSL..."
# Compile the cooperative Q8 matvec kernel.
msl_src = StringBuffer(2048)
msl_src << "// Q8_0 cooperative matvec — same as bits/.../q8_matvec_coop.w generated.\n"
msl_src << "#include <metal_stdlib>\n"
msl_src << "using namespace metal;\n"
msl_src << "kernel void q8_matvec_coop(\n"
msl_src << "  device int *w_q \[\[buffer(0)\]\],\n"
msl_src << "  device half *w_s \[\[buffer(1)\]\],\n"
msl_src << "  device float *x \[\[buffer(2)\]\],\n"
msl_src << "  device float *y \[\[buffer(3)\]\],\n"
msl_src << "  constant int &k_dim \[\[buffer(4)\]\],\n"
msl_src << "  uint __tg_id \[\[threadgroup_position_in_grid\]\],\n"
msl_src << "  uint __simd_lane \[\[thread_index_in_simdgroup\]\]\n"
msl_src << ") {\n"
msl_src << "  int m = int(__tg_id);\n"
msl_src << "  int lane = int(__simd_lane);\n"
msl_src << "  int nb = k_dim / 32;\n"
msl_src << "  int ints_per_row = k_dim / 4;\n"
msl_src << "  float partial = 0.0f;\n"
msl_src << "  for (int b = lane; b < nb; b += 32) {\n"
msl_src << "    half s = w_s\[m * nb + b\];\n"
msl_src << "    float ba = 0.0f;\n"
msl_src << "    int row_off = m * ints_per_row + b * 8;\n"
msl_src << "    int x_off = b * 32;\n"
msl_src << "    for (int i = 0; i < 8; i++) {\n"
msl_src << "      int p = w_q\[row_off + i\];\n"
msl_src << "      ba += ((p << 24) >> 24) * x\[x_off + i*4 + 0\]\n"
msl_src << "          + ((p << 16) >> 24) * x\[x_off + i*4 + 1\]\n"
msl_src << "          + ((p <<  8) >> 24) * x\[x_off + i*4 + 2\]\n"
msl_src << "          + ( p        >> 24) * x\[x_off + i*4 + 3\];\n"
msl_src << "    }\n"
msl_src << "    partial += s * ba;\n"
msl_src << "  }\n"
msl_src << "  partial = simd_sum(partial);\n"
msl_src << "  if (lane == 0) y\[m\] = partial;\n"
msl_src << "}\n"
msl = msl_src.to_s()

<< "MSL string built, length=" + msl.size.to_s
<< "compiling MSL..."
library = metal_compile_source(device, msl)
<< "compiled, getting pipeline..."
pipeline = metal_pipeline(library, "q8_matvec_coop")
<< "got pipeline"
queue = metal_queue(device)
<< "got queue"
bufs = [w_q, w_s, x_buf, y_buf, k_buf]
<< "bufs built, n_rows=" + n_rows.to_s

# Warmup
i = 0
while i < 3
  metal_dispatch_groups(queue, pipeline, bufs, n_rows, 32)
  i = i + 1

<< "dispatching lm_head matvec ([2048, 151936] @ [2048])..."
t0 = clock
metal_dispatch_groups(queue, pipeline, bufs, n_rows, 32)
dispatch_ms = (clock - t0) * ~1000.0
<< "  dispatch took " + dispatch_ms.to_s + "ms"

# Find argmax of y. Linear scan — 151936 reads.
best_id = 0
best_val = metal_buffer_read_f32(y_buf, 0)
i = 1
while i < n_rows
  v = metal_buffer_read_f32(y_buf, i)
  if v > best_val
    best_val = v
    best_id = i
  i = i + 1

<< "argmax token id = " + best_id.to_s + "  logit = " + best_val.to_s
<< "(this is meaningless linguistically since x = all 1.0,"
<< " but proves end-to-end: GGUF mmap → split → upload → dispatch → readback)"

g.close
