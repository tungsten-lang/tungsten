use flipfleet_simd_bundle

failures = 0 ## i64

-> expect(label, condition) i64
  if condition == false || condition == 0
    << "FAIL " + label
    return 1
  0

n = 3 ## i64
while n <= 7
  failures += expect("supported " + n.to_s(), ffsimd_supported(n))
  failures += expect("geometry " + n.to_s(), ffsimd_geometry_valid(n))
  failures += expect("naive reserve " + n.to_s(), ffsimd_cap(n) >= n * n * n + 12)
  failures += expect("shared ceiling " + n.to_s(), ffsimd_shared_bytes(n) <= 32768)
  source = read_file(ffsimd_source_rel(n))
  metal = read_file(ffsimd_metal_rel(n))
  failures += expect("source asset " + n.to_s(), source != nil)
  failures += expect("metal asset " + n.to_s(), metal != nil)
  if source != nil
    failures += expect("bounded dispatch ABI " + n.to_s(), source.include?("DISPATCHES = av\[4].to_i()"))
    failures += expect("host gate A " + n.to_s(), source.include?("while ai < ab"))
    failures += expect("host gate B " + n.to_s(), source.include?("while bi < bb"))
    failures += expect("host gate C " + n.to_s(), source.include?("while ci < cb"))
    failures += expect("structural gate " + n.to_s(), source.include?("A duplicate pair cancels over GF(2)"))
    failures += expect("write gated " + n.to_s(), source.include?("if vok == 1\n  write_file(outpath, body)"))
    failures += expect("checked-in sidecar " + n.to_s(), source.include?(ffsimd_metal_rel(n)))
    failures += expect("cached library " + n.to_s(), source.include?("metal_load_library(device, metallibpath)"))
  if metal != nil
    failures += expect("cooperative kernel " + n.to_s(), metal.include?("kernel void flipwalk_simd"))
    failures += expect("simd lane " + n.to_s(), metal.include?("thread_index_in_simdgroup"))
  n += 1

failures += expect("3x3 scan", ffsimd_mode(3) == 0)
failures += expect("5x5 scan", ffsimd_mode(5) == 0)
failures += expect("6x6 hash", ffsimd_mode(6) == 1)
failures += expect("7x7 hash", ffsimd_mode(7) == 1)
failures += expect("5x5 i32", ffsimd_mask_bytes(5) == 4)
failures += expect("6x6 i64", ffsimd_mask_bytes(6) == 8)

metal6 = read_file(ffsimd_metal_rel(6))
if metal6 != nil
  failures += expect("i64 Metal buffers", metal6.include?("device long *work_us"))
  failures += expect("i64 shared scheme", metal6.include?("threadgroup long sus\[232]"))
source7 = read_file(ffsimd_source_rel(7))
if source7 != nil
  failures += expect("7x7 raw parse", source7.include?("umask = uhi * 10000000 + ulo"))
  failures += expect("7x7 raw seed view", source7.include?("seed_us_view = metal_buffer_view(seed_us, 66"))
  failures += expect("7x7 raw result view", source7.include?("best_us_view = metal_buffer_view(best_us, 66"))

failures += expect("lane floor", ffsimd_round_lanes(95) == 64)
failures += expect("trajectory count", ffsimd_groups_for_lanes(95) == 2)
failures += expect("subgroup rejected", ffsimd_epoch_valid(31, 10, 1, 4) == 0)
failures += expect("counter overflow rejected", ffsimd_epoch_valid(32, 1000000001, 2, 4) == 0)

build = ffsimd_build_command("/repo path", 7, "/tmp/run/simd")
failures += expect("native build source", build.include?("simdgroup_777.w"))
failures += expect("quoted root", build.include?("'/repo path'"))

epoch = ffsimd_epoch_command("/repo", "/tmp/simd", 6, "/tmp/seed", "/tmp/best", 95, 100, 3, 4)
failures += expect("epoch groups", epoch.include?("'/tmp/seed' '/tmp/best' 2 100 3 4 1"))
failures += expect("cached epoch", epoch.ends_with?(" '/tmp/simd.metallib'"))
failures += expect("epoch finite", epoch != "")

if failures > 0
  << "flipfleet_simd_bundle_test: " + failures.to_s() + " failure(s)"
  exit(1)
if failures == 0
  << "flipfleet_simd_bundle_test: all checks passed"
