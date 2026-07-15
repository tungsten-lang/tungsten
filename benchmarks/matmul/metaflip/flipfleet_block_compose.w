use flipfleet_block_composer

# Pure-Tungsten CLI for support-aware rank-47 outer composition.
#
#   flipfleet-block-compose 13x13 OUT
#   flipfleet-block-compose 12x16x17 OUT 3,3,3,3 4,4,4,4 4,4,4,5
#
# `NxN` is the square-tensor shorthand for <N,N,N>.  With no explicit
# allocations the CLI scans every balanced 4-way placement and S3 ordering,
# then materialises every minimum-formula tie to select the lowest exact rank.

-> ffbc_cli_usage() i64
  << "usage: flipfleet-block-compose NxN|NxMxP OUTPUT; optional: ALLOC-N ALLOC-M ALLOC-P"
  << "       allocations are four comma-separated nonnegative integers"
  0 - 1

-> ffbc_cli_parse_target(text, dims) (String i64[]) i64
  fields = text.split("x")
  if fields.size() == 1
    n = fields[0].to_i() ## i64
    if n < 1
      return 0
    dims[0] = n
    dims[1] = n
    dims[2] = n
    return 1
  if fields.size() == 2 && fields[0] == fields[1]
    n = fields[0].to_i() ## i64
    if n < 1
      return 0
    dims[0] = n
    dims[1] = n
    dims[2] = n
    return 1
  if fields.size() == 3
    i = 0 ## i64
    while i < 3
      value = fields[i].to_i() ## i64
      if value < 1
        return 0
      dims[i] = value
      i += 1
    return 1
  0

-> ffbc_cli_parse_allocation(text, expected_parts, expected_sum) (String i64 i64)
  fields = text.split(",")
  if fields.size() != expected_parts
    return nil
  result = i64[expected_parts]
  sum = 0 ## i64
  i = 0 ## i64
  while i < expected_parts
    value = fields[i].to_i() ## i64
    if value < 0
      return nil
    result[i] = value
    sum += value
    i += 1
  if sum != expected_sum
    return nil
  result

-> ffbc_cli_add_leaf(root, path, n, m, p, leaves)
  full = root + path
  if read_file(full) == nil
    return 0
  leaf = ffbc_load_exact(full, n, m, p, 4096)
  if leaf == nil
    << "invalid default leaf: " + full
    exit(1)
  leaves.push(leaf)
  1

av = argv()
if av.size() != 2 && av.size() != 5
  exit(ffbc_cli_usage())

dims = i64[3]
if ffbc_cli_parse_target(av[0], dims) != 1
  << "invalid target: " + av[0]
  exit(ffbc_cli_usage())
output_path = av[1]
root = "benchmarks/matmul/metaflip/"

outer_path = root + "matmul_4x4_rank47_d450_gf2.txt"
outer = ffbc_load_exact(outer_path, 4, 4, 4, 128)
if outer == nil
  << "invalid or missing rank-47 outer: " + outer_path
  exit(1)

