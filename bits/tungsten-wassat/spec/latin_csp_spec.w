use spec
use wassat
use ../../tungsten-wrat/lib/wrat

# Four-valued domains.  A relation [a, b, c, k] permits exactly
#
#   value(c) = value(a) + value(b) + k  (mod 4)
#
# and renders the other 48 triples as all-negative CNF nogoods.  The SAT and
# UNSAT fixtures share a four-relation cycle, so the only difference is one
# offset rather than a malformed structural shell.
-> latin_csp_var(group, value)
  group * 4 + value + 1

-> latin_csp_relations(unsat)
  [
    [0, 1, 2, 0],
    [0, 1, 3, 1],
    [2, 4, 5, 1],
    [3, 4, 5, unsat ? 1 : 0]
  ]

-> latin_csp_permute_literal(lit, nvars)
  v = lit < 0 ? 0 - lit : lit
  mapped = ((v - 1) * 5) % nvars + 1
  lit < 0 ? 0 - mapped : mapped

# `first_kind` selects the first scope's relation:
#   0 = addition mod 4
#   1 = the non-Latin table c=a
#   2 = the Klein-four Latin table
-> latin_csp_render(ngroups, relations, permuted = false, first_kind = 0)
  nvars = ngroups * 4
  clauses = []

  group = 0
  while group < ngroups
    row = []
    value = 0
    while value < 4
      row.push(latin_csp_var(group, value))
      value += 1
    clauses.push(row)
    group += 1

  klein = [
    0, 1, 2, 3,
    1, 0, 3, 2,
    2, 3, 0, 1,
    3, 2, 1, 0
  ]
  ri = 0
  while ri < relations.size
    relation = relations[ri]
    a = 0
    while a < 4
      b = 0
      while b < 4
        c = 0
        while c < 4
          allowed = c == (a + b + relation[3]) % 4
          allowed = c == a if ri == 0 && first_kind == 1
          allowed = c == klein[a * 4 + b] if ri == 0 && first_kind == 2
          unless allowed
            clauses.push([
              0 - latin_csp_var(relation[0], a),
              0 - latin_csp_var(relation[1], b),
              0 - latin_csp_var(relation[2], c)
            ])
          c += 1
        b += 1
      a += 1
    ri += 1

  lines = []
  if permuted
    # A bijection of all Boolean ids plus reversal of both the clause stream
    # and every clause checks that neither numbering nor input order carries
    # semantic meaning for recognition.
    ci = clauses.size - 1
    while ci >= 0
      clause = clauses[ci]
      rendered = []
      j = clause.size - 1
      while j >= 0
        rendered.push(latin_csp_permute_literal(clause[j], nvars))
        j -= 1
      lines.push(rendered.join(" ") + " 0")
      ci -= 1
  else
    clauses.each -> (clause)
      lines.push(clause.join(" ") + " 0")

  "p cnf [nvars] [lines.size]\n" + lines.join("\n") + "\n"

-> latin_csp_text(unsat = false, permuted = false, first_kind = 0)
  latin_csp_render(
    6, latin_csp_relations(unsat), permuted, first_kind
  )

