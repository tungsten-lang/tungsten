# Element-wise f32 copy: dst[i] = src[i].
#
# One thread per element, bounds-checked. Replaces CPU loops like
# `i = 0; while i < n; write(dst, i, read(src, i)); i += 1` that
# showed up all over the inference driver for saving the pre-attention
# residual and restoring it after the block. Each of those loops was
# 2048 Metal buffer reads + 2048 writes; the kernel runs in one dispatch.

## f32[]: src
## f32[]: dst
## i32: n
@gpu fn f32_copy(src, dst, n)
  i = gpu.thread_position_in_grid.x ## i32
  if i < n
    dst[i] = src[i]
