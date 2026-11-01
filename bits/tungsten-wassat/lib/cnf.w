# DIMACS CNF parsing for Wassat.
#
# This deliberately duplicates the parser in tungsten-wrat rather than
# sharing it.  A proof checker is only worth running if it has no code in
# common with the solver whose work it audits: a shared parser bug could
# make both agree on a formula that is not the one on disk.  The duplication
# is the feature.

# Phase profiling for the speed campaign: WASSAT_PROFILE=1 prints per-phase
# wall times to stderr (stderr so `s ` verdict parsing stays clean). Returns
# the current clock so call sites chain: t = wassat_prof("phase", t).
-> wassat_prof(label, since_ms)
  return 0 unless env("WASSAT_PROFILE") == "1"
  t = ccall("__w_clock_ms")
  z = ccall("__w_eprint", "c prof [label] [t - since_ms]ms\n")
  t

# A profile line that reports a measurement other than elapsed time — the
# shape of a preprocessed rendering, say. Same gate, same stream, so it never
# reaches a harness parsing stdout.
-> wassat_prof_note(text)
  return 0 unless env("WASSAT_PROFILE") == "1"
  z = ccall("__w_eprint", "c prof [text]\n")
  0

# Clock a phase start only when profiling: the ccall is unavailable in the
# interpreter, where the spec suite runs these paths.
-> wassat_prof_clock
  return 0 unless env("WASSAT_PROFILE") == "1"
  ccall("__w_clock_ms")

# Split a line into non-empty whitespace-separated tokens. DIMACS permits
# tabs as well as spaces, so each space-split piece is split again on tabs;
# strip disposes of any carriage returns.
-> wassat_tokenize(line)
  out = []
  n = line.size
  i = 0
  while i < n
    while i < n && line.byte_at(i) <= 32
      i += 1
    break if i >= n
    start = i
    while i < n && line.byte_at(i) > 32
      i += 1
    out.push(line.slice(start, i - start))
  out

# DIMACS counts are non-negative decimal integers.  Do not use String#to_i
# for validation: it deliberately accepts a numeric prefix and, more
# dangerously for a SAT parser, turns arbitrary text such as `x` into zero.
-> wassat_unsigned_decimal?(token)
  return false if token == nil
  n = token.size
  return false if n == 0
  i = 0
  while i < n
    b = token.byte_at(i)
    return false if b < 48 || b > 57
    i += 1
  true

# A DIMACS literal is a decimal integer with an optional sign.  Signed zero
# is not a clause terminator: the grammar reserves the exact token `0` for
# that purpose.
-> wassat_literal_token?(token)
  return false if token == nil
  n = token.size
  return false if n == 0
  b0 = token.byte_at(0)
  start = 0
  start = 1 if b0 == 45 || b0 == 43
  return false if start == n
  all_zero = true
  i = start
  while i < n
    b = token.byte_at(i)
    return false if b < 48 || b > 57
    all_zero = false if b != 48
    i += 1
  # `00`, `+0`, `-0`, and their longer forms are numerically zero but are
  # not the exact DIMACS terminator token.
  return false if all_zero && !(n == 1 && b0 == 48)
  true

# Native-parser entry: the C extern tokenizes and validates strict DIMACS
# straight into flat i64 buffers (the boxed splitting below cost ~200ms on
# 200k-clause files); boxed clauses are then built by a cheap array walk.
# Validation matrix matches wassat_parse_cnf exactly — the spec suite runs
# the same rejection cases against both.
# Boxed clause list, materialized on demand and cached in the formula.
#
# MAIN THREAD ONLY. Worker threads must read the flat mirrors instead --
# subscripting a boxed Array off-thread SIGBUSes, and two arms racing to
# materialize would duplicate the work anyway.
-> wassat_formula_clauses(formula)
  return formula["clauses"] if formula["boxed"] == true
  return formula["clauses"] unless formula.has_key?("flat_ncl")
  lits = formula["flat_lits"]
  offs = formula["flat_offs"]
  lens = formula["flat_lens"]
  ncl = formula["flat_ncl"]
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
  formula["clauses"] = clauses
  formula["boxed"] = true
  clauses

