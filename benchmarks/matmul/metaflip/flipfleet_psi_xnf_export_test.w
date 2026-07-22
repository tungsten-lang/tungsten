# Focused native-XOR + lex-SBP exporter regression.  Pure Tungsten except
# for optional CryptoMiniSat verdict controls when that executable is on PATH.

use flipfleet_psi_xnf_export_lib

-> ffpxt_expect(label, condition) (String bool) i64
  if !condition
    << "PSI_XNF_EXPORT_FAIL " + label
    exit(1)
  1

-> ffpxt_line_counts(text, counts) (String i64[]) i64
  lines = text.split("\n")
  i = 1 ## i64
  while i < lines.size()
    if lines[i] != ""
      counts[0] += 1
      if lines[i].starts_with?("x ")
        counts[1] += 1
      else
        counts[2] += 1
    i += 1
  counts[0]

-> ffpxt_target_bit(cell, n, m) (i64 i64 i64) i64
  p = n ## i64
  vm = m * p ## i64
  wm = n * p ## i64
  cc = cell % wm ## i64
  rest = cell / wm ## i64
  b = rest % vm ## i64
  a = rest / vm ## i64
  i = a / m ## i64
  j = a % m ## i64
  j2 = b / p ## i64
  k = b % p ## i64
  i2 = cc / p ## i64
  k2 = cc % p ## i64
  if j == j2 && i == i2 && k == k2
    return 1
  0

-> ffpxt_pair_psi_mask(mask, n, m) (i64 i64 i64) i64
  width = 2 * n * m + n * n ## i64
  out = 0 ## i64
  pos = 0 ## i64
  while pos < width
    if ((mask >> pos) & 1) == 1
      mapped = ffpx_pair_psi_var(1, pos, n, m) - 1 ## i64
      out = out | (1 << mapped)
    pos += 1
  out

-> ffpxt_mask_lex_le(left, right, width) (i64 i64 i64) i64
  pos = 0 ## i64
  while pos < width
    a = (left >> pos) & 1 ## i64
    b = (right >> pos) & 1 ## i64
    if a < b
      return 1
    if a > b
      return 0
    pos += 1
  1

# Literal-for-literal equivalence with ffpsi_lex_chain, including both the
# direct e_1 equality definition and the deeper prefix link.
chain3 = ffpx_lex_chain_text(1, 4, 3, 7)
expected3 = "-1 4 0\n" ## String
expected3 = expected3 + "-7 -1 4 0\n"
expected3 = expected3 + "-7 1 -4 0\n"
expected3 = expected3 + "7 1 4 0\n"
expected3 = expected3 + "7 -1 -4 0\n"
expected3 = expected3 + "-7 -2 5 0\n"
expected3 = expected3 + "-8 7 0\n"
expected3 = expected3 + "-8 -2 5 0\n"
expected3 = expected3 + "-8 2 -5 0\n"
expected3 = expected3 + "8 -7 2 5 0\n"
expected3 = expected3 + "8 -7 -2 -5 0\n"
expected3 = expected3 + "-8 -3 6 0\n"
z = ffpxt_expect("lex chain matches in-process clause template", chain3 == expected3) ## i64
z = ffpxt_expect("lex chain accounting", ffpx_lex_aux_count(3) == 2 && ffpx_lex_clause_count(3) == 12)

# Pair orientation follows u(i,j)<->v(j,i) and w(i,k)<->w(k,i), and is itself
# an involution over the complete u|v|w block.
z = ffpxt_expect("pair psi map endpoints", ffpx_pair_psi_var(100, 0, 2, 5) == 110 && ffpx_pair_psi_var(100, 9, 2, 5) == 119)
z = ffpxt_expect("pair psi map swaps factor blocks", ffpx_pair_psi_var(100, 10, 2, 5) == 100 && ffpx_pair_psi_var(100, 19, 2, 5) == 109)
z = ffpxt_expect("pair psi map transposes w", ffpx_pair_psi_var(100, 20, 2, 5) == 120 && ffpx_pair_psi_var(100, 21, 2, 5) == 122 && ffpx_pair_psi_var(100, 22, 2, 5) == 121 && ffpx_pair_psi_var(100, 23, 2, 5) == 123)
pos = 0 ## i64
while pos < 24
  mapped = ffpx_pair_psi_var(100, pos, 2, 5) - 100 ## i64
  z = ffpxt_expect("pair psi position map is involutive", mapped >= 0 && mapped < 24 && ffpx_pair_psi_var(100, mapped, 2, 5) == 100 + pos)
  pos += 1
