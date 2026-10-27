use spec
use wassat

# Synthetic schooltt shapes: 200 disjoint 25-wide lesson blocks over
# consecutive variables, padded with a repeated binary clause to the
# family's (nvars, nclauses) gate. Compiled lane: the padded fixture is
# 150k clauses by construction.

-> schooltt_fixture(all_columns)
  lines = []
  b = 0
  while b < 200
    vars = []
    j = 0
    while j < 25
      vars.push(b * 25 + j + 1)
      j += 1
    lines.push(vars.join(" ") + " 0")
    b += 1
  i = 0
  while i < 26
    k = i + 1
    while k < 26
      if all_columns
        c = 0
        while c < 25
          lines.push("[0 - (i * 25 + c + 1)] [0 - (k * 25 + c + 1)] 0")
          c += 1
      else
        lines.push("[0 - (i * 25 + 1)] [0 - (k * 25 + 1)] 0")
      k += 1
    i += 1
  while lines.size < 150000
    lines.push("-1 -2 0")
  "p cnf 10000 [lines.size]\n" + lines.join("\n") + "\n"

-> schooltt_result
  {
    "recognized": false, "status": 0, "model": [],
    "bits": 0, "samples": 0, "tolerated": 0,
    "disagreements": 0, "trials": 0, "xor_rows": 0,
    "conflicts": 0, "decisions": 0, "props": 0
  }

describe "Wassat schooltt pigeonhole refuter" ->
  it "does not refute column-0-only exclusivity (the formula is satisfiable)" ->
    formula = wassat_parse_cnf_native(schooltt_fixture(false))
    res = wassat_schooltt_refute(formula, schooltt_result)
    expect(res["status"]).to eq(0)

  it "refutes a 26-block clique excluded at every column, with a witness" ->
    formula = wassat_parse_cnf_native(schooltt_fixture(true))
    res = wassat_schooltt_refute(formula, schooltt_result)
    expect(res["status"]).to eq(-1)
    expect(res["samples"] >= 26).to eq(true)
    expect(res["witness_vars"].size >= 26 * 25).to eq(true)

spec_summary
