# rung — running model calls: timeouts, retries, guards and concurrency.
#
# A call is a Hash (see rung_new_call). rung_run_calls runs a batch of them
# to completion: each provider runs at most its `concurrency` calls at once
# (machine-wide for a shared provider such as ollama),
# a call past its timeout gets TERM and, 10 s later, KILL (to its whole
# process group), and a failed call is retried after `retry_wait` seconds up
# to `retries` times unless the failure cannot heal by waiting (not signed
# in, command not found). Nothing outlives the batch: rung waits for every
# child, and on Ctrl-C it kills them all before it exits.
#
# The command is a fixed template from the registry. rung runs it with
# /bin/sh in the call's work dir, stdin from /dev/null, stdout and stderr to
# files; a model's answer is only ever read as text.

RUNG_KILL_GRACE_MS = 10000

# Process-wide state: the calls running now (killed on Ctrl-C or error)
# and whether progress lines are printed.
RUNG_RT = {"running" => [], "quiet" => false, "exhausted" => {}}

-> rung_say(s)
  return nil if RUNG_RT["quiet"]
  << s
  flush()
  nil

# kind: "model" or "integrator". settings: timeout, retries, retry_wait,
# guard, validate ("verdict" for the integrator).
-> rung_new_call(kind, label, entry, dir, settings)
  answer_file = dir + "/answer.md"
  stdout_file = entry["answer"] == "file" ? dir + "/stdout.txt" : answer_file
  call = {
    "kind" => kind,
    "label" => label,
    "entry" => entry,
    "dir" => dir,
    "prompt_file" => dir + "/prompt.md",
    "workdir" => dir + "/work",
    "answer_file" => answer_file,
    "stdout_file" => stdout_file,
    "log_file" => dir + "/log.txt",
    "timeout" => settings["timeout"],
    "retries" => settings["retries"],
    "retry_wait" => settings["retry_wait"],
    "guard" => settings["guard"],
    "validate" => settings["validate"] == nil ? "" : settings["validate"],
    "stage" => settings["stage"],
    "run_dir" => settings["run_dir"],
    "status" => "pending",
    "attempts" => 0,
    "reason" => "",
    "exit" => nil,
    "ms" => 0,
    "not_before" => 0,
    "process" => nil,
    "started" => 0,
    "killed_at" => nil,
    "timed_out" => false,
    "slot" => nil,
    "notes" => []
  }
  call

# The shell script for one attempt (saved as cmd.sh beside the answer).
-> rung_call_script(call)
  entry = call["entry"]
  vars = {
    "prompt_file" => call["prompt_file"],
    "workdir" => call["workdir"],
    "answer_file" => call["answer_file"],
    "timeout" => call["timeout"]
  }
  cmd = rung_render_command(entry, vars)
  inner = "/bin/sh -c " + rung_shq(cmd)
  if !rung_blank?(call["guard"])
    secs = call["timeout"] + 120
    inner = rung_shq(call["guard"]) + " " + entry["guard_mem_mb"].to_s + " " + secs.to_s + " " + inner
  s = "#!/bin/sh\n"
  s = s + "# rung: " + call["kind"] + " call to " + entry["name"] + " (timeout " + call["timeout"].to_s + " s)\n"
  s = s + "cd " + rung_shq(call["workdir"]) + " || exit 97\n"
  s = s + "exec " + inner + " < /dev/null > " + rung_shq(call["stdout_file"]) + " 2> " + rung_shq(call["log_file"]) + "\n"
  s

-> rung_call_meta_path(call)
  call["dir"] + "/meta.json"

# A call that already finished well (a resumed run reuses it).
-> rung_call_done?(call)
  meta = rung_json_read(rung_call_meta_path(call))
  return false if meta == nil || meta["status"] != "ok"
  ans = rung_read(call["answer_file"])
  return false if rung_blank?(ans)
  call["status"] = "ok"
  call["attempts"] = meta["attempts"]
  call["ms"] = meta["ms"]
  call["exit"] = meta["exit"]
  call["reused"] = true
  true

