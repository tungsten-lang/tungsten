use spec
use solver
use hantzsche_wendt

# Build the public group-ring encoding from its algebraic schema.  This is
# intentionally not a copy of the competition instance: the product buckets,
# Tseitin variables, and all parity truth tables are reconstructed here.
-> hantzsche_wendt_spec_clause(lines, literals)
  lines.push(literals.join(" ") + " 0")

-> hantzsche_wendt_spec_xor(lines, variables, rhs)
  width = variables.size
  assignment = 0
  while assignment < (1 << width)
    parity = 0
    bit = 0
    while bit < width
      parity = parity ^ ((assignment >> bit) & 1)
      bit += 1
    if parity != rhs
      clause = []
      bit = 0
      while bit < width
        variable = variables[bit]
        clause.push(
          (assignment & (1 << bit)) == 0 ? variable : 0 - variable
        )
        bit += 1
      hantzsche_wendt_spec_clause(lines, clause)
    assignment += 1

# A boxed, test-local shortlex enumerator keeps the generated fixture
# independent from the production admission helper and avoids mixing boxed
# and native-array specializations of that helper in one spec binary.
-> hantzsche_wendt_spec_shortlex(n, gx, gy, gz, gq, index)
  generators = [
    [0, 0, 0, 1],
    [-1, 0, 0, 1],
    [0, 0, 0, 2],
    [0, -1, 0, 2]
  ]
  gx[0] = 0
  gy[0] = 0
  gz[0] = 0
  gq[0] = 0
  index[wassat_hw_key([0, 0, 0, 0])] = 1
  count = 1
  first = 0
  stop = 1
  while count < n
    next_first = count
    position = first
    while position < stop && count < n
      current = [gx[position], gy[position], gz[position], gq[position]]
      generator = 0
      while generator < generators.size && count < n
        product = wassat_hw_mul(current, generators[generator])
        key = wassat_hw_key(product)
        unless index.has_key?(key)
          gx[count] = product[0]
          gy[count] = product[1]
          gz[count] = product[2]
          gq[count] = product[3]
          index[key] = count + 1
          count += 1
        generator += 1
      position += 1
    first = next_first
    stop = count
    return 0 if first == stop && count < n
  count

