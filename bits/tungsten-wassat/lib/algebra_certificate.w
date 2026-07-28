# Optional finite-proof bridge for exact algebra.
#
# This file intentionally is not loaded by `use wassat` or `use algebra`.
# Applications opt into it explicitly when a finite arithmetic construction
# has already been reduced to Boolean clauses.  Wassat produces a WRAT
# refutation; tungsten-wrat, which has its own parser and checking core,
# independently replays it.
#
# The certificate proves only the exported Boolean consequence.  Establishing
# that a class group, local image, Galois action, or Selmer condition was
# encoded correctly remains an arithmetic proof obligation for the algebra
# layer.  In particular, this bridge must not be used to turn an unverified
# arithmetic producer into a "certified descent".

use wassat
use ../../tungsten-wrat/lib/wrat


+ WassatFiniteBooleanCertificate
  -> new(@base_cnf, @query_cnf, claim_literals, @proof_text,
         variable_names, @labels_text)
    @claim_literals = []
    claim_literals.each -> @claim_literals.push(item)
    @variable_names = []
    variable_names.each -> @variable_names.push(item)

  -> base_cnf
    @base_cnf

  -> query_cnf
    @query_cnf

  -> proof_text
    @proof_text

  -> labels_text
    @labels_text

  -> claim_literals
    out = []
    @claim_literals.each -> out.push(item)
    out

  -> variable_names
    out = []
    @variable_names.each -> out.push(item)
    out

  -> integer?(value)
    name = value.class_name
    name == "Integer" || name == "Int" || name == "BigInt"

  -> render_cnf(variable_count, clauses)
    lines = [
      "p cnf " + variable_count.to_s + " " + clauses.size.to_s
    ]
    i = 0
    while i < clauses.size
      clause = clauses[i]
      if clause.empty?
        lines.push("0")
      else
        lines.push(clause.join(" ") + " 0")
      i += 1
    lines.join("\n") + "\n"

  # Reconstruct the exact refuted formula from the theorem statement:
  #
  #   base CNF and not(l1 or ... or ln)
  #
  # The canonical base rendering, variable table, normalized claim, and
  # appended unit clauses are all checked.  Thus an UNSAT proof for one query
  # cannot be relabeled as a certificate for a different consequence.
  -> expected_query_cnf
    base = wrat_parse_cnf(@base_cnf)
    clauses = []
    i = 0
    while i < base["clauses"].size
      clause = []
      base["clauses"][i].each -> clause.push(item)
      clauses.push(clause)
      i += 1
    return nil if render_cnf(base["nvars"], clauses) != @base_cnf
    return nil if @variable_names.size != base["nvars"]

    seen_names = {}
    i = 0
    while i < @variable_names.size
      name = @variable_names[i]
      return nil if name.class_name != "String" || name.empty?
      return nil if seen_names.has_key?(name)
      seen_names[name] = true
      i += 1

    previous = nil
    i = 0
    while i < @claim_literals.size
      literal = @claim_literals[i]
      return nil if !integer?(literal)
      return nil if literal == 0 || literal.abs > base["nvars"]
      return nil if previous != nil && literal <= previous
      clauses.push([0 - literal])
      previous = literal
      i += 1
    render_cnf(base["nvars"], clauses)

  # Reparse both artifacts through tungsten-wrat on every call.  The
  # producer's Wassat result is deliberately not part of this decision.
  -> verification
    result = nil
    begin
      result = verification_unchecked
    rescue e
      result = {
        "verified": false,
        "reason": "checker rejected certificate: " + e.to_s,
        "format": "unknown",
        "steps": 0
      }
    result

  -> verification_unchecked
    expected = expected_query_cnf
    if expected == nil || expected != @query_cnf
      return {
        "verified": false,
        "reason": "certificate query is not the deterministic negation of its claim",
        "format": "unknown",
        "steps": 0
      }
    wrat_verify(@query_cnf, @proof_text)

  -> verified?
    verification["verified"] == true

  -> certified?
    verified?

  -> format
    verification["format"]

  -> steps
    verification["steps"]

  -> reason
    verification["reason"]

  -> to_s
    body = @claim_literals.empty? ? "false" : @claim_literals.join(" or ")
    "CertifiedBooleanConsequence(" + body + ")"

  -> inspect
    to_s


