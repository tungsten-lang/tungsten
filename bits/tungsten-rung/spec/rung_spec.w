# rung spec: parsers, the registry, staging, the integrator's reply format,
# and whole ladders run against a fake registry of shell "models" (echo,
# grep, sleep), so it runs offline in a few seconds.
#
# spec: compiled -- rung spawns processes (Process is compiled-only) and
# parses its CLI with Argon (compiled option-parser lowering).
#
# Run from the repo root:
#   BIT_HOME=$PWD/bits bin/tungsten bits/tungsten-rung/spec/rung_spec.w

use spec
use ../lib/rung

# ---- fixtures ----------------------------------------------------------------------------

-> spec_tmp_root
  base = Env.get("TMPDIR")
  base = "/tmp" if rung_blank?(base)
  base = base.slice(0, base.size - 1) if base.ends_with?("/")
  base + "/rung-spec-" + rung_ms.to_s

SPEC_DIR = spec_tmp_root
rung_mkdir(SPEC_DIR)

FAKE_INTEGRATOR = <<~EOT
  #!/bin/sh
  # Fake integrator: accepts every "IMPROVE by NAME" line in the new answers
  # and appends "accepted NAME" to the state.
  p="$1"
  state=$(awk '/^# Current state/{f=1;next} /^# New answers/{f=0} f' "$p" | sed '/^$/d' | grep -v '^(empty')
  new=$(awk '/^# New answers/{f=1;next} /^# What to do/{f=0} f' "$p")
  credit=$(printf '%s\n' "$new" | sed -n 's/.*IMPROVE by \([a-z0-9:._-]*\).*/\1/p' | sort -u | paste -sd, - | sed 's/,/, /g')
  if [ -n "$credit" ]; then
    printf '<rung-state>\n'
    [ -n "$state" ] && printf '%s\n' "$state"
    for c in $(printf '%s' "$credit" | tr -d ' ' | tr ',' ' '); do printf 'accepted %s\n' "$c"; done
    printf '</rung-state>\n<rung-verdict>\nimproved: yes\ncredit: %s\nchanged: accepted %s\nverify:\n- the claim from %s\n</rung-verdict>\n' "$credit" "$credit" "$credit"
  else
    printf 'Nothing to merge.\n<rung-state>\n</rung-state>\n<rung-verdict>\nimproved: no\ncredit: none\nchanged: nothing\nverify:\n</rung-verdict>\n'
  fi
EOT

