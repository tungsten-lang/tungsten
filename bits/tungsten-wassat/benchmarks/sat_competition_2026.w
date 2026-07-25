# SAT Competition 2026 cross-solver runner.
#
# Runs every instance across every available solver, one at a time, and
# prints each result the moment it lands — a long benchmark sweep is
# useless if you have to wait until the end to see it going wrong.
#
#   tungsten benchmarks/sat_competition_2026.w <dir-or-file> [more...]
#
# Environment:
#   SC_TIMEOUT   per-solver seconds (default 60)
#   SC_SOLVERS   comma list to restrict, e.g. "wassat,kissat"
#   WASSAT       path to the wassat binary (default ./bin/wassat)
#
# Verdicts are cross-checked across solvers on every instance; a
# disagreement is reported loudly, because on this benchmark set a wrong
# answer has historically been much more expensive than a slow one.

# Timing comes from `/usr/bin/time -p` rather than a clock ccall, so this
# runs under the interpreter (no compile step) and on both macOS and
# Linux. Solver stdout goes to a temp file; only the timing returns
# through the pipe.
#
# `timeout` returns 124 when it kills the child; that is tagged so a
# killed run never masquerades as a fast UNKNOWN.
-> sc_run(cmd, secs, scratch)
  # Both streams go to files: `capture` does not return a brace group's
  # redirected stderr, and /usr/bin/time writes its report there. The
  # solver's own stderr lands in the same file, which is harmless — only
  # lines beginning "real" are read.
  tfile = scratch + ".time"
  z = system("/usr/bin/time -p timeout " + secs.to_s + " " + cmd +
             " > " + scratch + " 2> " + tfile)
  timing = read_file(tfile)
  timing = "" if timing == nil
  ms = 0
  timing.split("\n").each -> (line)
    if line.strip.starts_with?("real")
      secs_txt = line.strip.split(" ").last
      parts = secs_txt.split(".")
      whole = parts[0].to_i
      frac = parts.size > 1 ? (parts[1] + "00").slice(0, 2).to_i : 0
      ms = whole * 1000 + frac * 10
  out = read_file(scratch)
  out = "" if out == nil
  verdict = "NONE"
  out.split("\n").each -> (line)
    verdict = "SAT" if line.starts_with?("s SATISFIABLE")
    verdict = "UNSAT" if line.starts_with?("s UNSATISFIABLE")
    verdict = "UNKNOWN" if line.starts_with?("s UNKNOWN")
  verdict = "TIMEOUT" if verdict == "NONE" && ms >= secs * 1000 - 300
  { "verdict": verdict, "ms": ms }

-> sc_have?(name)
  capture("command -v " + name + " 2>/dev/null").strip != ""

# Only solvers actually installed are raced, so the table never carries a
# column of empty cells.
-> sc_solvers
  wassat_bin = env("WASSAT")
  wassat_bin = "./bin/wassat" if wassat_bin == nil || wassat_bin == ""
  all = []
  all.push({ "name": "wassat", "cmd": wassat_bin + " FILE --fast" }) if file?(wassat_bin)
  all.push({ "name": "cadical", "cmd": "cadical -q FILE" }) if sc_have?("cadical")
  all.push({ "name": "cms5", "cmd": "cryptominisat5 FILE" }) if sc_have?("cryptominisat5")
  all.push({ "name": "kissat", "cmd": "kissat -q FILE" }) if sc_have?("kissat")
  want = env("SC_SOLVERS")
  return all if want == nil || want == ""
  keep = []
  all.each -> (s)
    keep.push(s) if want.split(",").include?(s["name"])
  keep

-> sc_expand(paths)
  files = []
  paths.each -> (p)
    if capture("test -d " + p + " && echo d").strip == "d"
      capture("find " + p + " -name '*.cnf' -o -name '*.cnf.xz' | sort").split("\n").each -> (f)
        files.push(f) unless f.strip == ""
    else
      files.push(p) if file?(p)
  files

-> sc_pad(s, n)
  out = s
  out = out + " " while out.size < n
  out

-> sc_secs(ms)
  whole = ms / 1000
  frac = (ms % 1000) / 10
  tail = frac.to_s
  tail = "0" + tail if frac < 10
  whole.to_s + "." + tail

args = argv()
if args.size == 0
  << "usage: sat_competition_2026.w <dir-or-file> [more...]"
  << "  SC_TIMEOUT=<secs>  SC_SOLVERS=wassat,kissat  WASSAT=<path>"
  exit(1)

timeout_s = 60
timeout_s = env("SC_TIMEOUT").to_i if env("SC_TIMEOUT") != nil && env("SC_TIMEOUT") != ""

solvers = sc_solvers
if solvers.size == 0
  << "no solvers found (looked for wassat, cadical, cryptominisat5, kissat)"
  exit(1)

files = sc_expand(args)
if files.size == 0
  << "no .cnf files found under: " + args.join(" ")
  exit(1)

names = []
solvers.each -> (s)
  names.push(s["name"])
<< "SAT Competition 2026 runner — " + files.size.to_s + " instances, timeout " + timeout_s.to_s + "s"
<< "solvers: " + names.join(", ")
<< ""

header = sc_pad("instance", 34)
solvers.each -> (s)
  header = header + sc_pad(s["name"], 16)
<< header
<< "-" * header.size

scratch = "/tmp/sc2026_out.txt"
wins = {}
solved = {}
solvers.each -> (s)
  wins[s["name"]] = 0
  solved[s["name"]] = 0
mismatches = 0
i = 0
while i < files.size
  f = files[i]
  short = f.split("/").last
  short = short.slice(0, 32) if short.size > 32
  row = sc_pad(short, 34)
  seen = []
  best_ms = 0
  best_name = ""
  results = []
  si = 0
  while si < solvers.size
    s = solvers[si]
    r = sc_run(s["cmd"].replace("FILE", f), timeout_s, scratch)
    results.push(r)
    v = r["verdict"]
    cell = v
    cell = v + " " + sc_secs(r["ms"]) if v == "SAT" || v == "UNSAT"
    row = row + sc_pad(cell, 16)
    if v == "SAT" || v == "UNSAT"
      seen.push(v) unless seen.include?(v)
      solved[s["name"]] = solved[s["name"]] + 1
      if best_name == "" || r["ms"] < best_ms
        best_ms = r["ms"]
        best_name = s["name"]
    si += 1
  # Print the row NOW, before touching the next instance — a sweep that
  # only reports at the end tells you nothing while it runs.
  << row
  if seen.size > 1
    << "  !! VERDICT MISMATCH on " + short + " — solvers disagree: " + seen.join(" vs ")
    mismatches += 1
  wins[best_name] = wins[best_name] + 1 unless best_name == ""
  i += 1

<< ""
<< "summary over " + files.size.to_s + " instances"
solvers.each -> (s)
  n = s["name"]
  << "  " + sc_pad(n, 12) + "solved " + sc_pad(solved[n].to_s, 6) + "fastest " + wins[n].to_s
if mismatches > 0
  << ""
  << "!! " + mismatches.to_s + " VERDICT MISMATCH(ES) — a wrong answer outranks every timing above"
  exit(1)
