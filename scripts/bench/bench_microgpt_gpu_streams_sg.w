# microGPT streams bench — variant 4: simdgroup_matrix kernel.
# 8 streams per TG × N_TG TGs. S = N_TG * 8. Grid = N_TG threadgroups
# of 32 threads (1 simdgroup) each.

use core/metal
use core/file

WEIGHTS_PATH = "bits/tungsten-llama/lib/models/microgpt/weights_fp32.bin"
MGPT_TOTAL = 4192
MGPT_VOCAB = 27
MGPT_EMBD  = 16
MGPT_BLOCK = 16
VOCAB_PAD  = 32
TOK_PER_TG = 8

# We round S up to the nearest multiple of TOK_PER_TG.
S_VALUES       = [8, 64, 256, 1024, 8192, 16384, 32768]
N_STEPS_VALUES = [16, 64, 256]

device = metal_device()
queue  = metal_queue(device)

src = read_file("bits/tungsten-llama/lib/kernels/microgpt_streams_sg.metal")
lib  = metal_compile_source(device, src)
pipe = metal_pipeline(lib, "microgpt_streams_sg")

# Load weights as fp16.
mm = File.mmap(WEIGHTS_PATH)
src_view = mm.view_at(0, 32, MGPT_TOTAL)
w_buf = metal_buffer(device, MGPT_TOTAL * 2)

MGPT_TOTAL -> metal_buffer_write_f16(w_buf, i, src_view[i].to_f)

# Pad LM head from VOCAB=27 rows to VOCAB_PAD=32 rows (zero-fill the extras).
# Original LM occupies indices 3760..4191 (27 * 16 = 432 floats).
lm_buf = metal_buffer(device, VOCAB_PAD * MGPT_EMBD * 2)

(VOCAB_PAD * MGPT_EMBD)  -> metal_buffer_write_f16(lm_buf, i, ~0.0)

(MGPT_VOCAB * MGPT_EMBD) -> metal_buffer_write_f16(lm_buf, i, src_view[3760 + i].to_f)

<< "microGPT GPU streams (simdgroup_matrix) — S × N_STEPS per dispatch"
<< "  S         N_STEPS    aggregate tok/s   per-stream tok/s   us/dispatch"
<< "  --------  ---------  ----------------  -----------------  -----------"

S_VALUES -> (s_raw)
  s_count = s_raw ## i32

  if s_count % TOK_PER_TG != 0
    s_count = (s_count / TOK_PER_TG + 1) * TOK_PER_TG

  n_tg = s_count / TOK_PER_TG

  N_STEPS_VALUES -> (n_steps)
    seeds      = metal_buffer(device, s_count * 4)
    seeds_out  = metal_buffer(device, s_count * 4)
    out_buf    = metal_buffer(device, s_count * n_steps * 4)
    nsteps_buf = metal_buffer(device, 4)

    metal_buffer_write_i32(nsteps_buf, 0, n_steps)

    s_count -> metal_buffer_write_i32(seeds, j, 42 + j)

    bufs = [w_buf, lm_buf, seeds, out_buf, seeds_out, nsteps_buf]

    # Warmup.
    3 -> metal_dispatch_groups(queue, pipe, bufs, n_tg, 32)

    iters = 10
    best = ~1.0e18

    5 ->
      t0 = clock
      iters -> metal_dispatch_groups(queue, pipe, bufs, n_tg, 32)

      elapsed = clock - t0
      ms = elapsed * ~1000.0 / iters

      if ms < best
        best = ms

    total_tokens = s_count * n_steps
    aggregate = total_tokens.to_f / (best / ~1000.0)
    per_stream = n_steps.to_f / (best / ~1000.0)
    us_per_dispatch = best * ~1000.0

    line = "  S=[s_count]"
    while line.size < 11
      line << " "

    line << " "
    line << n_steps.to_s
    while line.size < 23
      line << " "

    line << aggregate.to_s
    while line.size < 42
      line << " "

    line = line + per_stream.to_s
    while line.size < 62
      line << " "

    line << us_per_dispatch.to_s
    << line
