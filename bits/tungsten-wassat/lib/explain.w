# Certificate narration (E6) -- map a trimmed core back to problem language.
#
# E1's encoders write a `.labels` sidecar per certified instance: one line
# per input clause, `<1-based id>\t<constraint in problem language>`. This
# module walks an (E5-trimmed) hinted proof, collects every INPUT clause its
# hint chains cite -- an id is an input citation iff no addition step in the
# proof defines it -- and narrates those constraints grouped by label.
#
# The doneness gate is mechanical, per the plan: every cited input id must
# be present in the labels sidecar ("missing" must come back empty), and
# every id named in the narration is cited by the trimmed core. Prose
# quality is explicitly unspecced.

# Parse a labels sidecar into {id -> label}.
-> wassat_labels_parse(text)
  out = {}
  text.split("\n").each -> (raw)
    line = raw.strip
    unless line == ""
      tab = line.index("\t")
      raise "malformed labels line '[line]': expected '<id><tab><label>'" if tab == nil
      id_tok = line.slice(0, tab)
      label = line.slice(tab + 1, line.size - tab - 1)
      raise "empty label for input clause [id_tok]" if label == ""
      raise "labels must not contain tab characters" unless label.index("\t") == nil
      id = wassat_decimal_in_range("label clause id", id_tok, 1, 2000000000)
      raise "duplicate label clause id [id]" if out.has_key?(id)
      out[id] = label
  out

# Analyze a hinted proof against a labels map. Returns
#   {"used": [[id, label] ...] in first-citation order,
#    "missing": ids cited but unlabeled,
#    "derived_steps": addition count, "input_citations": count}
-> wassat_explain(proof_text, labels)
  # Validate the complete hinted document before deriving any narration.
  validated = wassat_trim_hinted(proof_text)
  defined = {}
  steps = []
  had_header = false
  saw_body = false
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
        saw_body = true
        st = wassat_trim_parse_line(line)
        unless st == nil || st["delete"]
          steps.push(st)
          defined[st["id"]] = true

  used_ids = []
  seen = {}
  citations = 0
  steps.each -> (st)
    st["hints"].each -> (h)
      unless defined.has_key?(h)
        citations += 1
        unless seen.has_key?(h)
          seen[h] = true
          used_ids.push(h)

  used = []
  missing = []
  used_ids.each -> (id)
    if labels.has_key?(id)
      used.push([id, labels[id]])
    else
      missing.push(id)
  { "used": used, "missing": missing,
    "derived_steps": steps.size, "input_citations": citations }

# Group narration: one line per distinct label with its citation count,
# ordered by first citation. Sinz-register noise collapses naturally --
# every register clause of one constraint carries the same label.
-> wassat_explain_text(report)
  counts = {}
  order = []
  report["used"].each -> (pair)
    label = pair[1]
    if counts.has_key?(label)
      counts[label] = counts[label] + 1
    else
      counts[label] = 1
      order.push(label)
  lines = []
  lines.push("c the refutation rests on [report["used"].size] input constraints across [order.size] groups:")
  order.each -> (label)
    n = counts[label]
    suffix = n == 1 ? "" : " (x[n])"
    lines.push("c   - [label][suffix]")
  lines.join("\n") + "\n"

# CLI: `wassat explain <proof.wrat> --labels <path>`. Trim first for a
# faithful "what the refutation rests on"; explaining an untrimmed proof
# reports everything the search touched instead.
-> wassat_run_explain(args)
  input = nil
  labels_path = nil
  labels_seen = false
  i = 0
  while i < args.size
    flag = args[i]
    if flag == "--labels"
      raise "duplicate --labels option" if labels_seen
      labels_seen = true
      raise "missing value after [flag]" if i + 1 >= args.size
      labels_path = args[i + 1]
      i += 2
    elsif flag.starts_with?("--")
      raise "unknown wassat explain option: [flag]"
    else
      raise "unexpected extra argument '[flag]'" unless input == nil
      input = flag
      i += 1
  raise "missing input proof" if input == nil
  raise "missing --labels sidecar" if labels_path == nil
  proof_text = read_file(input)
  raise "cannot read proof '[input]'" if proof_text == nil
  labels_text = read_file(labels_path)
  raise "cannot read labels '[labels_path]'" if labels_text == nil
  labels = wassat_labels_parse(labels_text)
  report = wassat_explain(proof_text, labels)
  unless report["missing"].empty?
    raise "cited input ids missing from the labels sidecar: [report["missing"].join(" ")]"
  print(wassat_explain_text(report))
  << "c derived steps: [report["derived_steps"]], input citations: [report["input_citations"]]"
  0