FAKE_REGISTRY = <<~EOT
  # Fake models for the rung spec: plain shell, no network. builtins = false
  # drops the real CLIs, so nothing here can reach a real model.
  builtins = false

  [defaults]
  models = ["alpha", "beta | gamma"]
  integrator = "integ"
  timeout = 30
  retries = 0
  retry_wait = 0
  max_rounds = 5
  guard = ""

  [providers.fake]
  concurrency = 2

  [models.alpha]
  command = "echo run >> {{DIR}}/alpha.count; if grep -q 'accepted alpha' {prompt_file}; then echo 'alpha: nothing new'; else echo 'IMPROVE by alpha'; fi"

  [models.beta]
  command = "if grep -q 'accepted beta' {prompt_file}; then echo 'beta: nothing new'; else echo 'IMPROVE by beta'; fi"

  [models.gamma]
  command = "echo 'gamma: nothing new'"

  [models.integ]
  command = "sh {{DIR}}/fake_integrator.sh {prompt_file}"

  [models.broken]
  command = "echo 'Error: rate limit exceeded' >&2; exit 1"

  [models.nologin]
  command = "echo 'Not signed in' >&2; exit 1"

  [models.slow]
  command = "sleep 30"
  timeout = 1

  [models.filer]
  command = "echo 'IMPROVE by filer' > {answer_file}; echo 'progress noise'"
  answer = "file"

  [models.flaky]
  command = "if [ -e {{DIR}}/flaky.flag ]; then echo 'IMPROVE by flaky'; else touch {{DIR}}/flaky.flag; echo 'HTTP 429 Too Many Requests' >&2; exit 1; fi"

  [models.quota]
  command = "echo run >> {{DIR}}/quota.count; echo \"You've hit your weekly limit · resets Nov 1\"; exit 1"

  [models.retired]
  command = "echo 'Claude Code doesn'\\''t recognize the model \"x:cloud\"' >&2; echo 'API Error: 410 x:0731 was retired on September 25, 2026.'; echo 'Error: exit status 1' >&2; exit 1"

  [models.noisy]
  command = "echo 'Claude Code doesn'\\''t recognize the model \"y:cloud\"' >&2; echo 'Error: connection reset by peer' >&2; echo 'Error: exit status 1' >&2; exit 1"

  [models.delta]
  command = "echo run >> {{DIR}}/delta.count; echo 'IMPROVE by delta'"

  [models.gate]
  command = "if [ -e {{DIR}}/gate.open ]; then sh {{DIR}}/fake_integrator.sh {prompt_file}; else echo \"You've hit your weekly limit · resets Nov 1 at 2pm\"; exit 1; fi"

  [models.lister]
  command = "ls -R . > /dev/null; cat notes/a.md; cat src/x.w"

  [models."fake:*"]
  command = "sleep 1; printf 'IMPROVE by fake:%s\\n' {model}"
  provider = "fake"

  [providers.share]
  concurrency = 2
  shared = true

  [models."share:*"]
  command = "sleep 1; printf 'IMPROVE by share:%s\\n' {model}"
EOT

rung_write(SPEC_DIR + "/fake_integrator.sh", FAKE_INTEGRATOR)
SPEC_CONFIG = SPEC_DIR + "/models.toml"
rung_write(SPEC_CONFIG, rung_replace(FAKE_REGISTRY, "{{DIR}}", SPEC_DIR))

-> spec_prompt(name, text)
  p = SPEC_DIR + "/" + name
  rung_write(p, text)
  p

-> spec_run(args)
  rung_main(args + ["--config", SPEC_CONFIG, "--quiet"])

-> spec_step(run_dir, name)
  rung_json_read(run_dir + "/steps/" + name + "/step.json")

-> spec_count_lines(p)
  rung_lines(rung_read(p)).size

SPEC_TOML = <<~EOT
  # c
  [defaults]
  models = ["a", 'b | c',
    "d"]  # trailing
  timeout = 1_200
  flag = true
  [models."ollama:*"]
  command = 'say "hi" # not a comment'
  esc = "a\tb\"c"
  multi = '''
  line1
  line2'''
EOT

# ---- parsers ----------------------------------------------------------------------------

describe "rung prompt files" ->
  it "splits front matter from the task" ->
    pf = rung_parse_prompt_file("---\nmodels: codex, ollama:a | ollama:b, claude\nintegrator: claude\nmax_rounds: 3\nstage:\n  - README.md\n  - \"src/*.w\"\ndeliverable: |\n  Line one.\n  Line two.\n---\n# Bound the sum\n\nProve it.\n")
    f = pf["front"]
    expect(f["integrator"]).to eq("claude")
    expect(f["max_rounds"]).to eq("3")
    expect(f["stage"].size).to eq(2)
    expect(f["stage"][1]).to eq("src/*.w")
    expect(f["deliverable"]).to eq("Line one.\nLine two.")
    expect(pf["body"]).to eq("# Bound the sum\n\nProve it.\n")
    expect(rung_task_title(pf["body"], "x")).to eq("Bound the sum")

  it "reads a prompt without front matter" ->
    pf = rung_parse_prompt_file("Just the task.\n")
    expect(pf["front"].keys.size).to eq(0)
    expect(pf["body"]).to eq("Just the task.\n")

  it "parses inline lists and reports unknown keys" ->
    pf = rung_parse_prompt_file("---\nfiles: \[a.md, 'b c.md'\]\nmodles: codex\n---\nTask\n")
    expect(pf["front"]["files"].size).to eq(2)
    expect(pf["front"]["files"][1]).to eq("b c.md")
    expect(rung_unknown_front_keys(pf["front"])).to eq(["modles"])

  it "parses ladders with parallel groups" ->
    l = rung_parse_ladder("codex, ollama:a | ollama:b|ollama:c ,claude")
    expect(l.size).to eq(3)
    expect(l[1]).to eq(["ollama:a", "ollama:b", "ollama:c"])
    l2 = rung_parse_ladder(["alpha", "beta | gamma"])
    expect(l2[1]).to eq(["beta", "gamma"])
    expect(rung_ladder_models(l)).to eq(["codex", "ollama:a", "ollama:b", "ollama:c", "claude"])

