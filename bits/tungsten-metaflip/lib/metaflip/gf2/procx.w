# Procx: run an argv list as a child process and get its exit status, stdout and stderr.
#
# Tungsten's `capture` returns stdout only, hides the exit status and takes a shell string;
# `system` returns a bare boolean; `Process.spawn` cannot capture anything. The Python tools
# rely on subprocess.run / check_output for all of that, so this is the small layer that
# gives the ports the same three calls:
#
#   Procx.run(argv, ...)           subprocess.run(argv, capture_output=True, text=True)
#   Procx.check_output(argv, ...)  subprocess.check_output(argv, text=True)   (raises ProcError)
#   Procx.succeeds?(argv, ...)     subprocess.run(argv, stdout=DEVNULL, stderr=DEVNULL).returncode == 0
#   Procx.run_all(jobs, limit: n)  ThreadPoolExecutor(n).map(subprocess.run, jobs)
#
# Users in the originals: gf2_record_board.py (`git ls-tree`), verify_gf2_lineage.py (`git show`
# with a returncode test, the native walker with check=True), screen_public_ternary_gf2.py
# (walker with returncode + stdout + stderr), mmc_gf2_replay.py (`git rev-parse`, retrying
# `git show`), search_wide_projection_walks.py and screen_*_children.py (`ruby verify_tensor.rb`),
# tungsten-lang/papers/scripts/pack_arxiv.py (cwd= and DEVNULL); run_all: the ThreadPoolExecutor loops of
# screen_public_ternary_gf2.py walk, iterate.py, ruby_records.py, ruby_finals.py and
# tungsten-lang/papers/scripts/ruby_verify_all.py.
#
# How it works: every argument is single-quoted for /bin/sh and the child runs as
#   { cd DIR && NAME='v' 'prog' 'arg' ; } < /dev/null 2> ERRFILE ; printf '\n<SOH>procx:%s' "$?"
# through `capture`. The status therefore travels after the last marker of the captured text
# and stdout is everything before it, byte for byte. `capture` builds a C string, so a NUL byte
# in the child's stdout ends it and the marker never arrives: ProcResult#status is then nil
# (truncated?) and #out is only the text before the NUL. Binary output belongs in a file:
# `stdout_to:` sends it there and read_file, which is length-based, brings it back. The child's
# stdin is /dev/null. A child killed by a signal reports 128 + signal (Python reports -signal).
#
# TODO(port): core has no spawn-with-capture (Process.spawn cannot redirect, `capture` hides the
# status); a native one would remove the /bin/sh layer and the marker protocol.
#
# Cost: one /bin/sh per call on top of the child (about 7 ms on macOS). `stderr: :capture`
# needs a temporary file, and on macOS the first write of a subprocess to a brand-new file costs
# another ~5 ms; :null and :inherit avoid it, and so does anything that does not need stderr.

use core/process

# Raised by Procx.check_output and by argument validation; carries what a caller needs to log.
+ ProcError < Error
  -> new(@message, @status, @command, @stderr)
  ro :status, :command, :stderr

# What Procx.run returns (subprocess.CompletedProcess without `args`).
+ ProcResult
  -> new(@status, @out, @err)
  ro :status, :out, :err

  # True when the child exited with status 0.
  -> ok?
    @status == 0

  # True when a NUL byte in the child's stdout cut the captured text short before the exit status
  # could arrive (status is nil then). Run the command again with `stdout_to:`.
  -> truncated?
    @status == nil

