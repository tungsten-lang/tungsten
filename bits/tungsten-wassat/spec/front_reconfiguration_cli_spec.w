use spec
use reconfiguration_support

-> front_cli_bin
  bin = env("WASSAT_TEST_BIN")
  bin == nil || bin == "" ? "bits/tungsten-wassat/bin/wassat" : bin

-> front_cli_exits(cmd, code)
  system("(" + cmd + "); test $? -eq [code]")

describe "Wassat early reconfiguration CLI" ->
  it "uses the early reconfiguration scout only in unrestricted fast mode" ->
    rows = rc_rows(6, [1, 3], [2, 4], 3)
    rows.push([-2, -5])
    clauses = []
    rows.each -> (row) clauses.push(row.join(" ") + " 0")
    while clauses.size < 1000
      clauses.push("1 -1 0")
    cnf = "/tmp/wassat-cli-front-reconfiguration.cnf"
    expect(write_file(cnf, "p cnf 64 1000\n" + clauses.join("\n") + "\n")).to eq(true)
    bin = front_cli_bin
    out = "/tmp/wassat-cli-front-reconfiguration.out"
    cmd = "WASSAT_BACKDOOR_TABLES=0 WASSAT_PROFILE=1 " + bin + " " + cnf
    expect(front_cli_exits(cmd + " --fast > " + out + " 2>&1", 10)).to eq(true)
    text = read_file(out)
    expect(text.index("c mode: fast (verified front graph reconfiguration)") != nil).to eq(true)
    result = i64[65]
    text.split("\n").each -> (line)
      if line.starts_with?("v ")
        fields = wassat_tokenize(line)
        i = 1
        while i < fields.size
          lit = fields[i].to_i
          result[lit < 0 ? -lit : lit] = lit > 0 ? 1 : 0 if lit != 0
          i += 1
    expect(rc_replay(rows, result)).to eq(true)
    z = system(cmd + " --fast --conflicts 1 > " + out + " 2>&1")
    bounded = read_file(out)
    expect(bounded.index("s SATISFIABLE") != nil || bounded.index("s UNKNOWN") != nil).to eq(true)
    expect(bounded.index("front.reconfiguration") == nil).to eq(true)
    expect(front_cli_exits(cmd + " --fast --sequential > " + out + " 2>&1", 10)).to eq(true)
    expect(read_file(out).index("front.reconfiguration") == nil).to eq(true)
    expect(front_cli_exits(cmd + " --drat /tmp/wassat-cli-front-proof.drat > " + out + " 2>&1", 10)).to eq(true)
    expect(read_file(out).index("front.reconfiguration") == nil).to eq(true)


spec_summary
