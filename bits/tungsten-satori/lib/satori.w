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
use polynomial
use tactics
use pattern
use session

SATORI_VERSION = "0.1.0"
SATORI_SPLIT_PROTOCOL = "⋯ satori split protocol 7"

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
  << "OPTIONS"
  << "    --no-cache                    bypass .satc verified module cache"
  << ""
  << "ENVIRONMENT"
  << "    SATORI_ROOT       Tungsten checkout (prelude + SAT solver); default: cwd"
  << "    SATORI_SOLVER     external SAT solver emitting LRAT (default: wassat)"
  << "    SATORI_NO_CACHE   set to 1 to bypass .satc verified module cache"

-> satori_digits?(s)
  if s.size == 0
    return false
  i = 0
  while i < s.size
    if !"0123456789".include?(s.slice(i, 1))
      return false
    i += 1
  true

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
  no_cache = false
  files = []
  i = 0
  while i < args.size
    a = args[i]
    if a == "check" || a == "stats"
      stats = a == "stats"
    elsif a == "--no-cache"
      no_cache = true
    elsif a == "--only" && i + 1 < args.size
      if !satori_digits?(args[i + 1])
        << "error: --only requires a nonnegative theorem index"
        return 1
      only = args[i + 1].to_i
      i += 1
    elsif a == "-j" && i + 1 < args.size
      jobs = args[i + 1].to_i
      if !satori_digits?(args[i + 1]) || jobs <= 0
        << "error: -j requires a positive job count"
        return 1
      i += 1
    elsif a == "-j" || a == "--only"
      << "error: " + a + " requires an argument"
      return 1
    else
      files.push(a)
    i += 1
  if files.size == 0
    << "error: no input files"
    return 1
  if only == 0
    << SATORI_SPLIT_PROTOCOL
  root = Env.get("SATORI_ROOT")
  if root == nil || root == ""
    root = Dir.pwd
    if !File.exist?(root + "/bits/tungsten-satori/prelude/prelude.sat")
      root = Env.get("HOME") + "/tungsten"
  failures = 0
  if jobs > 0
    files.each -> (f)
      failures += split_check(root, f, jobs, no_cache)
    if failures > 0
      return 1
    return 0
  files.each -> (f)
    s = Session.new(root)
    if no_cache
      s.no_cache = true
    s.only = only
    if only != nil && only > 0
      path = Env.get("SATORI_SPLIT_PREMISES")
      if path != nil && path != ""
        split_lines(path).each -> (tag) s.split_premises[tag] = true
    s.load_prelude
    t0 = ccall("__w_clock")
    s.run_file(f)
    if only != nil && only > 0 && s.premise_retry.size > 0
      << "⋯ select " + s.premise_retry.keys.join(" ")
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

-> split_lines(path)
  if !File.exist?(path)
    return []
  File.read(path).split("\n")

-> split_block(lines, k)
  out = []
  inside = false
  open_m = "⟦" + k.to_s + "⟧"
  close_m = "⟦/" + k.to_s + "⟧"
  lines.each -> (l)
    if l == close_m
      inside = false
    if inside
      out.push(l)
    if l == open_m
      inside = true
  out

# [base text, own tags, split dependencies] of a "✓ name : stmt   [tags]" line
-> split_tags(line)
  parts = line.split("   \[")
  if parts.size < 2 || !line.ends_with?("]")
    return [line, [], []]
  base = arr_sub(parts, 0, parts.size - 1).join("   \[")
  last = parts[parts.size - 1]
  body = last.slice(0, last.size - 1)
  own = []
  deps = []
  body.split(", ").each -> (t)
    if t.starts_with?("split:")
      deps.push(t.slice(6, t.size - 6))
    elsif t != ""
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
        if !out.include?("uses-failed:" + failed[d])
          out.push("uses-failed:" + failed[d])
      split_resolve(d, own, deps, memo, failed, stack).each -> (t)
        if !out.include?(t)
          out.push(t)
    stack.pop
  memo[name] = out
  out