+ WassatFiniteBooleanProblem
  -> new(variable_names)
    if variable_names.class_name != "Array"
      raise "finite Boolean variable names must be an Array"

    @variable_names = []
    @variable_ids = {}
    @clauses = []
    @clause_labels = []
    @auxiliary_counter = 0

    variable_names.each -> (name)
      self.add_named_variable(name)
    @primary_variable_count = @variable_names.size

  -> integer?(value)
    name = value.class_name
    name == "Integer" || name == "Int" || name == "BigInt"

  -> add_named_variable(name)
    key = name.to_s
    raise "finite Boolean variable names cannot be empty" if key.empty?
    if @variable_ids.has_key?(key)
      raise "duplicate finite Boolean variable name: " + key
    @variable_names.push(key)
    @variable_ids[key] = @variable_names.size
    @variable_names.size

  -> primary_variable_count
    @primary_variable_count

  -> variable_count
    @variable_names.size

  -> variable_names
    out = []
    @variable_names.each -> out.push(item)
    out

  -> primary_variable_names
    out = []
    i = 0
    while i < @primary_variable_count
      out.push(@variable_names[i])
      i += 1
    out

  -> variable(name)
    if self.integer?(name)
      value = name
      if value < 1 || value > @variable_names.size
        raise "finite Boolean variable is out of range: " + value.to_s
      return value

    key = name.to_s
    unless @variable_ids.has_key?(key)
      raise "unknown finite Boolean variable: " + key
    @variable_ids[key]

  -> fresh_auxiliary
    name = ""
    begin
      @auxiliary_counter += 1
      name = "__wassat_finite_aux_" + @auxiliary_counter.to_s
    end while @variable_ids.has_key?(name)
    self.add_named_variable(name)

  -> validate_literal(literal)
    unless self.integer?(literal)
      raise "finite Boolean literals must be integers"
    if literal == 0
      raise "finite Boolean literal zero is reserved by DIMACS"
    if literal.abs > @variable_names.size
      raise "finite Boolean literal is out of range: " + literal.to_s
    literal

  # Return a deterministic clause and whether it was tautological.  Repeated
  # literals are removed; a clause containing x and not-x is omitted.
  -> normalize_clause(literals)
    unless literals.class_name == "Array"
      raise "finite Boolean clauses must be Arrays"
    seen = {}
    out = []
    tautology = false
    literals.each -> (raw)
      literal = self.validate_literal(raw)
      tautology = true if seen.has_key?(0 - literal)
      unless seen.has_key?(literal)
        seen[literal] = true
        out.push(literal)
    { "literals": out.sort, "tautology": tautology }

  -> add_clause(literals, label = nil)
    normalized = self.normalize_clause(literals)
    return 0 if normalized["tautology"]
    @clauses.push(normalized["literals"])
    @clause_labels.push(label == nil ? nil : label.to_s)
    @clauses.size

  -> generated_label(label, suffix)
    label == nil ? nil : label.to_s + " " + suffix

  # Four clauses for output = left XOR right.
  -> add_xor_gate(left, right, output, label)
    self.add_clause(
      [left, right, 0 - output],
      self.generated_label(label, "(xor 00)"))
    self.add_clause(
      [left, 0 - right, output],
      self.generated_label(label, "(xor 01)"))
    self.add_clause(
      [0 - left, right, output],
      self.generated_label(label, "(xor 10)"))
    self.add_clause(
      [0 - left, 0 - right, 0 - output],
      self.generated_label(label, "(xor 11)"))

  -> parity_value(value)
    return 1 if value == true
    return 0 if value == false
    unless self.integer?(value) && (value == 0 || value == 1)
      raise "F2 right-hand sides must be 0 or 1"
    value

  # Add sum(variables) = rhs over F2. Repeated variables cancel.  The XOR
  # chain is Tseitin encoded in O(width) clauses because Wassat deliberately
  # accepts standard CNF rather than native XNF.
  -> add_parity(variables, rhs, label = nil)
    unless variables.class_name == "Array"
      raise "F2 parity variables must be an Array"

    toggled = {}
    variables.each -> (name)
      value = self.variable(name)
      toggled[value] = toggled.has_key?(value) ? 1 - toggled[value] : 1

    active = []
    value = 1
    while value <= @variable_names.size
      active.push(value) if toggled.has_key?(value) && toggled[value] == 1
      value += 1

    parity = self.parity_value(rhs)
    if active.empty?
      self.add_clause([], label) if parity == 1
      return self
    if active.size == 1
      literal = parity == 1 ? active[0] : 0 - active[0]
      self.add_clause([literal], label)
      return self
    if active.size == 2
      left = active[0]
      right = active[1]
      if parity == 0
        self.add_clause(
          [0 - left, right],
          self.generated_label(label, "(equal forward)"))
        self.add_clause(
          [left, 0 - right],
          self.generated_label(label, "(equal reverse)"))
      else
        self.add_clause(
          [left, right],
          self.generated_label(label, "(unequal positive)"))
        self.add_clause(
          [0 - left, 0 - right],
          self.generated_label(label, "(unequal negative)"))
      return self

    current = active[0]
    index = 1
    while index < active.size - 1
      auxiliary = self.fresh_auxiliary
      self.add_xor_gate(
        current, active[index], auxiliary,
        self.generated_label(label, "(chain " + index.to_s + ")"))
      current = auxiliary
      index += 1

    final_variable = active[active.size - 1]
    if parity == 0
      self.add_clause(
        [0 - current, final_variable],
        self.generated_label(label, "(result 0 forward)"))
      self.add_clause(
        [current, 0 - final_variable],
        self.generated_label(label, "(result 0 reverse)"))
    else
      self.add_clause(
        [current, final_variable],
        self.generated_label(label, "(result 1 positive)"))
      self.add_clause(
        [0 - current, 0 - final_variable],
        self.generated_label(label, "(result 1 negative)"))
    self

  # Matrix-row convenience for finite Selmer intersections.  Columns refer
  # only to the named primary variables; auxiliary Tseitin variables never
  # become accidental arithmetic coordinates.
  -> add_equation(coefficients, rhs, label = nil)
    unless coefficients.class_name == "Array"
      raise "F2 equation coefficients must be an Array"
    unless coefficients.size == @primary_variable_count
      raise "F2 equation width does not match the primary variable count"

    variables = []
    i = 0
    while i < coefficients.size
      coefficient = coefficients[i]
      unless self.integer?(coefficient)
        raise "F2 equation coefficients must be integers"
      variables.push(i + 1) if coefficient.abs % 2 == 1
      i += 1
    self.add_parity(variables, rhs, label)

  -> add_equations(matrix, right_hand_sides, labels = nil)
    unless matrix.class_name == "Array" && right_hand_sides.class_name == "Array"
      raise "F2 systems need an Array matrix and right-hand side"
    unless matrix.size == right_hand_sides.size
      raise "F2 system row count does not match its right-hand side"
    unless labels == nil || (labels.class_name == "Array" && labels.size == matrix.size)
      raise "F2 system labels must match its row count"

    i = 0
    while i < matrix.size
      label = labels == nil ? nil : labels[i]
      self.add_equation(matrix[i], right_hand_sides[i], label)
      i += 1
    self

  -> clauses
    out = []
    @clauses.each -> (clause)
      copy = []
      clause.each -> copy.push(item)
      out.push(copy)
    out

  -> append_rendered_clause(lines, clause)
    if clause.empty?
      lines.push("0")
    else
      lines.push(clause.join(" ") + " 0")

  -> normalized_extra_clauses(extra_clauses)
    unless extra_clauses.class_name == "Array"
      raise "extra finite Boolean clauses must be an Array"
    out = []
    extra_clauses.each -> (clause)
      normalized = self.normalize_clause(clause)
      out.push(normalized["literals"]) unless normalized["tautology"]
    out

  -> cnf
    self.cnf_with_clauses([])

  -> cnf_with_clauses(extra_clauses)
    extra = self.normalized_extra_clauses(extra_clauses)
    lines = [
      "p cnf " + @variable_names.size.to_s + " " +
        (@clauses.size + extra.size).to_s
    ]
    @clauses.each -> (clause)
      self.append_rendered_clause(lines, clause)
    extra.each -> (clause)
      self.append_rendered_clause(lines, clause)
    lines.join("\n") + "\n"

  -> labels_text
    lines = []
    i = 0
    while i < @clause_labels.size
      label = @clause_labels[i]
      lines.push((i + 1).to_s + "\t" + label) unless label == nil
      i += 1
    lines.empty? ? "" : lines.join("\n") + "\n"

  -> labels_for_negated_claim(claim_literals)
    text = self.labels_text
    lines = []
    lines.push(text.strip) unless text.empty?
    i = 0
    while i < claim_literals.size
      clause_id = @clauses.size + i + 1
      lines.push(
        clause_id.to_s + "\tnegated claim: " +
          (0 - claim_literals[i]).to_s)
      i += 1
    lines.empty? ? "" : lines.join("\n") + "\n"

  -> normalized_claim(literals)
    unless literals.class_name == "Array"
      raise "finite Boolean claims must be clauses"
    seen = {}
    out = []
    literals.each -> (raw)
      literal = self.validate_literal(raw)
      unless seen.has_key?(literal)
        seen[literal] = true
        out.push(literal)
    out.sort

  # Prove that the current CNF entails the supplied clause by refuting the
  # formula conjoined with the negation of every claim literal.  A false
  # claim raises with Wassat's checked countermodel instead of manufacturing
  # a certificate.
  -> certify_clause(literals)
    claim = self.normalized_claim(literals)
    assumptions = []
    claim.each -> (literal)
      assumptions.push([0 - literal])
    base = self.cnf
    query = self.cnf_with_clauses(assumptions)
    result = wassat_solve(query)

    if result["status"] == 1
      message = "finite Boolean claim is false; countermodel: " + result["model"].join(" ")
      raise message
    if result["status"] != -1 || result["complete"] != true
      raise "finite Boolean claim is unknown; no complete refutation"

    proof = wassat_proof_text(result)
    certificate = WassatFiniteBooleanCertificate.new(
      base,
      query,
      claim,
      proof,
      self.variable_names,
      self.labels_for_negated_claim(claim))
    unless certificate.verified?
      raise "Wassat produced a finite Boolean proof rejected by tungsten-wrat"
    certificate

  -> certify_literal(name, value = true)
    variable = self.variable(name)
    literal = value == true ? variable : 0 - variable
    self.certify_clause([literal])

  # The empty clause as a consequence is exactly inconsistency of the base
  # finite problem.
  -> certify_inconsistent
    self.certify_clause([])
