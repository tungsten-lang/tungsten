# rung — the ladder: run directories, steps, integration, plateau, resume,
# and the report.
#
# RUN/
#   rung.json            the frozen plan: ladder, integrator, resolved commands,
#                        timeouts, retries, guard, staged names
#   task.md              the task (the prompt file's body)
#   stage/               read-only master copies of the staged files
#   state.md             the current integrated state
#   status.json          running / finished / interrupted, and why it stopped
#   log.md               one line per finished step
#   report.md            final state, step log, credited improvements
#   steps/rRR-sSS-<models>/
#     calls/<model>/     prompt.md, work/ (copies), cmd.sh, answer.md, log.txt, meta.json
#     integrate/         the integrator's prompt.md, work/, cmd.sh, answer.md, log.txt, meta.json
#     verdict.md         the integrator's verdict block, as parsed
#     state.md           the state after this step
#     step.json          the step's record; its presence marks the step done
#
# A step is one entry of the ladder: a model, or a parallel group
# (`a | b | c`). Every member answers the same state; then ONE integrator
# call merges all of the step's answers together and credits the ones that
# contributed. A round runs every step once. The ladder stops after a round
# in which no step improved the state (a plateau), when every model or the
# integrator failed for a whole round, or at max_rounds (0 = no cap).

-> rung_round_dir_name(round, slot, group)
  label = ""
  group.each -> (m)
    label = label == "" ? rung_slug(m) : label + "+" + rung_slug(m)
  label = label.slice(0, 60) if label.size > 60
  "r" + rung_two(round) + "-s" + rung_two(slot) + "-" + label

-> rung_step_dir(run_dir, round, slot, group)
  run_dir + "/steps/" + rung_round_dir_name(round, slot, group)

-> rung_group_text(group)
  group.size == 1 ? group[0] : "(" + group.join(" | ") + ")"

-> rung_ladder_arrow(ladder)
  parts = []
  ladder.each -> (g)
    parts.push(rung_group_text(g))
  parts.join(" → ")

# ---- settings -------------------------------------------------------------------------

-> rung_opt(opts, key)
  return nil if opts == nil
  v = opts[key]
  return nil if v == nil
  return nil if v.is_a?(String) && v.strip == ""
  v

-> rung_list_value(v)
  return [] if v == nil
  return v if v.is_a?(Array)
  s = v.to_s.strip
  return [] if s == ""
  out = []
  s.split(",").each -> (x)
    out.push(x.strip) unless x.strip == ""
  out

