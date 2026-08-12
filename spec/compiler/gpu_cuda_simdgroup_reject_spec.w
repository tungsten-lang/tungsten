# CUDA must reject Metal simdgroup matrix calls instead of copying their names
# verbatim into a .cu sidecar.

## f32[]: input
@gpu fn cuda_simdgroup_reject(input)
  simdgroup_load(0, input, 0, 8)
