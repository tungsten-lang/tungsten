# rung — the prompts rung writes, and the integrator's reply format.
#
# Everything here is generic: no names, emails or machine paths go into a
# prompt beyond the task text the user wrote and the model names.

RUNG_DEFAULT_DELIVERABLE = "One self-contained Markdown answer to the task."

RUNG_MODEL_TEMPLATE = <<~EOT
  You are one rung of a ladder: independent models take turns on the task below, and after each turn an integrator merges the answer into the current state, the ladder's best answer so far. This is round {{ROUND}}, step {{STEP}}.

  # Task

  {{TASK}}

  # Deliverable

  {{DELIVERABLE}}

  # Current state

  {{STATE}}

  # Your rung

  {{ASK}}

  - {{FIRST_RULE}}
  - Label each claim by how it is established: checked by you (say how), computed, cited (give the source), or conjectured.
  - {{FILES}}
  - Do not modify, build or run anything, and start no background processes: reason, or write code for a person to run.
  - Give your complete answer in Markdown as your final message. Do not write files.
EOT

RUNG_INTEGRATOR_TEMPLATE = <<~EOT
  You are the integrator of a ladder of models. Independent models take turns improving an answer to the task below. After each turn you merge the new answer(s) into the current state: the ladder's single best answer so far.

  # Task

  {{TASK}}

  # Deliverable

  {{DELIVERABLE}}

  # Current state

  {{STATE}}

  # New answers (round {{ROUND}}, step {{STEP}})

  {{ANSWERS}}

  # What to do

  1. Check each new answer against the current state and the task. Re-derive or spot-check what you can. {{FILES}}
  2. Adopt only what is genuinely better: corrections, new results, stronger or simpler arguments, verified facts. Keep everything in the state that is still correct. Drop errors, padding and unsupported claims.
  3. Add nothing of your own beyond what reconciling the answers needs.
  4. Keep every claim labeled by how it is established, and list what still needs verification.
  5. Do not modify, build or run anything, and start no background processes.

  Reply with exactly these two blocks and nothing after them:

  <rung-state>
  The complete updated state: one self-contained Markdown document that meets the deliverable (not a diff, not a list of changes). Leave this block empty if nothing improved.
  </rung-state>
  <rung-verdict>
  improved: yes or no
  credit: {{CREDIT}}
  changed: one sentence on what changed, or "nothing"
  verify:
  - each claim that still needs verification, one per line
  </rung-verdict>
EOT

# Single-pass {{NAME}} substitution: values are inserted verbatim and never
# rescanned, so a task that itself contains "{{STATE}}" stays as written.
-> rung_fill(template, vars)
  out = ""
  i = 0
  while true
    j = template.index("{{", i)
    if j == nil
      out = out + template.slice(i, template.size - i)
      return out
    k = template.index("}}", j + 2)
    if k == nil
      out = out + template.slice(i, template.size - i)
      return out
    name = template.slice(j + 2, k - j - 2)
    v = vars[name]
    if v == nil
      out = out + template.slice(i, k + 2 - i)
    else
      out = out + template.slice(i, j - i) + v.to_s
    i = k + 2

-> rung_files_line(rels, who)
  return "No files are staged for this task." if rels.size == 0
  shown = []
  i = 0
  while i < rels.size && i < 40
    shown.push(rels[i])
    i += 1
  more = rels.size > 40 ? " and " + (rels.size - 40).to_s + " more" : ""
  "Your working directory holds read-only copies of the staged files (" + shown.join(", ") + more + "); read them as needed."

# ctx: task, deliverable, state (nil when no answer is accepted yet),
# round, step, rels.
-> rung_model_prompt(ctx)
  has = !rung_blank?(ctx["state"])
  vars = {
    "ROUND" => ctx["round"].to_s,
    "STEP" => ctx["step"].to_s,
    "TASK" => ctx["task"].strip,
    "DELIVERABLE" => rung_blank?(ctx["deliverable"]) ? RUNG_DEFAULT_DELIVERABLE : ctx["deliverable"].strip,
    "STATE" => has ? ctx["state"].strip : "No answer yet: yours is the first rung.",
    "ASK" => has ? "Improve on the current state above." : "No model has answered yet: give the best answer you can.",
    "FIRST_RULE" => has ? "Improve on the current state: correct errors, fill gaps, tighten or verify arguments, or find a stronger result. Keep what is already right instead of restating it at length. If you cannot improve it, say so plainly and say what you checked." : "Answer the whole task carefully; where you are unsure, say so and say what would settle it.",
    "FILES" => rung_files_line(ctx["rels"], "model")
  }
  rung_fill(RUNG_MODEL_TEMPLATE, vars).strip + "\n"

