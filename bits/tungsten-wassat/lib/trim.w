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

# Parse one hinted line into {"id", "lits", "hints", "delete"}.
-> wassat_trim_parse_line(line)
  toks = wassat_tokenize(line)
  return nil if toks.empty?
  id = toks[0].to_i
  return nil if id == 0 && toks[0] != "0"
  if toks.size > 1 && toks[1] == "d"
    { "id": id, "lits": [], "hints": [], "delete": true }
  else
    lits = []
    hints = []
    seen_zero = false
    i = 1
    while i < toks.size
      v = toks[i].to_i
      if v == 0 && toks[i] == "0"
        break if seen_zero
        seen_zero = true
      else
        if seen_zero
          hints.push(v)
        else
          lits.push(v)
      i += 1
    { "id": id, "lits": lits, "hints": hints, "delete": false }

# Trim hinted proof text (wrat header optional). Returns
# {"text", "kept", "total", "found_empty"}; "text" preserves the header iff
# the input carried one.
-> wassat_trim_hinted(proof_text)
  had_header = false
  steps = []
  proof_text.split("\n").each -> (raw)
    line = raw.strip
    unless line == "" || line.starts_with?("c")
      if line.starts_with?("wrat")
        had_header = true
      else
        st = wassat_trim_parse_line(line)
        steps.push(st) unless st == nil

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
  trimmed_text.split("\n").each -> (raw)
    line = raw.strip
    unless line == "" || line.starts_with?("c") || line.starts_with?("wrat")
      st = wassat_trim_parse_line(line)
      unless st == nil || st["delete"]
        out.push(st["lits"].empty? ? "0" : st["lits"].join(" ") + " 0")
  out.empty? ? "" : out.join("\n") + "\n"

# CLI: `wassat trim <proof.wrat> --out <path> [--drat <path>]`.
-> wassat_run_trim(args)
  input = nil
  out_path = nil
  drat_path = nil
  i = 0
  while i < args.size
    flag = args[i]
    if flag == "--out" || flag == "--drat"
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
  raise "trim output must not overwrite the input proof" if wassat_same_file?(out_path, input)
  text = read_file(input)
  raise "cannot read proof '[input]'" if text == nil
  r = wassat_trim_hinted(text)
  raise "no empty-clause step found; not a refutation" unless r["found_empty"]
  raise "trim write failed at '[out_path]'" unless write_file(out_path, r["text"])
  unless drat_path == nil
    raise "trim output must not overwrite the input proof" if wassat_same_file?(drat_path, input)
    raise "trim write failed at '[drat_path]'" unless write_file(drat_path, wassat_trim_to_drat(r["text"]))
  << "c trim: kept [r["kept"]] of [r["total"]] additions"
  0
