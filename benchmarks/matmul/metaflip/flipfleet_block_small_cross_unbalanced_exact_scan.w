use flipfleet_block_leaf_pool

# Exact-materialize every layout whose bounded formula improves its balanced
# formula in the complete small-cross closure.  Formula scoring alone cannot
# see mapped-zero and duplicate-parity cancellation, so this second gate can
# promote a near miss without searching unrelated layouts.

-> ffbscues_parse_dims(text, dims) (String i64[]) i64
  fields = text.split("x")
  if fields.size() != 3
    return 0
  i = 0 ## i64
  while i < 3
    dims[i] = fields[i].to_i()
    i += 1
  1

-> ffbscues_parse_allocation(text) (String)
  fields = text.split(",")
  if fields.size() != 4
    return nil
  result = i64[4]
  i = 0 ## i64
  while i < 4
    result[i] = fields[i].to_i()
    if result[i] < 2 || result[i] > 8
      return nil
    i += 1
  result

-> ffbscues_status(baseline, rank) (String i64)
  if baseline.size() == 0
    return "uncovered"
  value = baseline.to_i() ## i64
  if rank < value
    return "win"
  if rank == value
    return "tie"
  "loss"

-> ffbscues_gain(baseline, rank) (String i64)
  if baseline.size() == 0
    return ""
  (baseline.to_i() - rank).to_s()

av = argv()
shard_id = 0 ## i64
shard_count = 1 ## i64
if av.size() == 2
  shard_id = av[0].to_i()
  shard_count = av[1].to_i()
elsif av.size() != 0
  << "usage: ffbc-small-cross-unbalanced-exact shard-id shard-count"
  exit(1)
if shard_count < 1 || shard_id < 0 || shard_id >= shard_count
  << "invalid shard"
  exit(1)

root = "benchmarks/matmul/metaflip/"
outer = ffbc_load_exact(root + "matmul_4x4_rank47_d450_gf2.txt", 4, 4, 4, 128)
leaves = ffbcp_stable_2_to_8(root)
audit = read_file(root + "block_composition_small_cross_unbalanced_full_audit.tsv")
if outer == nil || leaves.size() != 84 || audit == nil
  << "invalid outer, leaf pool, or unbalanced audit"
  exit(1)

header = "target\tbalanced_formula\tbounded_formula\texact_rank\tformula_improvement\tcancellation"
header = header + "\tf2_status\tf2_baseline\tf2_gain"
header = header + "\tuniversal_status\tuniversal_baseline\tuniversal_gain"
header = header + "\tchar0_status\tchar0_baseline\tchar0_gain"
header = header + "\tany_field_status\tany_field_baseline\tany_field_gain"
header = header + "\talloc_n\talloc_m\talloc_p\tsource\ts3_code"
<< header

lines = audit.split("\n")
improved_index = 0 ## i64
checked = 0 ## i64
exact_cancellations = 0 ## i64
i = 1 ## i64
while i < lines.size()
  if lines[i].size() > 0
    fields = lines[i].split("\t")
    if fields.size() != 21
      << "malformed full audit row " + i.to_s()
      exit(1)
    if fields[3].to_i() > 0
      if improved_index % shard_count == shard_id
        target_dims = i64[3]
        source_dims = i64[3]
        alloc_n = ffbscues_parse_allocation(fields[16])
        alloc_m = ffbscues_parse_allocation(fields[17])
        alloc_p = ffbscues_parse_allocation(fields[18])
        if ffbscues_parse_dims(fields[0], target_dims) != 1 || ffbscues_parse_dims(fields[19], source_dims) != 1 || alloc_n == nil || alloc_m == nil || alloc_p == nil
          << "malformed improved recipe " + fields[0]
          exit(1)
        recipe = [alloc_n, alloc_m, alloc_p, fields[2].to_i(), source_dims[0], source_dims[1], source_dims[2], fields[20].to_i()]
        result = ffbc_compose_oriented_recipe(outer, target_dims[0], target_dims[1], target_dims[2], leaves, recipe)
        if result == nil || ffbc_verify_exact(result) != 1 || result.rank() > fields[2].to_i()
          << "exact materialization failed " + fields[0]
          exit(1)
        exact_rank = result.rank() ## i64
        cancellation = fields[2].to_i() - exact_rank ## i64
        if cancellation > 0
          exact_cancellations += 1
        row = fields[0] + "\t" + fields[1] + "\t" + fields[2] + "\t" + exact_rank.to_s()
        row = row + "\t" + fields[3] + "\t" + cancellation.to_s()
        row = row + "\t" + ffbscues_status(fields[5], exact_rank) + "\t" + fields[5] + "\t" + ffbscues_gain(fields[5], exact_rank)
        row = row + "\t" + ffbscues_status(fields[8], exact_rank) + "\t" + fields[8] + "\t" + ffbscues_gain(fields[8], exact_rank)
        row = row + "\t" + ffbscues_status(fields[11], exact_rank) + "\t" + fields[11] + "\t" + ffbscues_gain(fields[11], exact_rank)
        row = row + "\t" + ffbscues_status(fields[14], exact_rank) + "\t" + fields[14] + "\t" + ffbscues_gain(fields[14], exact_rank)
        row = row + "\t" + fields[16] + "\t" + fields[17] + "\t" + fields[18] + "\t" + fields[19] + "\t" + fields[20]
        << row
        checked += 1
      improved_index += 1
  i += 1

summary = "SUMMARY shard=" + shard_id.to_s() + "/" + shard_count.to_s()
summary = summary + " checked=" + checked.to_s() + " cancellations=" + exact_cancellations.to_s()
<< summary