-> hantzsche_wendt_fixture_text
  lines = []

  # Both factors are nonzero.
  hantzsche_wendt_spec_clause(lines, [WASSAT_HW_LEFT])
  support = []
  variable = WASSAT_HW_LEFT + 1
  while variable < WASSAT_HW_RIGHT
    support.push(variable)
    variable += 1
  hantzsche_wendt_spec_clause(lines, support)
  hantzsche_wendt_spec_clause(lines, [WASSAT_HW_RIGHT])
  support = []
  variable = WASSAT_HW_RIGHT + 1
  while variable < WASSAT_HW_PRODUCT
    support.push(variable)
    variable += 1
  hantzsche_wendt_spec_clause(lines, support)

  # Every c_ij is exactly a_i AND b_j.
  i = 0
  while i < WASSAT_HW_N
    a = WASSAT_HW_LEFT + i
    j = 0
    while j < WASSAT_HW_N
      b = WASSAT_HW_RIGHT + j
      c = WASSAT_HW_PRODUCT + i * WASSAT_HW_N + j
      hantzsche_wendt_spec_clause(lines, [0 - c, a])
      hantzsche_wendt_spec_clause(lines, [0 - c, b])
      hantzsche_wendt_spec_clause(lines, [0 - a, 0 - b, c])
      j += 1
    i += 1

  # Bucket c_ij by the shortlex group product represented by (i,j).
  # Box these arrays: fixture generation keeps tens of thousands of clause
  # strings live and deliberately exercises the moving collector.
  gx = []
  gy = []
  gz = []
  gq = []
  i = 0
  while i < WASSAT_HW_N
    gx.push(0)
    gy.push(0)
    gz.push(0)
    gq.push(0)
    i += 1
  index = {}
  unless hantzsche_wendt_spec_shortlex(
    WASSAT_HW_N, gx, gy, gz, gq, index
  ) == WASSAT_HW_N
    raise "failed to enumerate Hantzsche-Wendt shortlex prefix"

  bucket_keys = []
  buckets = {}
  i = 0
  while i < WASSAT_HW_N
    left = [gx[i], gy[i], gz[i], gq[i]]
    j = 0
    while j < WASSAT_HW_N
      right = [gx[j], gy[j], gz[j], gq[j]]
      key = wassat_hw_key(wassat_hw_mul(left, right))
      unless buckets.has_key?(key)
        buckets[key] = []
        bucket_keys.push(key)
      buckets[key].push(WASSAT_HW_PRODUCT + i * WASSAT_HW_N + j)
      j += 1
    i += 1

  # Chain each bucket with complete XOR truth tables.  Put the group-ring
  # identity target in the first link; all later links have even parity.
  identity_key = wassat_hw_key([0, 0, 0, 0])
  next_aux = WASSAT_HW_AUX
  bucket_keys.each -> (key)
    work = buckets[key]
    original_size = work.size
    expected_links = 0
    remaining_size = original_size
    while remaining_size > 4
      expected_links += 1
      remaining_size -= 2
    rhs = key == identity_key ? 1 : 0
    first = true
    first_aux = next_aux
    while work.size > 4
      relation = [next_aux, work[0], work[1], work[2]]
      hantzsche_wendt_spec_xor(lines, relation, first ? rhs : 0)
      remainder = [next_aux]
      k = 3
      while k < work.size
        remainder.push(work[k])
        k += 1
      work = remainder
      next_aux += 1
      first = false
    hantzsche_wendt_spec_xor(lines, work, first ? rhs : 0)
    unless next_aux - first_aux == expected_links
      raise "parity chain mismatch size=[original_size] links=[next_aux - first_aux] expected=[expected_links]"

  unless next_aux == WASSAT_HW_NVARS + 1
    raise "unexpected Hantzsche-Wendt Tseitin variable count [next_aux]"
  unless lines.size == WASSAT_HW_NCLAUSES
    raise "unexpected Hantzsche-Wendt clause count [lines.size]"
  "p cnf [WASSAT_HW_NVARS] [WASSAT_HW_NCLAUSES]\n" + lines.join("\n") + "\n"

HANTZSCHE_WENDT_FIXTURE_TEXT = hantzsche_wendt_fixture_text

-> hantzsche_wendt_fixture
  wassat_parse_cnf_native(HANTZSCHE_WENDT_FIXTURE_TEXT)