leaves = []
# The two smallest leaves close the balanced 8--11 scan.  Larger production
# recipes never select them, so their stable-first placement does not perturb
# any existing 12--32 certificate.
ffbc_cli_add_leaf(root, "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, leaves)
ffbc_cli_add_leaf(root, "matmul_2x2x3_rank11_catalog_gf2.txt", 2, 2, 3, leaves)
# A complete exact two-wide pool closes balanced and explicit allocations in
# which the other axes contribute blocks through size eight.
ffbc_cli_add_leaf(root, "matmul_2x2x4_rank14_strassen_blocks_gf2.txt", 2, 2, 4, leaves)
ffbc_cli_add_leaf(root, "matmul_2x2x5_rank18_blocks_gf2.txt", 2, 2, 5, leaves)
ffbc_cli_add_leaf(root, "matmul_2x2x6_rank21_strassen_blocks_gf2.txt", 2, 2, 6, leaves)
ffbc_cli_add_leaf(root, "matmul_2x2x7_rank25_catalog_gf2.txt", 2, 2, 7, leaves)
ffbc_cli_add_leaf(root, "matmul_2x2x8_rank28_catalog_gf2.txt", 2, 2, 8, leaves)
ffbc_cli_add_leaf(root, "matmul_2x3x3_rank15_catalog_gf2.txt", 2, 3, 3, leaves)
ffbc_cli_add_leaf(root, "matmul_2x3x4_rank20_catalog_gf2.txt", 2, 3, 4, leaves)
ffbc_cli_add_leaf(root, "matmul_2x3x5_rank25_d160_fleet_gf2.txt", 2, 3, 5, leaves)
ffbc_cli_add_leaf(root, "matmul_2x3x6_rank30_catalog_gf2.txt", 2, 3, 6, leaves)
ffbc_cli_add_leaf(root, "matmul_2x3x7_rank35_catalog_gf2.txt", 2, 3, 7, leaves)
ffbc_cli_add_leaf(root, "matmul_2x3x8_rank40_catalog_gf2.txt", 2, 3, 8, leaves)
ffbc_cli_add_leaf(root, "matmul_2x4x4_rank26_catalog_gf2.txt", 2, 4, 4, leaves)
ffbc_cli_add_leaf(root, "matmul_2x4x5_rank33_catalog_gf2.txt", 2, 4, 5, leaves)
ffbc_cli_add_leaf(root, "matmul_2x4x6_rank39_catalog_gf2.txt", 2, 4, 6, leaves)
ffbc_cli_add_leaf(root, "matmul_2x4x7_rank45_catalog_gf2.txt", 2, 4, 7, leaves)
ffbc_cli_add_leaf(root, "matmul_2x4x8_rank51_catalog_gf2.txt", 2, 4, 8, leaves)
ffbc_cli_add_leaf(root, "matmul_2x5x5_rank40_catalog_gf2.txt", 2, 5, 5, leaves)
ffbc_cli_add_leaf(root, "matmul_2x5x6_rank47_catalog_gf2.txt", 2, 5, 6, leaves)
ffbc_cli_add_leaf(root, "matmul_2x5x7_rank55_catalog_gf2.txt", 2, 5, 7, leaves)
ffbc_cli_add_leaf(root, "matmul_2x5x8_rank63_catalog_gf2.txt", 2, 5, 8, leaves)
ffbc_cli_add_leaf(root, "matmul_2x6x6_rank56_catalog_gf2.txt", 2, 6, 6, leaves)
ffbc_cli_add_leaf(root, "matmul_2x6x7_rank66_catalog_gf2.txt", 2, 6, 7, leaves)
ffbc_cli_add_leaf(root, "matmul_2x6x8_rank75_catalog_gf2.txt", 2, 6, 8, leaves)
ffbc_cli_add_leaf(root, "matmul_2x7x7_rank76_catalog_gf2.txt", 2, 7, 7, leaves)
ffbc_cli_add_leaf(root, "matmul_2x7x8_rank88_catalog_gf2.txt", 2, 7, 8, leaves)
ffbc_cli_add_leaf(root, "matmul_2x8x8_rank100_catalog_gf2.txt", 2, 8, 8, leaves)
ffbc_cli_add_leaf(root, "matmul_3x3_rank23_d139_gf2.txt", 3, 3, 3, leaves)
ffbc_cli_add_leaf(root, "matmul_3x3x4_rank29_gf2.txt", 3, 3, 4, leaves)
ffbc_cli_add_leaf(root, "matmul_3x3x5_rank36_gf2.txt", 3, 3, 5, leaves)
ffbc_cli_add_leaf(root, "matmul_3x4x4_rank38_gf2.txt", 3, 4, 4, leaves)
ffbc_cli_add_leaf(root, "matmul_3x4x5_rank47_gf2.txt", 3, 4, 5, leaves)
ffbc_cli_add_leaf(root, "matmul_3x5x5_rank58_gf2.txt", 3, 5, 5, leaves)
ffbc_cli_add_leaf(root, "matmul_4x4_rank47_d450_gf2.txt", 4, 4, 4, leaves)
# Stable catalog leaves precede mutable campaign checkpoints.  Because leaf
# selection replaces only on strict rank improvement, an equal-rank checkpoint
# cannot perturb reproducible compositions; a genuine lower rank is consumed.
ffbc_cli_add_leaf(root, "matmul_4x4x5_rank60_catalog_gf2.txt", 4, 4, 5, leaves)
ffbc_cli_add_leaf("", "flipfleet_4x4x5_best.txt", 4, 4, 5, leaves)
ffbc_cli_add_leaf(root, "matmul_4x5x5_rank76_catalog_gf2.txt", 4, 5, 5, leaves)
ffbc_cli_add_leaf("", "flipfleet_4x5x5_best.txt", 4, 5, 5, leaves)
ffbc_cli_add_leaf(root, "matmul_5x5_rank93_catalog_perminov_c843_gf2.txt", 5, 5, 5, leaves)
ffbc_cli_add_leaf(root, "matmul_5x5_rank93_catalog_alphaevolve_gf2.txt", 5, 5, 5, leaves)
# Cross-range leaves make the pool complete for every sorted shape over block
# sizes 3--8.  Without them, scans below 21 and above 20 left an artificial
# seam even though some supported recipes happened not to touch a missing
# 3/4-by-6/7/8 sub-shape.
ffbc_cli_add_leaf(root, "matmul_3x3x6_rank42_catalog_gf2.txt", 3, 3, 6, leaves)
ffbc_cli_add_leaf(root, "matmul_3x3x7_rank49_catalog_gf2.txt", 3, 3, 7, leaves)
ffbc_cli_add_leaf(root, "matmul_3x3x8_rank56_catalog_gf2.txt", 3, 3, 8, leaves)
ffbc_cli_add_leaf(root, "matmul_3x4x6_rank54_catalog_gf2.txt", 3, 4, 6, leaves)
ffbc_cli_add_leaf(root, "matmul_3x4x7_rank64_catalog_gf2.txt", 3, 4, 7, leaves)
ffbc_cli_add_leaf(root, "matmul_3x4x8_rank73_catalog_gf2.txt", 3, 4, 8, leaves)
ffbc_cli_add_leaf(root, "matmul_3x5x6_rank68_catalog_gf2.txt", 3, 5, 6, leaves)
ffbc_cli_add_leaf(root, "matmul_3x5x7_rank79_catalog_gf2.txt", 3, 5, 7, leaves)
ffbc_cli_add_leaf(root, "matmul_3x5x8_rank90_catalog_gf2.txt", 3, 5, 8, leaves)
ffbc_cli_add_leaf(root, "matmul_3x6x6_rank82_catalog_gf2.txt", 3, 6, 6, leaves)
ffbc_cli_add_leaf(root, "matmul_3x6x7_rank96_catalog_gf2.txt", 3, 6, 7, leaves)
ffbc_cli_add_leaf(root, "matmul_3x6x8_rank108_catalog_gf2.txt", 3, 6, 8, leaves)
ffbc_cli_add_leaf(root, "matmul_3x7x7_rank111_catalog_gf2.txt", 3, 7, 7, leaves)
ffbc_cli_add_leaf(root, "matmul_3x7x8_rank128_catalog_gf2.txt", 3, 7, 8, leaves)
ffbc_cli_add_leaf(root, "matmul_3x8x8_rank146_catalog_gf2.txt", 3, 8, 8, leaves)
ffbc_cli_add_leaf(root, "matmul_4x4x6_rank73_catalog_gf2.txt", 4, 4, 6, leaves)
ffbc_cli_add_leaf(root, "matmul_4x4x7_rank85_catalog_gf2.txt", 4, 4, 7, leaves)
ffbc_cli_add_leaf(root, "matmul_4x4x8_rank96_catalog_gf2.txt", 4, 4, 8, leaves)
ffbc_cli_add_leaf(root, "matmul_4x5x6_rank90_catalog_gf2.txt", 4, 5, 6, leaves)
ffbc_cli_add_leaf(root, "matmul_4x5x7_rank104_catalog_gf2.txt", 4, 5, 7, leaves)
ffbc_cli_add_leaf(root, "matmul_4x5x8_rank118_catalog_gf2.txt", 4, 5, 8, leaves)
ffbc_cli_add_leaf(root, "matmul_4x6x6_rank105_catalog_gf2.txt", 4, 6, 6, leaves)
ffbc_cli_add_leaf(root, "matmul_4x6x7_rank123_catalog_gf2.txt", 4, 6, 7, leaves)
ffbc_cli_add_leaf(root, "matmul_4x6x8_rank140_catalog_gf2.txt", 4, 6, 8, leaves)
ffbc_cli_add_leaf(root, "matmul_4x7x7_rank144_catalog_gf2.txt", 4, 7, 7, leaves)
ffbc_cli_add_leaf(root, "matmul_4x7x8_rank161_catalog_gf2.txt", 4, 7, 8, leaves)
ffbc_cli_add_leaf(root, "matmul_4x8x8_rank180_catalog_gf2.txt", 4, 8, 8, leaves)
ffbc_cli_add_leaf(root, "matmul_5x5x6_rank110_catalog_gf2.txt", 5, 5, 6, leaves)
ffbc_cli_add_leaf(root, "matmul_5x5x7_rank127_catalog_gf2.txt", 5, 5, 7, leaves)
ffbc_cli_add_leaf(root, "matmul_5x5x8_rank144_catalog_gf2.txt", 5, 5, 8, leaves)
ffbc_cli_add_leaf(root, "matmul_5x6x6_rank130_catalog_gf2.txt", 5, 6, 6, leaves)
ffbc_cli_add_leaf(root, "matmul_5x6x7_rank150_catalog_gf2.txt", 5, 6, 7, leaves)
ffbc_cli_add_leaf(root, "matmul_5x6x8_rank170_catalog_gf2.txt", 5, 6, 8, leaves)
ffbc_cli_add_leaf(root, "matmul_5x7x7_rank176_catalog_gf2.txt", 5, 7, 7, leaves)
ffbc_cli_add_leaf(root, "matmul_5x7x8_rank204_catalog_gf2.txt", 5, 7, 8, leaves)
ffbc_cli_add_leaf(root, "matmul_5x8x8_rank230_catalog_gf2.txt", 5, 8, 8, leaves)
ffbc_cli_add_leaf(root, "matmul_6x6_rank153_catalog_gf2.txt", 6, 6, 6, leaves)
ffbc_cli_add_leaf(root, "matmul_6x6x7_rank183_catalog_gf2.txt", 6, 6, 7, leaves)
ffbc_cli_add_leaf(root, "matmul_6x6x8_rank203_catalog_gf2.txt", 6, 6, 8, leaves)
ffbc_cli_add_leaf(root, "matmul_6x7x7_rank212_catalog_gf2.txt", 6, 7, 7, leaves)
ffbc_cli_add_leaf(root, "matmul_6x7x8_rank238_catalog_gf2.txt", 6, 7, 8, leaves)
ffbc_cli_add_leaf(root, "matmul_6x8x8_rank266_catalog_gf2.txt", 6, 8, 8, leaves)
ffbc_cli_add_leaf(root, "matmul_7x7_rank247_d3554_outer_isotropy_gf2.txt", 7, 7, 7, leaves)
ffbc_cli_add_leaf(root, "matmul_7x7x8_rank278_catalog_gf2.txt", 7, 7, 8, leaves)
ffbc_cli_add_leaf(root, "matmul_7x8x8_rank310_catalog_gf2.txt", 7, 8, 8, leaves)
ffbc_cli_add_leaf(root, "matmul_8x8_rank329_catalog_gf2.txt", 8, 8, 8, leaves)

alloc_n = nil
alloc_m = nil
alloc_p = nil
nominal = 0 ## i64
source_n = dims[0] ## i64
source_m = dims[1] ## i64
source_p = dims[2] ## i64
orientation = 0 ## i64
recipe = nil
if av.size() == 5
  alloc_n = ffbc_cli_parse_allocation(av[2], outer.n(), dims[0])
  alloc_m = ffbc_cli_parse_allocation(av[3], outer.m(), dims[1])
  alloc_p = ffbc_cli_parse_allocation(av[4], outer.p(), dims[2])
  if alloc_n == nil || alloc_m == nil || alloc_p == nil
    << "invalid allocation: length must be four and sums must match the target"
    exit(1)
  nominal = ffbc_score_allocation(outer, alloc_n, alloc_m, alloc_p, leaves)
else
  recipe = ffbc_best_exact_oriented_balanced_recipe(outer, dims[0], dims[1], dims[2], leaves)
  if recipe == nil
    << "no S3-balanced recipe: the default pool lacks at least one required leaf shape"
    exit(1)
  alloc_n = recipe[0]
  alloc_m = recipe[1]
  alloc_p = recipe[2]
  nominal = recipe[3]
  source_n = recipe[4]
  source_m = recipe[5]
  source_p = recipe[6]
  orientation = recipe[7]

if nominal < 1
  << "unsupported recipe: add exact oriented leaves for every induced sub-shape"
  exit(1)

<< "target <" + dims[0].to_s() + "," + dims[1].to_s() + "," + dims[2].to_s() + ">"
if orientation != 0
  << "source <" + source_n.to_s() + "," + source_m.to_s() + "," + source_p.to_s() + ">; S3 code " + orientation.to_s()
<< "allocation " + alloc_n.join(",") + " | " + alloc_m.join(",") + " | " + alloc_p.join(",")
<< "formula rank " + nominal.to_s()

if av.size() == 5
  result = ffbc_compose(outer, alloc_n, alloc_m, alloc_p, leaves)
else
  result = ffbc_compose_oriented_recipe(outer, dims[0], dims[1], dims[2], leaves, recipe)
if result == nil
  << "composition or exact reconstruction failed"
  exit(1)
written = ffbc_write(output_path, result) ## i64
if written != result.rank()
  << "write failed: " + output_path
  exit(1)
<< "exact rank " + result.rank().to_s() + " -> " + output_path
