# spec: compiled -- verified export uses mmap and native file operations
use spec
use ../lib/wrat

describe "WRAT to DRAT export" ->
  it "translates ID deletions and publishes only a verified refutation" ->
    cnf = ccall("__w_temp_file_for", "/tmp/wrat-export-cnf")
    proof = ccall("__w_temp_file_for", "/tmp/wrat-export-proof")
    dest = ccall("__w_temp_file_for", "/tmp/wrat-export-drat")
    begin
      write_file(cnf, "p cnf 2 4\n1 2 0\n1 -2 0\n-1 2 0\n-1 -2 0\n")
      prefix = "wrat 1\n5 1 0 1 2 0\n5 d 1 2 0\n"
      write_file(proof, prefix + "6 0 5 3 4 0\n")
      expect(wrat_export_drat(cnf, proof, dest)).to eq(2)
      expected = "1 0\nd 1 2 0\nd 1 -2 0\n0\n"
      expect(read_file(dest)).to eq(expected)
      write_file(proof, prefix + "6 0 5 3 0\n")
      rejected = false
      begin
        wrat_export_drat(cnf, proof, dest)
      rescue e
        rejected = true
      expect(rejected).to eq(true)
      expect(read_file(dest)).to eq(expected)
    ensure
      File.rm(cnf)
      File.rm(proof)
      File.rm(dest)
