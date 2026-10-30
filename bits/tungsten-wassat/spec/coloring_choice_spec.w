use spec
use ../lib/cnf
use ../lib/coloring

-> covered_short_formula(text)
  f = wassat_parse_cnf(text)
  cs = f["clauses"]
  total = 0
  cs.each -> (c) total += c.size
  f["flat_lits"] = i64[total]
  f["flat_offs"] = i64[cs.size]
  f["flat_lens"] = i64[cs.size]
  f["flat_ncl"] = cs.size
  off = 0
  ci = 0
  while ci < cs.size
    f["flat_offs"][ci] = off
    f["flat_lens"][ci] = cs[ci].size
    cs[ci].each -> (lit)
      f["flat_lits"][off] = lit
      off += 1
    ci += 1
  f

# Force a 4-to-3 PHP through a literal that shortens every choice from4to3.
# Binary and unit clauses must not change ownership during choice discovery.
describe "Coloring choices under restriction" ->
  it "keeps the same obstruction when forced literals shorten long clauses" ->
    cs = []
    4.times -> (p)
      cs.push([p * 3 + 1, p * 3 + 2, p * 3 + 3, 13])
    3.times -> (hole)
      4.times -> (a)
        b = a + 1
        while b < 4
          cs.push([0 - (a * 3 + hole + 1), 0 - (b * 3 + hole + 1)])
          b += 1
    cs.push([-13])
    lines = ["p cnf 13 [cs.size]"]
    cs.each -> (c) lines.push(c.join(" ") + " 0")
    f = covered_short_formula(lines.join("\n") + "\n")
    forced = i8[14]
    forced[13] = -1
    r = wassat_amo_cover_or_rphp_unsat(f["flat_lits"], f["flat_offs"], f["flat_lens"], 13, cs.size, forced, true)
    expect(r).to eq(4)

  it "leaves a satisfiable restricted binary-only formula undecided" ->
    f = covered_short_formula("p cnf 3 3\n1 2 0\n-1 3 0\n-2 -3 0\n")
    forced = i8[4]
    forced[1] = 1
    expect(wassat_amo_cover_or_rphp_unsat(f["flat_lits"], f["flat_offs"], f["flat_lens"], 3, 3, forced, true)).to eq(0)
    expect(wassat_amo_cover_or_rphp_unsat(f["flat_lits"], f["flat_offs"], f["flat_lens"], 3, 3, forced, false)).to eq(0)

spec_summary
