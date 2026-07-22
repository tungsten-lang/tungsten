# Proof parsing for WRAT, LRAT and DRAT.
#
# A parsed step is the record
#
#   {"kind": "a"|"d", "id": Int, "lits": Array, "hints": Array}
#
# For deletions, "lits" is empty and "hints" holds the clause ids to drop
# (DRAT deletes by literal content instead, in which case "lits" holds them
# and "id" is 0).
#
# Three input dialects are recognised:
#
#   WRAT  `wrat 1` header, then  <id> <lits> 0 <hints> 0   /  <id> d <ids> 0
#   LRAT  same body, no header
#   DRAT  <lits> 0                                          /  d <lits> 0
#
# WRAT and LRAT carry a unit-propagation hint chain, which is what makes
# checking near-linear: the checker replays the named clauses in order
# instead of searching for a propagation sequence.


use dimacs

# Detect the dialect of a proof body: "wrat", "lrat" or "drat".
-> wrat_detect_format(text)
  fmt = "drat"
  decided = false
  text.split("\n").each -> (raw)
    unless decided
      line = raw.strip
      unless line == "" || line.starts_with?("c")
        if line.starts_with?("wrat")
          fmt = "wrat"
          decided = true
        else
          toks = wrat_tokenize(line)
          # `d ...` is a DRAT deletion; `<id> d ...` is LRAT/WRAT.
          if toks[0] == "d"
            fmt = "drat"
            decided = true
          elsif toks.size > 1 && toks[1] == "d"
            fmt = "lrat"
            decided = true
          else
            # Hinted additions carry two 0 terminators, DRAT only one.
            zeros = 0
            toks.each -> (t)
              zeros += 1 if t.to_i == 0 && t == "0"
            fmt = zeros >= 2 ? "lrat" : "drat"
            decided = true
  fmt

# A proof token that is not an exact integer (or the deletion marker `d`
# where the dialect allows it) is a malformed certificate, not something to
# coerce: `to_i` would turn garbage into 0 and silently truncate the step.
-> wrat_proof_int(tok)
  raise "invalid proof token '[tok]'" unless wrat_int_token?(tok)
  tok.to_i

# Parse one hinted (WRAT/LRAT) line into a step.
-> wrat_parse_hinted_line(toks)
  id = wrat_proof_int(toks[0])
  if toks[1] == "d"
    ids = []
    i = 2
    while i < toks.size
      v = wrat_proof_int(toks[i])
      ids.push(v) unless v == 0
      i += 1
    { "kind": "d", "id": id, "lits": [], "hints": ids }
  else
    lits = []
    hints = []
    i = 1
    seen_zero = false
    while i < toks.size
      v = wrat_proof_int(toks[i])
      if v == 0
        # The first 0 closes the literals, the second closes the hints.
        break if seen_zero
        seen_zero = true
      else
        if seen_zero
          hints.push(v)
        else
          lits.push(v)
      i += 1
    { "kind": "a", "id": id, "lits": lits, "hints": hints }

# Parse one DRAT line into a step (no ids, no hints).
-> wrat_parse_drat_line(toks)
  if toks[0] == "d"
    lits = []
    i = 1
    while i < toks.size
      v = wrat_proof_int(toks[i])
      lits.push(v) unless v == 0
      i += 1
    { "kind": "d", "id": 0, "lits": lits, "hints": [] }
  else
    lits = []
    i = 0
    while i < toks.size
      v = wrat_proof_int(toks[i])
      lits.push(v) unless v == 0
      i += 1
    { "kind": "a", "id": 0, "lits": lits, "hints": [] }

# Parse proof text into {"format": String, "steps": Array}.
-> wrat_parse_proof(text)
  fmt = wrat_detect_format(text)
  hinted = fmt == "wrat" || fmt == "lrat"
  steps = []
  text.split("\n").each -> (raw)
    line = raw.strip
    unless line == "" || line.starts_with?("c") || line.starts_with?("wrat")
      toks = wrat_tokenize(line)
      unless toks.empty?
        steps.push(hinted ? wrat_parse_hinted_line(toks) : wrat_parse_drat_line(toks))
  { "format": fmt, "steps": steps }
