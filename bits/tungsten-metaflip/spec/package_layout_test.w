use core/system
use ../lib/metaflip/seeds/catalog
use ../lib/metaflip/seeds/rect
use ../lib/metaflip/rect/policy
use ../lib/metaflip/kernels/bundles/generic
use ../lib/metaflip/kernels/bundles/c3
use ../lib/metaflip/kernels/bundles/simd
use ../lib/metaflip/kernels/bundles/rect
use ../lib/metaflip/kernels/bundles/pooled_exact
use ../lib/metaflip/kernels/metallib_cache
use ../lib/metaflip/paths

failures = 0 ## i64

-> package_expect(label, condition) (String bool) i64
  if condition == 0
    << "FAIL " + label
    return 1
  0

-> package_expect_rect_partner_guard(runtime_root, shape) (String String) i64
  source = read_file(runtime_root + "/kernels/rectangular/cal2zone_" + shape + ".w")
  package_expect("rectangular " + shape + " guards a missing partner", source != nil && source.include?("a = fj\n      if a < 0\n        a = rank\n      if a < rank"))

-> package_expect_generic_partner_guard(runtime_root, shape) (String String) i64
  source = read_file(runtime_root + "/kernels/generic/cal2zone_" + shape + ".w")
  package_expect("generic " + shape + " guards a missing partner", source != nil && source.include?("a = fj\n      if a < 0\n        a = rank\n      if a < rank"))

package_root = __DIR__ + "/.."
runtime_root = package_root + "/lib/metaflip"
canonical_runtime_root = ffls_canonical_dir(runtime_root)

failures += package_expect("relative runtime root canonicalizes", canonical_runtime_root.starts_with?("/") && read_file(canonical_runtime_root + "/fleet.w") != nil)

