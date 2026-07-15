# Rectangular GPU bundle

These are checked-in pure-Tungsten/Metal cal2zone workers for exact
rectangular GF(2) campaigns:

- `cal2zone_225`: rank-18 frontier / rank-17 target for `2x2x5`, capacity 64, 16 walkers/group.
- `cal2zone_234`: proven-optimal rank-20 `2x3x4` density/basin walker, capacity 64, 16 walkers/group.
- `cal2zone_235`: rank-25 frontier / rank-24 target for `2x3x5`, capacity 68, 16 walkers/group.
- `cal2zone_245`: rank-32 target for `2x4x5`, capacity 80, 16 walkers/group.
- `cal2zone_256`: rank-47 frontier / rank-46 target for `2x5x6`, capacity 92, 16 walkers/group.
- `cal2zone_334`: rank-29 target for `3x3x4`, capacity 68, 16 walkers/group.
- `cal2zone_335`: rank-35 target for `3x3x5`, capacity 77, 16 walkers/group.
- `cal2zone_344`: rank-38 target for `3x4x4`, capacity 80, 16 walkers/group.
- `cal2zone_345`: rank-46 target for `3x4x5`, capacity 92, 16 walkers/group.
- `cal2zone_355`: rank-57 target for `3x5x5`, capacity 107, 16 walkers/group.
- `cal2zone_445`: rank-59 target for `4x4x5`, capacity 112, 16 walkers/group.

Unlike the square generator's historical common factor mask, these kernels
mask plus moves independently to `nm`, `mp`, and `np` bits. Their host relays
exhaustively reconstruct every rectangular tensor coefficient before writing
a candidate. Rectangular split portfolios interleave U/V/W axes, so even a
single 16-lane scheduler slice covers all three instead of exhausting a full
rank of U splits first. `flipfleet_rect_gpu_bundle.w` is the native coordinator
ABI and uses the same source-fresh offline `.metallib` cache as the square
workers.

All checked-in workers also share the corrected GF(2) duplicate compactor:
it removes the higher and then lower duplicate indices as two independent
tail deletions. This prevents a parity cancellation from accidentally
discarding an unrelated term. Static generator/Metal tests cover all sixteen
assets, and the `2x2x5` worker passed an 8.192-billion-move full-width device
replay with no internal exactness rejection.

The 234, 235, 245, and 256 host relays accept both public `R u v w` rows and FlipFleet's
numeric-rank checkpoint format. This keeps their direct standalone runs
consistent with the coordinator's normalized snapshots; future regeneration
applies the same parser to the older bundle members.

The live 225, 235, 245, and 256 campaigns additionally rotate the adjacent
`flipfleet_rect_mitm_lane.w` exact 5 -> 4 worker at low cadence. This worker
shares the square lane's GPU pair kernels but uses independent `nm`, `mp`, and `np`
fingerprints plus the rectangular full-tensor admission gate. It is built as
a short-lived cached-metallib child rather than folded into these persistent
cal2zone relays. For `2x2x5` a hit is the target rank-17 decomposition; for
`2x3x5` it is the live rank-24 target. A 64-batch 235 admission sweep covered
1,024 subsets, 393,216 candidates, and 75,300,864 complementary pairs with no
fingerprint hit or exact rejection. The 234 MITM lane is retired
because the quotient-rank proof establishes exact rank 20.

The 256 bring-up uses the exact rank-47/d438 catalog seed. Capacity 92 leaves
45 terms of shoulder while using 17,664/32,768 threadgroup bytes. A four-round
4,096-lane smoke covered 163.84M moves in 2.89 seconds (56.7M moves/s including
setup), with no internal reject or false improvement. The companion pool-384
MITM smoke tested 16 windows, 6,144 candidates, and 1,176,576 complementary
pairs in 1.59 seconds with zero fingerprint or exact rejects. Both lanes are
therefore enabled by default at their normal adaptive/low cadence.
The native one-round full-width replay exercised both together and reported
163.84M cal2zone moves in 1,362 GPU ms plus the same MITM pair count in 840 ms,
with zero GPU failures, host exact rejects, internal rejects, MITM failures, or
degraded health; its final rank-47/d438 checkpoint independently reloaded.

