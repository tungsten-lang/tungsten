use flipfleet_c3_bundle

failures = 0 ## i64

-> expect(label, condition) i64
  if condition == 0
    << "FAIL " + label
    return 1
  0

n = 3 ## i64
while n <= 7
  failures += expect("supported " + n.to_s(), ffc3_supported(n))
  failures += expect("naive plus band capacity " + n.to_s(), ffc3_cap(n) >= n * n * n + 23)
  source = read_file(ffc3_source_rel(n))
  metal = read_file(ffc3_metal_rel(n))
  failures += expect("source asset " + n.to_s(), source != nil)
  failures += expect("metal asset " + n.to_s(), metal != nil)
  if source != nil
    failures += expect("full tensor gate " + n.to_s(), source.include?("-> verify_full"))
    failures += expect("C3 gate " + n.to_s(), source.include?("-> c3_closed"))
    failures += expect("factor gate " + n.to_s(), source.include?("-> factors_valid"))
    failures += expect("bounded dispatch " + n.to_s(), source.include?("DISPATCHES > 64"))
    failures += expect("gated output " + n.to_s(), source.include?("if factorok == 1"))
    failures += expect("cached library " + n.to_s(), source.include?("metal_load_library(device, metallibpath)"))
  if metal != nil
    failures += expect("Metal quotient kernel " + n.to_s(), metal.include?("kernel void c3_walk"))
  n += 1

failures += expect("3x3 i32", ffc3_mask_bytes(3) == 4)
failures += expect("5x5 i32", ffc3_mask_bytes(5) == 4)
failures += expect("6x6 i64", ffc3_mask_bytes(6) == 8)
failures += expect("7x7 i64", ffc3_mask_bytes(7) == 8)
failures += expect("reject unsupported", ffc3_build_command("/repo", 8, "/tmp/c3") == "")

build = ffc3_build_command("/repo path", 7, "/tmp/run/c3")
failures += expect("native build source", build.include?("c3_777.w"))
failures += expect("quoted root", build.include?("'/repo path'"))

epoch = ffc3_epoch_command("/repo", "/tmp/c3", 6, "/tmp/seed file", "/tmp/best", 9000, 0, 100, -2, -1)
failures += expect("quoted seed", epoch.include?("'/tmp/seed file'"))
failures += expect("bounded epoch", epoch.include?(" 4096 1 64 0 0"))
failures += expect("cached epoch", epoch.ends_with?(" '/tmp/c3.metallib'"))
failures += expect("invalid build status", ffc3_build("", 3, "/tmp/c3") == 0)
failures += expect("explicit epoch status", ffc3_epoch("/", "/usr/bin/true", 3, "/tmp/seed", "/tmp/out", 1, 1, 1, 0, 0) == 1)

if failures > 0
  << "flipfleet_c3_bundle_test: " + failures.to_s() + " failure(s)"
if failures == 0
  << "flipfleet_c3_bundle_test: all checks passed"
