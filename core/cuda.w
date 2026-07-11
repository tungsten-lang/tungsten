# CUDA — host-side launch for `@gpu fn` kernels emitted as .cu.
#
# Emit path (already exists):
#   bin/tungsten compile kernels.w  → kernels.metal + kernels.cu
#
# Host launch (this module + runtime/cuda_bridge.cu):
#   CUDA.available?
#   buf = CUDA.malloc(nbytes)
#   CUDA.memcpy_h2d(buf, host_arr, nbytes)
#   CUDA.launch("add_one", grid, block, [buf, n])
#   CUDA.memcpy_d2h(host_arr, buf, nbytes)
#   CUDA.free(buf)
#   CUDA.synchronize
#
# On machines without CUDA the ccall weak stubs raise a clear error.
# See doc/scientific-computing/cuda.md and benchmarks/cuda_add/.

+ CUDA
  -> .available?
    ccall("w_cuda_available")

  -> .device_count
    ccall("w_cuda_device_count")

  -> .malloc(nbytes)
    ccall("w_cuda_malloc", nbytes)

  -> .free(ptr)
    ccall("w_cuda_free", ptr)

  -> .memcpy_h2d(dst, src_arr, nbytes)
    ccall("w_cuda_memcpy_h2d", dst, src_arr, nbytes)

  -> .memcpy_d2h(dst_arr, src, nbytes)
    ccall("w_cuda_memcpy_d2h", dst_arr, src, nbytes)

  -> .synchronize
    ccall("w_cuda_synchronize")

  # Launch a kernel by name. grid/block are [x,y,z] lists (y/z default 1).
  # args is a list of device pointers / ints (see bridge ABI).
  -> .launch(name, grid, block, args)
    gx = grid[0]
    gy = 1
    gz = 1
    if grid.size() > 1
      gy = grid[1]
    if grid.size() > 2
      gz = grid[2]
    bx = block[0]
    by = 1
    bz = 1
    if block.size() > 1
      by = block[1]
    if block.size() > 2
      bz = block[2]
    ccall("w_cuda_launch", name, gx, gy, gz, bx, by, bz, args)

  -> .device_name(index = 0)
    ccall("w_cuda_device_name", index)