# Build a new run directory from a prompt file. opts (from the CLI):
# models, integrator, max_rounds, timeout, out, config, no_guard.
-> rung_create_run(prompt_path, opts)
  path = rung_abs(prompt_path)
  raise "prompt file not found: [path]" unless File.file?(path)
  pf = rung_parse_prompt_file(File.read(path))
  front = pf["front"]
  task = pf["body"]
  raise "the prompt file has no task (its body is empty)" if rung_blank?(task)
  bad = rung_unknown_front_keys(front)
  if bad.size > 0
    bad_text = bad.join(", ")
    known_text = RUNG_FRONT_KEYS.join(", ")
    raise "unknown front-matter keys: [bad_text] (known: [known_text])"
  loaded = rung_load_registry(rung_opt(opts, "config"))
  reg = loaded["registry"]
  spec = rung_opt(opts, "models")
  spec = front["models"] if spec == nil
  spec = rung_default(reg, "models") if spec == nil
  ladder = rung_parse_ladder(spec)
  raise "no models to run" if ladder.size == 0
  integrator = rung_opt(opts, "integrator")
  integrator = front["integrator"] if integrator == nil
  integrator = rung_default(reg, "integrator") if integrator == nil
  integrator = integrator.to_s.strip
  timeout = rung_opt(opts, "timeout")
  timeout = front["timeout"] if timeout == nil
  timeout = timeout == nil ? nil : rung_int(timeout, "timeout")
  itimeout = front["integrator_timeout"]
  itimeout = itimeout == nil ? timeout : rung_int(itimeout, "integrator_timeout")
  mem = front["guard_mem_mb"] == nil ? nil : rung_int(front["guard_mem_mb"], "guard_mem_mb")
  entries = {}
  rung_ladder_models(ladder).each -> (name)
    e = rung_resolve_model(reg, name)
    e["timeout"] = timeout if timeout != nil
    e["guard_mem_mb"] = mem if mem != nil
    entries[name] = e
  ientry = rung_resolve_model(reg, integrator)
  ientry["timeout"] = itimeout if itimeout != nil
  ientry["guard_mem_mb"] = mem if mem != nil
  max_rounds = rung_opt(opts, "max_rounds")
  max_rounds = front["max_rounds"] if max_rounds == nil
  max_rounds = rung_default(reg, "max_rounds") if max_rounds == nil
  max_rounds = rung_int(max_rounds, "max_rounds")
  retries = front["retries"] == nil ? rung_default(reg, "retries") : front["retries"]
  retry_wait = front["retry_wait"] == nil ? rung_default(reg, "retry_wait") : front["retry_wait"]
  guard = rung_guard_path(reg, front, rung_opt(opts, "no_guard") == true)
  patterns = rung_list_value(front["stage"])
  rung_list_value(front["files"]).each -> (p)
    patterns.push(p)
  base = rung_dirname(path)
  items = rung_resolve_stage(base, patterns, rung_int(rung_default(reg, "stage_max_files"), "stage_max_files"), rung_int(rung_default(reg, "stage_max_bytes"), "stage_max_bytes"))
  run_dir = rung_opt(opts, "out")
  if run_dir == nil
    run_dir = base + "/" + rung_stem(path) + ".rung/" + rung_stamp_compact
  run_dir = rung_abs(run_dir)
  if File.directory?(run_dir) && rung_children(run_dir).size > 0
    raise "run directory already exists and is not empty: [run_dir] (continue it with: rung --resume [run_dir])"
  rung_mkdir(run_dir)
  rung_stage_into(items, run_dir + "/stage")
  rels = []
  items.each -> (it)
    rels.push(it["rel"])
  title = front["title"] == nil ? rung_task_title(task, rung_stem(path)) : front["title"]
  rung_write(run_dir + "/task.md", task)
  rung_write(run_dir + "/state.md", rung_initial_state(task))
  manifest = {
    "rung_version" => RUNG_VERSION,
    "created" => rung_timestamp,
    "prompt_file" => path,
    "title" => title,
    "ladder" => ladder,
    "integrator" => integrator,
    "entries" => entries,
    "integrator_entry" => ientry,
    "max_rounds" => max_rounds,
    "retries" => rung_int(retries, "retries"),
    "retry_wait" => rung_int(retry_wait, "retry_wait"),
    "guard" => guard,
    "deliverable" => front["deliverable"] == nil ? "" : front["deliverable"],
    "staged" => rels,
    "config" => loaded["loaded"] ? loaded["path"] : ""
  }
  rung_json_write(run_dir + "/rung.json", manifest)
  rung_json_write(run_dir + "/status.json", {"state" => "created", "updated" => rung_timestamp})
  run_dir

-> rung_initial_state(task)
  "# State\n\nNo answer has been accepted yet. The task:\n\n" + task.strip + "\n"

-> rung_load_manifest(run_dir)
  m = rung_json_read(run_dir + "/rung.json")
  raise "not a rung run directory (no readable rung.json): [run_dir]" if m == nil
  m

-> rung_call_settings(m, run_dir, entry, kind)
  settings = {
    "timeout" => entry["timeout"],
    "retries" => m["retries"],
    "retry_wait" => m["retry_wait"],
    "guard" => m["guard"],
    "validate" => kind == "integrator" ? "verdict" : "",
    "stage" => m["staged"],
    "run_dir" => run_dir
  }
  settings

-> rung_ctx(m, task, state, round, slot)
  ctx = {"task" => task, "deliverable" => m["deliverable"], "state" => state, "round" => round, "step" => slot, "rels" => m["staged"]}
  ctx

# The model calls of one step (prompts written unless a call already finished).
-> rung_step_calls(m, run_dir, sdir, task, state, round, slot, group)
  calls = []
  prompt = rung_model_prompt(rung_ctx(m, task, state, round, slot))
  group.each -> (name)
    entry = m["entries"][name]
    c = rung_new_call("model", name, entry, sdir + "/calls/" + rung_slug(name), rung_call_settings(m, run_dir, entry, "model"))
    spent = RUNG_RT["exhausted"][name]
    if rung_call_done?(c)
      0
    elsif spent != nil
      # a usage window does not reset within a run, nor does a retired
      # model come back: do not call it again
      c["status"] = "failed"
      head = spent.starts_with?("usage limit") ? "usage limit" : "model unavailable"
      c["reason"] = head + " (earlier in this run)" + spent.slice(head.size, spent.size - head.size)
    else
      rung_write(c["prompt_file"], prompt)
    calls.push(c)
  calls

