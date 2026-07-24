# Explain specs (E6): the mechanical doneness gate — every cited input id
# resolves through the labels sidecar; unlabeled citations surface loudly.

use spec
use wassat

EXPLAIN_PHP32 = "p cnf 6 9\n1 2 0\n3 4 0\n5 6 0\n-1 -3 0\n-1 -5 0\n-3 -5 0\n-2 -4 0\n-2 -6 0\n-4 -6 0\n"

-> explain_fixture_labels
  text = ""
  names = ["pigeon 1 goes somewhere", "pigeon 2 goes somewhere", "pigeon 3 goes somewhere",
           "pigeons 1,2 not both in hole 1", "pigeons 1,3 not both in hole 1", "pigeons 2,3 not both in hole 1",
           "pigeons 1,2 not both in hole 2", "pigeons 1,3 not both in hole 2", "pigeons 2,3 not both in hole 2"]
  i = 0
  while i < names.size
    text = text + "[i + 1]\t[names[i]]\n"
    i += 1
  text

describe "Wassat explain" ->

  context "narrating a trimmed core" ->
    it "resolves every cited input id through the labels" ->
      r = wassat_solve_preprocessed(EXPLAIN_PHP32, WASSAT_PROOF_WRAT, 0, 0)
      expect(r["unsat"]).to eq(true)
      full = "wrat 1\n" + r["proof"].join("\n") + "\n"
      t = wassat_trim_hinted(full)
      labels = wassat_labels_parse(explain_fixture_labels)
      report = wassat_explain(t["text"], labels)
      expect(report["missing"].size).to eq(0)
      expect(report["used"].size >= 1).to eq(true)
      expect(report["input_citations"] >= report["used"].size).to eq(true)

    it "reports unlabeled citations instead of inventing prose" ->
      r = wassat_solve_preprocessed(EXPLAIN_PHP32, WASSAT_PROOF_WRAT, 0, 0)
      full = "wrat 1\n" + r["proof"].join("\n") + "\n"
      t = wassat_trim_hinted(full)
      empty_labels = wassat_labels_parse("")
      report = wassat_explain(t["text"], empty_labels)
      expect(report["missing"].size >= 1).to eq(true)

    it "groups repeated labels with counts" ->
      labels = wassat_labels_parse("1\tsame group\n2\tsame group\n")
      fake = "5 -1 0 1 2 0\n6 0 5 1 0\n"
      report = wassat_explain(fake, labels)
      expect(report["missing"].size).to eq(0)
      text = wassat_explain_text(report)
      expect(text.index("same group") != nil).to eq(true)
      expect(text.index("x2") != nil).to eq(true)

  context "labels sidecar parsing" ->
    it "parses ids and keeps tabs inside labels intact" ->
      labels = wassat_labels_parse("1\ttime 1 must be covered\n2\tat most k\n")
      expect(labels[1]).to eq("time 1 must be covered")
      expect(labels[2]).to eq("at most k")

    it "rejects malformed, zero, and duplicate clause ids" ->
      expect(-> () wassat_labels_parse("missing separator\n")).to raise_error
      expect(-> () wassat_labels_parse("0\tzero\n")).to raise_error
      expect(-> () wassat_labels_parse("1\tfirst\n1\tsecond\n")).to raise_error
      expect(-> () wassat_labels_parse("2\t\n")).to raise_error
      expect(-> () wassat_explain("wrat nope\n5 0 1 0\n", {})).to raise_error

spec_summary
