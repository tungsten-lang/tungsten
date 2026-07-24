# Proof trimming (E5) -- backward pruning of hinted certificates.
#
# A refutation ends at its first empty-clause addition; everything the
# checker replays is reachable from that step through hint citations. The
# trimmer marks the terminal step, closes backward over hints (input-clause
# ids need no marking -- the checker always has the formula), and emits only
# the needed additions in their original order. Deletions are dropped
# entirely: deleting only ever weakens a formula, so keeping clauses alive
# can never invalidate a RUP step -- hinted replay touches only cited
# clauses, and unhinted RUP is monotone in the clause set.
#
# The trimmer is untrusted by construction: its output is re-verified by
# wrat and drat-trim (the E5 gate), so a trimming bug can lose a
# certificate but never certify a wrong one.
#
# This parses wassat's OWN emitted format. It shares nothing with
# tungsten-wrat -- the checker's independence is untouched.

# Parse one hinted line into {"id", "lits", "hints", "delete"}. This is an
# artifact boundary, so every terminator and integer is exact: malformed
# lines are rejected rather than silently shortened by String#to_i.
-> wassat_trim_integer(token, label, allow_zero)
  raise "invalid [label] token '[token]'" unless wassat_literal_token?(token)
  sign = 1
  start = 0
  first = token.slice(0, 1)
  if first == "-" || first == "+"
    sign = -1 if first == "-"
    start = 1
  digits = token.slice(start, token.size - start)
  magnitude = wassat_decimal_in_range(label, digits, allow_zero ? 0 : 1, 2000000000)
  sign * magnitude

-> wassat_trim_parse_line(line)
  toks = wassat_tokenize(line)
  return nil if toks.empty?
  id = wassat_decimal_in_range("proof id", toks[0], 1, 2000000000)
  if toks.size > 1 && toks[1] == "d"
    raise "malformed hinted deletion: expected '<id> d <ids> 0'" if toks.size < 4 || toks[toks.size - 1] != "0"
    ids = []
    i = 2
    while i + 1 < toks.size
      ids.push(wassat_decimal_in_range("deleted clause id", toks[i], 1, 2000000000))
      i += 1
    { "id": id, "lits": [], "hints": ids, "delete": true }
  else
    raise "malformed hinted addition: expected two 0 terminators" if toks.size < 3
    lits = []
    hints = []
    seen_zero = false
    closed = false
    i = 1
    while i < toks.size
      tok = toks[i]
      if tok == "0"
        if seen_zero
          closed = true
          raise "trailing token after hinted proof terminator" unless i == toks.size - 1
        else
          seen_zero = true
      else
        raise "trailing token after hinted proof terminator" if closed
        if seen_zero
          hints.push(wassat_decimal_in_range("proof hint", tok, 1, 2000000000))
        else
          lits.push(wassat_trim_integer(tok, "proof literal", false))
      i += 1
    raise "malformed hinted addition: expected two 0 terminators" unless closed
    { "id": id, "lits": lits, "hints": hints, "delete": false }

# Trim hinted proof text (wrat header optional). Returns
# {"text", "kept", "total", "found_empty"}; "text" preserves the header iff
# the input carried one.
-> wassat_trim_hinted(proof_text)
  had_header = false
  saw_body = false
  defined = {}
  steps = []
  proof_text.split("\n").each -> (raw)
    line = raw.strip
    unless line == "" || line.starts_with?("c")
      toks = wassat_tokenize(line)
      if toks[0] == "wrat"
        raise "malformed WRAT header" unless toks.size == 2 && toks[1] == "1"
        raise "WRAT header must precede every proof step" if saw_body
        raise "duplicate WRAT header" if had_header
        had_header = true
      else
        st = wassat_trim_parse_line(line)
        saw_body = true
        unless st["delete"]
          raise "duplicate proof addition id [st["id"]]" if defined.has_key?(st["id"])
          defined[st["id"]] = steps.size
        steps.push(st)

  # A derived hint may cite only an earlier derived step. IDs absent from
  # this map are input-clause citations and remain valid without the CNF.
  i = 0
  while i < steps.size
    st = steps[i]
    st["hints"].each -> (h)
      if defined.has_key?(h) && defined[h] >= i
        raise "proof step [st["id"]] cites non-earlier derived id [h]"
    i += 1

  # locate the terminal step: the FIRST empty-clause addition
  terminal = -1
  i = 0
  while i < steps.size && terminal < 0
    st = steps[i]
    terminal = i if st["delete"] == false && st["lits"].empty?
    i += 1
  total_adds = 0
  steps.each -> (st)
    total_adds += 1 unless st["delete"]
  if terminal < 0
    # not a refutation; nothing safe to trim
    return { "text": proof_text, "kept": total_adds, "total": total_adds,
             "found_empty": false }

  # id -> step index for derived steps (input ids resolve to nothing here,
  # which is exactly right: the checker owns the formula)
  index_of = {}
  i = 0
  while i <= terminal
    st = steps[i]
    index_of[st["id"]] = i unless st["delete"]
    i += 1

  needed = {}
  needed[steps[terminal]["id"]] = true
  work = [terminal]
  wi = 0
  while wi < work.size
    st = steps[work[wi]]
    st["hints"].each -> (h)
      if index_of.has_key?(h) && !needed.has_key?(h)
        needed[h] = true
        work.push(index_of[h])
    wi += 1

  out = []
  kept = 0
  i = 0
  while i <= terminal
    st = steps[i]
    if st["delete"] == false && needed.has_key?(st["id"])
      kept += 1
      body = st["lits"].empty? ? "" : st["lits"].join(" ") + " "
      out.push("[st["id"]] " + body + "0 " + st["hints"].join(" ") + " 0")
    i += 1

  text = out.join("\n") + "\n"
  text = "wrat 1\n" + text if had_header
  { "text": text, "kept": kept, "total": total_adds, "found_empty": true }

