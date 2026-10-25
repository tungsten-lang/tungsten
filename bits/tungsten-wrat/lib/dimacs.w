# DIMACS CNF parsing.
#
# A clause is an Array of nonzero Int literals; a positive literal is a
# variable and a negative literal its negation.  A parsed formula is the
# plain record {"nvars": Int, "clauses": Array}.  The parser is permissive
# about whitespace and comments, and strict about anything that would
# silently change the meaning of the formula.


# Split a line into non-empty whitespace-separated tokens. DIMACS permits
# tabs as well as spaces; strip disposes of carriage returns.
-> wrat_tokenize(line)
  out = []
  has_tab = line.index("\t") != nil
  parts = line.split(" ")
  n = parts.size
  i = 0
  if !has_tab
    while i < n
      piece = parts[i].strip
      out.push(piece) unless piece == ""
      i += 1
    return out
  while i < n
    sub = parts[i].split("\t")
    m = sub.size
    j = 0
    while j < m
      piece = sub[j].strip
      out.push(piece) unless piece == ""
      j += 1
    i += 1
  out

# A checker must never guess: a token is an integer only if it is entirely
# decimal digits with an optional leading sign. `to_i` accepts numeric
# prefixes and turns arbitrary text into 0, either of which would silently
# change what is being verified.
-> wrat_int_token?(token)
  return false if token == nil
  n = token.size
  return false if n == 0
  b0 = token.byte_at(0)
  start = 0
  start = 1 if b0 == 45 || b0 == 43
  return false if start == n
  i = start
  while i < n
    b = token.byte_at(i)
    return false if b < 48 || b > 57
    i += 1
  true

# Header counts (variable count, clause count) are non-negative decimals: no
# sign is permitted, unlike a literal.
-> wrat_unsigned_decimal?(token)
  return false if token == nil
  n = token.size
  return false if n == 0
  i = 0
  while i < n
    b = token.byte_at(i)
    return false if b < 48 || b > 57
    i += 1
  true

# Parse DIMACS CNF text into {"nvars", "clauses"}.
#
# Accepts `c` comment lines and a `p cnf <vars> <clauses>` header.  Clauses
# may span lines; each is terminated by a literal 0.
-> wrat_parse_cnf(text)
  nvars = 0
  declared_clauses = 0
  clauses = []
  current = []
  have_header = false

  # A `%` line ends the clause section. SATLIB files close with "%\n0\n",
  # and reading that trailing 0 as a clause terminator would append an empty
  # clause -- silently turning every satisfiable instance unsatisfiable.
  sz = text.size
  pos = 0
  while pos < sz
    ls = pos
    le = pos
    while le < sz && text.byte_at(le) != 10
      le += 1
    pos = le < sz ? le + 1 : le

    i = ls
    while i < le
      b = text.byte_at(i)
      break unless b == 32 || b == 9 || b == 13
      i += 1
    if i < le
      b0 = text.byte_at(i)
      break if b0 == 37
      if b0 == 112
        line = text.slice(i, le - i).strip
        parts = wrat_tokenize(line)
        # The header is mandatory, unique, and EXACTLY `p cnf V C`. The
        # checker must trust the formula's own declared dimensions, not the
        # solver's -- so it enforces them here, independently of Wassat: the
        # declared variable count is an upper bound on every literal and the
        # declared clause count must match the clauses actually read.
        raise "duplicate p cnf header" if have_header
        raise "malformed p-line: [line]" unless parts.size == 4
        raise "only 'cnf' is supported, got '[parts[1]]'" unless parts[1] == "cnf"
        raise "invalid variable count '[parts[2]]'" unless wrat_unsigned_decimal?(parts[2])
        raise "invalid clause count '[parts[3]]'" unless wrat_unsigned_decimal?(parts[3])
        nvars = parts[2].to_i
        declared_clauses = parts[3].to_i
        have_header = true
      elsif b0 != 99
        raise "missing p cnf header" unless have_header
        while i < le
          while i < le
            b = text.byte_at(i)
            break unless b == 32 || b == 9 || b == 13
            i += 1
          break if i >= le

          ts = i
          b = text.byte_at(i)
          sign = 1
          has_sign = false
          if b == 45 || b == 43
            sign = -1 if b == 45
            has_sign = true
            i += 1

          val = 0
          digits = 0
          valid = true
          while i < le
            b = text.byte_at(i)
            break if b == 32 || b == 9 || b == 13
            if b >= 48 && b <= 57
              val = val * 10 + (b - 48)
              digits += 1
            else
              valid = false
            i += 1

          if !valid || digits == 0
            raise "invalid DIMACS token '[text.slice(ts, i - ts)]'"
          if val == 0
            if has_sign || digits > 1
              raise "signed or padded zero is not a clause terminator: '[text.slice(ts, i - ts)]'"
            clauses.push(current)
            current = []
            raise "too many clauses: header declared [declared_clauses]" if clauses.size > declared_clauses
          else
            lit = sign < 0 ? 0 - val : val
            raise "literal [lit] exceeds declared variable count [nvars]" if val > nvars
            current.push(lit)

  # A trailing clause with no terminating 0 is a truncated file, not an
  # empty clause -- surfacing it beats silently accepting a bad formula.
  raise "missing p cnf header" unless have_header
  raise "clause not terminated by 0" unless current.empty?
  unless clauses.size == declared_clauses
    raise "clause count mismatch: header declared [declared_clauses], parsed [clauses.size]"

  { "nvars": nvars, "clauses": clauses }

# Render a formula back to DIMACS text (used by specs and tooling).
-> wrat_to_dimacs(nvars, clauses)
  out = "p cnf [nvars] [clauses.size]\n"
  clauses.each -> (c)
    out = out + c.join(" ") + " 0\n"
  out
