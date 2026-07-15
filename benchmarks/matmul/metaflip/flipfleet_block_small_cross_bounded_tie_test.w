use flipfleet_block_leaf_pool

-> ffbsbtt_parse_dims(text, dims) (String i64[]) i64
  fields = text.split("x")
  if fields.size() != 3
    return 0
  i = 0 ## i64
  while i < 3
    dims[i] = fields[i].to_i()
    i += 1
  1

-> ffbsbtt_parse_allocation(text)
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

root = "benchmarks/matmul/metaflip/"
outer = ffbc_load_exact(root + "matmul_4x4_rank47_d450_gf2.txt", 4, 4, 4, 128)
leaves = ffbcp_stable_2_to_8(root)
body = read_file(root + "block_composition_small_cross_bounded_tie_exact_audit.tsv")
if outer == nil || leaves.size() != 84 || body == nil
  << "FAIL bounded-tie inputs"
  exit(1)

lines = body.split("\n")
rows = 0 ## i64
ties = 0 ## i64
wins = 0 ## i64
co_records = 0 ## i64
losses = 0 ## i64
reduced = 0 ## i64
reduction_sum = 0 ## i64
certificates = 0 ## i64
i = 1 ## i64
while i < lines.size()
  if lines[i].size() > 0
    fields = lines[i].split("\t")
    if fields.size() != 17
      << "FAIL malformed bounded-tie row " + i.to_s()
      exit(1)
    formula = fields[1].to_i() ## i64
    exact = fields[2].to_i() ## i64
    reduction = fields[3].to_i() ## i64
    baseline = fields[4].to_i() ## i64
    formula_gap = fields[5].to_i() ## i64
    exact_gap = fields[6].to_i() ## i64
    if formula - exact != reduction || formula - baseline != formula_gap || exact - baseline != exact_gap
      << "FAIL rank arithmetic " + fields[0]
      exit(1)
    if formula_gap < 0 || formula_gap > 12 || fields[10].to_i() != 0
      << "FAIL closure range/parity " + fields[0]
      exit(1)
    ties += fields[8].to_i()
    if fields[7] == "win"
      wins += 1
    elsif fields[7] == "tie"
      co_records += 1
    elsif fields[7] == "loss"
      losses += 1
    else
      << "FAIL status " + fields[0]
      exit(1)

    if reduction > 0
      target_dims = i64[3]
      source_dims = i64[3]
      alloc_n = ffbsbtt_parse_allocation(fields[11])
      alloc_m = ffbsbtt_parse_allocation(fields[12])
      alloc_p = ffbsbtt_parse_allocation(fields[13])
      if ffbsbtt_parse_dims(fields[0], target_dims) != 1 || ffbsbtt_parse_dims(fields[14], source_dims) != 1 || alloc_n == nil || alloc_m == nil || alloc_p == nil
        << "FAIL reduction recipe parse " + fields[0]
        exit(1)
      source = ffbc_compose(outer, alloc_n, alloc_m, alloc_p, leaves)
      if source == nil || source.n() != source_dims[0] || source.m() != source_dims[1] || source.p() != source_dims[2]
        << "FAIL reduction source " + fields[0]
        exit(1)
      if source.rank() != exact || source.compose_zero_terms() != fields[9].to_i() || source.compose_parity_reduction() != fields[10].to_i()
        << "FAIL reduction audit " + fields[0]
        exit(1)
      result = source
      code = fields[15].to_i() ## i64
      if code != 0
        result = ffbc_orient_scheme(source, code)
      if result == nil || result.n() != target_dims[0] || result.m() != target_dims[1] || result.p() != target_dims[2] || ffbc_verify_exact(result) != 1
        << "FAIL reduction exact gate " + fields[0]
        exit(1)
      reduced += 1
      reduction_sum += reduction

    if fields[16] != "-"
      dims = i64[3]
      if ffbsbtt_parse_dims(fields[0], dims) != 1
        << "FAIL certificate dims " + fields[0]
        exit(1)
      certificate = ffbc_load_exact(root + fields[16], dims[0], dims[1], dims[2], exact + 1)
      if certificate == nil || certificate.rank() != exact
        << "FAIL certificate " + fields[16]
        exit(1)
      certificates += 1
    rows += 1
  i += 1

if rows != 56 || ties != 648 || wins != 1 || co_records != 2 || losses != 53
  << "FAIL bounded-tie closure counts"
  exit(1)
if reduced != 2 || reduction_sum != 4 || certificates != 1
  << "FAIL bounded-tie exact counts"
  exit(1)

<< "PASS block bounded tie exact closure"
