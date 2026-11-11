# rung — the model registry.
#
# Built-in defaults match the standing ladder (codex, agy, grok, carbon, fable, claude);
# muse and any `ollama:<model>` are available but off the default ladder.
# ~/.config/rung/models.toml (or --config / $RUNG_CONFIG) is merged over
# them key by key, so a user file may change one timeout without restating
# a whole entry.
#
# A model entry:
#   command     shell command template; {prompt_file}, {workdir},
#               {answer_file}, {model} and {timeout} are substituted (paths
#               shell-quoted). It runs with {workdir} as its cwd.
#   answer      "stdout" (default): the command's stdout is the answer;
#               "file": the command writes {answer_file} itself (codex -o).
#   timeout     seconds per call
#   provider    concurrency bucket (default: the part before ':' or the name)
#   check       optional shell command that exits 0 when signed in
#   bin         executable checked by `rung models` (default: first word)
#   guard_mem_mb  memory cap for the guard wrapper
#   default_tag  pattern entries ("ollama:*"): tag appended when the model
#               name has none (glm-5.3 -> glm-5.3:cloud)
#
# [providers.<name>] concurrency = N caps how many calls of one provider run
# at once (default 3 for ollama, 1 for everything else); shared = true makes
# that cap machine-wide across rung processes (default for ollama).

RUNG_DEFAULT_GUARD = "~/math/openai/tools/guard.sh"

-> rung_builtin_registry
  models = {}
  models["codex"] = {
    "command" => "codex exec -m gpt-6-astra -c model_reasoning_effort='\"xhigh\"' -s read-only -C {workdir} --skip-git-repo-check -o {answer_file} - < {prompt_file}",
    "answer" => "file",
    "timeout" => 1500,
    "check" => "codex login status"
  }
  models["agy"] = {
    "command" => "agy -p \"$(cat {prompt_file})\" --model gemini-4-argon-high --print-timeout {timeout}s",
    "timeout" => 2400,
    "check" => "test -s \"$HOME/.gemini/google_accounts.json\""
  }
  models["grok"] = {
    "command" => "grok --prompt-file {prompt_file} -m grok-4.7 --reasoning-effort high --permission-mode dontAsk --no-subagents",
    "timeout" => 2400,
    "check" => "test -s \"$HOME/.grok/auth.json\""
  }
  models["muse"] = {
    "command" => "muse exec --model muse-wonder-full-1.0 --reasoning-effort xhigh --workspace {workdir} --prompt-file {prompt_file}",
    "timeout" => 2400,
    "check" => "muse usage"
  }
  models["claude"] = {
    "command" => "claude -p --permission-mode plan < {prompt_file}",
    "timeout" => 1800,
    "check" => "claude auth status"
  }
  # (2026-11-10, Erik: "include Fable 5.2 'high' and Gemini 4 Carbon 'high'") two more improvers on the default ladder; each
  # shares its CLI's concurrency bucket (agy, claude)
  models["carbon"] = {
    "command" => "agy -p \"$(cat {prompt_file})\" --model gemini-4-carbon-high --print-timeout {timeout}s",
    "timeout" => 2400,
    "provider" => "agy",
    "bin" => "agy",
    "check" => "test -s \"$HOME/.gemini/google_accounts.json\""
  }
  models["fable"] = {
    "command" => "claude -p --model claude-fable-5-2 --effort high --permission-mode plan < {prompt_file}",
    "timeout" => 1800,
    "provider" => "claude",
    "bin" => "claude",
    "check" => "claude auth status"
  }
  models["ollama:*"] = {
    "command" => "ollama launch claude --model {model} -- -p --permission-mode plan < {prompt_file}",
    "timeout" => 1800,
    "default_tag" => "cloud",
    "provider" => "ollama",
    "check" => "ollama list"
  }
  reg = {
    "defaults" => {
      "models" => ["codex", "agy", "grok", "carbon", "fable", "claude"],
      "integrator" => "claude",
      "timeout" => 2400,
      "retries" => 2,
      "retry_wait" => 60,
      "max_rounds" => 8,
      "guard" => RUNG_DEFAULT_GUARD,
      "guard_mem_mb" => 4096,
      "stage_max_files" => 200,
      "stage_max_bytes" => 8000000
    },
    "providers" => {"ollama" => {"concurrency" => 3, "shared" => true}},
    "models" => models
  }
  reg

