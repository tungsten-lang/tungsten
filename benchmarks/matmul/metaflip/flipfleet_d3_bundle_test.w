use flipfleet_d3_bundle

-> d3b_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)
  1

z = d3b_expect("6x6 only", ffd3b_supported(6) == 1 && ffd3b_supported(5) == 0 && ffd3b_supported(7) == 0) ## i64
z = d3b_expect("bounded capacity", ffd3b_cap(6) == 240 && ffd3b_cap(5) == 0)
z = d3b_expect("source path", ffd3b_source_rel(6) == "benchmarks/matmul/metaflip/d3_bundle/d3_666.w")
z = d3b_expect("metal path", ffd3b_metal_rel(6) == "benchmarks/matmul/metaflip/d3_bundle/d3_666.metal")
source = read_file(ffd3b_source_rel(6))
metal = read_file(ffd3b_metal_rel(6))
z = d3b_expect("checked-in Tungsten", source != nil && source.include?("@gpu fn d3_walk") && source.include?("z2_closed"))
z = d3b_expect("cached library", source != nil && source.include?("metal_load_library(device, metallibpath)"))
z = d3b_expect("checked-in Metal", metal != nil && metal.include?("kernel void d3_walk") && metal.include?("sameorbit"))
z = d3b_expect("unsupported build", ffd3b_build_command("/repo", 5, "/tmp/d3") == "")
build = ffd3b_build_command("/repo path", 6, "/tmp/d3")
z = d3b_expect("optimized native build", build.include?("--release --native --fast --lto") && build.include?("d3_666.w"))
epoch = ffd3b_epoch_command("/repo", "/tmp/d3", 6, "/tmp/seed file", "/tmp/out", 9000, 0, 100, 999, -1)
z = d3b_expect("epoch clamps walkers", epoch.include?(" 4096 "))
z = d3b_expect("epoch clamps steps/dispatch", epoch.include?(" 1 64 "))
z = d3b_expect("epoch clamps band/plus", epoch.include?(" 228 0"))
z = d3b_expect("cached epoch", epoch.ends_with?(" '/tmp/d3.metallib'"))
<< "flipfleet_d3_bundle_test: all checks passed"
