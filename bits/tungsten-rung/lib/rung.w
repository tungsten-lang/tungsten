# rung — run a prompt file up a ladder of models, with an integrator
# merging every answer into one evolving state.
#
#   rung FILE.md                 run the ladder (see README.md)
#   rung models                  the registry: installed? signed in?
#   rung check [FILE.md]         validate the registry and a prompt file
#   rung config                  print the effective registry as TOML
#
# rung only orchestrates text: it never executes anything a model proposes.

use argon
use util
use toml
use prompt_file
use registry
use stage
use runner
use prompts
use ladder

# Argon reads this text as the parser's schema: an "(default: X)" in an
# option's description becomes that option's value, so say defaults in words.
RUNG_MANPAGE = <<~EOT
  NAME
      rung -- run a prompt up a ladder of models, integrating after every call

  SYNOPSIS
      rung [options] [COMMAND] [FILE]

  DESCRIPTION
      rung FILE.md runs the task in FILE.md against each model of the ladder
      in turn. After every call an integrator model merges the answer into
      the current state (state.md). Rounds repeat until a full round brings
      no improvement, or until --max-rounds. Everything lands in a run
      directory: inputs, answers, state snapshots, verdicts, timings, and
      report.md.

      Commands:
          FILE.md          run the ladder on a prompt file
          models           list the registry: installed? signed in?
          check [FILE.md]  validate the registry, the guard and a prompt file
          config           print the effective registry as TOML
          version          print the version

  OPTIONS
      -m, --models LIST
          Models in ladder order, comma-separated; join models with | to run
          them as one parallel step, e.g. "codex,ollama:a|ollama:b,claude". (list)

      -i, --integrator MODEL
          The model that merges each answer into the state.

      -r, --max-rounds N
          Stop after N rounds even without a plateau; 0 means no cap.

      -t, --timeout SECS
          Per-call timeout for every model call.

      -o, --out DIR
          The run directory; without it, FILE.rung/STAMP beside the prompt file.

      -n, --dry-run
          Write the plan and round 1's first prompts, call nothing.

      --resume RUN_DIR
          Continue an interrupted, planned or finished run from its last completed step.

      -c, --config FILE
          Model registry. (env: RUNG_CONFIG)

      --no-guard
          Do not wrap calls in the memory/time guard.

      -q, --quiet
          Print only the final summary.

      -h, --help
          Show this help.

      -v, --version
          Print the version.
EOT

-> rung_usage
  << RUNG_MANPAGE.strip
  nil

# Turn argv into a Hash of the options rung uses (Argon does the parsing).
-> rung_cli(args)
  cli = Argon.new(RUNG_MANPAGE)
  o = cli.parse(args)
  models = o.get("models")
  if models != nil && !models.is_a?(Array)
    models = [models.to_s]
  opts = {
    "help" => o.flag?("help"),
    "version" => o.flag?("version"),
    "dry_run" => o.flag?("dry_run"),
    "no_guard" => o.flag?("no_guard"),
    "quiet" => o.flag?("quiet"),
    "models" => models,
    "integrator" => o.get("integrator"),
    "max_rounds" => o.get("max_rounds"),
    "timeout" => o.get("timeout"),
    "out" => o.get("out"),
    "resume" => o.get("resume"),
    "config" => o.get("config"),
    "args" => o.args
  }
  opts

-> rung_main(args)
  opts = nil
  begin
    opts = rung_cli(args)
  rescue e
    rung_warn("rung: [e]")
    return 2
  if opts["help"] || (args.size == 0)
    rung_usage
    return 0
  if opts["version"]
    << "rung " + RUNG_VERSION
    return 0
  RUNG_RT["quiet"] = opts["quiet"] == true
  pos = opts["args"]
  cmd = pos.size > 0 ? pos[0] : ""
  begin
    if cmd == "version"
      << "rung " + RUNG_VERSION
      return 0
    if cmd == "help"
      rung_usage
      return 0
    if cmd == "models"
      return rung_cmd_models(opts)
    if cmd == "config"
      return rung_cmd_config(opts)
    if cmd == "check"
      return rung_cmd_check(opts, pos.size > 1 ? pos[1] : nil)
    if !rung_blank?(opts["resume"])
      return rung_cmd_resume(opts)
    if cmd == ""
      rung_warn("rung: name a prompt file (rung FILE.md), or see rung --help")
      return 2
    return rung_cmd_run(cmd, opts)
  rescue e
    msg = "[e]"
    if msg == "interrupted"
      rung_warn("rung: interrupted; every call was stopped")
      return 130
    rung_warn("rung: " + msg)
    return 1
  0

