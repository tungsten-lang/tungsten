# Phase 4 — programmatic schedule enumeration over the bounded grammar.
#
# Generates a cross-product of schedule variants for q8_matvec
# (parallelize × stride × vectorize × layout), writes the kernel +
# generated @schedule blocks to a temp .w file, compiles it, then
# feeds the compiled variants to the Autotuner harness from
# tungsten-llama/lib/autotune.w.
#
# This is the last piece of Phase 4: the harness already exists; this
# script is the candidate generator that drives it.

use core/metal
use tungsten-llama/autotune

GEN_PATH = "/tmp/autotune_q8_gen.w"
GEN_BIN  = "/tmp/autotune_q8_gen"
GEN_MSL  = "/tmp/autotune_q8_gen.metal"

# Bounded grammar for the q8_matvec sweep. Every triple is one variant.
strides   = [16, 32, 64]
vec_factors = [0, 2, 4]
layouts   = ["none", "packed"]

variants = []
i = 0
while i < strides.size()
  j = 0
  while j < vec_factors.size()
    k = 0
    while k < layouts.size()
      variants.push({stride: strides[i], vec: vec_factors[j], layout: layouts[k]})
      k = k + 1
    j = j + 1
  i = i + 1

# Build the variant name from its grammar coordinates so the autotuner
# can refer to each compiled kernel by name.
-> variant_name(v)
  out = "s" + v[:stride].to_s + "_v" + v[:vec].to_s + "_" + v[:layout]
  out

# Emit the .w source: kernel definition, optional @layout, all
# generated @schedule blocks. Every `[]` that should appear in the
# emitted Tungsten source is `\[\]` here so Tungsten's own `[expr]`
# string interpolation doesn't fire on the scaffolding.
sb = StringBuffer(8192)
sb << "use core/metal\n\n"
sb << "## i8\[\]: w_q\n## f16\[\]: w_s\n## f32\[\]: x\n## f32\[\]: y\n## i32: k_dim\n"
sb << "@gpu fn q8_matvec(w_q, w_s, x, y, k_dim)\n"
sb << "  m = gpu.thread_position_in_grid.x ## axis :m\n"
sb << "  nb = k_dim / 32 ## i32\n"
sb << "  acc = 0.0 ## f32\n"
sb << "  b = 0 ## axis :b, i32\n"
sb << "  while b < nb\n"
sb << "    s = w_s\[m * nb + b\] ## f16\n"
sb << "    block_acc = 0.0 ## f32\n"
sb << "    j = 0 ## axis :j, i32\n"
sb << "    while j < 32\n"
sb << "      block_acc = block_acc + w_q\[m * k_dim + b * 32 + j\] * x\[b * 32 + j\]\n"
sb << "      j = j + 1\n"
sb << "    acc = acc + s * block_acc\n"
sb << "    b = b + 1\n"
sb << "  y\[m\] = acc\n\n"
sb << "@layout q8_matvec.packed_q8\n"
sb << "  buffer :w_q, from: \"i8\[\]\", to: \"i32\[\]\", unpack: :sign_extend_per_byte\n\n"

i = 0
while i < variants.size()
  v = variants[i]
  sb << "@schedule q8_matvec." + variant_name(v) + "\n"
  if v[:layout] == "packed"
    sb << "  use_layout :packed_q8\n"
  sb << "  axis :m, parallelize: :threadgroup\n"
  sb << "  axis :b, parallelize: :simdgroup_lane, stride: " + v[:stride].to_s + "\n"
  sb << "  axis :b, reduce: :simd_sum, into: :acc\n"
  if v[:vec] > 0
    sb << "  axis :j, vectorize: " + v[:vec].to_s + "\n"
  sb << "\n"
  i = i + 1

write_file(GEN_PATH, sb.to_s)
<< "wrote " + variants.size().to_s + " variants → " + GEN_PATH

# Compile to get the .metal file (and a binary we don't actually run).
system("bin/tungsten compile " + GEN_PATH + " --ll -o " + GEN_BIN)

# Set up the autotuner harness. Use qwen3 lm_head shape (151936 × 2048)
# as the test workload — same as q8_matvec_three_schedules.
n_rows = 151936
k_cols = 2048
nb = k_cols / 32

device = metal_device()
queue  = metal_queue(device)
msl    = read_file(GEN_MSL)
library = metal_compile_source(device, msl)

w_q_buf = metal_buffer(device, n_rows * k_cols)
w_s_buf = metal_buffer(device, n_rows * nb * 2)
x_buf   = metal_buffer(device, k_cols * 4)
y_buf   = metal_buffer(device, n_rows * 4)
k_buf   = metal_buffer(device, 4) ; metal_buffer_write_i32(k_buf, 0, k_cols)

i = 0
while i < (n_rows * k_cols) / 4
  metal_buffer_write_i32(w_q_buf, i, 0x01010101)
  i = i + 1
i = 0
while i < (n_rows * nb) / 2
  metal_buffer_write_i32(w_s_buf, i, 0x3C003C00)
  i = i + 1
i = 0
while i < k_cols
  metal_buffer_write_f32(x_buf, i, ~1.0)
  i = i + 1

bufs = [w_q_buf, w_s_buf, x_buf, y_buf, k_buf]

# Baseline: the un-scheduled `q8_matvec` kernel, one thread per row.
# It's slow but correct, and gives us a ground-truth output for the
# autotuner's validation pass to compare against. Without this, the
# harness would compare schedule variants to each other and miss any
# class of buggy schedule that happens to match other buggy schedules.
candidates = []
default_pipe = metal_pipeline(library, "q8_matvec")
candidates.push(AutotuneCandidate.new("default", default_pipe, n_rows, 0, bufs))

i = 0
while i < variants.size()
  vname = variant_name(variants[i])
  pipe  = metal_pipeline(library, "q8_matvec_" + vname)
  candidates.push(AutotuneCandidate.new(vname, pipe, n_rows, 32, bufs))
  i = i + 1

tuner = Autotuner.new(queue, candidates, y_buf, n_rows)
tuner.abs_tol = ~0.001
tuner.warmup_iters = 5
tuner.measure_iters = 30
winner_idx = tuner.run

if winner_idx >= 0
  shape_key = n_rows.to_s + "x" + k_cols.to_s
  system("mkdir -p /tmp/tungsten/autotune-cache")
  tuner.write_cache("/tmp/tungsten/autotune-cache", "q8_matvec", shape_key, winner_idx, ~0.0)