-> rung_config_path(explicit)
  return rung_abs(explicit) if !rung_blank?(explicit)
  env = Env.get("RUNG_CONFIG")
  return rung_abs(env) if !rung_blank?(env)
  xdg = Env.get("XDG_CONFIG_HOME")
  base = rung_blank?(xdg) ? rung_home + "/.config" : xdg
  base + "/rung/models.toml"

# Merge src's tables into dst (two levels: section -> entry -> key).
#
# TODO(compiler): plain while loops on purpose. Written with blocks
# (`sv.keys.each -> (k)` around `if v.is_a?(Hash)` whose branch builds a
# closure capturing k), the compiled block parameter k reads garbage in the
# else branch: it prints false and indexes as "Hash", so every [defaults]
# override was silently dropped. Repro: a block param captured by a closure
# created on an is_a?-narrowed receiver; see the rung branch's report.
-> rung_merge_registry(dst, src)
  sections = src.keys
  si = 0
  while si < sections.size
    section = sections[si]
    si += 1
    next if section == "builtins"
    sv = src[section]
    if !sv.is_a?(Hash)
      raise "models.toml: top-level key '[section]' must be a table"
    if dst[section] == nil
      dst[section] = {}
    dv = dst[section]
    keys = sv.keys
    ki = 0
    while ki < keys.size
      k = keys[ki]
      ki += 1
      v = sv[k]
      if v.is_a?(Hash) && (section == "models" || section == "providers")
        if dv[k] == nil
          dv[k] = {}
        entry = dv[k]
        inner = v.keys
        ii = 0
        while ii < inner.size
          entry[inner[ii]] = v[inner[ii]]
          ii += 1
      else
        dv[k] = v
  dst

# {"registry" => ..., "path" => ..., "loaded" => true/false}
# A top-level `builtins = false` in the file drops the built-in models,
# providers, ladder and integrator (the knobs in [defaults] stay), so a
# registry of stand-ins can never reach a real model CLI by accident.
-> rung_load_registry(explicit)
  reg = rung_builtin_registry
  path = rung_config_path(explicit)
  loaded = false
  if File.file?(path)
    parsed = rung_toml_parse(File.read(path))
    if parsed["builtins"] == false
      reg["models"] = {}
      reg["providers"] = {}
      reg["defaults"]["models"] = []
      reg["defaults"]["integrator"] = ""
    rung_merge_registry(reg, parsed)
    loaded = true
  elsif !rung_blank?(explicit)
    raise "config file not found: [path]"
  result = {"registry" => reg, "path" => path, "loaded" => loaded}
  result

-> rung_default(reg, key)
  reg["defaults"][key]

# Resolve one model name to a concrete entry:
#   {"name", "command", "answer", "timeout", "provider", "check", "bin",
#    "model", "guard_mem_mb"}
-> rung_resolve_model(reg, name)
  models = reg["models"]
  entry = models[name]
  model_arg = name
  if entry == nil && name.index(":") != nil
    prefix = name.slice(0, name.index(":"))
    pat = models[prefix + ":*"]
    if pat != nil
      entry = pat
      model_arg = name.slice(prefix.size + 1, name.size - prefix.size - 1)
      tag = entry["default_tag"]
      if model_arg.index(":") == nil && !rung_blank?(tag)
        model_arg = model_arg + ":" + tag
  raise "unknown model '[name]' (rung models lists the registry)" if entry == nil
  cmd = entry["command"]
  raise "model '[name]' has no command" if rung_blank?(cmd)
  provider = entry["provider"]
  if rung_blank?(provider)
    provider = name.index(":") == nil ? name : name.slice(0, name.index(":"))
  timeout = entry["timeout"]
  timeout = rung_default(reg, "timeout") if timeout == nil
  answer = entry["answer"]
  answer = "stdout" if rung_blank?(answer)
  raise "model '[name]': answer must be \"stdout\" or \"file\"" unless answer == "stdout" || answer == "file"
  bin = entry["bin"]
  bin = rung_first_word(cmd) if rung_blank?(bin)
  mem = entry["guard_mem_mb"]
  mem = rung_default(reg, "guard_mem_mb") if mem == nil
  resolved = {
    "name" => name,
    "command" => cmd,
    "answer" => answer,
    "timeout" => rung_int(timeout, "timeout of [name]"),
    "provider" => provider,
    "concurrency" => rung_provider_cap(reg, provider),
    "shared" => rung_provider_shared?(reg, provider),
    "check" => entry["check"] == nil ? "" : entry["check"],
    "bin" => bin,
    "model" => model_arg,
    "guard_mem_mb" => rung_int(mem, "guard_mem_mb of [name]")
  }
  resolved

