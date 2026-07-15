# Exact fixed-dictionary rank search for the <2,2,5> tensor.
#
# The dictionary is the unique union of the five production rank-18 doors and
# either the deterministic 32-parent maximin block-local GL archive or the
# first N members of the complete 4096-parent bank.  This first implementation
# reports the dictionary's exact GF(2) column rank/nullity; the SAT emitter and
# independently gated decoder live below the shared dictionary builder.

use flipfleet_rect_multi_parent_nullspace
use flipfleet_225_block_gl_parent_lib

-> ff225us_key(u, v, w) (i64 i64 i64) i64
  (u << 20) | (v << 10) | w

-> ff225us_add_scheme(scheme, us, vs, ws, count, seen) (FFBCScheme i64[] i64[] i64[] i64 i32[]) i64
  if scheme == nil || ffbc_verify_exact(scheme) != 1
    return 0 - 1
  i = 0 ## i64
  while i < scheme.rank()
    u = scheme.us()[i] ## i64
    v = scheme.vs()[i] ## i64
    w = scheme.ws()[i] ## i64
    key = ff225us_key(u, v, w) ## i64
    if u < 1 || u >= 16 || v < 1 || v >= 1024 || w < 1 || w >= 1024 || key < 0 || key >= seen.size()
      return 0 - 1
    if seen[key] == 0
      if count >= us.size()
        return 0 - 1
      us[count] = u
      vs[count] = v
      ws[count] = w
      seen[key] = count + 1
      count += 1
    i += 1
  count

# Rank the 400-bit tensor columns without retaining the (potentially enormous)
# provenance nullspace.  There can be at most 400 pivot rows.
-> ff225us_column_rank(us, vs, ws, count, meta) (i64[] i64[] i64[] i64 i64[]) i64
  tensor_bits = 400 ## i64
  tensor_words = 7 ## i64
  owners = i32[tensor_bits]
  pivots = i64[tensor_bits * tensor_words]
  work = i64[tensor_words]
  rank = 0 ## i64
  reductions = 0 ## i64
  column = 0 ## i64
  while column < count
    z = ffnd_clear(work, 0, tensor_words) ## i64
    z = ffran_xor_outer(work, 0, us[column], vs[column], ws[column], 2, 2, 5)
    done = 0 ## i64
    while done == 0
      bit = ffnd_first_set(work, 0, tensor_words) ## i64
      if bit < 0
        done = 1
      if bit >= 0
        prior = owners[bit] - 1 ## i64
        if prior < 0
          z = ffnd_copy(work, 0, pivots, rank * tensor_words, tensor_words)
          owners[bit] = rank + 1
          rank += 1
          done = 1
        if prior >= 0
          z = ffnd_xor(pivots, prior * tensor_words, work, 0, tensor_words)
          reductions += 1
    column += 1
  meta[0] = rank
  meta[1] = count - rank
  meta[2] = reductions
  rank

-> ff225us_archive_indices()
  selected = i64[32]
  selected[0] = 2577
  selected[1] = 1182
  selected[2] = 281
  selected[3] = 2650
  selected[4] = 293
  selected[5] = 1097
  selected[6] = 3822
  selected[7] = 151
  selected[8] = 692
  selected[9] = 89
  selected[10] = 1458
  selected[11] = 1181
  selected[12] = 1213
  selected[13] = 3363
  selected[14] = 636
  selected[15] = 1879
  selected[16] = 3169
  selected[17] = 30
  selected[18] = 456
  selected[19] = 1359
  selected[20] = 1530
  selected[21] = 2859
  selected[22] = 2958
  selected[23] = 2830
  selected[24] = 667
  selected[25] = 1082
  selected[26] = 2908
  selected[27] = 3000
  selected[28] = 1449
  selected[29] = 3587
  selected[30] = 3572
  selected[31] = 955
  selected

