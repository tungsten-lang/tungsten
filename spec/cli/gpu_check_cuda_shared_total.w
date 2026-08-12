# A CUDA-only intrinsic makes the Metal sidecar skip this kernel. CUDA
# preflight must then reject 13000*4 = 52000 bytes above its 48 KiB baseline.

## i32: marker
@gpu fn excessive_cuda_shared_total(marker)
  tile = gpu.shared_f32(13000)
  fragment = gpu.wmma_frag_acc_f32()
  tile[0] = 1.0
