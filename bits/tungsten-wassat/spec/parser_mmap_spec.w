# spec: compiled -- native DIMACS scanner and mapped file lifetime
use spec
use ../lib/cnf

-> mmap_raw_scan(source, count_only)
  lits = i64[32]
  offs = i64[16]
  lens = i64[16]
  hdr = i64[8]
  if count_only
    z = ccall("__w_parse_dimacs", source, nil, nil, nil, hdr)
  else
    z = ccall("__w_parse_dimacs", source, lits, offs, lens, hdr)
  [hdr, lits, offs, lens]

-> mmap_check_modes(text)
  path = "/tmp/wassat-case328-mmap-fixture.cnf"
  raise "write failed" unless write_file(path, text)
  mapping = File.mmap(path)
  begin
    a = mmap_raw_scan(text, false)
    b = mmap_raw_scan(mapping, false)
    ca = mmap_raw_scan(text, true)
    cb = mmap_raw_scan(mapping, true)
    raise "fill header differs" unless a[0].to_s == b[0].to_s
    raise "count header differs" unless ca[0].to_s == cb[0].to_s
    raise "count/fill validation differs" unless a[0].to_s == ca[0].to_s
    if a[0][4] == 0
      raise "literal data differs" unless a[1].to_s == b[1].to_s
      raise "clause offsets differ" unless a[2].to_s == b[2].to_s
      raise "clause lengths differ" unless a[3].to_s == b[3].to_s
    a[0][4]
  ensure
    mapping.close
    File.unlink(path)

describe "Mapped native DIMACS input" ->
  it "keeps exact counts and contents for comments, empty clauses and a trailer" ->
    expect(mmap_check_modes("c hi\np cnf 3 4\n1 -2 0 0\n+3 0\n-1 2 3 0\n%\n0\n")).to eq(0)
    expect(mmap_check_modes("p cnf 0 0")).to eq(0)
    expect(mmap_check_modes("p cnf 1 2\n0\n0")).to eq(0)
  it "rejects malformed input identically in all four scanner modes" ->
    cases = [["", 1], ["1 0", 1], ["p cnf 1 1\np cnf 1 1\n1 0", 1],
             ["p cnf 1x 1\n1 0", 2], ["p xnf 1 1\n1 0", 2],
             ["p cnf 1 1\n00", 3], ["p cnf 1 1\n-0", 3],
             ["p cnf 1 1\n+0", 3], ["p cnf 1 1\n1x 0", 3],
             ["p cnf 1 1\n2 0", 4], ["p cnf 1 1\n1", 5],
             ["p cnf 1 2\n1 0", 6], ["p cnf 1 0\n0", 6],
             ["p cnf 1 1\nx 1 0", 8]]
    cases.each ->(item)
      expect(mmap_check_modes(item[0])).to eq(item[1])
  it "sizes mapped buffers from the validated syntax" ->
    path = "/tmp/wassat-case328-mmap-size.cnf"
    text = "c " + "x" * 70000 + "\np cnf 3 2\n1 -2 0\n3 0\n"
    write_file(path, text)
    f = wassat_parse_cnf_file_native(path)
    expect([f["nvars"], f["flat_ncl"], f["flat_nlits"]]).to eq([3, 2, 3])
    expect([f["flat_lits"].size, f["flat_offs"].size, f["flat_lens"].size]).to eq([4, 4, 4])
    expect(f["flat_lits"][1]).to eq(-2)
    File.unlink(path)
  it "rejects closed mappings, short headers and mismatched output buffers" ->
    path = "/tmp/wassat-case328-mmap-closed.cnf"
    write_file(path, "p cnf 1 1\n1 0\n")
    mapping = File.mmap(path)
    mapping.close
    hdr = i64[8]
    expect(-> () ccall("__w_parse_dimacs", mapping, nil, nil, nil, hdr)).to raise_error
    expect(-> () ccall("__w_parse_dimacs", "p cnf 0 0", nil, nil, nil, nil)).to raise_error
    boxed = [0, 0, 0, 0, 0, 0, 0, 0]
    expect(-> () ccall("__w_parse_dimacs", "p cnf 0 0", nil, nil, nil, boxed)).to raise_error
    narrow = i32[8]
    expect(-> () ccall("__w_parse_dimacs", "p cnf 0 0", narrow, narrow, narrow, hdr)).to raise_error
    short = i64[5]
    expect(-> () ccall("__w_parse_dimacs", "p cnf 0 0", nil, nil, nil, short)).to raise_error
    lits = i64[8]
    expect(-> () ccall("__w_parse_dimacs", "p cnf 0 0", lits, nil, nil, hdr)).to raise_error
    offs = i64[8]
    lens = i64[1]
    z = ccall("__w_parse_dimacs", "p cnf 1 1\n1 0", lits, offs, lens, hdr)
    expect(hdr[4]).to eq(7)
    File.unlink(path)

spec_summary