# mode 0: five doors only; mode 1: five doors + archive_count maximin parents;
# mode 2: five doors + bank parents [0, parent_count).
-> ff225us_build(mode, parent_count, us, vs, ws, seen, meta) (i64 i64 i64[] i64[] i64[] i32[] i64[]) i64
  root = "benchmarks/matmul/metaflip/" ## String
  paths = []
  paths.push(root + "matmul_2x2x5_rank18_d84_gf2.txt")
  paths.push(root + "matmul_2x2x5_rank18_d88_gf2.txt")
  paths.push(root + "matmul_2x2x5_rank18_d92_block_local_gl_gf2.txt")
  paths.push(root + "matmul_2x2x5_rank18_d84_block_splice_gf2.txt")
  paths.push(root + "matmul_2x2x5_rank18_d84_gpu_block_tunnel_gf2.txt")
  count = 0 ## i64
  i = 0 ## i64
  while i < paths.size()
    door = ffbc_load_exact(paths[i], 2, 2, 5, 32)
    if door == nil || door.rank() != 18
      return 0 - 1
    count = ff225us_add_scheme(door, us, vs, ws, count, seen)
    if count < 1
      return 0 - 1
    i += 1
  meta[0] = count
  if mode == 0
    return count
  if parent_count < 1 || (mode == 1 && parent_count > 32) || (mode == 2 && parent_count > 4096)
    return 0 - 1
  leaf3 = ffbc_load_exact(root + "matmul_2x2x3_rank11_catalog_gf2.txt", 2, 2, 3, 16)
  leaf2 = ffbc_load_exact(root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, 16)
  outer = ff225gl_outer()
  if leaf3 == nil || leaf2 == nil || outer == nil
    return 0 - 1
  indices = ff225us_archive_indices()
  i = 0
  while i < parent_count
    index = i ## i64
    if mode == 1
      index = indices[i]
    parent = ff225gl_parent(leaf3, leaf2, outer, ff225gl_alloc_n(), ff225gl_alloc_m(), ff225gl_alloc_p(), index)
    if parent == nil || parent.rank() != 18
      return 0 - 1
    count = ff225us_add_scheme(parent, us, vs, ws, count, seen)
    if count < 1
      return 0 - 1
    i += 1
  meta[1] = count
  count

-> ff225us_seq_var(prefix_count, k, i, j) (i64 i64 i64 i64) i64
  prefix_count + (i - 1) * k + j

-> ff225us_term_hits(u, v, w, cell) (i64 i64 i64 i64) i64
  wi = cell % 10 ## i64
  rest = cell / 10 ## i64
  vi = rest % 10 ## i64
  ui = rest / 10 ## i64
  ((u >> ui) & 1) & ((v >> vi) & 1) & ((w >> wi) & 1)

-> ff225us_target_bit(cell) (i64) i64
  wi = cell % 10 ## i64
  rest = cell / 10 ## i64
  vi = rest % 10 ## i64
  ui = rest / 10 ## i64
  i = ui / 2 ## i64
  j = ui % 2 ## i64
  j2 = vi / 5 ## i64
  k = vi % 5 ## i64
  i2 = wi / 5 ## i64
  k2 = wi % 5 ## i64
  if i == i2 && j == j2 && k == k2
    return 1
  0

