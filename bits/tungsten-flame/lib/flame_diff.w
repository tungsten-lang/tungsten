# flame_diff.w — Differential profiling: compare two folded profiles.
#
# The complement to a single flame graph: given a BEFORE and an AFTER
# folded-stack profile (the same "root;mid;leaf <count>" text every other
# module in this bit speaks), it answers "what got hotter / what got
# cooler?" — the question you actually ask after an optimization.
#
# Two runs almost never collect the same number of samples, so a raw
# subtraction of counts is misleading. Normalization scales the BEFORE
# counts to the AFTER profile's sample total (integer math, difffolded -n
# semantics) so a frame's change is measured against a common baseline.
#
# Outputs, all text (no SVG — the interactive renderer is flame_svg.w's
# job; this module stays a pure analysis layer):
#   - .diff / .diff_normalized  → folded "stack delta" text (one trailing
#     number keeps the rindex-space folded contract intact even when frame
#     names contain spaces, e.g. "block in Array#tally").
#   - .rank_frames              → per-frame inclusive deltas, ranked.
#   - .report                   → a printable "Regressed / Improved" summary.

in Tungsten:Flame

+ FlameDiff

  # ---- Parsing ----

  # Parse folded text into { map: { stack => count }, total: N }. Duplicate
  # stacks are summed; lines with no positive count are ignored (matching
  # FlameSvg.build_tree, so the two agree on what a sample is).
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

  # Per-frame INCLUSIVE counts from a { stack => count } map: every frame in
  # a stack receives that stack's count, but a frame that recurses within a
  # single stack is counted only once (inclusive time is per-sample, not
  # per-appearance). Returns { frame => inclusive_count }.
  -> .inclusive_from_map(map)
    incl = {}
    keys = map.keys()
    i = 0
    while i < keys.size()
      stack = keys[i]
      count = map[stack]
      frames = stack.split(";")
      seen = {}
      fi = 0
      while fi < frames.size()
        f = frames[fi]
        if !seen.has_key?(f)
          seen[f] = true
          if incl.has_key?(f)
            incl[f] = incl[f] + count
          else
            incl[f] = count
        fi = fi + 1
      i = i + 1
    incl

  # Inclusive frame counts straight from folded text.
  -> .frame_inclusive(text)
    parsed = self.parse_folded(text)
    self.inclusive_from_map(parsed[:map])

  # ---- Per-stack diff ----

  # Raw per-stack signed delta (after - before), no normalization.
  -> .diff(before_text, after_text)
    self.diff_scaled(before_text, after_text, false)

  # Per-stack signed delta with before scaled to after's sample total.
  -> .diff_normalized(before_text, after_text)
    self.diff_scaled(before_text, after_text, true)

  # For every stack present in EITHER profile, emit "stack delta" where
  # delta = after - before (before optionally normalized). Lines are sorted
  # by stack name for deterministic, golden-file-friendly output.
  -> .diff_scaled(before_text, after_text, normalize)
    b = self.parse_folded(before_text)
    a = self.parse_folded(after_text)
    bmap = b[:map]
    amap = a[:map]
    atotal = a[:total]
    btotal = b[:total]
    stacks = self.union_keys(amap, bmap)
    sorted = self.sort_strings(stacks)
    out = []
    i = 0
    while i < sorted.size()
      stack = sorted[i]
      after_c = (amap.has_key?(stack) ? amap[stack] : 0)
      before_c = (bmap.has_key?(stack) ? bmap[stack] : 0)
      if normalize
        before_c = self.scale(before_c, atotal, btotal)
      delta = after_c - before_c
      out.push(stack + " " + delta.to_s())
      i = i + 1
    out.join("\n")

  # ---- Frame ranking ----

  # Rank frames by how much their inclusive count changed. When `normalize`
  # is true, before counts are scaled to after's sample total first. Returns
  # a list of [frame, before_count, after_count, delta] sorted by |delta|
  # descending, ties broken by frame name ascending (deterministic).
  -> .rank_frames(before_text, after_text, normalize)
    b = self.parse_folded(before_text)
    a = self.parse_folded(after_text)
    atotal = a[:total]
    btotal = b[:total]
    bi = self.inclusive_from_map(b[:map])
    ai = self.inclusive_from_map(a[:map])
    frames = self.union_keys(ai, bi)
    rows = []
    i = 0
    while i < frames.size()
      f = frames[i]
      before_c = (bi.has_key?(f) ? bi[f] : 0)
      if normalize
        before_c = self.scale(before_c, atotal, btotal)
      after_c = (ai.has_key?(f) ? ai[f] : 0)
      delta = after_c - before_c
      rows.push([f, before_c, after_c, delta])
      i = i + 1
    self.sort_by_abs_delta(rows)

  # ---- Report ----

  # Printable differential summary — top `top_n` regressions (hotter) and
  # top `top_n` improvements (cooler), each with a signed percent (of the
  # after-total) and a signed count delta. Always normalized. Returns the
  # report as a string; the CLI prints it.
  -> .report(before_text, after_text, top_n, color)
    b = self.parse_folded(before_text)
    a = self.parse_folded(after_text)
    btotal = b[:total]
    atotal = a[:total]
    ranked = self.rank_frames(before_text, after_text, true)

    bold  = color ? "\e[1m" : ""
    dim   = color ? "\e[2m" : ""
    reset = color ? "\e[0m" : ""
    red   = color ? "\e[38;5;167m" : ""
    green = color ? "\e[38;5;107m" : ""

    out = []
    out.push("")
    out.push("  " + bold + "Differential Profile" + reset + "  " + dim + "(before " + btotal.to_s() + " → after " + atotal.to_s() + " samples, normalized)" + reset)
    out.push("")

    # Regressions: positive deltas, largest magnitude first (ranked is
    # already ordered by |delta| desc, so a filtered scan preserves it).
    out.push("  " + bold + "Regressed (hotter)" + reset)
    shown = 0
    i = 0
    while i < ranked.size() && shown < top_n
      row = ranked[i]
      if row[3] > 0
        out.push(self.fmt_row(row, atotal, "+", red, bold, reset))
        shown = shown + 1
      i = i + 1
    if shown == 0
      out.push("    " + dim + "(none)" + reset)

    out.push("")
    out.push("  " + bold + "Improved (cooler)" + reset)
    shown = 0
    i = 0
    while i < ranked.size() && shown < top_n
      row = ranked[i]
      if row[3] < 0
        out.push(self.fmt_row(row, atotal, "-", green, bold, reset))
        shown = shown + 1
      i = i + 1
    if shown == 0
      out.push("    " + dim + "(none)" + reset)

    out.push("")
    out.join("\n")

  -> .fmt_row(row, atotal, sign, col, bold, reset)
    frame = row[0]
    delta = row[3]
    mag = self.abs(delta)
    pct = self.fmt_pct(mag, atotal)
    "    " + bold + sign + pct + "%" + reset + "  " + col + sign + mag.to_s() + reset + "  " + frame

  # ---- Helpers ----

  # Scale `value` from `source_total` up/down to `target_total` (integer
  # math). A zero source total (empty before-profile) yields 0 — every
  # after-frame then reads as pure regression, and no division by zero.
  -> .scale(value, target_total, source_total)
    if source_total == 0
      return 0
    value * target_total / source_total

  -> .abs(n)
    if n < 0
      return 0 - n
    n

  # Percentage with one decimal via integer math (no BigDecimal notation).
  -> .fmt_pct(n, total)
    if total == 0
      return "0.0"
    pct_x10 = n * 1000 / total
    whole = pct_x10 / 10
    frac = pct_x10 - whole * 10
    whole.to_s() + "." + frac.to_s()

  # Ordered union of the keys of two maps (a's keys first, then b's keys not
  # already seen), preserving insertion order for stable downstream sorting.
  -> .union_keys(a, b)
    out = []
    seen = {}
    ak = a.keys()
    i = 0
    while i < ak.size()
      k = ak[i]
      if !seen.has_key?(k)
        seen[k] = true
        out.push(k)
      i = i + 1
    bk = b.keys()
    i = 0
    while i < bk.size()
      k = bk[i]
      if !seen.has_key?(k)
        seen[k] = true
        out.push(k)
      i = i + 1
    out

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

  # Insertion sort of [frame, before, after, delta] rows by |delta|
  # descending, ties broken by frame name ascending.
  -> .sort_by_abs_delta(rows)
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

  # True when row `x` should sort AFTER row `y`: smaller |delta|, or equal
  # |delta| with a later-sorting frame name.
  -> .ranks_after(x, y)
    ax = self.abs(x[3])
    ay = self.abs(y[3])
    if ax != ay
      return ax < ay
    x[0] > y[0]