failures += package_expect("square seed is packaged", read_file(runtime_root + "/" + ffp_seed_path(5)) != nil)
failures += package_expect("rectangular seed is packaged", read_file(runtime_root + "/" + ffrp_seed_rel(3, 4, 6)) != nil)
failures += package_expect("227 d128 is the packaged default", ffrp_seed_rel(2, 2, 7).ends_with?("matmul_2x2x7_rank25_d128_rect_portfolio_gf2.txt"))
failures += package_expect("227 preserves d132 and +1/+2 doors", ffrp_frontier_seed_count(2, 2, 7) == 4 && ffrp_frontier_seed_rel(2, 2, 7, 1).ends_with?("matmul_2x2x7_rank25_catalog_gf2.txt") && ffrp_frontier_seed_rel(2, 2, 7, 2).ends_with?("rank26_isotropy_split_plus1_gf2.txt") && ffrp_frontier_seed_rel(2, 2, 7, 3).ends_with?("rank27_isotropy_split_plus2_gf2.txt"))
failures += package_expect("227 d128 seed is packaged", read_file(runtime_root + "/" + ffrp_seed_rel(2, 2, 7)) != nil)
failures += package_expect("229 preserves R/R+1/R+2 doors", ffrp_frontier_seed_count(2, 2, 9) == 5 && ffrp_frontier_seed_rel(2, 2, 9, 3).ends_with?("rank33_d159_isotropy_split_plus1_gf2.txt") && ffrp_frontier_seed_rel(2, 2, 9, 4).ends_with?("rank34_d165_isotropy_split_plus2_gf2.txt"))
failures += package_expect("229 rank-debt doors are packaged", read_file(runtime_root + "/" + ffrp_frontier_seed_rel(2, 2, 9, 3)) != nil && read_file(runtime_root + "/" + ffrp_frontier_seed_rel(2, 2, 9, 4)) != nil)
package_sums = read_file(runtime_root + "/SHA256SUMS")
failures += package_expect("229 rank-debt doors are checksummed", package_sums != nil && package_sums.include?("matmul_2x2x9_rank33_d159_isotropy_split_plus1_gf2.txt") && package_sums.include?("matmul_2x2x9_rank34_d165_isotropy_split_plus2_gf2.txt"))
failures += package_expect("344 d280 is the packaged default", ffrp_seed_rel(3, 4, 4).ends_with?("matmul_3x4x4_rank38_d280_live_density_leader_gf2.txt"))
failures += package_expect("344 preserves R/R+1/R+2 doors", ffrp_frontier_seed_count(3, 4, 4) == 4 && ffrp_frontier_seed_rel(3, 4, 4, 1).ends_with?("matmul_3x4x4_rank38_gf2.txt") && ffrp_frontier_seed_rel(3, 4, 4, 2).include?("rank39_peterson_2026_isotropy_split_plus1") && ffrp_frontier_seed_rel(3, 4, 4, 3).include?("rank40_peterson_2026_isotropy_split_plus2"))
failures += package_expect("344 d280 seed is packaged", read_file(runtime_root + "/" + ffrp_seed_rel(3, 4, 4)) != nil)
failures += package_expect("456 d906 is the packaged default", ffrp_seed_rel(4, 5, 6).ends_with?("matmul_4x5x6_rank90_d906_rect_portfolio_gf2.txt"))
failures += package_expect("456 preserves three doors", ffrp_frontier_seed_count(4, 5, 6) == 3 && ffrp_frontier_seed_rel(4, 5, 6, 1).ends_with?("matmul_4x5x6_rank90_d907_gl_frontier_gf2.txt") && ffrp_frontier_seed_rel(4, 5, 6, 2).ends_with?("matmul_4x5x6_rank90_catalog_gf2.txt"))
failures += package_expect("456 d906 seed is packaged", read_file(runtime_root + "/" + ffrp_seed_rel(4, 5, 6)) != nil)
failures += package_expect("rect leverage audit is current", ffrpp_default_leverage(346) == 1679 && ffrpp_default_leverage(347) == 1458 && ffrpp_default_leverage(445) == 1411 && ffrpp_default_leverage(356) == 1638)
failures += package_expect("generic GPU worker is packaged", read_file(ffb_source_path(runtime_root, 5)) != nil)
failures += package_expect_generic_partner_guard(runtime_root, "333")
failures += package_expect_generic_partner_guard(runtime_root, "444")
failures += package_expect_generic_partner_guard(runtime_root, "555")
failures += package_expect_generic_partner_guard(runtime_root, "666")
failures += package_expect_generic_partner_guard(runtime_root, "777")
failures += package_expect("generated Metal sidecar is not packaged", read_file(runtime_root + "/kernels/generic/cal2zone_555.metal") == nil)
failures += package_expect("C3 worker is packaged", read_file(ffc3_source_path(runtime_root, 5)) != nil)
failures += package_expect("SIMD worker is packaged", read_file(ffsimd_source_path(runtime_root, 5)) != nil)
failures += package_expect("rectangular worker is packaged", read_file(ffrgb_source_path(runtime_root, 2, 2, 5)) != nil)
failures += package_expect_rect_partner_guard(runtime_root, "225")
failures += package_expect("226 GPU geometry is packaged", ffrgb_geometry_valid(2, 2, 6) == 1 && ffrgb_cap(2, 2, 6) == 64 && ffrgb_shared_bytes(2, 2, 6) == 12288)
failures += package_expect_rect_partner_guard(runtime_root, "226")
failures += package_expect("346 GPU geometry is packaged", ffrgb_geometry_valid(3, 4, 6) == 1 && ffrgb_cap(3, 4, 6) == 104 && ffrgb_shared_bytes(3, 4, 6) == 19968)
failures += package_expect_rect_partner_guard(runtime_root, "346")
source346 = read_file(ffrgb_source_path(runtime_root, 3, 4, 6))
failures += package_expect("346 GPU masks and exact gate are packaged", source346 != nil && source346.include?("u1 = u1 & 4095") && source346.include?("u1 = u1 & 16777215") && source346.include?("u1 = u1 & 262143") && source346.include?("while ai < ab") && source346.include?("while bi < bb") && source346.include?("while ci < cb") && source346.include?("if got != want"))
failures += package_expect("347 GPU geometry is packaged", ffrgb_geometry_valid(3, 4, 7) == 1 && ffrgb_cap(3, 4, 7) == 116 && ffrgb_shared_bytes(3, 4, 7) == 22272)
failures += package_expect_rect_partner_guard(runtime_root, "347")
source347 = read_file(ffrgb_source_path(runtime_root, 3, 4, 7))
failures += package_expect("347 GPU masks and exact gate are packaged", source347 != nil && source347.include?("u1 = u1 & 4095") && source347.include?("u1 = u1 & 268435455") && source347.include?("u1 = u1 & 2097151") && source347.include?("while ai < ab") && source347.include?("while bi < bb") && source347.include?("while ci < cb") && source347.include?("if got != want"))
failures += package_expect("356 GPU geometry is packaged", ffrgb_geometry_valid(3, 5, 6) == 1 && ffrgb_cap(3, 5, 6) == 122 && ffrgb_shared_bytes(3, 5, 6) == 23424)
failures += package_expect_rect_partner_guard(runtime_root, "356")
source356 = read_file(ffrgb_source_path(runtime_root, 3, 5, 6))
failures += package_expect("356 GPU masks and exact gate are packaged", source356 != nil && source356.include?("u1 = u1 & 32767") && source356.include?("u1 = u1 & 1073741823") && source356.include?("u1 = u1 & 262143") && source356.include?("while ai < ab") && source356.include?("while bi < bb") && source356.include?("while ci < cb") && source356.include?("if got != want"))
failures += package_expect("446 GPU geometry is packaged", ffrgb_geometry_valid(4, 4, 6) == 1 && ffrgb_cap(4, 4, 6) == 128 && ffrgb_wpg(4, 4, 6) == 16 && ffrgb_mask_bytes(4, 4, 6) == 4 && ffrgb_shared_bytes(4, 4, 6) == 24576)
failures += package_expect_rect_partner_guard(runtime_root, "446")
source446 = read_file(ffrgb_source_path(runtime_root, 4, 4, 6))
failures += package_expect("446 GPU masks and exact gate are packaged", source446 != nil && source446.include?("u1 = u1 & 65535") && source446.include?("u1 = u1 & 16777215") && source446.include?("while ai < ab") && source446.include?("while bi < bb") && source446.include?("while ci < cb") && source446.include?("if got != want"))
failures += package_expect("456 GPU geometry is packaged", ffrgb_geometry_valid(4, 5, 6) == 1 && ffrgb_cap(4, 5, 6) == 152 && ffrgb_wpg(4, 5, 6) == 16 && ffrgb_mask_bytes(4, 5, 6) == 4 && ffrgb_shared_bytes(4, 5, 6) == 29184)
failures += package_expect_rect_partner_guard(runtime_root, "456")
source456 = read_file(ffrgb_source_path(runtime_root, 4, 5, 6))
failures += package_expect("456 GPU masks and exact gate are packaged", source456 != nil && source456.include?("u1 = u1 & 1048575") && source456.include?("u1 = u1 & 1073741823") && source456.include?("u1 = u1 & 16777215") && source456.include?("while ai < ab") && source456.include?("while bi < bb") && source456.include?("while ci < cb") && source456.include?("if got != want"))
failures += package_expect("457 wide GPU geometry is packaged", ffrgb_geometry_valid(4, 5, 7) == 1 && ffrgb_cap(4, 5, 7) == 168 && ffrgb_wpg(4, 5, 7) == 8 && ffrgb_mask_bytes(4, 5, 7) == 8 && ffrgb_shared_bytes(4, 5, 7) == 32256)
failures += package_expect_rect_partner_guard(runtime_root, "457")
source457 = read_file(ffrgb_source_path(runtime_root, 4, 5, 7))
failures += package_expect("457 full-width masks and exact gate are packaged", source457 != nil && source457.include?("## i64[]: work_us") && source457.include?("gpu.shared_i64(1344)") && source457.include?("sample2 = state ## u32") && source457.include?("u1 = u1 & 1048575") && source457.include?("u1 = u1 & 34359738367") && source457.include?("u1 = u1 & 268435455") && source457.include?("metal_buffer_write_i64(seed_us") && source457.include?("metal_buffer_read_i64(best_us") && source457.include?("while ai < ab") && source457.include?("while bi < bb") && source457.include?("while ci < cb") && source457.include?("if got != want"))
failures += package_expect_rect_partner_guard(runtime_root, "234")
failures += package_expect_rect_partner_guard(runtime_root, "235")
failures += package_expect_rect_partner_guard(runtime_root, "245")
failures += package_expect_rect_partner_guard(runtime_root, "256")
failures += package_expect_rect_partner_guard(runtime_root, "334")
failures += package_expect_rect_partner_guard(runtime_root, "335")
failures += package_expect_rect_partner_guard(runtime_root, "344")
failures += package_expect_rect_partner_guard(runtime_root, "345")
failures += package_expect_rect_partner_guard(runtime_root, "355")
failures += package_expect_rect_partner_guard(runtime_root, "445")
failures += package_expect("seed provenance manifest is packaged", read_file(runtime_root + "/manifests/seeds.tsv") != nil)
failures += package_expect("CLI source is packaged", read_file(package_root + "/bin/metaflip.w") != nil)
launcher_source = read_file(package_root + "/bin/metaflip")
failures += package_expect("source-checkout launcher targets CLI entry", launcher_source != nil && launcher_source.include?("metaflip.w") && launcher_source.include?("metaflip-cli"))
failures += package_expect("public library entry is packaged", read_file(package_root + "/lib/metaflip.w") != nil)
failures += package_expect("rank-down endpoint compiler is packaged", read_file(runtime_root + "/strategies/rect_endpoint_rankdown.w") != nil)
failures += package_expect("rank-two endpoint compiler is packaged", read_file(runtime_root + "/strategies/rect_endpoint_rankdown2.w") != nil)
failures += package_expect("four-line catalyst compiler is packaged", read_file(runtime_root + "/strategies/rect_catalyst_lift2.w") != nil)
failures += package_expect("double-annihilation macro is packaged", read_file(runtime_root + "/strategies/macro_double_annihilation.w") != nil)
failures += package_expect("block-interior selector is packaged", read_file(runtime_root + "/strategies/block_interior.w") != nil)
failures += package_expect("pooled exact strategies are packaged", read_file(runtime_root + "/strategies/mode_locked.w") != nil && read_file(runtime_root + "/strategies/debt_mitm.w") != nil && read_file(runtime_root + "/strategies/dynamic_syzygy.w") != nil)
failures += package_expect("pooled exact worker is packaged", read_file(runtime_root + "/kernels/workers/pooled_exact.w") != nil && read_file(runtime_root + "/kernels/pooled_exact.w") != nil && read_file(runtime_root + "/kernels/bundles/pooled_exact.w") != nil)
failures += package_expect("best provenance module is packaged", read_file(runtime_root + "/fleet/provenance.w") != nil)
fleet_source = read_file(runtime_root + "/fleet.w")
failures += package_expect("block selector participates in worker freshness", fleet_source != nil && fleet_source.include?("span_block_interior"))
rect_campaign_source = read_file(runtime_root + "/rect/campaign.w")
failures += package_expect("persistent rectangular CPU pool is packaged and linked", read_file(runtime_root + "/rect/cpu_pool.w") != nil && rect_campaign_source != nil && rect_campaign_source.include?("use cpu_pool"))
failures += package_expect("generated CUDA is not packaged", read_file(runtime_root + "/kernels/generic/cal2zone_555.cu") == nil)

