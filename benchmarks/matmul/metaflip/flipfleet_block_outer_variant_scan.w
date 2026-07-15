use flipfleet_block_leaf_pool

# Scan either exact rank-47 4x4x4 frontier component as a support-aware outer.
# Run d450 and d677 separately and join rows by target.
#
#   outer-variant-scan d450 balanced
#   outer-variant-scan d677 balanced
#   outer-variant-scan d450 upper
#   outer-variant-scan d677 upper
#   outer-variant-scan d677 target 26x32x32 exact
#
# `balanced` covers all 1,771 sorted targets in 12..32.  `upper` exhausts all
# ordered 3..8 four-part allocations and all unique S3 source orientations for
# the 84 sorted targets in 26..32.

-> ffbov_parse_target(text, dims) (String i64[]) i64
  fields = text.split("x")
  if fields.size() != 3
    return 0
  i = 0 ## i64
  while i < 3
    value = fields[i].to_i() ## i64
    if value < 12 || value > 32
      return 0
    dims[i] = value
    i += 1
  1

av = argv()
if av.size() < 2 || av.size() > 4
  << "usage: outer-variant-scan <d450|d677> <balanced|upper|target> [NxMxP] [exact]"
  exit(1)
outer_name = av[0]
scan = av[1]
if outer_name != "d450" && outer_name != "d677"
  << "outer must be d450 or d677"
  exit(1)
if scan != "balanced" && scan != "upper" && scan != "target"
  << "scan must be balanced, upper, or target"
  exit(1)

root = "benchmarks/matmul/metaflip/"
outer_path = "matmul_4x4_rank47_d450_gf2.txt"
if outer_name == "d677"
  outer_path = "matmul_4x4_rank47_d677_flips_gf2.txt"
outer = ffbc_load_exact(root + outer_path, 4, 4, 4, 128)
if outer == nil
  << "invalid rank-47 outer " + outer_path
  exit(1)
leaves = ffbcp_stable_3_to_8(root)
if leaves.size() != 56
  << "incomplete stable 3--8 leaf pool"
  exit(1)

<< "target\touter\tformula_rank\tallocation\tsource:s3\texact_rank"
targets = 0 ## i64
supported = 0 ## i64
unsupported = 0 ## i64
exact_checks = 0 ## i64

if scan == "target"
  if av.size() < 3
    << "target mode requires NxMxP"
    exit(1)
  dims = i64[3]
  if ffbov_parse_target(av[2], dims) != 1
    << "target dimensions must each be in 12..32"
    exit(1)
  recipe = ffbc_best_oriented_bounded_recipe(outer, dims[0], dims[1], dims[2], 3, 8, leaves)
  targets = 1
  if recipe == nil
    unsupported = 1
    << av[2] + "\t" + outer_name + "\tNA\tNA\tNA\tNA"
  else
    supported = 1
    row = av[2] + "\t" + outer_name + "\t" + recipe[3].to_s()
    row = row + "\t" + recipe[0].join(",") + "|" + recipe[1].join(",") + "|" + recipe[2].join(",")
    row = row + "\t" + recipe[4].to_s() + "x" + recipe[5].to_s() + "x" + recipe[6].to_s() + ":" + recipe[7].to_s()
    if av.size() == 4 && av[3] == "exact"
      result = ffbc_compose_oriented_recipe(outer, dims[0], dims[1], dims[2], leaves, recipe)
      if result == nil
        << "exact composition failed"
        exit(1)
      row = row + "\t" + result.rank().to_s()
      exact_checks = 1
    else
      row = row + "\tNA"
    << row
else
  first = 12 ## i64
  if scan == "upper"
    first = 26
  n = first ## i64
  while n <= 32
    m = n ## i64
    while m <= 32
      p = m ## i64
      while p <= 32
        recipe = nil
        if scan == "balanced"
          recipe = ffbc_best_oriented_balanced_recipe(outer, n, m, p, leaves)
        else
          recipe = ffbc_best_oriented_bounded_recipe(outer, n, m, p, 3, 8, leaves)
        targets += 1
        target = n.to_s() + "x" + m.to_s() + "x" + p.to_s()
        if recipe == nil
          unsupported += 1
          << target + "\t" + outer_name + "\tNA\tNA\tNA\tNA"
        else
          supported += 1
          row = target + "\t" + outer_name + "\t" + recipe[3].to_s()
          row = row + "\t" + recipe[0].join(",") + "|" + recipe[1].join(",") + "|" + recipe[2].join(",")
          row = row + "\t" + recipe[4].to_s() + "x" + recipe[5].to_s() + "x" + recipe[6].to_s() + ":" + recipe[7].to_s() + "\tNA"
          << row
        p += 1
      m += 1
    n += 1

<< "SUMMARY outer=" + outer_name + " scan=" + scan + " targets=" + targets.to_s() + " supported=" + supported.to_s() + " unsupported=" + unsupported.to_s() + " exact_checks=" + exact_checks.to_s()
