# spec: compiled -- the weak-order evaluator uses native worker threads
use spec
use ../lib/wassat
use circuit_cone_fixtures

# Two separately encoded copies of three three-bit words. Their equality is
# independent of any sorting theorem and supplies a small complete miter.
-> word_sort_identity_fixture(mode = "valid")
  rows = []
  input = 1
  while input <= 9
    rows.push([0 - (input + 9), input]); rows.push([input + 9, 0 - input])
    rows.push([0 - (input + 18), input]); rows.push([input + 18, 0 - input])
    input += 1
  bit = 0
  while bit < 9
    a = bit + 10; b = bit + 19; z = bit + 28
    group = [[a, b, 0 - z], [0 - a, 0 - b, 0 - z], [a, 0 - b, z], [0 - a, b, z]]
    if bit == 0 && mode == "positive-xor"
      group = [[a, b, z], [0 - a, 0 - b, z], [a, 0 - b, z], [0 - a, b, z]]
    elsif bit == 0 && mode == "duplicate-xor"
      group[0] = group[1].dup
    group.each -> (row) rows.push(row)
    bit += 1
  word = 0
  while word < 3
    first = 28 + 3 * word; z = 37 + word
    rows.push([first, first + 1, first + 2, word == 0 && mode == "positive-word-or" ? z : 0 - z])
    rows.push([0 - first, z]); rows.push([0 - (first + 1), z]); rows.push([0 - (first + 2), z])
    word += 1
  rows.push([37, 38, 39, mode == "positive-final-or" ? 40 : -40])
  rows.push([-37, 40]); rows.push([-38, 40]); rows.push([-39, 40]); rows.push([40])
  cone_fixture_flat(rows, 40)

-> word_sort_run_fixture(f)
  wassat_word_sort_miter_run(f["flat_lits"], f["flat_offs"], f["flat_lens"], f["nvars"], f["flat_ncl"])

describe "Word-sort complete miter recognition" ->
  it "recognizes separately encoded equal word copies" ->
    expect(word_sort_run_fixture(word_sort_identity_fixture)).to eq(1)

  it "rejects count-preserving SAT mutations with independently checked models" ->
    ["positive-xor", "duplicate-xor", "positive-word-or", "positive-final-or"].each -> (mode)
      f = word_sort_identity_fixture(mode)
      model = []
      v = 1
      while v <= 40
        positive = v == 40
        positive = true if mode != "positive-final-or" && v == 37
        positive = true if (mode == "positive-xor" || mode == "duplicate-xor") && v == 28
        model.push(positive ? v : 0 - v)
        v += 1
      expect(wassat_model_satisfies?(f, model)).to eq(true)
      expect(word_sort_run_fixture(f)).to eq(0)

spec_summary