# ---- one step ---------------------------------------------------------------------------

-> rung_run_step(m, run_dir, sdir, task, state, round, slot, group, step_no)
  t0 = rung_ms
  rung_say("  step " + slot.to_s + "/" + m["ladder"].size.to_s + ": " + rung_group_text(group))
  calls = rung_step_calls(m, run_dir, sdir, task, state, round, slot, group)
  rung_run_calls(calls)
  calls.each -> (c)
    cls = c["status"] == "failed" && c["attempts"] > 0 ? rung_failure_class(c["reason"]) : ""
    if cls == "usage-limit" || cls == "unavailable"
      RUNG_RT["exhausted"][c["label"]] = c["reason"]
  answers = []
  call_recs = []
  members = []
  calls.each -> (c)
    rec = {"model" => c["label"], "status" => c["status"], "reason" => c["reason"], "attempts" => c["attempts"], "ms" => c["ms"], "notes" => c["notes"]}
    call_recs.push(rec)
    if c["status"] == "ok"
      answers.push([c["label"], rung_read(c["answer_file"])])
      members.push(c["label"])
  rec = {
    "step" => step_no,
    "round" => round,
    "slot" => slot,
    "models" => group,
    "calls" => call_recs,
    "answers" => answers.size,
    "integration" => "none",
    "integration_reason" => "",
    "integration_ms" => 0,
    "improved" => false,
    "credit" => [],
    "changed" => "",
    "verify" => [],
    "notes" => []
  }
  new_state = state
  if answers.size == 0
    rec["status"] = "skipped"
    rec["notes"].push("every call failed")
  else
    ientry = m["integrator_entry"]
    ic = rung_new_call("integrator", "integrate (" + ientry["name"] + ")", ientry, sdir + "/integrate", rung_call_settings(m, run_dir, ientry, "integrator"))
    if !rung_call_done?(ic)
      rung_write(ic["prompt_file"], rung_integrator_prompt(rung_ctx(m, task, state, round, slot), answers))
    rung_run_calls([ic])
    rec["integration_ms"] = ic["ms"]
    if ic["status"] == "ok"
      parsed = rung_parse_integration(rung_read(ic["answer_file"]), members)
      if parsed == nil
        rec["integration"] = "failed"
        rec["integration_reason"] = "no verdict block"
        rec["status"] = "integration-failed"
      else
        rec["integration"] = "ok"
        rec["improved"] = parsed["improved"]
        rec["credit"] = parsed["credit"]
        rec["changed"] = parsed["changed"]
        rec["verify"] = parsed["verify"]
        parsed["notes"].each -> (n)
          rec["notes"].push(n)
        rec["status"] = parsed["improved"] ? "improved" : "no-change"
        new_state = parsed["state"] if parsed["improved"]
        rung_write(sdir + "/verdict.md", rung_verdict_md(parsed))
    else
      rec["integration"] = "failed"
      rec["integration_reason"] = ic["reason"]
      rec["status"] = "integration-failed"
      cls = rung_failure_class(ic["reason"])
      if cls == "usage-limit" || cls == "unavailable" || cls == "signin" || cls == "missing"
        # Every later step would fail the same way. Pause without step.json,
        # so `rung --resume` redoes only this integration (the answers are kept).
        rec["ms"] = rung_ms - t0
        rec["halt"] = "the integrator (" + ientry["name"] + ") is unavailable: " + ic["reason"]
        rung_append(run_dir + "/log.md", "- round " + round.to_s + ", step " + slot.to_s + ": paused, " + rec["halt"] + "\n")
        rung_say("    → paused: " + rec["halt"])
        return rec
  rec["ms"] = rung_ms - t0
  rec["finished"] = rung_timestamp
  rung_write(sdir + "/state.md", rung_blank?(new_state) ? rung_initial_state(task) : new_state.strip + "\n")
  rung_json_write(sdir + "/step.json", rec)
  if rec["improved"]
    rung_write(run_dir + "/state.md", new_state.strip + "\n")
  rung_append(run_dir + "/log.md", rung_log_line(rec))
  rung_say("    → " + rung_step_summary(rec))
  rec

