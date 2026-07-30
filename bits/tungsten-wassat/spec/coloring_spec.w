use spec
use wassat

# Build a width-three graph-coloring encoding. Complete mode yields K11 and
# therefore contains a K4/3-color obstruction. Partite mode yields K4-free
# K4,4,4 and is satisfiable by assigning one color per part.
-> coloring_cnf(complete, partial_bundle = false, embedded = false)
  groups = complete ? 11 : 12
  width = 3
  lines = []

  # Put the binaries first and reverse choice literals below: recognition must
  # not depend on clause order or literal order.
  a = 0
  while a < groups
    b = a + 1
    while b < groups
      edge = complete || a % 3 != b % 3
      c = 0
      while c < width
        if edge
          va = a * width + c + 1
          vb = b * width + c + 1
          lines.push("-[va] -[vb] 0")
        c += 1
      b += 1
    a += 1

  if partial_bundle
    # Same-part pair in K4,4,4: two of three colors are forbidden. This is not
    # a graph edge for the obstruction and the missing color keeps the formula
    # satisfiable.
    lines.push("-1 -4 0")
    lines.push("-2 -5 0")

  g = groups - 1
  while g >= 0
    base = g * width
    lines.push("[base + 3] [base + 2] [base + 1] 0")
    g -= 1

  nv = groups * width
  if embedded
    nv += 2
    # Irrelevant auxiliary implications demonstrate that an UNSAT subset,
    # rather than whole-formula canonicality, is what is certified.
    lines.push("-[nv - 1] [nv] 0")
    lines.push("[nv - 1] -[nv] 0")
  "p cnf [nv] [lines.size]\n" + lines.join("\n") + "\n"

describe "Wassat coloring-clique shortcut" ->
  it "certifies an explicit K4 obstruction to three-coloring" ->
    f = wassat_parse_cnf_native(coloring_cnf(true))
    expect(wassat_coloring_clique_unsat(f)).to eq(4)

  it "uses an UNSAT subset even when unrelated clauses and variables exist" ->
    f = wassat_parse_cnf_native(coloring_cnf(true, false, true))
    expect(wassat_coloring_clique_unsat(f)).to eq(4)

  it "declines a dense K4-free graph" ->
    f = wassat_parse_cnf_native(coloring_cnf(false))
    expect(wassat_coloring_clique_unsat(f)).to eq(0)

  it "does not treat a partial color-conflict bundle as an edge" ->
    f = wassat_parse_cnf_native(coloring_cnf(false, true))
    expect(wassat_coloring_clique_unsat(f)).to eq(0)

spec_summary