-> rung_start_attempt(call)
  call["attempts"] = call["attempts"] + 1
  n = call["attempts"]
  # keep the previous attempt's output for diagnosis
  if n > 1
    pairs = [["answer_file", "answer"], ["log_file", "log"], ["stdout_file", "stdout"]]
    pairs.each -> (pair)
      p = call[pair[0]]
      if File.exist?(p)
        File.rename(p, call["dir"] + "/attempt-" + (n - 1).to_s + "-" + pair[1] + ".txt")
  rung_make_workdir(call["run_dir"], call["stage"], call["workdir"])
  rung_write(call["dir"] + "/cmd.sh", rung_call_script(call))
  rung_write(call["answer_file"], "") if call["entry"]["answer"] == "file"
  call["timed_out"] = false
  call["killed_at"] = nil
  call["started"] = rung_ms
  call["status"] = "running"
  begin
    call["process"] = Process.spawn(["/bin/sh", call["dir"] + "/cmd.sh"])
  rescue e
    call["process"] = nil
    call["status"] = "failed"
    call["reason"] = "could not start: [e]"
  call

-> rung_tail(path, n)
  t = rung_read(path)
  return "" if t == nil
  return t if t.size <= n
  t.slice(t.size - n, n)

-> rung_has_any?(text, needles)
  needles.each -> (x)
    return true if text.index(x) != nil
  false

# Failure classes, each reported with the CLI's own line as evidence:
#   usage limit   a quota window (weekly, daily, session, credits): waiting a
#                 minute cannot help, so it is not retried, and the model is
#                 skipped for the rest of this run
#   rate limited  a transient 429 / too many requests / overloaded: retried
#   model unavailable  retired or unknown: not retried, skipped for the run
#   not signed in not retried
RUNG_SIGNIN_WORDS = ["not signed in", "not logged in", "please log in", "please sign in", "please run /login", "login required", "unauthorized", "invalid api key", "authentication failed"]
RUNG_QUOTA_WORDS = ["usage limit", "weekly limit", "daily limit", "monthly limit", "session limit", "hourly limit", "hit your limit", "limit reached", "quota", "out of credits", "insufficient credits", "usage credits", "upgrade for higher limits"]
RUNG_RATE_WORDS = ["rate limit", "rate-limit", "ratelimit", "too many requests", "resource_exhausted", "overloaded", "429", "try again later"]
RUNG_GONE_WORDS = ["was retired", "model not found", "no such model", "does not exist", "not_found_error", "unknown model", "invalid model"]
# Lines CLIs print on every run that say nothing about why one failed.
RUNG_NOISE_WORDS = ["doesn't recognize the model", "claude-code:unrecognized_model", "claude_code_auto_compact_window", "error: exit status"]
# Stricter lists for a short answer on exit 0: a CLI that prints its refusal
# as the answer (a real answer may well mention "429" or "quota").
RUNG_SIGNIN_ANSWER_WORDS = ["not signed in", "not logged in", "please log in", "please sign in", "please run /login"]
RUNG_QUOTA_ANSWER_WORDS = ["usage limit", "weekly limit", "daily limit", "monthly limit", "session limit", "hit your limit", "limit reached"]
RUNG_RATE_ANSWER_WORDS = ["rate limit", "too many requests"]

# The first line of text that mentions one of the words, trimmed for a report.
-> rung_evidence(text, words)
  rung_lines(text).each -> (l)
    t = l.strip
    if t != "" && rung_has_any?(t.downcase, words)
      return t.size > 160 ? t.slice(0, 157) + "..." : t
  ""

-> rung_reason(kind, evidence)
  evidence == "" ? kind : kind + ": " + evidence

-> rung_trim_line(t)
  t.size > 160 ? t.slice(0, 157) + "..." : t

