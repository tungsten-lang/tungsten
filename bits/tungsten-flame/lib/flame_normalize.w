# flame_normalize.w — Canonicalize a folded profile: collapse recursion and
# merge frame-name variants before viewing.

use folded

in Tungsten:Flame

+ FlameNormalize

  # ---- Parsing ----

  -> .parse_folded(text)
    Tungsten:Flame:Folded.parse(text)

  # ---- Recursion collapse ----

  # Collapse runs of consecutive identical frames within each stack, then
  # re-aggregate and sort.
  -> .collapse_recursion(text)
    map = self.parse_folded(text)[:map]
    out = {}
    keys = map.keys()
    i = 0
    while i < keys.size()
      stack = keys[i]
      frames = stack.split(";")
      collapsed = self.dedup_consecutive(frames)
      new_stack = collapsed.join(";")
      if out.has_key?(new_stack)
        out[new_stack] = out[new_stack] + map[stack]
      else
        out[new_stack] = map[stack]
      i = i + 1
    self.emit(out)

  # Drop each frame equal to the one immediately before it (A A A B B -> A B).
  -> .dedup_consecutive(frames)
    out = []
    i = 0
    while i < frames.size()
      f = frames[i]
      if out.size() == 0 || out.last() != f
        out.push(f)
      i = i + 1
    out

  # ---- Symbol rewrite ----

  # Apply substring rewrite rules to every frame of every stack, then
  # re-aggregate and sort.
  -> .rewrite(text, rules_spec)
    rules = self.parse_rules(rules_spec)
    map = self.parse_folded(text)[:map]
    out = {}
    keys = map.keys()
    i = 0
    while i < keys.size()
      stack = keys[i]
      frames = stack.split(";")
      new_frames = []
      fi = 0
      while fi < frames.size()
        nf = self.apply_rules(frames[fi], rules)
        if nf != ""
          new_frames.push(nf)
        fi = fi + 1
      if new_frames.size() > 0
        new_stack = new_frames.join(";")
        if out.has_key?(new_stack)
          out[new_stack] = out[new_stack] + map[stack]
        else
          out[new_stack] = map[stack]
      i = i + 1
    self.emit(out)

  -> .apply_rules(frame, rules)
    f = frame
    i = 0
    while i < rules.size()
      r = rules[i]
      f = self.replace_all(f, r[0], r[1])
      i = i + 1
    f

  -> .parse_rules(rules_spec)
    rules = []
    if rules_spec == nil
      return rules
    s = rules_spec.to_s()
    if s == ""
      return rules
    parts = s.split(";")
    i = 0
    while i < parts.size()
      p = parts[i].strip()
      arrow = p.index("=>")
      if arrow != nil
        old = p.slice(0, arrow)
        new = p.slice(arrow + 2, p.size())
        if old != ""
          rules.push([old, new])
      i = i + 1
    rules

  # Replace every non-overlapping occurrence of `old` with `new` in `s`
  # without rescanning inserted replacement text.
  -> .replace_all(s, old, new)
    if old == ""
      return s
    out = ""
    rest = s
    idx = rest.index(old)
    while idx != nil
      out = out + rest.slice(0, idx) + new
      rest = rest.slice(idx + old.size(), rest.size())
      idx = rest.index(old)
    out + rest

  # ---- CLI pipeline ----

  -> .apply(text, do_recursion, rules_spec)
    result = text
    if rules_spec != nil && rules_spec.to_s() != ""
      result = self.rewrite(result, rules_spec)
    if do_recursion
      result = self.collapse_recursion(result)
    result

  # ---- Emit ----

  -> .emit(map)
    Tungsten:Flame:Folded.emit(map)