compiler = ffmc_tungsten(runtime_root)
failures += package_expect("compiler resolver returns a command", compiler != "")

build_command = ffb_build_command(runtime_root, 5, "/tmp/metaflip_layout_test_worker")
failures += package_expect("build command uses packaged source", build_command.include?("kernels/generic/cal2zone_555.w"))
failures += package_expect("build command has no monorepo path", !build_command.include?("benchmarks/matmul/metaflip"))
failures += package_expect("native flag removed", !build_command.include?("--native"))
failures += package_expect("runtime compile suppresses incidental dialects", build_command.include?("TUNGSTEN_GPU_DIALECTS=none"))
failures += package_expect("runtime Metal output uses worker cache", build_command.include?("/tmp/metaflip_layout_test_worker.metal"))
exact_build_command = ffpeb_build_command(runtime_root, "/tmp/metaflip_layout_test_exact")
failures += package_expect("pooled exact build is pure Tungsten CPU", exact_build_command.include?("kernels/workers/pooled_exact.w") && exact_build_command.include?("TUNGSTEN_GPU_DIALECTS=none") && !exact_build_command.include?("benchmarks/matmul/metaflip"))

if failures > 0
  << "metaflip package layout: " + failures.to_s() + " failure(s)"
  exit(1)

<< "metaflip package layout: ok"
