use flipfleet_block_leaf_pool

# Exhaustive ordered-allocation companion to `flipfleet_block_compose.w`.
# The ordinary CLI scans balanced four-way splits; this research CLI scans all
# entries from 3 through 8 and all unique S3 source orderings.
#
#   flipfleet-block-unbalanced-compose 26x32x32
#   flipfleet-block-unbalanced-compose 26x32x32 OUTPUT
#
# With OUTPUT, the winning formula is materialised, parity-compacted, exact-
# verified, oriented to the requested dimensions, and written as decimal R
# triples.  Without OUTPUT, only the formula search is performed.

-> ffbu_parse_target(text, dims) (String i64[]) i64
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
if av.size() != 1 && av.size() != 2
  << "usage: flipfleet-block-unbalanced-compose NxMxP [OUTPUT]"
  exit(1)

dims = i64[3]
if ffbu_parse_target(av[0], dims) != 1
  << "target dimensions must each be in 12..32"
  exit(1)

root = "benchmarks/matmul/metaflip/"
outer = ffbc_load_exact(root + "matmul_4x4_rank47_d450_gf2.txt", 4, 4, 4, 128)
if outer == nil
  << "invalid or missing rank-47 outer"
  exit(1)
leaves = ffbcp_stable_3_to_8(root)
if leaves.size() != 56
  << "incomplete stable 3--8 leaf pool"
  exit(1)

recipe = ffbc_best_oriented_bounded_recipe(outer, dims[0], dims[1], dims[2], 3, 8, leaves)
if recipe == nil
  << "no bounded recipe"
  exit(1)

row = "target " + dims[0].to_s() + "x" + dims[1].to_s() + "x" + dims[2].to_s()
row = row + " formula " + recipe[3].to_s()
row = row + " source " + recipe[4].to_s() + "x" + recipe[5].to_s() + "x" + recipe[6].to_s()
row = row + " s3 " + recipe[7].to_s()
<< row
<< "allocation " + recipe[0].join(",") + " | " + recipe[1].join(",") + " | " + recipe[2].join(",")

if av.size() == 2
  result = ffbc_compose_oriented_recipe(outer, dims[0], dims[1], dims[2], leaves, recipe)
  if result == nil || ffbc_verify_exact(result) != 1
    << "composition or exact reconstruction failed"
    exit(1)
  written = ffbc_write(av[1], result) ## i64
  if written != result.rank()
    << "write failed: " + av[1]
    exit(1)
  << "exact rank " + result.rank().to_s() + " -> " + av[1]
