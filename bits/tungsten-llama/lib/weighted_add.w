# Scalar-weighted accumulate: dst[i] += w * src[i].
#
# Used by MoE FFN to combine the top-K experts' outputs into a single
# vector. Replaces the CPU loop that read each f32 back through the PCI
# bus, multiplied, and wrote it back — for n=2048 elements × 8 experts
# × 48 layers that's ~800K Metal buffer reads/writes per generated token.

## f32[]: dst
## f32[]: src
## f32: w
## i32: n
@gpu fn weighted_add(dst, src, w, n)
  i = gpu.thread_position_in_grid.x ## i32
  if i < n
    dst[i] = dst[i] + w * src[i]