# Sinz sequential counter for sum(x) <= k.  Every tensor coefficient is a
# native CryptoMiniSat XOR clause over exactly the dictionary terms that hit
# it.  CryptoMiniSat's x-lines assert odd parity, so a zero target negates the
# first literal.  meta: variables, clauses, XOR rows, cardinality clauses,
# literal incidences, empty rows.
-> ff225us_emit_xnf(us, vs, ws, count, k, meta) (i64[] i64[] i64[] i64 i64 i64[])
  if count < 2 || k < 1 || k >= count || meta.size() < 6
    return nil
  xor_body = ""
  xor_rows = 0 ## i64
  incidences = 0 ## i64
  empty_rows = 0 ## i64
  cell = 0 ## i64
  while cell < 400
    line = "x" ## String
    first = 0 ## i64
    term = 0 ## i64
    while term < count
      if ff225us_term_hits(us[term], vs[term], ws[term], cell) != 0
        literal = term + 1 ## i64
        if first == 0
          first = literal
          if ff225us_target_bit(cell) == 0
            literal = 0 - literal
        line = line + literal.to_s() + " "
        incidences += 1
      term += 1
    if first == 0
      empty_rows += 1
      if ff225us_target_bit(cell) != 0
        # Empty odd-parity XOR: an explicit contradictory ordinary clause.
        xor_body = xor_body + "0\n"
        xor_rows += 1
    if first != 0
      xor_body = xor_body + line + "0\n"
      xor_rows += 1
    cell += 1

  cardinality = ""
  card_clauses = 0 ## i64
  # (not x_i or s_i,1), 1 <= i < n
  i = 1 ## i64
  while i < count
    cardinality = cardinality + (0 - i).to_s() + " " + ff225us_seq_var(count, k, i, 1).to_s() + " 0\n"
    card_clauses += 1
    i += 1
  # Monotonicity s_(i-1),j -> s_i,j.
  i = 2
  while i < count
    cardinality = cardinality + (0 - ff225us_seq_var(count, k, i - 1, 1)).to_s() + " " + ff225us_seq_var(count, k, i, 1).to_s() + " 0\n"
    card_clauses += 1
    j = 2 ## i64
    while j <= k
      cardinality = cardinality + (0 - i).to_s() + " " + (0 - ff225us_seq_var(count, k, i - 1, j - 1)).to_s() + " " + ff225us_seq_var(count, k, i, j).to_s() + " 0\n"
      cardinality = cardinality + (0 - ff225us_seq_var(count, k, i - 1, j)).to_s() + " " + ff225us_seq_var(count, k, i, j).to_s() + " 0\n"
      card_clauses += 2
      j += 1
    i += 1
  # No (k+1)st selected term.
  i = 2
  while i <= count
    cardinality = cardinality + (0 - i).to_s() + " " + (0 - ff225us_seq_var(count, k, i - 1, k)).to_s() + " 0\n"
    card_clauses += 1
    i += 1
  variables = count + (count - 1) * k ## i64
  clauses = xor_rows + card_clauses ## i64
  meta[0] = variables
  meta[1] = clauses
  meta[2] = xor_rows
  meta[3] = card_clauses
  meta[4] = incidences
  meta[5] = empty_rows
  "p cnf " + variables.to_s() + " " + clauses.to_s() + "\n" + xor_body + cardinality

-> ff225us_shell_quote(text) (String)
  "'" + text.replace("'", "'\"'\"'") + "'"

# Return 1 for SAT, -1 for UNSAT, -2 for a deadline/process failure, and -3
# for malformed solver output.
-> ff225us_run_solver(xnf, timeout_s, stem, meta) (String i64 String i64[])
  if xnf == nil || timeout_s < 1
    return nil
  input = stem + ".xnf" ## String
  model_path = stem + ".model" ## String
  if write_file(input, xnf) == false || write_file(model_path, "") == false
    return nil
  command = "/usr/bin/perl -e 'alarm shift; exec @ARGV' " + (timeout_s + 2).to_s() + " cryptominisat5 --verb 1 --maxtime " + timeout_s.to_s() + " " + ff225us_shell_quote(input) + " > " + ff225us_shell_quote(model_path) + " 2>&1" ## String
  ok = system(command)
  model = read_file(model_path)
  meta[6] = 0 - 3
  if model != nil && model.include?("s UNSATISFIABLE")
    meta[6] = 0 - 1
    return model
  if model != nil && model.include?("s SATISFIABLE")
    meta[6] = 1
    return model
  if ok == false
    meta[6] = 0 - 2
  model