-> split_partial_note(line, own, deps, memo, failed)
  st = split_tags(line)
  parts = st[0].split("\t")
  if parts.size < 2 || parts.size > 4 || st[2].size == 0
    return nil
  st[2].each -> (id)
    if failed.has_key?(id) || !own.has_key?(id)
      return nil
    tags = split_resolve(id, own, deps, memo, failed, [])
    if tags.any?(-> (tag) tag == "sorry" || tag.starts_with?("uses-failed:"))
      return nil
  partial_proof_note(parts[1], parts.size >= 3 ? parts[2] : nil, parts.size == 4 ? parts[3] : nil)

-> split_check(root, f, jobs, no_cache = false)
  t0 = ccall("__w_clock")
  bin = Env.get("SATORI_BIN")
  if bin == nil || bin == ""
    bin = System.executable_path
    if bin == ""
      bin = root + "/bits/tungsten-satori/bin/satori"
  mem = Env.get("SATORI_JOB_MEM_MB")
  if mem == nil || mem == ""
    mem = "6144"
  secs = Env.get("SATORI_JOB_SECONDS")
  if secs == nil || secs == ""
    secs = "3600"
  nc_flag = no_cache ? "--no-cache" : ""
  dir = root + "/bits/tungsten-satori/.satori-cache/split-" + ((t0 * ~1000000.0).round % 1000000000).to_s
  File.mkdir_p(dir)
  nfail = 0
  begin
    if no_cache
      p = Process.spawn(["/bin/sh", "-c", "SATORI_ROOT=\"$3\" \"$0\" --no-cache --only 0 \"$1\" > \"$2\" 2>&1", bin, f, dir + "/out.0", root])
      p.wait
    else
      p = Process.spawn(["/bin/sh", "-c", "SATORI_ROOT=\"$3\" \"$0\" --only 0 \"$1\" > \"$2\" 2>&1", bin, f, dir + "/out.0", root])
      p.wait
    skel = split_lines(dir + "/out.0")
    if !skel.include?(SATORI_SPLIT_PROTOCOL)
      << "✗ " + f + ": split worker is incompatible or failed to start; use a matching Satori binary (SATORI_BIN)"
      return 1
    names = []
    indices = []
    registrations = {}
    skel.each -> (l)
      if l.starts_with?("⋯ split ")
        parts = l.split("⋯ split ")[1].split(" ")
        indices.push(parts[0])
        names.push(parts[1])
        if parts.size == 3 && parts[2] == "auto"
          registrations[parts[0]] = parts[1]
    if names.size > 0
      File.write(dir + "/indices", indices.join("\n") + "\n")
      # Fast-exit loop checks child completion every 10 ms for the first 50 ms before entering 250 ms RSS watchdog.
      job = "export SATORI_SPLIT_PREMISES=\"$8\"; out=\"$4/out.$3\"; idx=$(sed -n \"${3}p\" \"$4/indices\"); if test -n \"$7\"; then SATORI_ROOT=\"$5\" \"$0\" \"$7\" --only \"$idx\" \"$1\" > \"$out\" 2>&1 & else SATORI_ROOT=\"$5\" \"$0\" --only \"$idx\" \"$1\" > \"$out\" 2>&1 & fi; pid=$!; "
      job = job + "for _fast in 1 2 3 4 5; do kill -0 $pid 2>/dev/null || break; sleep 0.01; done; t=0; "
      job = job + "while kill -0 $pid 2>/dev/null; do r=$(ps -o rss= -p $pid 2>/dev/null | tr -d ' '); "
      job = job + "if test -n \"$r\" && test \"$r\" -gt $(( $2 * 1024 )); then kill -9 $pid; echo 'satori-split: memory limit' >> \"$out\"; break; fi; "
      job = job + "if test $t -gt $(( $6 * 4 )); then kill -9 $pid; echo 'satori-split: time limit' >> \"$out\"; break; fi; "
      job = job + "sleep 0.25; t=$((t+1)); done; wait $pid"
      drv = "seq 1 \"$1\" | xargs -P \"$2\" -I{} /bin/sh -c \"$3\" \"$4\" \"$5\" \"$6\" {} \"$7\" \"$8\" \"$9\" \"${10}\""
      q = Process.spawn(["/bin/sh", "-c", drv, "sh", names.size.to_s, jobs.to_s, job, bin, f, mem, dir, root, secs, nc_flag])
      q.wait
    blocks = {}
    own = {}
    deps = {}
    failed = {}
    memo = {}
    trusted = {}
    workers = names.size
    k = 0
    while k < names.size
      nm = names[k]
      id = indices[k]
      lines = split_lines(dir + "/out." + (k + 1).to_s)
      # A provisional statement is never eligible on its own. If it shared a
      # goal symbol, replay with the IDs whose proofs and dependencies checked.
      requests = lines.find(-> (line) line.starts_with?("⋯ select split:"))
      if requests != nil && requests.split(" ").any?(-> (tag) trusted.has_key?(tag))
        path = dir + "/trusted"
        File.write(path, trusted.keys.join("\n"))
        replay = Process.spawn(["/bin/sh", "-c", job, bin, f, mem, (k + 1).to_s, dir, root, secs, nc_flag, path])
        replay.wait
        workers += 1
        lines = split_lines(dir + "/out." + (k + 1).to_s)
      b = split_block(lines, indices[k].to_i)
      if b.size == 0 || !b[0].starts_with?("✓ ")
        failed[id] = nm
        if b.size == 0
          tail = []
          lines.each -> (l)
            if l.starts_with?("satori-split:") || l.starts_with?("✗")
              tail.push(l)
          b = ["✗ theorem " + nm + ": its checking process stopped " + tail.join(" ")]
      else
        st = split_tags(b[0])
        own[id] = st[1]
        deps[id] = st[2]
        error = auto_registration_error(split_resolve(id, own, deps, memo, failed, []))
        if error == nil
          trusted["split:" + id] = true
        elsif registrations.has_key?(id)
          failed[id] = nm
          b = ["✗ theorem " + nm + ": " + error]
      blocks[id] = b
      k += 1
    skel.each -> (l)
      if l.starts_with?("⋯ split ")
        id = l.split("⋯ split ")[1].split(" ")[0]
        b = blocks[id]
        if failed.has_key?(id)
          nfail += 1
          b.each -> (x)
            if x.starts_with?("⋯ partial-proof\t")
              note = split_partial_note(x, own, deps, memo, failed)
              if note != nil
                << note
            else
              << x
        else
          st = split_tags(b[0])
          tags = split_resolve(id, own, deps, memo, failed, [])
          line = st[0]
          if tags.size > 0
            line = line + "   \[" + tags.join(", ") + "\]"
          << line
          arr_sub(b, 1, b.size - 1).each -> (x)
            << x
      elsif l.starts_with?("⋯ axioms ")
        st = split_tags(l)
        prefix = "⋯ axioms "
        nm = st[0].slice(prefix.size, st[0].size - prefix.size)
        tags = st[1]
        st[2].each -> (d)
          if failed.has_key?(d) && !tags.include?("uses-failed:" + failed[d])
            tags.push("uses-failed:" + failed[d])
          split_resolve(d, own, deps, memo, failed, []).each -> (t)
            if !tags.include?(t)
              tags.push(t)
        if tags.size == 0
          << nm + " depends only on the foundational kernel"
        else
          << nm + " depends on: " + tags.join(", ")
      elsif l.starts_with?("── ")
        0
      elsif l == SATORI_SPLIT_PROTOCOL
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
    << "── " + f + ": " + status + " — " + info + ", " + ((dt * ~1000.0).round / ~1000.0).to_s + " s wall, " + workers.to_s + " theorem processes, " + jobs.to_s + " at a time"
  ensure
    Process.spawn(["/bin/rm", "-rf", dir]).wait
  nfail
