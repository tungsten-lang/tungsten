# The frozen-fringe SAT encoder must emit a DIMACS body whose clause count
# matches its header in linear time and memory.  It once appended every
# clause to one growing string; without a collector that leaked every
# intermediate copy, so the 4x4 window at k=16 (4096 cells, 15 wanted
# terms, ~480k clauses) consumed tens of gigabytes and never reached the
# solver.  The production-size case below is the regression guard.
use core/system
use ../lib/metaflip/strategies/sat_repair

failures = 0 ## i64

-> encoder_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    return 1
  0

-> encoder_check(label, au, av, aw, want, fill) (String i64 i64 i64 i64 i64) i64
  cells = au * av * aw ## i64
  words = ffsdr_tensor_words(cells) ## i64
  target = i64[words]
  i = 0 ## i64
  while i < words
    target[i] = fill
    i += 1
  meta = i64[8]
  cnf = ffsdr_emit_cnf(target, au, av, aw, want, cells, meta)
  bad = 0 ## i64
  bad += encoder_expect(label + " emits", cnf != nil)
  if cnf == nil
    return bad
  lines = cnf.split("\n")
  header = lines[0].split(" ")
  bad += encoder_expect(label + " header", header.size() == 4 && header[0] == "p" && header[1] == "cnf")
  variables = header[2].to_i() ## i64
  clauses = header[3].to_i() ## i64
  bad += encoder_expect(label + " meta variables", meta[4] == variables)
  bad += encoder_expect(label + " meta clauses", meta[5] == clauses)
  body_lines = 0 ## i64
  terminated = 1 ## i64
  max_literal = 0 ## i64
  i = 1
  while i < lines.size()
    if lines[i] != ""
      body_lines += 1
      literals = lines[i].split(" ")
      if literals[literals.size() - 1] != "0"
        terminated = 0
      j = 0 ## i64
      while j < literals.size() - 1
        value = literals[j].to_i() ## i64
        if value < 0
          value = 0 - value
        if value > max_literal
          max_literal = value
        if value == 0
          terminated = 0
        j += 1
    i += 1
  bad += encoder_expect(label + " clause count " + body_lines.to_s() + " vs header " + clauses.to_s(), body_lines == clauses)
  bad += encoder_expect(label + " every clause ends with 0 and has no zero literal", terminated == 1)
  bad += encoder_expect(label + " literals stay within the declared variables", max_literal <= variables && max_literal > 0)
  bad

failures += encoder_check("2x2x2 want=1 zero", 2, 2, 2, 1, 0)
failures += encoder_check("2x2x2 want=2 ones", 2, 2, 2, 2, 0 - 1)
failures += encoder_check("3x4x5 want=4 mixed", 3, 4, 5, 4, 6148914691236517205)
# The time bound is the suite watchdog: the quadratic encoder never finished
# the production case at all.  Under the root gate's interpreter (which sets
# TUNGSTEN_INTERPRETED_SPEC) the same structure is checked at one eighth of
# the cells so the shard stays inside its budget; compiled runs take the
# full 4x4 window.
if env("TUNGSTEN_INTERPRETED_SPEC") == "1"
  failures += encoder_check("8x8x8 want=15 interpreted", 8, 8, 8, 15, 6148914691236517205)
else
  failures += encoder_check("16x16x16 want=15 production", 16, 16, 16, 15, 6148914691236517205)

if failures > 0
  << "metaflip sat repair encoder: " + failures.to_s() + " failure(s)"
  exit(1)
<< "metaflip sat repair encoder: ok"