# The most telling line of a failed run: an "API Error"/"error" line that is
# not known noise, else the first line that is not noise.
-> rung_error_line(text)
  ls = rung_lines(text)
  ls.each -> (l)
    t = l.strip
    low = t.downcase
    if low.index("api error") != nil && !rung_has_any?(low, RUNG_NOISE_WORDS)
      return rung_trim_line(t)
  ls.each -> (l)
    t = l.strip
    low = t.downcase
    if low.index("error") != nil && !rung_has_any?(low, RUNG_NOISE_WORDS)
      return rung_trim_line(t)
  ls.each -> (l)
    t = l.strip
    if t != "" && !rung_has_any?(t.downcase, RUNG_NOISE_WORDS)
      return rung_trim_line(t)
  ""

# nil when the attempt produced a usable answer, else why not.
-> rung_attempt_failure(call, code)
  log = rung_tail(call["log_file"], 6000)
  if call["stdout_file"] != call["answer_file"]
    log = log + "\n" + rung_tail(call["stdout_file"], 3000)
  answer = rung_read(call["answer_file"])
  answer = "" if answer == nil
  # a failing CLI often prints its complaint on stdout (= the answer file)
  if code != 0
    log = rung_tail(call["answer_file"], 2000) + "\n" + log
  low = log.downcase
  short = answer.size < 600 ? answer : ""
  short_low = short.downcase
  if call["timed_out"]
    return "timed out after " + call["timeout"].to_s + " s"
  if low.index("guard: killed (rss") != nil
    return "killed by the memory guard"
  if low.index("guard: killed (wall") != nil
    return "killed by the time guard"
  return "work dir missing" if code == 97
  return "command not found" if code == 127
  if code != 0
    return rung_reason("usage limit", rung_evidence(log, RUNG_QUOTA_WORDS)) if rung_has_any?(low, RUNG_QUOTA_WORDS)
    return rung_reason("not signed in", rung_evidence(log, RUNG_SIGNIN_WORDS)) if rung_has_any?(low, RUNG_SIGNIN_WORDS)
    return rung_reason("model unavailable", rung_evidence(log, RUNG_GONE_WORDS)) if rung_has_any?(low, RUNG_GONE_WORDS)
    return rung_reason("rate limited", rung_evidence(log, RUNG_RATE_WORDS)) if rung_has_any?(low, RUNG_RATE_WORDS)
    line = rung_error_line(log)
    return "exit code " + code.to_s + (line == "" ? "" : ": " + line)
  return rung_reason("usage limit", rung_evidence(short, RUNG_QUOTA_ANSWER_WORDS)) if rung_has_any?(short_low, RUNG_QUOTA_ANSWER_WORDS)
  return rung_reason("not signed in", rung_evidence(short, RUNG_SIGNIN_ANSWER_WORDS)) if rung_has_any?(short_low, RUNG_SIGNIN_ANSWER_WORDS)
  return rung_reason("rate limited", rung_evidence(short, RUNG_RATE_ANSWER_WORDS)) if rung_has_any?(short_low, RUNG_RATE_ANSWER_WORDS)
  return "empty answer" if rung_blank?(answer)
  if call["validate"] == "verdict" && answer.index("</rung-verdict>") == nil
    return "no <rung-verdict> block in the answer"
  nil

# The class of a failure reason: usage-limit, unavailable, rate-limited,
# signin, timeout, missing or error.
-> rung_failure_class(reason)
  return "usage-limit" if reason.starts_with?("usage limit")
  return "unavailable" if reason.starts_with?("model unavailable")
  return "rate-limited" if reason.starts_with?("rate limited")
  return "signin" if reason.starts_with?("not signed in")
  return "timeout" if reason.starts_with?("timed out")
  return "missing" if reason == "command not found" || reason == "work dir missing" || reason.starts_with?("could not start")
  "error"

-> rung_retryable?(reason)
  c = rung_failure_class(reason)
  !(c == "usage-limit" || c == "unavailable" || c == "signin" || c == "missing")