-> rung_verdict_md(p)
  s = "improved: " + (p["improved"] ? "yes" : "no") + "\n"
  s = s + "credit: " + (p["credit"].size == 0 ? "none" : p["credit"].join(", ")) + "\n"
  s = s + "changed: " + p["changed"] + "\n"
  s = s + "verify:\n"
  p["verify"].each -> (v)
    s = s + "- " + v + "\n"
  p["notes"].each -> (n)
    s = s + "note: " + n + "\n"
  s

-> rung_step_summary(rec)
  return "paused: " + rec["halt"] if rec["halt"] != nil
  st = rec["status"]
  if st == "skipped"
    return "skipped (every call failed)"
  if st == "integration-failed"
    return "integration failed: " + rec["integration_reason"] + "; state kept"
  if rec["improved"]
    who = rec["credit"].size == 0 ? "" : " by " + rec["credit"].join(", ")
    return "improved" + who + ": " + rung_first_line(rec["changed"])
  "no improvement" + (rung_blank?(rec["changed"]) ? "" : ": " + rung_first_line(rec["changed"]))

-> rung_log_line(rec)
  calls = []
  rec["calls"].each -> (c)
    s = c["model"] + " " + c["status"]
    s = s + " (" + c["reason"] + ")" if c["status"] != "ok"
    s = s + " " + rung_secs(c["ms"])
    calls.push(s)
  "- round " + rec["round"].to_s + ", step " + rec["slot"].to_s + ": " + calls.join("; ") + "; integration " + rung_secs(rec["integration_ms"]) + " → " + rung_step_summary(rec) + "\n"

# ---- the loop ----------------------------------------------------------------------------

-> rung_take_lock(run_dir)
  lock = rung_json_read(run_dir + "/lock.json")
  me = rung_my_pid
  if lock != nil && lock["pid"].to_s != me && rung_pid_alive?(lock["pid"])
    other = lock["pid"]
    raise "another rung (pid [other]) is running this directory"
  rung_json_write(run_dir + "/lock.json", {"pid" => me, "since" => rung_timestamp})

-> rung_drop_lock(run_dir)
  p = run_dir + "/lock.json"
  File.delete(p) if File.exist?(p)

-> rung_set_status(run_dir, state, extra)
  s = {"state" => state, "updated" => rung_timestamp}
  extra.keys.each -> (k)
    s[k] = extra[k]
  rung_json_write(run_dir + "/status.json", s)

# Run (or continue) the ladder in run_dir. overrides: max_rounds.
# Returns {"stop" => reason, "rounds" => n, "steps" => [...]}.
-> rung_run_ladder(run_dir, overrides)
  m = rung_load_manifest(run_dir)
  mr = rung_opt(overrides, "max_rounds")
  if mr != nil
    m["max_rounds"] = rung_int(mr, "max_rounds")
    rung_json_write(run_dir + "/rung.json", m)
  ladder = m["ladder"]
  task = File.read(run_dir + "/task.md")
  max_rounds = m["max_rounds"]
  rung_take_lock(run_dir)
  rung_set_status(run_dir, "running", {})
  state = ""
  steps = []
  stop = nil
  round = 1
  begin
    while stop == nil
      if max_rounds > 0 && round > max_rounds
        stop = "reached max rounds (" + max_rounds.to_s + ")"
        break
      rung_say("round " + round.to_s)
      improved = false
      answered = 0
      integrated = 0
      slot = 1
      while slot <= ladder.size
        group = ladder[slot - 1]
        sdir = rung_step_dir(run_dir, round, slot, group)
        rec = rung_json_read(sdir + "/step.json")
        if rec == nil
          rec = rung_run_step(m, run_dir, sdir, task, state, round, slot, group, (round - 1) * ladder.size + slot)
          if rec["halt"] != nil
            steps.push(rec)
            stop = "paused: " + rec["halt"] + " (continue with rung --resume once it is back)"
            break
        else
          rung_say("  step " + slot.to_s + "/" + ladder.size.to_s + ": " + rung_group_text(group) + " (done earlier) → " + rung_step_summary(rec))
        if rec["improved"]
          state = File.read(sdir + "/state.md")
          improved = true
        answered += 1 if rec["answers"] > 0
        integrated += 1 if rec["integration"] == "ok"
        steps.push(rec)
        slot += 1
      break if stop != nil
      if answered == 0
        stop = "every model failed in round " + round.to_s
      elsif integrated == 0
        stop = "the integrator failed every step of round " + round.to_s
      elsif !improved
        stop = "plateau: no step improved the state in round " + round.to_s
      else
        round += 1
  rescue e
    msg = "[e]"
    rung_kill_all(RUNG_RT["running"])
    RUNG_RT["running"] = []
    if msg == "interrupted"
      rung_set_status(run_dir, "interrupted", {"rounds" => round, "steps" => steps.size})
    else
      rung_set_status(run_dir, "failed", {"error" => msg, "rounds" => round, "steps" => steps.size})
    rung_write_report(run_dir, m, steps, msg == "interrupted" ? "interrupted (continue with rung --resume)" : "error: " + msg, round)
    rung_drop_lock(run_dir)
    raise msg
  rounds = stop.starts_with?("reached max") ? round - 1 : round
  final = stop.starts_with?("paused") ? "paused" : "finished"
  done = 0
  steps.each -> (st)
    done += 1 if st["halt"] == nil
  rung_set_status(run_dir, final, {"stop" => stop, "rounds" => rounds, "steps" => done})
  rung_write_report(run_dir, m, steps, stop, rounds)
  rung_drop_lock(run_dir)
  {"stop" => stop, "rounds" => rounds, "steps" => steps, "state" => final}

