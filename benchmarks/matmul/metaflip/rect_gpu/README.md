# Rectangular GPU bundle

These are checked-in pure-Tungsten/Metal cal2zone workers for exact
rectangular GF(2) campaigns:

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

Regenerate the sources with:

```sh
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
