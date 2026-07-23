# DIMACS CNF parsing for Wassat.
#
# This deliberately duplicates the parser in tungsten-wrat rather than
# sharing it.  A proof checker is only worth running if it has no code in
# common with the solver whose work it audits: a shared parser bug could
# make both agree on a formula that is not the one on disk.  The duplication
# is the feature.

# Split a line into non-empty whitespace-separated tokens. DIMACS permits
# tabs as well as spaces, so each space-split piece is split again on tabs;
# strip disposes of any carriage returns.
-> wassat_tokenize(line)
  out = []
  line.split(" ").each -> (t)
    t.split("\t").each -> (u)
      piece = u.strip
      out.push(piece) unless piece == ""
  out

# DIMACS counts are non-negative decimal integers.  Do not use String#to_i
# for validation: it deliberately accepts a numeric prefix and, more
# dangerously for a SAT parser, turns arbitrary text such as `x` into zero.
-> wassat_unsigned_decimal?(token)
  return false if token == nil || token.empty?
  i = 0
  while i < token.size
    return false if "0123456789".index(token.slice(i, 1)) == nil
    i += 1
  true

# A DIMACS literal is a decimal integer with an optional sign.  Signed zero
# is not a clause terminator: the grammar reserves the exact token `0` for
# that purpose.
-> wassat_literal_token?(token)
  return false if token == nil || token.empty?
  first = token.slice(0, 1)
  start = 0
  start = 1 if first == "-" || first == "+"
  return false if start == token.size
  i = start
  while i < token.size
    return false if "0123456789".index(token.slice(i, 1)) == nil
    i += 1
  # `00`, `+0`, `-0`, and their longer forms are numerically zero but are
  # not the exact DIMACS terminator token.
  return false if token != "0" && token.to_i == 0
  true

# Native-parser entry: the C extern tokenizes and validates strict DIMACS
# straight into flat i64 buffers (the boxed splitting below cost ~200ms on
# 200k-clause files); boxed clauses are then built by a cheap array walk.
# Validation matrix matches wassat_parse_cnf exactly — the spec suite runs
# the same rejection cases against both.
-> wassat_parse_cnf_native(text)
  cap_l = text.size / 2 + 64
  cap_c = text.size / 4 + 64
  lits = i64[cap_l]
  offs = i64[cap_c]
  lens = i64[cap_c]
  hdr = i64[8]
  z = ccall("__w_parse_dimacs", text, lits, offs, lens, hdr)
  err = hdr[4]
  if err != 0
    msgs = { 1: "missing or duplicate p cnf header", 2: "malformed p-line",
             3: "invalid DIMACS token", 4: "literal exceeds declared variable count",
             5: "clause not terminated by 0", 6: "clause count mismatch",
             7: "input exceeds parser buffers", 8: "XNF/native XOR clauses are not supported; expand them to CNF" }
    raise "[msgs[err]] (line [hdr[5]])"
  nvars = hdr[0]
  raise "implausible variable count [nvars] in header" if nvars > 50000000
  ncl = hdr[2]
  clauses = []
  k = 0
  while k < ncl
    o = offs[k]
    n = lens[k]
    c = []
    j = 0
    while j < n
      c.push(lits[o + j])
      j += 1
    clauses.push(c)
    k += 1
  { "nvars": nvars, "clauses": clauses,
    "flat_lits": lits, "flat_offs": offs, "flat_lens": lens,
    "flat_ncl": ncl, "flat_nlits": hdr[3] }

# Parse DIMACS CNF text into {"nvars": Int, "clauses": Array}.
-> wassat_parse_cnf(text)
  nvars = 0
  declared_clauses = 0
  clauses = []
  current = []
  have_header = false

  # A `%` line ends the clause section. SATLIB files close with "%\n0\n",
  # and reading that trailing 0 as a clause terminator would append an empty
  # clause -- silently turning every satisfiable instance unsatisfiable.
  done = false
  text.split("\n").each -> (raw)
    line = raw.strip
    done = true if line.starts_with?("%")
    unless done || line == ""
      parts = wassat_tokenize(line)
      # A comment marker is a token, not a prefix: `c anything` is a
      # comment, while `cat 1 0` is malformed clause input and must fail.
      unless parts[0] == "c"
        if parts[0] == "p"
          raise "duplicate p cnf header" if have_header
          raise "malformed p-line: [line]" unless parts.size == 4
          raise "only 'cnf' is supported, got '[parts[1]]'" unless parts[1] == "cnf"
          raise "invalid variable count '[parts[2]]'" unless wassat_unsigned_decimal?(parts[2])
          raise "invalid clause count '[parts[3]]'" unless wassat_unsigned_decimal?(parts[3])
          nvars = parts[2].to_i
          declared_clauses = parts[3].to_i
          # A hostile header must fail loudly here, not OOM later when the
          # solver sizes its per-variable arrays from the declaration.
          raise "implausible variable count [nvars] in header" if nvars > 50000000
          raise "implausible clause count [declared_clauses] in header" if declared_clauses > 200000000
          have_header = true
        else
          raise "missing p cnf header" unless have_header
          if parts[0] == "x"
            raise "XNF/native XOR clauses are not supported; expand them to CNF"
          parts.each -> (tok)
            raise "invalid DIMACS token '[tok]'" unless wassat_literal_token?(tok)
            lit = tok.to_i
            if tok == "0"
              clauses.push(current)
              current = []
              raise "too many clauses: declared [declared_clauses]" if clauses.size > declared_clauses
            else
              current.push(lit)
              v = lit.abs
              raise "literal [lit] exceeds declared variable count [nvars]" if v > nvars

  raise "missing p cnf header" unless have_header
  raise "clause not terminated by 0" unless current.empty?
  unless clauses.size == declared_clauses
    raise "clause count mismatch: declared [declared_clauses], parsed [clauses.size]"

  { "nvars": nvars, "clauses": clauses }