# Interpreter-only test double for the native parser. Algorithm specs need the
# flat parser result shape, not the C scanner itself; build that shape from the
# independently validated boxed parser so those specs do not require a native
# compile/link. The native-parser benchmark and compiled contracts still call
# __w_parse_dimacs directly.
-> wassat_parse_cnf_test_stub(text)
  parsed = wassat_parse_cnf(text)
  lits = []
  offs = []
  lens = []
  parsed["clauses"].each -> (clause)
    offs.push(lits.size)
    lens.push(clause.size)
    clause.each -> (lit)
      lits.push(lit)
  { "nvars": parsed["nvars"], "clauses": parsed["clauses"], "boxed": true,
    "flat_lits": lits, "flat_offs": offs, "flat_lens": lens,
    "flat_ncl": parsed["clauses"].size, "flat_nlits": lits.size }

-> wassat_parse_cnf_header_clauses(text) (String) i64
  limit = text.size
  limit = 65536 if limit > 65536
  i = 0
  while i < limit
    b = text.byte_at(i)
    if b == 112
      # "p cnf <nvars> <nclauses>" at start of line
      if i + 6 < limit && text.byte_at(i + 1) == 32 && text.byte_at(i + 2) == 99 && text.byte_at(i + 3) == 110 && text.byte_at(i + 4) == 102 && text.byte_at(i + 5) == 32
        j = i + 6
        while j < limit && text.byte_at(j) == 32
          j += 1
        while j < limit && text.byte_at(j) >= 48 && text.byte_at(j) <= 57
          j += 1
        while j < limit && text.byte_at(j) == 32
          j += 1
        decl = 0
        has_digit = false
        while j < limit && text.byte_at(j) >= 48 && text.byte_at(j) <= 57
          decl = decl * 10 + (text.byte_at(j) - 48)
          has_digit = true
          j += 1
        # A digit run cut by the hint window may be only a prefix of the
        # actual clause count. Ignore it and let the strict scanner decide.
        return decl if has_digit && decl > 0 && j < limit
    while i < limit && text.byte_at(i) != 10
      i += 1
    i += 1
  0

-> wassat_parse_cnf_native(text)
  if env("TUNGSTEN_WASSAT_PARSE_STUB") == "1"
    return wassat_parse_cnf_test_stub(text)
  # Every clause needs at least a "0" terminator plus a separator (2 bytes),
  # and every literal at least a digit plus a separator (2 bytes), so
  # text.size/2 bounds BOTH counts. On multi-hundred-MB DIMACS files (e.g.
  # 754 MB / 35.6M clauses), sizing offs and lens at text.size/2 allocates
  # >9 GiB before parsing begins, exceeding the 8 GiB process memory ceiling;
  # use the p-line clause count when present to tighten the initial caps.
  # Apply the same bounded hint scan to medium files too; byte-based clause
  # tables otherwise overallocate heavily even for a short scout solve.
  cap_l = text.size / 2 + 64
  fallback_l = cap_l
  cap_c = text.size / 2 + 64
  if text.size >= 65536
    decl = wassat_parse_cnf_header_clauses(text)
    if decl > 0 && decl + 64 < cap_c
      cap_c = decl + 64
      rem_bytes = text.size - 2 * decl
      if rem_bytes > 0
        fallback_l = rem_bytes / 2 + 64
        # Three bytes per literal is only an estimate, not a bound.
        # Short positive literals may require the conservative retry below.
        if text.size >= 400000000 && decl >= 20000000
          cap_l = rem_bytes / 3 + 64
        else
          cap_l = rem_bytes / 2 + 64
  wassat_parse_cnf_native_buffers(text, cap_l, cap_c, fallback_l)