orientation = ffpx_pair_orientation_text(1, 2, 2, 50) ## String
z = ffpxt_expect("pair orientation starts with X <= psi(X)", orientation.starts_with?("-1 5 0\n-50 -1 5 0\n"))
z = ffpxt_expect("pair orientation uses only nontrivial two-cycles", ffpx_pair_orientation_width(2, 2) == 5 && ffpx_pair_orientation_width(2, 5) == 11)
z = ffpxt_expect("pair orientation has one reduced exact lex chain", orientation.split("\n").size() == 25)
mask = 0 ## i64
while mask < 4096
  psi_mask = ffpxt_pair_psi_mask(mask, 2, 2) ## i64
  z = ffpxt_expect("pair-mask psi is involutive", ffpxt_pair_psi_mask(psi_mask, 2, 2) == mask)
  forward = ffpxt_mask_lex_le(mask, psi_mask, 12) ## i64
  reverse = ffpxt_mask_lex_le(psi_mask, mask, 12) ## i64
  z = ffpxt_expect("one orientation is always canonical", forward == 1 || reverse == 1)
  z = ffpxt_expect("both orientations are canonical only at fixed points", (forward == 1 && reverse == 1) == (mask == psi_mask))
  mask += 1

# The two outer-coordinate parities give a generator- and orientation-invariant
# Hamming weight for every inner coordinate.  Four clauses sort adjacent
# weights without choosing an outer-coordinate orientation.
inner = ffpx_inner_weight_sbp_text(2, 2, 1, 1, 100) ## String
expected_inner = "x -1 5 13 100 0\n" ## String
expected_inner = expected_inner + "x -3 6 15 101 0\n"
expected_inner = expected_inner + "x -2 7 14 102 0\n"
expected_inner = expected_inner + "x -4 8 16 103 0\n"
expected_inner = expected_inner + "-100 102 103 0\n-101 102 103 0\n-100 -101 102 0\n-100 -101 103 0\n"
z = ffpxt_expect("inner weight SBP exact text", inner == expected_inner)
z = ffpxt_expect("inner weight SBP accounting", ffpx_inner_weight_sbp_aux_count(2, 2) == 4 && ffpx_inner_weight_sbp_clause_count(2, 2) == 8)

# The coefficient-cell quotient is a genuine involution quotient, not a row
# sample.  It has (64+8)/2=36 orbits for 2x2 and (400+20)/2=210 for 2x5.
z = ffpxt_expect("2x2 coefficient orbit count", ffpx_cell_orbit_count(2, 2) == 36)
z = ffpxt_expect("2x5 coefficient orbit count", ffpx_cell_orbit_count(2, 5) == 210)
cell = 0 ## i64
while cell < 400
  mate = ffpx_cell_mate(cell, 2, 5) ## i64
  z = ffpxt_expect("coefficient cell action is involutive", mate >= 0 && mate < 400 && ffpx_cell_mate(mate, 2, 5) == cell)
  z = ffpxt_expect("matmul target is constant on coefficient orbits", ffpxt_target_bit(cell, 2, 5) == ffpxt_target_bit(mate, 2, 5))
  cell += 1

# <2,2,2>, (c=2,f=3), rank 7: 268 primary/quotient-product variables
# plus three fixed-diagonal-rank auxiliaries, six fixed-U row-separation
# auxiliaries, four inner-weight auxiliaries, and 33 lex-prefix auxiliaries;
# 899 base rows (including the coordinate anchor), 18 fixed-rank clauses,
# eight inner-weight rows, and 198 ordinary SBP clauses.  The
# fixed-generator products whose wired U/V inputs coincide use an exact
# two-input rather than duplicate-input three-factor encoding.
sat_text = ffpx_cell_text(2, 2, 2, 3)
sat_header = sat_text.split("\n")[0] ## String
z = ffpxt_expect("rank7 header counts quotient products and auxiliaries: " + sat_header, sat_text.starts_with?("p cnf 314 1123\n")) ## i64
counts = i64[3]
z = ffpxt_line_counts(sat_text, counts)
z = ffpxt_expect("rank7 physical line count matches header", counts[0] == 1123)
z = ffpxt_expect("rank7 keeps coefficient, rank, and coordinate native XOR rows", counts[1] == 49 && counts[2] == 1074)
z = ffpxt_expect("last sorted fixed generator anchors U00", sat_text.include?("\n41 0\n"))
z = ffpxt_expect("fixed diagonal rows have explicit rank two", sat_text.include?("\n29 37 45 0\n32 40 48 0\nx -29 32 269 0\n") && sat_text.include?("\n269 270 271 0\n"))
z = ffpxt_expect("fixed U rows are nonzero and separated", sat_text.include?("x -25 27 272 0\nx -33 35 273 0\nx -41 43 274 0\n25 33 41 0\n27 35 43 0\n272 273 274 0\n"))
z = ffpxt_expect("inner weight precedes ordinary symmetry chains", sat_text.include?("x -1 5 13 17 25 33 41 278 0\nx -3 6 15 18 27 35 43 279 0\nx -2 7 14 19 26 34 42 280 0\nx -4 8 16 20 28 36 44 281 0\n-278 280 281 0\n"))
z = ffpxt_expect("first pair orientation precedes pair sorting", sat_text.include?("-1 5 0\n-282 -1 5 0\n") && sat_text.include?("-1 13 0\n-290 -1 13 0\n"))
z = ffpxt_expect("fixed lex chains follow pair auxiliaries", sat_text.include?("-25 33 0\n-301 -25 33 0\n") && sat_text.include?("-33 41 0\n-308 -33 41 0\n"))
z = ffpxt_expect("last allocated prefix variable is bounded by header", sat_text.include?("-314 -40 48 0\n"))

