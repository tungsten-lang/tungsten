# microGPT single-fused-kernel GPU bench.
# One Metal dispatch per token, autoregressive char-by-char.
# The whole forward pass (3 RMSNorms, QKV proj, attn, output proj, MLP, lm_head,
# softmax, multinomial sample) runs in one kernel within a single threadgroup.

use core/metal
use core/file

WEIGHTS_PATH = "bits/tungsten-llama/lib/models/microgpt/weights_fp32.bin"
MGPT_TOTAL = 4192
MGPT_BLOCK = 16
MGPT_EMBD  = 16
MGPT_BOS   = 26

device = metal_device()
queue  = metal_queue(device)

# Compile fused kernel.
src = read_file("bits/tungsten-llama/lib/kernels/microgpt_fused.metal")
lib  = metal_compile_source(device, src)
pipe = metal_pipeline(lib, "microgpt_fused")

# Load weights into a Metal buffer.
mm = File.mmap(WEIGHTS_PATH)
src_view = mm.view_at(0, 32, MGPT_TOTAL)
w_buf = metal_buffer(device, MGPT_TOTAL * 4)
i = 0
while i < MGPT_TOTAL
  metal_buffer_write_f32(w_buf, i, src_view[i].to_f)
  i = i + 1

# KV cache buffers (zero-initialized).
k_buf = metal_buffer(device, MGPT_BLOCK * MGPT_EMBD * 4)
v_buf = metal_buffer(device, MGPT_BLOCK * MGPT_EMBD * 4)

# State buffer: state[0] = tok_in, state[1] = pos, state[2] = rng, state[3] = tok_out
state_buf = metal_buffer(device, 16)
metal_buffer_write_i32(state_buf, 0, MGPT_BOS)
metal_buffer_write_i32(state_buf, 1, 0)
metal_buffer_write_i32(state_buf, 2, 42)
metal_buffer_write_i32(state_buf, 3, 0)

bufs = [w_buf, k_buf, v_buf, state_buf]

# Warmup.
warmup = 1000
i = 0
while i < warmup
  metal_dispatch_groups(queue, pipe, bufs, 1, 32)
  tok_out = metal_buffer_read_i32(state_buf, 3)
  pos = metal_buffer_read_i32(state_buf, 1)
  pos = pos + 1
  if pos >= MGPT_BLOCK
    pos = 0
    tok_out = MGPT_BOS
  metal_buffer_write_i32(state_buf, 0, tok_out)
  metal_buffer_write_i32(state_buf, 1, pos)
  i = i + 1

# Bench.
n_iters = 20000
t0 = clock
i = 0
while i < n_iters
  metal_dispatch_groups(queue, pipe, bufs, 1, 32)
  tok_out = metal_buffer_read_i32(state_buf, 3)
  pos = metal_buffer_read_i32(state_buf, 1)
  pos = pos + 1
  if pos >= MGPT_BLOCK
    pos = 0
    tok_out = MGPT_BOS
  metal_buffer_write_i32(state_buf, 0, tok_out)
  metal_buffer_write_i32(state_buf, 1, pos)
  i = i + 1
elapsed = clock - t0

rate = n_iters.to_f / elapsed
us_per_token = elapsed * ~1.0e6 / n_iters.to_f

<< "tungsten-gpu (fused)  " + rate.to_s + " tok/sec  (" + us_per_token.to_s + " us/tok)"
