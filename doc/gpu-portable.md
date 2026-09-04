# Portable GPU preflight (item 25)

`bin/tungsten gpu-check kernels.w` checks the source against the intersection
of Tungsten's Metal, CUDA and WGSL emitters. `--json` returns a versioned report
with source hash, entry kernel names, dialects and diagnostics;
`--capabilities` describes the profile and validation limits.

This reuses the existing AST and selected-dialect preflight. It adds no GPU
language or duplicate lowering backend. The WGSL baseline limits aggregate
shared storage to 16 KiB, and dialect-only operations must pass every emitter.
The command requires a GPU definition in the entry file, does not write shader
sidecars, and does not execute the host program.

Acceptance means compiler preflight/emission succeeded. External shader
compilation, device availability, dynamic bounds, race freedom and cross-device
numerical parity are separate gates. Do not treat the report as hardware
capabilities or a proof that a kernel is race-free. CI's existing WGSL/Naga
semantic validation remains applicable.

`python3 scripts/test-gpu-portable.py` covers a shared add kernel, Metal-only
simdgroup rejection, excess shared memory and a string containing fake kernel
syntax. The canonical AST reader uses byte lengths, not source-text matching.

The existing `gpu-bench --elements 4096 --runs 3 --warmup 1 --strict` also passed
actual Metal dispatch verification on Apple M5 Max, max error about 2.56e-8.
Its exact result is in `experiments/portable-gpu/metal-smoke.json`. This tiny
smoke run establishes Metal execution only; its timings are not a performance
comparison, and CUDA/WebGPU execution was not available in this check.
