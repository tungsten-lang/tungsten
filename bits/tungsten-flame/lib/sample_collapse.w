# sample_collapse.w — Collapse macOS `sample(1)` / `spindump` call graphs
# into folded stacks.
#
# Turns a `sample` / `spindump` "Call graph:" section into the canonical
# "root;mid;leaf <count>" folded text every other module in this bit speaks.

use folded

in Tungsten:Flame

+ SampleCollapse

  # ---- Public entry point ----

  # macOS `sample` / `spindump` text -> folded-stack string, one
  # "root;...;leaf <count>" line per stack with a positive self count, sorted
  # lexicographically for deterministic golden-file output.
  -> .collapse(text)
    lines = text.split("\n")
    start_i = self.section_start(lines)
    stacks = {}
    indents = []
    names = []
    selfs = []
    i = start_i
    while i < lines.size()
      line = lines[i]
      if self.section_end?(line)
        break
      parsed = self.parse_line(line)
      if parsed != nil
        self.push_frame(indents, names, selfs, parsed, stacks)
      i = i + 1
    while indents.size() > 0
      self.finish_top(indents, names, selfs, stacks)
    self.emit(stacks)

  # ---- Tree walk ----

  # Open a frame: close any frames at depth >= this one (they are complete),
  # subtract this frame's inclusive count from its parent's running self, then
  # push it. `parsed` is { indent:, count:, name: }.
  -> .push_frame(indents, names, selfs, parsed, stacks)
    d = parsed[:indent]
    c = parsed[:count]
    while indents.size() > 0 && indents.last() >= d
      self.finish_top(indents, names, selfs, stacks)
    if selfs.size() > 0
      li = selfs.size() - 1
      selfs[li] = selfs[li] - c
    indents.push(d)
    names.push(parsed[:name])
    selfs.push(c)

  # Close the top frame: if its self count is positive, emit the current stack
  # path (root -> this frame) with that count, summing frames that recur across
  # subtrees. Then pop it off the parallel stacks.
  -> .finish_top(indents, names, selfs, stacks)
    li = selfs.size() - 1
    sc = selfs[li]
    if sc > 0
      folded = names.join(";")
      if stacks.has_key?(folded)
        stacks[folded] = stacks[folded] + sc
      else
        stacks[folded] = sc
    indents.pop
    names.pop
    selfs.pop

  # ---- Line parsing ----

  # Parse one call-graph line into { indent:, count:, name: }, or nil for a
  # non-frame line (blank, header, annotation).
  -> .parse_line(line)
    indent = self.leading_indent(line)
    rest0 = line.slice(indent, line.size())
    sp = rest0.index(" ")
    if sp == nil
      return nil
    count_str = rest0.slice(0, sp)
    if !self.all_digits?(count_str)
      return nil
    count = count_str.to_i()
    symbol_part = rest0.slice(sp + 1, rest0.size()).strip()
    name = self.extract_symbol(symbol_part)
    if name.size() == 0
      return nil
    { indent: indent, count: count, name: name }

  # Number of leading indent/tree-marker characters before content begins.
  -> .leading_indent(line)
    i = 0
    n = line.size()
    while i < n
      c = line.slice(i, 1)
      if c == " " || c == "+" || c == "!" || c == "*"
        i = i + 1
      else
        break
    i

  # Extract the symbol name from the post-count remainder, cutting at the first
  # decoration delimiter that appears: " (in <lib>)", a " + <offset>", a
  # " [0x<addr>]", or a two-space label gap (thread/queue lines).
  -> .extract_symbol(s)
    cut = s.size()
    a = s.index(" (in ")
    if a != nil && a < cut
      cut = a
    b = s.index(" \[0x")
    if b != nil && b < cut
      cut = b
    off = self.offset_index(s)
    if off != nil && off < cut
      cut = off
    gap = s.index("  ")
    if gap != nil && gap < cut
      cut = gap
    s.slice(0, cut).strip()

  # Index of the " + <offset>" delimiter — the first " + " immediately followed
  # by a digit (so demangled "operator+ (in ...)" style names aren't cut).
  -> .offset_index(s)
    idx = s.index(" + ")
    if idx == nil
      return nil
    nextc = s.slice(idx + 3, 1)
    if self.is_digit?(nextc)
      return idx
    nil

  # ---- Section boundaries ----

  -> .section_start(lines)
    i = 0
    while i < lines.size()
      if lines[i].include?("Call graph")
        return i + 1
      i = i + 1
    0

  -> .section_end?(line)
    t = line.strip()
    if t.size() == 0
      return false
    t.starts_with?("Total number in stack") || t.starts_with?("Sort by top of stack") || t.starts_with?("Binary Images")

  # ---- Emit & Helpers ----

  -> .emit(stacks)
    Tungsten:Flame:Folded.emit(stacks)

  -> .all_digits?(s)
    Tungsten:Flame:Folded.all_digits?(s)

  -> .is_digit?(ch)
    ch.size() == 1 && ch >= "0" && ch <= "9"
