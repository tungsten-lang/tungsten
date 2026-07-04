# microGPT streams bench — variant 1: fp16 storage, fp32 accumulators.
# Compares against the fp32-scalar baseline at the same (S, N_STEPS) grid.

use core/metal
use core/file

WEIGHTS_PATH = "bits/tungsten-llama/lib/models/microgpt/weights_fp32.bin"
MGPT_TOTAL = 4192
MGPT_BLOCK = 16
MGPT_EMBD  = 16

S_VALUES       = [1, 16, 64, 256, 1024]
N_STEPS_VALUES = [16, 64, 256]

device = metal_device()
queue  = metal_queue(device)

src = read_file("bits/tungsten-llama/lib/kernels/microgpt_streams_fp16.metal")
lib  = metal_compile_source(device, src)
pipe = metal_pipeline(lib, "microgpt_streams_fp16")

# Load weights as fp16. Source is fp32 on disk; convert lane-by-lane.
mm = File.mmap(WEIGHTS_PATH)
src_view = mm.view_at(0, 32, MGPT_TOTAL)
w_buf = metal_buffer(device, MGPT_TOTAL * 2)
i = 0
while i < MGPT_TOTAL
  metal_buffer_write_f16(w_buf, i, src_view[i].to_f)
  i = i + 1

<< "microGPT GPU streams (fp16 storage) — S × N_STEPS per dispatch"
<< "  S         N_STEPS    aggregate tok/s   per-stream tok/s   us/dispatch"
<< "  --------  ---------  ----------------  -----------------  -----------"

i_s = 0
while i_s < S_VALUES.size()
  s_count = S_VALUES[i_s]
  i_n = 0
  while i_n < N_STEPS_VALUES.size()
    n_steps = N_STEPS_VALUES[i_n]

    k_pool = metal_buffer(device, s_count * MGPT_BLOCK * MGPT_EMBD * 2)
    v_pool = metal_buffer(device, s_count * MGPT_BLOCK * MGPT_EMBD * 2)
    seeds  = metal_buffer(device, s_count * 4)
    out_buf = metal_buffer(device, s_count * n_steps * 4)
    nsteps_buf = metal_buffer(device, 4)
    metal_buffer_write_i32(nsteps_buf, 0, n_steps)

    j = 0
    while j < s_count
      metal_buffer_write_i32(seeds, j, 42 + j)
      j = j + 1

    bufs = [w_buf, k_pool, v_pool, seeds, out_buf, nsteps_buf]

    j = 0
    while j < 3
      metal_dispatch_groups(queue, pipe, bufs, s_count, 32)
      j = j + 1

    iters = 10
    best = ~1.0e18
    trial = 0
    while trial < 5
      t0 = clock
      j = 0
      while j < iters
        metal_dispatch_groups(queue, pipe, bufs, s_count, 32)
        j = j + 1
      elapsed = clock - t0
      ms = elapsed * ~1000.0 / iters
      if ms < best
        best = ms
      trial = trial + 1

    total_tokens = s_count * n_steps
    aggregate = total_tokens.to_f / (best / ~1000.0)
    per_stream = n_steps.to_f / (best / ~1000.0)
    us_per_dispatch = best * ~1000.0

    line = "  S=" + s_count.to_s
    while line.size() < 11
      line = line + " "
    line = line + " " + n_steps.to_s
    while line.size() < 23
      line = line + " "
    line = line + aggregate.to_s
    while line.size() < 42
      line = line + " "
    line = line + per_stream.to_s
    while line.size() < 62
      line = line + " "
    line = line + us_per_dispatch.to_s
    << line

    i_n = i_n + 1
  i_s = i_s + 1
