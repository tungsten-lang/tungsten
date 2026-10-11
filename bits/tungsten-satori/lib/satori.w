# Satori — a concise proof language with a small LCF-style kernel.
#
# Trusted base: term.w (data), kernel.w, eval.w, checkers.w.
# Everything else (elaboration, tactics, automation) builds theorems only
# through the kernel's rules.

use term
use printer
use checkers
use eval
use kernel
use derived
use lexer
use parser
use elab
use simp
use arith
use satbridge
use tactics
use pattern
use session

SATORI_VERSION = "0.1.0"

-> satori_usage
  << "Satori [SATORI_VERSION] — a concise proof language with a small kernel"
  << ""
  << "USAGE"
  << "    satori check FILE.sat ...     check proofs (default command)"
  << "    satori stats FILE.sat ...     check and print line/theorem counts"
  << "    satori version"
  << "    satori check -j N FILE.sat    split mode: each theorem in its own process, N at a time"
  << "                                  (fresh memory per theorem; same verdict and trust tags)"
  << ""
  << "ENVIRONMENT"
  << "    SATORI_ROOT     Tungsten checkout (prelude + SAT solver); default: cwd"
  << "    SATORI_SOLVER   external SAT solver emitting LRAT (default: wassat)"

-> satori_main(args)
  if args.size == 0 || args[0] == "help" || args[0] == "--help"
    satori_usage
    return 0
  if args[0] == "version"
    << "satori " + SATORI_VERSION
    return 0
  stats = false
  only = nil
  jobs = 0
  files = []
  i = 0
  while i < args.size
    a = args[i]
    if a == "check" || a == "stats"
      stats = a == "stats"
    elsif a == "--only" && i + 1 < args.size
      only = args[i + 1].to_i
      i += 1
    elsif a == "-j" && i + 1 < args.size
      jobs = args[i + 1].to_i
      i += 1
    else
      files.push(a)
    i += 1
  root = Env.get("SATORI_ROOT")
  if root == nil || root == ""
    root = Dir.pwd
    # run from elsewhere (e.g. a project directory): use the standard checkout
    if !File.exist?(root + "/bits/tungsten-satori/prelude/prelude.sat")
      root = Env.get("HOME") + "/tungsten"
  failures = 0
  if jobs > 0
    files.each -> (f)
      failures += split_check(root, f, jobs)
    if failures > 0
      return 1
    return 0
  files.each -> (f)
    s = Session.new(root)
    s.only = only
    s.load_prelude
    t0 = ccall("__w_clock")
    s.run_file(f)
    dt = ccall("__w_clock") - t0
    failures += s.failures
    st = s.stats
    status = "OK"
    if s.failures > 0
      status = "FAILED (" + s.failures.to_s + ")"
    << "── " + f + ": " + status + " — " + s.stats_line + ", " + (st["lines"]).to_s + " lines, " + ((dt * ~1000.0).round / ~1000.0).to_s + " s"
  if failures > 0
    return 1
  0

# ---- split mode ------------------------------------------------------------------------
#
# Tungsten has no garbage collector, so one process that checks many heavy
# theorems keeps all their memory. Split mode runs `satori --only 0` once (all
# theorems admitted, to print definitions and count theorems), then
# `satori --only K` for every theorem K, each in a fresh process with a memory
# and time watchdog, N at a time. A process admits the other theorems with the
# tag split:NAME; the driver replaces those tags by the transitive tags of NAME's
# own check, so the report is the one a single process would print.

-> split_lines(path)
  if !File.exist?(path)
    return []
  File.read(path).split("\n")

-> split_block(lines, k)
  out = []
  inside = false
  lines.each -> (l)
    if l == "⟦/" + k.to_s + "⟧"
      inside = false
    if inside
      out.push(l)
    if l == "⟦" + k.to_s + "⟧"
      inside = true
  out

# [base text, own tags, split dependencies] of a "✓ name : stmt   [tags]" line
-> split_tags(line)
  parts = line.split("   \[")
  if parts.size < 2 || !line.ends_with?("]")
    return [line, [], []]
  base = arr_sub(parts, 0, parts.size - 1).join("   \[")
  last = parts[parts.size - 1]
  inner = last.chars
  body = arr_sub(inner, 0, inner.size - 1).join("")
  own = []
  deps = []
  body.split(", ").each -> (t)
    if t.starts_with?("split:")
      deps.push(t.split("split:")[1])
    else
      own.push(t)
  [base, own, deps]

-> split_resolve(name, own, deps, memo, failed, stack)
  if memo.has_key?(name)
    return memo[name]
  out = []
  if own.has_key?(name)
    own[name].each -> (t)
      if !out.include?(t)
        out.push(t)
  if deps.has_key?(name) && !stack.include?(name)
    stack.push(name)
    deps[name].each -> (d)
      if failed.has_key?(d)
        if !out.include?("uses-failed:" + d)
          out.push("uses-failed:" + d)
      split_resolve(d, own, deps, memo, failed, stack).each -> (t)
        if !out.include?(t)
          out.push(t)
    stack.pop
  memo[name] = out
  out