-> rung_provider_cap(reg, provider)
  p = reg["providers"] == nil ? nil : reg["providers"][provider]
  if p != nil && p["concurrency"] != nil
    n = rung_int(p["concurrency"], "concurrency of provider [provider]")
    return n < 1 ? 1 : n
  provider == "ollama" ? 3 : 1

# A shared provider's cap counts calls across every rung on the machine
# (an account limit, like ollama's); otherwise it counts within one run.
-> rung_provider_shared?(reg, provider)
  p = reg["providers"] == nil ? nil : reg["providers"][provider]
  return false if p == nil || p["shared"] == nil
  p["shared"] == true

-> rung_first_word(cmd)
  t = cmd.strip
  i = 0
  while i < t.size && t.slice(i, 1) != " " && t.slice(i, 1) != "\t"
    i += 1
  t.slice(0, i)

# The command for one call: placeholders become shell-quoted values.
-> rung_render_command(entry, vars)
  cmd = entry["command"]
  cmd = rung_replace(cmd, "{prompt_file}", rung_shq(vars["prompt_file"]))
  cmd = rung_replace(cmd, "{workdir}", rung_shq(vars["workdir"]))
  cmd = rung_replace(cmd, "{answer_file}", rung_shq(vars["answer_file"]))
  cmd = rung_replace(cmd, "{model}", rung_shq(entry["model"]))
  cmd = rung_replace(cmd, "{timeout}", vars["timeout"].to_s)
  cmd

# Placeholders a template uses that rung does not know (rung check).
-> rung_unknown_placeholders(cmd)
  known = ["prompt_file", "workdir", "answer_file", "model", "timeout"]
  out = []
  i = 0
  while true
    j = cmd.index("{", i)
    break if j == nil
    k = cmd.index("}", j)
    break if k == nil
    name = cmd.slice(j + 1, k - j - 1)
    simple = name != ""
    n = 0
    while n < name.size
      b = name.byte_at(n)
      simple = false unless (b >= 97 && b <= 122) || b == 95
      n += 1
    if simple && !rung_contains?(known, name)
      rung_uniq_push(out, name)
    i = j + 1
  out

-> rung_guard_path(reg, front, no_guard)
  return "" if no_guard
  g = nil
  if front != nil && front["guard"] != nil
    fg = front["guard"]
    return "" if rung_falsy?(fg)
    g = rung_truthy?(fg) ? rung_default(reg, "guard") : fg
  else
    g = rung_default(reg, "guard")
  return "" if rung_blank?(g) || g == false
  p = rung_abs(g)
  File.file?(p) ? p : ""

-> rung_model_names(reg)
  rung_sorted(reg["models"].keys)

# The effective registry as TOML (`rung config`): a starting point for
# ~/.config/rung/models.toml.
-> rung_registry_toml(reg)
  out = "# rung model registry (rung config prints the effective one).\n"
  out = out + "# Placeholders: {prompt_file} {workdir} {answer_file} {model} {timeout}\n\n"
  out = out + rung_toml_table("defaults", reg["defaults"], ["models", "integrator", "timeout", "retries", "retry_wait", "max_rounds", "guard", "guard_mem_mb", "stage_max_files", "stage_max_bytes"]) + "\n"
  rung_sorted(reg["providers"].keys).each -> (p)
    out = out + rung_toml_table("providers." + rung_toml_key(p), reg["providers"][p], ["concurrency", "shared"]) + "\n"
  rung_model_names(reg).each -> (m)
    out = out + rung_toml_table("models." + rung_toml_key(m), reg["models"][m], ["command", "answer", "timeout", "provider", "default_tag", "check", "bin", "guard_mem_mb"]) + "\n"
  out