+ Procx
  # POSIX single-quote quoting: 'it'\''s'. The empty string quotes to ''. A NUL byte cannot
  # travel through a shell command line and is rejected.
  -> .quote(arg)
    text = arg.to_s
    if text.index("\0") != nil
      raise ProcError.new("argument contains a NUL byte", nil, "", "")
    return "''" if text == ""
    "'" + text.gsub("'", "'\\''") + "'"

  # The shell words for one command: `cd DIR && NAME='value' 'prog' 'arg' ...`. `env` is a
  # Hash of String => String added to the child's environment; names must be shell identifiers.
  -> .command(argv, cwd: nil, env: nil)
    if argv.size == 0
      raise ProcError.new("empty command", nil, "", "")
    words = []
    if env != nil
      env.keys.each -> (name)
        raise ProcError.new("invalid environment variable name: " + name.to_s, nil, "", "") unless Procx.identifier?(name.to_s)
        words.push(name.to_s + "=" + Procx.quote(env[name]))
    argv.each -> (arg)
      words.push(Procx.quote(arg))
    line = words.join(" ")
    line = "cd " + Procx.quote(cwd) + " && " + line if cwd != nil
    line

  # subprocess.run: runs `argv`, waits, and returns a ProcResult. Never raises because of the
  # child's exit status.
  #   cwd:       directory to run in
  #   env:       Hash of extra environment variables
  #   stderr:    :capture (ProcResult#err holds it), :null, or :inherit (the parent's stderr)
  #   stdout_to: a file path; stdout goes there (byte-exact, NUL-safe) and ProcResult#out is ""
  -> .run(argv, cwd: nil, env: nil, stderr: :capture, stdout_to: nil)
    command = Procx.command(argv, cwd: cwd, env: env)
    # stderr is redirected before stdout so that a failure to open the stdout file is reported there.
    redirect = " < /dev/null"
    err_path = nil
    if stderr == :capture
      err_path = tempfile_create("procx-", nil)
      raise ProcError.new("cannot create a temporary file for stderr", nil, command, "") if err_path == nil
      redirect += " 2> " + Procx.quote(err_path)
    elsif stderr == :null
      redirect += " 2> /dev/null"
    elsif stderr != :inherit
      raise ProcError.new("stderr must be :capture, :null or :inherit", nil, command, "")
    redirect += " > " + Procx.quote(stdout_to) if stdout_to != nil
    marker = "\n" + 1.chr + "procx:"
    result = nil
    begin
      raw = capture("{ " + command + " ; }" + redirect + " ; printf '" + marker + "%s' \"$?\"")
      err = ""
      if err_path != nil
        text = read_file(err_path)
        err = text if text != nil
      cut = raw.rindex(marker)
      digits = cut == nil ? "" : raw.slice(cut + marker.size, raw.size - cut - marker.size)
      if Procx.digits?(digits)
        result = ProcResult.new(digits.to_i, raw.slice(0, cut), err)
        # the slice is a copy: the captured text (output plus marker) is ours and, with no garbage collector, not
        # freed by anyone else (a `git show` of a large blob would otherwise stay in memory for good)
        ccall("w_value_free_w", raw)
      else
        result = ProcResult.new(nil, raw, err)
    ensure
      file_unlink(err_path) if err_path != nil
    result

  # subprocess.check_output: stdout of a command that must exit 0; ProcError otherwise (its
  # message names the command, the status and the first 400 bytes of stderr). Output with a NUL
  # byte cannot be returned as text and raises too.
  -> .check_output(argv, cwd: nil, env: nil)
    result = Procx.run(argv, cwd: cwd, env: env)
    return result.out if result.ok?
    command = Procx.command(argv, cwd: cwd, env: env)
    if result.truncated?
      raise ProcError.new("stdout contains a NUL byte (use stdout_to:): " + command, nil, command, result.err)
    detail = result.err.strip
    detail = detail.slice(0, 400) if detail.size > 400
    raise ProcError.new("command failed with status " + result.status.to_s + ": " + command + "\n" + detail, result.status, command, result.err)

  # True when the command exits 0; its output is discarded.
  -> .succeeds?(argv, cwd: nil, env: nil)
    Procx.run(argv, cwd: cwd, env: env, stderr: :null).ok?

  # subprocess.run for many commands at once: `jobs` is an Array of argv Arrays, at most `limit`
  # of them run together (Process.spawn under /bin/sh), and the ProcResults come back in the order
  # of `jobs`. cwd: and env: apply to every job. Output and stderr go through temporary files,
  # so unlike run they are NUL-safe. Compiled programs only (Process.spawn).
  -> .run_all(jobs, limit: 4, cwd: nil, env: nil)
    raise ProcError.new("limit must be at least 1", nil, "", "") if limit < 1
    results = jobs.map -> (job)
      nil
    running = []
    started = 0
    begin
      while started < jobs.size || running.size > 0
        while started < jobs.size && running.size < limit
          running.push(Procx.launch(started, jobs[started], cwd, env))
          started += 1
        running = Procx.reap(running, results)
    ensure
      running.each -> (job)
        job[1].kill(9)
        Procx.discard(job)
    results

  # Starts one job of run_all: [index, process, stdout path, stderr path].
  -> .launch(index, argv, cwd, env)
    command = Procx.command(argv, cwd: cwd, env: env)
    out_path = tempfile_create("procx-", nil)
    err_path = tempfile_create("procx-", nil)
    raise ProcError.new("cannot create temporary files", nil, command, "") if out_path == nil || err_path == nil
    line = "{ " + command + " ; } < /dev/null 2> " + Procx.quote(err_path) + " > " + Procx.quote(out_path)
    [index, Process.spawn(["/bin/sh", "-c", line]), out_path, err_path]

  # Waits until at least one running job has finished, stores its ProcResult in `results` and
  # returns the jobs that are still running.
  -> .reap(running, results)
    while true
      still = []
      finished = 0
      running.each -> (job)
        code = job[1].poll
        if code == nil
          still.push(job)
        else
          results[job[0]] = Procx.collect(job, code)
          finished += 1
      return still if finished > 0
      system("sleep 0.01")
    still

  # The ProcResult of a finished run_all job; removes its temporary files. Process#wait reports
  # 256 + signal for a killed child, run reports 128 + signal; this follows run.
  -> .collect(job, code)
    out = read_file(job[2])
    err = read_file(job[3])
    Procx.discard(job)
    ProcResult.new(code >= 256 ? code - 128 : code, out == nil ? "" : out, err == nil ? "" : err)

  # Removes the temporary files of a run_all job.
  -> .discard(job)
    file_unlink(job[2])
    file_unlink(job[3])

  # True for a valid shell variable name ([A-Za-z_][A-Za-z0-9_]*).
  -> .identifier?(name)
    return false if name.size == 0
    bytes = name.bytes
    at = 0
    while at < bytes.size
      byte = bytes[at]
      letter = (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || byte == 95
      digit = byte >= 48 && byte <= 57
      return false unless letter || (digit && at > 0)
      at += 1
    true

  # True for a short non-empty run of ASCII digits (the exit status the shell appends).
  -> .digits?(text)
    return false if text.size == 0 || text.size > 3
    bytes = text.bytes
    at = 0
    while at < bytes.size
      return false unless bytes[at] >= 48 && bytes[at] <= 57
      at += 1
    true