# A small initial literal buffer is safe only with a bounded retry. The
# strict native scanner rewrites the same clause tables and header; nothing
# is published until it accepts the entire input. Keeping this boundary
# separate also lets native specs exercise exhaustion with small fixtures.
-> wassat_parse_cnf_native_buffers(text, cap_l, cap_c, fallback_l) (String i64 i64 i64)
  started = wassat_prof_clock()
  retries = 0
  lits = i64[cap_l]
  offs = i64[cap_c]
  lens = i64[cap_c]
  hdr = i64[8]
  z = ccall("__w_parse_dimacs", text, lits, offs, lens, hdr)
  err = hdr[4]
  if err == 7 && cap_l < fallback_l
    # The scanner retains no reference to these private buffers. Release
    # the failed literal allocation before making its larger replacement.
    z = ccall("w_value_free_w", lits)
    cap_l = fallback_l
    lits = i64[cap_l]
    retries = 1
    z = ccall("__w_parse_dimacs", text, lits, offs, lens, hdr)
    err = hdr[4]
  if env("WASSAT_PROFILE") == "1"
    z = wassat_prof("parse.native", started)
    z = wassat_prof_note("parse.native literals=[hdr[3]] clauses=[hdr[2]] literal_capacity=[cap_l] clause_capacity=[cap_c] retries=[retries] error=[err]")
  if err != 0
    msgs = { 1: "missing or duplicate p cnf header", 2: "malformed p-line",
             3: "invalid DIMACS token", 4: "literal exceeds declared variable count",
             5: "clause not terminated by 0", 6: "clause count mismatch",
             7: "input exceeds parser buffers", 8: "XNF/native XOR clauses are not supported; expand them to CNF" }
    raise "[msgs[err]] (line [hdr[5]])"
  nvars = hdr[0]
  raise "implausible variable count [nvars] in header" if nvars > 50000000
  ncl = hdr[2]
  # NO eager boxed materialization. Building one Array per clause cost ~60% of
  # parse time (302ms of 499ms on a 10M-clause instance) for data the flat
  # mirrors already hold: a clause IS the slice (flat_offs[k], flat_lens[k])
  # of flat_lits, exactly the way the Tungsten lexer keeps tokens as packed
  # (offset, length) slices of the source instead of copied strings.
  # Consumers that genuinely need boxed clauses call wassat_formula_clauses,
  # which materializes once and caches.
  { "nvars": nvars, "clauses": [], "boxed": false,
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
  len = text.size
  pos = 0
  while pos < len
    line_start = pos
    while pos < len && text.byte_at(pos) != 10
      pos += 1
    line_end = pos
    pos += 1 if pos < len

    s = line_start
    while s < line_end && text.byte_at(s) <= 32
      s += 1
    e = line_end
    while e > s && text.byte_at(e - 1) <= 32
      e -= 1

    if s < e && !done
      b0 = text.byte_at(s)
      if b0 == 37
        done = true
      else
        t0_end = s
        while t0_end < e && text.byte_at(t0_end) > 32
          t0_end += 1
        t0_len = t0_end - s
        # A comment marker is a token, not a prefix: `c anything` is a
        # comment, while `cat 1 0` is malformed clause input and must fail.
        unless t0_len == 1 && b0 == 99
          if t0_len == 1 && b0 == 112
            line = text.slice(s, e - s)
            parts = wassat_tokenize(line)
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
            if t0_len == 1 && b0 == 120
              raise "XNF/native XOR clauses are not supported; expand them to CNF"
            k = s
            while k < e
              while k < e && text.byte_at(k) <= 32
                k += 1
              break if k >= e
              ts = k
              while k < e && text.byte_at(k) > 32
                k += 1
              te = k
              tb0 = text.byte_at(ts)
              if te - ts == 1 && tb0 == 48
                clauses.push(current)
                current = []
                raise "too many clauses: declared [declared_clauses]" if clauses.size > declared_clauses
              else
                neg = false
                ds = ts
                if tb0 == 45
                  neg = true
                  ds = ts + 1
                elsif tb0 == 43
                  ds = ts + 1
                valid = ds < te
                val = 0
                di = ds
                while di < te
                  db = text.byte_at(di)
                  if db < 48 || db > 57
                    valid = false
                    break
                  val = val * 10 + (db - 48)
                  di += 1
                if !valid || val == 0
                  tok = text.slice(ts, te - ts)
                  raise "invalid DIMACS token '[tok]'"
                lit = neg ? 0 - val : val
                current.push(lit)
                raise "literal [lit] exceeds declared variable count [nvars]" if val > nvars

  raise "missing p cnf header" unless have_header
  raise "clause not terminated by 0" unless current.empty?
  unless clauses.size == declared_clauses
    raise "clause count mismatch: declared [declared_clauses], parsed [clauses.size]"

  { "nvars": nvars, "clauses": clauses }

# Exact equisatisfiable quotient for formulas built by substituting 2-variable
# OR gadgets (g_p = x_{2p-1} | x_{2p}) or XOR gadgets (g_p = x_{2p-1} ^ x_{2p})
# into a base CNF and expanding each clause into its consecutive 2^t block.
# Setting x_{2p} = false for every verified gadget pair collapses each 2^t
# block to the single quotient clause on the odd variables x_{2p-1}.
-> wassat_try_or_gadget_quotient(formula)
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  pair_p = i64[16]
  pair_k = i64[16]

  # Pass 1: verify every consecutive block of 2^t clauses
  ci = 0
  blocks = 0
  total_lits = 0
  while ci < ncl
    n0 = fcl[ci]
    return 0 if n0 < 2 || n0 > 16
    off0 = fcs[ci]
    j = 0
    np = 0
    t = 0
    while j < n0
      return 0 if np >= 16
      l1 = fla[off0 + j]
      v1 = l1 < 0 ? 0 - l1 : l1
      p1 = (v1 + 1) / 2
      same_p = false
      if j + 1 < n0
        l2 = fla[off0 + j + 1]
        v2 = l2 < 0 ? 0 - l2 : l2
        same_p = (v2 + 1) / 2 == p1
      if same_p
        return 0 unless l1 == 2 * p1 - 1 && fla[off0 + j + 1] == 2 * p1
        pair_p[np] = p1
        pair_k[np] = 1
        np += 1
        j += 2
      else
        return 0 unless l1 == 0 - (2 * p1 - 1)
        pair_p[np] = p1
        pair_k[np] = 2
        np += 1
        t += 1
        j += 1
    span = 1 << t
    return 0 if t == 0 && ci == 0 && (ci + 1 >= ncl || fcl[ci + 1] == n0)
    return 0 if ci + span > ncl
    m = 0
    while m < span
      return 0 unless fcl[ci + m] == n0
      offm = fcs[ci + m]
      pos = 0
      bit_idx = t - 1
      pi = 0
      while pi < np
        p = pair_p[pi]
        if pair_k[pi] == 1
          return 0 unless fla[offm + pos] == 2 * p - 1 && fla[offm + pos + 1] == 2 * p
          pos += 2
        else
          b = (m >> bit_idx) & 1
          bit_idx -= 1
          want = b == 1 ? 0 - (2 * p) : 0 - (2 * p - 1)
          return 0 unless fla[offm + pos] == want
          pos += 1
        pi += 1
      m += 1
    ci += span
    blocks += 1
    total_lits += np
  return 0 if blocks < 4 || blocks >= ncl

  # Pass 2: emit the collapsed quotient clauses
  out_lits = i64[total_lits]
  out_offs = i64[blocks]
  out_lens = i64[blocks]
  ci = 0
  bi = 0
  lpos = 0
  while ci < ncl
    n0 = fcl[ci]
    off0 = fcs[ci]
    out_offs[bi] = lpos
    j = 0
    np = 0
    t = 0
    while j < n0
      l1 = fla[off0 + j]
      v1 = l1 < 0 ? 0 - l1 : l1
      p1 = (v1 + 1) / 2
      same_p = false
      if j + 1 < n0
        l2 = fla[off0 + j + 1]
        v2 = l2 < 0 ? 0 - l2 : l2
        same_p = (v2 + 1) / 2 == p1
      if same_p
        out_lits[lpos] = 2 * p1 - 1
        lpos += 1
        np += 1
        j += 2
      else
        out_lits[lpos] = 0 - (2 * p1 - 1)
        lpos += 1
        np += 1
        t += 1
        j += 1
    out_lens[bi] = np
    bi += 1
    ci += (1 << t)
  formula["flat_lits"] = out_lits
  formula["flat_offs"] = out_offs
  formula["flat_lens"] = out_lens
  formula["flat_ncl"] = blocks
  formula["flat_nlits"] = lpos
  1

-> wassat_try_xor_gadget_quotient(formula)
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  pair_l1 = i64[16]
  pair_l2 = i64[16]

  ci = 0
  blocks = 0
  total_lits = 0
  while ci < ncl
    n0 = fcl[ci]
    return 0 if n0 < 4 || n0 > 16 || (n0 & 1) != 0
    t = n0 / 2
    off0 = fcs[ci]
    j = 0
    while j < t
      l1 = fla[off0 + 2 * j]
      l2 = fla[off0 + 2 * j + 1]
      v1 = l1 < 0 ? 0 - l1 : l1
      v2 = l2 < 0 ? 0 - l2 : l2
      p = (v1 + 1) / 2
      return 0 unless v1 == 2 * p - 1 && v2 == 2 * p
      pair_l1[j] = l1
      pair_l2[j] = l2
      j += 1
    span = 1 << t
    return 0 if ci + span > ncl
    m = 0
    while m < span
      return 0 unless fcl[ci + m] == n0
      offm = fcs[ci + m]
      j = 0
      while j < t
        b = (m >> (t - 1 - j)) & 1
        w1 = b == 0 ? pair_l1[j] : 0 - pair_l1[j]
        w2 = b == 0 ? pair_l2[j] : 0 - pair_l2[j]
        return 0 unless fla[offm + 2 * j] == w1 && fla[offm + 2 * j + 1] == w2
        j += 1
      m += 1
    ci += span
    blocks += 1
    total_lits += t
  return 0 if blocks < 4 || blocks >= ncl

  out_lits = i64[total_lits]
  out_offs = i64[blocks]
  out_lens = i64[blocks]
  ci = 0
  bi = 0
  lpos = 0
  while ci < ncl
    n0 = fcl[ci]
    t = n0 / 2
    off0 = fcs[ci]
    out_offs[bi] = lpos
    out_lens[bi] = t
    j = 0
    while j < t
      l1 = fla[off0 + 2 * j]
      l2 = fla[off0 + 2 * j + 1]
      out_lits[lpos] = l2 > 0 ? l1 : 0 - l1
      lpos += 1
      j += 1
    bi += 1
    ci += (1 << t)
  formula["flat_lits"] = out_lits
  formula["flat_offs"] = out_offs
  formula["flat_lens"] = out_lens
  formula["flat_ncl"] = blocks
  formula["flat_nlits"] = lpos
  1

-> wassat_apply_pair_gadget_quotient(formula)
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return 0 if nv < 8 || (nv & 1) != 0 || ncl < 8 || ncl > 600000
  fcl = formula["flat_lens"] ## i64[]
  n0 = fcl[0]
  return 0 if n0 < 2 || n0 > 16
  return 1 if wassat_try_or_gadget_quotient(formula) == 1
  return 1 if wassat_try_xor_gadget_quotient(formula) == 1
  0
