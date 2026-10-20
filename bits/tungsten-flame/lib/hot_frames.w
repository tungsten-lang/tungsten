# hot_frames.w — Self-vs-total "flat profile" of a folded stack profile.

use folded

in Tungsten:Flame

+ HotFrames

  # ---- Parsing & Per-frame counts ----

  -> .parse_folded(text)
    Tungsten:Flame:Folded.parse(text)

  -> .self_from_map(map)
    Tungsten:Flame:Folded.self_from_map(map, true)

  -> .inclusive_from_map(map)
    Tungsten:Flame:Folded.inclusive_from_map(map, true)

  # ---- Ranking ----

  # Rank frames by inclusive (total) count: [frame, self_count, total_count]
  # sorted by total descending, ties broken by self descending, then by frame
  # name ascending.
  -> .rank(text)
    parsed = self.parse_folded(text)
    map = parsed[:map]
    selfc = self.self_from_map(map)
    incl = self.inclusive_from_map(map)
    frames = incl.keys()
    rows = []
    i = 0
    while i < frames.size()
      f = frames[i]
      s = (selfc.has_key?(f) ? selfc[f] : 0)
      t = incl[f]
      rows.push([f, s, t])
      i = i + 1
    rows.sort_by -> (r) [-r[2], -r[1], r[0]]

  # ---- Report ----

  -> .report(text, top_n, color)
    parsed = self.parse_folded(text)
    total = parsed[:total]

    bold  = color ? "\e[1m" : ""
    dim   = color ? "\e[2m" : ""
    reset = color ? "\e[0m" : ""
    fn_color = color ? "\e[38;5;67m" : ""

    out = []
    out.push("")
    if total == 0
      out.push("  " + bold + "Hot Frames" + reset + "  " + dim + "(no samples)" + reset)
      out.push("")
      return out.join("\n")

    out.push("  " + bold + "Hot Frames" + reset + "  " + dim + "(" + total.to_s() + " samples, self vs total)" + reset)
    out.push("")
    out.push("  " + bold + "  TOTAL    SELF  FUNCTION" + reset)

    rows = self.rank(text)
    limit = top_n
    if limit > rows.size()
      limit = rows.size()
    i = 0
    while i < limit
      row = rows[i]
      frame = row[0]
      sp = self.fmt_pct(row[1], total)
      tp = self.fmt_pct(row[2], total)
      out.push("  " + bold + tp + "%" + reset + "  " + sp + "%  " + fn_color + frame + reset)
      i = i + 1

    out.push("")
    out.join("\n")

  # ---- Helpers ----

  -> .normalize_frame(name)
    Tungsten:Flame:Folded.normalize_frame(name)

  -> .fmt_pct(n, total)
    Tungsten:Flame:Folded.fmt_pct_padded(n, total)
