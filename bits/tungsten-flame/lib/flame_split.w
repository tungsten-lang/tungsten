# flame_split.w — Per-thread / per-root partition of a folded profile.
#
# Every reshape in this bit so far collapses a profile along the DEPTH axis:
# pattern filters (flame_filter), the long-tail threshold (flame_threshold),
# name canonicalization (flame_normalize). None of them touch the axis a
# concurrent program forces on you: BREADTH. A real profile of a threaded
# process — anything the macOS `sample` collapser produces, where each thread
# becomes its own folded root ("Thread_1;start;work 30") — is several
# independent profiles stacked into one file. Viewed whole, the flame graph is
# a row of unrelated towers, every percentage is diluted by threads you do not
# care about, and "what is thread 2 actually doing" is unanswerable.
#
# Splitting by root is how every real profiler handles this: Instruments has a
# thread picker, speedscope a per-thread profile list, pprof `-tagfocus`,
# perf `--sort comm`. This module is that operation as a first-class, testable,
# folded-text → folded-text transform. It partitions stacks by their ROOT
# frame (the first ";"-separated segment — a thread label, a process name, or
# whatever the collapser put first) into separate named groups.
#
# The partition is LOSSLESS by construction: a stack's root is a pure function
# of the stack, so every stack lands in exactly one group, no stack is dropped
# or duplicated, and the group totals sum to the input total exactly. This is
# the property `--grep` cannot offer (it deletes samples) and the reason a
# split is safe to reason about — nothing hides between the groups.
#
# Three views, all over the same parse:
#
#   - .list_report(text, color)  listing: which roots exist, their sample
#                                totals, share, and stack counts. The "what
#                                threads are in this file" question you ask
#                                before anything else.
#   - .select(text, root)        select: just one root's stacks, as folded
#                                text. Whole stacks are kept (the root frame
#                                included), so the result is a valid profile
#                                that pipes into every other view — SVG,
#                                speedscope, --hot, a diff, another filter.
#                                Compose with --subtree to re-root it.
#   - .groups(text)              the full partition as [root, folded] pairs in
#                                sorted-root order, for writing one file per
#                                thread in a single pass.
#
# Output is re-aggregated (duplicate stacks summed) and sorted by stack name,
# matching FlameFilter / FlameThreshold / FlameDiff for deterministic,
# golden-file output.
#
# CLI: `flame --split FILE.folded` prints the listing; `flame --split -o PREFIX
# FILE.folded` writes PREFIX.<root>.folded per root; `flame --root NAME
# FILE.folded` emits just that root's stacks. A pure-text mode (no compile, no
# profiling) like --grep / --diff / --hot; several files aggregate first, so
# N runs partition as one.

in Tungsten:Flame

