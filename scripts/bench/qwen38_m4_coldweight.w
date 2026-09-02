# Cold-weight timing: rotate through N_ROT distinct weight sets so each dispatch
# streams weights from DRAM (not L2). Argv: metal_path MT NT KT SG M K N N_ROT
# Prints warm (fixed buffer) vs cold (rotating) ms + GFLOPs.
use core/metal

path = ARGV[0]
MT = ARGV[1].to_i
NT = ARGV[2].to_i
KT = ARGV[3].to_i
SG = ARGV[4].to_i
M  = ARGV[5].to_i
K  = ARGV[6].to_i
N  = ARGV[7].to_i
nrot = ARGV[8].to_i
threads = SG * 32
tgmem = NT * KT * 2

device      = metal_device
m4_compiler = metal4_compiler(device)
m4_queue    = metal4_queue(device)
m4_alloc    = metal4_allocator(device)
lib  = metal_compile_source(device, read_file(path))
pipe = metal4_pipeline(m4_compiler, lib, "nvfp4_matmul_m4_param", threads, 1, 1)

a_buf   = metal_buffer(device, M * K * 2)
c_buf   = metal_buffer(device, M * N * 4)
k_const = metal_buffer(device, 4)
metal_buffer_write_i32(k_const, 0, K)
i = 0
na = (M * K) / 2
while i < na
  metal_buffer_write_i32(a_buf, i, 0x3C003C00)
  i = i + 1
a_tensor = metal_tensor_2d(a_buf, METAL_DTYPE_FLOAT16, M, K, 0, 0)
c_tensor = metal_tensor_2d(c_buf, METAL_DTYPE_FLOAT32, M, N, 0, 0)

# N_ROT distinct weight sets + argtables.
wp = []
ws = []
ats = []
resl = []
r = 0
while r < nrot
  wpb = metal_buffer(device, N * (K / 8) * 4)
  wsb = metal_buffer(device, N * (K / 16))
  i = 0
  nw = N * (K / 8)
  while i < nw
    metal_buffer_write_i32(wpb, i, 0x22222222)
    i = i + 1
  i = 0
  nsw = (N * (K / 16)) / 4
  while i < nsw
    metal_buffer_write_i32(wsb, i, 0x38383838)
    i = i + 1
  at = metal4_argtable(device, 5)
  metal4_argtable_set_tensor(at, 0, a_tensor)
  metal4_argtable_set_buffer(at, 1, wpb)
  metal4_argtable_set_buffer(at, 2, wsb)
  metal4_argtable_set_tensor(at, 3, c_tensor)
  metal4_argtable_set_buffer(at, 4, k_const)
  wp.push(wpb)
  ws.push(wsb)
  ats.push(at)
  resl.push([a_buf, wpb, wsb, c_buf, k_const])
  r = r + 1

ntx = (M + MT - 1) / MT
nty = (N + NT - 1) / NT
iters = 30

# Warm: always buffer 0.
j = 0
while j < 5
  metal4_dispatch_groups_3d(m4_queue, m4_alloc, pipe, ats[0], resl[0], tgmem, ntx, nty, 1, threads, 1, 1)
  j = j + 1
warm = ~1.0e18
trial = 0
while trial < 3
  t0 = clock
  j = 0
  while j < iters
    metal4_dispatch_groups_3d(m4_queue, m4_alloc, pipe, ats[0], resl[0], tgmem, ntx, nty, 1, threads, 1, 1)
    j = j + 1
  dt = (clock - t0) * ~1000.0 / iters
  if dt < warm then warm = dt
  trial = trial + 1

# Cold: rotate through all N_ROT sets.
cold = ~1.0e18
trial = 0
while trial < 3
  t0 = clock
  j = 0
  while j < iters
    idx = j % nrot
    metal4_dispatch_groups_3d(m4_queue, m4_alloc, pipe, ats[idx], resl[idx], tgmem, ntx, nty, 1, threads, 1, 1)
    j = j + 1
  dt = (clock - t0) * ~1000.0 / iters
  if dt < cold then cold = dt
  trial = trial + 1

gf_warm = (~2.0 * M.to_f * N.to_f * K.to_f) / (warm * ~1000000.0)
gf_cold = (~2.0 * M.to_f * N.to_f * K.to_f) / (cold * ~1000000.0)
wbytes = N.to_f * (K.to_f / ~2.0)
bw = wbytes / (cold * ~1000000.0)
<< MT.to_s + "x" + NT.to_s + "x" + KT.to_s + " sg" + SG.to_s + " | warm " + warm.to_s + "ms/" + gf_warm.to_s + "gf | cold " + cold.to_s + "ms/" + gf_cold.to_s + "gf | W " + bw.to_s + "GB/s"