# Decode only explicitly assigned dictionary variables, independently rebuild
# the scheme, exact-gate it, serialize it, parse it again, and exact-gate the
# replay.  meta[7]/[8] are decoded rank and replay gate.
-> ff225us_decode_gate(model, us, vs, ws, count, max_rank, output, meta) (String i64[] i64[] i64[] i64 i64 String i64[]) i64
  if model == nil || !model.include?("s SATISFIABLE") || model.include?("s UNSATISFIABLE")
    return 0
  meta[9] = 1
  assignments = i64[count + 1]
  lines = model.split("\n")
  line_index = 0 ## i64
  while line_index < lines.size()
    line = lines[line_index] ## String
    if line.starts_with?("v ")
      tokens = line.replace("\t", " ").split(" ")
      i = 1 ## i64
      while i < tokens.size()
        value = tokens[i].to_i() ## i64
        variable = value ## i64
        truth = 1 ## i64
        if value < 0
          variable = 0 - value
          truth = 0 - 1
        if variable > 0 && variable <= count
          if assignments[variable] != 0 && assignments[variable] != truth
            return 0
          assignments[variable] = truth
        i += 1
    line_index += 1
  rank = 0 ## i64
  variable = 1 ## i64
  while variable <= count
    if assignments[variable] == 0
      return 0
    if assignments[variable] == 1
      rank += 1
    variable += 1
  meta[7] = rank
  meta[9] = 2
  if rank < 1 || rank > max_rank
    return 0
  candidate = FFBCScheme.new(2, 2, 5, rank)
  slot = 0 ## i64
  variable = 1
  while variable <= count
    if assignments[variable] == 1
      candidate.us()[slot] = us[variable - 1]
      candidate.vs()[slot] = vs[variable - 1]
      candidate.ws()[slot] = ws[variable - 1]
      slot += 1
    variable += 1
  candidate.set_rank(rank)
  if slot != rank || ffbc_verify_exact(candidate) != 1
    return 0
  meta[9] = 3
  if ffbc_write(output, candidate) != rank
    return 0
  meta[9] = 4
  replay = ffbc_load_exact(output, 2, 2, 5, max_rank)
  if replay == nil || replay.rank() != rank || ffbc_verify_exact(replay) != 1
    return 0
  meta[9] = 5
  meta[8] = 1
  rank

-> ff225us_dictionary_text(us, vs, ws, count) (i64[] i64[] i64[] i64)
  body = "# <2,2,5> fixed rank-one dictionary; deterministic insertion order\n" ## String
  body = body + "# columns " + count.to_s() + "\n"
  i = 0 ## i64
  while i < count
    body = body + i.to_s() + " " + us[i].to_s() + " " + vs[i].to_s() + " " + ws[i].to_s() + "\n"
    i += 1
  body

arguments = argv()
if arguments.size() < 2 || arguments.size() > 5
  << "usage: flipfleet_225_union_subset_sat mode parents timeout output limit"
  << "  MODE is doors, archive, or bank"
  exit(2)
mode_text = arguments[0] ## String
parents = arguments[1].to_i() ## i64
mode = 0 ## i64
if mode_text == "archive"
  mode = 1
if mode_text == "bank"
  mode = 2
if mode_text != "doors" && mode_text != "archive" && mode_text != "bank"
  << "FF225_UNION_ERROR mode"
  exit(2)
if mode == 0
  parents = 0

capacity = 90 + parents * 18 ## i64
us = i64[capacity]
vs = i64[capacity]
ws = i64[capacity]
seen = i32[1 << 24]
meta = i64[8]
started = ccall("__w_clock_ms") ## i64
count = ff225us_build(mode, parents, us, vs, ws, seen, meta) ## i64
if count < 1
  << "FF225_UNION_ERROR build"
  exit(1)
