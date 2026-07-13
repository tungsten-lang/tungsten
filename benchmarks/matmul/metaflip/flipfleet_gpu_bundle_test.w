use flipfleet_gpu_bundle

failures = 0 ## i64

-> expect(label, condition) i64
  if condition == 0
    << "FAIL " + label
    return 1
  0

n = 3 ## i64
while n <= 7
  failures += expect("supported " + n.to_s(), ffb_supported(n))
  failures += expect("geometry " + n.to_s(), ffb_geometry_valid(n))
  failures += expect("naive capacity " + n.to_s(), ffb_cap(n) >= n * n * n + 32)
  failures += expect("32-lane divisibility " + n.to_s(), (32 % ffb_wpg(n)) == 0)
  failures += expect("shared ceiling " + n.to_s(), ffb_shared_bytes(n) <= 32768)
  source = read_file(ffb_source_rel(n))
  metal = read_file(ffb_metal_rel(n))
  failures += expect("source asset " + n.to_s(), source != nil)
  failures += expect("metal asset " + n.to_s(), metal != nil)
  if source != nil
    failures += expect("exact gate " + n.to_s(), source.include?("while ai < ab"))
    failures += expect("bounded epochs " + n.to_s(), source.include?("ROUNDS = av0[16].to_i()"))
  if metal != nil
    failures += expect("metal kernel " + n.to_s(), metal.include?("kernel void flipwalk"))
  n += 1

failures += expect("3x3 i32", ffb_mask_bytes(3) == 4)
failures += expect("5x5 i32", ffb_mask_bytes(5) == 4)
failures += expect("6x6 i64", ffb_mask_bytes(6) == 8)
failures += expect("7x7 i64", ffb_mask_bytes(7) == 8)
failures += expect("6x6 lane rounding", ffb_round_lanes(6, 35) == 32)
failures += expect("7x7 lane rounding", ffb_round_lanes(7, 33) == 32)

build = ffb_build_command("/repo path", 7, "/tmp/run/gpu")
failures += expect("native build source", build.include?("cal2zone_777.w"))
failures += expect("quoted root", build.include?("'/repo path'"))

epoch = ffb_epoch_command("/repo", "/tmp/gpu", 6, "/tmp/seed", "/tmp/best", "", 152, 100, 20, 8, 80000, 25000, 4, 35, "", 256, 3)
failures += expect("epoch dimension", epoch.include?(" 6 6 6 "))
failures += expect("epoch rounded lanes", epoch.include?(" 32 '' 32 3"))

if failures > 0
  << "flipfleet_gpu_bundle_test: " + failures.to_s() + " failure(s)"
if failures == 0
  << "flipfleet_gpu_bundle_test: all checks passed"
