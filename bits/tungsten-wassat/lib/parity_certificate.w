# An XOR row with charge r has weight r + 2 * (number of thresholds reached).
# Both directions of this equality are proved locally. In a selected odd
# component every original variable occurs an even number of times, so
# dividing the two sums by two gives incompatible integer bounds.
use parity_sum
use solver

# Block all assignments to the first k-1 inputs, then resolve these clauses
# up the binary tree. The input XOR fixes the last bit in every leaf. This
# also proves the empty clause directly for a locally forbidden full table.
-> wassat_parity_pb_tree(vars, off, width)
  out = StringBuffer()
  depth = width-1
  while depth > 0
    mask = 0
    while mask < (1 << depth)
      out.append("rup")
      j = 0
      while j < depth
        sign = ((mask >> j) & 1) == 0 ? "" : "~"
        out.append(" 1 [sign]x[vars[off+j]]")
        j += 1
      out.append(" >= 1 ;\n")
      mask += 1
    depth -= 1
  out.append("rup >= 1 ;\n")
  out.to_s

-> wassat_parity_pb_row(out, vars, off, k, rhs, row)
  pos = StringBuffer(); neg = StringBuffer()
  j = 0
  while j < k
    v = vars[off+j]
    pos.append(" 1 x[v]"); neg.append(" 1 ~x[v]")
    j += 1
  xs = pos.to_s; nxs = neg.to_s
  lo = StringBuffer(); hi = StringBuffer()
  lo.append(xs); hi.append(nxs)
  t = rhs+2
  while t <= k
    z = "z[row]t[t]"; u = k-t+1
    # Introduce a fresh Boolean z iff the row weight is at least t.
    out.append("red[xs] [t] ~[z] >= [t] : [z] -> 0 ;\n")
    out.append("red[nxs] [u] [z] >= [u] : [z] -> 1 ;\n")
    lo.append(" 2 ~[z]"); hi.append(" 2 [z]")
    t += 2
  tree = wassat_parity_pb_tree(vars, off, k)
  out.append("@lo[row] pbc[lo.to_s] >= [t-2] : subproof\n")
  out.append(tree); out.append("qed : -1 ;\n")
  out.append("@hi[row] pbc[hi.to_s] >= [k-rhs] : subproof\n")
  out.append(tree); out.append("qed : -1 ;\n")

-> wassat_parity_pb_sum(out, label, terms, first, count, divide)
  out.append("@[label] pol @[terms][first]")
  i = first+1
  while i < first+count
    out.append(" @[terms][i] +")
    i += 1
  out.append(" 2 d") if divide
  out.append(" ;\n")

-> wassat_flush_pb(path, buf)
  text = buf.to_s
  if path == "-"
    print(text)
  else
    raise "cannot append VeriPB proof at '[path]'" unless wassat_append_text(path, text)
  buf.clear()

-> wassat_emit_parity_pb(path, witness)
  out = StringBuffer()
  out.append("pseudo-Boolean proof version 3.0\n")
  vars = witness["vars"] ## i64[]
  if witness["local"] == true
    out.append(wassat_parity_pb_tree(vars, witness["offset"], witness["width"]))
  else
    members = witness["members"] ## i8[]
    offsets = witness["offsets"] ## i64[]
    lengths = witness["lengths"] ## i64[]
    rhs = witness["rhs"] ## i64[]
    i = 0; row = 0; groups = 0; first = 0
    while i < members.size
      if members[i] == 1
        wassat_parity_pb_row(out, vars, offsets[i], lengths[i], rhs[i], row)
        row += 1
        if row-first == 128
          wassat_parity_pb_sum(out, "bl[groups]", "lo", first, 128, false)
          wassat_parity_pb_sum(out, "bh[groups]", "hi", first, 128, false)
          groups += 1; first = row
        wassat_flush_pb(path, out) if out.size >= 65536
      i += 1
    if row > first
      wassat_parity_pb_sum(out, "bl[groups]", "lo", first, row-first, false)
      wassat_parity_pb_sum(out, "bh[groups]", "hi", first, row-first, false)
      groups += 1
    wassat_parity_pb_sum(out, "lower", "bl", 0, groups, true)
    wassat_parity_pb_sum(out, "upper", "bh", 0, groups, true)
    out.append("pol @lower @upper + ;\n")
  out.append("output NONE ;\nconclusion UNSAT : -1 ;\nend pseudo-Boolean proof ;\n")
  wassat_flush_pb(path, out)
