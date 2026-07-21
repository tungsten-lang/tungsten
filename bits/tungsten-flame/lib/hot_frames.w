# hot_frames.w — Self-vs-total "flat profile" of a folded stack profile.
#
# The interactive flame graph (flame_svg.w) shows inclusive time as a
# picture; the analyzer's "Top Functions" list ranks frames by SELF (leaf)
# time only. Neither answers the other canonical profiler question — "which
# functions dominate INCLUSIVE (total) time, and how much of that is their
# own self time?" — the flat profile every serious tool prints (perf report,
# pprof `top`, Instruments' heaviest-stack view).
#
# This module is that missing text view. Given the same "root;mid;leaf
# <count>" folded text every other module in this bit speaks, it computes,
# per frame:
#   - self  = counts where the frame is the leaf of a stack (its own work)
#   - total = inclusive counts (every sample whose stack contains the
#             frame; recursion within one stack is counted once)
# and ranks by total descending — surfacing hot-path dominators (dispatch
# glue, hot callers) that have little self time and are invisible in a
# self-only Top Functions list, while still showing self alongside.
#
# Pure text→analysis (no profiling, no atos, no SVG): fully unit-testable,
# and complementary to flame_svg (picture), flame_diff (two-profile delta),
# and speedscope (export) — a fourth, single-profile analytical view of the
# same folded data.
#
# Frame names are normalized the same way the analyzer's Top Functions are
# (strip a trailing " + <decimal offset>" and any "lib`" backtick prefix) so
# unresolved/decorated variants of one symbol merge into a single row.
#
# CLI: `flame --hot FILE.folded [MORE.folded ...]` — a pure-text mode (like
# --diff). Multiple files aggregate for free: concatenated folded text sums
# duplicate stacks in .parse_folded, so N runs combine into one report.

in Tungsten:Flame

+ HotFrames

  # ---- Parsing ----

  # Parse folded text into { map: { stack => count }, total: N }. Duplicate
  # stacks are summed (this is what lets concatenated files aggregate across
  # runs); lines with no positive count are ignored — matching
  # FlameDiff.parse_folded / Speedscope.dedupe_counts so every module agrees
  # on what a sample is. The trailing count is split with rindex(" "), so
  # frame names containing spaces (e.g. "block in Array#tally") survive.
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

  # ---- Per-frame counts ----

  # Self (leaf-only) counts from a { stack => count } map: a frame collects a
  # stack's count only when it is that stack's LEAF. Returns
  # { frame => self_count }. Frame names are normalized before tallying so
  # decorated variants merge.
  -> .self_from_map(map)
    selfc = {}
    keys = map.keys()
    i = 0
    while i < keys.size()
      stack = keys[i]
      count = map[stack]
      frames = stack.split(";")
      leaf = self.normalize_frame(frames.last())
      if selfc.has_key?(leaf)
        selfc[leaf] = selfc[leaf] + count
      else
        selfc[leaf] = count
      i = i + 1
    selfc

  # Inclusive (total) counts from a { stack => count } map: every distinct
  # frame in a stack receives that stack's count, but a frame that recurses
  # within one stack is counted only once (inclusive time is per-sample, not
  # per-appearance). Returns { frame => inclusive_count }, names normalized.
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
        f = self.normalize_frame(frames[fi])
        if !seen.has_key?(f)
          seen[f] = true
          if incl.has_key?(f)
            incl[f] = incl[f] + count
          else
            incl[f] = count
        fi = fi + 1
      i = i + 1
    incl

  # ---- Ranking ----

  # Rank frames by inclusive (total) count. Returns a list of
  # [frame, self_count, total_count] sorted by total descending, ties broken
  # by self descending, then by frame name ascending (deterministic,
  # golden-file-friendly). Every frame appears (inclusive counts cover them
  # all); self is 0 for frames that are never a leaf.
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
    self.sort_rows(rows)

  # ---- Report ----

  # Printable flat profile — the top `top_n` frames by inclusive time, each
  # with its total% and self% (of the grand sample total). Returns the report
  # as a string; the CLI prints it. Empty / count-less input yields a
  # "(no samples)" line rather than crashing.
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

  # Normalize a frame name the way the analyzer's Top Functions do: strip a
  # trailing " + <decimal offset>" (a raw address offset, not part of the
  # symbol) and any "lib`" backtick prefix (dyld/atos decoration). Leaves a
  # plain symbol untouched, so decorated and undecorated appearances of one
  # function merge into a single row.
  -> .normalize_frame(name)
    frame = name
    plus_idx = frame.rindex(" + ")
    if plus_idx
      rest = frame.slice(plus_idx + 3, frame.size())
      if rest.size() > 0 && rest.to_i().to_s() == rest
        frame = frame.slice(0, plus_idx)
    backtick = frame.rindex("`")
    if backtick
      frame = frame.slice(backtick + 1, frame.size())
    frame

  # Percentage with one decimal via integer math (avoids BigDecimal sci
  # notation), left-padded to a 5-char field for column alignment.
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

  # Insertion sort of [frame, self, total] rows: total desc, then self desc,
  # then frame name asc.
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

  # True when row `x` should sort AFTER row `y`: smaller total, or equal total
  # with smaller self, or equal total and self with a later-sorting name.
  -> .ranks_after(x, y)
    if x[2] != y[2]
      return x[2] < y[2]
    if x[1] != y[1]
      return x[1] < y[1]
    x[0] > y[0]
