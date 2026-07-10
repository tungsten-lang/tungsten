# CUDA add_one smoke

Validates the Tungsten `@gpu` → CUDA C dialect on NVIDIA hardware.

## Emit only (no GPU)

```bash
bin/tungsten compile spec/core/cuda_add_probe.w --out /tmp/cuda_add_probe
# sibling: spec/core/cuda_add_probe.cu
bin/tungsten run spec/core/cuda_add_probe.w   # checks .cu markers
```

`TUNGSTEN_GPU_DIALECTS` defaults to emitting CUDA for every `@gpu` program.
Set `TUNGSTEN_GPU_DIALECTS=none` to suppress, or `cuda,wgsl` to also emit WGSL.

## Run on NVIDIA (nvcc)

```bash
nvcc -O2 -o /tmp/cuda_add benchmarks/cuda_add/host.cu
/tmp/cuda_add
# => cuda add_one ok
```

To exercise a compiler-emitted kernel, compile the sidecar:

```bash
# After emitting spec/core/cuda_add_probe.cu, link a small host that declares
# the same signature and launches it (see host.cu for the pattern).
nvcc -O2 -c spec/core/cuda_add_probe.cu -o /tmp/add_one.o
# then link with a host .cu that only provides main() + extern kernel decl
```