# ---- dry run --------------------------------------------------------------------------------

# Write round 1's first step (prompts, work dirs, cmd.sh) without calling
# anything, and describe the plan. `rung --resume RUN` then runs it.
-> rung_dry_run(run_dir)
  m = rung_load_manifest(run_dir)
  task = File.read(run_dir + "/task.md")
  group = m["ladder"][0]
  sdir = rung_step_dir(run_dir, 1, 1, group)
  calls = rung_step_calls(m, run_dir, sdir, task, "", 1, 1, group)
  out = []
  out.push("# rung plan: " + m["title"])
  out.push("")
  out.push("- prompt file: " + m["prompt_file"])
  out.push("- run dir: " + run_dir)
  out.push("- ladder: " + rung_ladder_arrow(m["ladder"]))
  out.push("- integrator: " + m["integrator"])
  out.push("- max rounds: " + (m["max_rounds"] == 0 ? "no cap (until a plateau)" : m["max_rounds"].to_s))
  out.push("- retries: " + m["retries"].to_s + ", " + m["retry_wait"].to_s + " s apart")
  out.push("- guard: " + (rung_blank?(m["guard"]) ? "off" : m["guard"]))
  n_staged = m["staged"].size
  out.push("- staged: " + (n_staged == 0 ? "nothing" : n_staged.to_s + (n_staged == 1 ? " file: " : " files: ") + m["staged"].join(", ")))
  out.push("")
  out.push("## Calls")
  out.push("")
  names = rung_ladder_models(m["ladder"])
  names.each -> (n)
    e = m["entries"][n]
    out.push("- " + n + ": timeout " + e["timeout"].to_s + " s, provider " + e["provider"] + " (" + e["concurrency"].to_s + " at a time), answer on " + e["answer"])
  ie = m["integrator_entry"]
  out.push("- integrator " + ie["name"] + ": timeout " + ie["timeout"].to_s + " s")
  out.push("")
  out.push("## Round 1, step 1")
  out.push("")
  calls.each -> (c)
    rung_make_workdir(run_dir, m["staged"], c["workdir"])
    rung_write(c["dir"] + "/cmd.sh", rung_call_script(c))
    out.push("- " + c["label"] + ": prompt " + c["prompt_file"] + ", script " + c["dir"] + "/cmd.sh")
  out.push("")
  out.push("Nothing was called. Start it with: rung --resume " + run_dir)
  text = out.join("\n") + "\n"
  rung_write(run_dir + "/plan.md", text)
  rung_set_status(run_dir, "planned", {})
  text

# ---- the report -----------------------------------------------------------------------------

