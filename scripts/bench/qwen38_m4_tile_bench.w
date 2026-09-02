# Bench one parametrized matmul2d tile config. Argv: metal_path MT NT KT SG M K N
# Prints: "MT NT KT SG | gflops ms err"  (err != 0 or a crash => invalid tile)
use core/metal

path = ARGV[0]
MT = ARGV[1].to_i
NT = ARGV[2].to_i
KT = ARGV[3].to_i
SG = ARGV[4].to_i
M  = ARGV[5].to_i
K  = ARGV[6].to_i
N  = ARGV[7].to_i
threads = SG * 32
tgmem = NT * KT * 2

device      = metal_device
m4_compiler = metal4_compiler(device)
m4_queue    = metal4_queue(device)
m4_alloc    = metal4_allocator(device)

lib  = metal_compile_source(device, read_file(path))
pipe = metal4_pipeline(m4_compiler, lib, "nvfp4_matmul_m4_param", threads, 1, 1)

a_buf    = metal_buffer(device, M * K * 2)
w_packed = metal_buffer(device, N * (K / 8) * 4)
w_scales = metal_buffer(device, N * (K / 16))
c_buf    = metal_buffer(device, M * N * 4)
k_const  = metal_buffer(device, 4)
metal_buffer_write_i32(k_const, 0, K)

i = 0
na = (M * K) / 2
while i < na
  metal_buffer_write_i32(a_buf, i, 0x3C003C00)
  i = i + 1
i = 0
nw = N * (K / 8)
while i < nw
  metal_buffer_write_i32(w_packed, i, 0x22222222)
  i = i + 1
i = 0
ns = (N * (K / 16)) / 4
while i < ns
  metal_buffer_write_i32(w_scales, i, 0x38383838)
  i = i + 1

a_tensor = metal_tensor_2d(a_buf, METAL_DTYPE_FLOAT16, M, K, 0, 0)
c_tensor = metal_tensor_2d(c_buf, METAL_DTYPE_FLOAT32, M, N, 0, 0)
at = metal4_argtable(device, 5)
metal4_argtable_set_tensor(at, 0, a_tensor)
metal4_argtable_set_buffer(at, 1, w_packed)
metal4_argtable_set_buffer(at, 2, w_scales)
metal4_argtable_set_tensor(at, 3, c_tensor)
metal4_argtable_set_buffer(at, 4, k_const)
res = [a_buf, w_packed, w_scales, c_buf, k_const]
ntx = (M + MT - 1) / MT
nty = (N + NT - 1) / NT

j = 0
while j < 3
  metal4_dispatch_groups_3d(m4_queue, m4_alloc, pipe, at, res, tgmem, ntx, nty, 1, threads, 1, 1)
  j = j + 1
err = ~0.0
ci = 0
while ci < 3
  idx = 0
  if ci == 1 then idx = (M * N) / 2
  if ci == 2 then idx = M * N - 1
  d = metal_buffer_read_f32(c_buf, idx) - K.to_f
  if d < ~0.0 then d = ~0.0 - d
  if d > err then err = d
  ci = ci + 1

iters = 10
best = ~1.0e18
trial = 0
while trial < 3
  t0 = clock
  j = 0
  while j < iters
    metal4_dispatch_groups_3d(m4_queue, m4_alloc, pipe, at, res, tgmem, ntx, nty, 1, threads, 1, 1)
    j = j + 1
  dt = (clock - t0) * ~1000.0 / iters
  if dt < best then best = dt
  trial = trial + 1

gflops = (~2.0 * M.to_f * N.to_f * K.to_f) / (best * ~1000000.0)
<< MT.to_s + " " + NT.to_s + " " + KT.to_s + " " + SG.to_s + "\t| " + gflops.to_s + "\t" + best.to_s + "\t" + err.to_s
