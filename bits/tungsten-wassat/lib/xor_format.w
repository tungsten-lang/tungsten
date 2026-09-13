# CryptoMiniSat-style DIMACS+XOR interchange, explicitly lowered to CNF.
# x1 -2 3 0 and x 1 -2 3 0 mean XOR of the signed literals equals true.
# This is not general XNF (XORs of arbitrary clauses), nor a Gaussian solver.
# Proof consumers check the emitted CNF, not the unexpanded input file.

-> wassat_xor_emit(state, input)
  rhs = 1
  parity = {}
  input.each -> (lit)
    rhs = 1 - rhs if lit < 0
    v = lit.abs
    parity[v] = parity[v] != true
  vars = []
  parity.keys.sort.each -> (v)
    vars.push(v) if parity[v]
  clauses = state["clauses"]
  if vars.empty?
    clauses.push([]) if rhs == 1
  elsif vars.size == 1
    clauses.push([rhs == 1 ? vars[0] : 0 - vars[0]])
  else
    left = vars[0]
    i = 1
    while i < vars.size - 1
      right = vars[i]
      state["nvars"] += 1
      raise "expanded variable count exceeds 50000000" if state["nvars"] > 50000000
      out = state["nvars"]
      clauses.push([left, right, 0 - out])
      clauses.push([0 - left, 0 - right, 0 - out])
      clauses.push([left, 0 - right, out])
      clauses.push([0 - left, right, out])
      left = out
      i += 1
    right = vars[vars.size - 1]
    if rhs == 1
      clauses.push([left, right])
      clauses.push([0 - left, 0 - right])
    else
      clauses.push([left, 0 - right])
      clauses.push([0 - left, right])

-> wassat_expand_xor(text)
  state = { "nvars": 0, "clauses": [] }
  original = 0
  declared = 0
  parsed = 0
  nxor = 0
  header = false
  done = false
  current = []
  is_xor = false
  text.split("\n").each -> (raw)
    line = raw.strip
    done = true if line.starts_with?("%")
    unless done || line.empty?
      parts = wassat_tokenize(line)
      unless parts[0] == "c"
        if parts[0] == "p"
          raise "duplicate DIMACS+XOR header" if header
          raise "expected p cnf V C" unless parts.size == 4 && parts[1] == "cnf"
          raise "invalid variable count" unless wassat_unsigned_decimal?(parts[2])
          raise "invalid clause count" unless wassat_unsigned_decimal?(parts[3])
          original = parts[2].to_i
          declared = parts[3].to_i
          raise "implausible variable count" if original > 50000000
          raise "implausible clause count" if declared > 200000000
          state["nvars"] = original
          header = true
        else
          raise "missing p cnf header" unless header
          # An XOR marker is legal only at the beginning of a new clause.
          # The attached first literal is tokenized by the same strict rules.
          if parts[0].starts_with?("x")
            raise "XOR marker inside an unfinished clause" unless current.empty? && !is_xor
            is_xor = true
            token = parts[0].slice(1, parts[0].size - 1)
            parts[0] = token
          parts.each_with_index -> (tok, index)
            unless index == 0 && tok.empty? && is_xor
              raise "invalid DIMACS+XOR literal '[tok]'" unless wassat_literal_token?(tok)
              if tok == "0"
                parsed += 1
                raise "too many input clauses" if parsed > declared
                if is_xor
                  wassat_xor_emit(state, current)
                  nxor += 1
                else
                  state["clauses"].push(current)
                current = []
                is_xor = false
              else
                lit = tok.to_i
                raise "literal exceeds original variable count" if lit.abs > original
                current.push(lit)
          raise "expanded clause count exceeds 200000000" if state["clauses"].size > 200000000
  raise "missing p cnf header" unless header
  raise "unterminated input clause" unless current.empty? && !is_xor
  raise "input clause count mismatch" unless parsed == declared
  state["original_nvars"] = original
  state["input_clauses"] = parsed
  state["xor_clauses"] = nxor
  state

-> wassat_expanded_xor_text(formula)
  lines = []
  lines.push("c Wassat DIMACS+XOR expansion; original variables 1..[formula["original_nvars"]]")
  lines.push("c Verify UNSAT proofs against this CNF, not against the XOR input.")
  lines.push("p cnf [formula["nvars"]] [formula["clauses"].size]")
  formula["clauses"].each -> (clause)
    lines.push(clause.empty? ? "0" : clause.join(" ") + " 0")
  lines.join("\n") + "\n"

-> wassat_run_convert(args)
  raise "usage: wassat convert input.xcnf --out output.cnf" unless args.size == 3 && args[1] == "--out"
  input = args[0]
  output = args[2]
  text = read_file(input)
  raise "cannot read '[input]'" if text == nil
  formula = wassat_expand_xor(text)
  rendered = wassat_expanded_xor_text(formula)
  if output == "-"
    print(rendered)
  else
    wassat_prepare_output(output, input, "expanded CNF")
    tmp = wassat_reserve_output(output, input, "expanded CNF")
    begin
      raise "cannot write expanded CNF" unless write_file(tmp, rendered)
      wassat_publish_output(tmp, output, "expanded CNF")
    rescue e
      ignored = ccall("__w_unlink", tmp)
      raise e
    << "c expanded [formula["xor_clauses"]] XOR clauses to [formula["clauses"].size] CNF clauses"
    << "c original variables: [formula["original_nvars"]]; total variables: [formula["nvars"]]"
  0
