# Trimming specs (E5): the trimmed certificate must remain a certificate.

use spec
use wassat
use ../../tungsten-wrat/lib/wrat

TRIM_PHP32 = "p cnf 6 9\n1 2 0\n3 4 0\n5 6 0\n-1 -3 0\n-1 -5 0\n-3 -5 0\n-2 -4 0\n-2 -6 0\n-4 -6 0\n"
TRIM_ALL4 = "p cnf 2 4\n1 2 0\n1 -2 0\n-1 2 0\n-1 -2 0\n"

describe "Wassat proof trimming" ->

  context "backward pruning" ->
    it "keeps a subset that still verifies under the independent checker" ->
      r = wassat_solve_preprocessed(TRIM_PHP32, WASSAT_PROOF_WRAT, 0, 0)
      expect(r["unsat"]).to eq(true)
      full = "wrat 1\n" + r["proof"].join("\n") + "\n"
      t = wassat_trim_hinted(full)
      expect(t["found_empty"]).to eq(true)
      expect(t["kept"] <= t["total"]).to eq(true)
      check = wrat_verify(TRIM_PHP32, t["text"])
      expect(check["verified"]).to eq(true)

    it "preserves the header iff present" ->
      r = wassat_solve_preprocessed(TRIM_ALL4, WASSAT_PROOF_WRAT, 0, 0)
      full = "wrat 1\n" + r["proof"].join("\n") + "\n"
      t = wassat_trim_hinted(full)
      expect(t["text"].starts_with?("wrat 1")).to eq(true)
      bare = r["proof"].join("\n") + "\n"
      t2 = wassat_trim_hinted(bare)
      expect(t2["text"].starts_with?("wrat 1")).to eq(false)
      check = wrat_verify(TRIM_ALL4, t2["text"])
      expect(check["verified"]).to eq(true)

    it "drops steps after the first empty clause and all deletions" ->
      r = wassat_solve_preprocessed(TRIM_PHP32, WASSAT_PROOF_WRAT, 0, 0)
      full = "wrat 1\n" + r["proof"].join("\n") + "\n"
      t = wassat_trim_hinted(full)
      has_delete = false
      t["text"].split("\n").each -> (line)
        toks = wassat_tokenize(line)
        has_delete = true if toks.size > 1 && toks[1] == "d"
      expect(has_delete).to eq(false)

    it "refuses to trim a non-refutation" ->
      t = wassat_trim_hinted("wrat 1\n10 1 2 0 3 4 0\n")
      expect(t["found_empty"]).to eq(false)
      expect(t["text"]).to eq("wrat 1\n10 1 2 0 3 4 0\n")

    it "renders trimmed DRAT that verifies" ->
      r = wassat_solve_preprocessed(TRIM_ALL4, WASSAT_PROOF_WRAT, 0, 0)
      full = "wrat 1\n" + r["proof"].join("\n") + "\n"
      t = wassat_trim_hinted(full)
      dtext = wassat_trim_to_drat(t["text"])
      expect(dtext.ends_with?("0\n")).to eq(true)
      check = wrat_verify(TRIM_ALL4, dtext)
      expect(check["verified"]).to eq(true)

spec_summary
