# flame_diff.w — Differential profiling: compare two folded profiles.

use folded

in Tungsten:Flame

+ FlameDiff

  # ---- Parsing ----

  -> .parse_folded(text)
    Tungsten:Flame:Folded.parse(text)

  -> .inclusive_from_map(map)
    Tungsten:Flame:Folded.inclusive_from_map(map, false)

  -> .frame_inclusive(text)
    parsed = self.parse_folded(text)
    self.inclusive_from_map(parsed[:map])

  # ---- Per-stack diff ----

  -> .diff(before_text, after_text)
    self.diff_scaled(before_text, after_text, false)

  -> .diff_normalized(before_text, after_text)
    self.diff_scaled(before_text, after_text, true)

  -> .diff_scaled(before_text, after_text, normalize)
    b = self.parse_folded(before_text)
    a = self.parse_folded(after_text)
    bmap = b[:map]
    amap = a[:map]
    atotal = a[:total]
    btotal = b[:total]
    sorted = (amap.keys() + bmap.keys()).uniq().sort()
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

  # Rank frames by how much their inclusive count changed. Returns a list of
  # [frame, before_count, after_count, delta] sorted by |delta| descending,
  # ties broken by frame name ascending.
  -> .rank_frames(before_text, after_text, normalize)
    b = self.parse_folded(before_text)
    a = self.parse_folded(after_text)
    atotal = a[:total]
    btotal = b[:total]
    bi = self.inclusive_from_map(b[:map])
    ai = self.inclusive_from_map(a[:map])
    frames = (ai.keys() + bi.keys()).uniq()
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
    rows.sort_by -> (r) [-self.abs(r[3]), r[0]]

  # ---- Report ----

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

  -> .scale(value, target_total, source_total)
    if source_total == 0
      return 0
    value * target_total / source_total

  -> .abs(n)
    if n < 0
      return 0 - n
    n

  -> .fmt_pct(n, total)
    Tungsten:Flame:Folded.fmt_pct(n, total)