-> rung_write_report(run_dir, m, steps, stop, rounds)
  state = rung_read(run_dir + "/state.md")
  state = "" if state == nil
  improved = 0
  skipped = 0
  failed_int = 0
  model_ms = 0
  int_ms = 0
  steps.each -> (s)
    improved += 1 if s["improved"]
    skipped += 1 if s["status"] == "skipped"
    failed_int += 1 if s["status"] == "integration-failed"
    int_ms += s["integration_ms"]
    s["calls"].each -> (c)
      model_ms += c["ms"]
  r = []
  r.push("# rung report: " + m["title"])
  r.push("")
  r.push("| | |")
  r.push("|---|---|")
  r.push("| prompt | " + rung_cell(m["prompt_file"]) + " |")
  r.push("| run dir | " + rung_cell(run_dir) + " |")
  r.push("| ladder | " + rung_cell(rung_ladder_arrow(m["ladder"])) + " |")
  r.push("| integrator | " + rung_cell(m["integrator"]) + " |")
  r.push("| rounds | " + rounds.to_s + " (" + rung_cell(stop) + ") |")
  r.push("| steps | " + steps.size.to_s + ": " + improved.to_s + " improved, " + skipped.to_s + " skipped, " + failed_int.to_s + " integration failures |")
  r.push("| time | models " + rung_secs(model_ms) + ", integrator " + rung_secs(int_ms) + " |")
  r.push("| created | " + rung_cell(m["created"]) + "; report " + rung_cell(rung_timestamp) + " |")
  r.push("")
  r.push("## Final state")
  r.push("")
  r.push(state.strip)
  r.push("")
  r.push("## Accepted improvements")
  r.push("")
  if improved == 0
    r.push("None.")
  else
    r.push("| step | round | credited | what changed |")
    r.push("|---|---|---|---|")
    steps.each -> (s)
      if s["improved"]
        who = s["credit"].size == 0 ? rung_group_text(s["models"]) : s["credit"].join(", ")
        r.push("| " + s["step"].to_s + " | " + s["round"].to_s + " | " + rung_cell(who) + " | " + rung_cell(s["changed"]) + " |")
  r.push("")
  r.push("## Step log")
  r.push("")
  r.push("| step | round | model(s) | calls | integration | verdict |")
  r.push("|---|---|---|---|---|---|")
  steps.each -> (s)
    cs = []
    s["calls"].each -> (c)
      t = c["model"] + " " + c["status"] + " " + rung_secs(c["ms"])
      t = t + " (" + c["reason"] + ")" if c["status"] != "ok"
      t = t + ", " + c["attempts"].to_s + " attempts" if c["attempts"] > 1
      cs.push(t)
    integ = s["integration"] == "none" ? "none" : s["integration"] + " " + rung_secs(s["integration_ms"])
    integ = integ + " (" + s["integration_reason"] + ")" if s["integration"] == "failed"
    r.push("| " + s["step"].to_s + " | " + s["round"].to_s + " | " + rung_cell(rung_group_text(s["models"])) + " | " + rung_cell(cs.join("; ")) + " | " + rung_cell(integ) + " | " + rung_cell(rung_step_summary(s)) + " |")
  r.push("")
  verify = nil
  steps.each -> (s)
    verify = s["verify"] if s["integration"] == "ok" && s["verify"].size > 0
  r.push("## Still to verify")
  r.push("")
  if verify == nil
    r.push("Nothing listed by the integrator.")
  else
    verify.each -> (v)
      r.push("- " + v)
  r.push("")
  problems = []
  steps.each -> (s)
    s["calls"].each -> (c)
      c["notes"].each -> (n)
        problems.push("- round " + s["round"].to_s + ", step " + s["slot"].to_s + ", " + c["model"] + ": " + n + " (retried)")
      if c["status"] != "ok"
        problems.push("- round " + s["round"].to_s + ", step " + s["slot"].to_s + ", " + c["model"] + ": " + c["reason"] + " after " + c["attempts"].to_s + " attempt" + (c["attempts"] == 1 ? "" : "s") + "; skipped this round")
    if s["integration"] == "failed"
      problems.push("- round " + s["round"].to_s + ", step " + s["slot"].to_s + ", integrator: " + s["integration_reason"] + "; state kept")
    s["notes"].each -> (n)
      problems.push("- round " + s["round"].to_s + ", step " + s["slot"].to_s + ": " + n) unless n == "every call failed"
  r.push("## Failures and skips")
  r.push("")
  if problems.size == 0
    r.push("None.")
  else
    problems.each -> (p)
      r.push(p)
  r.push("")
  rung_write(run_dir + "/report.md", r.join("\n"))
