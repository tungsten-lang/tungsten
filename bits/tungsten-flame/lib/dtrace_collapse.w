# dtrace_collapse.w — Collapse DTrace ustack()/stack() aggregation output
# into folded stacks.

use folded

in Tungsten:Flame

+ DtraceCollapse

  # ---- Public entry point ----

  # DTrace aggregation text -> folded-stack string, one "root;...;leaf <count>"
  # line per unique stack, sorted lexicographically for deterministic
  # golden-file output.
  -> .collapse(text)
    lines = text.split("\n")
    stacks = {}
    current = []
    i = 0
    n = lines.size()
    while i < n
      stripped = lines[i].strip()
      if stripped.size() == 0
        current = []
      elsif self.all_digits?(stripped)
        self.flush(current, stripped.to_i(), stacks)
        current = []
      elsif self.frame_line?(stripped)
        current.push(self.parse_frame_name(stripped))
      i = i + 1
    self.emit(stacks)

  # Record one completed leaf-first stack under its aggregation count: reverse
  # to root-first, join, and sum into any identical stack.
  -> .flush(frames, count, stacks)
    if frames.size() == 0
      return
    if count <= 0
      return
    folded = frames.reverse().join(";")
    if stacks.has_key?(folded)
      stacks[folded] = stacks[folded] + count
    else
      stacks[folded] = count

  # ---- Line classification ----

  -> .frame_line?(stripped)
    if stripped.include?("`")
      return true
    stripped.starts_with?("0x")

  # ---- Frame naming ----

  -> .parse_frame_name(raw)
    p = raw.rindex("+")
    if p == nil
      return raw
    suffix = raw.slice(p + 1, raw.size())
    if self.is_offset?(suffix)
      return raw.slice(0, p)
    raw

  -> .is_offset?(s)
    if s.size() == 0
      return false
    if s.starts_with?("0x")
      return self.all_hex?(s.slice(2, s.size()))
    self.all_digits?(s)

  # ---- Emit & Helpers ----

  -> .emit(stacks)
    Tungsten:Flame:Folded.emit(stacks)

  -> .all_digits?(s)
    Tungsten:Flame:Folded.all_digits?(s)

  -> .all_hex?(s)
    n = s.size()
    if n == 0
      return false
    i = 0
    while i < n
      b = s.byte_at(i)
      if !((b >= 48 && b <= 57) || (b >= 97 && b <= 102) || (b >= 65 && b <= 70))
        return false
      i = i + 1
    true