describe "Wassat Hantzsche-Wendt group-ring specialist" ->
  it "derives and fully verifies a model of the reconstructed unit CNF" ->
    formula = hantzsche_wendt_fixture
    result = wassat_hantzsche_wendt_solve(formula)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(1)
    expect(result["support_left"]).to eq(WASSAT_HW_SUPPORT)
    expect(result["support_right"]).to eq(WASSAT_HW_SUPPORT)
    expect(result["xor_rows"]).to eq(3957)
    expect(result["model"].size).to eq(WASSAT_HW_NVARS)
    expect(wassat_model_satisfies?(formula, result["model"])).to eq(true)

  it "returns bounded UNKNOWN instead of making an incomplete claim" ->
    result = wassat_hantzsche_wendt_solve(hantzsche_wendt_fixture, 0)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(0)
    expect(result["bounded"]).to eq(true)
    expect(result["model"]).to eq([])

  it "rejects a changed support prefix" ->
    formula = hantzsche_wendt_fixture
    formula["flat_lits"][formula["flat_offs"][0]] = -1
    result = wassat_hantzsche_wendt_solve(formula)
    expect(result["recognized"]).to eq(false)
    expect(result["status"]).to eq(0)

  it "rejects a changed pair-product definition" ->
    formula = hantzsche_wendt_fixture
    off = formula["flat_offs"][WASSAT_HW_AND_CLAUSE]
    formula["flat_lits"][off] = WASSAT_HW_PRODUCT
    result = wassat_hantzsche_wendt_solve(formula)
    expect(result["recognized"]).to eq(false)
    expect(result["status"]).to eq(0)

  it "rejects an incomplete parity truth table" ->
    formula = hantzsche_wendt_fixture
    first = WASSAT_HW_XOR_CLAUSE
    width = formula["flat_lens"][first]
    j = 0
    while j < width
      source = formula["flat_offs"][first] + j
      destination = formula["flat_offs"][first + 1] + j
      formula["flat_lits"][destination] = formula["flat_lits"][source]
      j += 1
    result = wassat_hantzsche_wendt_solve(formula)
    expect(result["recognized"]).to eq(false)
    expect(result["status"]).to eq(0)

  it "falls through when a complete parity relation rejects the witness" ->
    formula = hantzsche_wendt_fixture
    first = WASSAT_HW_XOR_CLAUSE
    rows = 1 << (formula["flat_lens"][first] - 1)
    row = 0
    while row < rows
      off = formula["flat_offs"][first + row]
      formula["flat_lits"][off] = 0 - formula["flat_lits"][off]
      row += 1
    result = wassat_hantzsche_wendt_solve(formula)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(0)
    expect(result["model"]).to eq([])

  it "falls through on an unrelated formula" ->
    formula = wassat_parse_cnf_native("p cnf 1 1\n1 0\n")
    result = wassat_hantzsche_wendt_solve(formula)
    expect(result["recognized"]).to eq(false)
    expect(result["status"]).to eq(0)

  it "exhaustively checks the bounded group arithmetic used by the lane" ->
    gx = []
    gy = []
    gz = []
    gq = []
    i = 0
    while i < WASSAT_HW_N
      gx.push(0)
      gy.push(0)
      gz.push(0)
      gq.push(0)
      i += 1
    index = {}
    expect(
      hantzsche_wendt_spec_shortlex(WASSAT_HW_N, gx, gy, gz, gq, index)
    ).to eq(WASSAT_HW_N)
    identity = [0, 0, 0, 0]
    i = 0
    while i < WASSAT_HW_N
      a = [gx[i], gy[i], gz[i], gq[i]]
      inverse = wassat_hw_inverse(a)
      expect(wassat_hw_equal?(wassat_hw_mul(a, inverse), identity)).to eq(true)
      expect(wassat_hw_equal?(wassat_hw_mul(inverse, a), identity)).to eq(true)
      expect(index[wassat_hw_key(a)]).to eq(i + 1)
      j = 0
      while j < WASSAT_HW_N
        b = [gx[j], gy[j], gz[j], gq[j]]
        product = wassat_hw_mul(a, b)
        reverse = wassat_hw_mul(
          wassat_hw_inverse(b), wassat_hw_inverse(a)
        )
        expect(wassat_hw_equal?(
          wassat_hw_inverse(product), reverse
        )).to eq(true)
        j += 1
      i += 1

    # All triples in a nontrivial shortlex prefix exercise every quotient
    # component and every cocycle branch.
    i = 0
    while i < 17
      a = [gx[i], gy[i], gz[i], gq[i]]
      j = 0
      while j < 17
        b = [gx[j], gy[j], gz[j], gq[j]]
        k = 0
        while k < 17
          c = [gx[k], gy[k], gz[k], gq[k]]
          left = wassat_hw_mul(wassat_hw_mul(a, b), c)
          right = wassat_hw_mul(a, wassat_hw_mul(b, c))
          expect(wassat_hw_equal?(left, right)).to eq(true)
          k += 1
        j += 1
      i += 1

spec_summary
