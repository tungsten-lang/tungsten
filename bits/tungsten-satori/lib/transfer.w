# A constant substitution transports every model satisfying the source guards
# outside the source and into the target iff this counterexample CNF is UNSAT.
use ../../tungsten-wrat/lib/dimacs

-> satori_transfer_counterexample(original, witness)
  n = original["nvars"]
  rows = witness["clauses"]
  raise "expected source guards, target guards, and assignment" unless rows.size == 3
  raise "wrong variable domain" unless witness["nvars"] == n
  setting = Array.new(n + 1, 0)
  rows[2].each -> (lit)
    raise "duplicate substitution variable" unless setting[lit.abs] == 0
    setting[lit.abs] = lit
  clauses = original["clauses"].dup
  rows[0].each -> (lit)
    clauses.push([lit])
  # A fresh selector witnesses one false clause after substitution. Unchanged
  # original clauses already hold in every candidate source model.
  bad = []
  goals = original["clauses"].dup
  rows[1].each -> (lit)
    goals.push([lit])
  exclude_source = []
  rows[0].each -> (lit)
    exclude_source.push(0 - lit)
  goals.push(exclude_source)
  i = 0
  while i < goals.size
    remainder = []
    satisfied = false
    goals[i].each -> (lit)
      value = setting[lit.abs]
      if value == lit
        satisfied = true
      elsif value == 0
        remainder.push(lit)
    if !satisfied && (i >= original["clauses"].size || remainder.size != goals[i].size)
      selector = n + bad.size + 1
      bad.push(selector)
      remainder.each -> (lit)
        clauses.push([0 - selector, 0 - lit])
    i += 1
  clauses.push(bad)
  clauses

-> satori_transfer_main(args)
  if args.size != 4
    << "usage: satori " + args[0] + " ORIGINAL.cnf TRANSFER.cnf " + (args[0] == "check-transfer" ? "PROOF.lrat" : "OUTPUT.cnf")
    return 1
  begin
    original = wrat_parse_cnf(File.read(args[1]))
    witness = wrat_parse_cnf(File.read(args[2]))
    clauses = satori_transfer_counterexample(original, witness)
    if args[0] == "emit-transfer"
      File.write(args[3], sat_dimacs(clauses))
    elsif lrat_check(clauses, File.read(args[3]))
      << "VERIFIED state transfer"
    else
      << "error: transfer proof rejected"
      return 1
  rescue e
    << "error: " + e.to_s
    return 1
  0