# Meet the production route's 64-variable/1,000-clause gate without inflating
# the contradictory core.  Seventeen additional distinct Latin scopes connect
# ten more domains to the six-domain cycle.  Their offsets preserve the known
# SAT assignment; adding constraints cannot repair the UNSAT core.
-> latin_csp_production_relations(unsat)
  relations = latin_csp_relations(unsat)
  values = [0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

  group = 4
  while group < 15
    k = (values[group + 1] + 8 - values[0] - values[group]) % 4
    relations.push([0, group, group + 1, k])
    group += 1
  group = 4
  while group < 10
    k = (values[group + 1] + 8 - values[1] - values[group]) % 4
    relations.push([1, group, group + 1, k])
    group += 1
  relations

-> latin_csp_production_text(unsat)
  latin_csp_render(16, latin_csp_production_relations(unsat))

-> latin_csp_solve_text(text, node_cap = WASSAT_LATIN_NODE_CAP)
  wassat_latin_csp_solve_limits(
    wassat_parse_cnf_native(text), node_cap, 0, 0
  )

-> latin_csp_cli_bin
  bin = env("WASSAT_TEST_BIN")
  bin == nil || bin == "" ? "bits/tungsten-wassat/bin/wassat" : bin

-> latin_csp_cli_exits(cmd, code)
  system("(" + cmd + "); test $? -eq [code]")

-> latin_csp_cli_model(text)
  model = []
  text.split("\n").each -> (line)
    if line.starts_with?("v ")
      tokens = line.split(" ")
      i = 1
      while i < tokens.size
        value = tokens[i].to_i
        model.push(value) unless value == 0
        i += 1
  model

describe "Wassat exact four-value Latin CSP shortcut" ->
  it "solves compact generated SAT and UNSAT cycles exactly" ->
    sat_text = latin_csp_text(false)
    sat = latin_csp_solve_text(sat_text)
    expect(sat["recognized"]).to eq(true)
    expect(sat["status"]).to eq(1)
    expect(sat["groups"]).to eq(6)
    expect(sat["constraints"]).to eq(4)
    expect(wassat_model_satisfies?(
      wassat_parse_cnf_native(sat_text), sat["model"]
    )).to eq(true)
    expect(wassat_solve_opts(sat_text, false)["status"]).to eq(1)

    unsat_text = latin_csp_text(true)
    unsat = latin_csp_solve_text(unsat_text)
    expect(unsat["recognized"]).to eq(true)
    expect(unsat["status"]).to eq(-1)
    expect(wassat_solve_opts(unsat_text, false)["status"]).to eq(-1)

  it "accepts a non-cyclic Latin table after order and id permutation" ->
    text = latin_csp_text(false, true, 2)
    result = latin_csp_solve_text(text)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(1)
    expect(wassat_model_satisfies?(
      wassat_parse_cnf_native(text), result["model"]
    )).to eq(true)

  it "returns UNKNOWN rather than guessing when its node cap is exhausted" ->
    text = latin_csp_text(false)
    result = latin_csp_solve_text(text, 1)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(0)
    expect(result["model"]).to eq([])
    expect(wassat_solve_opts(text, false)["status"]).to eq(1)

  it "rejects malformed or overlapping positive domain rows" ->
    mixed = latin_csp_text(false).replace(
      "1 2 3 4 0", "1 2 3 -4 0"
    )
    overlap = latin_csp_text(false).replace(
      "5 6 7 8 0", "1 6 7 8 0"
    )
    expect(latin_csp_solve_text(mixed)["recognized"]).to eq(false)
    expect(latin_csp_solve_text(overlap)["recognized"]).to eq(false)

  it "rejects malformed nogoods and repeated domains in a scope" ->
    mixed = latin_csp_text(false).replace(
      "-1 -5 -10 0", "-1 -5 10 0"
    )
    repeated_domain = latin_csp_text(false).replace(
      "-1 -5 -10 0", "-1 -2 -10 0"
    )
    expect(latin_csp_solve_text(mixed)["recognized"]).to eq(false)
    expect(
      latin_csp_solve_text(repeated_domain)["recognized"]
    ).to eq(false)

  it "rejects missing, extra, and duplicate forbidden tuples" ->
    base = latin_csp_text(false)
    missing = base.replace(
      "p cnf 24 198", "p cnf 24 197"
    ).replace("-1 -5 -10 0\n", "")
    extra = base.replace(
      "p cnf 24 198", "p cnf 24 199"
    ) + "-1 -5 -9 0\n"
    duplicate = base.replace(
      "p cnf 24 198", "p cnf 24 199"
    ) + "-10 -5 -1 0\n"
    expect(latin_csp_solve_text(missing)["recognized"]).to eq(false)
    expect(latin_csp_solve_text(extra)["recognized"]).to eq(false)
    expect(latin_csp_solve_text(duplicate)["recognized"]).to eq(false)

  it "checks every pair projection rather than mere output functionality" ->
    # c=a still leaves exactly sixteen allowed triples and gives one output
    # for every (a,b), but (a,c) does not determine b.
    result = latin_csp_solve_text(latin_csp_text(false, false, 1))
    expect(result["recognized"]).to eq(false)
    expect(result["status"]).to eq(0)

  it "recognizes generated fixtures through the production size gate" ->
    sat_text = latin_csp_production_text(false)
    unsat_text = latin_csp_production_text(true)
    sat_formula = wassat_parse_cnf_native(sat_text)
    unsat_formula = wassat_parse_cnf_native(unsat_text)
    expect(sat_formula["nvars"]).to eq(64)
    expect(sat_formula["flat_ncl"]).to eq(1024)

    sat = wassat_latin_csp_solve(sat_formula)
    expect(sat["recognized"]).to eq(true)
    expect(sat["status"]).to eq(1)
    expect(sat["groups"]).to eq(16)
    expect(sat["constraints"]).to eq(21)
    expect(wassat_model_satisfies?(sat_formula, sat["model"])).to eq(true)

    unsat = wassat_latin_csp_solve(unsat_formula)
    expect(unsat["recognized"]).to eq(true)
    expect(unsat["status"]).to eq(-1)

  context "compiled CLI routing" ->
    it "uses the verified Latin model in fast mode" ->
      text = latin_csp_production_text(false)
      input = "/tmp/wassat-latin-csp-fast-sat.cnf"
      output = "/tmp/wassat-latin-csp-fast-sat.out"
      expect(write_file(input, text)).to eq(true)
      cmd = latin_csp_cli_bin + " " + input + " --fast > " + output + " 2>&1"
      expect(latin_csp_cli_exits(cmd, 10)).to eq(true)
      observed = read_file(output)
      expect(observed.include?("s SATISFIABLE")).to eq(true)
      expect(observed.include?(
        "exact four-value Latin ternary CSP"
      )).to eq(true)
      model = latin_csp_cli_model(observed)
      expect(model.size).to eq(64)
      expect(wassat_model_satisfies?(
        wassat_parse_cnf_native(text), model
      )).to eq(true)

    it "uses the exhaustive Latin refutation in fast mode" ->
      text = latin_csp_production_text(true)
      input = "/tmp/wassat-latin-csp-fast-unsat.cnf"
      output = "/tmp/wassat-latin-csp-fast-unsat.out"
      expect(write_file(input, text)).to eq(true)
      cmd = latin_csp_cli_bin + " " + input + " --fast > " + output + " 2>&1"
      expect(latin_csp_cli_exits(cmd, 20)).to eq(true)
      observed = read_file(output)
      expect(observed.include?("s UNSATISFIABLE")).to eq(true)
      expect(observed.include?(
        "c mode: fast (exact four-value Latin ternary CSP)"
      )).to eq(true)

    it "uses the verified Latin model in proof mode and leaves no proof" ->
      text = latin_csp_production_text(false)
      input = "/tmp/wassat-latin-csp-proof-sat.cnf"
      output = "/tmp/wassat-latin-csp-proof-sat.out"
      proof = "/tmp/wassat-latin-csp-proof-sat.wrat"
      expect(write_file(input, text)).to eq(true)
      expect(write_file(proof, "stale\n")).to eq(true)
      cmd = latin_csp_cli_bin + " " + input + " --proof " + proof + " > " + output + " 2>&1"
      expect(latin_csp_cli_exits(cmd, 10)).to eq(true)
      observed = read_file(output)
      expect(observed.include?(
        "c mode: proof (exact four-value Latin ternary CSP)"
      )).to eq(true)
      expect(file?(proof)).to eq(false)
      model = latin_csp_cli_model(observed)
      expect(wassat_model_satisfies?(
        wassat_parse_cnf_native(text), model
      )).to eq(true)

    it "falls through to an independently valid proof for UNSAT" ->
      text = latin_csp_production_text(true)
      input = "/tmp/wassat-latin-csp-proof-unsat.cnf"
      output = "/tmp/wassat-latin-csp-proof-unsat.out"
      proof = "/tmp/wassat-latin-csp-proof-unsat.wrat"
      expect(write_file(input, text)).to eq(true)
      z = ccall("__w_unlink", proof)
      cmd = latin_csp_cli_bin + " " + input + " --proof " + proof + " > " + output + " 2>&1"
      expect(latin_csp_cli_exits(cmd, 20)).to eq(true)
      observed = read_file(output)
      expect(observed.include?("s UNSATISFIABLE")).to eq(true)
      expect(observed.include?(
        "exact four-value Latin ternary CSP"
      )).to eq(false)
      expect(file?(proof)).to eq(true)
      expect(wrat_verify(text, read_file(proof))["verified"]).to eq(true)

spec_summary