The first 235 cal2zone bring-up used the exact rank-25/d160 fleet leader.
Capacity 68 leaves 43 terms of variable-rank shoulder above the leader and
still occupies only 13,056 of Metal's 32,768 threadgroup bytes. A four-round
4,096-lane profile covered 1.6384 billion moves in 5.27 seconds (311M moves/s
including process setup, while other fleet jobs were using the same GPU),
with no internal reject or false improvement. The full coordinator then
completed a bounded 10.24M-move cal2zone smoke plus 1,176,576 MITM pair probes:
both workers were ready, the final rank-25/d160 checkpoint was exact, and all
GPU failure, host exact-reject, and internal-reject counters remained zero.

`affine_decoder_225.metal` is a separate, offline 225 fixed-dictionary
decoder generated from `../flipfleet_225_affine_decoder_lib.w`. It contains
the complete radius-three coefficient-shell kernels and the sparse exact
rank-band walker documented in [`../AFFINE_DECODER_225.md`](../AFFINE_DECODER_225.md).
It is deliberately not part of the persistent rectangular bundle or default
kernel pool: its first large sweeps demonstrated distant rank-18 tunnels but
no rank-17 or downstream objective improvement.

Regenerate the sources with:

```sh
python3 benchmarks/matmul/zoo/gpu_cal2zone_gen.py 2 2 5 64 16 64 \
  benchmarks/matmul/metaflip/rect_gpu/cal2zone_225.w \
  benchmarks/matmul/metaflip/rect_gpu/cal2zone_225.ll
python3 benchmarks/matmul/zoo/gpu_cal2zone_gen.py 2 3 4 64 16 64 \
  benchmarks/matmul/metaflip/rect_gpu/cal2zone_234.w \
  benchmarks/matmul/metaflip/rect_gpu/cal2zone_234.ll
python3 benchmarks/matmul/zoo/gpu_cal2zone_gen.py 2 3 5 68 16 68 \
  benchmarks/matmul/metaflip/rect_gpu/cal2zone_235.w \
  benchmarks/matmul/metaflip/rect_gpu/cal2zone_235.ll
python3 benchmarks/matmul/zoo/gpu_cal2zone_gen.py 2 4 5 80 16 80 \
  benchmarks/matmul/metaflip/rect_gpu/cal2zone_245.w \
  benchmarks/matmul/metaflip/rect_gpu/cal2zone_245.ll
python3 benchmarks/matmul/zoo/gpu_cal2zone_gen.py 2 5 6 92 16 92 \
  benchmarks/matmul/metaflip/rect_gpu/cal2zone_256.w \
  benchmarks/matmul/metaflip/rect_gpu/cal2zone_256.ll
python3 benchmarks/matmul/zoo/gpu_cal2zone_gen.py 3 3 4 68 16 68 \
  benchmarks/matmul/metaflip/rect_gpu/cal2zone_334.w \
  benchmarks/matmul/metaflip/rect_gpu/cal2zone_334.ll
python3 benchmarks/matmul/zoo/gpu_cal2zone_gen.py 3 3 5 77 16 77 \
  benchmarks/matmul/metaflip/rect_gpu/cal2zone_335.w \
  benchmarks/matmul/metaflip/rect_gpu/cal2zone_335.ll
python3 benchmarks/matmul/zoo/gpu_cal2zone_gen.py 3 4 4 80 16 80 \
  benchmarks/matmul/metaflip/rect_gpu/cal2zone_344.w \
  benchmarks/matmul/metaflip/rect_gpu/cal2zone_344.ll
python3 benchmarks/matmul/zoo/gpu_cal2zone_gen.py 3 4 5 92 16 92 \
  benchmarks/matmul/metaflip/rect_gpu/cal2zone_345.w \
  benchmarks/matmul/metaflip/rect_gpu/cal2zone_345.ll
python3 benchmarks/matmul/zoo/gpu_cal2zone_gen.py 3 5 5 107 16 107 \
  benchmarks/matmul/metaflip/rect_gpu/cal2zone_355.w \
  benchmarks/matmul/metaflip/rect_gpu/cal2zone_355.ll
python3 benchmarks/matmul/zoo/gpu_cal2zone_gen.py 4 4 5 112 16 112 \
  benchmarks/matmul/metaflip/rect_gpu/cal2zone_445.w \
  benchmarks/matmul/metaflip/rect_gpu/cal2zone_445.ll
```

Compile with `TUNGSTEN_LL_PATH` set to the corresponding `.ll` path to refresh
the checked-in `.metal` sidecar. `.ll` and `.cu` are ignored build products.
Standalone campaign commands and seed provenance are in
[`../RECTANGULAR_CAMPAIGNS.md`](../RECTANGULAR_CAMPAIGNS.md).
