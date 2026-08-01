# The execution engine behind /api/check and /api/run — in Tungsten.
#
# Compiles a submitted program, optionally runs it with the sandbox gate
# latched, and returns the response document as a Hash the caller JSON-encodes.
#
#   ApiExec.check(source)   -> diagnostics only; never executes
#   ApiExec.run(source)     -> compile, then run sandboxed
#
# Two deliberate choices:
#
# * `check` uses the REAL compiler, not `tungsten -c`. `-c` runs the stage-0
#   parser, which rejects valid source the native compiler accepts (a typed
#   signature such as `fn add(a ## i64) ## i64` reports a bogus syntax error).
#   Telling an agent its correct program is broken is worse than being slow, so
#   check compiles to a throwaway path and discards the binary.
#
# * compile and run are SEPARATE spawns with SEPARATE deadlines. Going through
#   one `tungsten sandbox` process would force a single timeout covering both,
#   handing a runaway program the whole compile budget before it is killed.
#
# This bounds CPU time and output size, and the sandbox bounds reach. It is NOT
# a complete jail: ccall can call any linked symbol, and nothing here caps
# memory or stops a fork bomb. See services/api/README.md.
#
# Compiled programs only: Process and File externs are not in the interpreter's
# ccall whitelist.

+ ApiExec
  -> .max_source_bytes
    262144

  -> .max_output_bytes
    65536

  -> .compile_timeout_ms
    ms = env("TUNGSTEN_API_COMPILE_TIMEOUT_MS")
    return ms.to_i if ms != nil && ms != ""
    60000

  -> .run_timeout_ms
    ms = env("TUNGSTEN_API_RUN_TIMEOUT_MS")
    return ms.to_i if ms != nil && ms != ""
    10000

  # Locate the toolchain. TUNGSTEN_ROOT is exported by bin/tungsten, but a
  # binary launched directly (the spec harness runs compiled specs itself) does
  # not inherit it — so fall back to walking up from the working directory for a
  # tree that has bin/tungsten, then to the conventional install.
  -> .tungsten_root
    root = env("TUNGSTEN_ROOT")
    return root if root != nil && root != "" && File.exist?(root + "/bin/tungsten")

    candidates = []
    candidates.push(".")
    candidates.push("..")
    candidates.push("../..")
    candidates.push("../../..")
    found = nil
    candidates.each -> (dir)
      if found == nil
        abs = File.expand_path(dir)
        found = abs if File.exist?(abs + "/bin/tungsten")
    return found if found != nil

    home = env("HOME")
    return home + "/.tungsten" if home != nil && home != ""
    "."

  -> .version
    v = env("TUNGSTEN_VERSION")
    if v == nil || v == ""
      return "dev"
    v

  # Spawn argv under a shell with stdout and stderr redirected to separate
  # files, so the two streams are never interleaved. Polls until the deadline
  # and kills the process group on expiry.
  #
  # Returns {exit_code:, stdout:, stderr:, timed_out:, elapsed_ms:}.
  -> .spawn_captured(command, out_path, err_path, timeout_ms)
    argv = []
    argv.push("/bin/sh")
    argv.push("-c")
    # The braces matter: without them the redirection binds to the last
    # statement of `command` instead of the whole thing.
    argv.push("{ " + command + " ; } > '" + out_path + "' 2> '" + err_path + "'")

    started = clock_ms
    proc = Process.spawn(argv)
    status = nil
    timed_out = false
    while true
      status = proc.poll
      break unless status == nil
      if clock_ms - started >= timeout_ms
        proc.kill(9)
        proc.wait
        timed_out = true
        break
      sleep(0.005)
    elapsed = clock_ms - started

    code = status
    if timed_out
      code = -9
    elsif code == nil
      code = -1

    {
      exit_code: code,
      stdout: ApiExec.slurp(out_path),
      stderr: ApiExec.slurp(err_path),
      timed_out: timed_out,
      elapsed_ms: elapsed
    }

  # A capture file is absent when the child produced nothing on that stream.
  -> .slurp(path)
    text = File.read(path)
    return "" if text == nil
    text

  -> .clamp(text)
    return "" if text == nil
    return text if text.size() <= ApiExec.max_output_bytes
    text.slice(0, ApiExec.max_output_bytes) + "\n… output truncated …\n"

  -> .truncated?(text)
    return false if text == nil
    text.size() > ApiExec.max_output_bytes

  # Strip server-side paths and backend noise out of caller-visible text. The
  # source arrives as a temp file, so raw compiler output would hand back
  # absolute server paths; callers should see only the filename they submitted.
  -> .sanitize(text, source_path, build_dir)
    return "" if text == nil || text == ""
    out = text.gsub(source_path, "program.w")
    out = out.gsub(build_dir, "<build>")
    lines = out.split("\n")
    kept = []
    lines.each -> (line)
      unless line.include?("clang: warning: argument unused during compilation")
        kept.push(line)
    kept.join("\n")

  # --- diagnostics -----------------------------------------------------------
  #
  # Compiler and runtime messages span several lines: a `error: message` header,
  # then a `--> file:line:col` location, then a source excerpt, and sometimes an
  # `explain:` code. Location and code attach to the diagnostic above them.
  #
  # The runtime has TWO fatal prefixes and both mean "the program died": an
  # uncaught `raise` prints "unhandled exception: MSG", while a bad dispatch
  # prints "runtime error: MSG". Missing either would report a crashed program
  # as a clean non-zero exit.
  -> .parse_diagnostics(text)
    diagnostics = []
    return diagnostics if text == nil || text == ""
    text.split("\n").each -> (raw)
      line = raw.strip
      header = ApiExec.diagnostic_header(line)
      if header != nil
        diagnostics.push(header)
      elsif diagnostics.size() > 0
        current = diagnostics[diagnostics.size() - 1]
        ApiExec.attach_location(current, line)
        ApiExec.attach_code(current, line)
    diagnostics

  # Returns a fresh diagnostic Hash when `line` opens one, else nil.
  -> .diagnostic_header(line)
    severity = nil
    if line.starts_with?("runtime error:")
      severity = "runtime error"
    elsif line.starts_with?("unhandled exception:")
      severity = "unhandled exception"
    elsif line.starts_with?("error:")
      severity = "error"
    elsif line.starts_with?("warning:")
      severity = "warning"
    return nil if severity == nil

    message = line.slice(severity.size() + 1, line.size()).strip
    fatal = severity == "runtime error" || severity == "unhandled exception"
    {
      severity: severity == "warning" ? "warning" : "error",
      runtime: fatal,
      exception: severity == "unhandled exception",
      type: fatal ? ApiExec.exception_type(message) : nil,
      message: message,
      file: nil,
      line: nil,
      column: nil,
      code: nil
    }

  # "TypeError: no implicit conversion …" -> "TypeError". Only a leading
  # capitalized Error/Exception word counts as a type.
  -> .exception_type(message)
    idx = message.index(":")
    return nil if idx == nil || idx <= 0
    word = message.slice(0, idx)
    return nil if word.include?(" ")
    return word if word.ends_with?("Error") || word.ends_with?("Exception")
    nil

  # `  --> file:line:col`
  -> .attach_location(diag, line)
    return nil unless diag[:line] == nil
    return nil unless line.starts_with?("-->")
    rest = line.slice(3, line.size()).strip
    parts = rest.split(":")
    return nil if parts.size() < 3
    diag[:file] = ApiExec.basename(parts[0])
    diag[:line] = parts[1].to_i
    diag[:column] = parts[2].to_i

  # `explain: tungsten --explain E_LEX_UNEXPECTED_CHAR`
  -> .attach_code(diag, line)
    return nil unless diag[:code] == nil
    marker = "--explain "
    idx = line.index(marker)
    return nil if idx == nil
    diag[:code] = line.slice(idx + marker.size(), line.size()).strip

  -> .basename(path)
    idx = path.rindex("/")
    return path if idx == nil
    path.slice(idx + 1, path.size())

  # --- outcome ---------------------------------------------------------------
  #
  # Summarize how a run ended so a caller never parses stderr. `raised`
  # separates "the program threw" from "the program chose a non-zero exit":
  # `exit 3` and an uncaught raise both leave a non-zero code, and only one is
  # a crash.
  -> .classify(diagnostics, exit_code, timed_out)
    fatal = nil
    diagnostics.each -> (d)
      fatal = d if fatal == nil && d[:runtime] == true
    raised = fatal != nil && exit_code != 0

    exception = nil
    if raised
      exception = {
        type: fatal[:type],
        message: fatal[:message],
        file: fatal[:file],
        line: fatal[:line],
        column: fatal[:column],
        # An uncaught `raise` versus a fatal runtime fault (bad dispatch, bad
        # operands). The latter is NOT catchable by begin/rescue.
        uncaught_raise: fatal[:exception] == true
      }

    outcome = "ok"
    if timed_out
      outcome = "timeout"
    elsif raised
      outcome = "raised"
    elsif exit_code != 0
      outcome = "exit"

    {outcome: outcome, raised: raised, exception: exception}

  # Every key is present in every response, so a caller never probes for
  # missing fields.
  -> .base_document(mode)
    {
      ok: false,
      engine: "compiled",
      version: ApiExec.version,
      mode: mode,
      outcome: "ok",
      raised: false,
      exception: nil,
      stdout: "",
      stderr: "",
      exit_code: nil,
      diagnostics: [],
      compile_ms: 0,
      run_ms: 0,
      duration_ms: 0,
      timed_out: false,
      truncated: false,
      compiled: false,
      sandbox: {attempts: 0, log: []}
    }

  # The sandbox writes one JSON object per gated attempt.
  -> .read_sandbox_log(path)
    entries = []
    text = File.read(path)
    return entries if text == nil || text == ""
    text.split("\n").each -> (line)
      trimmed = line.strip
      unless trimmed == ""
        parsed = JSON.parse(trimmed)
        entries.push(parsed == nil ? {raw: trimmed} : parsed)
    entries

  -> .check(source)
    ApiExec.execute(source, "check")

  -> .run(source)
    ApiExec.execute(source, "run")

  -> .execute(source, mode)
    started = clock_ms
    doc = ApiExec.base_document(mode)

    if source == nil || source == ""
      doc[:error] = "source is empty"
      doc[:outcome] = "compile_error"
      return doc
    if source.size() > ApiExec.max_source_bytes
      doc[:error] = "source exceeds " + ApiExec.max_source_bytes.to_s + " bytes"
      doc[:outcome] = "compile_error"
      return doc

    # Per-request scratch dir. The source is always named program.w so
    # diagnostics read as a stable filename rather than a server temp path.
    work = ccall("__w_mkdtemp", "tungsten-api")
    source_path = work + "/program.w"
    binary = work + "/program"
    out_path = work + "/stdout.txt"
    err_path = work + "/stderr.txt"
    File.write(source_path, source)

    tungsten = ApiExec.tungsten_root + "/bin/tungsten"
    compile_cmd = "'" + tungsten + "' compile '" + source_path + "' --out '" + binary + "' --no-lto"
    compiled = ApiExec.spawn_captured(compile_cmd, out_path, err_path, ApiExec.compile_timeout_ms)

    cerr = ApiExec.sanitize(compiled[:stderr], source_path, work)
    cout = ApiExec.sanitize(compiled[:stdout], source_path, work)
    doc[:compile_ms] = compiled[:elapsed_ms]

    compile_ok = compiled[:exit_code] == 0 && compiled[:timed_out] == false && File.exist?(binary)

    if mode == "check"
      # Nothing executed, so there is no program output: the diagnostics ARE
      # the result. On success both streams stay empty rather than echoing
      # "Built <path>".
      doc[:ok] = compile_ok
      doc[:compiled] = compile_ok
      doc[:exit_code] = compiled[:exit_code]
      doc[:diagnostics] = ApiExec.parse_diagnostics(cerr + "\n" + cout)
      doc[:timed_out] = compiled[:timed_out]
      doc[:stderr] = compile_ok ? "" : ApiExec.clamp(cerr)
      doc[:truncated] = compile_ok ? false : ApiExec.truncated?(cerr)
      if compiled[:timed_out]
        doc[:outcome] = "timeout"
        doc[:error] = "compile exceeded " + ApiExec.compile_timeout_ms.to_s + "ms"
      elsif compile_ok == false
        doc[:outcome] = "compile_error"
      doc[:duration_ms] = clock_ms - started
      return doc

    unless compile_ok
      doc[:exit_code] = compiled[:exit_code]
      doc[:diagnostics] = ApiExec.parse_diagnostics(cerr + "\n" + cout)
      doc[:timed_out] = compiled[:timed_out]
      doc[:stderr] = ApiExec.clamp(cerr)
      doc[:truncated] = ApiExec.truncated?(cerr)
      if compiled[:timed_out]
        doc[:outcome] = "timeout"
        doc[:error] = "compile exceeded " + ApiExec.compile_timeout_ms.to_s + "ms"
      else
        doc[:outcome] = "compile_error"
      doc[:duration_ms] = clock_ms - started
      return doc

    # macOS refuses to launch a freshly linked binary unsigned.
    # macOS refuses to launch a freshly linked binary unsigned. Attempted
    # unconditionally and allowed to fail: on Linux `codesign` is simply absent,
    # which is why the failure is swallowed rather than platform-detected.
    OS.system("codesign --force -s - '" + binary + "' >/dev/null 2>&1 || true")

    # Latch the gate for the child and send the attempt log to its own file, so
    # it never interleaves with the program's stderr.
    log_path = work + "/sandbox.jsonl"
    run_cmd = "TUNGSTEN_SANDBOX=1 TUNGSTEN_SANDBOX_LOG='" + log_path + "' '" + binary + "'"
    ran = ApiExec.spawn_captured(run_cmd, out_path, err_path, ApiExec.run_timeout_ms)

    rerr = ApiExec.sanitize(ran[:stderr], source_path, work)
    rout = ApiExec.sanitize(ran[:stdout], source_path, work)
    diagnostics = ApiExec.parse_diagnostics(rerr)
    verdict = ApiExec.classify(diagnostics, ran[:exit_code], ran[:timed_out])
    attempts = ApiExec.read_sandbox_log(log_path)

    doc[:ok] = ran[:exit_code] == 0 && ran[:timed_out] == false
    doc[:compiled] = true
    doc[:outcome] = verdict[:outcome]
    doc[:raised] = verdict[:raised]
    doc[:exception] = verdict[:exception]
    doc[:exit_code] = ran[:exit_code]
    doc[:stdout] = ApiExec.clamp(rout)
    doc[:stderr] = ApiExec.clamp(rerr)
    doc[:diagnostics] = diagnostics
    doc[:run_ms] = ran[:elapsed_ms]
    doc[:timed_out] = ran[:timed_out]
    doc[:truncated] = ApiExec.truncated?(rout) || ApiExec.truncated?(rerr)
    doc[:sandbox] = {attempts: attempts.size(), log: attempts}
    if ran[:timed_out]
      doc[:error] = "execution exceeded " + ApiExec.run_timeout_ms.to_s + "ms"
    doc[:duration_ms] = clock_ms - started
    doc
