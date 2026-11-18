use circuit_cone_fixtures

-> cone_php_gate(rows, a, b, ids)
  g = ids[0]
  ids[0] += 1
  rows.push([0 - g, a]); rows.push([0 - g, b]); rows.push([g, 0 - a, 0 - b])
  g

# Encode a hard UNSAT function as a complete circuit, rather than adding
# non-circuit clauses to the decoder's trusted input. The local SAT query
# asks whether PHP(11,10) can be true while a constant-false gate is false.
-> cone_php_circuit(pigeons = 11, holes = 10)
  rows = []; ids = [pigeons * holes + 1]
  zero = cone_php_gate(rows, 1, -1, ids)
  output = 0 - zero
  p = 0
  while p < pigeons
    disj = p * holes + 1
    h = 1
    while h < holes
      disj = 0 - cone_php_gate(rows, 0 - disj, 0 - (p * holes + h + 1), ids)
      h += 1
    output = cone_php_gate(rows, output, disj, ids)
    p += 1
  h = 0
  while h < holes
    p = 0
    while p < pigeons
      q = p + 1
      while q < pigeons
        clash = cone_php_gate(rows, p * holes + h + 1, q * holes + h + 1, ids)
        output = cone_php_gate(rows, output, 0 - clash, ids)
        q += 1
      p += 1
    h += 1
  a = ids[0]; b = a + 1; c = b + 1
  rows.push([-a, output]); rows.push([-a, -zero])
  rows.push([-b, -output]); rows.push([-b, zero])
  rows.push([c, a, b]); rows.push([-c])
  [cone_fixture_flat(rows, c), output, zero]