# Render a trimmed hinted proof as plain DRAT (drop ids and hints).
-> wassat_trim_to_drat(trimmed_text)
  out = []
  had_header = false
  saw_body = false
  trimmed_text.split("\n").each -> (raw)
    line = raw.strip
    unless line == "" || line.starts_with?("c")
      toks = wassat_tokenize(line)
      if toks[0] == "wrat"
        raise "malformed WRAT header" unless toks.size == 2 && toks[1] == "1"
        raise "WRAT header must precede every proof step" if saw_body
        raise "duplicate WRAT header" if had_header
        had_header = true
      else
        saw_body = true
        st = wassat_trim_parse_line(line)
        unless st == nil || st["delete"]
          out.push(st["lits"].empty? ? "0" : st["lits"].join(" ") + " 0")
  out.empty? ? "" : out.join("\n") + "\n"

# CLI: `wassat trim <proof.wrat> --out <path> [--drat <path>]`.
-> wassat_run_trim(args)
  input = nil
  out_path = nil
  drat_path = nil
  seen = {}
  i = 0
  while i < args.size
    flag = args[i]
    if flag == "--out" || flag == "--drat"
      raise "duplicate wassat trim option: [flag]" if seen[flag] == true
      seen[flag] = true
      raise "missing value after [flag]" if i + 1 >= args.size
      if flag == "--out"
        out_path = args[i + 1]
      else
        drat_path = args[i + 1]
      i += 2
    elsif flag.starts_with?("--")
      raise "unknown wassat trim option: [flag]"
    else
      raise "unexpected extra argument '[flag]'" unless input == nil
      input = flag
      i += 1
  raise "missing input proof" if input == nil
  raise "missing --out destination" if out_path == nil
  raise "trim outputs must be files, not stdout" if out_path == "-" || drat_path == "-"
  raise "trim output must not overwrite the input proof" if wassat_same_file?(out_path, input)
  text = read_file(input)
  raise "cannot read proof '[input]'" if text == nil
  unless drat_path == nil
    raise "trim output must not overwrite the input proof" if wassat_same_file?(drat_path, input)
    raise "trim outputs need different destinations" if wassat_same_file?(out_path, drat_path)
  wassat_clear_output(out_path, input, "trimmed proof")
  wassat_clear_output(drat_path, input, "trimmed DRAT")
  r = wassat_trim_hinted(text)
  raise "no empty-clause step found; not a refutation" unless r["found_empty"]
  out_tmp = wassat_reserve_output(out_path, input, "trimmed proof")
  drat_tmp = nil
  begin
    drat_tmp = wassat_reserve_output(drat_path, input, "trimmed DRAT")
  rescue e
    wassat_discard_output(out_tmp, out_path)
    raise e
  unless write_file(out_tmp, r["text"])
    wassat_discard_output(out_tmp, out_path)
    wassat_discard_output(drat_tmp, drat_path)
    raise "trim write failed at '[out_path]'"
  unless drat_path == nil
    unless write_file(drat_tmp, wassat_trim_to_drat(r["text"]))
      wassat_discard_output(out_tmp, out_path)
      wassat_discard_output(drat_tmp, drat_path)
      raise "trim write failed at '[drat_path]'"
  wassat_publish_output(out_tmp, out_path, "trimmed proof")
  wassat_publish_output(drat_tmp, drat_path, "trimmed DRAT") unless drat_path == nil
  << "c trim: kept [r["kept"]] of [r["total"]] additions"
  0
