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
  line.split(" ").each -> (t)
    t.split("\t").each -> (u)
      piece = u.strip
      out.push(piece) unless piece == ""
  out

# A checker must never guess: a token is an integer only if it is entirely
# decimal digits with an optional leading sign. `to_i` accepts numeric
# prefixes and turns arbitrary text into 0, either of which would silently
# change what is being verified.
-> wrat_int_token?(token)
  return false if token == nil || token.empty?
  first = token.slice(0, 1)
  start = 0
  start = 1 if first == "-" || first == "+"
  return false if start == token.size
  i = start
  while i < token.size
    return false if "0123456789".index(token.slice(i, 1)) == nil
    i += 1
  true

# Parse DIMACS CNF text into {"nvars", "clauses"}.
#
# Accepts `c` comment lines and a `p cnf <vars> <clauses>` header.  Clauses
# may span lines; each is terminated by a literal 0.
-> wrat_parse_cnf(text)
  nvars = 0
  clauses = []
  current = []

  # A `%` line ends the clause section. SATLIB files close with "%\n0\n",
  # and reading that trailing 0 as a clause terminator would append an empty
  # clause -- silently turning every satisfiable instance unsatisfiable.
  done = false
  text.split("\n").each -> (raw)
    line = raw.strip
    done = true if line.starts_with?("%")
    unless done || line == "" || line.starts_with?("c")
      if line.starts_with?("p")
        parts = wrat_tokenize(line)
        raise "malformed p-line: [line]" if parts.size < 4
        raise "only 'cnf' is supported, got '[parts[1]]'" unless parts[1] == "cnf"
        raise "invalid variable count '[parts[2]]'" unless wrat_int_token?(parts[2])
        nvars = parts[2].to_i
      else
        wrat_tokenize(line).each -> (tok)
          raise "invalid DIMACS token '[tok]'" unless wrat_int_token?(tok)
          lit = tok.to_i
          if lit == 0
            raise "signed or padded zero is not a clause terminator: '[tok]'" unless tok == "0"
            clauses.push(current)
            current = []
          else
            current.push(lit)
            v = lit.abs
            nvars = v if v > nvars

  # A trailing clause with no terminating 0 is a truncated file, not an
  # empty clause -- surfacing it beats silently accepting a bad formula.
  raise "clause not terminated by 0" unless current.empty?

  { "nvars": nvars, "clauses": clauses }

# Render a formula back to DIMACS text (used by specs and tooling).
-> wrat_to_dimacs(nvars, clauses)
  out = "p cnf [nvars] [clauses.size]\n"
  clauses.each -> (c)
    out = out + c.join(" ") + " 0\n"
  out