-> rung_cmd_run(file, opts)
  run_dir = rung_create_run(file, opts)
  if opts["dry_run"]
    << rung_dry_run(run_dir).strip
    return 0
  rung_go(run_dir, {})

-> rung_cmd_resume(opts)
  run_dir = rung_abs(opts["resume"])
  rung_load_manifest(run_dir)
  over = {}
  over["max_rounds"] = opts["max_rounds"] if opts["max_rounds"] != nil
  rung_go(run_dir, over)

-> rung_go(run_dir, over)
  m = rung_load_manifest(run_dir)
  rung_say("rung " + RUNG_VERSION + ": " + m["title"])
  rung_say("run dir: " + run_dir)
  rung_say("ladder: " + rung_ladder_arrow(m["ladder"]) + "; integrator " + m["integrator"])
  ccall("__w_trap_interrupts")
  begin
    res = rung_run_ladder(run_dir, over)
  rescue e
    msg = "[e]"
    if msg == "interrupted"
      rung_warn("rung: interrupted; every call was stopped. Continue with: rung --resume " + run_dir)
      return 130
    raise msg
  << "rung: stopped after " + res["rounds"].to_s + " round" + (res["rounds"] == 1 ? "" : "s") + ", " + res["steps"].size.to_s + " steps: " + res["stop"]
  << "state:  " + run_dir + "/state.md"
  << "report: " + run_dir + "/report.md"
  0

-> rung_cmd_config(opts)
  loaded = rung_load_registry(opts["config"])
  << rung_registry_toml(loaded["registry"]).strip
  0

# ---- rung models ------------------------------------------------------------------------

-> rung_model_rows(reg, names)
  entries = []
  names.each -> (n)
    begin
      entries.push(rung_resolve_model(reg, n))
    rescue e
      entries.push({"name" => n, "error" => "[e]"})
  checks = []
  entries.each -> (e)
    checks.push(e["error"] == nil && rung_installed?(e["bin"]) ? e["check"] : "")
  codes = rung_run_checks(checks, 20000)
  rows = []
  i = 0
  while i < entries.size
    e = entries[i]
    if e["error"] != nil
      rows.push({"name" => e["name"], "error" => e["error"]})
    else
      inst = rung_installed?(e["bin"])
      signed = "-"
      if inst
        if rung_blank?(e["check"])
          signed = "?"
        elsif codes[i] == nil
          signed = "no answer"
        else
          signed = codes[i] == 0 ? "yes" : "no"
      rows.push({"name" => e["name"], "provider" => e["provider"], "cap" => e["concurrency"], "installed" => inst ? "yes" : "no", "signed" => signed, "timeout" => e["timeout"]})
    i += 1
  rows

-> rung_print_rows(rows)
  << rung_pad("MODEL", 18) + rung_pad("PROVIDER", 10) + rung_pad("AT ONCE", 9) + rung_pad("INSTALLED", 11) + rung_pad("SIGNED IN", 11) + "TIMEOUT"
  rows.each -> (r)
    if r["error"] != nil
      << rung_pad(r["name"], 18) + "error: " + r["error"]
    else
      << rung_pad(r["name"], 18) + rung_pad(r["provider"], 10) + rung_pad(r["cap"].to_s, 9) + rung_pad(r["installed"], 11) + rung_pad(r["signed"], 11) + r["timeout"].to_s + " s"
  nil

