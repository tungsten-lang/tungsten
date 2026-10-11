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
  # Resource guard (macOS has no enforceable ulimit -v): a single machine-wide
  # lock serializes solves, and a watchdog kills the solver when its resident
  # memory exceeds SATORI_SAT_MEM_MB (default 8192) or its run time exceeds
  # SATORI_SAT_SECONDS (default 600).
  mem = Env.get("SATORI_SAT_MEM_MB")
  if mem == nil || mem == ""
    mem = "8192"
  secs = Env.get("SATORI_SAT_SECONDS")
  if secs == nil || secs == ""
    secs = "600"
  lock = dir + "/.solver.lock"
  guard = "while ! mkdir \"$5\" 2>/dev/null; do sleep 0.5; done; trap 'rmdir \"$5\"' EXIT; "
  guard = guard + "\"$0\" \"$1\" --lrat \"$2\" > \"$3\" 2>&1 & pid=$!; t=0; "
  guard = guard + "while kill -0 $pid 2>/dev/null; do r=$(ps -o rss= -p $pid 2>/dev/null | tr -d ' '); "
  guard = guard + "if test -n \"$r\" && test \"$r\" -gt $(( $4 * 1024 )); then kill -9 $pid; echo 'c satori: solver exceeded memory limit' >> \"$3\"; fi; "
  guard = guard + "if test $t -gt $(( $6 * 4 )); then kill -9 $pid; echo 'c satori: solver exceeded time limit' >> \"$3\"; fi; "
  guard = guard + "sleep 0.25; t=$((t+1)); done; wait $pid"
  p = Process.spawn(["/bin/sh", "-c", guard, solver, cnf, proof, out, mem, lock, secs])
  p.wait
  res = ""
  if File.exist?(out)
    res = File.read(out)
  if res.include?("exceeded memory limit") || res.include?("exceeded time limit")
    raise "sat: solver stopped (" + clauses.size.to_s + " clauses): " + res.split("\n").select(->(l) l.include?("satori:")).join(" ") + " — shrink the instance or raise SATORI_SAT_MEM_MB / SATORI_SAT_SECONDS"
  if !res.include?("UNSATISFIABLE")
    if res.include?("SATISFIABLE")
      raise "sat: the formula is satisfiable (the claim is false)"
    raise "sat: solver failed: " + res
  File.read(proof)
