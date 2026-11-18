# A k+1 clique sharing k colors has a polynomial cutting-planes refutation.
# Rows are original choice clauses. Each same-color exclusion is a binary
# input clause. Additional constraints on the formula need no proof steps.
use coloring

-> wassat_clique_capacity_proof(formula, witness = nil)
  if witness == nil
    witness = {"rows": [], "choices": []}
    groups = wassat_coloring_clique_unsat(formula, witness)
  else
    groups = witness["rows"].size
  return nil if groups < 2 || groups > WASSAT_COLORING_MAX_WIDTH+1
  rows = witness["rows"]; choices = witness["choices"]
  colors = groups - 1
  nv = formula["nvars"]; nc = formula["flat_ncl"]
  lits = formula["flat_lits"] ## i64[]
  offs = formula["flat_offs"] ## i64[]
  lens = formula["flat_lens"] ## i64[]
  return nil unless choices.size == groups*colors
  # The position identifies both the choice row and its color. Adding one
  # distinguishes the first literal from a variable outside the clique.
  positions = i32[nv+1]
  i = 0
  while i < choices.size
    lit = choices[i]
    return nil if lit == 0 || lit.abs > nv || positions[lit.abs] != 0
    if lit > 0
      positions[lit] = i+1
    else
      positions[0-lit] = 0-(i+1)
    i += 1
  # Check the selected literals against each complete original choice clause.
  seen = i32[groups*colors]
  g = 0
  while g < groups
    ci = rows[g]-1
    return nil if ci < 0 || ci >= nc || lens[ci] != colors
    j = 0
    while j < colors
      lit = lits[offs[ci]+j]
      pos = (lit > 0 ? positions[lit] : 0-positions[0-lit])-1
      return nil if pos < g*colors || pos >= (g+1)*colors || seen[pos] != 0
      seen[pos] = 1; j += 1
    g += 1
  pairs = i32[groups*groups*colors]
  ci = 0
  while ci < nc
    if lens[ci] == 2
      at = offs[ci]; x = lits[at]; y = lits[at+1]
      a = (x < 0 ? positions[0-x] : 0-positions[x])-1
      b = (y < 0 ? positions[0-y] : 0-positions[y])-1
      if a >= 0 && b >= 0 && a != b && a % colors == b % colors
        lo = a < b ? a : b; hi = a < b ? b : a
        pairs[((lo / colors)*groups + hi / colors)*colors + lo % colors] = ci+1
    ci += 1

  proof = StringBuffer()
  proof.append("pseudo-Boolean proof version 3.0\n")
  last = nc; capacities = i64[colors]; c = 0
  while c < colors
    prev = pairs[colors+c]
    return nil if prev == 0
    r = 2
    while r < groups
      # If S <= 1 for the preceding r rows, their pair exclusions give
      # S+r*x <= r. Add (r-1)*S <= r-1 and divide by r, rounding to 1.
      proof.append("pol [prev] [r-1] *")
      i = 0
      while i < r
        id = pairs[(i*groups+r)*colors+c]
        return nil if id == 0
        proof.append(" [id] +")
        i += 1
      proof.append(" [r] d ;\n")
      last += 1; prev = last; r += 1
    capacities[c] = prev
    c += 1

  # All variables cancel, leaving k+1 <= k.
  proof.append("pol [rows[0]]")
  i = 1
  while i < groups
    proof.append(" [rows[i]] +")
    i += 1
  c = 0
  while c < colors
    proof.append(" [capacities[c]] +")
    c += 1
  proof.append(" ;\noutput NONE ;\nconclusion UNSAT : [last+1] ;\nend pseudo-Boolean proof ;\n")
  proof.to_s
