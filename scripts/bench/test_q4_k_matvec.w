# Focused synthetic correctness test for the packed GGML Q4_K matvec.
#
# Even rows use d=1, dmin=0, all eight six-bit scales=1, and quant bytes
# 0x21. Each block sums to 384. Odd rows use d=0.5, dmin=0.25 and scale/min
# 63, exercising all packed high bits; each block sums to 8064.

use core/metal

K_DIM = 512
N_ROWS = 9
BLOCKS_PER_ROW = K_DIM / 256
WORDS_PER_BLOCK = 144 / 4

device = metal_device()
queue = metal_queue(device)
source = read_file("bits/tungsten-llama/lib/kernels/q4_k/q4_k_matvec.metal")
pipe = metal_pipeline(metal_compile_source(device, source), "q4_k_matvec")

packed = metal_buffer(device, N_ROWS * BLOCKS_PER_ROW * 144)
x = metal_buffer(device, K_DIM * 4)
y = metal_buffer(device, N_ROWS * 4)

i = 0
while i < K_DIM
  metal_buffer_write_f32(x, i, ~1.0)
  i = i + 1

row = 0
while row < N_ROWS
  block = 0
  while block < BLOCKS_PER_ROW
    word = (row * BLOCKS_PER_ROW + block) * WORDS_PER_BLOCK
    if row % 2 == 0
      metal_buffer_write_i32(packed, word + 0, 0x00003c00) # d=half(1), dmin=0
      metal_buffer_write_i32(packed, word + 1, 0x01010101) # scales 0..3
      metal_buffer_write_i32(packed, word + 2, 0x00000000) # mins 0..3
      metal_buffer_write_i32(packed, word + 3, 0x01010101) # scales/mins 4..7
    else
      metal_buffer_write_i32(packed, word + 0, 0x34003800) # d=.5, dmin=.25
      metal_buffer_write_i32(packed, word + 1, -1)         # packed 63s
      metal_buffer_write_i32(packed, word + 2, -1)
      metal_buffer_write_i32(packed, word + 3, -1)
    qword = 4
    while qword < WORDS_PER_BLOCK
      metal_buffer_write_i32(packed, word + qword, 0x21212121)
      qword = qword + 1
    block = block + 1
  row = row + 1

metal_dispatch_groups(queue, pipe, [packed, x, y, K_DIM, N_ROWS], (N_ROWS + 7) / 8, 64)

row = 0
while row < N_ROWS
  expected = row % 2 == 0 ? ~768.0 : ~16128.0
  got = metal_buffer_read_f32(y, row)
  diff = got - expected
  if diff < ~0.0 then diff = ~0.0 - diff
  if diff > ~0.001
    raise "Q4_K matvec mismatch at row " + row.to_s + ": got " + got.to_s + ", expected " + expected.to_s
  row = row + 1

<< "Q4_K packed matvec PASS: " + N_ROWS.to_s + " rows, K=" + K_DIM.to_s + ", scale/min high bits covered"
