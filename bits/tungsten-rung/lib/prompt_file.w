# rung — the prompt file: Markdown with an optional front-matter block.
#
#   ---
#   models: codex, agy, ollama:glm-5.3 | ollama:kimi-k3, claude
#   integrator: claude
#   stage:
#     - README.md
#     - src/**/*.w
#   timeout: 1800
#   max_rounds: 4
#   deliverable: |
#     One Markdown note: the result, its proof, and how each claim is checked.
#   ---
#   The task, in Markdown.
#
# The front matter is a small YAML subset: `key: value`, `key: [a, b]`,
# `key:` followed by `- item` lines, and `key: |` followed by an indented
# block. Values stay strings (or arrays of strings); rung_prompt_settings
# converts and checks them.

RUNG_FRONT_KEYS = ["models", "integrator", "stage", "files", "timeout", "integrator_timeout", "max_rounds", "deliverable", "retries", "retry_wait", "guard", "guard_mem_mb", "title"]

-> rung_parse_prompt_file(text)
  lines = rung_lines(text)
  front = {}
  body_start = 0
  if lines.size > 0 && lines[0].strip == "---"
    close = nil
    i = 1
    while i < lines.size
      if lines[i].strip == "---" || lines[i].strip == "..."
        close = i
        break
      i += 1
    raise "front matter: no closing --- line" if close == nil
    front = rung_parse_front(lines.slice(1, close - 1))
    body_start = close + 1
  body_lines = []
  i = body_start
  while i < lines.size
    body_lines.push(lines[i])
    i += 1
  {"front" => front, "body" => body_lines.join("\n").strip + "\n"}

-> rung_unquote(v)
  s = v.strip
  if s.size >= 2 && ((s.starts_with?("\"") && s.ends_with?("\"")) || (s.starts_with?("'") && s.ends_with?("'")))
    return s.slice(1, s.size - 2)
  s

-> rung_indent_of(line)
  n = 0
  while n < line.size && line.slice(n, 1) == " "
    n += 1
  n

-> rung_parse_front(lines)
  front = {}
  i = 0
  while i < lines.size
    line = lines[i]
    i += 1
    t = line.strip
    next if t == "" || t.starts_with?("#")
    raise "front matter: unexpected indented line: [t]" if rung_indent_of(line) > 0
    colon = t.index(":")
    raise "front matter: expected key: value, got: [t]" if colon == nil
    key = t.slice(0, colon).strip
    rest = t.slice(colon + 1, t.size - colon - 1).strip
    if rest == "|" || rest == ">"
      block = []
      while i < lines.size && (lines[i].strip == "" || rung_indent_of(lines[i]) > 0)
        block.push(lines[i])
        i += 1
      while block.size > 0 && block[block.size - 1].strip == ""
        block.pop
      ind = 1000
      block.each -> (b)
        if b.strip != "" && rung_indent_of(b) < ind
          ind = rung_indent_of(b)
      text_lines = []
      block.each -> (b)
        text_lines.push(b.size >= ind ? b.slice(ind, b.size - ind) : "")
      front[key] = rest == "|" ? text_lines.join("\n") : text_lines.join(" ")
    elsif rest == ""
      items = []
      while i < lines.size && (lines[i].strip == "" || rung_indent_of(lines[i]) > 0)
        it = lines[i].strip
        i += 1
        next if it == ""
        raise "front matter: under [key]: expected '- item', got: [it]" unless it.starts_with?("-")
        items.push(rung_unquote(it.slice(1, it.size - 1)))
      front[key] = items
    elsif rest.starts_with?("\[") && rest.ends_with?("\]")
      items = []
      rest.slice(1, rest.size - 2).split(",").each -> (x)
        items.push(rung_unquote(x)) unless x.strip == ""
      front[key] = items
    else
      front[key] = rung_unquote(rest)
  front

# Front-matter keys rung does not know (reported by `rung check`).
-> rung_unknown_front_keys(front)
  out = []
  front.keys.each -> (k)
    out.push(k) unless rung_contains?(RUNG_FRONT_KEYS, k)
  out

# The task's title: its first Markdown heading, else the file's stem.
-> rung_task_title(body, fallback)
  rung_lines(body).each -> (l)
    t = l.strip
    if t.starts_with?("#")
      while t.starts_with?("#")
        t = t.slice(1, t.size - 1)
      return t.strip if t.strip != ""
  fallback

# ---- model lists ----------------------------------------------------------------------

# "codex, ollama:a | ollama:b, claude" (or an array of such entries) ->
# [["codex"], ["ollama:a", "ollama:b"], ["claude"]]: one entry per step of
# a round; `|` joins models that run as one parallel group.
-> rung_parse_ladder(spec)
  entries = []
  if spec.is_a?(Array)
    spec.each -> (e)
      e.to_s.split(",").each -> (x)
        entries.push(x)
  else
    spec.to_s.split(",").each -> (x)
      entries.push(x)
  steps = []
  entries.each -> (e)
    group = []
    e.split("|").each -> (m)
      name = m.strip
      group.push(name) unless name == ""
    steps.push(group) if group.size > 0
  steps

-> rung_ladder_text(steps)
  parts = []
  steps.each -> (g)
    parts.push(g.join(" | "))
  parts.join(", ")

-> rung_ladder_models(steps)
  out = []
  steps.each -> (g)
    g.each -> (m)
      rung_uniq_push(out, m)
  out

-> rung_truthy?(v)
  return v if v == true || v == false
  s = v.to_s.strip.downcase
  s == "true" || s == "yes" || s == "on" || s == "1"

-> rung_falsy?(v)
  return !v if v == true || v == false
  s = v.to_s.strip.downcase
  s == "false" || s == "no" || s == "off" || s == "0" || s == ""

-> rung_int(v, what)
  return v if v.is_a?(Integer)
  s = v.to_s.strip
  raise "[what] must be a whole number, got '[s]'" unless rung_toml_int?(s)
  s.to_i
