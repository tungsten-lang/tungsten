# flame_split.w — Per-thread / per-root partition of a folded profile.

use folded

in Tungsten:Flame

+ FlameSplit

  # ---- Parsing & Single-Pass Partition ----

  -> .parse_folded(text)
    Tungsten:Flame:Folded.parse(text)

  # The ROOT frame of a folded stack: everything before the first ";".
  -> .root_of(stack)
    sep = stack.index(";")
    if sep == nil
      return stack
    stack.slice(0, sep)

  # Partition folded text in a single pass into:
  #   { groups: { root => { stack => count } },
  #     totals: { root => sample_total },
  #     counts: { root => distinct_stack_count },
  #     total:  grand_total }
  -> .partition(text)
    parsed = self.parse_folded(text)
    map = parsed[:map]
    groups = {}
    totals = {}
    counts = {}
    keys = map.keys()
    i = 0
    while i < keys.size()
      stack = keys[i]
      c = map[stack]
      r = self.root_of(stack)
      if !groups.has_key?(r)
        groups[r] = {}
        totals[r] = 0
        counts[r] = 0
      groups[r][stack] = c
      totals[r] = totals[r] + c
      counts[r] = counts[r] + 1
      i = i + 1
    { groups: groups, totals: totals, counts: counts, total: parsed[:total] }

  # ---- Partition views ----

  # The distinct root frames present, sorted lexicographically.
  -> .roots(text)
    self.partition(text)[:totals].keys().sort()

  # Sample total per root: { root => count }.
  -> .totals(text)
    self.partition(text)[:totals]

  # Distinct-stack count per root: { root => stacks }.
  -> .stack_counts(text)
    self.partition(text)[:counts]

  # Select one root's stacks as folded text.
  -> .select(text, root)
    groups = self.partition(text)[:groups]
    if !groups.has_key?(root)
      return ""
    self.emit(groups[root])

  # The whole partition as [root, folded_text] pairs, in sorted-root order,
  # computed in a single pass.
  -> .groups(text)
    part = self.partition(text)
    groups = part[:groups]
    names = groups.keys().sort()
    out = []
    i = 0
    while i < names.size()
      r = names[i]
      out.push([r, self.emit(groups[r])])
      i = i + 1
    out

  # ---- Listing ----

  # Listing rows: [root, samples, stacks], sorted by samples descending, ties
  # broken by root name ascending.
  -> .rows(text)
    self.rows_from_partition(self.partition(text))

  -> .rows_from_partition(part)
    totals = part[:totals]
    counts = part[:counts]
    names = totals.keys()
    rows = []
    i = 0
    while i < names.size()
      r = names[i]
      rows.push([r, totals[r], counts[r]])
      i = i + 1
    rows.sort_by -> (row) [-row[1], row[0]]

  # Printable listing — which roots exist and how much of the profile each
  # holds.
  -> .list_report(text, color)
    part = self.partition(text)
    total = part[:total]

    bold  = color ? "\e[1m" : ""
    dim   = color ? "\e[2m" : ""
    reset = color ? "\e[0m" : ""
    name_color = color ? "\e[38;5;67m" : ""

    out = []
    out.push("")
    if total == 0
      out.push("  " + bold + "Roots" + reset + "  " + dim + "(no samples)" + reset)
      out.push("")
      return out.join("\n")

    rows = self.rows_from_partition(part)
    out.push("  " + bold + "Roots" + reset + "  " + dim + "(" + rows.size().to_s() + " roots, " + total.to_s() + " samples)" + reset)
    out.push("")
    out.push("  " + bold + "  SHARE   SAMPLES  STACKS  ROOT" + reset)

    i = 0
    while i < rows.size()
      row = rows[i]
      line = "  " + bold + self.fmt_pct(row[1], total) + "%" + reset
      line = line + "  " + self.pad_left(row[1].to_s(), 8)
      line = line + "  " + self.pad_left(row[2].to_s(), 6)
      line = line + "  " + name_color + row[0] + reset
      out.push(line)
      i = i + 1

    out.push("")
    out.join("\n")

  # ---- Helpers ----

  -> .slug(name)
    ok = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
    out = ""
    i = 0
    while i < name.size()
      ch = name.slice(i, 1)
      if ok.include?(ch)
        out = out + ch
      else
        out = out + "_"
      i = i + 1
    if out == ""
      return "root"
    out

  -> .fmt_pct(n, total)
    Tungsten:Flame:Folded.fmt_pct_padded(n, total)

  -> .pad_left(s, width)
    Tungsten:Flame:Folded.pad_left(s, width)

  -> .emit(map)
    Tungsten:Flame:Folded.emit(map)