-> rung_write_call_meta(call)
  meta = {
    "kind" => call["kind"],
    "model" => call["entry"]["name"],
    "provider" => call["entry"]["provider"],
    "status" => call["status"],
    "reason" => call["reason"],
    "failure" => call["status"] == "ok" ? "" : rung_failure_class(call["reason"]),
    "attempts" => call["attempts"],
    "exit" => call["exit"],
    "ms" => call["ms"],
    "timeout" => call["timeout"],
    "guarded" => !rung_blank?(call["guard"]),
    "answer_bytes" => rung_file_size(call["answer_file"]),
    "finished" => rung_timestamp
  }
  rung_json_write(rung_call_meta_path(call), meta)

-> rung_finish_attempt(call, code, now)
  rung_release_slot(call)
  call["exit"] = code
  call["ms"] = call["ms"] + (now - call["started"])
  call["process"] = nil
  why = rung_attempt_failure(call, code)
  if why == nil
    call["status"] = "ok"
    call["reason"] = ""
    rung_write_call_meta(call)
    return "done"
  call["reason"] = why
  if rung_retryable?(why) && call["attempts"] <= call["retries"]
    call["status"] = "pending"
    call["not_before"] = now + call["retry_wait"] * 1000
    call["notes"].push("attempt " + call["attempts"].to_s + ": " + why)
    return "retry"
  call["status"] = "failed"
  rung_write_call_meta(call)
  "done"

# ---- machine-wide slots for shared providers ------------------------------------------
#
# A shared provider (ollama by default: its cap is an account limit) counts
# calls across every rung process on the machine. Each running call holds a
# slot directory, ~/.cache/rung/slots/<provider>.<i> (or $RUNG_SLOTS/...):
# mkdir is atomic, the owner file names the holding pid, and a slot whose
# owner is gone is reclaimed.

-> rung_slot_root
  env = Env.get("RUNG_SLOTS")
  return env if !rung_blank?(env)
  rung_home + "/.cache/rung/slots"

-> rung_try_mkdir(dir)
  Process.spawn(["/bin/mkdir", dir]).wait == 0

-> rung_take_slot(provider, cap, label)
  root = rung_slot_root
  rung_mkdir(root)
  i = 1
  while i <= cap
    dir = root + "/" + rung_slug(provider) + "." + i.to_s
    got = rung_try_mkdir(dir)
    if !got
      owner = rung_read(dir + "/owner")
      if owner != nil
        pid = rung_first_word(owner)
        if !rung_pid_alive?(pid)
          rung_rm_rf(dir)
          got = rung_try_mkdir(dir)
    if got
      rung_write(dir + "/owner", rung_my_pid + " " + label + "\n")
      return dir
    i += 1
  nil

-> rung_release_slot(call)
  slot = call["slot"]
  if slot != nil
    rung_rm_rf(slot)
    call["slot"] = nil
  nil

-> rung_active_for(running, provider)
  n = 0
  running.each -> (c)
    n += 1 if c["entry"]["provider"] == provider
  n

# Stop every running child: TERM the groups, wait up to the grace period,
# then KILL and reap. Used on Ctrl-C and on errors.
-> rung_kill_all(running)
  running.each -> (c)
    p = c["process"]
    p.kill(15) if p != nil
  t0 = rung_ms
  while rung_ms - t0 < 5000
    alive = 0
    running.each -> (c)
      p = c["process"]
      alive += 1 if p != nil && p.poll == nil
    break if alive == 0
    rung_sleep_ms(100)
  running.each -> (c)
    p = c["process"]
    if p != nil && p.poll == nil
      p.kill(9)
      p.wait
    c["process"] = nil
    rung_release_slot(c)
  nil

-> rung_interrupted?
  ccall("__w_interrupted") != 0

