# CUDA host path

## Emit (already works)

`@gpu fn` → sibling `.cu` (and `.metal`). See `doc/gpu-cuda.md`.

```
bin/tungsten compile kernels.w
# → kernels.cu, kernels.metal
```

## Host API (`core/cuda.w`)

```
use core/sci/cuda
<< CUDA.available?          # 0 without bridge
<< CUDA.device_count
# CUDA.malloc / memcpy_h2d / memcpy_d2h / synchronize / free
# CUDA.launch(name, grid, block, args)  # v0 raises with guidance
```

Strong implementations: `runtime/cuda_bridge.cu` (nvcc + `-lcudart`).
Weak stubs in `runtime.c` so CPU-only builds still link.

### Linking the bridge

```
nvcc -O2 -c runtime/cuda_bridge.cu -o /tmp/cuda_bridge.o
# then link user program + cuda_bridge.o -lcudart
```

Named kernel launch table is still thin — for full end-to-end, follow
`benchmarks/cuda_add/` (emit kernel + hand host.cu).

## RunPod

Cheap smoke GPU (community): **RTX 3070 ~$0.13/hr**.

```
runpodctl create pod \
  --name tungsten-cuda-smoke \
  --gpuType "NVIDIA GeForce RTX 3070" \
  --imageName runpod/pytorch:2.1.0-py3.10-cuda11.8.0-devel-ubuntu22.04 \
  --communityCloud --startSSH \
  --ports 22/tcp
```

Then rsync the repo, install clang/nvcc toolchain, compile `benchmarks/cuda_add`.
