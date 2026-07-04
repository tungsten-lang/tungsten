# Benchmark the q8_matvec_gate_up_expert kernel at qwen3 expert
# dimensions in a tight loop. Isolates per-dispatch GPU+driver cost
# from the rest of the forward pass to see how far we are from
# bandwidth-bound on this specific kernel.

use core/metal
use tungsten-llama/gguf
use tungsten-llama/tensor

GGUF_PATH = "/Users/erik/.ollama/models/blobs/sha256-ae354763fe478c790125fb993e59bb1266655b3fa721eebe4a931660c3ed2ce9"
HIDDEN = 2048
EXPERT_FFN = 768
N_ITERS = 1000

device = metal_device()
queue = metal_queue(device)
gate_up_pipe = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/q8_matvec_gate_up_expert.metal")), "q8_matvec_gate_up_expert")

g = GGUF.new(GGUF_PATH)
gate_t = Tensor.new(g, g.tensor("blk.0.ffn_gate_exps.weight"))
up_t   = Tensor.new(g, g.tensor("blk.0.ffn_up_exps.weight"))
gate_parts = gate_t.upload_q8(device)
up_parts   = up_t.upload_q8(device)

xn_buf  = metal_buffer(device, HIDDEN * 4)
hg_buf  = metal_buffer(device, EXPERT_FFN * 4)
hu_buf  = metal_buffer(device, EXPERT_FFN * 4)
k_buf   = metal_buffer(device, 4) ; metal_buffer_write_i32(k_buf, 0, HIDDEN)
n_buf   = metal_buffer(device, 4) ; metal_buffer_write_i32(n_buf, 0, EXPERT_FFN)
e_buf   = metal_buffer(device, 4) ; metal_buffer_write_i32(e_buf, 0, 0)

# Synthetic input
i = 0
while i < HIDDEN
  metal_buffer_write_f32(xn_buf, i, Math.sin(i * ~0.013))
  i = i + 1

bufs = [gate_parts[:quants], gate_parts[:scales], up_parts[:quants], up_parts[:scales], xn_buf, hg_buf, hu_buf, k_buf, n_buf, e_buf]

# Warm up (5 iterations)
i = 0
while i < 5
  metal_dispatch_groups(queue, gate_up_pipe, bufs, EXPERT_FFN, 32)
  i = i + 1

# Eager (one commit per dispatch)
t_start = ccall("__w_clock_ms")
i = 0
while i < N_ITERS
  metal_dispatch_groups(queue, gate_up_pipe, bufs, EXPERT_FFN, 32)
  i = i + 1
t_eager = ccall("__w_clock_ms") - t_start

# Batched (one commit for all N_ITERS)
t_start = ccall("__w_clock_ms")
metal_batch_begin(queue)
i = 0
while i < N_ITERS
  metal_dispatch_groups(queue, gate_up_pipe, bufs, EXPERT_FFN, 32)
  i = i + 1
metal_batch_commit(queue)
t_batched = ccall("__w_clock_ms") - t_start

# Bytes touched per dispatch:
# - gate quants: HIDDEN * EXPERT_FFN bytes (Q8 = 1 byte per quant)
# - gate scales: HIDDEN * EXPERT_FFN / 32 * 2 bytes (f16)
# - up: same
# - xn: HIDDEN * 4 bytes (f32) — cached after first read
# - output: EXPERT_FFN * 4 bytes * 2 (hg + hu)
# Total weights = 2 * HIDDEN * EXPERT_FFN * (1 + 2/32) = 2 * 2048 * 768 * 1.0625 = ~3.34 MB
weight_bytes = 2 * HIDDEN * EXPERT_FFN + 2 * HIDDEN * EXPERT_FFN / 32 * 2
total_bytes = weight_bytes * N_ITERS
gb_per_s_eager = total_bytes / (t_eager * 1000) / 1000   # bytes/ms → KB/s? let me redo
# t_eager in ms; bytes/ms * 1e3 = bytes/s; / 1e9 = GB/s
gb_per_s_eager_calc = (total_bytes * ~1.0) / (t_eager * ~1.0)
gb_per_s_batched_calc = (total_bytes * ~1.0) / (t_batched * ~1.0)

<< "q8_matvec_gate_up_expert benchmark (qwen3 dims, " + N_ITERS.to_s + " iters)"
<< "  shape: gate+up [" + EXPERT_FFN.to_s + ", " + HIDDEN.to_s + "] Q8_0"
<< "  weight bytes per iter: " + weight_bytes.to_s + " (" + (weight_bytes / 1024 / 1024).to_s + " MB)"
<< "  eager:   " + t_eager.to_s + " ms total, " + (t_eager * ~1.0 / N_ITERS).to_s + " ms/iter, " + (gb_per_s_eager_calc / ~1000.0).to_s + " GB/s effective"
<< "  batched: " + t_batched.to_s + " ms total, " + (t_batched * ~1.0 / N_ITERS).to_s + " ms/iter, " + (gb_per_s_batched_calc / ~1000.0).to_s + " GB/s effective"

g.close