+ FlameSplit

  # ---- Parsing ----

  # Parse folded text into { map: { stack => count }, total: N }. Duplicate
  # stacks are summed; lines with no positive count are ignored — matching
  # FlameFilter.parse_folded / FlameThreshold.parse_folded so every module
  # agrees on what a sample is. Count split with rindex(" ") so frame names
  # containing spaces (e.g. "block in Array#tally") survive.
  -> .parse_folded(text)
    map = {}
    total = 0
    lines = text.split("\n")
    i = 0
    while i < lines.size()
      line = lines[i].strip()
      if line.size() > 0
        sp = line.rindex(" ")
        if sp != nil
          stack = line.slice(0, sp)
          count = line.slice(sp + 1, line.size()).to_i()
          if count > 0
            if map.has_key?(stack)
              map[stack] = map[stack] + count
            else
              map[stack] = count
            total = total + count
      i = i + 1
    { map: map, total: total }

  # ---- Root extraction ----

  # The ROOT frame of a folded stack: everything before the first ";". A stack
  # with no ";" is a single frame and is its own root. The segment is returned
  # byte-for-byte as the profile recorded it (no normalization), so a thread
  # label round-trips exactly and .select can match it.
  -> .root_of(stack)
    sep = stack.index(";")
    if sep == nil
      return stack
    stack.slice(0, sep)

  # ---- Partition views ----

  # The distinct root frames present, sorted lexicographically (deterministic
  # ordering for both the listing and the one-file-per-root walk).
  -> .roots(text)
    map = self.parse_folded(text)[:map]
    seen = {}
    keys = map.keys()
    i = 0
    while i < keys.size()
      seen[self.root_of(keys[i])] = true
      i = i + 1
    self.sort_strings(seen.keys())

  # Sample total per root: { root => count }. Because each stack contributes
  # its count to exactly one root, these values sum to the grand total — the
  # losslessness guarantee, in one hash.
  -> .totals(text)
    map = self.parse_folded(text)[:map]
    out = {}
    keys = map.keys()
    i = 0
    while i < keys.size()
      r = self.root_of(keys[i])
      if out.has_key?(r)
        out[r] = out[r] + map[keys[i]]
      else
        out[r] = map[keys[i]]
      i = i + 1
    out

  # Distinct-stack count per root: { root => stacks }. Complements .totals in
  # the listing — a root can hold many samples in few stacks (a hot loop) or
  # few samples across many (a diffuse tail).
  -> .stack_counts(text)
    map = self.parse_folded(text)[:map]
    out = {}
    keys = map.keys()
    i = 0
    while i < keys.size()
      r = self.root_of(keys[i])
      if out.has_key?(r)
        out[r] = out[r] + 1
      else
        out[r] = 1
      i = i + 1
    out

  # Select one root's stacks as folded text. Whole stacks are kept, root frame
  # and all, so the result is a valid standalone profile for any other view.
  # Matching is exact on the root segment (not a substring), so "Thread_1"
  # never picks up "Thread_10". An unknown root yields "" (no stacks).
  -> .select(text, root)
    map = self.parse_folded(text)[:map]
    out = {}
    keys = map.keys()
    i = 0
    while i < keys.size()
      stack = keys[i]
      if self.root_of(stack) == root
        out[stack] = map[stack]
      i = i + 1
    self.emit(out)

  # The whole partition as [root, folded_text] pairs, in sorted-root order.
  # Concatenating every pair's text reproduces the input, re-aggregated and
  # regrouped — nothing added, nothing lost.
  -> .groups(text)
    names = self.roots(text)
    out = []
    i = 0
    while i < names.size()
      out.push([names[i], self.select(text, names[i])])
      i = i + 1
    out

  # ---- Listing ----

  # Listing rows: [root, samples, stacks], sorted by samples descending, ties
  # broken by root name ascending (deterministic, golden-file-friendly).
  -> .rows(text)
    totals = self.totals(text)
    counts = self.stack_counts(text)
    names = totals.keys()
    rows = []
    i = 0
    while i < names.size()
      r = names[i]
      rows.push([r, totals[r], counts[r]])
      i = i + 1
    self.sort_rows(rows)

  # Printable listing — which roots exist and how much of the profile each
  # holds. The orientation view: run it before deciding which thread to look
  # at. Empty / count-less input yields a "(no samples)" line, not a crash.
  -> .list_report(text, color)
    parsed = self.parse_folded(text)
    total = parsed[:total]

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

    rows = self.rows(text)
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

  # Filesystem-safe form of a root name, for the one-file-per-root output
  # ("DispatchQueue_1: com.apple.main-thread" → "DispatchQueue_1__com.apple.main-thread").
  # Anything outside letters/digits/dot/underscore/hyphen becomes "_", so a
  # thread label carrying spaces, slashes or colons cannot escape the prefix
  # directory or collide with a shell metacharacter. An entirely stripped name
  # falls back to "root".
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

  # Percentage with one decimal via integer math (avoids BigDecimal sci
  # notation), left-padded to a 5-char field for column alignment — matching
  # HotFrames.fmt_pct so the two reports line up.
  -> .fmt_pct(n, total)
    if total == 0
      return "  0.0"
    pct_x10 = n * 1000 / total
    whole = pct_x10 / 10
    frac = pct_x10 - whole * 10
    s = whole.to_s() + "." + frac.to_s()
    while s.size() < 5
      s = " " + s
    s

  # Left-pad a string to `width` for column alignment.
  -> .pad_left(s, width)
    out = s
    while out.size() < width
      out = " " + out
    out

  # Insertion sort of [root, samples, stacks] rows: samples desc, then root
  # name asc.
  -> .sort_rows(rows)
    j = 1
    while j < rows.size()
      key = rows[j]
      k = j - 1
      while k >= 0 && self.ranks_after(rows[k], key)
        rows[k + 1] = rows[k]
        k = k - 1
      rows[k + 1] = key
      j = j + 1
    rows

  # True when row `x` should sort AFTER row `y`: fewer samples, or equal
  # samples with a later-sorting root name.
  -> .ranks_after(x, y)
    if x[1] != y[1]
      return x[1] < y[1]
    x[0] > y[0]

  # ---- Emit ----

  # Render a { stack => count } map back to folded text, one "stack count" line
  # per stack, sorted lexicographically by stack name for deterministic output
  # (matching FlameFilter.emit / FlameThreshold.emit).
  -> .emit(map)
    keys = self.sort_strings(map.keys())
    out = []
    i = 0
    while i < keys.size()
      k = keys[i]
      out.push(k + " " + map[k].to_s())
      i = i + 1
    out.join("\n")

  # Lexicographic insertion sort (deterministic golden output).
  -> .sort_strings(xs)
    arr = []
    i = 0
    while i < xs.size()
      arr.push(xs[i])
      i = i + 1
    j = 1
    while j < arr.size()
      key = arr[j]
      k = j - 1
      while k >= 0 && arr[k] > key
        arr[k + 1] = arr[k]
        k = k - 1
      arr[k + 1] = key
      j = j + 1
    arr