describe "rung command line" ->
  it "parses options, groups and flags, and leaves unset options nil" ->
    o = rung_cli(["task.md", "-m", "codex,ollama:a|ollama:b", "--no-guard", "-r", "0", "-n"])
    expect(o["args"]).to eq(["task.md"])
    expect(o["models"]).to eq(["codex", "ollama:a|ollama:b"])
    expect(o["no_guard"]).to eq(true)
    expect(o["dry_run"]).to eq(true)
    expect(o["max_rounds"]).to eq(0)
    plain = rung_cli(["task.md"])
    expect(plain["out"]).to be_nil
    expect(plain["timeout"]).to be_nil
    expect(plain["integrator"]).to be_nil
    expect(plain["max_rounds"]).to be_nil
    expect(plain["resume"]).to be_nil
    expect(plain["config"]).to be_nil

  it "puts the run directory beside the prompt file by default" ->
    p = spec_prompt("where.md", "---\nmodels: gamma\nmax_rounds: 1\n---\nTask seven.\n")
    expect(spec_run([p, "--dry-run"])).to eq(0)
    runs = rung_children(SPEC_DIR + "/where.rung")
    expect(runs.size).to eq(1)
    expect(runs[0].size).to eq(15)
    expect(File.exist?(SPEC_DIR + "/where.rung/" + runs[0] + "/plan.md")).to eq(true)

describe "rung TOML subset" ->
  it "parses tables, quoted keys, strings, numbers, booleans and arrays" ->
    t = rung_toml_parse(SPEC_TOML)
    expect(t["defaults"]["models"]).to eq(["a", "b | c", "d"])
    expect(t["defaults"]["timeout"]).to eq(1200)
    expect(t["defaults"]["flag"]).to eq(true)
    expect(t["models"]["ollama:*"]["command"]).to eq("say \"hi\" # not a comment")
    expect(t["models"]["ollama:*"]["esc"]).to eq("a\tb\"c")
    expect(t["models"]["ollama:*"]["multi"]).to eq("line1\nline2")

  it "round-trips the built-in registry through rung config" ->
    reg = rung_builtin_registry
    back = rung_toml_parse(rung_registry_toml(reg))
    expect(back["models"]["codex"]["command"]).to eq(reg["models"]["codex"]["command"])
    expect(back["models"]["ollama:*"]["default_tag"]).to eq("cloud")
    expect(back["defaults"]["models"]).to eq(["codex", "agy", "grok", "carbon", "fable", "claude"])

  it "rejects malformed input with a line number" ->
    msg = ""
    begin
      rung_toml_parse("\[defaults\]\ntimeout = soon\n")
    rescue e
      msg = "[e]"
    expect(msg.index("line 2") != nil).to eq(true)

# ---- registry ----------------------------------------------------------------------------

