# Bridge to an external SAT solver. The solver is untrusted: it only has to
# produce an LRAT refutation, which the kernel re-checks.
#
# Solver selection: $SATORI_SOLVER, else the Tungsten SAT solver bit
# (bits/tungsten-wassat/bin/wassat) relative to the Tungsten root.

-> sat_solver_path(session)
  env = Env.get("SATORI_SOLVER")
  if env != nil && env != ""
    return env
  session.solver_path

-> sat_dimacs(clauses)
  nv = 0
  clauses.each -> (c)
    c.each -> (l)
      a = l
      if a < 0
        a = 0 - a
      if a > nv
        nv = a
  sb = StringBuffer()
  sb.append("p cnf " + nv.to_s + " " + clauses.size.to_s + "\n")
  clauses.each -> (c)
    c.each -> (l)
      sb.append(l.to_s)
      sb.append(" ")
    sb.append("0\n")
  sb.to_s

-> sat_cache_key(text)
  Digest.sha256(text)

# Returns LRAT text refuting `clauses`, using a content-addressed cache.
-> sat_solve_lrat(session, clauses)
  text = sat_dimacs(clauses)
  key = sat_cache_key(text)
  dir = session.cache_dir
  if !File.exist?(dir)
    File.mkdir_p(dir)
  cnf = dir + "/" + key + ".cnf"
  proof = dir + "/" + key + ".lrat"
  if File.exist?(proof)
    return File.read(proof)
  File.write(cnf, text)
  out = dir + "/" + key + ".out"
  solver = sat_solver_path(session)
  p = Process.spawn(["/bin/sh", "-c", "exec \"$0\" \"$1\" --lrat \"$2\" > \"$3\" 2>&1", solver, cnf, proof, out])
  p.wait
  res = ""
  if File.exist?(out)
    res = File.read(out)
  if !res.include?("UNSATISFIABLE")
    if res.include?("SATISFIABLE")
      raise "sat: the formula is satisfiable (the claim is false)"
    raise "sat: solver failed: " + res
  File.read(proof)
