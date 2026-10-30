use spec
use ../lib/cnf
use ../lib/coloring

-> mask_test_lit(v, signed)
  signed && v % 3 == 0 ? 0 - v : v

-> mask_php_text(p, h, signed = false, omit_pair = false)
  clauses = []
  row = 0
  while row < p
    choice = []
    col = 0
    while col < h
      choice.push(mask_test_lit(row * h + col + 1, signed))
      col += 1
    clauses.push(choice)
    row += 1
  col = 0
  while col < h
    a = 0
    while a < p
      b = a + 1
      while b < p
        unless omit_pair && a == 0 && b == 1 && col == 0
          clauses.push([0 - mask_test_lit(a * h + col + 1, signed),
                        0 - mask_test_lit(b * h + col + 1, signed)])
        b += 1
      a += 1
    col += 1
  lines = ["p cnf [p * h] [clauses.size]"]
  clauses.each -> (c)
    lines.push(c.join(" ") + " 0")
  lines.join("\n") + "\n"

-> mask_cover_result(text, residual = false)
  f = wassat_parse_cnf(text)
  clauses = f["clauses"]
  total = 0
  ci = 0
  while ci < clauses.size
    total += clauses[ci].size
    ci += 1
  f["flat_ncl"] = clauses.size
  f["flat_lits"] = i64[total]
  f["flat_offs"] = i64[clauses.size]
  f["flat_lens"] = i64[clauses.size]
  ci = 0
  off = 0
  while ci < clauses.size
    c = clauses[ci]
    f["flat_offs"][ci] = off
    f["flat_lens"][ci] = c.size
    j = 0
    while j < c.size
      f["flat_lits"][off] = c[j]
      off += 1
      j += 1
    ci += 1
  forced = i8[f["nvars"] + 1]
  if residual
    wassat_amo_cover_residual_unsat(f["flat_lits"], f["flat_offs"],
                                  f["flat_lens"], f["nvars"], f["flat_ncl"], forced)
  else
    wassat_amo_cover_or_rphp_unsat(f["flat_lits"], f["flat_offs"],
                                 f["flat_lens"], f["nvars"], f["flat_ncl"], forced, false)

# A balanced first layer forces a relay through one complete hole clique.
# That relay supplies the one missing exclusion in a second PHP(4,3) layer.
-> mask_relay_text(width, negative = false)
  clauses = []
  first_nv = width * width
  relay = first_nv + 13
  relay_lit = negative ? 0 - relay : relay
  layer = 0
  while layer < 2
    p = layer == 0 ? width : 4
    h = layer == 0 ? width : 3
    shift = layer == 0 ? 0 : first_nv
    row = 0
    while row < p
      choice = []
      col = 0
      while col < h
        choice.push(shift + row * h + col + 1)
        col += 1
      clauses.push(choice)
      row += 1
    layer += 1
  layer = 0
  while layer < 2
    p = layer == 0 ? width : 4
    h = layer == 0 ? width : 3
    shift = layer == 0 ? 0 : first_nv
    col = 0
    while col < h
      a = 0
      while a < p
        b = a + 1
        while b < p
          x = shift + a * h + col + 1
          y = shift + b * h + col + 1
          if layer == 1 && col == 0 && a == 0 && b == 1
            clauses.push([0 - relay_lit, 0 - x, 0 - y])
          else
            clauses.push([0 - x, 0 - y])
          b += 1
        a += 1
      col += 1
    layer += 1
  a = 0
  while a < width
    x = a * width + 1
    if a % 2 == 0
      clauses.push([0 - x, relay_lit])
    else
      clauses.push([relay_lit, 0 - x])
    a += 1
  lines = ["p cnf [relay] [clauses.size]"]
  clauses.each -> (c)
    lines.push(c.join(" ") + " 0")
  lines.join("\n") + "\n"

describe "Coloring exclusion masks" ->
  it "recognizes a cover across the 62-bit word boundary" ->
    expect(mask_cover_result(mask_php_text(9, 8, true))).to eq(9)

  it "keeps a balanced signed assignment problem satisfiable" ->
    expect(mask_cover_result(mask_php_text(9, 9, true))).to eq(0)

  it "does not accept a clique with a missing exclusion" ->
    expect(mask_cover_result(mask_php_text(9, 8, true, true))).to eq(0)

  it "preserves the residual cover across the word boundary" ->
    expect(mask_cover_result(mask_php_text(9, 8, true), true)).to eq(9)

  it "keeps a residual cover with a missing edge unproved" ->
    expect(mask_cover_result(mask_php_text(9, 8, true, true), true)).to eq(0)

  it "propagates a positive relay into the residual cover" ->
    expect(mask_cover_result(mask_relay_text(3))).to eq(4)

  it "propagates a negative relay into the residual cover" ->
    expect(mask_cover_result(mask_relay_text(3, true))).to eq(4)

spec_summary