describe "rung registry" ->
  it "resolves ollama models through the pattern entry" ->
    reg = rung_builtin_registry
    e = rung_resolve_model(reg, "ollama:glm-5.3")
    expect(e["model"]).to eq("glm-5.3:cloud")
    expect(e["provider"]).to eq("ollama")
    expect(e["concurrency"]).to eq(3)
    e2 = rung_resolve_model(reg, "ollama:qwen4:local")
    expect(e2["model"]).to eq("qwen4:local")
    cmd = rung_render_command(e, {"prompt_file" => "/r/p.md", "workdir" => "/r/w", "answer_file" => "/r/a.md", "timeout" => 60})
    expect(cmd).to eq("ollama launch claude --model 'glm-5.3:cloud' -- -p --permission-mode plan < '/r/p.md'")

  it "keeps the standing ladder's read-only modes" ->
    reg = rung_builtin_registry
    expect(rung_resolve_model(reg, "codex")["command"].index("-s read-only") != nil).to eq(true)
    expect(rung_resolve_model(reg, "codex")["answer"]).to eq("file")
    expect(rung_resolve_model(reg, "claude")["command"].index("--permission-mode plan") != nil).to eq(true)
    expect(rung_resolve_model(reg, "grok")["command"].index("--permission-mode dontAsk --no-subagents") != nil).to eq(true)
    expect(rung_resolve_model(reg, "muse")["command"].index("--workspace {workdir}") != nil).to eq(true)
    expect(rung_resolve_model(reg, "codex")["concurrency"]).to eq(1)
    expect(rung_resolve_model(reg, "codex")["shared"]).to eq(false)
    expect(rung_resolve_model(reg, "ollama:glm-5.3")["shared"]).to eq(true)

  it "merges a user file over the built-ins key by key" ->
    reg = rung_builtin_registry
    rung_merge_registry(reg, rung_toml_parse("\[models.codex\]\ntimeout = 99\n\[providers.codex\]\nconcurrency = 2\n"))
    e = rung_resolve_model(reg, "codex")
    expect(e["timeout"]).to eq(99)
    expect(e["concurrency"]).to eq(2)
    expect(e["command"].index("codex exec") != nil).to eq(true)

  it "takes \[defaults\] from the user file, and drops the built-ins on builtins = false" ->
    loaded = rung_load_registry(SPEC_CONFIG)
    reg = loaded["registry"]
    expect(loaded["loaded"]).to eq(true)
    expect(rung_default(reg, "integrator")).to eq("integ")
    expect(rung_default(reg, "guard")).to eq("")
    expect(rung_default(reg, "retries")).to eq(0)
    expect(rung_default(reg, "stage_max_files")).to eq(200)
    expect(reg["models"]["claude"]).to be_nil
    expect(reg["providers"]["ollama"]).to be_nil
    expect(rung_resolve_model(reg, "fake:x")["concurrency"]).to eq(2)

  it "quotes substituted paths for the shell" ->
    e = {"command" => "cat {prompt_file} > {answer_file}", "model" => "m"}
    cmd = rung_render_command(e, {"prompt_file" => "/a b/it's.md", "workdir" => "/w", "answer_file" => "/o.md", "timeout" => 5})
    expect(cmd).to eq("cat '/a b/it'\\''s.md' > '/o.md'")

  it "refuses unknown models" ->
    msg = ""
    begin
      rung_resolve_model(rung_builtin_registry, "gpt-nobody")
    rescue e
      msg = "[e]"
    expect(msg.index("unknown model 'gpt-nobody'") != nil).to eq(true)

  it "finds unknown placeholders" ->
    expect(rung_unknown_placeholders("x {prompt_file} {promt} ${HOME} {model}")).to eq(["promt"])

# ---- staging -----------------------------------------------------------------------------