-> split_check(root, f, jobs)
  t0 = ccall("__w_clock")
  bin = Env.get("SATORI_BIN")
  if bin == nil || bin == ""
    bin = root + "/bits/tungsten-satori/bin/satori"
  mem = Env.get("SATORI_JOB_MEM_MB")
  if mem == nil || mem == ""
    mem = "6144"
  secs = Env.get("SATORI_JOB_SECONDS")
  if secs == nil || secs == ""
    secs = "3600"
  dir = root + "/bits/tungsten-satori/.satori-cache/split-" + ((t0 * ~1000000.0).round % 1000000000).to_s
  File.mkdir_p(dir)
  p = Process.spawn(["/bin/sh", "-c", "SATORI_ROOT=\"$3\" \"$0\" --only 0 \"$1\" > \"$2\" 2>&1", bin, f, dir + "/out.0", root])
  p.wait
  skel = split_lines(dir + "/out.0")
  names = []
  skel.each -> (l)
    if l.starts_with?("⋯ split ")
      names.push(l.split("⋯ split ")[1])
  if names.size > 0
    job = "out=\"$4/out.$3\"; SATORI_ROOT=\"$5\" \"$0\" --only \"$3\" \"$1\" > \"$out\" 2>&1 & pid=$!; t=0; "
    job = job + "while kill -0 $pid 2>/dev/null; do r=$(ps -o rss= -p $pid 2>/dev/null | tr -d ' '); "
    job = job + "if test -n \"$r\" && test \"$r\" -gt $(( $2 * 1024 )); then kill -9 $pid; echo 'satori-split: memory limit' >> \"$out\"; fi; "
    job = job + "if test $t -gt $(( $6 * 4 )); then kill -9 $pid; echo 'satori-split: time limit' >> \"$out\"; fi; "
    job = job + "sleep 0.25; t=$((t+1)); done; wait $pid"
    drv = "seq 1 \"$1\" | xargs -P \"$2\" -I{} /bin/sh -c \"$3\" \"$4\" \"$5\" \"$6\" {} \"$7\" \"$8\" \"$9\""
    q = Process.spawn(["/bin/sh", "-c", drv, "sh", names.size.to_s, jobs.to_s, job, bin, f, mem, dir, root, secs])
    q.wait
  # collect each theorem's block, own tags and split dependencies
  blocks = {}
  own = {}
  deps = {}
  failed = {}
  k = 0
  while k < names.size
    nm = names[k]
    lines = split_lines(dir + "/out." + (k + 1).to_s)
    b = split_block(lines, k + 1)
    if b.size == 0 || !b[0].starts_with?("✓ ")
      failed[nm] = true
      if b.size == 0
        tail = []
        lines.each -> (l)
          if l.starts_with?("satori-split:") || l.starts_with?("✗")
            tail.push(l)
        b = ["✗ theorem " + nm + ": its checking process stopped " + tail.join(" ")]
    else
      st = split_tags(b[0])
      own[nm] = st[1]
      deps[nm] = st[2]
    blocks[nm] = b
    k += 1
  memo = {}
  nfail = 0
  skel.each -> (l)
    if l.starts_with?("⋯ split ")
      nm = l.split("⋯ split ")[1]
      b = blocks[nm]
      if failed.has_key?(nm)
        nfail += 1
        b.each -> (x)
          << x
      else
        st = split_tags(b[0])
        tags = split_resolve(nm, own, deps, memo, failed, [])
        line = st[0]
        if tags.size > 0
          line = line + "   \[" + tags.join(", ") + "\]"
        << line
        arr_sub(b, 1, b.size - 1).each -> (x)
          << x
    elsif l.starts_with?("── ")
      0
    else
      if l.starts_with?("✗")
        nfail += 1
      << l
  dt = ccall("__w_clock") - t0
  info = ""
  finished = false
  skel.each -> (l)
    if l.starts_with?("── ")
      finished = true
  if !finished
    # the skeleton process died (crash, memory or time): never report OK
    nfail += 1
    << "✗ " + f + ": the elaboration process stopped before the end of the file"
    tail = []
    skel.each -> (l)
      if l.starts_with?("unhandled") || l.starts_with?("satori-split:") || l.starts_with?("error")
        tail.push(l)
    if tail.size > 0
      << "  " + tail.join(" ")
  skel.each -> (l)
    if l.starts_with?("── ")
      parts = l.split(" — ")
      if parts.size > 1
        sp = parts[1].split(", ")
        info = arr_sub(sp, 0, sp.size - 1).join(", ")
  status = "OK"
  if nfail > 0
    status = "FAILED (" + nfail.to_s + ")"
  << "── " + f + ": " + status + " — " + info + ", " + ((dt * ~1000.0).round / ~1000.0).to_s + " s wall, " + names.size.to_s + " theorem processes, " + jobs.to_s + " at a time"
  Process.spawn(["/bin/rm", "-rf", dir]).wait
  nfail
