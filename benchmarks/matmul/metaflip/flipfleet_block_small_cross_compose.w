use flipfleet_block_leaf_pool

# Exhaustive ordered-allocation composer for the complete exact 2--8 leaf
# pool.  This is the small-dimension companion to the historical 3--8 tool:
# it permits concentrated splits such as 11=5+2+2+2 which the balanced scan
# cannot see.
#
#   flipfleet-block-small-cross-compose NxMxP [OUTPUT]

-> ffbsc_parse_target(text, dims) (String i64[]) i64
  fields = text.split("x")
  if fields.size() != 3
    return 0
  i = 0 ## i64
  while i < 3
    value = fields[i].to_i() ## i64
    if value < 8 || value > 32
      return 0
    dims[i] = value
    i += 1
  1

av = argv()
if av.size() != 1 && av.size() != 2
  << "usage: flipfleet-block-small-cross-compose NxMxP [OUTPUT]"
  exit(1)
dims = i64[3]
if ffbsc_parse_target(av[0], dims) != 1
  << "target dimensions must each be in 8..32"
  exit(1)

root = "benchmarks/matmul/metaflip/"
outer = ffbc_load_exact(root + "matmul_4x4_rank47_d450_gf2.txt", 4, 4, 4, 128)
leaves = ffbcp_stable_2_to_8(root)
if outer == nil || leaves.size() != 84
  << "invalid outer or incomplete 2--8 leaf pool"
  exit(1)

recipe = ffbc_best_oriented_bounded_recipe(outer, dims[0], dims[1], dims[2], 2, 8, leaves)
if recipe == nil
  << "no bounded 2--8 recipe"
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
  if ffbc_write(av[1], result) != result.rank()
    << "write failed: " + av[1]
    exit(1)
  << "exact rank " + result.rank().to_s() + " -> " + av[1]
