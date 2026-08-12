# `tungsten -c` must run the GPU preflight and reject this before any sidecar
# or external shader compiler sees it.

@gpu fn missing_gpu_hint(output)
  output[0] = 1.0