# answers: [[model, text], ...]
-> rung_integrator_prompt(ctx, answers)
  has = !rung_blank?(ctx["state"])
  parts = []
  names = []
  answers.each -> (a)
    parts.push("## Answer from " + a[0] + "\n\n" + a[1].strip)
    names.push(a[0])
  credit = names.size == 1 ? names[0] + " if its answer contributed, else none" : "the answers that contributed, comma-separated, from: " + names.join(", ") + " (none if nothing improved)"
  files = ctx["rels"].size == 0 ? "" : "Your working directory holds read-only copies of the staged files."
  vars = {
    "ROUND" => ctx["round"].to_s,
    "STEP" => ctx["step"].to_s,
    "TASK" => ctx["task"].strip,
    "DELIVERABLE" => rung_blank?(ctx["deliverable"]) ? RUNG_DEFAULT_DELIVERABLE : ctx["deliverable"].strip,
    "STATE" => has ? ctx["state"].strip : "(empty: no answer has been accepted yet)",
    "ANSWERS" => parts.join("\n\n"),
    "CREDIT" => credit,
    "FILES" => files
  }
  rung_fill(RUNG_INTEGRATOR_TEMPLATE, vars).strip + "\n"

# ---- the integrator's reply -----------------------------------------------------------

# A verdict line's key, tolerant of list markers and bold: "- **improved:** yes".
-> rung_verdict_key(line)
  t = rung_replace(line.strip, "**", "")
  t = rung_replace(t, "__", "")
  while t.starts_with?("-") || t.starts_with?("*")
    t = t.slice(1, t.size - 1).strip
  c = t.index(":")
  return nil if c == nil
  key = t.slice(0, c).strip.downcase
  return nil unless key == "improved" || key == "credit" || key == "changed" || key == "verify"
  [key, t.slice(c + 1, t.size - c - 1).strip]

# {"improved", "credit", "changed", "verify", "state"} or nil when the reply
# has no verdict block.
-> rung_parse_integration(text, members)
  return nil if text == nil
  open_v = "<rung-verdict>"
  close_v = "</rung-verdict>"
  vs = text.rindex(open_v)
  ve = text.rindex(close_v)
  return nil if vs == nil || ve == nil || ve < vs
  vblock = text.slice(vs + open_v.size, ve - vs - open_v.size)
  open_s = "<rung-state>"
  close_s = "</rung-state>"
  ss = text.index(open_s)
  se = text.rindex(close_s)
  state = ""
  if ss != nil && se != nil && se > ss
    state = text.slice(ss + open_s.size, se - ss - open_s.size).strip
  improved = false
  credit = []
  changed = ""
  verify = []
  in_verify = false
  rung_lines(vblock).each -> (line)
    kv = rung_verdict_key(line)
    if kv != nil
      in_verify = kv[0] == "verify"
      v = kv[1]
      if kv[0] == "improved"
        w = v.downcase
        improved = w.starts_with?("yes") || w.starts_with?("true") || w == "y"
      elsif kv[0] == "credit"
        v.split(",").each -> (c)
          name = c.strip
          name = name.slice(1, name.size - 2) if name.size > 1 && name.starts_with?("`") && name.ends_with?("`")
          rung_uniq_push(credit, name) unless name == "" || name.downcase == "none" || name == "-"
      elsif kv[0] == "changed"
        changed = v
      elsif kv[0] == "verify" && v != "" && v.downcase != "none" && v != "-"
        verify.push(v)
    elsif in_verify
      t = line.strip
      if t.starts_with?("-") || t.starts_with?("*")
        item = t.slice(1, t.size - 1).strip
        verify.push(item) unless item == "" || item.downcase == "none"
  # credit only names that ran in this step; a lone member is credited
  # whenever the step improved
  real = []
  credit.each -> (c)
    real.push(c) if rung_contains?(members, c)
  if improved && real.size == 0
    real = members.size == 1 ? [members[0]] : credit
  notes = []
  if improved && state == ""
    improved = false
    notes.push("the integrator said improved but returned no state; state kept")
  result = {"improved" => improved, "credit" => improved ? real : [], "changed" => changed, "verify" => verify, "state" => state, "notes" => notes}
  result
