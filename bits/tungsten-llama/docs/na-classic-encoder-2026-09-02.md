# Neural-Accelerator matmul from a classic compute encoder — 2026-09-02

**Box:** Apple M5 Max (40 GPU cores), 128 GB, macOS 26.6. Kernels in
`bits/tungsten-llama/lib/kernels/na/`, harness `scripts/bench/na_matmul_bench.w`.

## Finding

`mpp::tensor_ops::matmul2d` (the M5 GPU Neural Accelerators) does **not**
need Metal-4 dispatch. Take the operands as plain `device` pointers, build
the tensor views in-shader —

```metal
auto A = tensor(A_ptr, dextents<int32_t, 2>(K, M), array<int32_t, 2>{1, K});  // extent 0 = innermost
```

— keep the weight tile in a static `threadgroup` array, compile with the
ordinary `metal_compile_source` + `metal_pipeline`, and dispatch with
`metal_dispatch_3d` inside the same concurrent command buffer as every other
kernel. No `MTLTensor` binding, no `MTL4ArgumentTable`, no MTL4 command
buffer, no residency set, no commit segmentation.

Why this matters: every earlier NA integration existed only to bind
MTLTensors on MTL4 argument tables — the 27B `ffn_m4` path (five blocking
GPU round-trips per layer, ~4% e2e), the flash-next `FN_M4` markers with
shared-event chaining (measured negative), and the all-MTL4 executor
`FN_M4EXEC` whose 135 GB residency set panicked the AGX driver twice on
2026-09-01. With pointer args the NA GEMM drops straight into the recorded
programs and the no-copy mmap'd weights stay on the classic driver path.

## Throughput (batched: 20 dispatches per commit, best of 5; err = 0 everywhere)

| M | K | N | shape | NVFP4 128x64x128 | bf16 128x64x128 | f16 128x64x128 | bf16 128x64x64 |
|---|---|---|---|---|---|---|---|
| 512 | 2048 | 2048 | smoke | 45.8 | 56.6 | 57.6 | 56.3 |
| 1024 | 2048 | 2048 | smoke | 51.6 | 60.9 | 61.5 | 60.6 |
| 512 | 5120 | 17408 | 27B ffn gate/up | 53.1 | 61.4 | 63.0 | 61.3 |
| 1024 | 5120 | 17408 | 27B ffn gate/up | 53.8 | 61.5 | 61.4 | 61.9 |
| 1024 | 17408 | 5120 | 27B ffn down | 53.2 | 52.1 | 52.3 | 52.3 |
| 512 | 5120 | 12288 | 27B q_proj | 53.6 | 61.9 | 61.5 | 61.2 |
| 512 | 2560 | 512 | FN k/v_proj | 35.6 | 43.8 | 44.2 | 44.8 |
| 512 | 2560 | 6144 | FN gdn out | 51.4 | 62.8 | 61.7 | 62.1 |
| 512 | 10240 | 320 | FN hc mix down | 38.8 | 52.7 | 48.9 | 47.6 |
| 512 | 320 | 10240 | FN hc mix up | — (K%128) | — | — | 55.4 |
| 128 | 2560 | 640 | expert gate/up, 128 rows | 28.1 | 29.3 | 31.5 | 30.1 |
| 512 | 2560 | 640 | expert gate/up, 512 rows | 40.4 | 46.7 | 46.9 | 47.1 |
| 512 | 640 | 2560 | expert down, 512 rows | 42.0 | 49.1 | 52.0 | 49.1 |

Units: TFLOPS. For reference the MTL4 argument-table dispatch of the same
NVFP4 kernel measured 45.0 TFLOPS on `1024x5120x17408` with a per-dispatch
sync; batched classic dispatch is 53.8 on the same shape because the
sync floor (~0.25 ms MTL4, ~0.55 ms classic per commit+wait) is amortized.

## Rules (measured)

1. **The cooperative-tensor store does not clip.** M=100 with a 128-row tile
   wrote 28 rows past `M*N` (row stride N), and a 64-row shape under the
   128 tile page-faulted. Keep `M % MT == 0`, `N % NT == 0`, `K % KT == 0`;
   scratch buffers are `MULTI_MAX` rows so garbage rows beyond the real
   chunk are harmless, but a per-expert grouped GEMM must run full tiles on
   the NA and hand the row tails to the simdgroup-MMA path.
2. **Dynamic-K `op.run(mA, mB, mC)` hangs.** The `dynamic_extent` form used
   by the old MTL4 `bf16_matmul_m4.metal` (`slice<dynamic_length_v, MT>` +
   a device destination) never completes from a classic encoder — all four
   tiles, both element types, 60 s+. The static K-tile loop with a
   cooperative accumulator and explicit `slice<KT, MT>` on both operands
   completes and is what the `na/` kernels use.
3. `execution_simdgroups<4>` needs exactly 128 threads per threadgroup;
   `[[max_total_threads_per_threadgroup(128)]]` plus dispatching (128,1,1)
   is sufficient on the classic path (no `requiredThreadsPerThreadgroup`
   pipeline descriptor needed).
4. The K=64 tile costs nothing measurable and unlocks K=320 (hyper-connection
   mixers); default to it when a shape mix includes K % 128 != 0.

## What this unblocks

- **Qwen3.8-27B prefill:** swap `ffn_m4`'s five per-layer MTL4 round-trips
  for in-batch dispatches, raise the chunk from 64 to 512 (crossover is
  M≈48-64; 53 TFLOPS needs M ≥ 512), route q/k/v/o through the NA, fuse
  gate|up (they share `global_scale` in every layer).
- **Flash-next prefill:** NA backbone GEMMs inside the recorded chunk
  program with no segmentation (the reason the FN_M4 point integration lost);
  hybrid per-expert grouped GEMM — full 64-row tiles on the NA, tails on the
  simdgroup MMA — at chunk ≥ 2048 where the hot experts carry 100s of rows.
- Retires the MTL4-residency redesign entirely; `metal4_*` stays for the
  smoke tests.