describe "rung staging" ->
  it "matches segments with * and ?" ->
    expect(rung_fnmatch("*.md", "a.md")).to eq(true)
    expect(rung_fnmatch("*.md", "a.mdx")).to eq(false)
    expect(rung_fnmatch("a?c*", "abcdef")).to eq(true)
    expect(rung_fnmatch("a?c", "ac")).to eq(false)

  it "resolves globs, directories and ** relative to the prompt" ->
    d = SPEC_DIR + "/stagecase"
    rung_write(d + "/notes/a.md", "note a\n")
    rung_write(d + "/notes/b.txt", "note b\n")
    rung_write(d + "/src/x.w", "x = 1\n")
    rung_write(d + "/src/deep/y.w", "y = 2\n")
    rung_write(d + "/src/.hidden.w", "h\n")
    items = rung_resolve_stage(d, ["notes/*.md", "src/**/*.w"], 100, 100000)
    rels = []
    items.each -> (it)
      rels.push(it["rel"])
    expect(rels).to eq(["notes/a.md", "src/deep/y.w", "src/x.w"])
    items2 = rung_resolve_stage(d, ["src"], 100, 100000)
    expect(items2.size).to eq(2)

  it "refuses patterns that match nothing and oversized sets" ->
    d = SPEC_DIR + "/stagecase"
    msg = ""
    begin
      rung_resolve_stage(d, ["nope/*.md"], 100, 100000)
    rescue e
      msg = "[e]"
    expect(msg.index("matches no files") != nil).to eq(true)
    msg2 = ""
    begin
      rung_resolve_stage(d, ["src"], 1, 100000)
    rescue e
      msg2 = "[e]"
    expect(msg2.index("exceed the limit") != nil).to eq(true)

# ---- the integrator's reply -----------------------------------------------------------------

describe "rung integration replies" ->
  it "parses the state and the verdict" ->
    r = rung_parse_integration("Some preamble.\n<rung-state>\n# Answer\nx = 2\n</rung-state>\n<rung-verdict>\n- **improved:** yes\ncredit: codex, `grok`, nobody\nchanged: fixed the bound\nverify:\n- the constant 3\n- the base case\n</rung-verdict>\n", ["codex", "grok"])
    expect(r["improved"]).to eq(true)
    expect(r["state"]).to eq("# Answer\nx = 2")
    expect(r["credit"]).to eq(["codex", "grok"])
    expect(r["changed"]).to eq("fixed the bound")
    expect(r["verify"]).to eq(["the constant 3", "the base case"])

  it "credits a lone model and keeps the state on a contentless yes" ->
    r = rung_parse_integration("<rung-state>\nS\n</rung-state>\n<rung-verdict>\nimproved: yes\ncredit: none\nchanged: c\nverify: none\n</rung-verdict>", ["agy"])
    expect(r["credit"]).to eq(["agy"])
    expect(r["verify"].size).to eq(0)
    r2 = rung_parse_integration("<rung-state>\n</rung-state>\n<rung-verdict>\nimproved: yes\n</rung-verdict>", ["agy"])
    expect(r2["improved"]).to eq(false)
    expect(r2["notes"].size).to eq(1)

  it "returns nil without a verdict block" ->
    expect(rung_parse_integration("just prose", ["a"])).to be_nil

  it "fills prompt templates in one pass" ->
    expect(rung_fill("{{A}} and {{B}} {{C}}", {"A" => "{{B}}", "B" => "b"})).to eq("{{B}} and b {{C}}")

  it "writes generic model prompts" ->
    p = rung_model_prompt({"task" => "Do X.", "deliverable" => "", "state" => "", "round" => 1, "step" => 2, "rels" => ["a.md"]})
    expect(p.index("Do X.") != nil).to eq(true)
    expect(p.index("No model has answered yet") != nil).to eq(true)
    expect(p.index("read-only copies of the staged files (a.md)") != nil).to eq(true)
    expect(p.index("round 1, step 2") != nil).to eq(true)

# ---- whole ladders against the fake registry ------------------------------------------------