# <2,2,2>, (c=3,f=0), rank 6: two 12-bit pair chains.  This is the known
# impossible rank-6 cell and exercises the no-fixed-generator boundary.
unsat_text = ffpx_cell_text(2, 2, 3, 0)
z = ffpxt_expect("rank6 header counts quotient products and pair symmetries", unsat_text.starts_with?("p cnf 242 925\n"))
counts2 = i64[3]
z = ffpxt_line_counts(unsat_text, counts2)
z = ffpxt_expect("rank6 physical line count matches header", counts2[0] == 925 && counts2[1] == 32)
z = ffpxt_expect("rank6 fixed-cell odd target exposes an empty clause", unsat_text.include?("\n0\n"))
z = ffpxt_expect("second pair sorting chain has fresh auxiliaries", unsat_text.include?("-13 25 0\n-232 -13 25 0\n"))

# Rank 17 with only one fixed generator cannot span the two-dimensional fixed
# coefficient target.  This already-closed <2,5,2> cell validates the explicit
# fixed-diagonal rank consequence on the production shape.
thin_fixed_text = ffpx_cell_text(2, 5, 8, 1) ## String
z = ffpxt_expect("one-fixed production cell carries rank-two consequence", thin_fixed_text.include?("\nx -") && thin_fixed_text.include?("\n0\n") == false)

# External controls prove that adding the textual SBP has neither removed the
# planted rank-7 orbit nor admitted a rank-6 decomposition.  The structural
# checks above remain unconditional on machines without CryptoMiniSat.
if system("command -v cryptominisat5 >/dev/null 2>&1")
  sat_path = "/tmp/flipfleet_psi_xnf_export_rank7.cnf" ## String
  sat_log = "/tmp/flipfleet_psi_xnf_export_rank7.log" ## String
  unsat_path = "/tmp/flipfleet_psi_xnf_export_rank6.cnf" ## String
  unsat_log = "/tmp/flipfleet_psi_xnf_export_rank6.log" ## String
  thin_path = "/tmp/flipfleet_psi_xnf_export_psi252_c8f1.cnf" ## String
  thin_log = "/tmp/flipfleet_psi_xnf_export_psi252_c8f1.log" ## String
  z = ffpxt_expect("write rank7 control", write_file(sat_path, sat_text))
  z = ffpxt_expect("write rank6 control", write_file(unsat_path, unsat_text))
  z = ffpxt_expect("write one-fixed production control", write_file(thin_path, thin_fixed_text))
  z = ffpxt_expect("run rank7 control", system("cryptominisat5 --verb 0 --threads 1 --maxtime 30 --zero-exit-status " + sat_path + " > " + sat_log + " 2>&1"))
  z = ffpxt_expect("run rank6 control", system("cryptominisat5 --verb 0 --threads 1 --maxtime 30 --zero-exit-status " + unsat_path + " > " + unsat_log + " 2>&1"))
  z = ffpxt_expect("run one-fixed production control", system("cryptominisat5 --verb 0 --threads 1 --maxtime 30 --zero-exit-status " + thin_path + " > " + thin_log + " 2>&1"))
  sat_result = read_file(sat_log)
  unsat_result = read_file(unsat_log)
  thin_result = read_file(thin_log)
  z = ffpxt_expect("rank7 planted cell remains SAT", sat_result != nil && sat_result.include?("s SATISFIABLE"))
  z = ffpxt_expect("rank6 cell remains UNSAT", unsat_result != nil && unsat_result.include?("s UNSATISFIABLE"))
  z = ffpxt_expect("one-fixed production cell remains UNSAT", thin_result != nil && thin_result.include?("s UNSATISFIABLE"))
  << "PSI_XNF_EXPORT_SOLVER rank7=SAT rank6=UNSAT psi252_c8f1=UNSAT"
else
  << "PSI_XNF_EXPORT_SOLVER skipped=cryptominisat5-not-found"

<< "flipfleet_psi_xnf_export_test: all checks passed"