rank_meta = i64[4]
rank = ff225us_column_rank(us, vs, ws, count, rank_meta) ## i64
if rank < 1
  << "FF225_UNION_ERROR rank"
  exit(1)
elapsed = ccall("__w_clock_ms") - started ## i64
<< "FF225_UNION_SUMMARY mode=" + mode_text + " parents=" + parents.to_s() + " door_union=" + meta[0].to_s() + " union=" + count.to_s() + " column_rank=" + rank.to_s() + " nullity=" + rank_meta[1].to_s() + " reductions=" + rank_meta[2].to_s() + " elapsed_ms=" + elapsed.to_s()
if arguments.size() == 2
  exit(0)
if arguments.size() != 4 && arguments.size() != 5
  << "FF225_UNION_ERROR solve-arguments"
  exit(2)
timeout_s = arguments[2].to_i() ## i64
output = arguments[3] ## String
limit = 17 ## i64
if arguments.size() == 5
  limit = arguments[4].to_i()
if timeout_s < 1 || output.size() < 1 || limit < 1 || limit > 18
  << "FF225_UNION_ERROR solve-bounds"
  exit(2)
sat_meta = i64[12]
emit_started = ccall("__w_clock_ms") ## i64
xnf = ff225us_emit_xnf(us, vs, ws, count, limit, sat_meta)
if xnf == nil
  << "FF225_UNION_ERROR emit"
  exit(1)
emit_ms = ccall("__w_clock_ms") - emit_started ## i64
stem = output + ".union-sat-" + mode_text + "-" + parents.to_s() + "-k" + limit.to_s() ## String
terms_path = stem + ".terms" ## String
digest_path = terms_path + ".sha256" ## String
dictionary = ff225us_dictionary_text(us, vs, ws, count)
if write_file(terms_path, dictionary) == false
  << "FF225_UNION_ERROR dictionary-write"
  exit(1)
digest_command = "/usr/bin/shasum -a 256 " + ff225us_shell_quote(terms_path) + " > " + ff225us_shell_quote(digest_path) ## String
digest_ok = system(digest_command)
digest = read_file(digest_path)
if digest == nil
  digest = "unavailable"
digest = digest.replace("\n", "")
if digest.include?(" ")
  digest = digest.split(" ")[0]
<< "FF225_UNION_SAT_START mode=" + mode_text + " parents=" + parents.to_s() + " union=" + count.to_s() + " weight_le=" + limit.to_s() + " vars=" + sat_meta[0].to_s() + " clauses=" + sat_meta[1].to_s() + " xor_rows=" + sat_meta[2].to_s() + " card_clauses=" + sat_meta[3].to_s() + " incidences=" + sat_meta[4].to_s() + " emit_ms=" + emit_ms.to_s() + " timeout_s=" + timeout_s.to_s() + " dictionary_sha256=" + digest
solve_started = ccall("__w_clock_ms") ## i64
model = ff225us_run_solver(xnf, timeout_s, stem, sat_meta)
solve_ms = ccall("__w_clock_ms") - solve_started ## i64
if sat_meta[6] == 1
  hit = ff225us_decode_gate(model, us, vs, ws, count, limit, output, sat_meta) ## i64
  if hit < 1 || sat_meta[8] != 1
    << "FF225_UNION_ERROR sat-decode-or-gate stage=" + sat_meta[9].to_s() + " decoded_rank=" + sat_meta[7].to_s()
    exit(1)
  << "FF225_UNION_SAT_HIT rank=" + hit.to_s() + " output=" + output + " exact_replay=1 solve_ms=" + solve_ms.to_s()
  exit(0)
label = "unknown" ## String
if sat_meta[6] == 0 - 1
  label = "unsat"
if sat_meta[6] == 0 - 2
  label = "timeout-or-process"
<< "FF225_UNION_SAT_RESULT status=" + label + " hit=0 solve_ms=" + solve_ms.to_s() + " xnf=" + stem + ".xnf model=" + stem + ".model"