describe "rung ladders" ->
  it "plans with --dry-run, then runs to a plateau with --resume" ->
    p = spec_prompt("plateau.md", "---\nmodels: alpha, beta | gamma\n---\n# Fake task\n\nSay something.\n")
    out = SPEC_DIR + "/run-plateau"
    expect(spec_run([p, "--out", out, "--dry-run"])).to eq(0)
    expect(File.exist?(out + "/plan.md")).to eq(true)
    expect(File.exist?(out + "/steps/r01-s01-alpha/calls/alpha/prompt.md")).to eq(true)
    expect(File.exist?(out + "/steps/r01-s01-alpha/calls/alpha/answer.md")).to eq(false)
    expect(rung_json_read(out + "/status.json")["state"]).to eq("planned")
    plan = rung_json_read(out + "/rung.json")
    expect(plan["integrator"]).to eq("integ")
    expect(plan["guard"]).to eq("")
    expect(plan["ladder"]).to eq([["alpha"], ["beta", "gamma"]])
    expect(spec_run(["--resume", out])).to eq(0)
    st = rung_json_read(out + "/status.json")
    expect(st["state"]).to eq("finished")
    expect(st["stop"]).to eq("plateau: no step improved the state in round 2")
    expect(st["steps"]).to eq(4)
    state = rung_read(out + "/state.md")
    expect(state).to eq("accepted alpha\naccepted beta\n")
    s2 = spec_step(out, "r01-s02-beta+gamma")
    expect(s2["improved"]).to eq(true)
    expect(s2["credit"]).to eq(["beta"])
    expect(s2["calls"].size).to eq(2)
    expect(spec_step(out, "r02-s01-alpha")["improved"]).to eq(false)
    report = rung_read(out + "/report.md")
    expect(report.index("| 1 | 1 | alpha | accepted alpha |") != nil).to eq(true)
    expect(report.index("| 2 | 1 | beta | accepted beta |") != nil).to eq(true)
    expect(report.index("plateau") != nil).to eq(true)
    expect(report.index("- the claim from beta") != nil).to eq(true)
    expect(File.exist?(out + "/steps/r01-s01-alpha/integrate/prompt.md")).to eq(true)
    expect(File.exist?(out + "/lock.json")).to eq(false)
    expect(spec_count_lines(SPEC_DIR + "/alpha.count")).to eq(2)

  it "resumes after max rounds and after an interrupted step without redoing finished calls" ->
    p = spec_prompt("resume.md", "---\nmodels: alpha, beta\n---\nTask two.\n")
    out = SPEC_DIR + "/run-resume"
    rung_rm_rf(SPEC_DIR + "/alpha.count")
    expect(spec_run([p, "--out", out, "--max-rounds", "1"])).to eq(0)
    expect(rung_json_read(out + "/status.json")["stop"]).to eq("reached max rounds (1)")
    expect(spec_run(["--resume", out, "--max-rounds", "4"])).to eq(0)
    st = rung_json_read(out + "/status.json")
    expect(st["stop"]).to eq("plateau: no step improved the state in round 2")
    expect(st["steps"]).to eq(4)
    expect(spec_count_lines(SPEC_DIR + "/alpha.count")).to eq(2)
    # lose the last step's record, as if rung died while integrating
    File.delete(out + "/steps/r02-s02-beta/step.json")
    expect(spec_run(["--resume", out])).to eq(0)
    expect(rung_json_read(out + "/status.json")["steps"]).to eq(4)
    expect(spec_count_lines(SPEC_DIR + "/alpha.count")).to eq(2)
    expect(spec_step(out, "r02-s02-beta")["calls"][0]["status"]).to eq("ok")
    expect(rung_read(out + "/state.md")).to eq("accepted alpha\naccepted beta\n")

  it "retries, times out, skips signed-out models, and reads answer files" ->
    p = spec_prompt("failures.md", "---\nmodels: broken, nologin, slow, flaky, filer\nretries: 1\nretry_wait: 0\nmax_rounds: 1\n---\nTask three.\n")
    out = SPEC_DIR + "/run-failures"
    expect(spec_run([p, "--out", out])).to eq(0)
    b = spec_step(out, "r01-s01-broken")
    expect(b["status"]).to eq("skipped")
    expect(b["calls"][0]["reason"]).to eq("rate limited: Error: rate limit exceeded")
    expect(b["calls"][0]["attempts"]).to eq(2)
    expect(File.exist?(out + "/steps/r01-s01-broken/calls/broken/attempt-1-log.txt")).to eq(true)
    n = spec_step(out, "r01-s02-nologin")
    expect(n["calls"][0]["reason"]).to eq("not signed in: Not signed in")
    expect(n["calls"][0]["attempts"]).to eq(1)
    s = spec_step(out, "r01-s03-slow")
    expect(s["calls"][0]["reason"]).to eq("timed out after 1 s")
    expect(s["calls"][0]["ms"] < 15000).to eq(true)
    f = spec_step(out, "r01-s04-flaky")
    expect(f["improved"]).to eq(true)
    expect(f["calls"][0]["attempts"]).to eq(2)
    fl = spec_step(out, "r01-s05-filer")
    expect(fl["credit"]).to eq(["filer"])
    expect(rung_read(out + "/state.md")).to eq("accepted flaky\naccepted filer\n")
    report = rung_read(out + "/report.md")
    expect(report.index("broken: rate limited: Error: rate limit exceeded (after 2 attempts); skipped this round") != nil).to eq(true)
    expect(report.index("nologin: not signed in: Not signed in (after 1 attempt)") != nil).to eq(true)
    expect(report.index("flaky: attempt 1: rate limited: HTTP 429 Too Many Requests (retried)") != nil).to eq(true)

  it "runs a parallel group within its provider's concurrency cap" ->
    p = spec_prompt("group.md", "---\nmodels: fake:m1 | fake:m2 | fake:m3\nmax_rounds: 1\n---\nTask four.\n")
    out = SPEC_DIR + "/run-group"
    expect(spec_run([p, "--out", out])).to eq(0)
    g = spec_step(out, "r01-s01-fake-m1+fake-m2+fake-m3")
    expect(g["answers"]).to eq(3)
    expect(g["credit"]).to eq(["fake:m1", "fake:m2", "fake:m3"])
    # three one-second calls, two at a time: about two seconds, not one or three
    expect(g["ms"] >= 1900).to eq(true)
    expect(g["ms"] < 3300).to eq(true)

  it "counts a shared provider's cap across processes and reclaims dead slots" ->
    slots = SPEC_DIR + "/slots"
    Env.set("RUNG_SLOTS", slots)
    # slot 1 is held by a live process (this one, outside the run), slot 2 by a dead pid
    rung_write(slots + "/share.1/owner", rung_my_pid + " another rung\n")
    rung_write(slots + "/share.2/owner", "999999 a crashed rung\n")
    p = spec_prompt("shared.md", "---\nmodels: share:a | share:b | share:c\nmax_rounds: 1\n---\nTask six.\n")
    out = SPEC_DIR + "/run-shared"
    expect(spec_run([p, "--out", out])).to eq(0)
    g = spec_step(out, "r01-s01-share-a+share-b+share-c")
    expect(g["answers"]).to eq(3)
    # one free slot machine-wide: the three one-second calls ran one at a time
    expect(g["ms"] >= 2900).to eq(true)
    expect(File.exist?(slots + "/share.1/owner")).to eq(true)
    expect(File.exist?(slots + "/share.2")).to eq(false)
    expect(rung_json_read(out + "/rung.json")["entries"]["share:a"]["shared"]).to eq(true)
    Env.set("RUNG_SLOTS", "")

  it "gives each call read-only copies of the staged files" ->
    d = SPEC_DIR + "/stagecase"
    p = d + "/staged.md"
    rung_write(p, "---\nmodels: lister\nintegrator: integ\nstage: \[notes/a.md, src/x.w\]\nmax_rounds: 1\n---\nTask five.\n")
    out = SPEC_DIR + "/run-stage"
    expect(spec_run([p, "--out", out])).to eq(0)
    w = out + "/steps/r01-s01-lister/calls/lister/work"
    expect(rung_read(w + "/notes/a.md")).to eq("note a\n")
    expect(File.stat(w + "/src/x.w").permissions).to eq(0o444)
    expect(File.stat(out + "/stage/notes/a.md").permissions).to eq(0o444)
    expect(File.stat(d + "/notes/a.md").permissions != 0o444).to eq(true)
    expect(rung_read(out + "/steps/r01-s01-lister/calls/lister/answer.md")).to eq("note a\nx = 1\n")

  it "names usage limits, does not retry them, and skips the model for the rest of the run" ->
    p = spec_prompt("quota.md", "---\nmodels: quota, alpha\nretries: 2\nretry_wait: 0\nmax_rounds: 3\n---\nTask eight.\n")
    out = SPEC_DIR + "/run-quota"
    expect(spec_run([p, "--out", out])).to eq(0)
    q1 = spec_step(out, "r01-s01-quota")["calls"][0]
    expect(q1["reason"]).to eq("usage limit: You've hit your weekly limit · resets Nov 1")
    expect(q1["attempts"]).to eq(1)
    q2 = spec_step(out, "r02-s01-quota")["calls"][0]
    expect(q2["reason"]).to eq("usage limit (earlier in this run): You've hit your weekly limit · resets Nov 1")
    expect(q2["attempts"]).to eq(0)
    expect(spec_count_lines(SPEC_DIR + "/quota.count")).to eq(1)
    expect(rung_json_read(out + "/steps/r01-s01-quota/calls/quota/meta.json")["failure"]).to eq("usage-limit")
    expect(rung_json_read(out + "/status.json")["stop"]).to eq("plateau: no step improved the state in round 2")
    report = rung_read(out + "/report.md")
    expect(report.index("quota: usage limit: You've hit your weekly limit · resets Nov 1 (after 1 attempt); skipped for the rest of this run") != nil).to eq(true)
    expect(report.index("(not called); skipped for the rest of this run") != nil).to eq(true)

  it "names retired models and real errors, not the CLI's noise lines" ->
    p = spec_prompt("gone.md", "---\nmodels: retired, noisy, alpha\nretries: 1\nretry_wait: 0\nmax_rounds: 1\n---\nTask ten.\n")
    out = SPEC_DIR + "/run-gone"
    expect(spec_run([p, "--out", out])).to eq(0)
    r = spec_step(out, "r01-s01-retired")["calls"][0]
    expect(r["reason"]).to eq("model unavailable: API Error: 410 x:0731 was retired on September 25, 2026.")
    expect(r["attempts"]).to eq(1)
    n = spec_step(out, "r01-s02-noisy")["calls"][0]
    expect(n["reason"]).to eq("exit code 1: Error: connection reset by peer")
    expect(n["attempts"]).to eq(2)

  it "pauses when the integrator hits its limit, and resumes with the answers kept" ->
    p = spec_prompt("gate.md", "---\nmodels: delta\nintegrator: gate\nmax_rounds: 1\n---\nTask nine.\n")
    out = SPEC_DIR + "/run-gate"
    expect(spec_run([p, "--out", out])).to eq(3)
    st = rung_json_read(out + "/status.json")
    expect(st["state"]).to eq("paused")
    expect(st["stop"].index("the integrator (gate) is unavailable: usage limit: You've hit your weekly limit") != nil).to eq(true)
    expect(File.exist?(out + "/steps/r01-s01-delta/step.json")).to eq(false)
    expect(rung_json_read(out + "/steps/r01-s01-delta/integrate/meta.json")["attempts"]).to eq(1)
    rung_write(SPEC_DIR + "/gate.open", "")
    expect(spec_run(["--resume", out])).to eq(0)
    expect(rung_json_read(out + "/status.json")["state"]).to eq("finished")
    expect(spec_count_lines(SPEC_DIR + "/delta.count")).to eq(1)
    expect(rung_read(out + "/state.md")).to eq("accepted delta\n")

  it "refuses to reuse a non-empty run directory" ->
    p = SPEC_DIR + "/plateau.md"
    expect(spec_run([p, "--out", SPEC_DIR + "/run-plateau"])).to eq(1)

rung_rm_rf(SPEC_DIR)

spec_summary