# Run calls to completion. Returns the calls (status "ok" or "failed").
# Raises "interrupted" after killing every child when Ctrl-C arrives.
-> rung_run_calls(calls, poll_ms = 200)
  pending = []
  calls.each -> (c)
    if c["status"] == "failed"
      rung_say("    " + c["label"] + ": " + c["reason"])
    elsif c["status"] == "ok" || rung_call_done?(c)
      rung_say("    " + c["label"] + ": reused the finished answer")
    else
      pending.push(c)
  running = []
  RUNG_RT["running"] = running
  while pending.size > 0 || running.size > 0
    if rung_interrupted?
      rung_kill_all(running)
      RUNG_RT["running"] = []
      raise "interrupted"
    now = rung_ms
    still = []
    pending.each -> (c)
      cap = c["entry"]["concurrency"]
      prov = c["entry"]["provider"]
      ready = c["not_before"] <= now && rung_active_for(running, prov) < cap
      if ready && c["entry"]["shared"] == true
        c["slot"] = rung_take_slot(prov, cap, c["label"])
        if c["slot"] == nil
          ready = false
          c["not_before"] = now + 1000
          if c["waiting"] != true
            rung_say("    " + c["label"] + ": waiting for a free " + prov + " slot (" + cap.to_s + " at once, machine-wide)")
            c["waiting"] = true
      if ready
        c["waiting"] = false
        rung_start_attempt(c)
        if c["status"] == "failed"
          rung_release_slot(c)
          rung_write_call_meta(c)
          rung_say("    " + c["label"] + ": " + c["reason"])
        else
          extra = c["attempts"] > 1 ? " (attempt " + c["attempts"].to_s + ")" : ""
          rung_say("    " + c["label"] + ": started" + extra)
          running.push(c)
      else
        still.push(c)
    pending = still
    keep = []
    running.each -> (c)
      r = c["process"].poll
      now = rung_ms
      if r == nil
        if c["killed_at"] == nil && now - c["started"] > c["timeout"] * 1000
          c["timed_out"] = true
          c["killed_at"] = now
          c["process"].kill(15)
        elsif c["killed_at"] != nil && now - c["killed_at"] > RUNG_KILL_GRACE_MS
          c["process"].kill(9)
        keep.push(c)
      else
        what = rung_finish_attempt(c, r, now)
        if what == "retry"
          rung_say("    " + c["label"] + ": " + c["reason"] + "; retry " + c["attempts"].to_s + "/" + c["retries"].to_s + " in " + c["retry_wait"].to_s + " s")
          pending.push(c)
        elsif c["status"] == "ok"
          rung_say("    " + c["label"] + ": ok (" + rung_secs(c["ms"]) + ")")
        else
          rung_say("    " + c["label"] + ": failed, " + c["reason"] + " (" + c["attempts"].to_s + " attempt" + (c["attempts"] == 1 ? "" : "s") + ")")
    running = keep
    RUNG_RT["running"] = running
    if pending.size > 0 || running.size > 0
      rung_sleep_ms(poll_ms)
  RUNG_RT["running"] = []
  calls

# ---- light checks (rung models / rung check) ----------------------------------------

# Run shell checks concurrently, each with a time limit; returns exit codes
# (nil when it timed out). The commands are registry text, never model text.
-> rung_run_checks(cmds, limit_ms)
  procs = []
  cmds.each -> (c)
    if rung_blank?(c)
      procs.push(nil)
    else
      procs.push(Process.spawn(["/bin/sh", "-c", "exec >/dev/null 2>&1 </dev/null; " + c]))
  codes = []
  procs.each -> (p)
    codes.push(nil)
  t0 = rung_ms
  done = false
  while !done
    done = true
    i = 0
    while i < procs.size
      p = procs[i]
      if p != nil && codes[i] == nil
        r = p.poll
        if r == nil
          done = false
        else
          codes[i] = r
      i += 1
    if !done
      if rung_ms - t0 > limit_ms
        procs.each -> (p)
          if p != nil && p.poll == nil
            p.kill(9)
            p.wait
        done = true
      else
        rung_sleep_ms(50)
  codes

-> rung_installed?(bin)
  return false if rung_blank?(bin)
  Process.spawn(["/bin/sh", "-c", "command -v \"$1\" >/dev/null 2>&1", "sh", rung_expand_home(bin)]).wait == 0
