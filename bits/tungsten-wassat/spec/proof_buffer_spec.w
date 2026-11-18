# spec: compiled -- streaming uses file-append ccalls unavailable to the interpreter
use spec
use ../lib/solver

+ ProofBufferFixture < Wassat
  -> small_buffers(cap)
    @wbcap = cap
    @dbcap = cap
    0

  -> buffered_line(cid)
    @lbuf[0] = 1
    @phint[0] = 1
    self.wrat_put(cid, 1, 1)
    self.drat_put(@lbuf, 0, 1, 0) if @dbytes != nil
    0

  -> bad_chunk(path)
    @wchunk = path
    0

-> proof_buffer_rows
  rows = []
  p = 0
  while p < 6
    row = []
    h = 0
    while h < 5
      row.push(p * 5 + h + 1)
      h += 1
    rows.push(row)
    p += 1
  p = 0
  while p < 6
    q = p + 1
    while q < 6
      h = 0
      while h < 5
        rows.push([0 - (p * 5 + h + 1), 0 - (q * 5 + h + 1)])
        h += 1
      q += 1
    p += 1
  rows

describe "Streamed hinted proofs" ->
  it "matches in-memory WRAT and DRAT through flushes and oversized fallback" ->
    rows = proof_buffer_rows
    mem = Wassat.new(30, rows, WASSAT_PROOF_WRAT)
    mem.enable_dual_drat
    reference = mem.solve_budget(0)
    expect(reference["status"]).to eq(-1)
    [1, 64, 1048576].each -> (cap)
      wp = "/tmp/wassat-proof-buffer-[cap].wrat"
      dp = "/tmp/wassat-proof-buffer-[cap].drat"
      write_file(wp, "")
      write_file(dp, "")
      s = ProofBufferFixture.new(30, rows, WASSAT_PROOF_WRAT)
      s.enable_dual_drat
      s.stream_proofs(wp, dp)
      s.small_buffers(cap)
      r = s.solve_budget(0)
      s.flush_proof_sinks
      expect(r["status"]).to eq(-1)
      expect(r["conflicts"]).to eq(reference["conflicts"])
      expect(read_file(wp)).to eq("wrat 1\n" + reference["proof"].join("\n") + "\n")
      expect(read_file(dp)).to eq(reference["drat"].join("\n") + "\n")
      s.abort_proof_sinks

  it "orders buffered and text records after a coordinator's header" ->
    wp = "/tmp/wassat-proof-buffer-order.wrat"
    dp = "/tmp/wassat-proof-buffer-order.drat"
    write_file(wp, "wrat 1\n2 1 0 1 0\n")
    write_file(dp, "")
    s = ProofBufferFixture.new(1, [[1]], WASSAT_PROOF_WRAT)
    s.stream_proofs(wp, dp)
    s.wrat_header_written
    s.buffered_line(3)
    s.log_wrat_line("4 1 0 1 0")
    s.log_drat_line("-1 0")
    s.buffered_line(5)
    s.flush_proof_sinks
    expect(read_file(wp)).to eq("wrat 1\n2 1 0 1 0\n3 1 0 1 0\n4 1 0 1 0\n5 1 0 1 0\n")
    expect(read_file(dp)).to eq("1 0\n-1 0\n1 0\n")
    s.abort_proof_sinks

  it "can retain either dialect in memory while streaming the other" ->
    rows = proof_buffer_rows
    mem = Wassat.new(30, rows, WASSAT_PROOF_WRAT)
    mem.enable_dual_drat
    reference = mem.solve_budget(0)
    [true, false].each -> (stream_wrat)
      wp = stream_wrat ? "/tmp/wassat-proof-buffer-mixed.wrat" : nil
      dp = stream_wrat ? nil : "/tmp/wassat-proof-buffer-mixed.drat"
      write_file(wp, "") unless wp == nil
      write_file(dp, "") unless dp == nil
      s = ProofBufferFixture.new(30, rows, WASSAT_PROOF_WRAT)
      s.enable_dual_drat
      s.stream_proofs(wp, dp)
      r = s.solve_budget(0)
      s.flush_proof_sinks
      expect(r["status"]).to eq(-1)
      if stream_wrat
        expect(read_file(wp)).to eq("wrat 1\n" + reference["proof"].join("\n") + "\n")
        expect(r["drat"]).to eq(reference["drat"])
      else
        expect(read_file(dp)).to eq(reference["drat"].join("\n") + "\n")
        expect(r["proof"]).to eq(reference["proof"])
      s.abort_proof_sinks

  it "clears both buffered streams on abort, including a later flush" ->
    wp = "/tmp/wassat-proof-buffer-abort.wrat"
    dp = "/tmp/wassat-proof-buffer-abort.drat"
    write_file(wp, "")
    write_file(dp, "")
    s = ProofBufferFixture.new(1, [[1]], WASSAT_PROOF_WRAT)
    s.stream_proofs(wp, dp)
    s.buffered_line(2)
    s.flush_proof_sinks
    s.buffered_line(3)
    s.abort_proof_sinks
    s.flush_proof_sinks
    expect(read_file(wp)).to eq("")
    expect(read_file(dp)).to eq("")

  it "keeps scratch files distinct from both proof destinations" ->
    [true, false].each -> (wrat_first)
      base = "/tmp/wassat-proof-buffer-alias"
      wp = wrat_first ? base : base + ".chunk"
      dp = wrat_first ? base + ".chunk" : base
      write_file(wp, "")
      write_file(dp, "")
      s = ProofBufferFixture.new(1, [[1]], WASSAT_PROOF_WRAT)
      s.stream_proofs(wp, dp)
      s.buffered_line(2)
      s.flush_proof_sinks
      s.buffered_line(3)
      s.flush_proof_sinks
      expect(read_file(wp)).to eq("wrat 1\n2 1 0 1 0\n3 1 0 1 0\n")
      expect(read_file(dp)).to eq("1 0\n1 0\n")
      s.abort_proof_sinks

  it "surfaces header, chunk and append failures" ->
    missing = "/tmp/wassat-proof-buffer-missing-dir/proof"
    s = ProofBufferFixture.new(1, [[1]], WASSAT_PROOF_WRAT)
    s.stream_proofs(missing, nil)
    expect(-> () s.buffered_line(2)).to raise_error
    wp = "/tmp/wassat-proof-buffer-failure.wrat"
    write_file(wp, "")
    t = ProofBufferFixture.new(1, [[1]], WASSAT_PROOF_WRAT)
    t.stream_proofs(wp, nil)
    t.buffered_line(2)
    t.bad_chunk(missing)
    expect(-> () t.flush_proof_sinks).to raise_error
    # A directory cannot be opened as an append destination; its sibling
    # chunk remains writable, so this exercises the checked append itself.
    u = ProofBufferFixture.new(1, [[1]], WASSAT_PROOF_WRAT)
    u.stream_proofs("/tmp", nil)
    u.wrat_header_written
    u.bad_chunk("/tmp/wassat-proof-buffer-append.chunk")
    u.buffered_line(2)
    expect(-> () u.flush_proof_sinks).to raise_error
    ccall("__w_unlink", "/tmp/wassat-proof-buffer-append.chunk")