-> rung_cmd_models(opts)
  loaded = rung_load_registry(opts["config"])
  reg = loaded["registry"]
  rows = []
  plain = []
  patterns = []
  rung_model_names(reg).each -> (n)
    if n.ends_with?(":*")
      patterns.push(n)
    else
      plain.push(n)
  rung_model_rows(reg, plain).each -> (r)
    rows.push(r)
  patterns.each -> (p)
    prefix = p.slice(0, p.size - 2)
    pr = rung_model_rows(reg, [prefix + ":<model>"])
    pr.each -> (r)
      r["name"] = p
      rows.push(r)
  rung_print_rows(rows)
  << ""
  << "default ladder: " + rung_ladder_text(rung_parse_ladder(rung_default(reg, "models"))) + "; integrator " + rung_default(reg, "integrator").to_s
  << "config: " + loaded["path"] + (loaded["loaded"] ? "" : " (not found: built-in defaults)")
  g = rung_guard_path(reg, nil, opts["no_guard"] == true)
  << "guard: " + (g == "" ? "off" : g + " (" + rung_default(reg, "guard_mem_mb").to_s + " MB per call)")
  << "signed in: the model's check command exits 0 (? = no check configured)"
  0

# ---- rung check -------------------------------------------------------------------------

-> rung_cmd_check(opts, file)
  problems = []
  notes = []
  loaded = nil
  begin
    loaded = rung_load_registry(opts["config"])
  rescue e
    rung_warn("rung check: registry: [e]")
    return 1
  reg = loaded["registry"]
  notes.push("registry: " + loaded["path"] + (loaded["loaded"] ? "" : " (not found: built-in defaults)"))
  rung_model_names(reg).each -> (n)
    cmd = reg["models"][n]["command"]
    if rung_blank?(cmd)
      problems.push("model " + n + " has no command")
    else
      bad = rung_unknown_placeholders(cmd)
      problems.push("model " + n + " uses unknown placeholders: " + bad.join(", ")) if bad.size > 0
  front = nil
  if file != nil
    path = rung_abs(file)
    if !File.file?(path)
      problems.push("prompt file not found: " + path)
    else
      begin
        pf = rung_parse_prompt_file(File.read(path))
        front = pf["front"]
        problems.push("the prompt file has no task") if rung_blank?(pf["body"])
        bad = rung_unknown_front_keys(front)
        problems.push("unknown front-matter keys: " + bad.join(", ")) if bad.size > 0
        patterns = rung_list_value(front["stage"])
        rung_list_value(front["files"]).each -> (p)
          patterns.push(p)
        items = rung_resolve_stage(rung_dirname(path), patterns, rung_int(rung_default(reg, "stage_max_files"), "stage_max_files"), rung_int(rung_default(reg, "stage_max_bytes"), "stage_max_bytes"))
        total = 0
        items.each -> (it)
          total += it["bytes"]
        notes.push("task: " + rung_task_title(pf["body"], rung_stem(path)) + " (" + pf["body"].size.to_s + " bytes); staged " + items.size.to_s + " files, " + total.to_s + " bytes")
      rescue e
        problems.push("prompt file: [e]")
  spec = rung_opt(opts, "models")
  spec = front["models"] if spec == nil && front != nil
  spec = rung_default(reg, "models") if spec == nil
  ladder = rung_parse_ladder(spec)
  integ = rung_opt(opts, "integrator")
  integ = front["integrator"] if integ == nil && front != nil
  integ = rung_default(reg, "integrator") if integ == nil
  names = rung_ladder_models(ladder)
  rung_uniq_push(names, integ.to_s.strip)
  notes.push("ladder: " + rung_ladder_arrow(ladder) + "; integrator " + integ.to_s)
  rows = rung_model_rows(reg, names)
  rows.each -> (r)
    if r["error"] != nil
      problems.push(r["error"])
    elsif r["installed"] != "yes"
      problems.push(r["name"] + " is not installed")
    elsif r["signed"] == "no" || r["signed"] == "no answer"
      problems.push(r["name"] + " does not look signed in (its check failed)")
  g = rung_guard_path(reg, front, opts["no_guard"] == true)
  notes.push("guard: " + (g == "" ? "off" : g))
  rung_print_rows(rows)
  << ""
  notes.each -> (n)
    << n
  if problems.size == 0
    << "ok"
    return 0
  << ""
  problems.each -> (p)
    << "problem: " + p
  1
