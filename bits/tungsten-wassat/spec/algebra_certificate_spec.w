# Certified finite Boolean obligations for algebra.

use spec
use ../lib/algebra_certificate

describe "Wassat finite algebra certificate bridge" ->

  it "matches F2 parity on every four-variable assignment" ->
    rhs = 0
    while rhs <= 1
      mask = 0
      while mask < 16
        problem = WassatFiniteBooleanProblem.new([:a, :b, :c, :d])
        problem.add_parity([:a, :b, :c, :d], rhs)
        units = []
        bit = 0
        parity = 0
        while bit < 4
          value = (mask >> bit) & 1
          parity = parity ^ value
          variable = bit + 1
          units.push([value == 1 ? variable : 0 - variable])
          bit += 1
        result = wassat_solve_opts(problem.cnf_with_clauses(units), false)
        expect(result["status"]).to eq(parity == rhs ? 1 : -1)
        mask += 1
      rhs += 1

  it "certifies a consequence of an F2 parity equation with independent WRAT replay" ->
    problem = WassatFiniteBooleanProblem.new([:a, :b, :c])
    problem.add_parity([:a, :b, :c], 1, "odd parity")

    a = problem.variable(:a)
    b = problem.variable(:b)
    c = problem.variable(:c)
    certificate = problem.certify_clause([a, b, c])

    expect(certificate.certified?).to eq(true)
    expect(certificate.format).to eq("wrat")
    expect(certificate.steps > 0).to eq(true)
    expect(certificate.proof_text.starts_with?("wrat 1")).to eq(true)
    expect(certificate.labels_text.index("odd parity") != nil).to eq(true)
    expect(certificate.labels_text.index("negated claim") != nil).to eq(true)

  it "keeps Tseitin variables out of the arithmetic coordinate width" ->
    problem = WassatFiniteBooleanProblem.new([:u, :v, :w, :x])
    problem.add_equation([1, 1, 1, 1], 0, "global norm parity")
    expect(problem.primary_variable_count).to eq(4)
    expect(problem.variable_count > 4).to eq(true)
    expect(problem.primary_variable_names).to eq(["u", "v", "w", "x"])
    expect(
      -> () problem.add_equation([1, 1, 1, 1, 0], 0)
    ).to raise_error

  it "certifies implications in an F2 linear intersection" ->
    problem = WassatFiniteBooleanProblem.new([:x, :y, :z])
    problem.add_equations(
      [[1, 1, 0], [0, 1, 1]],
      [0, 0],
      ["x equals y", "y equals z"])

    x = problem.variable(:x)
    z = problem.variable(:z)
    expect(problem.certify_clause([0 - x, z]).verified?).to eq(true)
    expect(problem.certify_clause([x, 0 - z]).verified?).to eq(true)

  it "certifies an inconsistent finite system" ->
    problem = WassatFiniteBooleanProblem.new([:x])
    problem.add_equation([1], 0, "x is zero")
    problem.add_equation([1], 1, "x is one")
    certificate = problem.certify_inconsistent
    expect(certificate.claim_literals).to eq([])
    expect(certificate.verified?).to eq(true)

  it "binds an explicit empty base clause without changing its rendering" ->
    problem = WassatFiniteBooleanProblem.new([:x])
    problem.add_clause([], "empty")
    certificate = problem.certify_inconsistent
    expect(certificate.base_cnf.index("\n0\n") != nil).to eq(true)
    expect(certificate.verified?).to eq(true)

  it "refuses to certify a false Boolean consequence" ->
    problem = WassatFiniteBooleanProblem.new([:a, :b])
    problem.add_parity([:a, :b], 1)
    expect(-> () problem.certify_literal(:a)).to raise_error

  it "rejects malformed finite encodings and tampered proofs" ->
    expect(
      -> () WassatFiniteBooleanProblem.new([:x, :x])
    ).to raise_error

    problem = WassatFiniteBooleanProblem.new([:x])
    expect(-> () problem.add_clause([0])).to raise_error
    expect(-> () problem.add_clause([2])).to raise_error
    problem.add_clause([problem.variable(:x)], "x")
    certificate = problem.certify_literal(:x)
    tampered = WassatFiniteBooleanCertificate.new(
      certificate.base_cnf,
      certificate.query_cnf,
      certificate.claim_literals,
      "wrat 1\n",
      certificate.variable_names,
      certificate.labels_text)
    expect(tampered.verified?).to eq(false)

    relabeled = WassatFiniteBooleanCertificate.new(
      certificate.base_cnf,
      certificate.query_cnf,
      [0 - problem.variable(:x)],
      certificate.proof_text,
      certificate.variable_names,
      certificate.labels_text)
    expect(relabeled.verified?).to eq(false)

spec_summary
